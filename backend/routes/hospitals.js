// routes/hospitals.js
const express = require('express');
const router  = express.Router();
const db      = require('../db/connection');

// GET /api/hospitals — all hospitals with bed counts
router.get('/', async (req, res) => {
  try {
    const [rows] = await db.execute(`
      SELECT
        h.*,
        ROUND((h.available_beds / h.total_beds) * 100, 1) AS availability_percent,
        COUNT(a.assignment_id) AS total_assignments
      FROM Hospital h
      LEFT JOIN Assignment a ON h.hospital_id = a.hospital_id
      GROUP BY h.hospital_id
      ORDER BY h.name
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/hospitals/:id — single hospital
router.get('/:id', async (req, res) => {
  try {
    const [[row]] = await db.execute(
      'SELECT * FROM Hospital WHERE hospital_id = ?',
      [req.params.id]
    );
    if (!row) return res.status(404).json({ error: 'Hospital not found' });
    res.json(row);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/hospitals/:id/beds — update available_beds (admin use)
router.put('/:id/beds', async (req, res) => {
  try {
    const { available_beds } = req.body;
    if (available_beds === undefined || available_beds < 0) {
      return res.status(400).json({ error: 'Invalid available_beds value' });
    }

    // Ensure available_beds does not exceed total_beds
    const [[hosp]] = await db.execute(
      'SELECT total_beds FROM Hospital WHERE hospital_id = ?',
      [req.params.id]
    );
    if (!hosp) return res.status(404).json({ error: 'Hospital not found' });
    if (available_beds > hosp.total_beds) {
      return res.status(400).json({ error: 'available_beds cannot exceed total_beds' });
    }

    await db.execute(
      'UPDATE Hospital SET available_beds = ? WHERE hospital_id = ?',
      [available_beds, req.params.id]
    );

    const [[updated]] = await db.execute(
      'SELECT * FROM Hospital WHERE hospital_id = ?',
      [req.params.id]
    );
    res.json(updated);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
