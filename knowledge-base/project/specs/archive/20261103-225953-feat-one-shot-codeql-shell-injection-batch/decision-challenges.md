# Decision Challenges — feat-one-shot-codeql-shell-injection-batch

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Fix vs leave-open for the two test-file alerts (302/303) | operator (scope) | Ruled by operator $ARGUMENTS, 2026-11-03: fix when a shape-preserving remediation exists; the temp-file `sh <file> <argv>` pattern (precedent PR #7566, alerts 213/214) is exactly that — fix, don't flag as false positive. |

Notes: no open technical forks survive into this table. The remediation shape (pure-Node `resolveBin` PATH walk; temp-file `sh` writers) is precedent-bound — decided by the plan's Phase 0.6b mechanism-minimality cut against the repo's proven fix for the same query (commit `f5f51c84b0`, PR #7566), not an open design question. `have()`'s unflagged `shell:` option and empty-PATH-entry handling are implementation detail recorded in the plan's Technical Considerations, not challenges. This harness has no Task/Agent spawn capability; had a genuine technical fork existed, the CTO seat would have been mandatory.
