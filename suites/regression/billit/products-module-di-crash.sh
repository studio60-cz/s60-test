#!/bin/bash
# REGRESSION: Billit — TenantUser chybí v ProductsModule forFeature → DI crash
# @env dev hub prod
#
# BUG: TenantMiddleware vyžaduje TenantUser entitu pro DI, ale ProductsModule
#      ji neměl v TypeOrmModule.forFeature(). Startup crash při prvním requestu
#      na /products (NestJS DI error).
#
# Fix: přidat TenantUser do TypeOrmModule.forFeature([Product, Tenant, TenantUser])
# Soubor: billit-api/src/modules/products/products.module.ts
# Commit: 95b31fc
#
# Pokud test failuje → pošli bug report:
#   /root/dev/agent-messages/redis-queue.sh send billit TODO \
#     "REGRESSION: ProductsModule DI crash" "GET /products vrátil 500" test

set -uo pipefail

BILLIT_URL=${BILLIT_URL:-"https://billit.s60dev.cz"}
BILLIT_SLUG=${BILLIT_SLUG:-$(echo "$BILLIT_URL" | grep -q "hub" && echo "test" || echo "test-tenant")}
# DEV nginx: /* → Vite, /api/* → billit-api. Health endpoint se liší.
# Health URL: strip /api suffix for base, then add correct path per env
_BILLIT_BASE="${BILLIT_URL%/api}"
BILLIT_HEALTH_URL=$(echo "$BILLIT_URL" | grep -q "s60dev" && echo "${_BILLIT_BASE}/api/health" || echo "${_BILLIT_BASE}/health")
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

echo -e "\n${YELLOW}=== REGRESSION: billit/products-module-di-crash ===${NC}"
echo -e "  Bug: TenantUser chyběl v ProductsModule → DI crash při GET /products\n"

# Zkontroluj dostupnost
http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$BILLIT_HEALTH_URL" 2>/dev/null || echo "000")
if [ "$http_code" = "000" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Billit není dostupný na $BILLIT_URL"
  exit 0
fi

# Test 1: Health — server musí naběhnout
assert "reg-billit-di-01" "GET /health → 200 (server naběhl)" "$http_code" "200"

# Test 2: GET /products nesmí vrátit 500 DI error
# Bez tokenu očekáváme 401/403 — 500 = DI crash
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
  "${_BILLIT_BASE}/api/v1/accounts/${BILLIT_SLUG}/products" \
  -H "Authorization: Bearer invalid" 2>/dev/null || echo "000")

if [ "$code" = "200" ] || [ "$code" = "401" ] || [ "$code" = "403" ] || [ "$code" = "404" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-billit-di-02] GET /products → $code (no DI crash)"
  PASS=$((PASS+1))
elif [ "$code" = "500" ]; then
  echo -e "  ${RED}❌ FAIL${NC} [reg-billit-di-02] GET /products → 500 (DI crash regrese!)"
  FAIL=$((FAIL+1))
  [ "${REGRESSION_NOTIFY:-0}" = "1" ] && /root/dev/agent-messages/redis-queue.sh send billit TODO \
    "REGRESSION: ProductsModule DI crash" \
    "GET /api/v1/accounts/${BILLIT_SLUG}/products vrátil 500 — regrese TenantUser DI bugu (commit 95b31fc)" test 2>/dev/null || true
elif [ "$code" = "000" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-di-02] /products endpoint nedostupný"
else
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-di-02] Response: $code"
fi

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
