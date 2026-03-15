# Test — aktuální stav

## Poslední run: 2026-03-15 (daily cron)

### Coverage per služba

| Služba | Smoke | Integration | Regression | E2E | Pokrytí |
|--------|-------|-------------|------------|-----|---------|
| **S60Auth** | ✅ dev/hub/prod | ✅ 2 suites | ✅ 4 testy | ❌ | Dobrá |
| **S60BadWolf** | ✅ dev/hub/prod | ✅ 1 suite | ✅ 2 testy | ❌ | Dobrá |
| **Billit** | ✅ dev/hub/prod | ❌ | ✅ 4 testy | ❌ | Střední |
| **S60Mail** | ✅ dev | ✅ 1 suite | ❌ | ❌ | Střední |
| **S60Venom** | ✅ dev/hub/prod | ❌ | ❌ | ❌ | Slabá |
| **S60Pulse** | ✅ dev/hub/prod | ❌ | ❌ | ❌ | Slabá |
| **Learnia** | ❌ | ❌ | ✅ 1 test | ❌ | Slabá |
| **S60Nexus** | ❌ | ❌ | ❌ | ❌ | Žádná |
| **KVT** | ❌ | ❌ | ❌ | ❌ | Žádná |
| **NoGames** | ❌ | ❌ | ❌ | ❌ | Žádná |
| **Moodle** | ❌ | ❌ | ❌ | ❌ | Žádná |
| **n8n** | ❌ | ❌ | ❌ | ❌ | Žádná |
| **SSO Portál** | ❌ | ❌ | ❌ | ❌ | Žádná |

**Pokrytí: 6/13 služeb (46%) — 17 testových souborů**

---

### Výsledky posledního daily runu (2026-03-14)

| Suite | PASS | FAIL | SKIP | Status |
|-------|------|------|------|--------|
| Smoke DEV | ~8 | 6 | 0 | FAIL — auth 502 (lokální PG) |
| Smoke HUB | ~6 | 2 | 0 | FAIL — badwolf courses 500 |
| Smoke PROD | ~4 | 3 | 3 | FAIL — not deployed |
| Integration: ForwardAuth | 5 | 3 | 0 | FAIL — auth down |
| Integration: BadWolf Apps | 2 | 0 | 0 | ✅ PASS |
| Integration: S60Auth | 0 | 19 | 0 | FAIL — auth down |
| Regression: applications | 0 | 0 | 5 | SKIP — no token |
| Regression: auth | 5 | 3 | 0 | FAIL — auth down |
| Regression: billit | 8 | 4 | 2 | PARTIAL |
| Regression: learnia | 0 | 1 | 0 | FAIL — timeout |
| **F-162 HUB (ad-hoc)** | **6** | **0** | **1** | **✅ PASS** |

**Root cause:** S60Auth DEV přepnut na lokální PG (workaround) → kaskáda auth failures.

---

### Známé problémy

| Problém | Služba | Status |
|---------|--------|--------|
| Auth DEV → lokální PG místo DO Managed PG | S60Auth | Eskalováno main |
| S60Mail DEV 502 | S60Mail | Persistentní |
| Billit DEV /invoices 404 | Billit | Not deployed locally |
| Billit PROD → HTTP 301 | Billit | HTTPS config issue |
| TEST_TOKEN not set → auth testy skipnuty | Auth/BadWolf | Chybí config |
| Learnia uppercase course codes | Learnia | Bug u badwolf |

---

### Backlog: Co přidat

1. S60Nexus smoke + integration
2. SSO Portál smoke
3. n8n health check
4. KVT, NoGames WP smoke
5. Moodle (přes BadWolf /courses)
