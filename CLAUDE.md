# s60-test — Test Infrastructure

**Project:** Unified testing infrastructure pro celý S60 ekosystém
**Purpose:** E2E, API, integration testy pro BadWolf, Venom, a další
**Agent:** test-runner (specialized subagent)

---

## 🔴 ABSOLUTNÍ ZÁKAZ — NIKDY NESAHEJ DO CIZÍHO REPO

**Tvůj repo je POUZE: `/root/dev/s60-test`**

```
❌ ZAKÁZÁNO — i kdyby si myslel že pomáháš:
  Měnit cokoliv v s60-badwolf/
  Měnit cokoliv v s60-venom/
  Měnit cokoliv v s60-auth/
  Měnit cokoliv kdekoliv jinde

✅ POVOLENO:
  Číst cizí repo (pro psaní testů)
  Spouštět testy (read-only operace)
  Poslat zprávu agentovi pokud najdeš bug
```

**Našel jsi bug v cizím kódu?**
```bash
/root/dev/agent-messages/redis-queue.sh send badwolf TODO "Bug nalezen" "Popis + test který failuje..." test
# → Neopravuj to sám. Reportuj a počkej.
```

**Toto pravidlo bylo opakovaně porušeno. Je to LAW — ne doporučení.**

---

## 🚨 MANDATORY: CHECK MESSAGES FIRST!

**BEFORE EVERY RESPONSE - NO EXCEPTIONS:**

```bash
/root/dev/agent-messages/check-my-messages.sh test
```

⚠️ **POVINNÉ:** První příkaz KAŽDÉ response!

**Proč:**
- Venom může požadovat VERIFY_FIX (TODO)
- BadWolf může mít nové API k testování (TODO)
- Main může mít nové priority (URGENT)
- Trvá <100ms

**Template každé response:**
```
Bash: /root/dev/agent-messages/check-my-messages.sh test
→ [zprávy nebo silent]
→ [pokračuj s testy]
```

---

## 🔌 MCP SERVERY (aktivní)

Máš přístup ke třem MCP serverům (sdílená konfigurace ~/.claude/settings.json):

### s60-docs — Filesystem
- `/root/dev/s60-docs/`, `/root/dev/KNOWLEDGE_BASE.md`, `/root/dev/CLAUDE.md`
- Použití: čtení dokumentace přes `mcp__s60-docs__read_file`
- Preferuj MCP před ručním Read tool pro docs soubory

### s60-database — PostgreSQL (s60_badwolf)
- Přímé SQL dotazy: `mcp__s60-database__query`
- Tabulky: `applications`, `clients`, `courses`, `online_courses`, `course_dates`, `locations`
- Použití: kontrola dat, debugging, analýzy

### s60-knowledge — Knowledge MCP Server
- Fulltext search přes všechny .md soubory: `mcp__s60-knowledge__search_docs query="..."`
- Poslední session notes: `mcp__s60-knowledge__get_session_notes lines=150`
- Zápis rozhodnutí: `mcp__s60-knowledge__log_decision text="..."`
- Info o službách: `mcp__s60-knowledge__get_service_info service="all"`
- Seznam docs: `mcp__s60-knowledge__list_docs`

### Kdy použít MCP vs Read tool:
- Docs (`s60-docs/`, `KNOWLEDGE_BASE.md`) → `mcp__s60-docs__read_file`
- SQL data → `mcp__s60-database__query`
- Fulltext search / session notes / rozhodnutí → `mcp__s60-knowledge__*`
- Kód aplikací (`src/`, atd.) → standardní Read tool

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

---

## 🚨 SERVER LIFECYCLE - KRITICKÉ PRAVIDLO

**NIKDY NESPOUŠTĚJ BE PŘÍMO!**

❌ DON'T:
- `npm run start:dev` (v s60-badwolf)
- `docker restart s60-badwolf`
- `pkill -f nest`

✅ DO: Send message to Main agent

```bash
/root/dev/agent-messages/redis-queue.sh send main \
  SERVER_START_REQUEST \
  "BE needed for E2E tests" \
  "Test agent needs BE running for Playwright tests" \
  test
```

**Workflow before running tests:**
1. Check if BE is responding (curl http://localhost:3000/health)
2. If not → send SERVER_START_REQUEST to Main
3. Wait for Main's response (BE ready notification)
4. Run tests

**Main agent zodpovídá za:**
- Start/restart BE serveru
- Check maintenance mode
- Prevence konfliktů s deployment
- Notify tě když je BE ready


---

## 📋 Freelo — Správné použití

**NIKDY nevolej Freelo API přímo. Vždy přes script:**

```bash
# READ (přímé, výsledek ihned):
/root/dev/agent-messages/freelo.sh list todo
/root/dev/agent-messages/freelo.sh list backlog
/root/dev/agent-messages/freelo.sh get <task_id>

# WRITE (přes frontu, worker zpracuje):
/root/dev/agent-messages/freelo.sh create   --list todo   --name "[PREFIX] Název"   --description "Popis..."   --from <agent>

/root/dev/agent-messages/freelo.sh finish <task_id> <agent>
/root/dev/agent-messages/freelo.sh move <task_id> inprogress <agent>
```

**Sloupce:** backlog (1761121) | todo (1761122) | inprogress (1761123) | done (1761124)
**Prefixy:** [BW] [VENOM] [AUTH] [WP] [KVT] [LEARNIA] [INFRA] [N8N] [EDGE] [BILLIT]
**Docs:** `/root/dev/agent-messages/FREELO_QUEUE.md`
