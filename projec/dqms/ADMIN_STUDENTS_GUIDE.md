# Admin Student Management Feature Documentation

## Overview

The Admin Dashboard now includes comprehensive **Student Management** functionality that allows administrators to:
- View all registered students in a tabular format
- Add students **manually** through a form
- Upload and import **bulk students via CSV** files
- Delete student records
- Real-time validation and feedback

## Features

### 1. **Students Dashboard Page**

Located in the Admin sidebar under 🎓 **Students**, this page displays:
- Complete list of all registered students
- DQMS Number, Phone Number, Student Name, and Student ID
- Row numbering for easy reference
- Delete action buttons for each student
- Add Student(s) button to open the management modal

### 2. **Manual Student Entry**

**Location:** Students Page → Add Student(s) → Manual Entry Tab

**Form Fields:**
- **DQMS Number** (Required): Unique identifier for the student's DQMS registration
  - Example: `DQMS-2024-001`
  - Max 50 characters
  
- **Phone Number** (Required): Student's contact number
  - Example: `0712345678`
  - Max 20 characters
  
- **Student Name** (Required): Full name of the student
  - Example: `John Doe`
  - Max 100 characters
  
- **Student ID** (Required): Student's institution ID
  - Example: `STU-001`
  - Max 50 characters

**Workflow:**
1. Click "Add Student(s)" button on Students page
2. Select "Manual Entry" tab (default)
3. Fill in all required fields
4. Click "Add Student" button
5. Receive success notification
6. Student list auto-refreshes

### 3. **CSV Bulk Upload**

**Location:** Students Page → Add Student(s) → CSV Upload Tab

**CSV Format:**
```csv
dqms_number,phone_number,student_name,student_id
DQMS-2024-001,0701234567,John Doe,STU001
DQMS-2024-002,0702334455,Jane Smith,STU002
DQMS-2024-003,0703445566,Peter Johnson,STU003
```

**Requirements:**
- First row must be the header with exact column names
- Columns must be in order: `dqms_number, phone_number, student_name, student_id`
- All fields required for each row
- Max file size: Browser dependent (typically 50MB)
- Supported format: `.csv` only

**Workflow:**
1. Click "Add Student(s)" button on Students page
2. Select "CSV Upload" tab
3. Click file input and select a `.csv` file
4. System automatically parses and shows a preview
5. Preview displays first 10 rows with data validation
6. Click "Upload Students" to insert into database
7. System processes each row; shows success count and any failures
8. Student list auto-refreshes

**CSV Sample Files:**
- Pre-made sample file included: `/sample_students.csv`
- Contains 10 example student records
- Ready to use for testing the upload feature

### 4. **Student List Display**

The Students page shows:
- Row number (auto-numbered from 1+)
- DQMS Number
- Phone Number
- Student Name
- Student ID
- Delete button for each record

**Features:**
- Table automatically updates after add/delete operations
- Empty state message when no students exist
- Real-time row count visible in header
- Responsive design for mobile viewing

### 5. **Data Validation**

**Frontend Validation:**
- All fields marked as required
- Phone format checking
- Empty field detection
- CSV parsing error handling

**Backend Validation:**
- DQMS Number uniqueness
- Required field validation
- Data type checking
- Database constraint enforcement

**Error Handling:**
- User-friendly error messages
- Field-level validation feedback
- Bulk upload partial success (tries all records, reports results)
- Toast notifications for all operations

## API Endpoints Used

All requests go to: `http://localhost:3000/api`

### Students Endpoints

```
GET    /students                    - Get all students
GET    /students/:id                - Get student by ID
GET    /students/by-dqms/:dqmsNumber - Search by DQMS number
GET    /students/by-phone/:phone    - Search by phone number
POST   /students                    - Create new student
PUT    /students/:id                - Update student record
DELETE /students/:id                - Delete student record
```

### Request/Response Format

**POST /students (Create Student)**
```json
Request:
{
  "dqmsNumber": "DQMS-2024-001",
  "phoneNumber": "0712345678",
  "studentName": "John Doe",
  "studentId": "STU001"
}

Response:
{
  "success": true,
  "message": "Student created successfully",
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "dqms_number": "DQMS-2024-001",
    "phone_number": "0712345678",
    "student_name": "John Doe",
    "student_id": "STU001",
    "is_active": true,
    "created_at": "2024-03-31T12:34:56.789Z",
    "updated_at": "2024-03-31T12:34:56.789Z"
  }
}
```

**GET /students (List All)**
```json
Response:
{
  "success": true,
  "count": 10,
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "dqms_number": "DQMS-2024-001",
      "phone_number": "0712345678",
      "student_name": "John Doe",
      "student_id": "STU001",
      "is_active": true,
      "created_at": "2024-03-31T12:34:56.789Z",
      "updated_at": "2024-03-31T12:34:56.789Z"
    }
    ...
  ]
}
```

