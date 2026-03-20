# Scheduled Run — hlavní proces test agenta

**Kdy:** Scheduler spustí task "Scheduled run: test" (cron nebo manuálně)
**Kdo:** test agent
**Účel:** Pravidelný health check + test run celého S60 ekosystému

---

## Postup

### 1. Check messages
```bash
/root/dev/agent-messages/check-my-messages.sh test
```
- Zpracuj URGENT/TODO zprávy (mohou změnit priority)
- Zaznamenej TEST_REQUESTy od sentinel/jiných agentů

### 2. Health check
```bash
curl -sk -o /dev/null -w "%{http_code}" https://api.s60dev.cz/health
```
- Očekáváno: 200 (nebo 403 pokud ForwardAuth blokuje)
- Pokud 000/timeout → SERVER_START_REQUEST to main, čekej

### 3. Smoke testy (dev)
```bash
bash /root/dev/s60-test/suites/smoke/run-smoke.sh dev all
```
- Testuje: auth, badwolf, venom, pulse, billit, mail, nexus, portál, n8n, WP weby
- Pokud FAIL → reportuj příslušnému agentovi

### 4. Integration testy
```bash
bash /root/dev/s60-test/suites/integration/s60auth.sh
bash /root/dev/s60-test/suites/integration/s60mail.sh
bash /root/dev/s60-test/suites/integration/badwolf-applications.sh
```

### 5. Zpracuj TEST_REQUESTy
- Od sentinel (po deployi) → spusť příslušné testy (smoke/integration/regression)
- Pulse testy běží proti **hub** (ne dev):
  ```bash
  bash /root/dev/s60-test/suites/smoke/pulse-smoke.sh hub
  bash /root/dev/s60-test/suites/integration/pulse.sh hub
  ```

### 6. Regression testy
```bash
# Auth
bash /root/dev/s60-test/suites/regression/auth/*.sh
# Billit
bash /root/dev/s60-test/suites/regression/billit/*.sh
# Applications
bash /root/dev/s60-test/suites/regression/applications/*.sh
```

### 7. Report
- Pošli výsledky sentinel (pokud TEST_REQUEST) a PM:
  ```bash
  /root/dev/agent-messages/send-message.sh sentinel INFO "TEST_RESULT ..." "..." test
  /root/dev/agent-messages/send-message.sh pm INFO "Test report" "..." test
  ```
- FAIL → pošli TODO příslušnému agentovi (badwolf/venom/auth/pulse/billit)

### 8. Ulož do memory
```bash
/root/projects/memory-worker/memory_client.sh test note "Scheduled run: X/Y PASS, failures: ..." "test,scheduled"
```

---

## Eskalace

| Situace | Akce |
|---------|------|
| BE nereaguje | SERVER_START_REQUEST → main |
| Venom 502 | TODO → venom |
| Auth FAIL | TODO → auth |
| Pulse FAIL | TODO → pulse |
| Billit FAIL | TODO → billit |
| Infra problém (DNS, nginx, certbot) | TODO → infra |

---

## Poznámky
- BE endpoint: `api.s60dev.cz` (dev), `api.s60hub.cz` (hub), `api.studio60.cz` (prod)
- Pulse nemá dev prostředí — testy vždy proti hub (`pulse.s60hub.cz`)
- Smoke testy blokují deploy (exit 1 = deploy blokován)
