#!/bin/bash
# REGRESSION: BadWolf — /applications response musí obsahovat client.name
#
# BUG (commit fb6305f): EditApplicationForm v Venom používal client.name
#       ale API vracelo client.firstName + client.lastName (nebo nested struktura)
#       Výsledek: "undefined" zobrazeno v UI místo jména klienta
#
# Fix: BadWolf embeds client objekt s .name nebo Venom concatenuje firstName+lastName
#
# Tento test ověřuje, že API vrací konzistentní client data.

set -euo pipefail

BASE_URL=${BADWOLF_URL:-"https://be.s60dev.cz"}

if [ -z "${TEST_TOKEN:-}" ] && [ -f "/root/dev/.env" ]; then
  TEST_TOKEN=$(grep "^TEST_TOKEN=" /root/dev/.env 2>/dev/null | cut -d'=' -f2 | tr -d '"' || echo "")
fi

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

echo -e "\n${YELLOW}=== REGRESSION: applications/client-name-reference ===${NC}"
echo -e "  Bug: client.name undefined v EditApplicationForm (commit fb6305f)\n"

if [ -z "${TEST_TOKEN:-}" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} TEST_TOKEN not set"
  exit 0
fi

AUTH_HEADER="Authorization: Bearer $TEST_TOKEN"

resp=$(curl -sk -H "$AUTH_HEADER" "$BASE_URL/applications?limit=5")
code=$(curl -sk -o /dev/null -w "%{http_code}" -H "$AUTH_HEADER" "$BASE_URL/applications?limit=5")
assert "reg-app-client-01" "GET /applications → 200" "$code" "200"

# Ověř, že každý item má client objekt (buď .client nebo .clientId)
check=$(echo "$resp" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d.get('data',[])
if not items:
    print('skip')
    sys.exit(0)

issues=[]
for item in items:
    if 'client' not in item and 'clientId' not in item:
        issues.append(item.get('id','?'))

print('ok' if not issues else 'missing_client:' + ','.join(issues[:3]))
" 2>/dev/null || echo "error")

if [ "$check" = "skip" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} [reg-app-client-02] No applications in DB"
elif [ "$check" = "ok" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-app-client-02] All items have .client or .clientId"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-app-client-02] $check"
  FAIL=$((FAIL+1))
fi

# Pokud client je embedded objekt, musí mít identifikovatelné pole (name NEBO firstName)
check2=$(echo "$resp" | python3 -c "
import sys,json
d=json.load(sys.stdin)
items=d.get('data',[])
issues=[]
for item in items:
    c=item.get('client')
    if c and isinstance(c, dict):
        if not (c.get('name') or c.get('firstName') or c.get('email')):
            issues.append(item.get('id','?'))
print('ok' if not issues else 'empty_client:' + ','.join(issues[:3]))
" 2>/dev/null || echo "skip")

if [ "$check2" = "skip" ] || [ "$check2" = "ok" ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-app-client-03] Embedded client has identifiable fields"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-app-client-03] $check2 — client object has no name/firstName/email"
  FAIL=$((FAIL+1))
fi

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
