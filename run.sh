#!/usr/bin/env bash
set -euo pipefail
LOCKFILE="/tmp/test-agent.lock"
AGENT_DIR="/root/projects/s60/s60-test"
LOG_FILE="$AGENT_DIR/state/iterations.log"
MAX_RUNTIME=600
mkdir -p "$AGENT_DIR/state"
if [ -f "$LOCKFILE" ]; then
  pid=$(cat "$LOCKFILE" 2>/dev/null || echo "")
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Skipped — still running (PID $pid)" >> "$LOG_FILE"
    exit 0
  fi
  rm -f "$LOCKFILE"
fi
echo $$ > "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT
cd "$AGENT_DIR"
# Set agent identity
export S60_AGENT="test"

# Idle check — skip claude if no messages in Redis queue
UNREAD=$(docker exec s60-redis redis-cli -a changeme123 --no-auth-warning LLEN agent:test:messages 2>/dev/null || echo "0")
if [ "${UNREAD:-0}" -eq 0 ] 2>/dev/null; then
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Idle — 0 unread, skipping claude" >> "$LOG_FILE"
  exit 0
fi
unset CLAUDECODE
ITER_NUM=$(grep -c "^\[" "$LOG_FILE" 2>/dev/null || echo "0")
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting iteration..." >> "$LOG_FILE"
timeout "$MAX_RUNTIME" claude --print \
  --no-session-persistence \
  --name "test-iter-${ITER_NUM}" \
  --max-budget-usd 0.50 \
  --fallback-model sonnet \
  -p "Jsi Test agent — zodpovídáš za testování celého S60 ekosystému v dev prostředí.

1. Zkontroluj zprávy: /root/dev/agent-messages/check-my-messages.sh test
2. Přečti state/current.md a state/backlog.md.
3. Zpracuj nové zprávy (TODO/URGENT mají přednost).
4. Pokud žádné zprávy — spusť testy a reportuj výsledky.
5. Aktualizuj state/current.md s reálnými výsledky.
6. Zapiš 1 řádek do state/iterations.log.

PRAVIDLA:
- POUZE čti cizí repozitáře — NIKDY v nich neměň kód
- Testy piš POUZE do /root/dev/s60-test/
- Reportuj REÁLNÉ výsledky — kolik testů SKUTEČNĚ prošlo/selhalo
- NEFALŠUJ reporty — pokud test neexistuje, řekni že neexistuje
- Při nálezu bugu pošli TODO zodpovědnému agentovi s popisem + failing test
- Taguj testy: @dev-only (default), @hub-safe, @prod-safe" \
  2>&1 | tail -5 >> "$LOG_FILE" || {
    EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 124 ]; then
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] TIMEOUT" >> "$LOG_FILE"
    else
      echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR code $EXIT_CODE" >> "$LOG_FILE"
    fi
  }
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Iteration complete." >> "$LOG_FILE"
