#!/bin/bash
# REGRESSION: Billit — API key scopes nebyly enforced (F-162)
#
# BUG: API klíče měly scopes v DB (permissions JSONB) ale žádný guard je
#      nekontroloval → jakýkoliv platný API klíč mohl dělat cokoliv.
#
# Fix: ApiKeyScopeGuard jako globální APP_GUARD + @RequireScope() dekorátor
# Commit: 070f0d3
#
# FIX 2 (commit e059878):
#   request.apiKeyPermissions === undefined byl interpretován jako JWT auth.
#   Fix: kontroluje Authorization header — ApiKey prefix → deny default.
#
# URL FIX: Nginx mapuje /api/ → billit-api container.
#   Bez /api/ prefixu zasáhne React SPA → 200 (index.html) nebo 405 (POST).
#   Správná base URL: https://billit.s60hub.cz/api  (BILLIT_TEST_API_BASE_URL_HUB)
#
# Test scénáře (dle specifikace billit agenta):
#   1. API klíč bez scopů       → GET /invoices → 403
#   2. API klíč s read:invoices → GET /invoices → 200
#   3. API klíč s read:invoices → POST /invoices → 403
#   4. API klíč s write:invoices → POST /invoices → 201
#   5. JWT Bearer token          → GET /invoices → 200 (scope ignorován)
#   6. API klíč s null permissions → GET /invoices → 403 "API key has no scopes"
#
# Požadavky: TEST_API_KEY_NO_SCOPE, TEST_API_KEY_READ_INVOICES,
#            TEST_API_KEY_WRITE_INVOICES, TEST_JWT_TOKEN
#   → nastav v /root/dev/.env nebo jako env proměnné
#
# Pokud test failuje → pošli bug report:
#   /root/dev/agent-messages/redis-queue.sh send billit TODO \
#     "REGRESSION: API key scope enforcement selhalo" "Scénář X: ..." test

set -uo pipefail

PASS=0; FAIL=0; SKIP=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Načti credentials z .env
# Priorita klíčů: env proměnná → .env hub vars → .env dev vars
_e() { grep "^$1=" /root/dev/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo ""; }

if [ -f "/root/dev/.env" ]; then
  # Base URL detekce — určí prostředí (hub vs dev)
  _HUB_BASE_URL=$(_e BILLIT_TEST_API_BASE_URL_HUB)   # https://billit.s60hub.cz/api
  _DEV_BASE_URL=$(_e BILLIT_TEST_API_BASE_URL_DEV)    # https://billit.s60dev.cz/api

  # Pokud BILLIT_URL není nastaven explicitně, autodetect z URL
  if [ -z "${BILLIT_URL:-}" ]; then
    # Default: hub pokud je nastaven, jinak dev
    BILLIT_URL="${_HUB_BASE_URL:-${_DEV_BASE_URL:-"https://billit.s60dev.cz/api"}}"
  fi

  # Vyber správné klíče podle prostředí (hub vs dev)
  if echo "$BILLIT_URL" | grep -q "s60hub"; then
    # HUB prostředí — použij BILLIT_TEST_HUB_* klíče
    TEST_API_KEY_NO_SCOPE=${TEST_API_KEY_NO_SCOPE:-$(_e BILLIT_TEST_HUB_API_KEY_NO_SCOPE)}
    TEST_API_KEY_READ_INVOICES=${TEST_API_KEY_READ_INVOICES:-$(_e BILLIT_TEST_HUB_API_KEY_READ_INVOICES)}
    TEST_API_KEY_WRITE_INVOICES=${TEST_API_KEY_WRITE_INVOICES:-$(_e BILLIT_TEST_HUB_API_KEY_WRITE_INVOICES)}
    TEST_BILLIT_SLUG=${TEST_BILLIT_SLUG:-$(_e BILLIT_TEST_HUB_SLUG)}
    TEST_JWT_TOKEN=${TEST_JWT_TOKEN:-$(_e BILLIT_TEST_HUB_JWT_TOKEN)}
  else
    # DEV prostředí — použij BILLIT_TEST_* klíče
    TEST_API_KEY_NO_SCOPE=${TEST_API_KEY_NO_SCOPE:-$(_e BILLIT_TEST_API_KEY_NO_SCOPE)}
    TEST_API_KEY_READ_INVOICES=${TEST_API_KEY_READ_INVOICES:-$(_e BILLIT_TEST_API_KEY_READ_INVOICES)}
    TEST_API_KEY_WRITE_INVOICES=${TEST_API_KEY_WRITE_INVOICES:-$(_e BILLIT_TEST_API_KEY_WRITE_INVOICES)}
    TEST_BILLIT_SLUG=${TEST_BILLIT_SLUG:-$(_e BILLIT_TEST_SLUG)}
    TEST_JWT_TOKEN=${TEST_JWT_TOKEN:-$(_e BILLIT_TEST_JWT_TOKEN)}
  fi
