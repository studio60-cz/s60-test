#!/bin/bash
# S60 Smoke Tests — rychlý health check všech služeb
# Spouští sentinel po každém deployi + cron
# Usage: ./run-smoke.sh [dev|hub|prod] [service|all]

set -euo pipefail

ENV=${1:-dev}
SERVICE=${2:-all}

# Domain mapping
# NOTE: BadWolf subdomena se liší podle prostředí:
#   dev:  be.s60dev.cz   (legacy, zachováno)
#   hub:  be.s60hub.cz
#   prod: api.studio60.cz (DNS korekce 2026-03-12, be.studio60.cz = starý Merlin)
case "$ENV" in
  dev)   DOMAIN="s60dev.cz";  BE_SUBDOMAIN="be" ;;
  hub)   DOMAIN="s60hub.cz";  BE_SUBDOMAIN="be" ;;
  prod)  DOMAIN="studio60.cz"; BE_SUBDOMAIN="api" ;;
  *)     echo "Unknown env: $ENV (dev|hub|prod)"; exit 1 ;;
esac

# Mail je internal service (port 3010, bez nginx na hub/prod)
# → smoke jen na dev (kde může být nginx exposed), hub/prod se testuje přes Tailscale
MAIL_TAILSCALE_HUB="100.68.138.14"   # hub-alfa Tailscale IP
MAIL_TAILSCALE_PROD="100.78.87.88"   # prod-alfa Tailscale IP
MAIL_PORT="3010"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="/tmp/smoke-${ENV}-${TIMESTAMP}.json"

PASS=0
FAIL=0
SKIP=0
RESULTS=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check() {
  local id=$1
  local desc=$2
  local url=$3
  local expected_status=${4:-200}
  local body_contains=${5:-""}

  local response
  local http_code

  http_code=$(curl -sk -o /tmp/smoke-body -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
  response=$(cat /tmp/smoke-body 2>/dev/null || echo "")

  local status="PASS"

  if [ "$http_code" != "$expected_status" ]; then
    status="FAIL"
  fi

  if [ -n "$body_contains" ] && ! echo "$response" | grep -q "$body_contains"; then
    status="FAIL"
  fi

  if [ "$status" = "PASS" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc (HTTP $http_code)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc (HTTP $http_code, expected $expected_status)"
    FAIL=$((FAIL + 1))
  fi

  RESULTS+=("{\"id\":\"$id\",\"status\":\"$status\",\"http_code\":\"$http_code\"}")
}

# ============================================================
echo -e "\n${BLUE}=== S60 Smoke Tests — ENV: $ENV ($DOMAIN) ===${NC}\n"

# ============================================================
if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "auth" ]; then
  echo -e "${YELLOW}-- S60Auth --${NC}"
  check "auth-smoke-health"     "GET /api/health"               "https://auth.${DOMAIN}/api/health"                200 "S60-Auth"
  check "auth-smoke-jwks"       "GET /api/auth/oauth/jwks"      "https://auth.${DOMAIN}/api/auth/oauth/jwks"       200 "keys"
  check "auth-smoke-oidc"       "GET /openid-configuration"     "https://auth.${DOMAIN}/.well-known/openid-configuration" 200 "issuer"
  check "auth-smoke-no-token"   "ForwardAuth rejects no token"  "https://${BE_SUBDOMAIN}.${DOMAIN}/applications"   401
fi

# ============================================================
if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "badwolf" ]; then
  echo -e "\n${YELLOW}-- S60BadWolf (https://${BE_SUBDOMAIN}.${DOMAIN}) --${NC}"
  check "badwolf-smoke-health"    "GET /health"      "https://${BE_SUBDOMAIN}.${DOMAIN}/health"      200
  check "badwolf-smoke-courses"   "GET /courses"     "https://${BE_SUBDOMAIN}.${DOMAIN}/courses"     200
  check "badwolf-smoke-locations" "GET /locations"   "https://${BE_SUBDOMAIN}.${DOMAIN}/locations"   200
fi

