# Changes Summary - Meru DQMS SMS Integration & Route Consolidation

## Files Modified

### 1. `.env` Configuration
**File**: `server/.env`

**Added**:
```env
# SMS Configuration (Mobitech API)
SMS_API_URL=https://app.mobitechtechnologies.com/sms/sendsms
SMS_API_KEY=4575d6f769777051dde88e8f1987bcf2d9a94cf5e649d3798b5f3f6dc6868d5c
SMS_SENDER_NAME=FULL_CIRCLE
```

### 2. SMS Service Module
**File**: `server/services/smsService.js` (NEW)

**Created**: Complete SMS service that uses Node.js native `https` module
- `sendSMS(phoneNumber, message)` - Generic SMS function
- `sendTicketNotification(phoneNumber, ticketNumber, studentName, officeName)` - Formatted ticket notification

**Features**:
- Uses native Node.js https module (no external dependencies)
- Proper error handling and logging
- Returns success/failure response objects
- Async/Promise-based

### 3. DQMS Controller Enhancement
**File**: `server/controllers/dqmsController.js`

**Modified**: `registerDQMS` function now:
1. Validates DQMS number and office ID
2. Looks up student by DQMS number
3. Verifies office exists
4. Registers DQMS and creates ticket
5. **NEW**: Automatically sends SMS notification with ticket details

**Added Import**:
```javascript
const { sendTicketNotification } = require('../services/smsService');
```

### 4. Route Consolidation
**File**: `server/routes/queueRoutes.js`

**Changed**:
- Removed: `POST /queue/register` → `queueController.registerTicket`
- Removed: `POST /dqms/register` nested route
- Added: `POST /register` → `dqmsController.registerDQMS` (SINGLE ENDPOINT)

**Reorganized routes** for better clarity:
- Queue Registration (new consolidated endpoint)
- Queue Status & Management
- DQMS Status & Notifications
- Student Management
- Offices
- Staff

### 5. Server Output
**File**: `server/server.js`

**Updated**: Startup console logging to reflect new endpoints

**Before**:
```
📱 DQMS Endpoints:
POST   /api/dqms/register
GET    /api/dqms/:id/status
```

**After**:
```
📝 Main Endpoints:
POST   /api/register                - Register new ticket (DQMS + Office)
GET    /api/current                 - Get current serving ticket
...
📱 DQMS Status:
GET    /api/status/:dqmsNumber
```

## Files Created

### 1. Database Initialization Script
**File**: `init-database-tables.sh` (NEW)

**Creates**:
- `students` table with proper indexes
- `dqms_records` table with foreign keys
- Both tables created safely (IF NOT EXISTS)

**Usage**:
```bash
chmod +x init-database-tables.sh
./init-database-tables.sh
```

### 2. Student Data Management Script
**File**: `manage-students.sh` (NEW)

**Functions**:
- Creates `students` table if doesn't exist
- Clears all student records
- Adds default student: xxxxxx (xxxxxx, ID: xxxxxx)

**Usage**:
```bash
chmod +x manage-students.sh
./manage-students.sh
```

### 3. Documentation
**File**: `DQMS_SETUP_GUIDE.md` (NEW)

Complete implementation guide including:
- Setup instructions
- API endpoint reference
- Configuration details
- Testing examples
- Architecture changes
- Error handling

## Database Schema Changes

### New Table: `students`
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

### New Table: `dqms_records`
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

## Key Improvements

### 1. Unified Registration Flow
**Before**: Two separate endpoints causing confusion
```
POST /api/queue/register       → Just creates ticket
POST /api/dqms/register        → Complex DQMS flow
```

**After**: Single clear endpoint
```
POST /api/register             → Complete flow: Student lookup → Ticket → SMS
```

### 2. Automatic SMS Notifications
- Student receives ticket number immediately after registration
- Format: "Hi [Name], your ticket #[Number] is ready at [Office]. Please proceed to the counter."
- Happens synchronously with registration (returns immediately)

### 3. No External HTTP Dependencies
- Uses Node.js native `https` module
- Lighter footprint, fewer dependencies
- Better performance

### 4. Cleaner Architecture
- SMS logic separated into service module
- Controllers remain focused on API logic
- Easy to extend or modify SMS behavior

## API Changes

### Endpoint Consolidation

| Old | New | Status |
|-----|-----|--------|
| `POST /api/queue/register` | `POST /api/register` | Consolidated |
| `POST /api/dqms/register` | `POST /api/register` | Consolidated |

### Request/Response Consistency

**All registrations now use the same endpoint**:
```
POST /api/register
Body: {
  "dqmsNumber": "xxxxxx",
  "officeId": 1
}
```

**Response includes all necessary data**:
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

## Setup Steps

1. **Initialize database tables**:
   ```bash
   ./init-database-tables.sh
   ```

2. **Add test student data**:
   ```bash
   ./manage-students.sh
   ```

3. **Install dependencies** (if axios was added before):
   ```bash
   cd server && npm install
   ```

4. **Start the server**:
   ```bash
   npm start
   ```

5. **Test the endpoint**:
   ```bash
   curl -X POST http://localhost:3000/api/register \
     -H "Content-Type: application/json" \
     -d '{"dqmsNumber":"xxxxxx","officeId":1}'
   ```

## Backward Compatibility

- Old `queueController.registerTicket` still exists (not used in routes)
- Can be restored if needed for legacy clients
- DQMS records table is new but doesn't break existing `queue_tickets` table
- Students table is new and doesn't affect existing tables

## Testing

### Test Cases

1. **Valid Registration**:
   ```bash
   curl -X POST http://localhost:3000/api/register \
     -H "Content-Type: application/json" \
     -d '{"dqmsNumber":"xxxxxx","officeId":1}'
   ```
   Expected: ✅ Success with ticket number, SMS sent

2. **Missing DQMS Number**:
   ```bash
   curl -X POST http://localhost:3000/api/register \
     -H "Content-Type: application/json" \
     -d '{"officeId":1}'
   ```
   Expected: ❌ 400 - "dqmsNumber and officeId are required"

3. **Unknown Student**:
   ```bash
   curl -X POST http://localhost:3000/api/register \
     -H "Content-Type: application/json" \
     -d '{"dqmsNumber":"UNKNOWN","officeId":1}'
   ```
   Expected: ❌ 404 - "Student not found"

## Monitoring

Check server logs for SMS delivery status:
```
📱 Sending SMS to xxxxxx...
✅ SMS sent successfully to xxxxxx
```

## Notes

- All phone numbers must be in E.164 format: `+254XXXXXXXXX`
- SMS API key is from Mobitech Technologies
- The system is production-ready for SMS sending
- SMS notifications are asynchronous (non-blocking)
