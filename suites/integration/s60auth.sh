#!/bin/bash
# S60Auth Integration Tests — P0
# Pokrývá: health, OIDC discovery, JWKS, token endpoint, ForwardAuth, userinfo
# Vyžaduje: TEST_TOKEN nebo TEST_EMAIL+TEST_PASSWORD v /root/dev/.env

set -euo pipefail

AUTH_URL=${AUTH_URL:-"https://auth.s60dev.cz"}
BE_URL=${BE_URL:-"https://be.s60dev.cz"}

# Load credentials
if [ -f "/root/dev/.env" ]; then
  source <(grep -E "^(TEST_TOKEN|TEST_EMAIL|TEST_PASSWORD|S60_TEST_CLIENT_ID|S60_TEST_CLIENT_SECRET)=" /root/dev/.env 2>/dev/null || true)
fi

PASS=0; FAIL=0; SKIP=0
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}✅ PASS${NC} [$1] $2"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}❌ FAIL${NC} [$1] $2"; [ -n "${3:-}" ] && echo -e "         $3"; FAIL=$((FAIL+1)); }
skip() { echo -e "  ${YELLOW}⏭ SKIP${NC} [$1] $2"; SKIP=$((SKIP+1)); }

check_status() {
  local id=$1 desc=$2 url=$3 expected=$4
  shift 4
  local code
  code=$(curl -sk "$@" -o /dev/null -w "%{http_code}" --max-time 8 "$url")
  [ "$code" = "$expected" ] && pass "$id" "$desc (HTTP $code)" || fail "$id" "$desc" "expected HTTP $expected, got $code"
}

check_body() {
  local id=$1 desc=$2 url=$3 needle=$4 extra_args="${5:-}"
  local body
  body=$(curl -sk $extra_args --max-time 8 "$url")
  echo "$body" | grep -q "$needle" && pass "$id" "$desc" || fail "$id" "$desc" "missing: '$needle' in response"
}

# ================================================================
echo -e "\n${BLUE}=== S60Auth Integration Tests ===${NC}\n"

# ----------------------------------------------------------------
echo -e "${YELLOW}-- 1. Health & Availability --${NC}"

check_status "auth-01" "GET /api/health → 200"          "$AUTH_URL/api/health"                   "200"
check_body   "auth-02" "/api/health returns S60-Auth"   "$AUTH_URL/api/health"                   "S60-Auth"
check_status "auth-03" "Frontend (/) → 200 (SPA)"       "$AUTH_URL/"                             "200"

# ----------------------------------------------------------------
echo -e "\n${YELLOW}-- 2. OIDC Discovery --${NC}"

check_status "auth-04" "GET /.well-known/openid-configuration → 200"  "$AUTH_URL/.well-known/openid-configuration"  "200"
check_body   "auth-05" "OIDC config has issuer"                        "$AUTH_URL/.well-known/openid-configuration"  '"issuer"'
check_body   "auth-06" "OIDC config has authorization_endpoint"        "$AUTH_URL/.well-known/openid-configuration"  '"authorization_endpoint"'
check_body   "auth-07" "OIDC config has token_endpoint"                "$AUTH_URL/.well-known/openid-configuration"  '"token_endpoint"'
check_body   "auth-08" "OIDC config has jwks_uri"                      "$AUTH_URL/.well-known/openid-configuration"  '"jwks_uri"'
check_body   "auth-09" "OIDC config has userinfo_endpoint"             "$AUTH_URL/.well-known/openid-configuration"  '"userinfo_endpoint"'
check_body   "auth-10" "OIDC issuer matches domain"                    "$AUTH_URL/.well-known/openid-configuration"  "auth.s60dev.cz"

# ----------------------------------------------------------------
echo -e "\n${YELLOW}-- 3. JWKS (Token Signing Keys) --${NC}"

check_status "auth-11" "GET /api/auth/oauth/jwks → 200"          "$AUTH_URL/api/auth/oauth/jwks"   "200"
check_body   "auth-12" "JWKS has 'keys' array"                   "$AUTH_URL/api/auth/oauth/jwks"   '"keys"'
check_body   "auth-13" "JWKS key has RSA type (kty: RSA)"        "$AUTH_URL/api/auth/oauth/jwks"   '"kty":"RSA"'
check_body   "auth-14" "JWKS key has modulus (n field)"          "$AUTH_URL/api/auth/oauth/jwks"   '"n":'

JWKS_COUNT=$(curl -sk "$AUTH_URL/api/auth/oauth/jwks" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('keys',[])))" 2>/dev/null || echo "0")
if [ "$JWKS_COUNT" -ge 1 ]; then
  pass "auth-15" "JWKS contains at least 1 key ($JWKS_COUNT found)"
else
  fail "auth-15" "JWKS is empty — no signing keys!"
fi

# ----------------------------------------------------------------
echo -e "\n${YELLOW}-- 4. Token Endpoint — Error Handling --${NC}"

# Missing body
code=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$AUTH_URL/api/auth/token" -H "Content-Type: application/json" -d '{}')
if [ "$code" = "400" ] || [ "$code" = "401" ] || [ "$code" = "422" ]; then
  pass "auth-16" "POST /token with empty body → $code (error handled)"
else
  fail "auth-16" "POST /token with empty body" "expected 400/401/422, got $code"
fi

# Wrong grant type
code=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$AUTH_URL/api/auth/token" \
  -H "Content-Type: application/json" \
  -d '{"grant_type":"invalid_grant"}')
