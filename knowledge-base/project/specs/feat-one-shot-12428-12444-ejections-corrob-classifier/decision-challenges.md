# Decision Challenges — feat-one-shot-12428-12444-ejections-corrob-classifier

Sequential-fallback: no Task/subagent spawn exists in this harness, so
plan-review seats and the CTO-adjacent dispositions below were applied inline by
the pipeline runner using the cited agent definitions' lenses; the two
deliverables' own rulings are CTO rulings already on record (2026-11-08,
#12428 comment and #10448/#12444) and are BINDING, not re-ruled here.
`Reviewed-Coverage: sequential-fallback` is disclosed in the PR body and
session-state.md.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Both ruled deliverables build in ONE PR (#12428 + #12444) | technical | Held: binding per dispatch brief and the issues; the deliverables share the unit pipeline, window manifest and suite. |
| Landed-sha corroboration shape: bounded check-suites→check-runs join vs verbatim `corroborating_runs` reuse | technical | Bounded join — verbatim reuse measures ~300 commits × ~40 run reads ≈ 12k calls/window (live-measured 2026-11-08: 28–65 distinct run ids/commit), unreachable against the ruling's own "bounded run reads" sizing; the join keeps the same non-search commit-keyed family and the ruling's `details_url`/truncation/fan-out trust rules. |
| Oracle expected-side: `added_to_merge_queue` events vs `removed_…` events vs run ids | technical | expected = in-window `added` count; observed = DISTINCT `pr-N-*` head_branch names (one branch ≈ one queue entry; re-runs share it — verified `pr-12390`: 4 adds vs 7 runs). `removed` counts are recorded in the window json for the receipt; over-count from adds removed pre-processing counts into worst_case — the conservative direction per the ruling. |
| Failed corroboration/oracle read disposition | technical | One synthetic `not-evaluable` unit per failed read (`corroboration-read:`/`queue-oracle-read:`), never a silent skip and never a whole-run abort — consistent with "a failed read is never nothing found" and keeps one bad PR/commit from voiding a completed window. |
| `ejections-window.json` schema: new `expected_units` key vs redefining `refused` | technical | New key — `refused` keeps its run-level meaning; `check_complete` reads `expected_units` with `refused` fallback so old manifests and suite `mkmeta` fixtures stay valid. |
| `failure`-concluded job + runner-shutdown signature + no `[FAIL]` line → failed or unsettled? | technical | Unsettled (`mid-termination`) — no suite verdict exists; GitHub's `failure` rollup records the cancel. Verified against live logs (jobs 124613574229, 126016312817). Routing it through the new unsettled-clearing arm is the principled disposition. |
| Log-404 job → not-evaluable forever, or annotation probe? | technical | Probe `check-runs/{id}/annotations` once per log-read failure for the hosted-runner-comms-loss string (verified live on jobs 125980654539, 127743275859); hit → unsettled (`runner-comms-loss`), miss/failed probe → `log-read` not-evaluable. A wording change upstream degrades to today's verdict — fail-safe. |
| `FAIL_LINE` label charset for `apps/web-platform [repo-wide+component]` | technical | `([ -~]+?)` lazy printable-ASCII — captures space/bracket labels; control bytes stay outside the class so the pinned control-byte rejection row stays green. |
| Unsettled-leg witness set: which proofs count as "identical tree went green" | technical | Per-leg union: (ejections) existing `cleared()` later same-PR identical-content success; (both) earlier attempt of the same run with the leg `success`; (commits) sibling FULL_EVENTS run on the same sha with the leg `success`. Unit clears iff EVERY unsettled leg is witnessed; an unreadable witness read is not evidence. |
| Commit-side `same_tree_green`: keep `lambda: False` or build the sibling/attempt witness | technical | Build it — the measured window had 1 commit-side unsettled unit and a churn-heavy window can produce more; `cmd_collect` already holds the sha's `runs`, so the closure costs a bounded jobs read per sibling/attempt and only inside the unsettled arm. |
| Full §4 evidence re-run + go/no-go re-ruling in this PR? | operator (priority/schedule) | Held: sequenced post-merge per runbook §3 entry conditions; the re-run and activation authorization stays with the budget owner (identical reservation to row 5 of `specs/archive/20261108-110953-feat-one-shot-10862-norun-investigation/decision-challenges.md`). This PR ships a bounded live smoke as its evidence. |
| New ADR / C4 update for the corroboration + clearing rules | technical | None required — extends the established non-search corroboration pattern (ADR-276 amendment chain); C4 enumeration (all three .c4 files read 2026-11-08) found no new actor, external system, container, or access relationship. |
| Domain fan-out, Product/UX tier, GDPR, IaC, encryption posture | technical | All NONE — measurement-tool change inside `scripts/` + one suite + runbook bullet; no UI-surface file, no regulated-data surface, no infra, no store/connection. |
