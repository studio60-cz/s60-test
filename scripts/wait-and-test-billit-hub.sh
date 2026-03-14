#!/bin/bash
# Čeká na Billit HUB deploy a pak spustí regression suite (F-162)
# Spouští se po notifikaci od Sentinel/billit agenta
#
# Usage: bash wait-and-test-billit-hub.sh [timeout_minutes]
#
# Výstup: reportuje PM + billit agentovi

set -uo pipefail

BILLIT_HUB_BASE="https://billit.s60hub.cz"
BILLIT_HUB_API="${BILLIT_HUB_BASE}/api"  # Nginx: /api/ → billit-api container
TIMEOUT_MIN=${1:-20}
TIMEOUT_SEC=$((TIMEOUT_MIN * 60))
POLL_INTERVAL=15
ELAPSED=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

echo -e "${BLUE}=== Wait-and-test: Billit HUB (F-162 regression) ===${NC}"
echo -e "  Base: $BILLIT_HUB_BASE | API: $BILLIT_HUB_API"
echo -e "  Timeout: ${TIMEOUT_MIN}m | Poll: ${POLL_INTERVAL}s"
echo ""

# --- Čekej na health endpoint (health je na base URL bez /api) ---
echo -e "${YELLOW}Čekám na ${BILLIT_HUB_BASE}/health ...${NC}"
while true; do
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$BILLIT_HUB_BASE/health" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    echo -e "${GREEN}✅ Billit HUB je up (${ELAPSED}s)${NC}"
    break
  fi

  ELAPSED=$((ELAPSED + POLL_INTERVAL))
  if [ $ELAPSED -ge $TIMEOUT_SEC ]; then
    echo -e "${RED}❌ Timeout po ${TIMEOUT_MIN}m — Billit HUB nepřišel online (poslední HTTP: $code)${NC}"
    /root/dev/agent-messages/redis-queue.sh send billit INFO \
      "Billit HUB deploy timeout — testy neproběhly" \
      "wait-and-test-billit-hub.sh: ${BILLIT_HUB_BASE}/health neodpovídal po ${TIMEOUT_MIN}m. Spusť ručně: BILLIT_URL=$BILLIT_HUB_API bash suites/regression/billit/api-key-scope-enforcement.sh" test 2>/dev/null || true
    /root/dev/agent-messages/redis-queue.sh send pm INFO \
      "Billit HUB deploy timeout" \
      "Billit na $BILLIT_HUB_BASE nepřišel online do ${TIMEOUT_MIN}m — F-162 regression testy neproběhly." test 2>/dev/null || true
    exit 1
  fi

  echo -e "  [${ELAPSED}s/${TIMEOUT_SEC}s] HTTP $code — čekám..."
  sleep $POLL_INTERVAL
done

# --- Spusť regression suite s /api base URL ---
echo -e "\n${YELLOW}Spouštím F-162 regression suite (commit e059878)...${NC}"
echo -e "  API URL: $BILLIT_HUB_API\n"

BILLIT_URL="$BILLIT_HUB_API" bash /root/dev/s60-test/suites/regression/billit/api-key-scope-enforcement.sh
EXIT_CODE=$?

# --- Report ---
if [ $EXIT_CODE -eq 0 ]; then
  STATUS="PASS"
  EMOJI="✅"
else
  STATUS="FAIL"
  EMOJI="❌"
fi

/root/dev/agent-messages/redis-queue.sh send billit INFO \
  "F-162 regression na HUB: $STATUS" \
  "$EMOJI Billit HUB — API key scope enforcement regression: $STATUS
Commits: 070f0d3 + e059878
API URL: $BILLIT_HUB_API
Spuštěno po Sentinel deployi." test 2>/dev/null || true

/root/dev/agent-messages/redis-queue.sh send pm INFO \
  "Billit HUB regression: $STATUS (F-162)" \
  "$EMOJI Billit HUB post-deploy regression test: $STATUS
Suite: api-key-scope-enforcement (F-162)
API URL: $BILLIT_HUB_API" test 2>/dev/null || true

exit $EXIT_CODE
