# Decision Challenges — feat-one-shot-10094-slot-trigger-lease-legs

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Re-scope #10094 from "fix the red legs" to "verify + close" — fix already merged via #10001 five hours after the observed failing run | operator (scope) | pending - assumed: verify-and-close proceeds; legs verified green on four consecutive post-#10001 runs including the 2026-10-12 `schedule` run 38248356757 |
| Fold in closure of #3373 and #3221 (open code-review scope-outs whose re-evaluation criteria are verifiably met) alongside #10094 | operator (scope) | pending - assumed: fold-in per plan Phase 1.7.5 contract; both carry `do-not-autoclose`, so closure is a deliberate evidence-based act with mechanism citations |
| Dev function-body drift hypothesis — is `pg_proc.prosrc` probe required before closing? | technical | pending - assumed: not required — green legs bound the live threshold to (60 s, 300 s); probe retained as optional non-blocking corroboration (no Agent tool available to spawn soleur:engineering:cto) |
