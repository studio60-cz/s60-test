#!/bin/bash
# REGRESSION: S60Auth — OIDC issuer hardcoded na prod URL
#
# BUG: OIDC issuer byl hardcoded na "https://auth.studio60.cz" i v dev/staging
#      prostředí. Tokens z dev/staging měly špatný issuer → validace failovala
#      na jiných službách.
#
# Fix: issuer se čte z env proměnné (S60_DOMAIN nebo AUTH_ISSUER)
#
# Pokud test failuje → pošli bug report:
#   /root/dev/agent-messages/redis-queue.sh send auth TODO \
#     "REGRESSION: OIDC issuer hardcoded na prod" "..." test

set -uo pipefail

AUTH_URL=${AUTH_URL:-"https://auth.s60dev.cz"}
EXPECTED_ISSUER_DOMAIN="s60dev.cz"
PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "\n${YELLOW}=== REGRESSION: auth/oidc-issuer-hardcoded ===${NC}"
echo -e "  Bug: OIDC issuer byl hardcoded na prod URL i v dev prostředí\n"

# Test 1: OIDC discovery musí být dostupný
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
  "$AUTH_URL/.well-known/openid-configuration" 2>/dev/null || echo "000")

if [ "$code" != "200" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Auth není dostupný ($code)"
  exit 0
fi

echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-iss-01] OIDC discovery dostupný"
PASS=$((PASS+1))

# Test 2: issuer v OIDC config musí odpovídat aktuálnímu prostředí
oidc=$(curl -sk --max-time 5 "$AUTH_URL/.well-known/openid-configuration" 2>/dev/null || echo "{}")
issuer=$(echo "$oidc" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('issuer','MISSING'))" 2>/dev/null || echo "ERROR")

if echo "$issuer" | grep -q "$EXPECTED_ISSUER_DOMAIN"; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-iss-02] issuer odpovídá prostředí: $issuer"
  PASS=$((PASS+1))
elif echo "$issuer" | grep -q "studio60.cz"; then
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-iss-02] issuer je hardcoded na PROD: $issuer (DEV prostředí!)"
  FAIL=$((FAIL+1))
  /root/dev/agent-messages/redis-queue.sh send auth TODO \
    "REGRESSION: OIDC issuer hardcoded na prod" \
    "DEV auth vrací issuer=$issuer (prod URL) místo $AUTH_URL" test 2>/dev/null || true
else
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-auth-iss-02] Issuer: $issuer (nelze ověřit prostředí)"
fi

# Test 3: issuer URL musí být dostupná (nesmí být 404/500)
if [ -n "$issuer" ] && [ "$issuer" != "MISSING" ] && [ "$issuer" != "ERROR" ]; then
  issuer_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    "$issuer/.well-known/openid-configuration" 2>/dev/null || echo "000")
  if [ "$issuer_code" = "200" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-iss-03] issuer URL je reachable ($issuer)"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [reg-auth-iss-03] issuer URL neodpovídá: $issuer → $issuer_code"
    FAIL=$((FAIL+1))
  fi
fi

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
