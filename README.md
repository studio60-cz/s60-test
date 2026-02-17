# s60-test — Testing Infrastructure

Centralizované testy pro celý S60 ekosystém.

## Quick Start

```bash
# BadWolf smoke tests
./test-runner.sh badwolf smoke

# Venom E2E tests
./test-runner.sh venom-e2e applications

# All Venom tests
./test-runner.sh venom-e2e all
```

## Suites

**BadWolf API:**
- `smoke` — all endpoints quick check
- `applications`, `courses`, `locations`, `clients` — specific endpoints

**Venom E2E:**
- `all`, `navigation`, `applications`, `filters`, `crud`, `errors`

## Documentation

- **CLAUDE.md** — Agent instructions
- **TEST_AGENT_GUIDE.md** — Complete testing guide
- **test-runner.sh** — Main test script

## Requirements

- Node.js + npm
- Playwright (installed in s60-venom)
- curl + jq

## Architecture

```
Developer Agent (Venom/BadWolf)
    ↓
  Test Runner (this project)
    ↓
  Test Suites (Playwright, curl)
    ↓
  Results (PASS/FAIL + logs)
```

---

**Path:** `/root/dev/s60-test/test-runner.sh`
