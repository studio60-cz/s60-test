#!/bin/bash
# S60 Daily Test Run — spouští se cronem každý den
# Výstup: /tmp/test-results/daily-YYYYMMDD.json
# Reportuje PM agentovi výsledky

set -uo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE=$(date +%Y-%m-%d)
RESULTS_DIR="/tmp/test-results"
REPORT_FILE="$RESULTS_DIR/daily-${TIMESTAMP}.json"
LOG_FILE="$RESULTS_DIR/daily-${TIMESTAMP}.log"
mkdir -p "$RESULTS_DIR"

# Colors (for log file readability)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
SUITE_RESULTS=()

log() {
  echo -e "$1" | tee -a "$LOG_FILE"
}

run_suite() {
  local name=$1
  local cmd=$2
  local start_time=$(date +%s)

  log "\n${YELLOW}=== $name ===${NC}"

  local output
  local exit_code
  output=$(eval "$cmd" 2>&1) || exit_code=$?
  exit_code=${exit_code:-0}

  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  echo "$output" >> "$LOG_FILE"

  # Parse PASS/FAIL counts from output
  local pass=$(echo "$output" | grep -c "✅ PASS" || true)
  local fail=$(echo "$output" | grep -c "❌ FAIL" || true)
  local skip=$(echo "$output" | grep -c "⏭ SKIP" || true)

  TOTAL_PASS=$((TOTAL_PASS + pass))
  TOTAL_FAIL=$((TOTAL_FAIL + fail))
  TOTAL_SKIP=$((TOTAL_SKIP + skip))

  local status="PASS"
  [ "$exit_code" -ne 0 ] && status="FAIL"

  SUITE_RESULTS+=("{\"name\":\"$name\",\"status\":\"$status\",\"pass\":$pass,\"fail\":$fail,\"skip\":$skip,\"duration_s\":$duration}")

  if [ "$status" = "PASS" ]; then
    log "${GREEN}  => $name: PASS ($pass tests, ${duration}s)${NC}"
  else
    log "${RED}  => $name: FAIL ($fail failures, ${duration}s)${NC}"
  fi
}

# ============================================================
log "${BLUE}=== S60 Daily Test Run — $DATE ===${NC}"
log "Start: $(date -u +%H:%M:%S) UTC"

# 1. Smoke Tests (all environments that are up)
run_suite "Smoke DEV" "bash /root/dev/s60-test/suites/smoke/run-smoke.sh dev all"
run_suite "Smoke: Pulse DEV" "bash /root/dev/s60-test/suites/smoke/pulse-smoke.sh dev"

# 2. Smoke Hub (staging) — if reachable
if curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "https://auth.s60hub.cz/api/health" 2>/dev/null | grep -q "200"; then
  run_suite "Smoke HUB" "bash /root/dev/s60-test/suites/smoke/run-smoke.sh hub all"
else
  log "${YELLOW}  ⏭ Smoke HUB skipped — auth.s60hub.cz not reachable${NC}"
  TOTAL_SKIP=$((TOTAL_SKIP + 1))
  SUITE_RESULTS+=("{\"name\":\"Smoke HUB\",\"status\":\"SKIP\",\"pass\":0,\"fail\":0,\"skip\":1,\"duration_s\":0}")
fi

# 3. Smoke Prod — if reachable
if curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "https://auth.studio60.cz/api/health" 2>/dev/null | grep -q "200"; then
  run_suite "Smoke PROD" "bash /root/dev/s60-test/suites/smoke/run-smoke.sh prod all"
else
  log "${YELLOW}  ⏭ Smoke PROD skipped — auth.studio60.cz not reachable${NC}"
  TOTAL_SKIP=$((TOTAL_SKIP + 1))
  SUITE_RESULTS+=("{\"name\":\"Smoke PROD\",\"status\":\"SKIP\",\"pass\":0,\"fail\":0,\"skip\":1,\"duration_s\":0}")
fi

# 4. Integration tests (only if BE is up)
if curl -sk -o /dev/null -w "%{http_code}" --max-time 3 "https://be.s60dev.cz/health" 2>/dev/null | grep -q "200"; then
  run_suite "Integration: Auth ForwardAuth" "bash /root/dev/s60-test/suites/integration/auth-forwardauth.sh"
  run_suite "Integration: BadWolf Applications" "bash /root/dev/s60-test/suites/integration/badwolf-applications.sh"
  run_suite "Integration: S60Auth" "bash /root/dev/s60-test/suites/integration/s60auth.sh"
  run_suite "Integration: S60Mail" "bash /root/dev/s60-test/suites/integration/s60mail.sh"
else
  log "${YELLOW}  ⏭ Integration tests skipped — BE not reachable${NC}"
  TOTAL_SKIP=$((TOTAL_SKIP + 3))
  SUITE_RESULTS+=("{\"name\":\"Integration\",\"status\":\"SKIP\",\"pass\":0,\"fail\":0,\"skip\":3,\"duration_s\":0}")
fi

