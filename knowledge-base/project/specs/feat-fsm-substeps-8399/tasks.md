# Tasks: feat-fsm-substeps-8399 (#8399)

Plan: `knowledge-base/project/plans/2026-09-21-feat-fsm-substeps-compound-skip-triage-plan.md`

## Phase 0: Setup and tracking

- [ ] 0.1 File the D.2 tracking issue: ship Phase 2's learning probe is repo-wide and never empty, so it skips the feature-scoped archive check.
  - The body carries the 12/12-weeks measurement, the C triage table and the uncommitted-learning caveat.
  - The body names the fix path: extract Phase 2 to `ship/references/`, add a branch-scoped probe, fixture-test it.
  - The body names the D re-open trigger the issue owns.
  - The body carries the Appendix triage procedure verbatim. The ADR cites this issue, not the plan.
  - Labels: `domain/engineering`, `type/bug`, `priority/p2-medium`.
- [ ] 0.2 Snapshot the base measurement on a frozen copy of the log, before any code change.
  - Make the copy in the session scratchpad with `umask 077`. Run the base and new views on that same file via `CLASSIFY_REPO_ROOT`.
  - Delete the snapshot after Phase 3.

## Phase 1: RED — tests first

- [ ] 1.1 `plugins/soleur/test/workflow-fidelity.test.ts`
  - [ ] 1.1.1 Exact-set pin becomes `{ brainstorm, plan, postmerge, ship: ["compound"] }`.
  - [ ] 1.1.2 Parity block: a test naming the view's `sub_steps` and `transitions` key sets.
  - [ ] 1.1.3 SKILL.md anchor test.
    - Match `/skill: soleur:<V>(?![\w-])/` within the owning section: plan `## Exit Gate`; postmerge `## Phase 6: Update Issue and Compound`; ship `## Phase 2: Capture Learnings`; brainstorm the whole file.
    - Checks performed must equal `Object.values(DECLARED_SUB_STEPS).flat().length`, and must be > 0.
    - A key missing from the section map fails the test.
- [ ] 1.2 `scripts/classify-workflow-transitions.test.sh`
  - [ ] 1.2.1 Case 14: keep the input and flip the assertion.
    - `--summary` has `pairs=0 ` and `substep=1 `.
    - No rows with `2>/dev/null`.
    - The `formed ZERO lifecycle pairs` warning is present.
  - [ ] 1.2.2 Case 20: fix the comment ("keyed on the declared keys, never on `review`").
  - [ ] 1.2.3 Cases 33–35 as one loop over `plan:work postmerge:work ship:postmerge`. Each gives `undeclared=0 pairs=1 substep=1` and no row.
    - One pass per key, and a per-iteration `new_root`.
    - Keep the trailing space in each assertion.
    - The key list must equal the view's `sub_steps` keys minus `brainstorm`.
  - [ ] 1.2.4 Case 36: `plan compound ship` gives the row `plan -> ship` with `substep=1`.
  - [ ] 1.2.5 Case 37: `postmerge compound ship` gives the row `postmerge -> ship` with `substep=1`.
  - [ ] 1.2.6 Case 38: `plan`@:09 filed before `brainstorm`@:01 gives `undeclared=0` (pure ts order). Case 14's failure message prints `pairs` and `substep`.
  - [ ] 1.2.7 `MIN_CASES=38`, keeping `SELFTEST_PASSES=1` contiguous. Add a comment that the loop records one pass per key.
- [ ] 1.3 Run both suites. RED is expected on the pins, case 14, and cases 33–37. Case 38 and the anchor test are green from the start; each one's RED comes from its mutation row.

## Phase 2: GREEN — const, then mirror

- [ ] 2.1 `plugins/soleur/lib/workflow-fidelity.ts`: set `DECLARED_SUB_STEPS` to the four entries.
  - Rewrite the doc comment with each entry's SKILL.md anchor.
  - Name the forbidden `review` entry.
  - Keep "To add an entry" verbatim.
- [ ] 2.2 `.claude/workflow-transitions.json`: mirror `sub_steps`.
- [ ] 2.3 Both suites green.

## Phase 3: ADR-229 amendment

- [ ] 3.1 Decision 1 note: the four `sub_steps` entries (#8399).
- [ ] 3.2 Consequences: resolve the dissent-2 sentence, with A and B evidence and no symmetry argument.
- [ ] 3.3 A new re-baseline bullet with snapshot deltas, the exposure (plan→ship +3, postmerge→ship +3), and updated older wording.
- [ ] 3.4 Replace the deferred-gate bullet with the compact D ruling (about 10 lines).
  - Include the D.2 issue number and the re-open trigger.
  - Add the false-deny reason to the existing gate Alternatives rows.
- [ ] 3.5 Verification: classifier floor 38, the coverage list, the key-set test, the anchor test.
- [ ] 3.5.1 Reword "a future gate (below) have a typed source". Annotate the `plan → ship` (7) adoption sentence with the +3 laundered through `compound → ship`.
- [ ] 3.6 Dissent 1: apply edit (a) or (b) ONLY if the operator has answered. Otherwise no edit.

## Phase 4: Verify and ship-prep

- [ ] 4.1 Run `lint-guard-contract.py`, `lint-skill-body-budget.test.sh` and the c4 count parity check.
- [ ] 4.2 Full `bash scripts/test-all.sh` before the first push.
- [ ] 4.3 Confirm no `plugins/soleur/skills/*/SKILL.md` is touched beyond `b1a41c34f`.
- [ ] 4.4 Batch all commits and push once. The PR body says `Closes #8399` only if dissent 1 was answered, otherwise `Ref #8399`.
