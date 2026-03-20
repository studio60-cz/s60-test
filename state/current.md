# Test — aktuální stav

## Poslední run: 2026-03-20 19:38 UTC (scheduled)

### Coverage per služba

| Služba | Smoke DEV | Smoke HUB | Regression | Celkem testů |
|--------|-----------|-----------|------------|-------------|
| **S60Auth** | ✅ 4/4 | ✅ 4/4 | ✅ 21/21 (1 SKIP) | **29** |
| **S60BadWolf** | ✅ 3/3 | ✅ 3/3 | 0 (no TEST_TOKEN) | **6** |
| **S60Venom** | ❌ 502 | ✅ 1/1 (200) | — | **1** |
| **S60Pulse** | ✅ 5/5 | ✅ 5/5 | — | **10** |
| **Billit** | ✅ 1/1 | ✅ 1/1 | ✅ 14/14 (1 SKIP) | **16** |
| **S60Mail** | ✅ 1/1 | ⏭ SKIP (Tailscale) | ✅ 14/14 integration | **15** |
| **SSO Portál** | ✅ 1/1 (403) | ❌ 301 | — | **1** |
| **n8n** | ✅ 1/1 (403) | ✅ 1/1 (200) | — | **2** |
| **Learnia WP** | ✅ 1/1 | ✅ 1/1 | — | **2** |
| **KVT WP** | ✅ 1/1 | ✅ 1/1 | — | **2** |
| **NoGames WP** | ✅ 1/1 | ✅ 1/1 | — | **2** |
| **S60Nexus** | ✅ 1/1 | — | — | **1** |

**Celkem: ~119 PASS / 5 FAIL / 10 SKIP**
**Pokrytí: 11/12 služeb smoke DEV (92%), 9/12 HUB (75%)**

---

### Výsledky (2026-03-20 19:38 UTC)

| Suite | PASS | FAIL | SKIP | Status |
|-------|------|------|------|--------|
| **Smoke DEV** | **20** | **1** | **0** | ❌ Venom 502 |
| **Smoke HUB** | **19** | **1** | **1** | ❌ Portal 301, Mail SKIP |
| **Auth integration** | **25** | **0** | **2** | ✅ ALL PASS |
| **Mail integration** | **14** | **0** | **0** | ✅ ALL PASS |
| **BadWolf integration** | **2** | **0** | **0** | ✅ PASS |
| **Pulse integration** | **4** | **3** | **4** | ❌ Auth'd endpoints 401 |
| **Regression Auth** | **21** | **0** | **1** | ✅ ALL PASS |
| **Regression Billit** | **14** | **0** | **1** | ✅ ALL PASS |
| **Regression Apps** | **0** | **0** | **2** | ⏭ SKIP (no TEST_TOKEN) |

---

### Změny oproti 2026-03-17

- ✅ Billit regression: 14/14 PASS (bylo 4 FAIL — opraveny exports, products, invoices, orders)
- ✅ Mail integration: 14/14 PASS (nový suite — full CRUD)
- ✅ Nexus smoke: PASS (bylo not deployed)
- ❌ Venom DEV: 502 (bylo OK) — reported to venom
- ❌ Pulse auth'd endpoints: 401 (token rejected) — reported to pulse
- ❌ Portal HUB: 301 (bylo not deployed)

---

### Známé problémy

| Problém | Služba | Env | Status | Od |
|---------|--------|-----|--------|-----|
| Venom DEV 502 | Venom | DEV | NEW — reported | 2026-03-20 |
| Pulse auth'd endpoints 401 | Pulse | HUB | NEW — reported | 2026-03-20 |
| Portal HUB 301 (redirect) | Portal | HUB | Low priority | 2026-03-20 |
| Mail unreachable on HUB (Tailscale?) | Mail | HUB | Infra | 2026-03-15 |
| Applications regression needs TEST_TOKEN | BadWolf | DEV | Missing config | 2026-03-17 |

---

### Backlog: Co přidat

1. PROD smoke tests
2. BadWolf regression (potřeba TEST_TOKEN)
3. Rozšířit Pulse integration — fix auth token
4. Portal HUB — investigate 301
5. Billit JWT scope test (BILLIT_TEST_JWT_TOKEN)
