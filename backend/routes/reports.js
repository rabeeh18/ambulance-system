// routes/reports.js
const express = require('express');
const router  = express.Router();
const db      = require('../db/connection');

// GET /api/reports/assignments-per-hospital
router.get('/assignments-per-hospital', async (req, res) => {
  try {
    const [rows] = await db.execute(`
      SELECT
        h.hospital_id,
        h.name,
        h.total_beds,
        h.available_beds,
        COUNT(a.assignment_id) AS total_assignments
      FROM Hospital h
      LEFT JOIN Assignment a ON h.hospital_id = a.hospital_id
      GROUP BY h.hospital_id, h.name, h.total_beds, h.available_beds
      ORDER BY total_assignments DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/reports/daily-summary — counts today
router.get('/daily-summary', async (req, res) => {
  try {
    const [[summary]] = await db.execute(`
      SELECT
        SUM(CASE WHEN status = 'PENDING'   AND DATE(request_time) = CURDATE() THEN 1 ELSE 0 END) AS pending,
        SUM(CASE WHEN status = 'ASSIGNED'  AND DATE(request_time) = CURDATE() THEN 1 ELSE 0 END) AS assigned,
        SUM(CASE WHEN status = 'COMPLETED' AND DATE(request_time) = CURDATE() THEN 1 ELSE 0 END) AS completed,
        COUNT(CASE WHEN DATE(request_time) = CURDATE() THEN 1 END) AS total_today
      FROM Emergency_Request
    `);
    res.json(summary);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/reports/top-ambulances — by assignment count
router.get('/top-ambulances', async (req, res) => {
  try {
    const [rows] = await db.execute(`
      SELECT
        am.ambulance_id,
        am.vehicle_number,
        am.status,
        d.name AS driver_name,
        COUNT(a.assignment_id) AS total_assignments,
        SUM(CASE WHEN a.completion_time IS NOT NULL THEN 1 ELSE 0 END) AS completed_assignments
      FROM Ambulance am
      LEFT JOIN Driver d     ON am.driver_id   = d.driver_id
      LEFT JOIN Assignment a ON am.ambulance_id = a.ambulance_id
      GROUP BY am.ambulance_id, am.vehicle_number, am.status, d.name
      ORDER BY total_assignments DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/reports/pending-by-hour — pending requests by hour today
router.get('/pending-by-hour', async (req, res) => {
  try {
    const [rows] = await db.execute(`
      SELECT
        HOUR(request_time) AS hour,
        COUNT(*) AS total_requests,
        SUM(CASE WHEN status = 'PENDING' THEN 1 ELSE 0 END) AS pending_count
      FROM Emergency_Request
      WHERE DATE(request_time) = CURDATE()
      GROUP BY HOUR(request_time)
      ORDER BY hour
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
