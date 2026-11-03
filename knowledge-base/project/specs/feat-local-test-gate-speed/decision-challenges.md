# Decision Challenges — feat-local-test-gate-speed

`/ship` renders these into the PR body. Each keeps the operator's stated direction as the default
unless it says otherwise.

## Decision Classes

| # | Class | Decision | Default taken | Evidence |
|---|---|---|---|---|
| UC-1 | User-Challenge (partial scope drop) | The plan asked for measured weight rows for `image-cve-verdict` and `destroy-ask-mutation` (Phase 3.1). Not done in this PR. | Moved to follow-up #12025 with the evidence below. | `scripts/image-cve-verdict` is an ALWAYS-ON suite carried at the 1223 ms unmeasured-floor weight (`scripts/suite-durations.tsv`), but runs about 57 s locally (`time bash scripts/image-cve-verdict.test.sh`, 2026-11-03). An honest weight breaks the fast tier's committed-weight cap for always-on suites (PR #9804, #11662), so pricing it means demoting it to edge selection — the #11779 shape (arrays, two floor pins, justification rows, baselines), which is the deferred re-pricing work. `apps/web-platform/test/destroy-ask-mutation` is registered in the webplat shard, which has no duration table (out of scope in `test-all-corpus-weight-budget.test.sh`), so there is no row to add. A hand-edited weight would also contradict the generated table (`regenerate-shard-manifest.py`, `growth-acked` digest). |

To override: tell the agent to land the demotion of `image-cve-verdict` in this PR instead; it is one suite and the work is mechanical but touches the affected index, two pins and the baselines.