# ============================================================
if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "venom" ]; then
  echo -e "\n${YELLOW}-- S60Venom --${NC}"
  # Venom je za ForwardAuth → 403 bez tokenu = OK (service běží)
  http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "https://venom.${DOMAIN}/" 2>/dev/null || echo "000")
  if [ "$http_code" = "200" ] || [ "$http_code" = "403" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [venom-smoke-index] GET / (HTTP $http_code — service up)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [venom-smoke-index] GET / (HTTP $http_code, expected 200 or 403)"
    FAIL=$((FAIL + 1))
  fi
  RESULTS+=("{\"id\":\"venom-smoke-index\",\"status\":\"$([ "$http_code" = "200" ] || [ "$http_code" = "403" ] && echo PASS || echo FAIL)\",\"http_code\":\"$http_code\"}")
fi

# ============================================================
if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "billit" ]; then
  echo -e "\n${YELLOW}-- Billit --${NC}"
  # Billit nemusí být na všech envs; vždy HTTPS (301 = HTTP→HTTPS redirect = chyba v URL)
  BILLIT_HEALTH_URL="https://billit.${DOMAIN}/health"
  http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$BILLIT_HEALTH_URL" 2>/dev/null || echo "000")
  if [ "$http_code" = "000" ]; then
    echo -e "  ${YELLOW}⏭ SKIP${NC} [billit-smoke-health] Not deployed on $ENV"
    SKIP=$((SKIP + 1))
  elif [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
    echo -e "  ${RED}❌ FAIL${NC} [billit-smoke-health] $BILLIT_HEALTH_URL → HTTP $http_code (redirect — zkontroluj HTTPS config)"
    FAIL=$((FAIL + 1))
    RESULTS+=("{\"id\":\"billit-smoke-health\",\"status\":\"FAIL\",\"http_code\":\"$http_code\"}")
  else
    check "billit-smoke-health"   "GET /health"   "$BILLIT_HEALTH_URL"   200
  fi
fi

# ============================================================
if [ "$SERVICE" = "all" ] || [ "$SERVICE" = "mail" ]; then
  echo -e "\n${YELLOW}-- S60Mail --${NC}"
  # S60Mail je internal service (port 3010, bez nginx na hub/prod)
  # dev: https://mail.s60dev.cz/health (nginx exposed)
  # hub/prod: přes Tailscale IP:3010 (interní)
  case "$ENV" in
    dev)
      MAIL_URL="https://mail.${DOMAIN}/health"
      ;;
    hub)
      MAIL_URL="http://${MAIL_TAILSCALE_HUB}:${MAIL_PORT}/health"
      ;;
    prod)
      MAIL_URL="http://${MAIL_TAILSCALE_PROD}:${MAIL_PORT}/health"
      ;;
  esac
  http_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$MAIL_URL" 2>/dev/null || echo "000")
  if [ "$http_code" = "000" ]; then
    echo -e "  ${YELLOW}⏭ SKIP${NC} [mail-smoke-health] Not reachable ($MAIL_URL) — not deployed or Tailscale down"
    SKIP=$((SKIP + 1))
  else
    check "mail-smoke-health"   "GET /health ($ENV)"   "$MAIL_URL"   200
  fi
fi

# ============================================================
TOTAL=$((PASS + FAIL))
echo -e "\n${BLUE}=== VÝSLEDKY ===${NC}"
echo -e "  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}  |  SKIP: ${YELLOW}$SKIP${NC}"

# JSON výstup
RESULTS_JSON=$(IFS=,; echo "[${RESULTS[*]}]")
cat > "$RESULTS_FILE" <<EOF
{
  "env": "$ENV",
  "domain": "$DOMAIN",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "summary": {"pass": $PASS, "fail": $FAIL, "skip": $SKIP, "total": $TOTAL},
  "tests": $RESULTS_JSON
}
EOF

echo -e "\n  Results: $RESULTS_FILE"

if [ $FAIL -gt 0 ]; then
  echo -e "\n${RED}❌ SMOKE FAILED — deploy blokován!${NC}"
  exit 1
else
  echo -e "\n${GREEN}✅ SMOKE OK${NC}"
  exit 0
fi
