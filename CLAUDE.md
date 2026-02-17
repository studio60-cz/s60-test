# s60-test — Test Infrastructure

**Project:** Unified testing infrastructure pro celý S60 ekosystém
**Purpose:** E2E, API, integration testy pro BadWolf, Venom, a další
**Agent:** test-runner (specialized subagent)

---

## Přehled

Centralizovaná testing infrastruktura pro všechny S60 projekty:
- **BadWolf API tests** — smoke tests, endpoint tests
- **Venom E2E tests** — Playwright UI tests
- **Integration tests** — cross-service tests
- **Performance tests** — load testing, benchmarks

---

## Struktura

```
s60-test/
├── test-runner.sh          # Main test runner (unified entry point)
├── lib/                    # Test utilities, helpers
├── suites/
│   ├── badwolf/           # BadWolf API test suites
│   ├── venom/             # Venom E2E test suites (Playwright)
│   └── integration/       # Integration tests (cross-service)
├── results/               # Test results (gitignored)
├── screenshots/           # Test screenshots (gitignored)
├── TEST_AGENT_GUIDE.md    # Complete testing guide
├── CLAUDE.md              # This file
└── README.md              # Quick start
```

---

## Usage

### Quick Tests

```bash
# BadWolf smoke tests (all endpoints)
/root/dev/s60-test/test-runner.sh badwolf smoke

# Venom E2E tests (applications)
/root/dev/s60-test/test-runner.sh venom-e2e applications

# All Venom tests
/root/dev/s60-test/test-runner.sh venom-e2e all
```

### Test Suites

**BadWolf:**
- `smoke` — quick smoke tests (all endpoints)
- `applications` — /applications endpoint tests
- `courses` — /courses endpoint tests
- `locations` — /locations endpoint tests
- `clients` — /clients endpoint tests

**Venom:**
- `all` — všechny E2E testy
- `navigation` — navigace mezi sekcemi
- `applications` — aplikace (list, detail, edit)
- `filters` — filtry a search
- `crud` — CRUD operace
- `errors` — error handling

---

## For Test Agent (Specialized Subagent)

**Role:** Spouští testy na požádání od developer agentů

**Workflow:**

```bash
# 1. Agent (Venom/BadWolf) pošle zprávu
"Test request: venom-e2e applications"

# 2. Test agent spustí test
/root/dev/s60-test/test-runner.sh venom-e2e applications

# 3. Vrátí výsledek
{
  "status": "PASS" | "FAIL",
  "duration": "45s",
  "errors": [...],
  "log": "/tmp/playwright-output.log"
}
```

**Capabilities:**
- ✅ Spustí libovolný test suite
- ✅ Parsuje výsledky (PASS/FAIL)
- ✅ Extrahuje error messages
- ✅ Vrací strukturovaný report
- ✅ Rychlá odpověď (<60s pro E2E, <10s pro API)

---

## Integration with Developer Agents

### Venom Agent

**POVINNÉ před každým commitem:**

```bash
# Po implementaci změny
Bash: /root/dev/s60-test/test-runner.sh venom-e2e applications

# Pokud FAIL → OPRAV → RE-TEST
# Pokud PASS → Commit
```

### BadWolf Agent

**Po implementaci endpointu:**

```bash
# Smoke test
Bash: /root/dev/s60-test/test-runner.sh badwolf smoke

# Nebo specifický endpoint
Bash: /root/dev/s60-test/test-runner.sh badwolf applications
```

---

## Test Results

**Location:** `/tmp/test-results/`

**Format:**
```
venom-e2e-applications-20260217_143052.json
badwolf-api-smoke-20260217_143100.json
```

**Logs:** `/tmp/playwright-output.log`, `/tmp/vitest-output.log`

---

## Extending

### Add New Test Suite

```bash
# 1. Create suite file
vim suites/venom/my-new-test.spec.ts

# 2. Add to test-runner.sh
# (already supports any .spec.ts file)

# 3. Run
/root/dev/s60-test/test-runner.sh venom-e2e my-new-test
```

### Add New Project

```bash
# Edit test-runner.sh, add new project case:
"my-project")
    test_my_project_api "$SUITE"
    ;;
```

---

## Dependencies

**Required:**
- Node.js + npm (for Playwright)
- curl + jq (for API tests)
- Playwright browsers installed

**Installation:**
```bash
cd /root/dev/s60-venom
npx playwright install
```

---

## Configuration

**Environment:**
- `VENOM_URL` — Venom dev server (default: http://localhost:5173)
- `BADWOLF_URL` — BadWolf API (default: https://be.s60dev.cz)

---

## Best Practices

1. **Test často** — po každé změně
2. **Test rychle** — suite <60s
3. **Test automaticky** — před každým commitem
4. **Fix okamžitě** — FAIL = stop, oprav, re-test

**Motto:**
> "If you didn't test it, it's broken"

---

## For Main Agent

**Kdy spustit test agent:**

```typescript
// Po implementaci feature v Venom/BadWolf
await Task({
  subagent_type: "test-runner",
  description: "Test Venom applications",
  prompt: `
    Run E2E tests for Venom applications module.
    Return PASS/FAIL with details.
  `
});

// Agent automaticky spustí:
// /root/dev/s60-test/test-runner.sh venom-e2e applications
```

---

**Last updated:** 2026-02-17
**Status:** ✅ Production ready
