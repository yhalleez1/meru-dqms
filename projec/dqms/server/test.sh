#!/bin/bash

echo "🧪 Testing MERU DQMS System - Comprehensive Test Suite"
echo "========================================================"
echo ""

API="http://localhost:3000/api"
OFFICE_ID="811d76ff-17fc-46a7-ae20-e9cbc4be7f47"
TEST_DQMS="TEST-C100"
TEST_PHONE="0712345678"
TEST_STUDENT_NAME="Test Student"
TEST_STUDENT_ID="S99999"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print test results
test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local description=$4
    
    echo -e "${GREEN}→ $description${NC}"
    if [ "$method" = "GET" ]; then
        curl -s "$endpoint" | jq '.'
    else
        curl -s -X "$method" "$endpoint" \
            -H "Content-Type: application/json" \
            -d "$data" | jq '.'
    fi
    echo ""
}

# =========================================================================
# HEALTH CHECK
# =========================================================================
echo -e "\n${GREEN}=== HEALTH CHECK ===${NC}"
test_endpoint "GET" "$API/health" "" "1. Health Check"

# =========================================================================
# OFFICE MANAGEMENT
# =========================================================================
echo -e "\n${GREEN}=== OFFICE MANAGEMENT ===${NC}"

# Create a test office
echo -e "${GREEN}→ 2. Create Test Office${NC}"
OFFICE_RESPONSE=$(curl -s -X POST "$API/offices" \
    -H "Content-Type: application/json" \
    -d "{
        \"office_name\": \"Test Office\",
        \"location\": \"Meru County\",
        \"max_queue_size\": 50
    }")
echo $OFFICE_RESPONSE | jq '.'
TEST_OFFICE_ID=$(echo $OFFICE_RESPONSE | jq -r '.data.id // empty')
if [ -z "$TEST_OFFICE_ID" ]; then
    TEST_OFFICE_ID=$OFFICE_ID
fi
echo ""

# Get all offices
test_endpoint "GET" "$API/offices" "" "3. Get All Offices"

# Get office by ID
test_endpoint "GET" "$API/offices/$TEST_OFFICE_ID" "" "4. Get Office by ID"

# =========================================================================
# STUDENT MANAGEMENT
# =========================================================================
echo -e "\n${GREEN}=== STUDENT MANAGEMENT ===${NC}"

# Create a test student
echo -e "${GREEN}→ 5. Create Test Student${NC}"
STUDENT_RESPONSE=$(curl -s -X POST "$API/students" \
    -H "Content-Type: application/json" \
    -d "{
        \"dqmsNumber\": \"$TEST_DQMS\",
        \"phoneNumber\": \"$TEST_PHONE\",
        \"studentName\": \"$TEST_STUDENT_NAME\",
        \"studentId\": \"$TEST_STUDENT_ID\"
    }")
echo $STUDENT_RESPONSE | jq '.'
TEST_STUDENT=$(echo $STUDENT_RESPONSE | jq -r '.data.id // empty')
echo ""

# Get all students
test_endpoint "GET" "$API/students" "" "6. Get All Students"

# Get student by ID
if [ -n "$TEST_STUDENT" ]; then
    test_endpoint "GET" "$API/students/$TEST_STUDENT" "" "7. Get Student by ID"
fi

# Get student by DQMS number
test_endpoint "GET" "$API/students/by-dqms/$TEST_DQMS" "" "8. Get Student by DQMS Number"

# Get student by phone
test_endpoint "GET" "$API/students/by-phone/$TEST_PHONE" "" "9. Get Student by Phone"

# Update student
if [ -n "$TEST_STUDENT" ]; then
    echo -e "${GREEN}→ 10. Update Student${NC}"
    curl -s -X PUT "$API/students/$TEST_STUDENT" \
        -H "Content-Type: application/json" \
        -d "{
            \"student_name\": \"Updated Test Student\",
            \"phone_number\": \"0723456789\"
        }" | jq '.'
    echo ""
fi

# =========================================================================
# DQMS DEVICE MANAGEMENT
# =========================================================================
echo -e "\n${GREEN}=== DQMS DEVICE MANAGEMENT ===${NC}"

# Register DQMS device
echo -e "${GREEN}→ 11. Register DQMS Device${NC}"
DQMS_RESPONSE=$(curl -s -X POST "$API/dqms/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"dqmsNumber\": \"$TEST_DQMS\",
        \"phoneNumber\": \"$TEST_PHONE\",
        \"officeId\": \"$TEST_OFFICE_ID\",
        \"studentName\": \"$TEST_STUDENT_NAME\",
        \"studentId\": \"$TEST_STUDENT_ID\"
    }")
echo $DQMS_RESPONSE | jq '.'
echo ""

# Get DQMS status
test_endpoint "GET" "$API/dqms/$TEST_DQMS/status" "" "12. Get DQMS Status"

# Get DQMS by phone
echo -e "${GREEN}→ 13. Get Current Ticket by Phone (ESP32 Style)${NC}"
curl -s "$API/dqms/current?phone=$TEST_PHONE" | jq '.'
echo ""

# Get DQMS statistics
test_endpoint "GET" "$API/dqms/stats" "" "14. Get DQMS Statistics"

# Get pending notifications
echo -e "${GREEN}→ 15. Get Pending Notifications${NC}"
curl -s "$API/dqms/pending?office=$TEST_OFFICE_ID" | jq '.'
echo ""

# =========================================================================
# QUEUE MANAGEMENT
# =========================================================================
echo -e "\n${GREEN}=== QUEUE MANAGEMENT ===${NC}"

