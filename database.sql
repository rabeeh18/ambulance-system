-- ============================================================
-- EMERGENCY AMBULANCE ALLOCATION SYSTEM — DATABASE SETUP
-- ============================================================
-- Run this entire file in MySQL as root or admin user.
-- It creates the database, all tables, functions, procedures,
-- triggers, views, and seeds sample data.
-- ============================================================

CREATE DATABASE IF NOT EXISTS ambulance_system;
USE ambulance_system;

-- ============================================================
-- DROP EXISTING OBJECTS (for clean re-runs)
-- ============================================================
DROP TRIGGER IF EXISTS after_assignment_update;
DROP TRIGGER IF EXISTS after_assignment_insert;
DROP TRIGGER IF EXISTS before_assignment_insert;
DROP VIEW IF EXISTS hospital_capacity;
DROP VIEW IF EXISTS active_assignments;
DROP VIEW IF EXISTS available_ambulances;
DROP PROCEDURE IF EXISTS allocate_ambulance;
DROP FUNCTION IF EXISTS calculate_distance;
DROP TABLE IF EXISTS Assignment;
DROP TABLE IF EXISTS Emergency_Request;
DROP TABLE IF EXISTS Ambulance;
DROP TABLE IF EXISTS Hospital;
DROP TABLE IF EXISTS Driver;

-- ============================================================
-- TABLES
-- ============================================================

CREATE TABLE Driver (
  driver_id        INT PRIMARY KEY AUTO_INCREMENT,
  name             VARCHAR(100) NOT NULL,
  phone            VARCHAR(15) UNIQUE NOT NULL,
  license_number   VARCHAR(50) UNIQUE NOT NULL,
  experience_years INT,
  status           VARCHAR(20) DEFAULT 'ACTIVE'
);

CREATE TABLE Ambulance (
  ambulance_id       INT PRIMARY KEY AUTO_INCREMENT,
  vehicle_number     VARCHAR(20) UNIQUE NOT NULL,
  driver_id          INT,
  status             ENUM('AVAILABLE','BUSY') NOT NULL DEFAULT 'AVAILABLE',
  current_latitude   DOUBLE,
  current_longitude  DOUBLE,
  FOREIGN KEY (driver_id) REFERENCES Driver(driver_id)
);

CREATE TABLE Hospital (
  hospital_id    INT PRIMARY KEY AUTO_INCREMENT,
  name           VARCHAR(150) NOT NULL,
  address        TEXT,
  contact_number VARCHAR(15),
  total_beds     INT NOT NULL,
  available_beds INT NOT NULL CHECK (available_beds >= 0)
);

CREATE TABLE Emergency_Request (
  request_id         INT PRIMARY KEY AUTO_INCREMENT,
  caller_name        VARCHAR(100),
  caller_phone       VARCHAR(15),
  request_time       DATETIME DEFAULT CURRENT_TIMESTAMP,
  emergency_type     VARCHAR(100),
  location_latitude  DOUBLE,
  location_longitude DOUBLE,
  priority           ENUM('Critical','High','Low') NOT NULL,
  status             ENUM('PENDING','ASSIGNED','COMPLETED') NOT NULL DEFAULT 'PENDING'
);

CREATE TABLE Assignment (
  assignment_id   INT PRIMARY KEY AUTO_INCREMENT,
  request_id      INT UNIQUE NOT NULL,
  ambulance_id    INT NOT NULL,
  hospital_id     INT NOT NULL,
  assigned_time   DATETIME DEFAULT CURRENT_TIMESTAMP,
  completion_time DATETIME,
  FOREIGN KEY (request_id)   REFERENCES Emergency_Request(request_id),
  FOREIGN KEY (ambulance_id) REFERENCES Ambulance(ambulance_id),
  FOREIGN KEY (hospital_id)  REFERENCES Hospital(hospital_id)
);

-- ============================================================
-- DISTANCE FUNCTION (Haversine formula — returns km)
-- ============================================================
DELIMITER $$
CREATE FUNCTION calculate_distance(
  lat1 DOUBLE, lon1 DOUBLE,
  lat2 DOUBLE, lon2 DOUBLE
)
RETURNS DOUBLE
DETERMINISTIC
BEGIN
  RETURN 6371 * ACOS(
    GREATEST(-1, LEAST(1,
      COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
      COS(RADIANS(lon2) - RADIANS(lon1)) +
      SIN(RADIANS(lat1)) * SIN(RADIANS(lat2))
    ))
  );
END$$
DELIMITER ;

