# Decision Challenges — feat-one-shot-10862-norun-investigation

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Corroborator for an empty `?head_sha=` listing: `commits/{sha}/check-runs` + `actions/runs/{id}` (commit-keyed, non-search) over the `?event=push&branch=main&created=…` listing (same search-index class) | technical | Ruled by CTO agent (sequential-fallback — no subagent spawn in this harness), 2026-11-08: use check-runs - the failure being guarded against IS the search index; a second search listing can share the outage. check-runs is commit-keyed and was already the receipt's named non-search option. |
| Window for the evidence re-run: fresh last-300 of origin/main over re-collecting the October window | technical | Ruled by CTO agent (sequential-fallback), 2026-11-08: fresh window - runbook §3 entry condition says "re-run on a fresh window" and criterion-a must measure the current selector; the October SHAs' run-existence was already re-proven 2026-11-07 (0 empty of 300). |
| Empty-after-retry listing resolves the unit through the corroborated run rather than marking it `runs-read:` not-evaluable | technical | Ruled by CTO agent (sequential-fallback), 2026-11-08: resolve through the true run - the plan's decision rule (H3/H4 arm) says "re-read through the true run", and a resolved unit is evidence while a not-evaluable one only feeds the worst-case numerator. |
| Full go/no-go re-ruling (criteria b/c/d measurement, flip) | operator (authorization) | Held: the go-ahead covers the criterion-a evidence re-run only; the re-ruling and activation stay with the budget owner per the plan's "Later" section. |
| `ejections` uses the same search-index listing class; a dropped merge_group run is invisible to its `total_count` guard | technical | Deferred follow-up, not this PR: issue's deliverable is collect's `no-run`; recorded as a known residual in `receipts/cause.md` (a tracking issue will be filed if none exists). |
