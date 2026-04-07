# DQMS Implementation Guide

## Summary of Changes

This document outlines all the changes made to the Meru DQMS system to integrate SMS notifications and consolidate queue registration.

---

## 1. SMS Service Integration

### Setup

All SMS credentials are now stored in the `.env` file:

```env
SMS_API_URL=https://app.mobitechtechnologies.com/sms/sendsms
SMS_API_KEY=4575d6f769777051dde88e8f1987bcf2d9a94cf5e649d3798b5f3f6dc6868d5c
SMS_SENDER_NAME=FULL_CIRCLE
```

### SMS Service Module

A new SMS service module has been created: `server/services/smsService.js`

**Available Functions:**
- `sendSMS(phoneNumber, message)` - Send raw SMS
- `sendTicketNotification(phoneNumber, ticketNumber, studentName, officeName)` - Send formatted ticket notification

**Example Usage:**
```javascript
const { sendTicketNotification } = require('../services/smsService');

await sendTicketNotification('xxxxxx', 42, 'John Doe', 'Main Office');
// Sends: "Hi John Doe, your ticket #42 is ready at Main Office. Please proceed to the counter."
```

---

## 2. Consolidated Queue Registration

### Old Route (Deprecated)
```
POST /api/queue/register
```

### New Single Endpoint
```
POST /api/register
```

**Request Body:**
```json
{
  "dqmsNumber": "xxxxxx",
  "officeId": 1
}
```

**Response:**
```json
{
  "success": true,
  "message": "DQMS registered successfully",
  "data": {
    "dqms_number": "xxxxxx",
    "office_id": 1,
    "office_name": "Main Office",
    "student_name": "xxxxxx",
    "phone_number": "xxxxxx",
    "student_id": "xxxxxx",
    "ticket_number": 42,
    "ticket_sent": false
  }
}
```

### Workflow

1. **Receive Request**: Client sends DQMS number + office ID
2. **Validate Student**: Look up student by DQMS number
3. **Check Office**: Verify office exists
4. **Register DQMS**: Create/update DQMS record
5. **Generate Ticket**: Automatic ticket is generated
6. **Send SMS**: SMS notification is sent to student's phone with:
   - Ticket number
   - Student name
   - Office name

---

## 3. Database Tables

### Students Table
```sql
CREATE TABLE students (
    id              SERIAL PRIMARY KEY,
    dqms_number     VARCHAR(50) UNIQUE NOT NULL,
    phone_number    VARCHAR(20) NOT NULL,
    student_name    VARCHAR(200),
    student_id      VARCHAR(20),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);
```

