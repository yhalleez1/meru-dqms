# DQMS Quick Reference & Troubleshooting

## Quick Start

### 1. Initialize Database (First Time Only)
```bash
./init-database-tables.sh
./manage-students.sh
```

### 2. Start Server
```bash
cd server
npm install
npm start
```

### 3. Test Registration
```bash
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{"dqmsNumber":"HARON-OYNGO","officeId":1}'
```

---

## Common Tasks

### Add a New Student
```bash
curl -X POST http://localhost:3000/api/students \
  -H "Content-Type: application/json" \
  -d '{
    "dqmsNumber": "NEW-STU-001",
    "phoneNumber": "+254700000000",
    "studentName": "John Doe",
    "studentId": "12345678"
  }'
```

### Get All Students
```bash
curl http://localhost:3000/api/students
```

### Get Student by DQMS Number
```bash
curl http://localhost:3000/api/students/by-dqms/HARON-OYNGO
```

### Update Student
```bash
curl -X PUT http://localhost:3000/api/students/1 \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "+254700000001",
    "studentName": "Jane Doe"
  }'
```

### Delete Student
```bash
curl -X DELETE http://localhost:3000/api/students/1
```

### Get Current Serving
```bash
curl "http://localhost:3000/api/current?officeId=1"
```

### Call Next Ticket
```bash
curl -X POST http://localhost:3000/api/next \
  -H "Content-Type: application/json" \
  -d '{"officeId":1}'
```

### Get Waiting Tickets
```bash
curl "http://localhost:3000/api/waiting?officeId=1"
```

### Mark Ticket as Served
```bash
curl -X POST http://localhost:3000/api/served/42 \
  -H "Content-Type: application/json" \
  -d '{"officeId":1}'
```

---

## Troubleshooting

### Problem: SMS Not Sending
**Symptoms**: Registration successful but SMS not received

**Check**:
1. SMS API key is correct in `.env`
   ```bash
   echo $SMS_API_KEY
   ```

2. Phone number is in correct format (E.164: +254XXXXXXXXX)
   ```
   ✅ Correct:   +254797074165
   ❌ Wrong:     254797074165 (missing +)
   ❌ Wrong:     +254 797 074 165 (has spaces)
   ```

3. Check server logs for SMS errors:
   ```bash
   # Look for these messages:
   📱 Sending SMS to +254797074165...
   ✅ SMS sent successfully
   # or
   ❌ Failed to send SMS
   ```

4. Verify MongoDB connectivity (if using LISTEN/NOTIFY):
   ```bash
   psql -U haron -d meru-dqms -c "SELECT 1"
   ```

### Problem: Student Not Found
**Symptoms**: 404 error when registering

**Check**:
1. Student exists in database:
   ```bash
   curl http://localhost:3000/api/students/by-dqms/HARON-OYNGO
   ```

2. DQMS number is correct (case-sensitive):
   ```
   ✅ Correct:   HARON-OYNGO
   ❌ Wrong:     haron-oyngo
   ❌ Wrong:     Haron-Oyngo
   ```

3. Add student if missing:
   ```bash
   ./manage-students.sh
   ```

### Problem: Office Not Found
**Symptoms**: 404 error about office

**Check**:
1. Office exists:
   ```bash
   curl http://localhost:3000/api/offices
   ```

2. Office ID is correct (numeric):
   ```
   ✅ Correct:   1, 2, 3
   ❌ Wrong:     "1" (string)
   ```

3. Create office if missing:
   ```bash
   curl -X POST http://localhost:3000/api/offices \
     -H "Content-Type: application/json" \
     -d '{"name":"Main Office"}'
   ```

### Problem: Database Connection Error
**Symptoms**: Cannot connect to PostgreSQL

**Check**:
1. PostgreSQL is running:
   ```bash
   psql -U haron -d meru-dqms -c "SELECT 1"
   ```

2. DATABASE_URL is correct in `.env`:
   ```env
   DATABASE_URL=postgresql://haron:92949698@localhost:5432/meru-dqms
   ```

3. Database exists:
   ```bash
   psql -U haron -l | grep meru-dqms
   ```

4. Tables exist:
   ```bash
   psql -U haron -d meru-dqms -c "\dt"
   ```

### Problem: Port Already in Use
**Symptoms**: "Error: listen EADDRINUSE"