# 5. Regression tests (run all .sh files in regression dirs)
for dir in /root/dev/s60-test/suites/regression/*/; do
  module=$(basename "$dir")
  for test_file in "$dir"*.sh; do
    [ -f "$test_file" ] || continue
    test_name="Regression: ${module}/$(basename "$test_file" .sh)"
    run_suite "$test_name" "bash $test_file"
  done
done

# ============================================================
# Summary
TOTAL=$((TOTAL_PASS + TOTAL_FAIL))
log "\n${BLUE}=== DENNÍ SOUHRN ===${NC}"
log "  PASS: ${GREEN}$TOTAL_PASS${NC} / $TOTAL  |  FAIL: ${RED}$TOTAL_FAIL${NC}  |  SKIP: ${YELLOW}$TOTAL_SKIP${NC}"
log "  Log: $LOG_FILE"

# JSON report
SUITES_JSON=$(IFS=,; echo "[${SUITE_RESULTS[*]}]")
cat > "$REPORT_FILE" <<EOF
{
  "date": "$DATE",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "summary": {"pass": $TOTAL_PASS, "fail": $TOTAL_FAIL, "skip": $TOTAL_SKIP, "total": $TOTAL},
  "suites": $SUITES_JSON,
  "log_file": "$LOG_FILE"
}
EOF

log "  Report: $REPORT_FILE"

# ============================================================
# Report to PM
PASS_RATE=0
[ "$TOTAL" -gt 0 ] && PASS_RATE=$(( (TOTAL_PASS * 100) / TOTAL ))

STATUS_EMOJI="OK"
[ "$TOTAL_FAIL" -gt 0 ] && STATUS_EMOJI="FAIL"

# Build failure details
FAIL_DETAILS=""
if [ "$TOTAL_FAIL" -gt 0 ]; then
  FAIL_DETAILS=$(grep -E "❌ FAIL" "$LOG_FILE" | sed 's/\x1b\[[0-9;]*m//g' | head -10)
  FAIL_DETAILS=$'\n\nFailed tests:\n'"$FAIL_DETAILS"
fi

/root/dev/agent-messages/send-message.sh pm INFO \
  "Daily Test Report [$DATE]: $STATUS_EMOJI" \
  "$(cat <<EOF
S60 Daily Test Report — $DATE

Summary: $TOTAL_PASS/$TOTAL PASS ($PASS_RATE%) | $TOTAL_FAIL FAIL | $TOTAL_SKIP SKIP

Suites:
$(for r in "${SUITE_RESULTS[@]}"; do
  name=$(echo "$r" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['name'])" 2>/dev/null)
  st=$(echo "$r" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['status'])" 2>/dev/null)
  echo "  - $name: $st"
done)
$FAIL_DETAILS

Report: $REPORT_FILE
Log: $LOG_FILE
EOF
)" test

# Report to Kaizen (KPI tracking)
/root/dev/agent-messages/send-message.sh kaizen INFO \
  "TEST REPORT: [$DATE] $TOTAL_PASS/$TOTAL tests" \
  "$(cat <<KAIZEN_EOF
TEST REPORT: $DATE

Summary: $TOTAL_PASS/$TOTAL PASS ($PASS_RATE%) | $TOTAL_FAIL FAIL | $TOTAL_SKIP SKIP

Per-služba breakdown:
  S60Auth:   smoke + integration (ForwardAuth, S60Auth) + regression (4 testy)
  BadWolf:   smoke + integration (Applications) + regression (2 testy)
  Billit:    smoke + regression (scope, decimal, DI, RLS — 4 testy)
  S60Mail:   smoke + integration
  S60Venom:  smoke only
  S60Pulse:  smoke only
  Learnia:   regression (1 test)
  Nexus/KVT/NoGames/Moodle/n8n/Portal: bez pokrytí

Coverage: 6/13 služeb (46%)
KAIZEN_EOF
)" test

# If failures → also notify responsible agents
if [ "$TOTAL_FAIL" -gt 0 ]; then
  # Check which suites failed and notify responsible agents
  for r in "${SUITE_RESULTS[@]}"; do
    status=$(echo "$r" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['status'])" 2>/dev/null)
    name=$(echo "$r" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['name'])" 2>/dev/null)
    if [ "$status" = "FAIL" ]; then
      case "$name" in
        *BadWolf*|*badwolf*)
          /root/dev/agent-messages/send-message.sh badwolf INFO \
            "Daily test failure: $name" \
            "Test suite '$name' failed in daily run. Check: $LOG_FILE" test
          ;;
        *Auth*|*auth*)
          /root/dev/agent-messages/send-message.sh auth INFO \
            "Daily test failure: $name" \
            "Test suite '$name' failed in daily run. Check: $LOG_FILE" test
          ;;
        *Venom*|*venom*)
          /root/dev/agent-messages/send-message.sh venom INFO \
            "Daily test failure: $name" \
            "Test suite '$name' failed in daily run. Check: $LOG_FILE" test
          ;;
      esac
    fi
  done
fi

exit $TOTAL_FAIL
