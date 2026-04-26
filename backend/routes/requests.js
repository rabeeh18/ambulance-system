// routes/requests.js
const express = require('express');
const router  = express.Router();
const db      = require('../db/connection');

// GET /api/requests — all requests, optional ?status= filter
router.get('/', async (req, res) => {
  try {
    const { status } = req.query;
    let sql    = 'SELECT * FROM Emergency_Request';
    const params = [];
    if (status) {
      sql += ' WHERE status = ?';
      params.push(status);
    }
    sql += ' ORDER BY request_time DESC';
    const [rows] = await db.execute(sql, params);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/requests/:id — single request
router.get('/:id', async (req, res) => {
  try {
    const [[row]] = await db.execute(
      'SELECT * FROM Emergency_Request WHERE request_id = ?',
      [req.params.id]
    );
    if (!row) return res.status(404).json({ error: 'Request not found' });
    res.json(row);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/requests — create new request and immediately attempt allocation
router.post('/', async (req, res) => {
  try {
    const {
      caller_name, caller_phone, emergency_type,
      location_latitude, location_longitude, priority
    } = req.body;

    // Insert new emergency request
    const [result] = await db.execute(
      `INSERT INTO Emergency_Request
       (caller_name, caller_phone, emergency_type, location_latitude, location_longitude, priority)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [caller_name, caller_phone, emergency_type, location_latitude, location_longitude, priority]
    );

    const request_id = result.insertId;

    // Immediately attempt allocation via stored procedure
    await db.execute('CALL allocate_ambulance(?)', [request_id]);

    // Fetch final state of the request
    const [[request]] = await db.execute(
      'SELECT * FROM Emergency_Request WHERE request_id = ?',
      [request_id]
    );

    res.status(201).json(request);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/requests/:id/allocate — manually retry allocation for a PENDING request
router.post('/:id/allocate', async (req, res) => {
  try {
    await db.execute('CALL allocate_ambulance(?)', [req.params.id]);
    const [[request]] = await db.execute(
      'SELECT * FROM Emergency_Request WHERE request_id = ?',
      [req.params.id]
    );
    res.json(request);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
