# 🚑 Emergency Ambulance Allocation System

A full-stack real-time dispatcher dashboard for managing emergency requests, dispatching the nearest available ambulance, and allocating hospital beds.

---

## 📁 Project Structure

```
ambulance-system/
├── database.sql                  ← Run this first in MySQL
├── frontend/
│   └── index.html                ← Single-page dispatcher dashboard
└── backend/
    ├── package.json
    ├── server.js                 ← Express entry point (port 3000)
    ├── db/
    │   └── connection.js         ← MySQL connection pool
    └── routes/
        ├── requests.js           ← /api/requests
        ├── ambulances.js         ← /api/ambulances
        ├── hospitals.js          ← /api/hospitals
        ├── assignments.js        ← /api/assignments
        └── reports.js            ← /api/reports
```

---

## ⚙️ Prerequisites

- **Node.js** v18+ — https://nodejs.org
- **MySQL** 8.0+ — https://dev.mysql.com/downloads/
- A terminal / command prompt

---

## 🚀 Setup — Step by Step

### Step 1 — Set up the database

1. Open MySQL Workbench, DBeaver, or your MySQL terminal.
2. Open the file `database.sql` (from this project).
3. Run the entire file. It will:
   - Create the `ambulance_system` database
   - Create all 5 tables (Driver, Ambulance, Hospital, Emergency_Request, Assignment)
   - Create the Haversine distance function
   - Create the `allocate_ambulance` stored procedure
   - Create 3 triggers
   - Create 3 views
   - Insert sample seed data (8 drivers, 8 ambulances, 4 hospitals, 7 requests)

You should see: `Database setup complete!`

---

### Step 2 — Configure database credentials (if needed)

If your MySQL username/password is not `root` / `` (empty), edit this file:

**`backend/db/connection.js`**

```js
const db = mysql.createPool({
  host:     'localhost',
  user:     'root',        // ← change this
  password: '',            // ← change this
  database: 'ambulance_system'
});
```

---

### Step 3 — Install backend dependencies

Open a terminal and run:

```bash
cd ambulance-system/backend
npm install
```

This installs: `express`, `mysql2`, `cors`, `nodemon`.

---

### Step 4 — Start the backend server

```bash
cd ambulance-system/backend
node server.js
```

You should see:
```
🚑  Dispatch server running at http://localhost:3000
```

---

### Step 5 — Open the frontend

Open your browser and go to:

```
http://localhost:3000
```

The Node.js server automatically serves the `frontend/index.html` file.

> **Or** open `frontend/index.html` directly in your browser — but the API calls will fail unless the backend is running on port 3000.

---

## 🗂️ Where to put each file

| File | Location on your computer |
|------|--------------------------|
| `database.sql` | Anywhere — open and run it in MySQL |
| `frontend/index.html` | `ambulance-system/frontend/index.html` |
| `backend/server.js` | `ambulance-system/backend/server.js` |
| `backend/package.json` | `ambulance-system/backend/package.json` |
| `backend/db/connection.js` | `ambulance-system/backend/db/connection.js` |
| `backend/routes/requests.js` | `ambulance-system/backend/routes/requests.js` |
| `backend/routes/ambulances.js` | `ambulance-system/backend/routes/ambulances.js` |
| `backend/routes/hospitals.js` | `ambulance-system/backend/routes/hospitals.js` |
| `backend/routes/assignments.js` | `ambulance-system/backend/routes/assignments.js` |
| `backend/routes/reports.js` | `ambulance-system/backend/routes/reports.js` |

---

## 🌐 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/requests` | All requests (`?status=PENDING` filter) |
| POST | `/api/requests` | Create request + auto-allocate |
| GET | `/api/requests/:id` | Single request |
| POST | `/api/requests/:id/allocate` | Retry allocation for PENDING request |
| GET | `/api/ambulances` | All ambulances with driver info |
| GET | `/api/ambulances/available` | Only AVAILABLE ambulances |
| PUT | `/api/ambulances/:id/complete` | Mark job done |
| GET | `/api/hospitals` | All hospitals with bed counts |
| PUT | `/api/hospitals/:id/beds` | Update available beds |
| GET | `/api/assignments` | All assignments (full join) |
| GET | `/api/assignments/active` | Active assignments only |
| PUT | `/api/assignments/:id/complete` | Complete an assignment |
| GET | `/api/reports/daily-summary` | Today's PENDING/ASSIGNED/COMPLETED counts |
| GET | `/api/reports/assignments-per-hospital` | GROUP BY hospital |
| GET | `/api/reports/top-ambulances` | Most active ambulances |
| GET | `/api/reports/pending-by-hour` | Hourly breakdown today |
| GET | `/api/health` | Health check |

---

## 🔄 End-to-End Flow

1. Dispatcher fills the **New Request** form and clicks **Save & allocate**
2. Frontend `POST /api/requests`
3. Backend inserts into `Emergency_Request` (status = PENDING)
4. Backend immediately calls `CALL allocate_ambulance(request_id)`
5. Stored procedure:
   - Finds nearest AVAILABLE ambulance (Haversine distance)
   - Finds hospital with `available_beds > 0`
   - If both found → INSERT Assignment, UPDATE ambulance to BUSY, DECREMENT beds, UPDATE request to ASSIGNED, COMMIT
   - If not → ROLLBACK, request stays PENDING
6. Dashboard auto-refreshes every 30 seconds
7. When job is done → **Mark done** button → `PUT /api/ambulances/:id/complete`
8. Sets `completion_time` → trigger fires → ambulance back to AVAILABLE, request to COMPLETED

---

## 📊 Dashboard Pages

| Page | What it shows |
|------|---------------|
| **Dashboard** | Live metrics, recent requests, hospital capacity bars, fleet pills |
| **Emergency Requests** | Full CRUD table with status filter tabs, new request form, manual allocate button |
| **Ambulances** | Fleet table with driver info, GPS, Mark Done button, map placeholder |
| **Hospitals** | Hospital cards with occupancy bars and editable bed count |
| **Assignments** | Full join table of all allocations with completion control |
| **Reports** | Daily summary, bar charts for hospitals, ambulances, hourly breakdown |

---

## 🛠️ Troubleshooting

**"Error connecting to MySQL"**
- Make sure MySQL service is running
- Check credentials in `backend/db/connection.js`

**"CALL allocate_ambulance does not exist"**
- Re-run `database.sql` — the procedure may not have been created

**Blank dashboard / no data**
- Open browser DevTools → Network tab → look for failed API calls
- Ensure backend is running on port 3000

**CORS error in browser**
- The backend has CORS enabled. Make sure you're hitting `http://localhost:3000` not the file directly.
