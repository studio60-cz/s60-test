#!/bin/bash
# REGRESSION: S60Auth ForwardAuth — bad/expired tokens MUSÍ vracet 401
# @env dev hub prod
#
# BUG (potenciální): ForwardAuth mohl propustit request s malformed JWT
#       nebo expirovaným tokenem který ještě byl v Redis cache.
#
# Fix: ForwardAuth kontroluje token expiration i při Redis cache hit.
#
# Pokud tento test failuje → pošli bug report authu:
#   /root/dev/agent-messages/redis-queue.sh send auth TODO "REGRESSION: ForwardAuth propouští bad token" "..." test

set -euo pipefail

BASE_URL=${BADWOLF_URL:-"https://be.s60dev.cz"}

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

echo -e "\n${YELLOW}=== REGRESSION: auth/bad-token-rejection ===${NC}"
echo -e "  Bug: ForwardAuth must reject all invalid tokens\n"

# No token → 401
code=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE_URL/applications")
assert "reg-auth-01" "No token → 401" "$code" "401"

# Malformed JWT (not even base64) → 401
code=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer thisisnotajwt" "$BASE_URL/applications")
assert "reg-auth-02" "Malformed token → 401" "$code" "401"

# Valid-looking JWT structure but wrong signature → 401
FAKE_JWT="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0IiwiZXhwIjo5OTk5OTk5OTk5fQ.fakesignature"
code=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $FAKE_JWT" "$BASE_URL/applications")
assert "reg-auth-03" "Valid-structure JWT with fake signature → 401" "$code" "401"

# Expired JWT (exp in past) — manually crafted
# Header: {"alg":"RS256"} Payload: {"sub":"test","exp":1000000000} (year 2001)
EXPIRED_JWT="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0IiwiZXhwIjoxMDAwMDAwMDAwfQ.fakesig"
code=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $EXPIRED_JWT" "$BASE_URL/applications")
assert "reg-auth-04" "Expired JWT → 401" "$code" "401"

# Bearer with empty string → 401
code=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer " "$BASE_URL/applications")
assert "reg-auth-05" "Bearer with empty value → 401" "$code" "401"

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
