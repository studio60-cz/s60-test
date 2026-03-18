#!/bin/bash
# Pulse Integration Tests
# @env dev hub
#
# Pokrývá: auth guard, output sub-endpointy, M2M API klíč
#
# Requires: PULSE_API_KEY v /root/dev/.env nebo env proměnná
#   Key: qa-pulse-admin-test (scope: pulse:admin) — vytvořen main agentem
#
# Pokud test failuje → pošli bug report:
#   /root/dev/agent-messages/send-message.sh pulse TODO "REGRESSION: pulse/$id" "Popis" test

set -uo pipefail

ENV=${1:-dev}
case "$ENV" in
  dev)  BASE_URL="https://pulse.s60dev.cz" ;;
  hub)  BASE_URL="https://pulse.s60hub.cz" ;;
  *)    echo "Unknown env: $ENV (dev|hub)"; exit 1 ;;
esac

PASS=0; FAIL=0; SKIP=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Načti API klíč
_e() { grep "^$1=" /root/dev/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo ""; }
PULSE_API_KEY=${PULSE_API_KEY:-$(_e PULSE_QA_API_KEY)}

assert_http() {
  local id=$1 desc=$2 code=$3 expected=$4
  if [ "$code" = "$expected" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc → $code"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc → $code (expected: $expected)"
    FAIL=$((FAIL+1))
    /root/dev/agent-messages/send-message.sh pulse TODO \
      "REGRESSION: pulse/$id selhalo" \
      "$desc: HTTP $code (očekáváno $expected). ENV: $ENV" test 2>/dev/null || true
  fi
}

echo -e "\n${YELLOW}=== Pulse Integration Tests ($BASE_URL) ===${NC}\n"

# ---------------------------------------------------------------
echo -e "${YELLOW}-- Auth guard --${NC}"

# Bez tokenu → 401
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL/api/outputs" 2>/dev/null || echo "000")
assert_http "pulse-int-auth-01" "GET /api/outputs bez tokenu → 401" "$code" "401"

code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL/api/projects" 2>/dev/null || echo "000")
assert_http "pulse-int-auth-02" "GET /api/projects bez tokenu → 401" "$code" "401"

# GET /api/outputs/:id neexistuje (NestJS 404 z routeru — correct behavior)
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL/api/outputs/1" 2>/dev/null || echo "000")
assert_http "pulse-int-auth-03" "GET /api/outputs/:id → 404 (endpoint neexistuje — by design)" "$code" "404"

# ---------------------------------------------------------------
echo -e "\n${YELLOW}-- Authenticated endpoints --${NC}"

if [ -z "${PULSE_API_KEY:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Auth testy — PULSE_QA_API_KEY not set v /root/dev/.env"
  SKIP=$((SKIP+3))
else
  AUTH_HEADER="Authorization: Bearer $PULSE_API_KEY"

  # Projects list
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 -H "$AUTH_HEADER" "$BASE_URL/api/projects" 2>/dev/null || echo "000")
  assert_http "pulse-int-proj-01" "GET /api/projects s tokenem → 200" "$code" "200"

  # Outputs list
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 -H "$AUTH_HEADER" "$BASE_URL/api/outputs" 2>/dev/null || echo "000")
  assert_http "pulse-int-out-01" "GET /api/outputs s tokenem → 200" "$code" "200"

  # Clients list
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 -H "$AUTH_HEADER" "$BASE_URL/api/clients" 2>/dev/null || echo "000")
  assert_http "pulse-int-cli-01" "GET /api/clients s tokenem → 200" "$code" "200"

  # Output sub-endpointy (pokud existuje nějaký output)
  FIRST_OUTPUT=$(curl -sk -H "$AUTH_HEADER" "$BASE_URL/api/outputs" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); items=d if isinstance(d,list) else d.get('data',[]); print(items[0]['id'] if items else '')" 2>/dev/null || echo "")

  if [ -n "$FIRST_OUTPUT" ]; then
    echo -e "\n${YELLOW}-- Output sub-endpointy (id: $FIRST_OUTPUT) --${NC}"
    for fmt in markdown html json pdf; do
      code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 -H "$AUTH_HEADER" \
        "$BASE_URL/api/outputs/$FIRST_OUTPUT/$fmt" 2>/dev/null || echo "000")
      assert_http "pulse-int-out-fmt-$fmt" "GET /api/outputs/:id/$fmt → 200" "$code" "200"
    done
  else
    echo -e "  ${YELLOW}⏭ SKIP${NC} Output sub-endpointy — žádné outputs v DB"
    SKIP=$((SKIP+4))
  fi
fi

# ---------------------------------------------------------------
TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}  |  SKIP: ${YELLOW}$SKIP${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
