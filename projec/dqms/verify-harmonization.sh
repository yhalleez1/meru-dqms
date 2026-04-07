#!/bin/bash

echo "🔍 MERU DQMS - System Harmonization Verification"
echo "=================================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0
SUCCESS=0

check_file() {
    local file=$1
    local description=$2
    
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $description"
        ((SUCCESS++))
    else
        echo -e "${RED}✗${NC} $description - MISSING: $file"
        ((ERRORS++))
    fi
}

check_content() {
    local file=$1
    local search=$2
    local description=$3
    
    if grep -q "$search" "$file"; then
        echo -e "${GREEN}✓${NC} $description"
        ((SUCCESS++))
    else
        echo -e "${RED}✗${NC} $description - NOT FOUND: $search"
        ((ERRORS++))
    fi
}

echo "📂 Backend Files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_file "server/app.js" "app.js exists"
check_content "server/app.js" "module.exports = { server: app }" "app.js exports server object"
check_content "server/app.js" "app.use('/api', queueRoutes)" "Routes mounted at /api"

check_file "server/server.js" "server.js exists"
check_content "server/server.js" "require('./app').server" "server.js imports correctly"

check_file "server/routes/queueRoutes.js" "queueRoutes.js exists"
check_content "server/routes/queueRoutes.js" "router.post('/register'" "Queue route exists"
check_content "server/routes/queueRoutes.js" "router.post('/dqms/register'" "DQMS route exists"
check_content "server/routes/queueRoutes.js" "router.post('/staff/login'" "Staff login route exists"

check_file "server/controllers/queueController.js" "queueController.js exists"
check_content "server/controllers/queueController.js" "exports.registerTicket" "registerTicket handler exists"
check_content "server/controllers/queueController.js" "exports.callNext" "callNext handler exists"

check_file "server/models/student.model.js" "student.model.js exists (correct naming)"
check_content "server/models/index.js" "require('./student.model')" "student.model.js imported correctly"

check_file "server/controllers/studentsController.js" "studentsController.js exists"
check_file "server/controllers/dqmsController.js" "dqmsController.js exists"
check_file "server/controllers/officesController.js" "officesController.js exists"
check_file "server/controllers/staffController.js" "staffController.js exists"

echo ""
echo "🎨 Frontend Files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_file "simulator/script.js" "simulator/script.js exists"
check_content "simulator/script.js" "http://localhost:3000/api" "Simulator uses correct API base"
check_content "simulator/script.js" "fetch(\`\${API_BASE}/register\`" "Simulator calls /register"

check_file "staff/script.js" "staff/script.js exists"
check_content "staff/script.js" "http://localhost:3000/api" "Staff uses correct API base"
check_content "staff/script.js" "officeId" "Staff sends officeId"

check_file "staff/login.html" "staff/login.html exists"
check_content "staff/login.html" "staff/login" "Login page connects to correct endpoint"

echo ""
echo "📚 Documentation Files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_file "API_ENDPOINTS.md" "API_ENDPOINTS.md created"
check_file "HARMONIZATION_SUMMARY.md" "HARMONIZATION_SUMMARY.md created"
check_file "FRONTEND_QUICK_REFERENCE.md" "FRONTEND_QUICK_REFERENCE.md created"
check_file "README.md" "README.md created"

echo ""
echo "🧪 Test Scripts"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_file "server/test.sh" "test.sh exists"
check_content "server/test.sh" "api/register" "Test includes register endpoint"
check_content "server/test.sh" "api/next" "Test includes next endpoint"
check_content "server/test.sh" "api/elapsed" "Test includes elapsed endpoint"

echo ""
echo "🔗 Endpoint Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

QUEUE_ENDPOINTS=$(grep -c "router\." server/routes/queueRoutes.js)
echo "📍 Total routes defined: $QUEUE_ENDPOINTS"
if [ "$QUEUE_ENDPOINTS" -ge 50 ]; then
    echo -e "${GREEN}✓${NC} Expected 50+ routes"
    ((SUCCESS++))
else
    echo -e "${YELLOW}⚠${NC} Only found $QUEUE_ENDPOINTS routes"
    ((WARNINGS++))
fi

echo ""
echo "📊 Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "${GREEN}✓ Passed: $SUCCESS${NC}"
if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠ Warnings: $WARNINGS${NC}"
fi
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}✗ Errors: $ERRORS${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo -e "${GREEN}  ✅ All Systems Harmonized!          ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════${NC}"
    echo ""
    echo "🚀 Ready to start the server:"
    echo "   cd server"
    echo "   npm start"
    echo ""
    echo "🌐 Access frontends:"
    echo "   Simulator: http://localhost:3000/simulator"
    echo "   Login:     http://localhost:3000/staff/login.html"
    echo ""
    echo "🧪 Run tests:"
    echo "   ./test.sh"
    echo ""
    exit 0
fi
