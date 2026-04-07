#!/bin/bash
# =============================================================================
#  Meru DQMS — Database Switcher
#  Usage:
#    bash db-switch.sh local     → switch to local PostgreSQL
#    bash db-switch.sh render    → switch to Render PostgreSQL
#    bash db-switch.sh show      → show current .env
#    bash db-switch.sh help      → show this help
# =============================================================================

ENV_FILE="/home/haron/projec/meru-dqms/server/.env"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ── Functions ─────────────────────────────────────────────────────────────────

use_local() {
    cat > "$ENV_FILE" << 'EOF'
PORT=3000
DATABASE_URL=postgresql://haron:92949698@localhost:5432/meru-dqms
EOF
    echo -e "${GREEN}✅  Switched to LOCAL database${NC}"
    echo -e "${CYAN}Host    : localhost:5432${NC}"
    echo -e "${CYAN}Database: meru-dqms${NC}"
    echo -e "${CYAN}User    : haron${NC}"
}

use_render() {
    cat > "$ENV_FILE" << 'EOF'
PORT=3000
DATABASE_URL=postgresql://haron:9URqzsyejraYhaT3uDusQwc1ALSDLmSR@dpg-d6rkh67fte5s73ep1300-a.oregon-postgres.render.com/meruqms
EOF
    echo -e "${GREEN}✅  Switched to RENDER database${NC}"
    echo -e "${CYAN}Host    : dpg-d6rkh67fte5s73ep1300-a.oregon-postgres.render.com${NC}"
    echo -e "${CYAN}Database: meruqms${NC}"
    echo -e "${CYAN}User    : haron${NC}"
}

show_current() {
    if [ -f "$ENV_FILE" ]; then
        echo -e "${YELLOW}📄  Current .env:${NC}"
        cat "$ENV_FILE"
        echo ""
        # Detect which DB is active
        if grep -q "localhost" "$ENV_FILE"; then
            echo -e "${GREEN}▶  Active: LOCAL${NC}"
        elif grep -q "render.com" "$ENV_FILE"; then
            echo -e "${GREEN}▶  Active: RENDER${NC}"
        else
            echo -e "${YELLOW}▶  Active: UNKNOWN${NC}"
        fi
    else
        echo -e "${RED}❌  .env file not found at $ENV_FILE${NC}"
    fi
}

show_help() {
    echo -e "${CYAN}"
    echo "============================================="
    echo "  Meru DQMS — Database Switcher"
    echo "============================================="
    echo -e "${NC}"
    echo "  bash db-switch.sh local    Switch to local PostgreSQL"
    echo "  bash db-switch.sh render   Switch to Render PostgreSQL"
    echo "  bash db-switch.sh show     Show current .env"
    echo "  bash db-switch.sh help     Show this help"
    echo ""
    echo "  After switching, restart the server:"
    echo "    cd /home/haron/projec/meru-dqms/server && npm start"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
case "$1" in
    local)
        use_local
        show_current
        echo ""
        echo -e "${YELLOW}▶  Run: cd /home/haron/projec/meru-dqms/server && npm start${NC}"
        ;;
    render)
        use_render
        show_current
        echo ""
        echo -e "${YELLOW}▶  Run: cd /home/haron/projec/meru-dqms/server && npm start${NC}"
        ;;
    show)
        show_current
        ;;
    help|*)
        show_help
        ;;
esac
