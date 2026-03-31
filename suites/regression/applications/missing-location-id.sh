#!/bin/bash
# REGRESSION: BadWolf — GET /applications with missing courseDate.locationId
# @env dev hub prod
#
# BUG: BadWolf vrací 500 pokud courseDate.locationId neexistuje v DB
#      Místo 500 se očekává: buď 200 s null/empty locationId, nebo 404
#
# Jak reprodukovat původní bug:
#   - Existuje application s courseDate kde locationId je NULL nebo orphaned FK
#   - GET /applications nebo GET /applications/:id → 500 Internal Server Error
#
# Fix: BadWolf by měl gracefully handlovat chybějící locationId (LEFT JOIN, nullable)
#
# Pokud tento test failuje → pošli bug report:
#   /root/dev/agent-messages/redis-queue.sh send badwolf TODO "REGRESSION: missing locationId → 500" "..." test

set -euo pipefail

BASE_URL=${BADWOLF_URL:-"https://api.s60dev.cz"}

if [ -z "${TEST_TOKEN:-}" ] && [ -f "/root/dev/.env" ]; then
  TEST_TOKEN=$(grep "^TEST_TOKEN=" /root/dev/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
fi

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

assert() {
  local id=$1 desc=$2 result=$3 expected=$4
  if [ "$result" = "$expected" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc"; PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc (expected: $expected, got: $result)"; FAIL=$((FAIL+1))
  fi
}

echo -e "\n${YELLOW}=== REGRESSION: applications/missing-location-id ===${NC}"
echo -e "  Bug: GET /applications → 500 when courseDate.locationId missing in DB\n"

if [ -z "${TEST_TOKEN:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} TEST_TOKEN not set"
  exit 0
fi

AUTH_HEADER="Authorization: Bearer $TEST_TOKEN"

# Regression test: GET /applications nesmí vrátit 500
code=$(curl -sk -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/applications")
assert "reg-app-loc-01" "GET /applications → NOT 500 (graceful null locationId)" "$code" "200"

# GET /applications?limit=50 — wider scan, still no 500
code=$(curl -sk -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/applications?limit=50")
assert "reg-app-loc-02" "GET /applications?limit=50 → NOT 500" "$code" "200"

# Response musí být validní JSON s .data polem
resp=$(curl -sk -H "$AUTH_HEADER" "$BASE_URL/applications")
if echo "$resp" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d.get('data'), list)" 2>/dev/null; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-app-loc-03] Response is valid JSON with .data array"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-app-loc-03] Response is not valid JSON or missing .data"
  FAIL=$((FAIL+1))
fi

# Každý item v .data musí mít courseDate (může mít null locationId, ale ne undefined)
resp=$(curl -sk -H "$AUTH_HEADER" "$BASE_URL/applications?limit=10")
has_course_date=$(echo "$resp" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d.get('data',[])
if not items:
    print('skip')
else:
    bad=[i for i in items if 'courseDate' not in i]
    print('ok' if not bad else f'missing in {len(bad)} items')
" 2>/dev/null || echo "error")

if [ "$has_course_date" = "skip" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-app-loc-04] No applications in DB to validate"
elif [ "$has_course_date" = "ok" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-app-loc-04] All items have .courseDate field"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-app-loc-04] courseDate missing: $has_course_date"
  FAIL=$((FAIL+1))
fi

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
