-- ============================================================
-- EMERGENCY AMBULANCE ALLOCATION SYSTEM — DATABASE SETUP
-- ============================================================
CREATE DATABASE IF NOT EXISTS ambulance_system;
USE ambulance_system;

-- ============================================================
-- DROP EXISTING OBJECTS
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
-- DISTANCE FUNCTION
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
-- STORED PROCEDURE
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

  SELECT location_latitude, location_longitude
  INTO v_req_lat, v_req_lon
  FROM Emergency_Request
  WHERE request_id = p_request_id;

  SELECT ambulance_id INTO v_ambulance_id
  FROM Ambulance
  WHERE status = 'AVAILABLE'
  ORDER BY calculate_distance(current_latitude, current_longitude, v_req_lat, v_req_lon)
  LIMIT 1
  FOR UPDATE;

  SELECT hospital_id INTO v_hospital_id
  FROM Hospital
  WHERE available_beds > 0
  LIMIT 1
  FOR UPDATE;

  IF v_ambulance_id IS NULL OR v_hospital_id IS NULL THEN
    ROLLBACK;
  ELSE
    INSERT INTO Assignment (request_id, ambulance_id, hospital_id)
    VALUES (p_request_id, v_ambulance_id, v_hospital_id);

    UPDATE Ambulance SET status = 'BUSY' WHERE ambulance_id = v_ambulance_id;
    UPDATE Hospital SET available_beds = available_beds - 1 WHERE hospital_id = v_hospital_id;
    UPDATE Emergency_Request SET status = 'ASSIGNED' WHERE request_id = p_request_id;

    COMMIT;
  END IF;
END$$
DELIMITER ;

-- ============================================================
-- TRIGGERS
-- ============================================================
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

DELIMITER $$
CREATE TRIGGER after_assignment_insert
AFTER INSERT ON Assignment
FOR EACH ROW
BEGIN
  SET @dummy = 0;
END$$
DELIMITER ;

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

-- 20 Drivers
INSERT INTO Driver (name, phone, license_number, experience_years, status) VALUES
('Rajesh Kumar',     '9876543210', 'PB-DL-001', 8,  'ACTIVE'),
('Suresh Singh',     '9876543211', 'PB-DL-002', 5,  'ACTIVE'),
('Amandeep Gill',    '9876543212', 'PB-DL-003', 12, 'ACTIVE'),
('Harpreet Kaur',    '9876543213', 'PB-DL-004', 3,  'ACTIVE'),
('Vikram Sharma',    '9876543214', 'PB-DL-005', 7,  'ACTIVE'),
('Mandeep Verma',    '9876543215', 'PB-DL-006', 6,  'ACTIVE'),
('Gurpreet Singh',   '9876543216', 'PB-DL-007', 9,  'ACTIVE'),
('Deepak Chaudhary', '9876543217', 'PB-DL-008', 4,  'ACTIVE'),
('Arjun Patel',      '9900001001', 'PB-DL-009', 6,  'ACTIVE'),
('Ravi Shankar',     '9900001002', 'PB-DL-010', 11, 'ACTIVE'),
('Neeraj Yadav',     '9900001003', 'PB-DL-011', 4,  'ACTIVE'),
('Sandeep Bhatia',   '9900001004', 'PB-DL-012', 9,  'ACTIVE'),
('Kulwinder Toor',   '9900001005', 'PB-DL-013', 2,  'ACTIVE'),
('Balveer Randhawa', '9900001006', 'PB-DL-014', 14, 'ACTIVE'),
('Jagdeep Sohal',    '9900001007', 'PB-DL-015', 7,  'ACTIVE'),
('Pritam Dhaliwal',  '9900001008', 'PB-DL-016', 5,  'ACTIVE'),
('Onkar Sidhu',      '9900001009', 'PB-DL-017', 10, 'ACTIVE'),
('Harmeet Brar',     '9900001010', 'PB-DL-018', 3,  'ACTIVE'),
('Lakhwinder Mann',  '9900001011', 'PB-DL-019', 8,  'ACTIVE'),
('Dalbir Cheema',    '9900001012', 'PB-DL-020', 6,  'ACTIVE');