**PUT /students/:id (Update Student)**
```json
Request:
{
  "phoneNumber": "0722222222",
  "studentName": "Updated Name"
}

Response: Same format as POST with updated data
```

**DELETE /students/:id (Delete Student)**
```json
Response:
{
  "success": true,
  "message": "Student deleted successfully"
}
```

## User Interface Components

### Modal Dialog

**Title:** "Add Student(s)"

**Tabs:**
1. **Manual Entry** - Single student form (default)
2. **CSV Upload** - File upload interface

**Buttons:**
- Cancel - Close modal without saving
- Add Student / Upload Students - Submit data to create records

### Tab Switching

The modal includes styled tab buttons that:
- Visually indicate active tab with border and color
- Switch between manual entry form and CSV upload interface
- Maintain tab state during session

### Preview Table (CSV Only)

Shows:
- Column headers: DQMS #, Phone, Name, ID
- Up to 10 sample rows from CSV
- Row count indicator
- Allows visual verification before upload

## Keyboard Shortcuts

- `Tab` - Navigate between fields
- `Enter` - Submit form (Add Student or Upload)
- `Escape` - Close modal

## Browser Compatibility

- Chrome/Edge: ✅ Full support
- Firefox: ✅ Full support
- Safari: ✅ Full support
- Mobile browsers: ✅ Responsive design

## Troubleshooting

### Issue: "Failed to add student"

**Solutions:**
- Verify all fields are not empty
- Check DQMS Number is not already registered
- Ensure phone number format is valid
- Verify server is running (`http://localhost:3000/api/students` should work)

### Issue: CSV Upload Shows "No valid records"

**Solutions:**
- Verify CSV has header row with correct column names:
  `dqms_number,phone_number,student_name,student_id`
- Check all data rows have 4 comma-separated values
- Ensure no extra spaces or special characters in headers
- Verify file encoding is UTF-8

### Issue: "Connection refused" errors

**Solutions:**
- Ensure backend server is running: `cd server && node server.js`
- Verify port 3000 is available
- Check firewall allowing localhost connections
- Try server health check: `curl http://localhost:3000/api/students`

### Issue: CSV Upload - Partial success

**Expected behavior:**
- If 1 record fails but others succeed, system reports total results
- Check error message for which record failed
- Review data in that row for issues (duplicate DQMS, missing fields)

## Testing

### Manual Testing Steps

1. **Navigate to Students Page**
   - Click 🎓 Students in sidebar
   - Verify student table loads

2. **Add Single Student**
   - Click "Add Student(s)" button
   - Fill in all fields with valid data
   - Click "Add Student"
   - Verify new student appears in table

3. **Test CSV Upload**
   - Click "Add Student(s)" button
   - Switch to "CSV Upload" tab
   - Select `sample_students.csv` file
   - Review preview
   - Click "Upload Students"
   - Verify students appear in list

4. **Delete Student**
   - Hover over any row
   - Click "Delete" button
   - Confirm deletion
   - Verify student removed from table

### Automated Testing

Run the comprehensive test script:
```bash
cd /home/haron/projec/meru-dqms
bash test-admin-students.sh
```

This tests all 11 critical functions:
- Listing students
- Adding single student
- Retrieving by ID
- Searching by DQMS
- Searching by phone
- Bulk adding
- Count verification
- Updating records
- Deleting records
- Status verification
- Complete listing

## Performance Notes

- Page loads all students on initial view
- Auto-refresh every 30 seconds when tab is active
- CSV preview limited to 10 rows for UI responsiveness
- Bulk upload processes records sequentially (not parallel)
- Database queries optimized with indexes

## Security Considerations

- Admin authentication required (session-based)
- All data inputs sanitized server-side
- SQL injection prevention via parameterized queries
- No sensitive data logged to console
- Session tokens stored in sessionStorage

## Future Enhancements

Potential features for future releases:
- Export students to CSV
- Advanced search and filtering
- Batch edit multiple students
- Student profile details view
- Integration with queue tickets
- Export analytics by student cohort
- Scheduled bulk imports
- Student status tracking (active/inactive)

## Support & Questions

For issues or questions:
1. Check the Troubleshooting section above
2. Review console logs for error messages
3. Run the test script to verify backend health
4. Check API documentation in API_ENDPOINTS.md

---

**Last Updated:** 2024-03-31
**Component Location:** `/staff/admin.html` (Lines 607-615 for nav, 710-723 for page, 867-971 for modal)
**API Controller:** `/server/controllers/studentsController.js`
**Database Model:** `/server/models/student.model.js`
