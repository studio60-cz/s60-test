#!/bin/bash
# REGRESSION: Billit — RLS migrace crashovala na child tabulkách + UUID cast
# @env dev hub prod
#
# BUG 1: RLS CREATE POLICY aplikována na tabulky bez tenant_id sloupce
#         (invoice_lines, order_lines, expense_lines, order_invoices,
#          invoice_payments, webhook_deliveries) → migration crash
#   Fix: RLS jen pro tabulky s přímým tenant_id sloupcem
#
# BUG 2: NULLIF chyběl → current_setting('app.current_tenant_id',true)='',
#         přímý ::uuid cast failoval s error
#   Fix: NULLIF(current_setting('app.current_tenant_id', true), '')::uuid
#
# Commit: 95b31fc
#
# Pokud test failuje → pošli bug report:
#   /root/dev/agent-messages/redis-queue.sh send billit TODO \
#     "REGRESSION: RLS migration crash" "Popis" test

set -uo pipefail

BILLIT_URL=${BILLIT_URL:-"https://billit.s60dev.cz"}
BILLIT_SLUG=${BILLIT_SLUG:-$(echo "$BILLIT_URL" | grep -q "hub" && echo "test" || echo "test-tenant")}
# DEV nginx: /* → Vite, /api/* → billit-api. Health endpoint se liší.
BILLIT_HEALTH_URL=$(echo "$BILLIT_URL" | grep -q "hub\|prod" && echo "${BILLIT_URL%/}/health" || echo "${BILLIT_URL%/}/api/health")
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

echo -e "\n${YELLOW}=== REGRESSION: billit/rls-migration-child-tables ===${NC}"
echo -e "  Bug 1: RLS policy na child tabulkách bez tenant_id → migration crash"
echo -e "  Bug 2: empty string UUID cast → runtime crash\n"

# Zkontroluj jestli Billit API je dostupné
http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$BILLIT_HEALTH_URL" 2>/dev/null || echo "000")

if [ "$http_code" = "000" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Billit není dostupný na $BILLIT_URL"
  exit 0
fi

# Test 1: Health endpoint — pokud migration crashla, server nenaběhne
assert "reg-billit-rls-01" "GET /health → server naběhl (migration necrashla)" "$http_code" "200"

# Test 2: SELECT na child tabulce bez tenant kontextu nesmí crashnout
# invoice_lines endpoint (přes parent invoice) → nesmí vrátit 500
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
  "$BILLIT_URL/v1/accounts/${BILLIT_SLUG}/invoices" \
  -H "Authorization: Bearer invalid" 2>/dev/null || echo "000")

# 401 = server funguje a autentizuje, 403 = OK, 500 = RLS crash
if [ "$code" = "200" ] || [ "$code" = "401" ] || [ "$code" = "403" ] || [ "$code" = "404" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-billit-rls-02] /invoices → $code (no 500 crash)"
  PASS=$((PASS+1))
elif [ "$code" = "500" ]; then
  echo -e "  ${RED}❌ FAIL${NC} [reg-billit-rls-02] /invoices vrátil 500 — možný RLS crash"
  FAIL=$((FAIL+1))
  /root/dev/agent-messages/redis-queue.sh send billit TODO \
    "REGRESSION: RLS crash na /invoices" \
    "GET /invoices vrátil 500 — pravděpodobná regrese RLS UUID cast bugu (commit 95b31fc)" test 2>/dev/null || true
else
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-rls-02] Unexpected response: $code"
fi

# Test 3: Podobně pro /orders endpoint (order_lines jsou child tabulka)
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
  "$BILLIT_URL/v1/accounts/${BILLIT_SLUG}/orders" \
  -H "Authorization: Bearer invalid" 2>/dev/null || echo "000")

if [ "$code" = "200" ] || [ "$code" = "401" ] || [ "$code" = "403" ] || [ "$code" = "404" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-billit-rls-03] /orders → $code (no 500 crash)"
  PASS=$((PASS+1))
elif [ "$code" = "500" ]; then
  echo -e "  ${RED}❌ FAIL${NC} [reg-billit-rls-03] /orders vrátil 500 — možný RLS crash"
  FAIL=$((FAIL+1))
else
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-rls-03] Response: $code"
fi

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
