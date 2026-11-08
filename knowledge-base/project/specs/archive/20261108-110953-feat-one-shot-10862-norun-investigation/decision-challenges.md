# Decision Challenges — feat-one-shot-10862-norun-investigation

Sequential-fallback: no Task/subagent spawn exists in this harness, so the
`soleur:engineering:cto` ruling was made inline by the pipeline runner applying
the cto agent definition's lens (evidence over convenience, fail-closed reads);
`Reviewed-Coverage: sequential-fallback` is disclosed in the PR body and
session-state.md.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Corroborator for an empty `?head_sha=` listing: `commits/{sha}/check-runs` + `actions/runs/{id}` (commit-keyed, non-search) over the `?event=push&branch=main&created=…` listing (same search-index class) | technical | Ruled by CTO agent, 2026-11-08: use check-runs - the failure being guarded against IS the search index, so a second search-parameter listing can share the outage; check-runs is commit-keyed and is the receipt's named non-search option. |
| Window for the evidence re-run: fresh last-300 of origin/main over re-collecting the October window | technical | Ruled by CTO agent, 2026-11-08: fresh window - runbook §3 entry condition requires a fresh window and criterion-a must measure the current selector; the October SHAs' run-existence was already re-proven 2026-11-07 (0 empty of 300). |
| Empty-after-retry listing resolves the unit through the corroborated run rather than marking it `runs-read:` not-evaluable | technical | Ruled by CTO agent, 2026-11-08: resolve through the true run - the plan's decision rule (H3/H4 arm) says "re-read through the true run", and a resolved unit is evidence while a not-evaluable one only feeds the worst-case numerator. |
| Scope of the fix: `ejections` also reads a search-index listing (`?event=merge_group&created=…`) and a dropped run is invisible to its `total_count` guard | technical | Ruled by CTO agent, 2026-11-08: record as residual in the cause receipt, not built here - the issue's deliverable is collect's `no-run` and corroborating a window listing has no per-sha non-search read to pin against. |
| Full go/no-go re-ruling (criteria b/c/d measurement, lever flip) | operator (production-mutating) | Held: the 2026-11-07 go-ahead covers the criterion-a evidence re-run only; the re-ruling and activation stay with the budget owner per the plan's "Later" section. |
