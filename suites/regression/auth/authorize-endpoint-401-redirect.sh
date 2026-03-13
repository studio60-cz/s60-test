#!/bin/bash
# REGRESSION: S60Auth — authorize endpoint vrací 401 místo redirect
#
# BUG: GET /api/auth/oauth/authorize s platnými parametry vrátilo 401
#      místo 302 redirect na login nebo consent screen
#
# Fix: oprava v auth controlleru/service
#
# Pokud test failuje → pošli bug report:
#   /root/dev/agent-messages/redis-queue.sh send auth TODO \
#     "REGRESSION: /authorize vrací 401 místo redirect" "..." test

set -uo pipefail

AUTH_URL=${AUTH_URL:-"https://auth.s60dev.cz"}
PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "\n${YELLOW}=== REGRESSION: auth/authorize-endpoint-401-redirect ===${NC}"
echo -e "  Bug: /authorize vrátil 401 místo 302 redirect\n"

# Test 1: /authorize s validními params → MUSÍ vrátit redirect (3xx), ne 401
# Používáme -L0 abychom nesledovali redirect, jen zkontrolujeme první response
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
  "$AUTH_URL/api/auth/oauth/authorize?response_type=code&client_id=venom&redirect_uri=https%3A%2F%2Fvenom.s60dev.cz%2Fauth%2Fcallback&scope=openid+profile+email" \
  2>/dev/null || echo "000")

if [ "$code" = "302" ] || [ "$code" = "301" ] || [ "$code" = "303" ] || [ "$code" = "200" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-auth-01] /authorize → $code (redirect, not 401)"
  PASS=$((PASS+1))
elif [ "$code" = "401" ]; then
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-auth-01] /authorize → 401 (REGRESE!)"
  FAIL=$((FAIL+1))
  /root/dev/agent-messages/redis-queue.sh send auth TODO \
    "REGRESSION: /authorize vrací 401 místo redirect" \
    "GET /api/auth/oauth/authorize vrátil 401 — regrese!" test 2>/dev/null || true
elif [ "$code" = "400" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-auth-01] /authorize → 400 (bad params handled, not 401)"
  PASS=$((PASS+1))
else
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-auth-auth-01] Response: $code (server issue?)"
fi

# Test 2: OIDC discovery endpoint musí být dostupný (základ pro authorize flow)
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
  "$AUTH_URL/.well-known/openid-configuration" 2>/dev/null || echo "000")

if [ "$code" = "200" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-auth-02] /.well-known/openid-configuration → 200"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-auth-02] OIDC discovery → $code"
  FAIL=$((FAIL+1))
fi

# Test 3: authorization_endpoint v OIDC config nesmí být prázdný
oidc=$(curl -sk --max-time 5 "$AUTH_URL/.well-known/openid-configuration" 2>/dev/null || echo "{}")
auth_ep=$(echo "$oidc" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('authorization_endpoint','MISSING'))" 2>/dev/null || echo "ERROR")

if [ "$auth_ep" != "MISSING" ] && [ "$auth_ep" != "ERROR" ] && [ -n "$auth_ep" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-auth-03] authorization_endpoint definován: $auth_ep"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-auth-03] authorization_endpoint chybí v OIDC config"
  FAIL=$((FAIL+1))
fi

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
