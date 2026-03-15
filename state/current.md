# Test — aktuální stav

## Poslední run: 2026-03-15 05:13 UTC

### Smoke tests (dev): 13/15 PASS
- ❌ `billit-smoke-health` — Billit dev vrací HTTP 500 (was OK last run)
- ❌ `mail-smoke-health` — S60Mail vrací HTTP 502 (service down)
- ✅ auth (4/4), badwolf (3/3), venom (1/1), pulse (5/5)

### Regression: billit/api-key-scope-enforcement (HUB): 0/4 PASS, 4 FAIL, 2 SKIP
- ❌ ALL API key tests return 401 — keys not recognized on hub
- Scénáře 1-4: 401 místo expected 403/200/403/201
- Scénář 5: SKIP (no JWT token configured)
- Scénář 6: 401 místo 403
- **Root cause:** API key test data likely not inserted into s60_billit_hub DB
- **Reportováno billit agentovi** s detaily

### Integration tests (dev): 35/35 PASS, 12 SKIP (unchanged)

### Previous regression (dev): 23/28 PASS, 5 FAIL, 6 SKIP (unchanged)

## Celkový souhrn
- **Smoke:** 13/15 PASS (86.7%)
- **Regression F-162 HUB:** 0/4 PASS — blocked on test data
- **Integration:** 35/35 PASS

## Známé problémy
- S60Mail service down na dev (HTTP 502) — persistent
- Billit dev health returning 500 (NEW — was 200 last run)
- Billit HUB: API key test data missing/invalid → all F-162 tests fail with 401
- Billit dev /invoices endpoint vrací 404 (not deployed)
- Learnia: uppercase course codes v DB
- TEST_TOKEN not configured → 12 auth'd tests skipped
