# Decision Challenges — feat-one-shot-11682-cmo-gate-stale-cwd

| Item | Class | Ruling |
|------|-------|--------|
| TIP fallback order: origin/<headRef> → refs/pull/N/head → HEAD | technical | mechanical — issue prescribes this order; origin-ref first matches the PR's pushed state, HEAD preserves pre-fix behavior |
| no `git fetch` of refs/pull/N/head inside the hook | technical | mechanical — PreToolUse hooks stay offline-tolerant; read-only rev-parse only |
| threshold `none` (User-Brand) | taste | threshold: none — internal hook machinery; challengeable |