if [ "$code" = "400" ] || [ "$code" = "401" ] || [ "$code" = "422" ]; then
  pass "auth-17" "POST /token with invalid grant_type → $code"
else
  fail "auth-17" "POST /token with invalid grant_type" "expected 4xx, got $code"
fi

# Wrong credentials
code=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$AUTH_URL/api/auth/token" \
  -H "Content-Type: application/json" \
  -d '{"grant_type":"password","email":"nonexistent@test.invalid","password":"wrongpass"}')
if [ "$code" = "400" ] || [ "$code" = "401" ] || [ "$code" = "403" ] || [ "$code" = "422" ]; then
  pass "auth-18" "POST /token with wrong credentials → $code (rejected)"
else
  fail "auth-18" "POST /token with wrong credentials" "expected 4xx, got $code"
fi

# ----------------------------------------------------------------
echo -e "\n${YELLOW}-- 5. Authorization Endpoint --${NC}"

# Missing required params → 400
code=$(curl -sk -o /dev/null -w "%{http_code}" "$AUTH_URL/api/auth/authorize")
if [ "$code" = "400" ] || [ "$code" = "302" ]; then
  pass "auth-19" "GET /authorize without params → $code"
else
  fail "auth-19" "GET /authorize without params" "expected 400 or redirect, got $code"
fi

# With required params → 302 redirect to login page
code=$(curl -sk -o /dev/null -w "%{http_code}" \
  "$AUTH_URL/api/auth/authorize?response_type=code&client_id=test&redirect_uri=https://test.local/callback&scope=openid")
if [ "$code" = "302" ] || [ "$code" = "200" ] || [ "$code" = "400" ]; then
  pass "auth-20" "GET /authorize with params → $code"
else
  fail "auth-20" "GET /authorize with params" "expected 302/200/400, got $code"
fi

# ----------------------------------------------------------------
echo -e "\n${YELLOW}-- 6. ForwardAuth (token validation) --${NC}"

check_status "auth-21" "ForwardAuth: no token → 401"              "$BE_URL/applications"   "401"
check_status "auth-22" "ForwardAuth: malformed token → 401"       "$BE_URL/applications"   "401"  -H "Authorization: Bearer bad.token"
check_status "auth-23" "ForwardAuth: fake RSA JWT → 401"          "$BE_URL/applications"   "401"  -H "Authorization: Bearer eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjMifQ.invalidsig"
check_status "auth-24" "ForwardAuth: public /health passes"        "$BE_URL/health"         "200"
check_status "auth-25" "ForwardAuth: public /courses passes"       "$BE_URL/courses"        "200"

# ----------------------------------------------------------------
echo -e "\n${YELLOW}-- 7. Userinfo Endpoint (requires valid token) --${NC}"

if [ -z "${TEST_TOKEN:-}" ] && [ -z "${TEST_EMAIL:-}" ]; then
  skip "auth-26" "Userinfo test — no TEST_TOKEN or TEST_EMAIL in env"
  skip "auth-27" "Token issuance test — no credentials in env"
  echo -e "  ${YELLOW}  Hint:${NC} Add TEST_TOKEN=<jwt> to /root/dev/.env to enable auth'd tests"
else
  # Get token if not already set
  if [ -z "${TEST_TOKEN:-}" ]; then
    TOKEN_RESP=$(curl -sk -X POST "$AUTH_URL/api/auth/token" \
      -H "Content-Type: application/json" \
      -d "{\"grant_type\":\"password\",\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")
    TEST_TOKEN=$(echo "$TOKEN_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
  fi

  if [ -z "$TEST_TOKEN" ]; then
    fail "auth-26" "Could not obtain token with provided credentials"
    skip "auth-27" "Userinfo — no valid token"
  else
    pass "auth-26" "Obtained access_token from /api/auth/token"

    code=$(curl -sk -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $TEST_TOKEN" \
      "$AUTH_URL/api/auth/userinfo")
    [ "$code" = "200" ] && pass "auth-27" "GET /userinfo with valid token → 200" || fail "auth-27" "GET /userinfo with valid token" "got $code"

    # Userinfo must return email
    body=$(curl -sk -H "Authorization: Bearer $TEST_TOKEN" "$AUTH_URL/api/auth/userinfo")
    echo "$body" | grep -q '"email"' && pass "auth-28" "Userinfo response contains email field" || fail "auth-28" "Userinfo response missing email"
    echo "$body" | grep -q '"sub"' && pass "auth-29" "Userinfo response contains sub (userId)" || fail "auth-29" "Userinfo response missing sub"

    # ForwardAuth with valid token → 200
    code=$(curl -sk -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TEST_TOKEN" "$BE_URL/applications")
    [ "$code" = "200" ] && pass "auth-30" "ForwardAuth: valid token → 200 on /applications" || fail "auth-30" "ForwardAuth with valid token" "got $code"
  fi
fi

# ================================================================
TOTAL=$((PASS + FAIL))
echo -e "\n${BLUE}=== VÝSLEDKY ===${NC}"
echo -e "  PASS: ${GREEN}$PASS${NC}  FAIL: ${RED}$FAIL${NC}  SKIP: ${YELLOW}$SKIP${NC}  TOTAL: $TOTAL"
[ $FAIL -eq 0 ] && echo -e "\n${GREEN}✅ S60Auth — ALL PASS${NC}" || echo -e "\n${RED}❌ S60Auth — $FAIL FAILURES${NC}"
exit $FAIL
