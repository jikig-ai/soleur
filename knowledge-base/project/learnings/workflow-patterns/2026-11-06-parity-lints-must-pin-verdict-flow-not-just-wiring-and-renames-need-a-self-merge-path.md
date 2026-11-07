---
category: workflow-patterns
issue: 12089
date: 2026-11-06
---

# A parity lint that pins wiring but not verdict-flow certifies silence — and a required-context rename PR cannot merge through its own ruleset

Two findings from PR #12250 (16 required check contexts → 3 umbrella jobs), one from the test-design fix-round seat, one from the architecture seat — both are general shapes for any CI-topology change.

## Finding 1 — the sentinel pinned the map, not the edge the map feeds

`scripts/lint-umbrella-aggregate.sh` v1 asserted step-id ↔ `member()` call parity — every member step named in an aggregate call. The test-design seat's mutation battery proved it green on the two defects that matter: deleting the `[ "$failed" -ne 0 ] → exit 1` tail (verdicts computed, never consumed — a red member cannot redden the umbrella) and editing `skipped) ;;` to `skipped) any_run=1 ;;` (all-skipped members flip to PASS — the #8450 fabricated-green class inside a required context). **Rule: when a sentinel pins a fan-in structure (members → aggregate), it must pin BOTH directions — the wiring AND the verdict-consumption edge. Assert the discriminating tokens (`failed=0`, `|| failed=1` per call, `exit 1`, `skipped) ;;`, `return 1`) or the lint certifies silence.** Same seat's corollary: a hand-maintained census of linted objects fails open the day a new one is added — discover the set from the artifact itself (`- id: aggregate` scan) and assert discovery == census.

## Finding 2 — a rename PR can never satisfy the live ruleset it is renaming

The PR that renames a required context reports the NEW names on its head while the live ruleset still requires the OLD names — the old rows stay Expected-forever, `gh pr merge --auto` arms an entry whose merge_group candidate produces only new names, and it ejects at the 120-min timeout having never been mergeable. The only landing path is `gh pr merge --admin` after manually verifying the new-set greens — and the sanctioned gate (`admin-merge-ready.sh`) refuses the same ABSENT old names, so it runs as a raw operator command outside the skill gate. None of this is derivable from the transition-hazard recipe for *queued* entries — it must be written into the ADR amendment + PR body or an operator reads 16 pending rows as a broken run. **Rule: any change that renames a required check context must document the self-merge path (admin-merge + which contexts to verify) alongside the post-merge transition recipe — the PR's own landing is the first instance of the hazard class it introduces.**
