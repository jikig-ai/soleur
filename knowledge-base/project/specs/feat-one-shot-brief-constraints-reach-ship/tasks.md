# Tasks: propagate a brief's stated constraints from one-shot to ship

Plan: `knowledge-base/project/plans/2026-11-06-feat-propagate-brief-constraints-to-ship-plan.md`
Branch: `feat-one-shot-brief-constraints-reach-ship` | Draft PR: #12246 | Deferral: #12247

## Phase 1: RED (tests first)

- 1.1 Add rows T18a-T18p to `plugins/soleur/test/ship-battery-owed.test.sh` (fixtures: committed vs untracked token, behind main, ruleset unreadable, infra paths committed/untracked/staged, unresolved diff, wrong section/branch, empty/two-space/control-only words, `- constraint:` line, two sections, sanitize + 200-byte cut, reference-derived parity).
  - 1.1.1 Each of T18a-c isolates one condition (4, 2, 1); T18d is all of them at once.
  - 1.1.2 Reject rows assert the fall-through reason and the absence of `operator ci-is-the-gate`.
- 1.2 Add the `mut18` helper and mutants T18q-s (arm disabled, arm's `INFRA_RE` grep removed, condition-2 `-z` guard removed).
- 1.3 Run only `bash plugins/soleur/test/ship-battery-owed.test.sh`; confirm the new rows are RED for the right reason.

## Phase 2: GREEN

- 2.1 `plugins/soleur/skills/ship/scripts/battery-owed.sh`: token read (sanitize before the emptiness test), `-z` stand-down guards on conditions 1 and 2, the arm after `INFRA_RE=` (committed diff + working tree, grep rc handled), three `undecidable` prefixes, header contract and trust statement.
- 2.2 Create `plugins/soleur/skills/one-shot/references/operator-constraints.md` (what/where/append-after-arm, `- constraint:` prefix, replace-not-append, token + phrase list, Recover and lifetime note, fenced example).
- 2.3 `plugins/soleur/skills/ship/SKILL.md`: hunks S1-S4 only. `plugins/soleur/skills/one-shot/SKILL.md`: hunks O1-O2 only. Re-measure with `wc -c` and `python3 scripts/lint-skill-body-budget.py --base origin/main`; do not touch `skill-body-budget.json`.
- 2.4 Re-run the single suite until green; set `print_results` to the exact green count; run Guard 1 mutation rows 4-11 once by hand on a copy.
- 2.5 `scripts/lib/test-affected-paths.sh`: one declared edge for `operator-constraints.md` in the `SHIP_BATTERY_OWED_TEST_SH` array.

## Phase 3: Document

- 3.1 ADR-242 amendment (`## Amendment — 2026-11-06 (#12246)`, em dash) via `soleur:architecture`, plus the ADR-183 pointer amendment.
- 3.2 `bash plugins/soleur/test/c4-count-parity.test.sh` (no C4 change).

## Phase 4: Targeted checks (single suites only)

- 4.1 `scripts/lint-skill-body-budget.py`, `scripts/lint-orphan-test-suites.sh`, `plugins/soleur/test/fixture-relative-assert.test.sh`.
- 4.2 `bun test` of `components.test.ts`, `plan-skeleton-checkpoint.test.ts`, `fullsuite-merge-gate.test.ts`.
- 4.3 The four sibling ship suites named in the plan.
- 4.4 Smoke test: hand-written token in this branch's `session-state.md`, run `battery-owed.sh`, keep the verdict line for the Test plan.

## Phase 5: Ship under the same constraint

- 5.1 Skip ship Phase 4's local battery by hand and record it in the PR Test plan (brief's words verbatim, smoke-test verdict line, targeted suites, diff touches no infra path).
- 5.2 PR body references the learning file; `Ref #12246` / `Ref #12247` only, never `Closes`.
- 5.3 Rely on CI's required checks (`gh pr checks 12246 --required` exits 0); read `infra-validation` and `sandbox-canary-capture-gate` rows by hand.
- 5.4 Push rules: cd into the worktree, `git add` and `git commit` in separate calls, check the push's real exit code, never push to a PR in the merge queue, never `--admin` merge, never touch the ruleset, do not touch `apps/web-platform/test/claude-pin-lockstep.test.ts` or the stale-accept row for `real-sdk-ask-probe-workflow.test.sh`.
