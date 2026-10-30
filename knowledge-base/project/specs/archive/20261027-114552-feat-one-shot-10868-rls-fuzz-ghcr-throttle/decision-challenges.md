# Decision Challenges — feat-one-shot-10868-rls-fuzz-ghcr-throttle

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Retry placement: inline `run:` loop vs `supabase-local.sh` vs dedicated CI helper script | technical | Ruled by CTO agent, 2026-10-27: dedicated `.github/scripts/ghcr-pull-with-retry.sh` invoked by the workflow step - the only option inside an existing tested convention (`.github/scripts/` + `test-*.sh` siblings); keeps `supabase-local.sh`'s exit contract and local-dev callers untouched; keeps the whole mitigation CI-side where the failure lives |
| Retry signature breadth: any-nonzero vs multi-token vs `toomanyrequests`-only + rc≠2 exclusion | technical | Ruled by CTO agent, 2026-10-27: retry iff the attempt's own fresh log tail matches `toomanyrequests`, never on rc=2 - `Retrying after`/`failed to pull docker image`/`failed to display json stream` also fire on non-throttle failures (recovered internal retries, post-login `denied`) and misclassify; false-narrow fails loudly, false-broad masks deterministic bugs |
| Retry parameters: 3 attempts, sleeps 20s/45s env-overridable, per-attempt fresh log, tail re-emission | technical | Ruled by CTO agent, 2026-10-27: approved - the measured quota is per-minute (44000/minute) so 3 attempts + ~65s backoff spans the window proportionately; per-attempt log freshness is load-bearing (a stale signature must not authorize a retry over a later deterministic failure); re-emit the failing log's TAIL (~200 lines), never head-truncated |
| Retry signature tail-scoping + `2>&1` merge + `PIPESTATUS[0]` read + symmetric `::error::` on deterministic exit | technical | Ruled by CTO agent, 2026-10-27: folded from spec-flow P1-1/P1-2/P1-4/P2-6 - stderr merge and PIPESTATUS are load-bearing for classification correctness; only the terminal region of an attempt's log may classify it; non-throttle exits get the same ::error:: attribution as exhaustion |
| User-Brand threshold: none | technical | Ruled by CTO agent, 2026-10-27: `none` stands - CI-internal machinery diff, no user-facing surface or data path; scope-out line carried in `## User-Brand Impact` for the sensitive-paths regex |
