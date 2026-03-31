#!/bin/bash
# REGRESSION: BadWolf JwtOrApiKeyGuard — bad/expired tokens MUSÍ vracet 401
# @env dev hub prod
#
# BUG (potenciální): JwtOrApiKeyGuard mohl propustit request s malformed JWT
#       nebo expirovaným tokenem.
#
# Fix: JwtOrApiKeyGuard (DEC-001) validuje JWT podpis + Redis blacklist.
# Testovaný endpoint: PATCH /products/:id (chráněný JwtOrApiKeyGuard)
# Pozor: GET /applications je @Public() — nevhodný pro tento test.
#
# Pokud tento test failuje → zkontroluj BadWolf JwtOrApiKeyGuard implementaci:
#   /root/dev/agent-messages/send-message.sh badwolf TODO "REGRESSION: JwtOrApiKeyGuard propouští bad token" "..." test

set -euo pipefail

BASE_URL=${BADWOLF_URL:-"https://api.s60dev.cz"}
# Chráněný endpoint — vyžaduje platný JWT nebo X-Api-Key (DEC-001)
PROTECTED_PATH="/products/00000000-0000-0000-0000-000000000001"

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
echo -e "  Bug: JwtOrApiKeyGuard must reject all invalid tokens on protected endpoints\n"
echo -e "  Endpoint: PATCH ${BASE_URL}${PROTECTED_PATH}\n"

# No token → 401
code=$(curl -sk -o /dev/null -w "%{http_code}" -X PATCH "$BASE_URL$PROTECTED_PATH" -H "Content-Type: application/json" -d '{}')
assert "reg-auth-01" "No token → 401" "$code" "401"

# Malformed JWT (not even base64) → 401
code=$(curl -sk -o /dev/null -w "%{http_code}" -X PATCH \
  -H "Authorization: Bearer thisisnotajwt" \
  -H "Content-Type: application/json" -d '{}' \
  "$BASE_URL$PROTECTED_PATH")
assert "reg-auth-02" "Malformed token → 401" "$code" "401"

# Valid-looking JWT structure but wrong signature → 401
FAKE_JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0IiwiZXhwIjo5OTk5OTk5OTk5fQ.fakesignature"
code=$(curl -sk -o /dev/null -w "%{http_code}" -X PATCH \
  -H "Authorization: Bearer $FAKE_JWT" \
  -H "Content-Type: application/json" -d '{}' \
  "$BASE_URL$PROTECTED_PATH")
assert "reg-auth-03" "Valid-structure JWT with fake signature → 401" "$code" "401"

# Expired JWT (exp in past) — manually crafted HS256
# Header: {"alg":"HS256"} Payload: {"sub":"test","exp":1000000000} (year 2001)
EXPIRED_JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ0ZXN0IiwiZXhwIjoxMDAwMDAwMDAwfQ.fakesig"
code=$(curl -sk -o /dev/null -w "%{http_code}" -X PATCH \
  -H "Authorization: Bearer $EXPIRED_JWT" \
  -H "Content-Type: application/json" -d '{}' \
  "$BASE_URL$PROTECTED_PATH")
assert "reg-auth-04" "Expired JWT → 401" "$code" "401"

# Bearer with empty string → 401
code=$(curl -sk -o /dev/null -w "%{http_code}" -X PATCH \
  -H "Authorization: Bearer " \
  -H "Content-Type: application/json" -d '{}' \
  "$BASE_URL$PROTECTED_PATH")
assert "reg-auth-05" "Bearer with empty value → 401" "$code" "401"

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
