#!/bin/bash
# REGRESSION: S60Auth — F-308 unit testy (AppController, AuthService, UsersService)
# @env dev hub prod
#
# BUG: Kaizen F-308 — detaily v commitu de4df23 (auth repo)
# Fix: 3 test soubory, 7 assertions přidány do auth backend
#
# Tento regression test ověřuje, že unit testy v auth backendu stále prochází.

set -uo pipefail

PASS=0; FAIL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "\n${YELLOW}=== REGRESSION: auth/kaizen-f308-unit-tests ===${NC}"
echo -e "  Commit: de4df23 — AppController, AuthService, UsersService unit testy\n"

AUTH_BACKEND="/root/projects/auth/backend"

if [ ! -d "$AUTH_BACKEND" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Auth backend not found at $AUTH_BACKEND"
  exit 0
fi

output=$(cd "$AUTH_BACKEND" && npm test 2>&1)
exit_code=$?

suites=$(echo "$output" | grep -E "Test Suites:" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+" || echo "0")
tests=$(echo "$output" | grep -E "^Tests:" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+" || echo "0")
failed=$(echo "$output" | grep -E "^Tests:" | grep -oE "[0-9]+ failed" | grep -oE "[0-9]+" || echo "0")

if [ "$exit_code" -eq 0 ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-f308-01] jest: $suites suites, $tests tests PASS"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-f308-01] jest failed: $failed tests failed"
  echo "$output" | grep -E "FAIL|●" | head -10
  FAIL=$((FAIL+1))
  /root/dev/agent-messages/send-message.sh auth TODO \
    "REGRESSION: F-308 unit testy selhaly" \
    "jest v auth/backend vrátil non-zero. Commit de4df23." test 2>/dev/null || true
fi

# Ověř počet testů — nesmí klesnout pod 7
if [ "${tests:-0}" -ge 7 ]; then
  echo -e "  ${GREEN}✅ PASS${NC} [reg-auth-f308-02] Počet testů >= 7 (got: $tests)"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}❌ FAIL${NC} [reg-auth-f308-02] Počet testů < 7 (got: $tests)"
  FAIL=$((FAIL+1))
fi

TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"
[ $FAIL -eq 0 ] && exit 0 || exit 1