-- ============================================================
-- STORED PROCEDURE — allocate_ambulance
-- ============================================================
DELIMITER $$
CREATE PROCEDURE allocate_ambulance(IN p_request_id INT)
BEGIN
  DECLARE v_ambulance_id INT DEFAULT NULL;
  DECLARE v_hospital_id  INT DEFAULT NULL;
  DECLARE v_req_lat      DOUBLE;
  DECLARE v_req_lon      DOUBLE;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
  END;

  START TRANSACTION;

  -- Get request coordinates
  SELECT location_latitude, location_longitude
  INTO v_req_lat, v_req_lon
  FROM Emergency_Request
  WHERE request_id = p_request_id;

  -- Find nearest AVAILABLE ambulance and lock the row
  SELECT ambulance_id INTO v_ambulance_id
  FROM Ambulance
  WHERE status = 'AVAILABLE'
  ORDER BY calculate_distance(current_latitude, current_longitude, v_req_lat, v_req_lon)
  LIMIT 1
  FOR UPDATE;

  -- Find hospital with available beds and lock the row
  SELECT hospital_id INTO v_hospital_id
  FROM Hospital
  WHERE available_beds > 0
  LIMIT 1
  FOR UPDATE;

  -- If either resource is missing, leave as PENDING and exit
  IF v_ambulance_id IS NULL OR v_hospital_id IS NULL THEN
    ROLLBACK;
  ELSE
    -- Create assignment record
    INSERT INTO Assignment (request_id, ambulance_id, hospital_id)
    VALUES (p_request_id, v_ambulance_id, v_hospital_id);

    -- Mark ambulance as BUSY
    UPDATE Ambulance SET status = 'BUSY' WHERE ambulance_id = v_ambulance_id;

    -- Decrement hospital bed count
    UPDATE Hospital SET available_beds = available_beds - 1 WHERE hospital_id = v_hospital_id;

    -- Mark request as ASSIGNED
    UPDATE Emergency_Request SET status = 'ASSIGNED' WHERE request_id = p_request_id;

    COMMIT;
  END IF;
END$$
DELIMITER ;

-- ============================================================
-- TRIGGERS
-- ============================================================

-- BEFORE INSERT on Assignment — guard against zero beds
DELIMITER $$
CREATE TRIGGER before_assignment_insert
BEFORE INSERT ON Assignment
FOR EACH ROW
BEGIN
  DECLARE bed_count INT;
  SELECT available_beds INTO bed_count FROM Hospital WHERE hospital_id = NEW.hospital_id;
  IF bed_count <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No available beds in selected hospital';
  END IF;
END$$
DELIMITER ;

-- AFTER INSERT on Assignment — safety net (procedure already does these)
DELIMITER $$
CREATE TRIGGER after_assignment_insert
AFTER INSERT ON Assignment
FOR EACH ROW
BEGIN
  -- These are already done in the procedure; triggers act as safety net
  -- for direct inserts outside the procedure.
  -- Commented out to avoid double-updates when procedure is used:
  -- UPDATE Ambulance SET status = 'BUSY' WHERE ambulance_id = NEW.ambulance_id;
  -- UPDATE Hospital SET available_beds = available_beds - 1 WHERE hospital_id = NEW.hospital_id;
  SET @dummy = 0; -- placeholder to keep trigger valid
END$$
DELIMITER ;

-- AFTER UPDATE on Assignment — completion handler
DELIMITER $$
CREATE TRIGGER after_assignment_update
AFTER UPDATE ON Assignment
FOR EACH ROW
BEGIN
  IF NEW.completion_time IS NOT NULL AND OLD.completion_time IS NULL THEN
    UPDATE Ambulance SET status = 'AVAILABLE' WHERE ambulance_id = NEW.ambulance_id;
    UPDATE Emergency_Request SET status = 'COMPLETED' WHERE request_id = NEW.request_id;
  END IF;
END$$
DELIMITER ;

-- ============================================================
-- VIEWS
-- ============================================================

CREATE VIEW available_ambulances AS
SELECT a.ambulance_id, a.vehicle_number, d.name AS driver_name,
       a.current_latitude, a.current_longitude
FROM Ambulance a
JOIN Driver d ON a.driver_id = d.driver_id
WHERE a.status = 'AVAILABLE';

CREATE VIEW active_assignments AS
SELECT a.assignment_id, er.emergency_type, er.priority,
       am.vehicle_number, d.name AS driver_name,
       h.name AS hospital_name, a.assigned_time
FROM Assignment a
JOIN Emergency_Request er ON a.request_id = er.request_id
JOIN Ambulance am ON a.ambulance_id = am.ambulance_id
JOIN Driver d ON am.driver_id = d.driver_id
JOIN Hospital h ON a.hospital_id = h.hospital_id
WHERE a.completion_time IS NULL;

