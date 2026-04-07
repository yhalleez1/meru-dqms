# MERU DQMS - API Endpoints & Frontend Harmonization

## Base URL
```
http://localhost:3000/api
```

## Frontend Configurations

### Simulator
- **File**: `/simulator/script.js`
- **API Base**: `http://localhost:3000/api`
- **Purpose**: Student ticket generation interface

### Staff Dashboard  
- **File**: `/staff/script.js`
- **API Base**: `http://localhost:3000/api`
- **Purpose**: Queue management and staff operations

### Staff Login
- **File**: `/staff/login.html`
- **API Base**: `http://localhost:3000/api`
- **Purpose**: Authentication for staff members

---

## Harmonized Endpoints

### 1. HEALTH CHECK
```
GET /api/health
```
**Response:**
```json
{ "status": "Server is running" }
```

---

### 2. QUEUE MANAGEMENT (Core Operations)

#### Register New Ticket
```
POST /api/register
```
**Body:**
```json
{
  "officeId": "uuid",
  "issuedAt": "2026-03-31T..."
}
```
**Response:**
```json
{
  "success": true,
  "ticketNumber": 123,
  "data": { ... }
}
```
**Used By**: Simulator

---

#### Get Current Serving
```
GET /api/current?officeId=uuid
```
**Response:**
```json
{
  "success": true,
  "currentServing": 123,
  "data": { ... }
}
```
**Used By**: Simulator, Staff Dashboard

---

#### Get Waiting Tickets
```
GET /api/waiting?officeId=uuid
```
**Response:**
```json
{
  "success": true,
  "count": 5,
  "data": [
    { "ticket_number": 124, "created_at": "...", ... },
    ...
  ]
}
```
**Used By**: Simulator, Staff Dashboard

---

#### Call Next Ticket
```
POST /api/next
```
**Body:**
```json
{
  "officeId": "uuid"
}
```
**Response:**
```json
{
  "success": true,
  "ticketNumber": 124,
  "data": { ... }
}
```
**Used By**: Staff Dashboard

---

#### Mark Ticket as Served
```
POST /api/served/:ticketNumber
```
**Body:**
```json
{
  "officeId": "uuid"
}
```
**Response:**
```json
{
  "success": true,
  "data": { ... }
}
```
**Used By**: Staff Dashboard (via Call Next flow)

---

#### Skip Ticket
```
POST /api/skip/:ticketNumber
```
**Body:**
```json
{
  "officeId": "uuid"
}
```
**Response:**
```json
{
  "success": true,
  "message": "Ticket #123 skipped",
  "data": { ... }
}
```
**Used By**: Staff Dashboard

---

#### Save Elapsed Time
```
POST /api/elapsed
```
**Body:**
```json
{
  "ticketNumber": 123,
  "elapsedSeconds": 120,
  "officeId": "uuid"
}
```
**Response:**
```json
{
  "success": true,
  "message": "Elapsed time recorded: 120s",
  "data": { ... }
}
```
**Used By**: Staff Dashboard (on ticket closure)

---

#### Get Total Elapsed Time
```
GET /api/elapsed/total?officeId=uuid
```
**Response:**
```json
{
  "success": true,
  "totalSeconds": 450,
  "data": { "totalSeconds": 450, "officeId": "uuid" }
}
```
**Used By**: Staff Dashboard (on boot)

---

### 3. ANALYTICS

#### Get Weekly Analytics
```
GET /api/analytics/weekly?officeId=uuid
```
**Response:**
```json
{
  "success": true,
  "count": 7,
  "data": [ { day: "Monday", ticketsServed: 45, ... }, ... ]
}
```

---

#### Get Office Analytics
```
GET /api/analytics/by-office?officeId=uuid
```
**Response:**
```json
{
  "success": true,
  "data": {
    "totalTicketsToday": 100,
    "averageWaitTime": 85,
    ...
  }
}
```

---

### 4. OFFICE MANAGEMENT

#### Get All Offices
```
GET /api/offices
```
**Response:**
```json
[
  { "id": "uuid", "name": "Main Office", "staffCount": 3, ... },
  ...
]
```
**Used By**: Simulator (to populate office dropdown)

---

#### Create Office
```
POST /api/offices
```
**Body:**
```json
{
  "name": "New Office",
  "location": "Meru",
  "max_queue_size": 50
}
```

---

#### Get Office by ID
```
GET /api/offices/:id
```

---

#### Update Office
```
PUT /api/offices/:id
```

---

#### Delete Office
```
DELETE /api/offices/:id
```

---

### 5. STUDENT MANAGEMENT

#### Get All Students
```
GET /api/students
```
**Response:**
```json
{
  "success": true,
  "count": 50,
  "data": [
    { "id": "uuid", "dqms_number": "C100", "phone_number": "0712...", ... },
    ...
  ]
}
```

---

#### Create Student
```
POST /api/students
```
**Body:**
```json
{
  "dqmsNumber": "C100",
  "phoneNumber": "0712345678",
  "studentName": "John Doe",
  "studentId": "S12345"
}
```

---

