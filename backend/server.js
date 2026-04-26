// server.js
const express  = require('express');
const cors     = require('cors');
const path     = require('path');

const requestsRouter    = require('./routes/requests');
const ambulancesRouter  = require('./routes/ambulances');
const hospitalsRouter   = require('./routes/hospitals');
const assignmentsRouter = require('./routes/assignments');
const reportsRouter     = require('./routes/reports');

const app  = express();
const PORT = process.env.PORT || 3000;

// ── Middleware ────────────────────────────────────────────────
app.use(cors());
app.use(express.json());

// Serve static frontend files from ../frontend
app.use(express.static(path.join(__dirname, '..', 'frontend')));

// ── API Routes ───────────────────────────────────────────────
app.use('/api/requests',    requestsRouter);
app.use('/api/ambulances',  ambulancesRouter);
app.use('/api/hospitals',   hospitalsRouter);
app.use('/api/assignments', assignmentsRouter);
app.use('/api/reports',     reportsRouter);

// ── Health check ─────────────────────────────────────────────
app.get('/api/health', (_req, res) => res.json({ status: 'OK', timestamp: new Date() }));

// ── SPA fallback — serve index.html for any non-API route ────
app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'index.html'));
});

app.listen(PORT, () => {
  console.log(`🚑  Dispatch server running at http://localhost:${PORT}`);
});
