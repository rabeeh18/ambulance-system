// routes/ambulances.js
const express = require('express');
const router  = express.Router();
const db      = require('../db/connection');

// GET /api/ambulances — all ambulances with driver info
router.get('/', async (req, res) => {
  try {
    const [rows] = await db.execute(`
      SELECT
        a.ambulance_id,
        a.vehicle_number,
        a.status,
        a.current_latitude,
        a.current_longitude,
        d.driver_id,
        d.name           AS driver_name,
        d.phone          AS driver_phone,
        d.license_number,
        d.experience_years
      FROM Ambulance a
      LEFT JOIN Driver d ON a.driver_id = d.driver_id
      ORDER BY a.vehicle_number
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/ambulances/available — only AVAILABLE ambulances
router.get('/available', async (req, res) => {
  try {
    const [rows] = await db.execute(`
      SELECT
        a.ambulance_id,
        a.vehicle_number,
        a.current_latitude,
        a.current_longitude,
        d.name AS driver_name
      FROM Ambulance a
      LEFT JOIN Driver d ON a.driver_id = d.driver_id
      WHERE a.status = 'AVAILABLE'
      ORDER BY a.vehicle_number
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/ambulances/:id/complete — mark current job as done
router.put('/:id/complete', async (req, res) => {
  try {
    const { id } = req.params;

    // Set completion_time on the active assignment for this ambulance
    const [result] = await db.execute(`
      UPDATE Assignment
      SET completion_time = NOW()
      WHERE ambulance_id = ?
        AND completion_time IS NULL
    `, [id]);

    if (result.affectedRows === 0) {
      return res.status(404).json({ error: 'No active assignment found for this ambulance' });
    }

    // Trigger after_assignment_update fires automatically to:
    // - SET Ambulance.status = 'AVAILABLE'
    // - SET Emergency_Request.status = 'COMPLETED'

    const [[ambulance]] = await db.execute(`
      SELECT a.*, d.name AS driver_name
      FROM Ambulance a
      LEFT JOIN Driver d ON a.driver_id = d.driver_id
      WHERE a.ambulance_id = ?
    `, [id]);

    res.json(ambulance);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
