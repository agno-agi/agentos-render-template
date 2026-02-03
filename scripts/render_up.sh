#!/bin/bash

############################################################################
#
#    Agno Render Deployment
#
#    Usage: ./scripts/render_up.sh
#
#    This script guides you through deploying to Render using Blueprints.
#    Render Blueprints require a Git repository connection through the
#    Dashboard for initial setup.
#
############################################################################

set -e

# Colors
ORANGE='\033[38;5;208m'
DIM='\033[2m'
BOLD='\033[1m'
GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo -e "${ORANGE}"
cat << 'BANNER'
     █████╗  ██████╗ ███╗   ██╗ ██████╗
    ██╔══██╗██╔════╝ ████╗  ██║██╔═══██╗
    ███████║██║  ███╗██╔██╗ ██║██║   ██║
    ██╔══██║██║   ██║██║╚██╗██║██║   ██║
    ██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝
    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝
BANNER
echo -e "${NC}"

# Load .env if it exists
if [[ -f .env ]]; then
    set -a
    source .env
    set +a
    echo -e "${DIM}Loaded .env${NC}"
fi

# Check for OPENAI_API_KEY
if [[ -z "$OPENAI_API_KEY" ]]; then
    echo -e "${ORANGE}Warning:${NC} OPENAI_API_KEY not set in environment."
    echo -e "You'll need to set it in the Render Dashboard after deployment."
    echo ""
fi

# Check for render CLI (optional but helpful)
if command -v render &> /dev/null; then
    echo -e "${GREEN}✓${NC} Render CLI detected"

    # Check if logged in
    if render whoami --output json 2>/dev/null | grep -q "email"; then
        RENDER_USER=$(render whoami --output json 2>/dev/null | grep -o '"email":"[^"]*"' | cut -d'"' -f4)
        echo -e "${GREEN}✓${NC} Logged in as: ${BOLD}${RENDER_USER}${NC}"
    else
        echo -e "${DIM}Not logged in. Run 'render login' to authenticate.${NC}"
    fi
else
    echo -e "${DIM}Render CLI not installed (optional).${NC}"
    echo -e "${DIM}Install: https://docs.render.com/cli${NC}"
fi

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}                    Render Deployment Guide${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Render uses ${BOLD}Blueprints${NC} (render.yaml) to define infrastructure."
echo -e "Deployment requires connecting a Git repository through the Dashboard."
echo ""
echo -e "${BOLD}Step 1: Push to GitHub${NC}"
echo -e "  git init"
echo -e "  git add ."
echo -e "  git commit -m 'Initial commit'"
echo -e "  gh repo create agentos-render --public --source=. --push"
echo ""
echo -e "${BOLD}Step 2: Deploy via Render Dashboard${NC}"
echo -e "  1. Go to ${GREEN}https://dashboard.render.com/blueprints${NC}"
echo -e "  2. Click ${BOLD}\"New Blueprint Instance\"${NC}"
echo -e "  3. Connect your GitHub repository"
echo -e "  4. Render will detect render.yaml and show resources to create:"
echo -e "     - ${DIM}agentos-api${NC} (Web Service)"
echo -e "     - ${DIM}agentos-db${NC} (PostgreSQL)"
echo -e "  5. Click ${BOLD}\"Apply\"${NC} to provision resources"
echo ""
echo -e "${BOLD}Step 3: Configure Environment Variables${NC}"
echo -e "  After deployment, go to your service's Environment tab and set:"
echo -e "  - ${BOLD}OPENAI_API_KEY${NC} (required)"
echo -e "  - ${BOLD}EXA_API_KEY${NC} (optional, for web research)"
echo ""
echo -e "${BOLD}Step 4: Connect to Control Plane${NC}"
echo -e "  1. Open ${GREEN}https://os.agno.com${NC}"
echo -e "  2. Click \"Add OS\" → \"Live\""
echo -e "  3. Enter your Render URL: https://agentos-api.onrender.com"
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Useful CLI commands (after deployment):${NC}"
echo -e "  ${DIM}render services${NC}                    # List services"
echo -e "  ${DIM}render logs${NC}                        # View logs (interactive)"
echo -e "  ${DIM}render ssh${NC}                         # SSH into service"
echo -e "  ${DIM}render psql${NC}                        # Connect to database"
echo -e "  ${DIM}render deploys create${NC}              # Trigger new deploy"
echo ""

# Offer to open the dashboard
echo -e "Would you like to open the Render Blueprint page? [y/N] "
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    if command -v open &> /dev/null; then
        open "https://dashboard.render.com/blueprints"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "https://dashboard.render.com/blueprints"
    else
        echo "Open: https://dashboard.render.com/blueprints"
    fi
fi

echo ""