### DQMS Records Table
```sql
CREATE TABLE dqms_records (
    id               SERIAL PRIMARY KEY,
    dqms_number      VARCHAR(50) UNIQUE NOT NULL,
    student_id       INTEGER REFERENCES students(id),
    office_id        UUID REFERENCES offices(id),
    ticket_number    INTEGER,
    ticket_sent      BOOLEAN DEFAULT FALSE,
    ticket_sent_at   TIMESTAMPTZ,
    created_at       TIMESTAMPTZ DEFAULT NOW(),
    updated_at       TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 4. Setup Instructions

### Step 1: Initialize Database Tables
```bash
chmod +x init-database-tables.sh
./init-database-tables.sh
```

This script creates both `students` and `dqms_records` tables with proper indexes and constraints.

### Step 2: Manage Student Data
```bash
chmod +x manage-students.sh
./manage-students.sh
```

This script:
- Clears all existing student records
- Adds xxxxxx (phone: xxxxxx, ID: xxxxxx)

### Step 3: Install Dependencies
```bash
cd server
npm install
```

### Step 4: Start Server
```bash
npm start
# or for development
npm run dev
```

---

## 5. API Endpoints

### Queue Registration (Consolidated)
```
POST /api/register
Body: { dqmsNumber: string, officeId: number }
Response: { success: boolean, data: {...} }
```

### Queue Management
```
GET  /api/current          - Get current serving ticket
POST /api/next             - Call next ticket
POST /api/served/:ticket   - Mark ticket as served
GET  /api/waiting          - Get waiting tickets
POST /api/skip/:ticket     - Skip a ticket
GET  /api/analytics/weekly - Get weekly statistics
```

### DQMS Status
```
GET  /api/status/:dqmsNumber        - Get DQMS status
GET  /api/current-ticket            - Get ticket by phone
POST /api/ticket-sent/:dqmsNumber   - Mark ticket as sent
GET  /api/pending-notifications     - Get pending SMS notifications
GET  /api/stats                     - Get DQMS statistics
```

### Student Management
```
GET  /api/students                          - Get all students
GET  /api/students/:id                      - Get student by ID
GET  /api/students/by-dqms/:dqmsNumber      - Get student by DQMS number
GET  /api/students/by-phone/:phone          - Get student by phone
POST /api/students                          - Create student
PUT  /api/students/:id                      - Update student
DELETE /api/students/:id                    - Delete student
```

### Office Management
```
GET  /api/offices      - Get all offices
POST /api/offices      - Create office
PUT  /api/offices/:id  - Update office
DELETE /api/offices/:id - Delete office
```

---

## 6. Testing the Integration

### Test Request
```bash
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "dqmsNumber": "xxxxxx",
    "officeId": 1
  }'
```

### Expected Output
```json
{
  "success": true,
  "message": "DQMS registered successfully",
  "data": {
    "dqms_number": "xxxxxx",
    "office_id": 1,
    "office_name": "Main Office",
    "student_name": "xxxxxx",
    "phone_number": "xxxxxx",
    "student_id": "xxxxxx",
    "ticket_number": 1,
    "ticket_sent": false
  }
}
```

The SMS should be sent immediately to the student's phone.

---

## 7. Configuration

### .env File
```env
PORT=3000
DATABASE_URL=postgresql://xxxxxx:xxxxxx@localhost:5432/meru-dqms

# SMS Configuration (Mobitech API)
SMS_API_URL=https://app.mobitechtechnologies.com/sms/sendsms
SMS_API_KEY=4575d6f769777051dde88e8f1987bcf2d9a94cf5e649d3798b5f3f6dc6868d5c
SMS_SENDER_NAME=FULL_CIRCLE
```

### SMS API Details
- **Provider**: Mobitech Technologies
- **Endpoint**: https://app.mobitechtechnologies.com/sms/sendsms
- **Method**: HTTPS POST
- **Auth**: h_api_key header
- **Payload**: Mobile, message, sender_name, service_id, response_type

---

## 8. Error Handling

### Missing SMS Configuration
```json
{
  "success": false,
  "error": "SMS API not configured"
}
```

### Student Not Found
```json
{
  "error": "Student not found. Please contact admin to register student first."
}
```

### Office Not Found
```json
{
  "error": "Office not found"
}
```

---

## 9. Architecture Changes

### Before
- Multiple endpoints: `/queue/register` and `/dqms/register`
- No SMS integration
- Manual ticket generation

### After
- Single unified endpoint: `/register`
- Automatic SMS notification on registration
- Streamlined workflow: DQMS → Student lookup → Ticket generation → SMS

---

## 10. Next Steps

1. Run `init-database-tables.sh` to create tables
2. Run `manage-students.sh` to add test data
3. Start the server and test the `/api/register` endpoint
4. Monitor SMS delivery in the Mobitech dashboard
5. Add more students as needed via the `/api/students` endpoint

---

## Notes

- Phone numbers must be in E.164 format: `+254XXXXXXXXX`
- The system uses Node.js's native `https` module (no external HTTP library)
- All timestamps are in UTC (TIMESTAMPTZ)
- The SMS Service runs asynchronously and doesn't block the API response
- Old DQMS routes are now redirected to the consolidated endpoint