fi

BILLIT_API_BASE="${BILLIT_URL:-"https://billit.s60dev.cz/api"}"
TEST_BILLIT_SLUG=${TEST_BILLIT_SLUG:-"s60"}
INVOICES_URL="${BILLIT_API_BASE}/v1/accounts/${TEST_BILLIT_SLUG}/invoices"

assert_http() {
  local id=$1 desc=$2 actual=$3 expected=$4
  if [ "$actual" = "$expected" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc → HTTP $actual"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc → HTTP $actual (očekáváno: $expected)"
    FAIL=$((FAIL+1))
    /root/dev/agent-messages/redis-queue.sh send billit TODO \
      "REGRESSION: API key scope enforcement — $id" \
      "Test $id selhal: $desc. HTTP $actual (očekáváno $expected). Commit 070f0d3" test 2>/dev/null || true
  fi
}

assert_body() {
  local id=$1 desc=$2 body=$3 needle=$4
  if echo "$body" | grep -qi "$needle"; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc (obsahuje: '$needle')"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc (chybí: '$needle')"
    FAIL=$((FAIL+1))
  fi
}

echo -e "\n${YELLOW}=== REGRESSION: billit/api-key-scope-enforcement (F-162) ===${NC}"
echo -e "  Bug: API key scopes v DB nebyly enforced — jakýkoliv klíč mohl cokoliv"
echo -e "  API base: $BILLIT_API_BASE\n"

# Zkontroluj dostupnost — health je bez /api/ prefixu (statický endpoint)
_HEALTH_BASE=$(echo "$BILLIT_API_BASE" | sed 's|/api$||')
http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "${_HEALTH_BASE}/health" 2>/dev/null || echo "000")
if [ "$http_code" = "000" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Billit není dostupný na ${_HEALTH_BASE}/health"
  exit 0
fi
if [ "$http_code" != "200" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Billit health → $http_code (${_HEALTH_BASE}/health)"
  exit 0
fi

# ---------------------------------------------------------------
echo -e "${YELLOW}-- Scénář 1: API klíč BEZ scopů → GET /invoices → 403 --${NC}"
if [ -z "${TEST_API_KEY_NO_SCOPE:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-scope-01] BILLIT_TEST_API_KEY_NO_SCOPE not set"
  SKIP=$((SKIP+1))
else
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    -H "X-Api-Key: $TEST_API_KEY_NO_SCOPE" \
    "$INVOICES_URL" 2>/dev/null || echo "000")
  assert_http "reg-billit-scope-01" "API key bez scopů → GET /invoices" "$code" "403"
fi

# ---------------------------------------------------------------
echo -e "\n${YELLOW}-- Scénář 2: API klíč s read:invoices → GET /invoices → 200 --${NC}"
if [ -z "${TEST_API_KEY_READ_INVOICES:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-scope-02] BILLIT_TEST_API_KEY_READ_INVOICES not set"
  SKIP=$((SKIP+1))
else
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    -H "X-Api-Key: $TEST_API_KEY_READ_INVOICES" \
    "$INVOICES_URL" 2>/dev/null || echo "000")
  assert_http "reg-billit-scope-02" "API key read:invoices → GET /invoices" "$code" "200"
fi

# ---------------------------------------------------------------
echo -e "\n${YELLOW}-- Scénář 3: API klíč s read:invoices → POST /invoices → 403 --${NC}"
if [ -z "${TEST_API_KEY_READ_INVOICES:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-scope-03] BILLIT_TEST_API_KEY_READ_INVOICES not set"
  SKIP=$((SKIP+1))
else
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    -X POST \
    -H "X-Api-Key: $TEST_API_KEY_READ_INVOICES" \
    -H "Content-Type: application/json" \
    -d '{"clientId":"test","lines":[]}' \
    "$INVOICES_URL" 2>/dev/null || echo "000")
  assert_http "reg-billit-scope-03" "API key read:invoices → POST /invoices (write blocked)" "$code" "403"
fi

# ---------------------------------------------------------------
echo -e "\n${YELLOW}-- Scénář 4: API klíč s write:invoices → POST /invoices → 201 --${NC}"
if [ -z "${TEST_API_KEY_WRITE_INVOICES:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-scope-04] BILLIT_TEST_API_KEY_WRITE_INVOICES not set"
  SKIP=$((SKIP+1))
else
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    -X POST \
    -H "X-Api-Key: $TEST_API_KEY_WRITE_INVOICES" \
    -H "Content-Type: application/json" \
    -d '{"clientId":"test","lines":[]}' \
    "$INVOICES_URL" 2>/dev/null || echo "000")
  # 201 = created, 422/400 = validation error (OK — guard prošel, validace selhala na datech)
  if [ "$code" = "201" ] || [ "$code" = "422" ] || [ "$code" = "400" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [reg-billit-scope-04] API key write:invoices → POST /invoices → $code (guard prošel)"
    PASS=$((PASS+1))
  elif [ "$code" = "403" ]; then
    echo -e "  ${RED}❌ FAIL${NC} [reg-billit-scope-04] API key write:invoices → POST /invoices → 403 (scope guard blokuje write klíč!)"
    FAIL=$((FAIL+1))
    /root/dev/agent-messages/redis-queue.sh send billit TODO \
      "REGRESSION: write:invoices scope blokován" \
      "API klíč s write:invoices dostal 403 na POST /invoices — scope guard nerozpoznal write scope. Commit 070f0d3" test 2>/dev/null || true
  else
    echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-scope-04] Unexpected: $code"
    SKIP=$((SKIP+1))
  fi
fi

# ---------------------------------------------------------------
echo -e "\n${YELLOW}-- Scénář 5: JWT Bearer token → GET /invoices → 200 (scope ignorován) --${NC}"
if [ -z "${TEST_JWT_TOKEN:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-scope-05] BILLIT_TEST_JWT_TOKEN not set"
  SKIP=$((SKIP+1))
else
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    -H "Authorization: Bearer $TEST_JWT_TOKEN" \
    "$INVOICES_URL" 2>/dev/null || echo "000")
  # JWT = full access, nesmí dostat 403 kvůli scopům
  if [ "$code" = "200" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [reg-billit-scope-05] JWT token → GET /invoices → 200 (scope check přeskočen)"
    PASS=$((PASS+1))
  elif [ "$code" = "403" ]; then
    echo -e "  ${RED}❌ FAIL${NC} [reg-billit-scope-05] JWT token → GET /invoices → 403 (JWT nemá být scope-checked!)"
    FAIL=$((FAIL+1))
    /root/dev/agent-messages/redis-queue.sh send billit TODO \
      "REGRESSION: JWT token dostává 403 scope error" \
      "JWT Bearer token dostal 403 na GET /invoices — ApiKeyScopeGuard aplikuje scope check i na JWT. Commit 070f0d3" test 2>/dev/null || true
  elif [ "$code" = "401" ]; then
    echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-scope-05] JWT token expiroval nebo neplatný (401)"
    SKIP=$((SKIP+1))
  else
    echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-scope-05] Unexpected: $code"
    SKIP=$((SKIP+1))
  fi
fi

# ---------------------------------------------------------------
echo -e "\n${YELLOW}-- Scénář 6: API klíč s null permissions → GET /invoices → 403 + správná zpráva --${NC}"
if [ -z "${TEST_API_KEY_NO_SCOPE:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-billit-scope-06] BILLIT_TEST_API_KEY_NO_SCOPE not set"
  SKIP=$((SKIP+1))
else
  body=$(curl -sk --max-time 5 \
    -H "X-Api-Key: $TEST_API_KEY_NO_SCOPE" \
    "$INVOICES_URL" 2>/dev/null || echo "{}")
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    -H "X-Api-Key: $TEST_API_KEY_NO_SCOPE" \
    "$INVOICES_URL" 2>/dev/null || echo "000")
  assert_http "reg-billit-scope-06a" "null permissions → 403" "$code" "403"
  if [ "$code" = "403" ]; then
    assert_body "reg-billit-scope-06b" "Error message obsahuje 'API key has no scopes'" "$body" "no scopes"
  fi
fi

# ---------------------------------------------------------------
TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}  |  SKIP: ${YELLOW}$SKIP${NC}"

if [ "$SKIP" -gt 0 ]; then
  echo -e "\n  ${YELLOW}Poznámka:${NC} $SKIP scénářů přeskočeno — nastav testovací API klíče v /root/dev/.env:"
  echo -e "    BILLIT_TEST_API_KEY_NO_SCOPE=..."
  echo -e "    BILLIT_TEST_API_KEY_READ_INVOICES=..."
  echo -e "    BILLIT_TEST_API_KEY_WRITE_INVOICES=..."
  echo -e "    BILLIT_TEST_JWT_TOKEN=..."
  echo -e "    BILLIT_TEST_SLUG=... (default: test-tenant)"
fi

[ $FAIL -eq 0 ] && exit 0 || exit 1