**Solution**:
1. Kill process using port 3000:
   ```bash
   lsof -ti:3000 | xargs kill -9
   ```

2. Or use different port:
   ```env
   PORT=3001
   ```

### Problem: Missing Dependencies
**Symptoms**: Cannot find module (e.g., "pg")

**Solution**:
```bash
cd server
npm install
```

### Problem: JSON Parse Error
**Symptoms**: "SyntaxError: Unexpected token"

**Check**:
1. Request body is valid JSON:
   ```bash
   # Valid
   {"dqmsNumber":"TEST","officeId":1}
   
   # Invalid - missing comma
   {"dqmsNumber":"TEST" "officeId":1}
   ```

2. Content-Type header is set:
   ```bash
   curl -X POST ... -H "Content-Type: application/json" ...
   ```

---

## Database Cleanup

### Clear All Students
```bash
./manage-students.sh
```

### Clear Specific Table
```bash
psql -U haron -d meru-dqms -c "DELETE FROM students WHERE is_active = false;"
```

### Reset Tables (If Needed)
```bash
psql -U haron -d meru-dqms << EOF
DROP TABLE IF EXISTS dqms_records CASCADE;
DROP TABLE IF EXISTS students CASCADE;
EOF

./init-database-tables.sh
./manage-students.sh
```

---

## Logs & Monitoring

### View Server Logs
```bash
# If using npm start
npm start

# If using npm run dev (with nodemon)
npm run dev

# From another terminal, test:
curl http://localhost:3000/api/register ...
```

### Monitor Database Queries
```bash
# In PostgreSQL
psql -U haron -d meru-dqms

# Inside psql:
SET log_statement = 'all';
SELECT * FROM students;
```

### Check SMS API Status
```bash
# Test API directly (replace KEY with actual key)
curl -X POST https://app.mobitechtechnologies.com/sms/sendsms \
  -H "h_api_key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "mobile":"+254797074165",
    "response_type":"json",
    "sender_name":"FULL_CIRCLE",
    "service_id":0,
    "message":"Test message"
  }'
```

---

## Performance Tips

### Improve Query Speed
```bash
# Create indexes (already created by scripts)
psql -U haron -d meru-dqms -c "
  CREATE INDEX IF NOT EXISTS idx_students_dqms ON students(dqms_number);
  CREATE INDEX IF NOT EXISTS idx_dqms_student ON dqms_records(student_id);
  CREATE INDEX IF NOT EXISTS idx_dqms_office ON dqms_records(office_id);
"
```

### Monitor Connection Pool
Add to `.env`:
```env
# PostgreSQL Connection Pool
DB_POOL_MAX=20
DB_POOL_IDLE_TIMEOUT=30000
```

### Cache Students (Optional)
For high-traffic systems, implement Redis caching layer.

---

## Deployment Checklist

- [ ] `.env` file configured with correct credentials
- [ ] SMS API key is active and working
- [ ] Database tables created: `students`, `dqms_records`
- [ ] Test student "HARON-OYNGO" added
- [ ] At least one office created
- [ ] PostgreSQL backups configured
- [ ] SMS delivery logging enabled
- [ ] Error monitoring set up (e.g., Sentry)
- [ ] Load testing completed
- [ ] SSL certificates configured (for production)

---

## API Response Codes

| Code | Meaning | Solution |
|------|---------|----------|
| 200 | Success | ✅ Everything working |
| 201 | Created | ✅ Resource created |
| 400 | Bad Request | Check request JSON format |
| 404 | Not Found | Check if resource exists |
| 500 | Server Error | Check server logs |

---

## Default Test Data

After running `manage-students.sh`:

| Field | Value |
|-------|-------|
| DQMS Number | HARON-OYNGO |
| Phone | +254797074165 |
| Name | Haron Oyngo |
| ID | 41150479 |
| Status | Active |

---

## Support

For issues:
1. Check this troubleshooting guide
2. Review server logs: `npm start`
3. Check database: `psql -U haron -d meru-dqms`
4. Verify SMS API: Check Mobitech dashboard
5. Test endpoint: Use curl examples above

---

## Resources

- [DQMS_SETUP_GUIDE.md](./DQMS_SETUP_GUIDE.md) - Complete setup documentation
- [CHANGES_SUMMARY.md](./CHANGES_SUMMARY.md) - Detailed changes made
- [README.md](./README.md) - Project overview