-- 8 Hospitals (with plenty of beds so inserts don't get blocked by trigger)
INSERT INTO Hospital (name, address, contact_number, total_beds, available_beds) VALUES
('PGIMER Chandigarh',        'Sector 12, Chandigarh, Punjab 160012',         '0172-2756565', 60, 28),
('Rajindra Hospital',        'Patna, Patiala, Punjab 147001',                '0175-2212045', 60, 12),
('Fortis Mohali',            'Phase 8, Sector 62, Mohali, Punjab 160062',    '0172-6920000', 50, 21),
('Max Super Specialty',      'Phase 6, Mohali, Punjab 160055',               '0172-3988000', 45, 15),
('Apollo Hospitals Ludhiana','Model Town, Ludhiana, Punjab 141002',          '0161-4675000', 70, 19),
('Civil Hospital Amritsar',  'Circular Road, Amritsar, Punjab 143001',       '0183-2564000', 55, 17),
('DMC & Hospital Ludhiana',  'Tagore Nagar, Ludhiana, Punjab 141001',        '0161-2301023', 80, 24),
('Ivy Hospital Mohali',      'Sector 71, SAS Nagar, Mohali, Punjab 160071',  '0172-7172700', 40, 10);

-- 20 Ambulances (mix of AVAILABLE and BUSY)
INSERT INTO Ambulance (vehicle_number, driver_id, status, current_latitude, current_longitude) VALUES
('AMB-001', 1,  'AVAILABLE', 30.7333, 76.7794),
('AMB-002', 2,  'BUSY',      30.9010, 75.8573),
('AMB-003', 3,  'AVAILABLE', 30.3398, 76.3869),
('AMB-004', 4,  'BUSY',      30.7333, 76.7794),
('AMB-005', 5,  'AVAILABLE', 30.6942, 76.8606),
('AMB-006', 6,  'AVAILABLE', 30.9010, 75.8573),
('AMB-007', 7,  'AVAILABLE', 30.2968, 74.9662),
('AMB-008', 8,  'BUSY',      30.5318, 74.3290),
('AMB-009', 9,  'AVAILABLE', 31.6340, 74.8723),
('AMB-010', 10, 'BUSY',      30.7333, 76.7794),
('AMB-011', 11, 'AVAILABLE', 31.7280, 75.5762),
('AMB-012', 12, 'BUSY',      30.9010, 75.8573),
('AMB-013', 13, 'AVAILABLE', 30.4500, 76.5200),
('AMB-014', 14, 'BUSY',      31.6340, 74.8723),
('AMB-015', 15, 'AVAILABLE', 30.8000, 75.9500),
('AMB-016', 16, 'AVAILABLE', 30.6200, 76.1000),
('AMB-017', 17, 'BUSY',      30.3398, 76.3869),
('AMB-018', 18, 'AVAILABLE', 31.5200, 74.7800),
('AMB-019', 19, 'AVAILABLE', 30.7100, 76.6800),
('AMB-020', 20, 'BUSY',      30.9500, 75.7300);

-- 55 Emergency Requests
INSERT INTO Emergency_Request (caller_name, caller_phone, request_time, emergency_type, location_latitude, location_longitude, priority, status) VALUES
-- ASSIGNED (10)
('Priya Sharma',    '9811001001', NOW() - INTERVAL 2  MINUTE, 'Cardiac arrest',       30.7333, 76.7794, 'Critical', 'ASSIGNED'),
('Sunil Mehta',     '9811001004', NOW() - INTERVAL 5  MINUTE, 'Fall injury',          30.6942, 76.8606, 'Low',      'ASSIGNED'),
('Simran Bajwa',    '9811003003', NOW() - INTERVAL 7  MINUTE, 'Stroke',               30.9010, 75.8573, 'Critical', 'ASSIGNED'),
('Rohit Khanna',    '9811003004', NOW() - INTERVAL 10 MINUTE, 'Seizure',              30.3398, 76.3869, 'High',     'ASSIGNED'),
('Divya Malhotra',  '9811003005', NOW() - INTERVAL 13 MINUTE, 'Burn injury',          30.6942, 76.8606, 'High',     'ASSIGNED'),
('Tejinder Walia',  '9811003006', NOW() - INTERVAL 16 MINUTE, 'Childbirth emergency', 31.7280, 75.5762, 'Critical', 'ASSIGNED'),
('Arvind Bose',     '9811004001', NOW() - INTERVAL 19 MINUTE, 'Road accident',        31.6340, 74.8723, 'High',     'ASSIGNED'),
('Neelam Chopra',   '9811004002', NOW() - INTERVAL 22 MINUTE, 'Poisoning',            30.8000, 75.9500, 'Critical', 'ASSIGNED'),
('Bikram Sandhu',   '9811004003', NOW() - INTERVAL 25 MINUTE, 'Cardiac arrest',       30.4500, 76.5200, 'Critical', 'ASSIGNED'),
('Gurleen Kaur',    '9811004004', NOW() - INTERVAL 28 MINUTE, 'Breathing difficulty', 30.7100, 76.6800, 'High',     'ASSIGNED'),
-- PENDING (10)
('Rahul Verma',     '9811001002', NOW() - INTERVAL 1  MINUTE, 'Road accident',        30.9010, 75.8573, 'High',     'PENDING'),
('Anita Kaur',      '9811001003', NOW() - INTERVAL 3  MINUTE, 'Breathing difficulty', 30.3398, 76.3869, 'High',     'PENDING'),
('Amit Joshi',      '9811002001', NOW() - INTERVAL 4  MINUTE, 'Cardiac arrest',       31.6340, 74.8723, 'Critical', 'PENDING'),
('Pooja Sharma',    '9811003008', NOW() - INTERVAL 6  MINUTE, 'Burn injury',          30.3398, 76.3869, 'High',     'PENDING'),
('Navneet Grewal',  '9811003007', NOW() - INTERVAL 8  MINUTE, 'Poisoning',            30.7333, 76.7794, 'High',     'PENDING'),
('Harish Nanda',    '9811005001', NOW() - INTERVAL 9  MINUTE, 'Road accident',        31.6340, 74.8723, 'High',     'PENDING'),
('Ranjit Boparai',  '9811005002', NOW() - INTERVAL 11 MINUTE, 'Seizure',              30.6200, 76.1000, 'Critical', 'PENDING'),
('Manpreet Dhatt',  '9811005003', NOW() - INTERVAL 12 MINUTE, 'Fall injury',          31.5200, 74.7800, 'Low',      'PENDING'),
('Sunita Arora',    '9811005004', NOW() - INTERVAL 14 MINUTE, 'Stroke',               30.9500, 75.7300, 'Critical', 'PENDING'),
('Taranjit Sran',   '9811005005', NOW() - INTERVAL 15 MINUTE, 'Cardiac arrest',       30.8000, 75.9500, 'Critical', 'PENDING'),
-- COMPLETED (35)
('Kavita Rani',     '9811001005', NOW() - INTERVAL 30  MINUTE, 'Cardiac arrest',       30.9010, 75.8573, 'Critical', 'COMPLETED'),
('Deepak Nair',     '9811001006', NOW() - INTERVAL 45  MINUTE, 'Road accident',        30.2968, 74.9662, 'High',     'COMPLETED'),
('Mohan Das',       '9811001007', NOW() - INTERVAL 60  MINUTE, 'Fall injury',          30.5318, 74.3290, 'Low',      'COMPLETED'),
('Jasleen Dhaliwal','9811003008', NOW() - INTERVAL 70  MINUTE, 'Fall injury',          30.5318, 74.3290, 'Low',      'COMPLETED'),
('Pardeep Sandhu',  '9811003009', NOW() - INTERVAL 80  MINUTE, 'Road accident',        30.2968, 74.9662, 'High',     'COMPLETED'),
('Manpreet Gill',   '9811003010', NOW() - INTERVAL 90  MINUTE, 'Cardiac arrest',       30.9010, 75.8573, 'Critical', 'COMPLETED'),
('Arvind Thapar',   '9811003011', NOW() - INTERVAL 100 MINUTE, 'Fracture',             31.6340, 74.8723, 'Low',      'COMPLETED'),
('Sneha Chauhan',   '9811003012', NOW() - INTERVAL 110 MINUTE, 'Stroke',               30.6942, 76.8606, 'Critical', 'COMPLETED'),
('Tarun Gill',      '9811003013', NOW() - INTERVAL 120 MINUTE, 'Stroke',               31.6340, 74.8723, 'Critical', 'COMPLETED'),
('Mehak Arora',     '9811003014', NOW() - INTERVAL 130 MINUTE, 'Fracture',             30.6942, 76.8606, 'Low',      'COMPLETED'),
('Balvinder Singh', '9811003015', NOW() - INTERVAL 140 MINUTE, 'Poisoning',            30.2968, 74.9662, 'High',     'COMPLETED'),
('Reena Kapoor',    '9811003016', NOW() - INTERVAL 150 MINUTE, 'Childbirth emergency', 30.5318, 74.3290, 'Critical', 'COMPLETED'),
('Surjit Bains',    '9811006001', NOW() - INTERVAL 160 MINUTE, 'Cardiac arrest',       30.7333, 76.7794, 'Critical', 'COMPLETED'),
('Kamaljit Dhami',  '9811006002', NOW() - INTERVAL 170 MINUTE, 'Road accident',        30.9010, 75.8573, 'High',     'COMPLETED'),
('Parminder Kang',  '9811006003', NOW() - INTERVAL 180 MINUTE, 'Breathing difficulty', 31.6340, 74.8723, 'High',     'COMPLETED'),
('Harjit Uppal',    '9811006004', NOW() - INTERVAL 190 MINUTE, 'Seizure',              30.3398, 76.3869, 'Critical', 'COMPLETED'),
('Gurjant Ludhar',  '9811006005', NOW() - INTERVAL 200 MINUTE, 'Burn injury',          30.6942, 76.8606, 'High',     'COMPLETED'),
('Navdeep Bajwa',   '9811006006', NOW() - INTERVAL 210 MINUTE, 'Fracture',             30.8000, 75.9500, 'Low',      'COMPLETED'),
('Charanjit Sekhon','9811006007', NOW() - INTERVAL 220 MINUTE, 'Stroke',               31.5200, 74.7800, 'Critical', 'COMPLETED'),
('Manjit Grewal',   '9811006008', NOW() - INTERVAL 230 MINUTE, 'Cardiac arrest',       30.4500, 76.5200, 'Critical', 'COMPLETED'),
('Kulbir Dhillon',  '9811006009', NOW() - INTERVAL 240 MINUTE, 'Road accident',        30.7100, 76.6800, 'High',     'COMPLETED'),
('Satinder Pannu',  '9811006010', NOW() - INTERVAL 250 MINUTE, 'Fall injury',          30.9500, 75.7300, 'Low',      'COMPLETED'),
('Jasvir Aulakh',   '9811006011', NOW() - INTERVAL 260 MINUTE, 'Poisoning',            30.6200, 76.1000, 'High',     'COMPLETED'),
('Inderjit Gosal',  '9811006012', NOW() - INTERVAL 270 MINUTE, 'Childbirth emergency', 30.7333, 76.7794, 'Critical', 'COMPLETED'),
('Baljit Kahlon',   '9811006013', NOW() - INTERVAL 280 MINUTE, 'Cardiac arrest',       31.6340, 74.8723, 'Critical', 'COMPLETED'),
('Amrik Bhullar',   '9811006014', NOW() - INTERVAL 290 MINUTE, 'Breathing difficulty', 30.3398, 76.3869, 'High',     'COMPLETED'),
('Darshan Thind',   '9811006015', NOW() - INTERVAL 300 MINUTE, 'Road accident',        30.9010, 75.8573, 'High',     'COMPLETED'),
('Gurmail Nagra',   '9811006016', NOW() - INTERVAL 310 MINUTE, 'Seizure',              30.6942, 76.8606, 'Critical', 'COMPLETED'),
('Sukhwinder Bajaj','9811006017', NOW() - INTERVAL 320 MINUTE, 'Fracture',             30.2968, 74.9662, 'Low',      'COMPLETED'),
('Harnek Johal',    '9811006018', NOW() - INTERVAL 330 MINUTE, 'Stroke',               30.5318, 74.3290, 'Critical', 'COMPLETED'),
('Ranjodh Hayer',   '9811006019', NOW() - INTERVAL 340 MINUTE, 'Burn injury',          31.6340, 74.8723, 'High',     'COMPLETED'),
('Nirmal Sandhu',   '9811006020', NOW() - INTERVAL 350 MINUTE, 'Cardiac arrest',       30.7333, 76.7794, 'Critical', 'COMPLETED'),
('Tejpal Badal',    '9811006021', NOW() - INTERVAL 360 MINUTE, 'Fall injury',          30.4500, 76.5200, 'Low',      'COMPLETED'),
('Gurcharan Sidhu', '9811006022', NOW() - INTERVAL 370 MINUTE, 'Road accident',        30.9500, 75.7300, 'High',     'COMPLETED'),
('Paramjit Saini',  '9811006023', NOW() - INTERVAL 380 MINUTE, 'Childbirth emergency', 30.8000, 75.9500, 'Critical', 'COMPLETED');

-- Assignments for ASSIGNED requests (request_ids 1–10)
INSERT INTO Assignment (request_id, ambulance_id, hospital_id, assigned_time) VALUES
(1,  2,  1, NOW() - INTERVAL 2  MINUTE),
(2,  4,  3, NOW() - INTERVAL 5  MINUTE),
(3,  8,  5, NOW() - INTERVAL 7  MINUTE),
(4,  10, 2, NOW() - INTERVAL 10 MINUTE),
(5,  12, 4, NOW() - INTERVAL 13 MINUTE),
(6,  14, 6, NOW() - INTERVAL 16 MINUTE),
(7,  17, 7, NOW() - INTERVAL 19 MINUTE),
(8,  20, 1, NOW() - INTERVAL 22 MINUTE),
(9,  2,  8, NOW() - INTERVAL 25 MINUTE),
(10, 4,  3, NOW() - INTERVAL 28 MINUTE);

-- Completed assignments (request_ids 21–55)
INSERT INTO Assignment (request_id, ambulance_id, hospital_id, assigned_time, completion_time) VALUES
(21, 1,  2, NOW() - INTERVAL 35  MINUTE, NOW() - INTERVAL 10 MINUTE),
(22, 3,  4, NOW() - INTERVAL 50  MINUTE, NOW() - INTERVAL 18 MINUTE),
(23, 5,  1, NOW() - INTERVAL 65  MINUTE, NOW() - INTERVAL 25 MINUTE),
(24, 6,  6, NOW() - INTERVAL 75  MINUTE, NOW() - INTERVAL 32 MINUTE),
(25, 7,  3, NOW() - INTERVAL 85  MINUTE, NOW() - INTERVAL 40 MINUTE),
(26, 9,  5, NOW() - INTERVAL 95  MINUTE, NOW() - INTERVAL 48 MINUTE),
(27, 11, 7, NOW() - INTERVAL 105 MINUTE, NOW() - INTERVAL 55 MINUTE),
(28, 13, 8, NOW() - INTERVAL 115 MINUTE, NOW() - INTERVAL 62 MINUTE),
(29, 15, 2, NOW() - INTERVAL 125 MINUTE, NOW() - INTERVAL 70 MINUTE),
(30, 16, 4, NOW() - INTERVAL 135 MINUTE, NOW() - INTERVAL 78 MINUTE),
(31, 18, 1, NOW() - INTERVAL 145 MINUTE, NOW() - INTERVAL 85 MINUTE),
(32, 19, 6, NOW() - INTERVAL 155 MINUTE, NOW() - INTERVAL 92 MINUTE),
(33, 1,  3, NOW() - INTERVAL 165 MINUTE, NOW() - INTERVAL 100 MINUTE),
(34, 3,  5, NOW() - INTERVAL 175 MINUTE, NOW() - INTERVAL 108 MINUTE),
(35, 5,  7, NOW() - INTERVAL 185 MINUTE, NOW() - INTERVAL 115 MINUTE),
(36, 6,  8, NOW() - INTERVAL 195 MINUTE, NOW() - INTERVAL 122 MINUTE),
(37, 7,  2, NOW() - INTERVAL 205 MINUTE, NOW() - INTERVAL 130 MINUTE),
(38, 9,  4, NOW() - INTERVAL 215 MINUTE, NOW() - INTERVAL 138 MINUTE),
(39, 11, 1, NOW() - INTERVAL 225 MINUTE, NOW() - INTERVAL 145 MINUTE),
(40, 13, 6, NOW() - INTERVAL 235 MINUTE, NOW() - INTERVAL 152 MINUTE),
(41, 15, 3, NOW() - INTERVAL 245 MINUTE, NOW() - INTERVAL 160 MINUTE),
(42, 16, 5, NOW() - INTERVAL 255 MINUTE, NOW() - INTERVAL 168 MINUTE),
(43, 18, 7, NOW() - INTERVAL 265 MINUTE, NOW() - INTERVAL 175 MINUTE),
(44, 19, 8, NOW() - INTERVAL 275 MINUTE, NOW() - INTERVAL 182 MINUTE),
(45, 1,  2, NOW() - INTERVAL 285 MINUTE, NOW() - INTERVAL 190 MINUTE),
(46, 3,  4, NOW() - INTERVAL 295 MINUTE, NOW() - INTERVAL 198 MINUTE),
(47, 5,  1, NOW() - INTERVAL 305 MINUTE, NOW() - INTERVAL 205 MINUTE),
(48, 6,  6, NOW() - INTERVAL 315 MINUTE, NOW() - INTERVAL 212 MINUTE),
(49, 7,  3, NOW() - INTERVAL 325 MINUTE, NOW() - INTERVAL 220 MINUTE),
(50, 9,  5, NOW() - INTERVAL 335 MINUTE, NOW() - INTERVAL 228 MINUTE),
(51, 11, 7, NOW() - INTERVAL 345 MINUTE, NOW() - INTERVAL 235 MINUTE),
(52, 13, 8, NOW() - INTERVAL 355 MINUTE, NOW() - INTERVAL 242 MINUTE),
(53, 15, 2, NOW() - INTERVAL 365 MINUTE, NOW() - INTERVAL 250 MINUTE),
(54, 16, 4, NOW() - INTERVAL 375 MINUTE, NOW() - INTERVAL 258 MINUTE),
(55, 18, 1, NOW() - INTERVAL 385 MINUTE, NOW() - INTERVAL 265 MINUTE);

SELECT 'Database setup complete!' AS message;