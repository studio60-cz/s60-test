#!/bin/bash
# Regression: Kaizen F-340 — Auth Docker healthcheck
# @env hub prod
#
# Ověřuje že auth /api/health endpoint vrací 200
# Commit: 7cf35cb (auth agent)

set -uo pipefail

ENV=${1:-hub}
case "$ENV" in
  hub)  AUTH_URL="https://auth.s60hub.cz" ;;
  prod) AUTH_URL="https://auth.studio60.cz" ;;
  *)    echo "Unknown env: $ENV (hub|prod)"; exit 1 ;;
esac

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

assert() {
  local id=$1 desc=$2 ok=$3
  if [ "$ok" = "1" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc"
    FAIL=$((FAIL+1))
    /root/dev/agent-messages/send-message.sh auth TODO \
      "REGRESSION: auth/F-340 — $id selhalo" \
      "$desc. ENV: $ENV, AUTH_URL: $AUTH_URL" test 2>/dev/null || true
  fi
}

echo -e "\n${YELLOW}=== Regression F-340: auth Docker healthcheck ($AUTH_URL) ===${NC}\n"

# /api/health → 200
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$AUTH_URL/api/health" 2>/dev/null || echo "000")
assert "f340-api-health" "GET /api/health → 200" "$([ "$code" = "200" ] && echo 1 || echo 0)"

# /health (root) — frontend nebo redirect
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$AUTH_URL/health" 2>/dev/null || echo "000")
assert "f340-root-health-not-500" "GET /health nekončí 500 (frontend OK)" \
  "$([ "$code" != "500" ] && [ "$code" != "000" ] && echo 1 || echo 0)"

echo -e "\n  PASS: ${GREEN}$PASS${NC} / $((PASS+FAIL))  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