CREATE VIEW hospital_capacity AS
SELECT hospital_id, name,
       total_beds, available_beds,
       ROUND((available_beds / total_beds) * 100, 1) AS availability_percent
FROM Hospital;

-- ============================================================
-- SEED DATA
-- ============================================================

INSERT INTO Driver (name, phone, license_number, experience_years, status) VALUES
('Rajesh Kumar',    '9876543210', 'PB-DL-001', 8,  'ACTIVE'),
('Suresh Singh',    '9876543211', 'PB-DL-002', 5,  'ACTIVE'),
('Amandeep Gill',   '9876543212', 'PB-DL-003', 12, 'ACTIVE'),
('Harpreet Kaur',   '9876543213', 'PB-DL-004', 3,  'ACTIVE'),
('Vikram Sharma',   '9876543214', 'PB-DL-005', 7,  'ACTIVE'),
('Mandeep Verma',   '9876543215', 'PB-DL-006', 6,  'ACTIVE'),
('Gurpreet Singh',  '9876543216', 'PB-DL-007', 9,  'ACTIVE'),
('Deepak Chaudhary','9876543217', 'PB-DL-008', 4,  'ACTIVE');

INSERT INTO Hospital (name, address, contact_number, total_beds, available_beds) VALUES
('PGIMER Chandigarh',    'Sector 12, Chandigarh, Punjab 160012',    '0172-2756565', 60, 18),
('Rajindra Hospital',    'Patna, Patiala, Punjab 147001',           '0175-2212045', 60,  2),
('Fortis Mohali',        'Phase 8, Sector 62, Mohali, Punjab 160062','0172-6920000', 50, 31),
('Max Super Specialty',  'Phase 6, Mohali, Punjab 160055',          '0172-3988000', 45,  8);

INSERT INTO Ambulance (vehicle_number, driver_id, status, current_latitude, current_longitude) VALUES
('AMB-001', 1, 'AVAILABLE', 30.7333, 76.7794),
('AMB-002', 2, 'BUSY',      30.9010, 75.8573),
('AMB-003', 3, 'AVAILABLE', 30.3398, 76.3869),
('AMB-004', 4, 'BUSY',      30.7333, 76.7794),
('AMB-005', 5, 'AVAILABLE', 30.6942, 76.8606),
('AMB-006', 6, 'AVAILABLE', 30.9010, 75.8573),
('AMB-007', 7, 'AVAILABLE', 30.2968, 74.9662),
('AMB-008', 8, 'BUSY',      30.5318, 74.3290);

INSERT INTO Emergency_Request (caller_name, caller_phone, request_time, emergency_type, location_latitude, location_longitude, priority, status) VALUES
('Priya Sharma',   '9811001001', NOW() - INTERVAL 2  MINUTE, 'Cardiac arrest',       30.7333, 76.7794, 'Critical', 'ASSIGNED'),
('Rahul Verma',    '9811001002', NOW() - INTERVAL 5  MINUTE, 'Road accident',        30.9010, 75.8573, 'High',     'PENDING'),
('Anita Kaur',     '9811001003', NOW() - INTERVAL 9  MINUTE, 'Breathing difficulty', 30.3398, 76.3869, 'High',     'PENDING'),
('Sunil Mehta',    '9811001004', NOW() - INTERVAL 14 MINUTE, 'Fall injury',          30.6942, 76.8606, 'Low',      'ASSIGNED'),
('Kavita Rani',    '9811001005', NOW() - INTERVAL 30 MINUTE, 'Cardiac arrest',       30.9010, 75.8573, 'Critical', 'COMPLETED'),
('Deepak Nair',    '9811001006', NOW() - INTERVAL 45 MINUTE, 'Road accident',        30.2968, 74.9662, 'High',     'COMPLETED'),
('Mohan Das',      '9811001007', NOW() - INTERVAL 60 MINUTE, 'Fall injury',          30.5318, 74.3290, 'Low',      'COMPLETED');

-- Assignments for ASSIGNED requests
INSERT INTO Assignment (request_id, ambulance_id, hospital_id, assigned_time) VALUES
(1, 2, 1, NOW() - INTERVAL 2  MINUTE),
(4, 4, 3, NOW() - INTERVAL 14 MINUTE);

-- Completed assignments
INSERT INTO Assignment (request_id, ambulance_id, hospital_id, assigned_time, completion_time) VALUES
(5, 8, 2, NOW() - INTERVAL 45 MINUTE, NOW() - INTERVAL 15 MINUTE),
(6, 8, 4, NOW() - INTERVAL 60 MINUTE, NOW() - INTERVAL 20 MINUTE),
(7, 8, 1, NOW() - INTERVAL 70 MINUTE, NOW() - INTERVAL 30 MINUTE);

SELECT 'Database setup complete!' AS message;
