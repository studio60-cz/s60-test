# Test Agent Guide

**Datum:** 2026-02-17
**Účel:** Synchronní testování před commitem - žádné chyby nesmí projít do gitu

---

## 🎯 Filozofie

> **Agent netestuje = agent dělá stejné chyby pořád dokola**

**Zlaté pravidlo:**
```
IMPLEMENTACE → TEST → COMMIT
              ↑
         Pokud FAIL → OPRAV
```

**NIKDY:**
- ❌ Commit bez testů
- ❌ "Otestuji to příště"
- ❌ "Uživatel to otestuje"

**VŽDY:**
- ✅ Test PŘED commitem
- ✅ Pokud test selže → oprav TEĎKA
- ✅ Commit jen když je vše zelené

---

## 🧪 Test Runner

### Umístění
```bash
/root/dev/s60-tools/test-runner.sh
```

### Použití

**Syntax:**
```bash
/root/dev/s60-tools/test-runner.sh <project> <suite> [headless]
```

**Projekty:**
- `venom-e2e` — Venom E2E testy (Playwright)
- `venom-unit` — Venom unit testy (Vitest)
- `badwolf` — BadWolf API testy

**Suites (venom-e2e):**
- `all` — všechny E2E testy
- `navigation` — navigace mezi sekcemi
- `applications` — aplikace (list, detail, edit)
- `filters` — filtry a search
- `crud` — CRUD operace
- `errors` — error handling

**Suites (badwolf):**
- `smoke` — rychlé smoke testy (všechny endpoints)
- `applications` — GET /applications testy
- `courses` — GET /courses testy
- `locations` — GET /locations testy
- `clients` — GET /clients testy

---

## 📋 Kdy testovat co

### 1. Změna v Backend API (BadWolf)

**Po implementaci endpointu:**
```bash
# Quick smoke test (30s)
/root/dev/s60-tools/test-runner.sh badwolf smoke

# Specific endpoint test
/root/dev/s60-tools/test-runner.sh badwolf applications
```

**Pokud PASS:**
- ✅ Commit
- ✅ Push
- ✅ Pošli zprávu Venom agentovi: "API ready"

**Pokud FAIL:**
- ❌ NEOPOUŠTĚJ session dokud není opraveno!
- 🔧 Oprav chybu
- 🔄 Re-run test
- ✅ Pak commit

### 2. Změna v Frontend UI (Venom)

**Po změně komponenty:**
```bash
# Před commitem VŽDY:
/root/dev/s60-tools/test-runner.sh venom-e2e applications

# Nebo specifický test:
/root/dev/s60-tools/test-runner.sh venom-e2e filters
```

**Pokud PASS:**
- ✅ Commit
- ✅ Screenshot test (optional)
- ✅ Push

**Pokud FAIL:**
- ❌ DO NOT COMMIT!
- 🔧 Oprav podle error message
- 🔄 Re-run test
- ✅ Commit až je zelené

### 3. Změna API integrace (Venom ↔ BadWolf)

**Test OBOJÍ:**
```bash
# 1. Backend API test
/root/dev/s60-tools/test-runner.sh badwolf applications

# 2. Frontend E2E test
/root/dev/s60-tools/test-runner.sh venom-e2e applications

# Oboje MUSÍ být PASS!
```

---

## 🤖 Pro Claude Agents

### VENOM Agent

**POVINNÝ workflow PŘED každým commitem:**

```bash
# 1. Implementuj změnu
# ... kód ...

# 2. POVINNÉ: Test PŘED commitem
Bash: /root/dev/s60-tools/test-runner.sh venom-e2e applications

# 3a. Pokud PASS:
if test_passed:
    git commit -m "feat: implemented X"
    git push

# 3b. Pokud FAIL:
if test_failed:
    # ČTEŠ error message
    # OPRAVÍŠ chybu
    # RE-RUN test
    # COMMIT až je zelené
```

**Příklad chat flow:**

```
USER: "Přidej filter by course name"

VENOM:
1. Implementuji filter... DONE
2. Running tests...
   Bash: /root/dev/s60-tools/test-runner.sh venom-e2e filters

   Result: FAIL
   Error: "Filter input not found in DOM"

3. Opravuji chybu... (přidán data-testid)
4. Re-running tests...
   Bash: /root/dev/s60-tools/test-runner.sh venom-e2e filters

   Result: PASS ✅

5. Committing...
   git commit -m "feat: add course name filter"

✅ DONE - Filter funguje, testy prošly
```

### BADWOLF Agent

**POVINNÝ workflow:**

