# Regression Tests

## Pravidlo: každý bug = nový test

1. Najdeš bug → napiš test který ho reprodukuje (MUSÍ failnout)
2. Bug se opraví → test MUSÍ projít
3. Test zůstane navždy (chrání před regresí)

## Struktura

```
regression/
├── applications/    # BadWolf — přihlášky
├── auth/            # S60Auth — tokeny, ForwardAuth
├── venom/           # Venom — UI, EditForm
├── orders/          # BadWolf — objednávky
└── mail/            # S60Mail — emaily
```

## Spuštění

```bash
# Jedna suite:
bash suites/regression/applications/missing-location-id.sh
bash suites/regression/auth/bad-token-rejection.sh

# Všechny regression testy pro oblast:
for f in suites/regression/applications/*.sh; do bash "$f"; done

# Všechny regression testy:
find suites/regression -name "*.sh" | sort | xargs -I{} bash {}
```

## Pojmenování souborů

`<popis-bugu>.sh` — lowercase, pomlčky, krátký popis co bug způsoboval

## Kdy spouštět

| Změna v | Spustit |
|---------|---------|
| ApplicationsModule | `regression/applications/` |
| S60Auth, ForwardAuth | `regression/auth/` |
| Venom frontend | `regression/venom/` |
| Release / deploy | **VŠECHNY** regression testy |

## Tracking

Každý test má comment s:
- Popis původního bugu
- Commit kde byl opraven (pokud znám)
- Jak reprodukovat
- Kam poslat bug report při selhání
