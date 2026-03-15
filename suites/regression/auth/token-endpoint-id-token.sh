#!/bin/bash
# REGRESSION: S60Auth — token endpoint nevrací id_token když chybí OIDC env var
# @env dev hub prod
#
# BUG: Pokud OIDC_PRIVATE_KEY nebo OIDC_ISSUER env var nebylo nastaveno,
#      token endpoint vrátil access_token bez id_token.
#      OAuth2 clients čekají id_token pro OIDC flow (scope=openid).
#
# Fix: validace OIDC env vars při startu + správná chybová zpráva
#
# Pokud test failuje → pošli bug report:
#   /root/dev/agent-messages/redis-queue.sh send auth TODO \
#     "REGRESSION: token endpoint nevrací id_token" "..." test

set -uo pipefail

AUTH_URL=${AUTH_URL:-"https://auth.s60dev.cz"}
PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "\n${YELLOW}=== REGRESSION: auth/token-endpoint-id-token ===${NC}"
echo -e "  Bug: token endpoint nevrátil id_token při chybějícím OIDC env var\n"

# Test 1: OIDC JWKS endpoint musí existovat a obsahovat klíče
# Pokud OIDC_PRIVATE_KEY chybí, JWKS bude prázdný nebo nedostupný
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
  "$AUTH_URL/api/auth/oauth/jwks" 2>/dev/null || echo "000")

if [ "$code" != "200" ]; then
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-tok-01] JWKS endpoint → $code (OIDC nefunguje)"
  FAIL=$((FAIL+1))
  exit 1
fi

echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-tok-01] JWKS endpoint → 200"
PASS=$((PASS+1))

# Test 2: JWKS musí obsahovat alespoň jeden klíč
jwks=$(curl -sk --max-time 5 "$AUTH_URL/api/auth/oauth/jwks" 2>/dev/null || echo "{}")
key_count=$(echo "$jwks" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('keys',[])))" 2>/dev/null || echo "0")

if [ "$key_count" -gt 0 ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-tok-02] JWKS obsahuje $key_count klíč(e) — OIDC env vars OK"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-tok-02] JWKS je prázdný — OIDC_PRIVATE_KEY pravděpodobně chybí!"
  FAIL=$((FAIL+1))
  /root/dev/agent-messages/redis-queue.sh send auth TODO \
    "REGRESSION: JWKS prázdný — token endpoint nevrátí id_token" \
    "JWKS endpoint vrátil 0 klíčů — OIDC_PRIVATE_KEY nebo OIDC_ISSUER env var pravděpodobně není nastaven" test 2>/dev/null || true
fi

# Test 3: OIDC discovery musí obsahovat id_token_signing_alg_values_supported
oidc=$(curl -sk --max-time 5 "$AUTH_URL/.well-known/openid-configuration" 2>/dev/null || echo "{}")
algs=$(echo "$oidc" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id_token_signing_alg_values_supported','MISSING'))" 2>/dev/null || echo "ERROR")

if [ "$algs" != "MISSING" ] && [ "$algs" != "ERROR" ] && [ "$algs" != "None" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-tok-03] id_token signing algs definovány: $algs"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-tok-03] id_token_signing_alg_values_supported chybí v OIDC config"
  FAIL=$((FAIL+1))
fi

# Test 4: token_endpoint musí být definován v OIDC discovery
token_ep=$(echo "$oidc" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('token_endpoint','MISSING'))" 2>/dev/null || echo "ERROR")
if [ "$token_ep" != "MISSING" ] && [ "$token_ep" != "ERROR" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-tok-04] token_endpoint definován: $token_ep"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-tok-04] token_endpoint chybí v OIDC config"
  FAIL=$((FAIL+1))
fi

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
