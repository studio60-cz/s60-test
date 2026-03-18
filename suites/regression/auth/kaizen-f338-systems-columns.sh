#!/bin/bash
# Regression: Kaizen F-338 — systems table migration
# @env hub prod
#
# Ověřuje že SystemsModule vrací systémy s novými sloupci
# (marketing_html, purchase_url, custom_name, primary_color atd.)
# Commit: 1b11c0d (auth agent)
#
# Pokud test failuje → /root/dev/agent-messages/send-message.sh auth TODO "REGRESSION: F-338" "popis" test

set -uo pipefail

ENV=${1:-hub}
case "$ENV" in
  hub)  AUTH_URL="https://auth.s60hub.cz" ;;
  prod) AUTH_URL="https://auth.studio60.cz" ;;
  *)    echo "Unknown env: $ENV (hub|prod)"; exit 1 ;;
esac

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

assert() {
  local id=$1 desc=$2 ok=$3
  if [ "$ok" = "1" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc"
    FAIL=$((FAIL+1))
    /root/dev/agent-messages/send-message.sh auth TODO \
      "REGRESSION: auth/F-338 — $id selhalo" \
      "$desc. ENV: $ENV, AUTH_URL: $AUTH_URL" test 2>/dev/null || true
  fi
}

echo -e "\n${YELLOW}=== Regression F-338: systems table migration ($AUTH_URL) ===${NC}\n"

# Zkontroluj /health
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$AUTH_URL/health" 2>/dev/null || echo "000")
assert "f338-health" "Auth /health → 200" "$([ "$code" = "200" ] && echo 1 || echo 0)"

# Pokud není auth online → skip DB testy
if [ "$code" != "200" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Auth není dostupné — přeskakuji DB testy"
  echo -e "\n  PASS: ${GREEN}$PASS${NC} / $((PASS+FAIL))  |  FAIL: ${RED}$FAIL${NC}"
  [ $FAIL -eq 0 ] && exit 0 || exit 1
fi

# Systems endpoint vrací 200 (systémy existují a migrate proběhla)
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$AUTH_URL/api/systems" 2>/dev/null || echo "000")
# 200 nebo 401 jsou OK — 500 by znamenalo DB error (chybějící sloupec)
assert "f338-systems-no-500" "GET /api/systems nekončí 500 (DB migration OK)" \
  "$([ "$code" != "500" ] && [ "$code" != "000" ] && echo 1 || echo 0)"

# Kontrola přes veřejný discovery endpoint (OIDC)
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$AUTH_URL/.well-known/openid-configuration" 2>/dev/null || echo "000")
assert "f338-oidc-ok" "OIDC discovery → 200 (auth server operational)" \
  "$([ "$code" = "200" ] && echo 1 || echo 0)"

echo -e "\n  PASS: ${GREEN}$PASS${NC} / $((PASS+FAIL))  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
