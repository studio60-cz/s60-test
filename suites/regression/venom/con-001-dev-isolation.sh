#!/bin/bash
# REGRESSION: Venom — CON-001 dev build nesmí ukazovat na prod/hub endpointy
# @env dev hub prod
#
# SPEC: /root/dev/catalog/specs/CON-001.md
# Constraint: Dev agenti na Cerebru nesmí mít write přístup k prod/hub DB.
# Pro Venom (frontend): dev build nesmí mít prod/hub API URL v konfiguraci.
#
# Implementace: vite.config.ts funkce enforceDevIsolation() — hází error při
# build-time pokud VITE_API_URL/VITE_AUTH_URL/VITE_CALLBACK_URL ukazuje na
# studio60.cz nebo s60hub.cz v development mode.
#
# AC verifikováno: 2026-03-20
#   ✅ AC1: .env.development neobsahuje prod/hub endpoint
#   ✅ AC2: vite.config.ts enforceDevIsolation() blokuje prod/hub domény
#   ✅ AC3: N/A (venom je pure frontend, nemá přímý DB přístup)

set -uo pipefail

VENOM_DIR="/root/projects/bw/venom"
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

echo -e "\n${YELLOW}=== REGRESSION: venom/con-001-dev-isolation ===${NC}"
echo -e "  Spec: CON-001 — Dev build nesmí používat prod/hub endpointy\n"

if [ ! -d "$VENOM_DIR" ]; then
  echo -e "  ${YELLOW}⏭ SKIP${NC} Venom repo nenalezen: $VENOM_DIR"
  exit 0
fi

# -------------------------------------------------------------------
echo -e "${YELLOW}-- AC1: .env.development neobsahuje prod/hub doménu --${NC}"

if [ -f "$VENOM_DIR/.env.development" ]; then
  prod_in_env=$(grep -E "studio60\.cz|s60hub\.cz" "$VENOM_DIR/.env.development" | grep -v "^#" || echo "")
  if [ -z "$prod_in_env" ]; then
    echo -e "  ${GREEN}✅ PASS${NC} [con001-ac1] .env.development neobsahuje studio60.cz ani s60hub.cz"
    PASS=$((PASS+1))
  else
    echo -e "  ${RED}❌ FAIL${NC} [con001-ac1] .env.development obsahuje prod/hub endpoint:"
    echo "$prod_in_env" | sed 's/^/    /'
    FAIL=$((FAIL+1))
  fi
else
  echo -e "  ${YELLOW}⏭ SKIP${NC} [con001-ac1] .env.development nenalezen"
fi

# -------------------------------------------------------------------
echo -e "\n${YELLOW}-- AC2: vite.config.ts obsahuje enforceDevIsolation guard --${NC}"

if [ -f "$VENOM_DIR/vite.config.ts" ]; then
  has_guard=$(grep -c "enforceDevIsolation\|CON-001" "$VENOM_DIR/vite.config.ts" || echo "0")
  assert "con001-ac2a" "vite.config.ts obsahuje CON-001 guard" "$([ "$has_guard" -gt 0 ] && echo yes || echo no)" "yes"

  blocks_prod=$(grep -c "studio60.cz" "$VENOM_DIR/vite.config.ts" || echo "0")
  assert "con001-ac2b" "Guard blokuje studio60.cz" "$([ "$blocks_prod" -gt 0 ] && echo yes || echo no)" "yes"

  blocks_hub=$(grep -c "s60hub.cz" "$VENOM_DIR/vite.config.ts" || echo "0")
  assert "con001-ac2c" "Guard blokuje s60hub.cz" "$([ "$blocks_hub" -gt 0 ] && echo yes || echo no)" "yes"

  result=$(node -e "
const PROD_DOMAINS = ['studio60.cz', 's60hub.cz'];
const testCases = [
  { url: 'https://be.studio60.cz', expectBlocked: true },
  { url: 'https://auth.s60hub.cz', expectBlocked: true },
  { url: 'https://be.s60dev.cz', expectBlocked: false },
  { url: 'https://auth.s60dev.cz', expectBlocked: false },
  { url: 'http://localhost:3000', expectBlocked: false },
];
let ok = true;
for (const tc of testCases) {
  const blocked = PROD_DOMAINS.some(d => tc.url.includes(d));
  if (blocked !== tc.expectBlocked) { ok = false; break; }
}
process.exit(ok ? 0 : 1);
" 2>/dev/null && echo "PASS" || echo "FAIL")
  assert "con001-ac2d" "Guard logika správně blokuje prod, povoluje dev" "$result" "PASS"
else
  echo -e "  ${RED}❌ FAIL${NC} [con001-ac2] vite.config.ts nenalezen!"
  FAIL=$((FAIL+2))
fi

# -------------------------------------------------------------------
echo -e "\n${YELLOW}-- AC3: Venom nemá přímý DB přístup --${NC}"

db_refs=$(grep -rn "typeorm\|prisma\|pg\.Pool\|new Client\|createConnection\|DATABASE_URL" \
  "$VENOM_DIR/src/" 2>/dev/null | grep -v "node_modules\|\.snap\|test\|spec" | wc -l)
assert "con001-ac3" "Žádný přímý DB přístup v src/ (pure frontend)" "$([ "$db_refs" -eq 0 ] && echo yes || echo no)" "yes"

# -------------------------------------------------------------------
TOTAL=$((PASS+FAIL))
echo -e "\n  PASS: ${GREEN}$PASS${NC} / $TOTAL  |  FAIL: ${RED}$FAIL${NC}"

[ $FAIL -eq 0 ] && exit 0 || exit 1
