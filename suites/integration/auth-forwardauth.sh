#!/bin/bash
# Integration Tests — S60Auth ForwardAuth
# @env dev hub
# Testuje: token flow, header injection, invalidation
# Vyžaduje: platný JWT token v $TEST_TOKEN

set -euo pipefail

BASE_URL=${BADWOLF_URL:-"https://api.s60dev.cz"}
AUTH_URL=${AUTH_URL:-"https://auth.s60dev.cz"}

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
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc (expected: $expected, got: $result)"
    FAIL=$((FAIL + 1))
  fi
}

echo -e "\n${YELLOW}=== Integration — S60Auth ForwardAuth ===${NC}\n"

# -------------------------------------------------------------------
echo -e "${YELLOW}-- Unauthenticated requests --${NC}"

# No token
code=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL/applications")
assert "fa-01" "No token → 401" "$code" "401"

# Malformed token (not JWT)
code=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: Bearer notajwt" "$BASE_URL/applications")
assert "fa-02" "Malformed token → 401" "$code" "401"

# Wrong scheme (Basic instead of Bearer)
code=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: Basic dXNlcjpwYXNz" "$BASE_URL/applications")
assert "fa-03" "Basic auth (wrong scheme) → 401" "$code" "401"

# Expired/tampered JWT structure (valid base64 but wrong signature)
FAKE_JWT="eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjMiLCJlbWFpbCI6InRlc3RAdGVzdC5jb20ifQ.invalidsignature"
code=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $FAKE_JWT" "$BASE_URL/applications")
assert "fa-04" "JWT with invalid signature → 401" "$code" "401"

# -------------------------------------------------------------------
echo -e "\n${YELLOW}-- Public endpoints (no auth) --${NC}"

# /courses a /locations jsou public
code=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL/courses")
assert "fa-05" "GET /courses without token → 200 (public)" "$code" "200"

code=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL/locations")
assert "fa-06" "GET /locations without token → 200 (public)" "$code" "200"

code=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL/health")
assert "fa-07" "GET /health without token → 200 (public)" "$code" "200"

# -------------------------------------------------------------------
echo -e "\n${YELLOW}-- Auth with valid token --${NC}"

if [ -z "${TEST_TOKEN:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Valid token tests — TEST_TOKEN not set"
  echo -e "  ${YELLOW}  Hint:${NC} Add TEST_TOKEN=<jwt> to /root/dev/.env"
else
  # Valid token → 200
  code=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TEST_TOKEN" "$BASE_URL/applications")
  assert "fa-08" "Valid token → 200" "$code" "200"

  # ForwardAuth injects X-User-Id header (via debug echo endpoint if exists)
  # Pokud BadWolf má /debug/headers endpoint, ověříme hlavičky
  debug_code=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TEST_TOKEN" "$BASE_URL/debug/headers" 2>/dev/null || echo "404")
  if [ "$debug_code" = "200" ]; then
    resp=$(curl -sk -H "Authorization: Bearer $TEST_TOKEN" "$BASE_URL/debug/headers")
    if echo "$resp" | grep -qi "x-user-id"; then
      echo -e "  ${GREEN}✅ PASS${NC} [fa-09] X-User-Id header injected by ForwardAuth"
      PASS=$((PASS + 1))
    else
      echo -e "  ${RED}❌ FAIL${NC} [fa-09] X-User-Id header not found in debug headers"
      FAIL=$((FAIL + 1))
    fi
  else
    echo -e "  ${YELLOW}⏭ SKIP${NC} [fa-09] /debug/headers not available ($debug_code)"
  fi
fi

# -------------------------------------------------------------------
# Auth health — ForwardAuth service itself
echo -e "\n${YELLOW}-- ForwardAuth service health --${NC}"

# ForwardAuth Express service is internal, testujeme přes Nginx
# Pokud auth.{domain}/api/auth/forward endpoint existuje
forward_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "$AUTH_URL/api/health" 2>/dev/null || echo "000")
assert "fa-10" "S60Auth /api/health → 200" "$forward_code" "200"

# -------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo -e "\n${YELLOW}=== VÝSLEDKY ===${NC}"
echo -e "  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"

[ $FAIL -eq 0 ] && exit 0 || exit 1