#### Get Student by ID
```
GET /api/students/:id
```

---

#### Get Student by DQMS Number
```
GET /api/students/by-dqms/:dqmsNumber
```

---

#### Get Student by Phone
```
GET /api/students/by-phone/:phone
```

---

#### Update Student
```
PUT /api/students/:id
```

---

#### Delete Student
```
DELETE /api/students/:id
```

---

### 6. DQMS DEVICE MANAGEMENT

#### Register DQMS Device
```
POST /api/dqms/register
```
**Body:**
```json
{
  "dqmsNumber": "C100",
  "phoneNumber": "0712345678",
  "officeId": "uuid",
  "studentName": "John Doe",
  "studentId": "S12345"
}
```

---

#### Get DQMS Status
```
GET /api/dqms/:dqmsNumber/status
```
**Response:**
```json
{
  "success": true,
  "data": {
    "dqms_number": "C100",
    "ticket_number": 123,
    "ticket_sent": false,
    ...
  }
}
```

---

#### Get Current Ticket by Phone (ESP32 Call)
```
GET /api/dqms/current?phone=0712345678
```
**Response:**
- Returns ticket number or '0' if no ticket
**Used By**: ESP32 display devices

---

#### Mark DQMS Ticket as Sent
```
POST /api/dqms/:dqmsNumber/sent
```
**Response:**
```json
{
  "success": true,
  "data": { "ticket_number": 123, "ticket_sent": true }
}
```

---

#### Get Pending Notifications
```
GET /api/dqms/pending?office=uuid
```

---

#### Get DQMS Statistics
```
GET /api/dqms/stats
```

---

### 7. STAFF MANAGEMENT

#### Staff Login
```
POST /api/staff/login
```
**Body:**
```json
{
  "username": "john_smith",
  "password": "password123"
}
```
**Response:**
```json
{
  "id": "uuid",
  "name": "John Smith",
  "officeId": "uuid",
  "officeName": "Main Office"
}
```
**Used By**: Staff Login page

**Session Storage:**
- `staffId` → Used to track which staff member is logged in
- `staffName` → Display staff name
- `officeId` → Filter queues and analytics to this office
- `officeName` → Display office name

---

#### Get All Staff
```
GET /api/staff
```

---

#### Create Staff
```
POST /api/staff
```

---

#### Update Staff
```
PUT /api/staff/:id
```

---

#### Delete Staff
```
DELETE /api/staff/:id
```

---

## Frontend Data Flow

### Simulator Flow
1. **Page Load**
   - Fetch `/api/offices` → Populate office dropdown
   
2. **Every 2 seconds**
   - Fetch `/api/current?officeId=...` → Update LCD display
   
3. **On "Get Ticket" Button**
   - POST `/api/register` with officeId
   - Display ticket number
   - Update LCD display

---

### Staff Dashboard Flow
1. **Page Load**
   - Verify session (officeId from sessionStorage)
   - Fetch `/api/elapsed/total?officeId=...` → Load today's total
   - Fetch `/api/current?officeId=...` → Get current ticket
   - Fetch `/api/waiting?officeId=...` → Get waiting list

2. **Every 2 seconds (Auto-refresh)**
   - Fetch `/api/current?officeId=...`
   - Fetch `/api/waiting?officeId=...`

3. **On "Call Next" Button**
   - POST `/api/next` with officeId
   - Start 10-second countdown
   - After countdown, start timer for service tracking
   - When user clicks "Call Next" again:
     - POST `/api/elapsed` with elapsed seconds
     - Call `/api/next` again

4. **On "Skip" Button**
   - POST `/api/skip/:ticketNumber` with officeId
   - Call `/api/next` if available

5. **On "Total Time" Button**
   - Display cumulative time from DB + current session

---

## Key Query Parameters

| Parameter | Type | Usage | Example |
|-----------|------|-------|---------|
| `officeId` | UUID/string | Filter queue/analytics to office | `?officeId=811d76ff-...` |
| `phone` | string | Find ticket by phone (DQMS) | `?phone=0712345678` |
| `office` | UUID | Filter DQMS pending by office | `?office=811d76ff-...` |

---

## Response Format Standards

All successful responses follow:
```json
{
  "success": true,
  "data": { ... },
  "message": "...",  // optional
  "count": 0,        // optional (arrays)
  "ticketNumber": 0, // optional (queue endpoints)
  "totalSeconds": 0  // optional (time endpoints)
}
```

All error responses follow:
```json
{
  "error": "Error message",
  "details": "...",  // optional
  "success": false   // optional
}
```

---

## Session Management

**Staff Dashboard Session Storage:**
```javascript
sessionStorage.setItem('staffId', data.id);
sessionStorage.setItem('staffName', data.name);
sessionStorage.setItem('officeId', data.officeId);
sessionStorage.setItem('officeName', data.officeName);
```

**Logout:**
```javascript
sessionStorage.clear();
window.location.href = '/staff/login.html';
```

---

## Testing

Run the comprehensive test suite:
```bash
cd server
./test.sh
```

This tests ALL endpoints with proper payloads and displays results in a harmonized format.
