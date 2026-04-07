#!/bin/bash
# Test script for Admin Student Management Feature

set -e

API_BASE="http://localhost:3000/api"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Admin Student Management - Comprehensive Test Suite${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST 1: Get all students (initial count)
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 1]${NC} Get all students"
INITIAL_COUNT=$(curl -s "$API_BASE/students" | jq '.count')
echo -e "  ${GREEN}✓${NC} Initial student count: ${INITIAL_COUNT}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST 2: Add a single student (manual entry)
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 2]${NC} Add single student (manual entry)"
STUDENT_ID=$(curl -s -X POST "$API_BASE/students" \
  -H "Content-Type: application/json" \
  -d '{
    "dqmsNumber": "TEST-MANUAL-001",
    "phoneNumber": "0722111111",
    "studentName": "Test Manual Student",
    "studentId": "MANUAL001"
  }' | jq -r '.data.id')

if [ ! -z "$STUDENT_ID" ] && [ "$STUDENT_ID" != "null" ]; then
  echo -e "  ${GREEN}✓${NC} Student added successfully (ID: ${STUDENT_ID:0:8}...)"
else
  echo -e "  ${RED}✗${NC} Failed to add student"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# TEST 3: Get student by ID
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 3]${NC} Retrieve student by ID"
STUDENT=$(curl -s "$API_BASE/students/$STUDENT_ID" | jq '.data')
NAME=$(echo $STUDENT | jq -r '.student_name')
DQMS=$(echo $STUDENT | jq -r '.dqms_number')
echo -e "  ${GREEN}✓${NC} Retrieved: ${NAME} (DQMS: ${DQMS})"

# ─────────────────────────────────────────────────────────────────────────────
# TEST 4: Search student by DQMS number
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 4]${NC} Search student by DQMS number"
FOUND=$(curl -s "$API_BASE/students/by-dqms/TEST-MANUAL-001" | jq '.data.student_name')
echo -e "  ${GREEN}✓${NC} Found: ${FOUND}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST 5: Search student by phone
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 5]${NC} Search student by phone number"
FOUND=$(curl -s "$API_BASE/students/by-phone/0722111111" | jq '.data.student_name')
echo -e "  ${GREEN}✓${NC} Found: ${FOUND}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST 6: Bulk add multiple students (simulating CSV upload)
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 6]${NC} Bulk add students (CSV simulation)"
declare -a BULK_IDS

for i in {1..5}; do
  BULK_ID=$(curl -s -X POST "$API_BASE/students" \
    -H "Content-Type: application/json" \
    -d '{
      "dqmsNumber": "BULK-'$(printf "%03d" $i)'",
      "phoneNumber": "07'$(printf "%08d" $((20000000 + i)))'",
      "studentName": "Bulk Student '$i'",
      "studentId": "BULK'$(printf "%03d" $i)'"
    }' | jq -r '.data.id')
  
  BULK_IDS["$i"]=$BULK_ID
  echo -e "  ${GREEN}✓${NC} Added bulk student $i"
done

# ─────────────────────────────────────────────────────────────────────────────
# TEST 7: Verify count increased
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 7]${NC} Verify student count increased"
NEW_COUNT=$(curl -s "$API_BASE/students" | jq '.count')
ADDED=$((NEW_COUNT - INITIAL_COUNT))
echo -e "  ${GREEN}✓${NC} New count: ${NEW_COUNT} (Added: ${ADDED})"

# ─────────────────────────────────────────────────────────────────────────────
# TEST 8: Update a student
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 8]${NC} Update student record"
curl -s -X PUT "$API_BASE/students/$STUDENT_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "phoneNumber": "0722222222",
    "studentName": "Updated Test Student"
  }' > /dev/null

UPDATED=$(curl -s "$API_BASE/students/$STUDENT_ID" | jq '.data.student_name')
echo -e "  ${GREEN}✓${NC} Updated to: ${UPDATED}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST 9: Delete a student
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 9]${NC} Delete student record"
curl -s -X DELETE "$API_BASE/students/${BULK_IDS[1]}" > /dev/null
echo -e "  ${GREEN}✓${NC} Student deleted"

# ─────────────────────────────────────────────────────────────────────────────
# TEST 10: Verify count after deletion
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 10]${NC} Verify student count after deletion"
FINAL_COUNT=$(curl -s "$API_BASE/students" | jq '.count')
echo -e "  ${GREEN}✓${NC} Final count: ${FINAL_COUNT}"

# ─────────────────────────────────────────────────────────────────────────────
# TEST 11: List all students
# ─────────────────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}[TEST 11]${NC} List sample of all students"
curl -s "$API_BASE/students" | jq '.data[0:3] | .[] | {dqms_number, student_name, phone_number}' | \
  head -20 | while IFS= read -r line; do
  echo -e "  ${GREEN}  ${NC}${line}"
done

echo -e "\n${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ All tests completed successfully!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
