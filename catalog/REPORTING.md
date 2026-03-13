# Reporting Tool — Rozhodnutí

## Výběr: Allure Report ✅

**Proč Allure:**
- HTML reporty s trendy (pass/fail over time)
- Kategorie failures (regression, new failures, flaky)
- Screenshots a video embed pro Playwright testy
- CI-friendly (JSON → HTML v post-step)
- Integrace s Playwright přes `allure-playwright` reporter
- Integrace s bash testy přes allure-commandline

**Alternativy zvažovány:**
- Playwright HTML reporter — vestavěný, ale bez trendů
- Custom JSON → GitHub Pages — jednodušší, bez kategorií
- Allure ✅ — nejlepší poměr features/setup

## Instalace

```bash
# Allure CLI
npm install -g allure-commandline

# Playwright integration
cd /root/dev/s60-test
npm install --save-dev allure-playwright
```

## Použití

```bash
# Generuj report z výsledků
allure generate /tmp/allure-results -o /tmp/allure-report --clean

# Zobraz (lokálně)
allure open /tmp/allure-report

# Playwright s Allure reporterem
npx playwright test --reporter=allure-playwright
```

## Výstupní adresáře

- Raw results: `/tmp/allure-results/` (JSON, attachments)
- HTML report: `/tmp/allure-report/`
- Archiv: `/root/dev/s60-test/results/` (gitignored, lokální)

## Budoucí: Allure server

Pro trvalé trendy (histórie) nasadit Allure Server nebo použít
GitHub Actions artifact upload + GitHub Pages.
