// routes/assignments.js
const express = require('express');
const router  = express.Router();
const db      = require('../db/connection');

// GET /api/assignments — all assignments with full join data
router.get('/', async (req, res) => {
  try {
    const [rows] = await db.execute(`
      SELECT
        a.assignment_id,
        a.request_id,
        a.assigned_time,
        a.completion_time,
        er.caller_name,
        er.caller_phone,
        er.emergency_type,
        er.priority,
        er.location_latitude,
        er.location_longitude,
        er.status AS request_status,
        am.ambulance_id,
        am.vehicle_number,
        d.name           AS driver_name,
        d.license_number,
        h.hospital_id,
        h.name           AS hospital_name,
        h.address        AS hospital_address
      FROM Assignment a
      JOIN Emergency_Request er ON a.request_id   = er.request_id
      JOIN Ambulance am          ON a.ambulance_id = am.ambulance_id
      JOIN Driver d              ON am.driver_id   = d.driver_id
      JOIN Hospital h            ON a.hospital_id  = h.hospital_id
      ORDER BY a.assigned_time DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/assignments/active — assignments with no completion_time
router.get('/active', async (req, res) => {
  try {
    const [rows] = await db.execute(`
      SELECT
        a.assignment_id,
        a.request_id,
        a.assigned_time,
        er.caller_name,
        er.emergency_type,
        er.priority,
        am.vehicle_number,
        d.name  AS driver_name,
        h.name  AS hospital_name
      FROM Assignment a
      JOIN Emergency_Request er ON a.request_id   = er.request_id
      JOIN Ambulance am          ON a.ambulance_id = am.ambulance_id
      JOIN Driver d              ON am.driver_id   = d.driver_id
      JOIN Hospital h            ON a.hospital_id  = h.hospital_id
      WHERE a.completion_time IS NULL
      ORDER BY a.assigned_time DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/assignments/:id/complete — mark assignment as done
router.put('/:id/complete', async (req, res) => {
  try {
    const [result] = await db.execute(`
      UPDATE Assignment
      SET completion_time = NOW()
      WHERE assignment_id = ?
        AND completion_time IS NULL
    `, [req.params.id]);

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'Assignment not found or already completed' });
    }

    const [[updated]] = await db.execute(`
      SELECT
        a.*,
        er.emergency_type, er.priority, er.caller_name,
        am.vehicle_number,
        d.name AS driver_name,
        h.name AS hospital_name
      FROM Assignment a
      JOIN Emergency_Request er ON a.request_id   = er.request_id
      JOIN Ambulance am          ON a.ambulance_id = am.ambulance_id
      JOIN Driver d              ON am.driver_id   = d.driver_id
      JOIN Hospital h            ON a.hospital_id  = h.hospital_id
      WHERE a.assignment_id = ?
    `, [req.params.id]);

    res.json(updated);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
