#!/bin/bash

############################################################################
#
#    Agno Render Deployment (API-based)
#
#    Usage: ./scripts/render_up.sh
#
#    Prerequisites:
#      - RENDER_API_KEY set in environment (get from Dashboard > Account Settings > API Keys)
#      - OPENAI_API_KEY set in environment
#      - GitHub repo URL for the project
#
#    Note: Free-tier services cannot be created via API. This script uses paid plans.
#
############################################################################

set -e

# Colors
ORANGE='\033[38;5;208m'
DIM='\033[2m'
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

RENDER_API="https://api.render.com/v1"

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

# Preflight checks
if [[ -z "$RENDER_API_KEY" ]]; then
    echo -e "${RED}Error:${NC} RENDER_API_KEY not set."
    echo ""
    echo "To get your API key:"
    echo "  1. Go to https://dashboard.render.com/u/settings#api-keys"
    echo "  2. Click 'Create API Key'"
    echo "  3. Export it: export RENDER_API_KEY='rnd_...'"
    echo ""
    exit 1
fi

if [[ -z "$OPENAI_API_KEY" ]]; then
    echo -e "${RED}Error:${NC} OPENAI_API_KEY not set."
    exit 1
fi

# Get owner ID
echo -e "${BOLD}Fetching account info...${NC}"
OWNER_RESPONSE=$(curl -s -X GET "$RENDER_API/owners" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Accept: application/json")

OWNER_ID=$(echo "$OWNER_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -z "$OWNER_ID" ]]; then
    echo -e "${RED}Error:${NC} Could not fetch owner ID. Check your API key."
    echo "$OWNER_RESPONSE"
    exit 1
fi
echo -e "${GREEN}✓${NC} Owner ID: $OWNER_ID"

# Check for existing services
echo -e "${BOLD}Checking for existing services...${NC}"
EXISTING=$(curl -s -X GET "$RENDER_API/services?name=agentos-api&limit=1" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Accept: application/json")

if echo "$EXISTING" | grep -q '"name":"agentos-api"'; then
    echo -e "${ORANGE}Warning:${NC} agentos-api service already exists."
    echo -e "Delete it first or use a different name."
    exit 1
fi

# Get GitHub repo URL
echo ""
REPO_URL=$(git remote get-url origin 2>/dev/null | sed 's/git@github.com:/https:\/\/github.com\//' | sed 's/\.git$//')
if [[ -z "$REPO_URL" ]]; then
    echo -e "Enter your GitHub repo URL (e.g., https://github.com/user/repo):"
    read -r REPO_URL
fi
echo -e "${GREEN}✓${NC} Repo: $REPO_URL"

# Get default branch
DEFAULT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
echo -e "${GREEN}✓${NC} Branch: $DEFAULT_BRANCH"

# Step 1: Create PostgreSQL database
echo ""
echo -e "${BOLD}Creating PostgreSQL database...${NC}"

DB_RESPONSE=$(curl -s -X POST "$RENDER_API/postgres" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"agentos-db\",
        \"ownerId\": \"$OWNER_ID\",
        \"plan\": \"basic_256mb\",
        \"version\": \"16\",
        \"region\": \"oregon\"
    }")

DB_ID=$(echo "$DB_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -z "$DB_ID" ]]; then
    echo -e "${RED}Error:${NC} Failed to create database."
    echo "$DB_RESPONSE"
    exit 1
fi
echo -e "${GREEN}✓${NC} Database created: $DB_ID"

# Wait for database to be ready and get connection info
echo -e "${DIM}Waiting for database to initialize...${NC}"
sleep 20

# Get database info
DB_INFO=$(curl -s -X GET "$RENDER_API/postgres/$DB_ID" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Accept: application/json")

DB_NAME=$(echo "$DB_INFO" | grep -o '"databaseName":"[^"]*"' | cut -d'"' -f4)
DB_USER=$(echo "$DB_INFO" | grep -o '"databaseUser":"[^"]*"' | cut -d'"' -f4)

# Get connection string for password and internal host
CONN_INFO=$(curl -s -X GET "$RENDER_API/postgres/$DB_ID/connection-info" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Accept: application/json")

DB_PASS=$(echo "$CONN_INFO" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)
# Extract internal host from internalConnectionString (format: postgresql://user:pass@host/db)
INTERNAL_CONN=$(echo "$CONN_INFO" | grep -o '"internalConnectionString":"[^"]*"' | cut -d'"' -f4)
DB_HOST=$(echo "$INTERNAL_CONN" | sed 's/.*@//' | sed 's/\/.*//')

if [[ -z "$DB_HOST" || -z "$DB_PASS" ]]; then
    echo -e "${RED}Error:${NC} Could not get database connection info."
    echo "$CONN_INFO"
    exit 1
fi

echo -e "${GREEN}✓${NC} Database ready: $DB_HOST"

# Step 2: Create Web Service (without env vars - they're added separately)
echo ""
echo -e "${BOLD}Creating web service...${NC}"

SERVICE_RESPONSE=$(curl -s -X POST "$RENDER_API/services" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"agentos-api\",
        \"ownerId\": \"$OWNER_ID\",
        \"type\": \"web_service\",
        \"serviceDetails\": {
            \"env\": \"docker\",
            \"plan\": \"starter\",
            \"region\": \"oregon\",
            \"dockerfilePath\": \"./Dockerfile\",
            \"dockerCommand\": \"uvicorn app.main:app --host 0.0.0.0 --port 8000\",
            \"healthCheckPath\": \"/docs\",
            \"disk\": {
                \"name\": \"agentos-data\",
                \"mountPath\": \"/data\",
                \"sizeGB\": 1
            }
        },
        \"repo\": \"$REPO_URL\",
        \"branch\": \"$DEFAULT_BRANCH\",
        \"autoDeploy\": \"yes\"
    }")

SERVICE_ID=$(echo "$SERVICE_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -z "$SERVICE_ID" ]]; then
    echo -e "${RED}Error:${NC} Failed to create service."
    echo "$SERVICE_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓${NC} Service created: $SERVICE_ID"

# Step 3: Add environment variables
echo ""
echo -e "${BOLD}Configuring environment variables...${NC}"

ENV_VARS='[
    {"key": "PORT", "value": "8000"},
    {"key": "DATA_DIR", "value": "/data"},
    {"key": "DB_DRIVER", "value": "postgresql+psycopg"},
    {"key": "WAIT_FOR_DB", "value": "True"},
    {"key": "OPENAI_API_KEY", "value": "'"$OPENAI_API_KEY"'"},
    {"key": "DB_HOST", "value": "'"$DB_HOST"'"},
    {"key": "DB_PORT", "value": "5432"},
    {"key": "DB_USER", "value": "'"$DB_USER"'"},
    {"key": "DB_PASS", "value": "'"$DB_PASS"'"},
    {"key": "DB_DATABASE", "value": "'"$DB_NAME"'"}'

# Add EXA_API_KEY if set
if [[ -n "$EXA_API_KEY" ]]; then
    ENV_VARS="${ENV_VARS},
    {\"key\": \"EXA_API_KEY\", \"value\": \"$EXA_API_KEY\"}"
fi

ENV_VARS="${ENV_VARS}]"

ENV_RESPONSE=$(curl -s -X PUT "$RENDER_API/services/$SERVICE_ID/env-vars" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$ENV_VARS")

if echo "$ENV_RESPONSE" | grep -q '"key"'; then
    echo -e "${GREEN}✓${NC} Environment variables configured"
else
    echo -e "${ORANGE}Warning:${NC} Could not verify env vars were set"
    echo "$ENV_RESPONSE"
fi

# Step 4: Trigger deployment
echo ""
echo -e "${BOLD}Triggering deployment...${NC}"

DEPLOY_RESPONSE=$(curl -s -X POST "$RENDER_API/services/$SERVICE_ID/deploys" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"clearCache": "do_not_clear"}')

DEPLOY_ID=$(echo "$DEPLOY_RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -n "$DEPLOY_ID" ]]; then
    echo -e "${GREEN}✓${NC} Deployment triggered: $DEPLOY_ID"
else
    echo -e "${DIM}Auto-deploy will handle deployment${NC}"
fi

# Get final service URL
sleep 3
SERVICE_INFO=$(curl -s -X GET "$RENDER_API/services/$SERVICE_ID" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Accept: application/json")

SERVICE_URL=$(echo "$SERVICE_INFO" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                      Deployment Complete!${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Service URL: ${BOLD}${SERVICE_URL:-https://agentos-api.onrender.com}${NC}"
echo -e "API Docs:    ${BOLD}${SERVICE_URL:-https://agentos-api.onrender.com}/docs${NC}"
echo ""
echo -e "Database ID: ${DIM}$DB_ID${NC}"
echo -e "Service ID:  ${DIM}$SERVICE_ID${NC}"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo -e "  1. Wait for deployment to complete (~5 minutes)"
echo -e "  2. Connect to control plane: ${GREEN}https://os.agno.com${NC}"
echo -e "     → Add OS → Live → Enter your service URL"
echo ""
echo -e "${BOLD}Useful commands:${NC}"
echo -e "  ${DIM}render services${NC}              # List services"
echo -e "  ${DIM}render logs${NC}                  # View logs"
echo -e "  ${DIM}render ssh${NC}                   # SSH into service"
echo -e "  ${DIM}render psql${NC}                  # Connect to database"
echo ""