```bash
# 1. Implementuj endpoint
# ... NestJS controller/service ...

# 2. RESTART server (aby načetl nový kód)
Bash: npm run build
Bash: kill <PID> && nohup node dist/main &

# 3. POVINNÉ: Test API
Bash: /root/dev/s60-tools/test-runner.sh badwolf smoke

# 4a. Pokud PASS:
git commit -m "feat: add GET /endpoint"
git push

# Pošli zprávu Venom
/root/dev/agent-messages/redis-queue.sh send venom INFO \
  "New API endpoint ready" \
  "GET /endpoint is live and tested"

# 4b. Pokud FAIL:
# OPRAV → RE-TEST → COMMIT
```

---

## 🔍 Test Output Interpretace

### PASS (zelené)
```
[INFO] ✅ Venom E2E tests PASSED
All tests green, safe to commit
```

**Action:** Commit & Push

---

### FAIL (červené)
```
[ERROR] ❌ Venom E2E tests FAILED
See details: /tmp/playwright-output.log

Error: locator.click: Target closed
  at ApplicationsList.test.ts:45
```

**Action:**
1. Read `/tmp/playwright-output.log`
2. Pochop error
3. Oprav kód
4. Re-run test
5. NEOPOUŠTĚJ session dokud není zelené!

---

## 🚨 Co NIKDY nedělat

### ❌ BAD: Commit bez testu
```bash
# ŠPATNĚ!
git commit -m "feat: add filter"
git push
# (uživatel pak najde bug)
```

### ❌ BAD: Ignorovat failed test
```bash
# Test failed
# "No jo, opravim to priste..."
git commit  # ❌ ŠPATNĚ!
```

### ❌ BAD: "Test to uživatel"
```bash
# "Pusham to, user to otestuje"
# ❌ ŠPATNĚ! Agent testuje SAM!
```

---

## ✅ Co VŽDY dělat

### ✅ GOOD: Test-driven workflow
```bash
# 1. Implementuj
vim src/components/Filter.tsx

# 2. Test
/root/dev/s60-tools/test-runner.sh venom-e2e filters

# 3a. PASS → Commit
git commit -m "feat: add filter"

# 3b. FAIL → Oprav → Re-test → Commit
```

### ✅ GOOD: Opakuj test dokud není zelené
```bash
for attempt in {1..5}; do
    /root/dev/s60-tools/test-runner.sh venom-e2e filters
    if [ $? -eq 0 ]; then
        echo "✅ Tests passed on attempt $attempt"
        break
    else
        echo "❌ Attempt $attempt failed, fixing..."
        # FIX CODE HERE
    fi
done
```

---

## 📊 Test Metriky

**Cíle:**
- ⏱️ E2E tests: <60s
- ⏱️ API smoke tests: <10s
- ✅ Pass rate: >95%
- 🔄 Max re-runs: 3 (pak eskaluj na uživatele)

**Red flags:**
- ❌ Stejný test failuje 3× → structurální problém, ne jen typo
- ❌ Test trvá >2min → optimalizuj
- ❌ Flaky tests (někdy pass, někdy fail) → oprav test

---

## 🛠️ Troubleshooting

### "Venom dev server not running"
```bash
# Start dev server first
cd /root/dev/s60-venom
npm run dev &

# Then run tests
/root/dev/s60-tools/test-runner.sh venom-e2e all
```

### "BadWolf API not responding"
```bash
# Check if running
curl https://be.s60dev.cz/applications

# If not, restart
cd /root/dev/s60-badwolf
npm run build
# ... restart process
```

### "Test timeout"
```bash
# Playwright default timeout: 30s
# If test needs more time, increase in test file:
test.setTimeout(60000); // 60s
```

---

## 📝 Pro Test Agent (specialized subagent)

**Když dostaneš úkol "Test venom applications":**

```typescript
// 1. Check co testovat
const suite = extractSuite(prompt); // "applications"

// 2. Run test
const result = await Bash({
  command: `/root/dev/s60-tools/test-runner.sh venom-e2e ${suite}`,
  timeout: 120000 // 2 min
});

// 3. Parse výsledek
if (result.includes("PASSED")) {
  return {
    status: "PASS",
    message: "All tests green ✅"
  };
} else {
  return {
    status: "FAIL",
    errors: extractErrors(result),
    log: "/tmp/playwright-output.log"
  };
}
```

**Return format:**
```json
{
  "status": "PASS" | "FAIL",
  "duration": "45s",
  "passed": 12,
  "failed": 0,
  "errors": [],
  "screenshots": ["/tmp/test-results/..."],
  "log": "/tmp/playwright-output.log"
}
```

---

## 🎓 Best Practices

1. **Test často** — po každé změně, ne jednou denně
2. **Test rychle** — suite <60s, smoke <10s
3. **Test automaticky** — PŘED každým commitem
4. **Fix okamžitě** — FAIL = stop vše, oprav, re-test
5. **Komunikuj** — pošli výsledky relevant agentům

**Motto:**
> "If you didn't test it, it's broken" — Murphy's Law pro agenty

---

**Last updated:** 2026-02-17
**Status:** ✅ Production ready
