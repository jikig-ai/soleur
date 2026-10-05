# Tasks: model ship's in-ship review call as a declared sub-step (ADR-229)

Plan: `knowledge-base/project/plans/2026-09-23-feat-model-in-ship-review-sub-step-plan.md`.
The PR body says `Ref #8470`, never a closing keyword.

## Phase 1: Setup

- [ ] 1.1 `export TMPDIR=/var/tmp`, then run `npm ci --ignore-scripts` at the worktree root and in
      `apps/web-platform`.
- [ ] 1.2 Baseline green: run `bun test plugins/soleur/test/workflow-fidelity.test.ts`, then
      `bash scripts/classify-workflow-transitions.test.sh`. The suite should report
      `39 passed, 0 failed`.

## Phase 2: Core Implementation

- [ ] 2.1 RED in `plugins/soleur/test/workflow-fidelity.test.ts`:
  - [ ] 2.1.1 Exact-set pin: `ship: ["compound", "review"]`.
  - [ ] 2.1.2 Replace the `SECTION` map with the per-entry `ANCHORS` heading lists.
        - Assert the pair-set equality BEFORE the loop.
        - Loop over `DECLARED_SUB_STEPS`, looking up `ANCHORS[node]?.[sub] ?? []`.
        - Assert each list is non-empty, with a named message.
        - Assert `checks >= Object.values(DECLARED_SUB_STEPS).flat().length`.
        - Add no literal count.
  - [ ] 2.1.3 Extend the LIMITS comment to cover the Phase 1.5 two-site limit and the Phase 5.5
        scope width.
- [ ] 2.2 RED in `scripts/classify-workflow-transitions.test.sh`:
  - [ ] 2.2.1 Case 39: `ship review compound postmerge` gives `undeclared=0 pairs=1 substep=2`
        and no row.
  - [ ] 2.2.2 Case 40, the control: `work review ship` gives `undeclared=1 pairs=2 substep=0`.
        The row output must EQUAL `$'  s40\treview -> ship'`; a substring match is not enough.
  - [ ] 2.2.3 Case 41: `ship review work` gives `undeclared=0 pairs=1 substep=1` and no row.
        Its pass message names it as the accepted false-negative.
  - [ ] 2.2.4 Set `MIN_CASES=42` directly above its `if`, and change the floor comment to
        "cases 1-41 yield 42".
- [ ] 2.3 Run both suites and confirm the expected RED: the exact-set pin, the anchor set
      equality, and cases 39 and 41. Case 40 stays green.
- [ ] 2.4 GREEN, TS first. In `plugins/soleur/lib/workflow-fidelity.ts`, set
      `ship: ["compound", "review"]`, then update the docblock: the ship bullet, the legality
      sentence, the "To add an entry" list, and the ADR citation.
- [ ] 2.5 GREEN, the mirror. In `.claude/workflow-transitions.json`, set `sub_steps.ship` and add
      the `_comment` amendment entry `2026-09-23, #8627`.
- [ ] 2.6 Amend ADR-229:
  - [ ] 2.6.1 Status line, citing "(PR #8627)".
  - [ ] 2.6.2 The Decision 1 #8627 bracket.
  - [ ] 2.6.3 Add one re-baseline bullet after the 2026-09-21 bullet. It holds:
        - the deltas from a work-time frozen-copy run;
        - the cost stated once, with the `ship → ship` causes split by reading the exposed
          sessions (review's own exit gate vs a direct review → ship);
        - the two #8470 sentences, including the classifier's `review → ship` delta.
  - [ ] 2.6.3b Add supersede brackets on the 2026-09-21 sentences "`review → ship` stays at 51"
        and "No collapse can launder a review skip". Add an Alternatives row for the
        `ship → review` edge.
  - [ ] 2.6.4 Add the Modelled bracket beside the unmodelled sentence. Do not edit the
        2026-09-22 bracket.
  - [ ] 2.6.5 Verification: rewrite the anchor clause and the floor number, and add the
        "Since #8627: …" classifier clause.

## Phase 3: Testing

- [ ] 3.1 Run both suites green. `REAL_PASSES` must equal `MIN_CASES` (42).
- [ ] 3.2 Mutation spot-checks, each on a scratch copy and each expected RED:
  - [ ] 3.2.1 Delete the Phase 5.5 review call only. Anchor the edit on "No code review was run
        before ship" and confirm the call count fell by exactly 1.
  - [ ] 3.2.2 Delete both Phase 1.5 calls.
  - [ ] 3.2.3 C1: make the classifier drop any `sub_steps` value regardless of the previous
        node. Case 40 must go RED.
  - [ ] 3.2.4 Restore after each, and record the results in the PR body.
- [ ] 3.3 Run `bash scripts/guard-vacuity-floor.test.sh`,
      `bash plugins/soleur/test/c4-count-parity.test.sh` and `bash scripts/check-adr-ordinals.sh`.
- [ ] 3.4 Run the full gate with `bash scripts/test-all.sh`. If it is REFUSED, run
      `TEST_GROUP=affected` plus every path-less ratchet UNFILTERED, then the
      vocabulary-consumer suites.
- [ ] 3.5 Run the joined-text ADR check. It must print `1`.
- [ ] 3.6 Run the diff-scope check. `ship/SKILL.md`, the classifier script and
      `rule-metrics.json` must be untouched, and `knowledge-base/INDEX.md` must not be staged.
