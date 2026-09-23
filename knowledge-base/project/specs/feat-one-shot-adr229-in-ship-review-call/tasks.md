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
  - [ ] 2.1.2 Replace the `SECTION` map with the per-entry `ANCHORS` heading lists. Coverage is
        one set equality (the `ANCHORS` pairs equal the `DECLARED_SUB_STEPS` pairs). Each heading
        list must be non-empty. `checks` equals the computed heading total, with no literal.
  - [ ] 2.1.3 Extend the LIMITS comment to cover the Phase 1.5 two-site limit and the Phase 5.5
        scope width.
- [ ] 2.2 RED in `scripts/classify-workflow-transitions.test.sh`:
  - [ ] 2.2.1 Case 39: `ship review compound postmerge` gives `undeclared=0 pairs=1 substep=2`
        and no row.
  - [ ] 2.2.2 Case 40, the control: `work review ship` gives the single row `review -> ship`,
        with `undeclared=1 pairs=2 substep=0`.
  - [ ] 2.2.3 Case 41: `ship review work` gives `undeclared=0 pairs=1 substep=1` and no row.
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
  - [ ] 2.6.1 Status line.
  - [ ] 2.6.2 The Decision 1 #8627 bracket.
  - [ ] 2.6.3 One re-baseline bullet after the 2026-09-21 bullet. Take its deltas from a
        work-time frozen-copy run, state the cost once, and add the #8470 instrument sentence.
  - [ ] 2.6.4 Add the Modelled bracket beside the unmodelled sentence. Do not edit the
        2026-09-22 bracket.
  - [ ] 2.6.5 Verification: rewrite the anchor clause and the floor number.

## Phase 3: Testing

- [ ] 3.1 Run both suites green. `REAL_PASSES` must equal `MIN_CASES` (42).
- [ ] 3.2 Mutation spot-checks: delete the Phase 5.5 review call, then delete both Phase 1.5
      review calls. Each must go RED. Restore the file after each and record the results in the
      PR body.
- [ ] 3.3 Run `bash scripts/guard-vacuity-floor.test.sh`,
      `bash plugins/soleur/test/c4-count-parity.test.sh` and `bash scripts/check-adr-ordinals.sh`.
- [ ] 3.4 Run the full gate with `bash scripts/test-all.sh`. If it is REFUSED, run
      `TEST_GROUP=affected` plus every path-less ratchet UNFILTERED, then the
      vocabulary-consumer suites.
- [ ] 3.5 Run the joined-text ADR check. It must print `1`.
- [ ] 3.6 Run the diff-scope check. `ship/SKILL.md`, the classifier script and
      `rule-metrics.json` must be untouched, and `knowledge-base/INDEX.md` must not be staged.
