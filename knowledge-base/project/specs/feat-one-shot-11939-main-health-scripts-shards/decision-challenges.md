# Decision Challenges — feat-one-shot-11939-main-health-scripts-shards

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Fix locus: runner-side `export -n TEST_GROUP` (B) vs monitor-side positional channel (A) vs per-suite `env -u TEST_GROUP` (C) vs A+B (D) | technical | Ruled by CTO agent, 2026-11-03: B only - one edit at the point of coupling (beside `unset SCRIPTS_SHARD`) makes the runner independent of caller channel; do not edit `main-health-monitor.yml` or its S2b pin because `scripts/followthroughs/jobs1-stopgap-7432.sh:140` reads the `TEST_GROUP: infra` step-env echo. (First ruling was D; revised to B-only after the consumer was shown.) |
| Is `export -n TEST_GROUP` safe given ~60 shell reads and sandbox-splice builders | technical | Ruled by CTO agent, 2026-11-03: safe - it removes only the export attribute; keep it after group resolution, the `affected->all` alias and the `--print-selection`/`--affected` parse; the affected-walk child already receives the group positionally. |
| PR keyword `Closes` vs `Ref` for #11939 | technical | Ruled by CTO agent, 2026-11-03: `Closes #11939` only if a branch dry-run dispatch of the monitor is fully green; otherwise `Ref #11939`. Dry run proves legs, not the alert path. |
| Add regression rows to `scripts/test-all-group-affected.test.sh` rather than a new suite | technical | Ruled by planner, 2026-11-03 (low-stakes, no new registration/manifest/affected-class churn): extend the suite that already owns runner TEST_GROUP behaviour. |
| Change what the main-health report's push red-rate counts (0/50 blind to elided legs) | operator (priority/schedule) | Deferred, tracked as #11953; alert predicates are out of scope by operator instruction. |
