#!/bin/bash
# BadWolf Integration Tests — /applications
# @env dev hub
# Testuje: auth flow, CRUD, validace, edge cases
# Vyžaduje: platný JWT token v $TEST_TOKEN nebo .env

set -euo pipefail

BASE_URL=${BADWOLF_URL:-"https://be.s60dev.cz"}
AUTH_URL=${AUTH_URL:-"https://auth.s60dev.cz"}

# Load token z .env pokud není set
if [ -z "${TEST_TOKEN:-}" ] && [ -f "/root/dev/.env" ]; then
  TEST_TOKEN=$(grep "^TEST_TOKEN=" /root/dev/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
fi

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

assert() {
  local id=$1; local desc=$2; local result=$3; local expected=$4
  if [ "$result" = "$expected" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc"
    echo -e "         expected: $expected"
    echo -e "         got:      $result"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local id=$1; local desc=$2; local haystack=$3; local needle=$4
  if echo "$haystack" | grep -q "$needle"; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc (missing: $needle)"
    FAIL=$((FAIL + 1))
  fi
}

echo -e "\n${YELLOW}=== BadWolf Integration — /applications ===${NC}\n"

# -------------------------------------------------------------------
echo -e "${YELLOW}-- AUTH: Unauthorized access --${NC}"

# Without token → 401
code=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL/applications")
assert "bw-app-auth-01" "GET /applications without token → 401" "$code" "401"

# Bad token → 401
code=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: Bearer invalid.token.here" "$BASE_URL/applications")
assert "bw-app-auth-02" "GET /applications with bad token → 401" "$code" "401"

# -------------------------------------------------------------------
echo -e "\n${YELLOW}-- LIST: Pagination --${NC}"

if [ -z "${TEST_TOKEN:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Auth tests — TEST_TOKEN not set (set in /root/dev/.env)"
else
  AUTH_HEADER="Authorization: Bearer $TEST_TOKEN"

  # List returns paginated response
  resp=$(curl -sk -H "$AUTH_HEADER" "$BASE_URL/applications")
  code=$(curl -sk -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/applications")
  assert "bw-app-list-01" "GET /applications → 200" "$code" "200"
  assert_contains "bw-app-list-02" "Response has .data array" "$resp" '"data"'
  assert_contains "bw-app-list-03" "Response has .meta" "$resp" '"meta"'

  # Limit param
  resp_limited=$(curl -sk -H "$AUTH_HEADER" "$BASE_URL/applications?limit=3")
  count=$(echo "$resp_limited" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "-1")
  if [ "$count" -le 3 ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [bw-app-list-04] ?limit=3 respects limit (got $count)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [bw-app-list-04] ?limit=3 returned $count items"
    FAIL=$((FAIL + 1))
  fi

  # -------------------------------------------------------------------
  echo -e "\n${YELLOW}-- DETAIL --${NC}"

  FIRST_ID=$(curl -sk -H "$AUTH_HEADER" "$BASE_URL/applications" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'] if d.get('data') else '')" 2>/dev/null || echo "")

  if [ -n "$FIRST_ID" ]; then
    code=$(curl -sk -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/applications/$FIRST_ID")
    assert "bw-app-detail-01" "GET /applications/:id → 200" "$code" "200"

    resp=$(curl -sk -H "$AUTH_HEADER" "$BASE_URL/applications/$FIRST_ID")
    assert_contains "bw-app-detail-02" "Detail has .id field" "$resp" '"id"'
    assert_contains "bw-app-detail-03" "Detail has .courseDate" "$resp" '"courseDate"'
    assert_contains "bw-app-detail-04" "Detail has .client or .clientId" "$resp" '"client'
  fi

  # 404 for nonexistent
  code=$(curl -sk -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/applications/00000000-0000-0000-0000-000000000000")
  assert "bw-app-detail-05" "GET /applications/nonexistent → 404" "$code" "404"

  # -------------------------------------------------------------------
  echo -e "\n${YELLOW}-- FILTERS --${NC}"

  # Filter by status
  resp_paid=$(curl -sk -H "$AUTH_HEADER" "$BASE_URL/applications?status=paid")
  code_paid=$(curl -sk -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/applications?status=paid")
  assert "bw-app-filter-01" "GET /applications?status=paid → 200" "$code_paid" "200"

  # Filter by invalid status → should return 0 or 400
  code_bad=$(curl -sk -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/applications?status=__invalid__")
  if [ "$code_bad" = "200" ] || [ "$code_bad" = "400" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [bw-app-filter-02] ?status=invalid → $code_bad (handled)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [bw-app-filter-02] ?status=invalid → $code_bad (unexpected)"
    FAIL=$((FAIL + 1))
  fi
fi

# -------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo -e "\n${YELLOW}=== VÝSLEDKY ===${NC}"
echo -e "  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"

[ $FAIL -eq 0 ] && exit 0 || exit 1
