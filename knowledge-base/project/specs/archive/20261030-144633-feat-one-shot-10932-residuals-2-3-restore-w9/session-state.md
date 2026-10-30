# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-30-chore-registry-restore-w9-residuals-2-3-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=3+ (plan, plan-review, deepen; all rulings recorded in decision-challenges.md)

### Errors
None blocking. One Bash hook block on draft wording during planning, reworded.

### Decisions
- All four items (residual 2, 3a, 3b, 3c) are real on current origin/main; none dropped.
- Test-side only: the PR edits one file (tests/scripts/test-registry-d10-workflow-wiring.sh). Workflow, engine, lib and pull-path-health suite are untouched, so no production apply and no mutation battery.
- 3b is latent (the engine has no computed die site today); closed with a census tripwire in the wiring suite.
- Merging does not clear #10932: two items stay outside the brief (the grep -vx 1 ignore follow-up and engine-owned wording). Ask before closing.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto, dhh/kieran/code-simplicity/test-design reviewers, sandbox prototype seat

## Work phase (2026-10-30)

- Suite: 63 passed / 0 failed (EXPECTED_ASSERTIONS=63, from the green run). pull-path-health 63/0, restore-from-ghcr 98/0, workflow-file-size 9 pass. Workflow 489,131 bytes, unchanged; engine, lib and workflow untouched.
- Timing, back to back on one machine state: origin/main suite 64 s, new suite 87 s (+23 s).
- RED first: 13 new controls failed (49 passed) before the implementation.
- Mutation battery (sandbox copy, separate mutant files, pristine copy compared at the end): 16 full-suite mutants, control green, 14 of 15 killed. Survivor M13 (loop verdict hardcoded at the call site) is the accepted residue. Defect found by the battery and fixed in bec56b1400: the meta-control reported through w9_verdict, so an always-ok w9_verdict survived 63/0; it now reports inline and is killed (M01), as is the inverted verdict (M02, two FAIL lines).
- Function-level rows: census 16 rows (all red except the baseline and the by-design whole-line comment), summary check 10 rows (all red except the baseline). G2-15 red via the `939:die(` offender.
- Lints green: lint-infra-no-human-steps --changed, lint-guard-contract, lint-shell-capture-exit (baseline), lint-shell-trace-credential-refusal --changed, ci-pr-affected-replay ratchet (live=1513 baseline=1513).
- Next: review, qa, compound, ship. PR body must carry the timing pair, the battery outcome and the accepted residues.