# Register ticket (add to queue)
echo -e "${GREEN}→ 16. Register New Ticket${NC}"
TICKET_RESPONSE=$(curl -s -X POST "$API/register" \
    -H "Content-Type: application/json" \
    -d "{
        \"officeId\": \"$TEST_OFFICE_ID\",
        \"dqmsNumber\": \"$TEST_DQMS\"
    }")
echo $TICKET_RESPONSE | jq '.'
TEST_TICKET=$(echo $TICKET_RESPONSE | jq -r '.data.ticket_number // empty')
echo ""

# Get current serving
test_endpoint "GET" "$API/current" "" "17. Get Current Serving Ticket"

# Get waiting tickets
test_endpoint "GET" "$API/waiting" "" "18. Get Waiting Tickets"

# Call next ticket
echo -e "${GREEN}→ 19. Call Next Ticket${NC}"
curl -s -X POST "$API/next" \
    -H "Content-Type: application/json" \
    -d "{
        \"officeId\": \"$TEST_OFFICE_ID\"
    }" | jq '.'
echo ""

# Mark ticket as served
if [ -n "$TEST_TICKET" ]; then
    echo -e "${GREEN}→ 20. Mark Ticket as Served${NC}"
    curl -s -X POST "$API/served/$TEST_TICKET" \
        -H "Content-Type: application/json" \
        -d "{
            \"officeId\": \"$TEST_OFFICE_ID\"
        }" | jq '.'
    echo ""
fi

# Mark DQMS ticket as sent
echo -e "${GREEN}→ 21. Mark DQMS Ticket as Sent${NC}"
curl -s -X POST "$API/dqms/$TEST_DQMS/sent" \
    -H "Content-Type: application/json" | jq '.'
echo ""

# Save elapsed time
echo -e "${GREEN}→ 22. Save Elapsed Time${NC}"
curl -s -X POST "$API/elapsed" \
    -H "Content-Type: application/json" \
    -d "{
        \"ticketNumber\": \"$TEST_TICKET\",
        \"elapsedSeconds\": 120,
        \"officeId\": \"$TEST_OFFICE_ID\"
    }" | jq '.'
echo ""

# Get total elapsed time
test_endpoint "GET" "$API/elapsed/total?office=$TEST_OFFICE_ID" "" "23. Get Total Elapsed Time Today"

# Get weekly analytics
test_endpoint "GET" "$API/analytics/weekly?office=$TEST_OFFICE_ID" "" "24. Get Weekly Analytics"

# Get office analytics
test_endpoint "GET" "$API/analytics/by-office?office=$TEST_OFFICE_ID" "" "25. Get Office Analytics"

# =========================================================================
# STAFF MANAGEMENT (if available)
# =========================================================================
echo -e "\n${GREEN}=== STAFF MANAGEMENT ===${NC}"

# Get all staff
test_endpoint "GET" "$API/staff" "" "26. Get All Staff"

# Create test staff
echo -e "${GREEN}→ 27. Create Test Staff${NC}"
STAFF_RESPONSE=$(curl -s -X POST "$API/staff" \
    -H "Content-Type: application/json" \
    -d "{
        \"staff_name\": \"Test Officer\",
        \"position\": \"Counter Officer\",
        \"office_id\": \"$TEST_OFFICE_ID\",
        \"phone_number\": \"0700000000\"
    }")
echo $STAFF_RESPONSE | jq '.'
TEST_STAFF=$(echo $STAFF_RESPONSE | jq -r '.data.id // empty')
echo ""

# Update staff
if [ -n "$TEST_STAFF" ]; then
    echo -e "${GREEN}→ 28. Update Staff${NC}"
    curl -s -X PUT "$API/staff/$TEST_STAFF" \
        -H "Content-Type: application/json" \
        -d "{
            \"staff_name\": \"Updated Officer\",
            \"position\": \"Senior Officer\"
        }" | jq '.'
    echo ""
fi

# =========================================================================
# CLEANUP (OPTIONAL)
# =========================================================================
echo -e "\n${GREEN}=== CLEANUP (Optional) ===${NC}"

# Delete student
if [ -n "$TEST_STUDENT" ]; then
    echo -e "${GREEN}→ 29. Delete Test Student${NC}"
    curl -s -X DELETE "$API/students/$TEST_STUDENT" | jq '.'
    echo ""
fi

# Delete staff
if [ -n "$TEST_STAFF" ]; then
    echo -e "${GREEN}→ 30. Delete Test Staff${NC}"
    curl -s -X DELETE "$API/staff/$TEST_STAFF" | jq '.'
    echo ""
fi

# Delete office
if [ -n "$TEST_OFFICE_ID" ] && [ "$TEST_OFFICE_ID" != "$OFFICE_ID" ]; then
    echo -e "${GREEN}→ 31. Delete Test Office${NC}"
    curl -s -X DELETE "$API/offices/$TEST_OFFICE_ID" | jq '.'
    echo ""
fi

# =========================================================================
# TEST COMPLETE
# =========================================================================
echo -e "\n${GREEN}========================================================"
echo "✅ Comprehensive Test Suite Complete!"
echo "========================================================${NC}"
echo ""
echo "Test Summary:"
echo "  • Health checks"
echo "  • Office management (create, read, update)"
echo "  • Student management (create, read, update)"
echo "  • DQMS device registration and status"
echo "  • Queue operations (register, call, serve)"
echo "  • Analytics and timing"
echo "  • Staff management"
echo ""