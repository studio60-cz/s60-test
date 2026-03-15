#!/bin/bash
# S60Pulse Smoke Tests
# @env dev hub prod
# Usage: ./pulse-smoke.sh [dev|hub|prod]

ENV=${1:-dev}

case "$ENV" in
  dev)  BASE_URL="https://pulse.s60dev.cz" ;;
  hub)  BASE_URL="https://pulse.s60hub.cz" ;;
  prod) BASE_URL="https://pulse.studio60.cz" ;;
  *)    echo "Unknown env: $ENV"; exit 1 ;;
esac

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

check() {
  local id=$1 desc=$2 url=$3 expected=${4:-200}
  local code
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
  if [ "$code" = "$expected" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc (HTTP $code)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc (HTTP $code, expected $expected)"
    FAIL=$((FAIL + 1))
  fi
}

check_body() {
  local id=$1 desc=$2 url=$3 contains=$4
  local body code
  body=$(curl -sk --max-time 5 "$url" 2>/dev/null || echo "")
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
  if echo "$body" | grep -q "$contains"; then
    echo -e "  ${GREEN}✅ PASS${NC} [$id] $desc (HTTP $code)"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [$id] $desc — missing '$contains' (HTTP $code)"
    FAIL=$((FAIL + 1))
  fi
}

echo -e "\n${YELLOW}-- S60Pulse ($BASE_URL) --${NC}"

# Health — db:error je OK (lokální DB), status:ok musí být
check_body "pulse-health"     "GET /health → status:ok"   "$BASE_URL/health"       '"status":"ok"'

# Auth protected endpoints → 401 bez tokenu
check "pulse-projects-401"  "GET /api/projects → 401"    "$BASE_URL/api/projects"  401
check "pulse-clients-401"   "GET /api/clients → 401"     "$BASE_URL/api/clients"   401
check "pulse-outputs-401"   "GET /api/outputs → 401"     "$BASE_URL/api/outputs"   401

# Frontend — redirect na /app
local_code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$BASE_URL/" 2>/dev/null || echo "000")
if [ "$local_code" = "200" ] || [ "$local_code" = "302" ] || [ "$local_code" = "301" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [pulse-frontend] GET / → app/redirect (HTTP $local_code)"
  PASS=$((PASS + 1))
else
  echo -e "  ${RED}❌ FAIL${NC} [pulse-frontend] GET / → HTTP $local_code"
  FAIL=$((FAIL + 1))
fi

TOTAL=$((PASS + FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"

[ $FAIL -eq 0 ] && exit 0 || exit 1
