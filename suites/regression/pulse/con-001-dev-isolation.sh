#!/bin/bash
# REGRESSION: Pulse — CON-001 dev agent nesmí psát do prod/hub DB
# @env dev hub prod
#
# SPEC: /root/dev/catalog/specs/CON-001.md
# Constraint: Dev agenti na Cerebru nesmí mít write přístup k prod/hub DB.
# Pro Pulse (NestJS backend): DATABASE_URL musí ukazovat na dev DB.
#
# STATUS: ČÁSTEČNÁ IMPLEMENTACE (2026-03-20)
#   ✅ AC1: .env DATABASE_URL ukazuje na s60_pulse_dev (dev DB)
#   ✅ AC2: APP_URL/S60_AUTH_URL ukazují na s60dev.cz
#   ⚠️  AC_MISSING: Chybí startup guard (jako venom enforceDevIsolation)
#                  → závisí pouze na .env konfiguraci, žádná code-level ochrana
#
# Commit pulse: 0db8106 — označen jako CON-001, ale jde o migration (projects tabulka)
#               Skutečná CON-001 implementace = pouze .env konfigurace

set -uo pipefail

PULSE_DIR="/root/projects/pulse"
PASS=0; FAIL=0; WARN=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

assert() {
  local id=$1 desc=$2 result=$3 expected=$4
  if [ "$result" = "$expected" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc"; PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc (expected: $expected, got: $result)"; FAIL=$((FAIL+1))
  fi
}

warn() {
  echo -e "  ${YELLOW}⚠️  WARN${NC} [$1] $2"
  WARN=$((WARN+1))
}

echo -e "\n${YELLOW}=== REGRESSION: pulse/con-001-dev-isolation ===${NC}"
echo -e "  Spec: CON-001 — Dev agent nesmí psát do prod/hub DB\n"

if [ ! -d "$PULSE_DIR" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Pulse repo nenalezen: $PULSE_DIR"
  exit 0
fi

# -------------------------------------------------------------------
echo -e "${YELLOW}-- AC1: DATABASE_URL neukazuje na prod/hub DB --${NC}"

if [ -f "$PULSE_DIR/.env" ]; then
  DB_URL=$(grep "^DATABASE_URL=" "$PULSE_DIR/.env" | cut -d= -f2-)

  # Check: nesmí být prod (s60_pulse bez suffixu nebo s60_pulse_prod)
  if echo "$DB_URL" | grep -qE "s60_pulse_prod|/s60_pulse\?|/s60_pulse$"; then
    echo -e "  ${RED}❌ FAIL${NC} [con001-pulse-ac1a] DATABASE_URL ukazuje na PROD DB!"
    FAIL=$((FAIL+1))
  elif echo "$DB_URL" | grep -qE "s60_pulse_hub|s60_pulse_staging"; then
    echo -e "  ${RED}❌ FAIL${NC} [con001-pulse-ac1a] DATABASE_URL ukazuje na HUB/STAGING DB!"
    FAIL=$((FAIL+1))
  elif echo "$DB_URL" | grep -q "s60_pulse_dev"; then
    echo -e "  ${GREEN}✅ PASS${NC} [con001-pulse-ac1a] DATABASE_URL ukazuje na DEV DB (s60_pulse_dev)"
    PASS=$((PASS+1))
  else
    echo -e "  ${YELLOW}⚠️  WARN${NC} [con001-pulse-ac1a] DATABASE_URL — nelze určit prostředí: $(echo "$DB_URL" | sed 's/:.*@/:***@/')"
    WARN=$((WARN+1))
  fi
else
  echo -e "  ${YELLOW}⏭ SKIP${NC} [con001-pulse-ac1a] .env nenalezen"
fi

# -------------------------------------------------------------------
echo -e "\n${YELLOW}-- AC2: APP_URL/S60_AUTH_URL neukazují na prod/hub --${NC}"

if [ -f "$PULSE_DIR/.env" ]; then
  APP_URL=$(grep "^APP_URL=" "$PULSE_DIR/.env" | cut -d= -f2-)
  AUTH_URL=$(grep "^S60_AUTH_URL=" "$PULSE_DIR/.env" | cut -d= -f2-)

  for url_var in "$APP_URL" "$AUTH_URL"; do
    if echo "$url_var" | grep -qE "studio60\.cz|s60hub\.cz"; then
      echo -e "  ${RED}❌ FAIL${NC} [con001-pulse-ac2] Prod/hub URL v .env: $url_var"
      FAIL=$((FAIL+1))
    fi
  done

  # Verify both point to dev
  app_ok=$(echo "$APP_URL" | grep -c "s60dev.cz" || true)
  auth_ok=$(echo "$AUTH_URL" | grep -c "s60dev.cz" || true)

  [ "$app_ok" -gt 0 ] && { echo -e "  ${GREEN}✅ PASS${NC} [con001-pulse-ac2a] APP_URL → s60dev.cz"; PASS=$((PASS+1)); }
  [ "$auth_ok" -gt 0 ] && { echo -e "  ${GREEN}✅ PASS${NC} [con001-pulse-ac2b] S60_AUTH_URL → s60dev.cz"; PASS=$((PASS+1)); }
fi

# -------------------------------------------------------------------
echo -e "\n${YELLOW}-- AC3: Startup guard (code-level ochrana) --${NC}"

# Check for startup validation in main.ts or app.module.ts
has_guard=$(grep -rn "CON-001\|prod.*guard\|isProd.*db\|validateDb\|databaseGuard\|studio60\.cz.*throw\|s60hub.*throw" \
  "$PULSE_DIR/src/main.ts" "$PULSE_DIR/src/app.module.ts" 2>/dev/null | grep -v "//\|node_modules" | wc -l)

if [ "$has_guard" -eq 0 ]; then
  warn "con001-pulse-ac3" "Chybí startup guard! Pulse nemá code-level ochranu (jako venom enforceDevIsolation).
         Spoléhá pouze na .env konfiguraci — pokud někdo změní DATABASE_URL na prod,
         nic to nezastaví. Doporučení: přidat validaci v main.ts:
         if (DATABASE_URL.includes('s60_pulse_prod')) throw Error('[CON-001] ZAKÁZÁNO...')"
else
  echo -e "  ${GREEN}✅ PASS${NC} [con001-pulse-ac3] Startup guard nalezen"
  PASS=$((PASS+1))
fi

# -------------------------------------------------------------------
TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}  |  WARN: ${YELLOW}$WARN${NC}"

if [ "$WARN" -gt 0 ]; then
  echo -e "  ${YELLOW}Poznámka:${NC} CON-001 pro pulse je ČÁSTEČNĚ implementováno — viz WARN výše."
fi

[ $FAIL -eq 0 ] && exit 0 || exit 1
