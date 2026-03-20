# Test Agent — Katalog procesů

Před každým servisním úkonem najdi odpovídající proces zde.
Pokud proces neexistuje, vytvoř ho po dokončení úkonu.

## Procesy

| Proces | Soubor | Kdy použít |
|--------|--------|------------|
| **Scheduled run** | [`docs/runbooks/scheduled-run.md`](runbooks/scheduled-run.md) | Scheduler task / manuálně — hlavní proces test agenta |
| Denní test run | `daily-test-run.sh` | Každý den 6:03 UTC (cron), nebo manuálně |
| Smoke testy | `suites/smoke/run-smoke.sh` | Po deployi, nebo ad-hoc health check |
| S60Auth integration | `suites/integration/s60auth.sh` | Po změnách v auth, OIDC, ForwardAuth |
| S60Mail integration | `suites/integration/s60mail.sh` | Po změnách v mail service |
| BadWolf integration | `suites/integration/badwolf-applications.sh` | Po změnách v applications API |
| Regression testy | `suites/regression/*/` | Po každém bug fixu (vytvoř nový test) |

---

## ⛔ CO NENÍ MÁ ZODPOVĚDNOST

| Požadavek | Komu předat | Proč |
|-----------|-------------|------|
| Nginx konfigurace (`/etc/nginx/sites-enabled/`, `nginx -s reload`) | **infra** | Pravidlo 2026-03-14: Nginx smí měnit POUZE infra agent |
| Restart/start BE serveru (`npm run start:dev`, `docker restart`) | **main** | Server lifecycle = Main agent (SERVER_START_REQUEST) |
| Oprava bugů v aplikačním kódu | **badwolf / auth / venom / billit** | Test agent reportuje, neopravuje |
| Deploy na staging/prod | **sentinel** | Deploy orchestrace = Sentinel |
| Infrastrukturní změny (Docker, sítě, DNS) | **infra** | Infra agent |
| DB migrace | **badwolf** (nebo příslušný service owner) | Test agent nespouští migrace |
| WordPress / Bricks změny | **wp / cms-\*** | Mimo scope test agenta |

**Pravidlo:** Pokud uživatel požádá o něco z tohoto seznamu → odmítni a řekni komu to patří.

---

_Katalog se naplní postupně. Po každém servisním úkonu přidej nový runbook._
