#!/bin/bash
# manage-students.sh - Clear all student data and seed with Haron Oyngo

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

DB_USER="haron"
DB_HOST="localhost"
DB_NAME="meru-dqms"

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    Student Data Management${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

# Check if students table exists
echo -e "${BLUE}Checking if students table exists...${NC}"
TABLE_EXISTS=$(psql -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" -tc "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'students')")

if [[ "$TABLE_EXISTS" != *"t"* ]]; then
    echo -e "${RED}❌ Students table does not exist!${NC}"
    echo -e "${BLUE}Creating students table...${NC}"
    psql -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" << 'SQL'
CREATE TABLE IF NOT EXISTS students (
    id              SERIAL PRIMARY KEY,
    dqms_number     VARCHAR(50) UNIQUE NOT NULL,
    phone_number    VARCHAR(20) NOT NULL,
    student_name    VARCHAR(200),
    student_id      VARCHAR(20),
    is_active       BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_students_dqms_number ON students (dqms_number);
CREATE INDEX IF NOT EXISTS idx_students_phone ON students (phone_number);
CREATE INDEX IF NOT EXISTS idx_students_active ON students (is_active);

COMMENT ON TABLE students IS 'Student records linked to DQMS devices';
COMMENT ON COLUMN students.dqms_number IS 'Unique DQMS device identifier';
COMMENT ON COLUMN students.phone_number IS 'Phone number for SMS notifications';
SQL
    echo -e "${GREEN}✅ Students table created${NC}"
else
    echo -e "${GREEN}✅ Students table exists${NC}"
fi

# Clear all student data
echo -e "${BLUE}Clearing all student records...${NC}"
psql -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" << 'SQL'
DELETE FROM students;
COMMENT ON COLUMN students.student_id IS 'National ID or student ID';
SQL
echo -e "${GREEN}✅ All student records deleted${NC}"

# Add Haron Oyngo
echo -e "${BLUE}Adding Haron Oyngo...${NC}"
psql -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" << 'SQL'
INSERT INTO students (dqms_number, phone_number, student_name, student_id, is_active)
VALUES ('HARON-OYNGO', '+254797074165', 'Haron Oyngo', '41150479', TRUE);
SQL
echo -e "${GREEN}✅ Haron Oyngo added${NC}"

# Show current students
echo -e "${BLUE}Current students in database:${NC}"
psql -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" << 'SQL'
\x
SELECT * FROM students;
SQL

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Student data management complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
