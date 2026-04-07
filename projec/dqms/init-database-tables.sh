#!/bin/bash
# init-database-tables.sh - Initialize students and dqms_records tables

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
echo -e "${BLUE}    Initializing Additional Database Tables${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

# Create students table if it doesn't exist
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
COMMENT ON COLUMN students.phone_number IS 'Phone number for SMS notifications (+254...)';
COMMENT ON COLUMN students.student_id IS 'National ID or student ID';
SQL
echo -e "${GREEN}✅ Students table ready${NC}"

# Create dqms_records table if doesn't exist
echo -e "${BLUE}Creating dqms_records table...${NC}"
psql -U "$DB_USER" -h "$DB_HOST" -d "$DB_NAME" << 'SQL'
CREATE TABLE IF NOT EXISTS dqms_records (
    id               SERIAL PRIMARY KEY,
    dqms_number      VARCHAR(50) UNIQUE NOT NULL,
    student_id       INTEGER REFERENCES students(id) ON DELETE SET NULL,
    office_id        UUID REFERENCES offices(id) ON DELETE SET NULL,
    ticket_number    INTEGER,
    ticket_sent      BOOLEAN DEFAULT FALSE,
    ticket_sent_at   TIMESTAMPTZ,
    created_at       TIMESTAMPTZ DEFAULT NOW(),
    updated_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dqms_records_dqms_number ON dqms_records (dqms_number);
CREATE INDEX IF NOT EXISTS idx_dqms_records_student_id ON dqms_records (student_id);
CREATE INDEX IF NOT EXISTS idx_dqms_records_office_id ON dqms_records (office_id);
CREATE INDEX IF NOT EXISTS idx_dqms_records_ticket_sent ON dqms_records (ticket_sent);

COMMENT ON TABLE dqms_records IS 'DQMS device registration linked to students and offices';
COMMENT ON COLUMN dqms_records.dqms_number IS 'Unique DQMS device identifier';
COMMENT ON COLUMN dqms_records.student_id IS 'Foreign key to students table';
COMMENT ON COLUMN dqms_records.office_id IS 'Foreign key to offices table';
COMMENT ON COLUMN dqms_records.ticket_number IS 'Generated ticket number for the student';
COMMENT ON COLUMN dqms_records.ticket_sent IS 'Whether SMS notification was sent';
SQL
echo -e "${GREEN}✅ DQMS records table ready${NC}"

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ All tables initialized successfully!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e ""
echo -e "${BLUE}Next step: Run ./manage-students.sh to add student data${NC}"
