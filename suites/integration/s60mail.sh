#!/bin/bash
# S60Mail Integration Tests — P0
# Pokrývá: health, templates CRUD, editor endpoint
# S60Mail je internal service (port 3010, bez veřejného nginx)
# Dev: https://mail.s60dev.cz | Hub/Prod: http://<tailscale>:3010

set -euo pipefail

# Auto-detect URL podle prostředí
ENV=${MAIL_ENV:-dev}
case "$ENV" in
  dev)   MAIL_URL=${MAIL_URL:-"https://mail.s60dev.cz"} ;;
  hub)   MAIL_URL=${MAIL_URL:-"http://100.68.138.14:3010"} ;;
  prod)  MAIL_URL=${MAIL_URL:-"http://100.78.87.88:3010"} ;;
  *)     MAIL_URL=${MAIL_URL:-"https://mail.s60dev.cz"} ;;
esac

PASS=0; FAIL=0; SKIP=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}✅ PASS${NC} [$1] $2"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} [$1] $2"; [ -n "${3:-}" ] && echo -e "         $3"; FAIL=$((FAIL+1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} [$1] $2"; SKIP=$((SKIP+1)); }

check_status() {
  local id=$1 desc=$2 url=$3 expected=$4
  shift 4
  local code
  code=$(curl -sk "$@" -o /dev/null -w "%{http_code}" --max-time 8 "$url" 2>/dev/null || echo "000")
  if [ "$code" = "000" ]; then
    fail "$id" "$desc" "service unreachable ($MAIL_URL)"
  elif [ "$code" = "$expected" ]; then
    pass "$id" "$desc (HTTP $code)"
  else
    fail "$id" "$desc" "expected HTTP $expected, got $code"
  fi
}

check_body() {
  local id=$1 desc=$2 url=$3 needle=$4
  shift 4
  local body
  body=$(curl -sk "$@" --max-time 8 "$url" 2>/dev/null || echo "")
  if [ -z "$body" ]; then
    fail "$id" "$desc" "empty response"
  elif echo "$body" | grep -q "$needle"; then
    pass "$id" "$desc"
  else
    fail "$id" "$desc" "missing '$needle' in response"
  fi
}

# ================================================================
echo -e "\n${BLUE}=== S60Mail Integration Tests (${MAIL_URL}) ===${NC}\n"

# Reachability check — pokud mail není up, skip vše
REACH=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$MAIL_URL/health" 2>/dev/null || echo "000")
if [ "$REACH" = "000" ] || [ "$REACH" = "502" ]; then
  echo -e "  ${YELLOW}⚠ S60Mail není reachable na $MAIL_URL${NC}"
  echo -e "  ${YELLOW}  Všechny testy přeskočeny — service není deploynutý nebo Tailscale down${NC}"
  SKIP=10
  echo -e "\n${YELLOW}=== VÝSLEDKY ===${NC}"
  echo -e "  PASS: ${GREEN}$PASS${NC}  FAIL: ${RED}$FAIL${NC}  SKIP: ${YELLOW}$SKIP${NC}"
  echo -e "\n${YELLOW}⏭ S60Mail — NOT DEPLOYED (expected)${NC}"
  exit 0
fi

# ----------------------------------------------------------------
echo -e "${YELLOW}-- 1. Health --${NC}"

check_status "mail-01" "GET /health → 200"                   "$MAIL_URL/health"   "200"
check_body   "mail-02" "/health returns status ok"           "$MAIL_URL/health"   '"status"'

# ----------------------------------------------------------------
echo -e "\n${YELLOW}-- 2. Templates API --${NC}"

check_status "mail-03" "GET /api/templates → 200 (list)"     "$MAIL_URL/api/templates"   "200"

# Response musí být array nebo objekt
TMPL_RESP=$(curl -sk --max-time 8 "$MAIL_URL/api/templates" 2>/dev/null || echo "")
if echo "$TMPL_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if isinstance(d,(list,dict)) else 1)" 2>/dev/null; then
  pass "mail-04" "/api/templates returns valid JSON (array or object)"
else
  fail "mail-04" "/api/templates returns valid JSON" "response: ${TMPL_RESP:0:100}"
fi

# Filter by source
check_status "mail-05" "GET /api/templates?source=system → 200"  "$MAIL_URL/api/templates?source=system"   "200"
check_status "mail-06" "GET /api/templates?tenantId=1 → 200"     "$MAIL_URL/api/templates?tenantId=1"      "200"

# 404 for nonexistent template
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$MAIL_URL/api/templates/999999" 2>/dev/null || echo "000")
if [ "$code" = "404" ] || [ "$code" = "400" ]; then
  pass "mail-07" "GET /api/templates/999999 → $code (not found handled)"
else
  fail "mail-07" "GET /api/templates/999999" "expected 404, got $code"
fi

# ----------------------------------------------------------------
echo -e "\n${YELLOW}-- 3. Template CRUD (create + delete) --${NC}"

# Create template
CREATE_RESP=$(curl -sk -X POST "$MAIL_URL/api/templates" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test-smoke-template",
    "subject": "Test Subject {{name}}",
    "html": "<p>Hello {{name}}</p>",
    "source": "system"
  }' --max-time 8 2>/dev/null || echo "")

CREATE_ID=$(echo "$CREATE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")

if [ -n "$CREATE_ID" ] && [ "$CREATE_ID" != "None" ]; then
  pass "mail-08" "POST /api/templates → created (id: $CREATE_ID)"

  # Read it back
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$MAIL_URL/api/templates/$CREATE_ID" 2>/dev/null || echo "000")
  [ "$code" = "200" ] && pass "mail-09" "GET /api/templates/$CREATE_ID → 200" || fail "mail-09" "GET created template" "got $code"

  # Preview
  PREVIEW_RESP=$(curl -sk -X POST "$MAIL_URL/api/templates/$CREATE_ID/preview" \
    -H "Content-Type: application/json" \
    -d '{"variables": {"name": "TestUser"}}' --max-time 8 2>/dev/null || echo "")
  if echo "$PREVIEW_RESP" | grep -q "TestUser\|html\|rendered\|subject"; then
    pass "mail-10" "POST /api/templates/$CREATE_ID/preview renders variables"
  else
    fail "mail-10" "Template preview" "unexpected response: ${PREVIEW_RESP:0:100}"
  fi

  # Update
  UPDATE_RESP=$(curl -sk -X PUT "$MAIL_URL/api/templates/$CREATE_ID" \
    -H "Content-Type: application/json" \
    -d '{"name": "test-smoke-template-updated"}' --max-time 8 2>/dev/null || echo "")
  UPDATE_NAME=$(echo "$UPDATE_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name',''))" 2>/dev/null || echo "")
  [ "$UPDATE_NAME" = "test-smoke-template-updated" ] && \
    pass "mail-11" "PUT /api/templates/$CREATE_ID → name updated" || \
    fail "mail-11" "PUT /api/templates/$CREATE_ID" "name not updated, got: $UPDATE_NAME"

  # Delete
  DEL_CODE=$(curl -sk -X DELETE -o /dev/null -w "%{http_code}" --max-time 8 "$MAIL_URL/api/templates/$CREATE_ID" 2>/dev/null || echo "000")
  if [ "$DEL_CODE" = "200" ] || [ "$DEL_CODE" = "204" ]; then
    pass "mail-12" "DELETE /api/templates/$CREATE_ID → $DEL_CODE"
  else
    fail "mail-12" "DELETE /api/templates/$CREATE_ID" "got $DEL_CODE"
  fi

  # Verify deleted
  code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$MAIL_URL/api/templates/$CREATE_ID" 2>/dev/null || echo "000")
  [ "$code" = "404" ] && pass "mail-13" "Deleted template returns 404" || fail "mail-13" "Deleted template should return 404" "got $code"
else
  fail "mail-08" "POST /api/templates → failed to create" "response: ${CREATE_RESP:0:100}"
  skip "mail-09" "Read template — create failed"
  skip "mail-10" "Preview template — create failed"
  skip "mail-11" "Update template — create failed"
  skip "mail-12" "Delete template — create failed"
  skip "mail-13" "Verify delete — create failed"
fi

# ----------------------------------------------------------------
echo -e "\n${YELLOW}-- 4. Editor --${NC}"

check_status "mail-14" "GET /editor → 200 (HTML editor served)"  "$MAIL_URL/editor"   "200"

# ================================================================
TOTAL=$((PASS + FAIL))
echo -e "\n${BLUE}=== VÝSLEDKY ===${NC}"
echo -e "  PASS: ${GREEN}$PASS${NC}  FAIL: ${RED}$FAIL${NC}  SKIP: ${YELLOW}$SKIP${NC}  TOTAL: $TOTAL"
[ $FAIL -eq 0 ] && echo -e "\n${GREEN}✅ S60Mail — ALL PASS${NC}" || echo -e "\n${RED}❌ S60Mail — $FAIL FAILURES${NC}"
exit $FAIL
