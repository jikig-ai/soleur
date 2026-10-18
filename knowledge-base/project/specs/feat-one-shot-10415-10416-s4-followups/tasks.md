# Tasks: feat-one-shot-10415-10416-s4-followups

Plan: `knowledge-base/project/plans/2026-10-18-fix-ci-mode-aware-doc-only-classifiers-plan.md`
Scope: build #10416; #10415 is deferred by CTO ruling R1 (no code). Reference #9729 with "Ref" only.

## Phase 1: Setup and RED tests

- 1.1 Confirm worktree/branch (`feat-one-shot-10415-10416-s4-followups`), base `origin/main` 840dc667fc, configured git identity (never `s@example.invalid`).
- 1.2 In `plugins/soleur/test/ci-e2e-skip-anchors.test.sh` and `plugins/soleur/test/ci-shard-totality-skip.test.sh`: add a raw-row builder (`raw_row <status> <old> <new> <path>`, tab separator, 7-hex shas) with `mrow`/`arow` shorthands; rewrite every existing name-status fixture through it.
  - 1.2.1 Add the mode matrix: A with 120000, 160000, 100755; M with 100644 to 100755 and 100755 to 100644; A with non-000000 old mode; T, R100, C, D, U; legacy name-status row; bare path; uppercase-hex row; missing-tab row; extra-field row; 40-hex row; path with spaces; C-quoted path; empty input; compliant-first then symlink-second and the reverse.
  - 1.2.2 Add the grammar-derived cross-product census (8 statuses x 5 old x 5 new = 200 tuples, exactly two `false`; print `tuples=200`).
  - 1.2.3 Add the sed-mutation battery on a mktemp copy: named mutant array with pinned length; assert each mutant differs (`cmp`) and passes `bash -n`; control row on the unmutated copy.
  - 1.2.4 Change the pinned diff anchor to the `--raw` spelling; raise the assertion floors (51, 52).
- 1.3 In `plugins/soleur/test/ci-classify-step-exec.test.sh`: add executed modes `symlink`, `execbit`, `modeflip` for both jobs (expect `true`), keep `md` (expect `false`); raise floor 16 to the new exact count.
- 1.4 In `plugins/soleur/test/ci-shard-totality-skip.test.sh`: add the marker-bounded parity assertion across both classifiers (exactly one marker pair each, non-empty, byte-identical) and its own mutants.
- 1.5 Run the three suites against the UNCHANGED classifiers/workflow and record that the new mode and grammar cases fail (RED).

## Phase 2: Core implementation

- 2.1 `scripts/ci-e2e-classify.sh`: add the `mode-aware-row-parse` block (GUARD-tagged lines), keep the three-arm path case byte-for-byte, rewrite the header (stdin contract, strict-vs-driver divergence).
- 2.2 `scripts/ci-shard-totality-classify.sh`: same block, byte-identical; remove the stale "accepted here" paragraph; rewrite the header.
- 2.3 `.github/workflows/ci.yml`: in `Classify shard-totality applicability` and `Classify e2e applicability` only, replace `--name-status` with `--raw --no-color --no-ext-diff` and add one comment sentence; touch no job-level `if:`/`needs:`.
- 2.4 `scripts/lib/test-affected-paths.sh`: add `scripts/ci-e2e-classify.sh` to the `ci-shard-totality-skip` edge array (one path only).

## Phase 3: Verification

- 3.1 Run the three edited suites, `scripts/ci-pr-selection.test.sh`, `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`, `scripts/guard-vacuity-floor.test.sh`, and the repo-global ratchets; all green.
- 3.2 `git diff origin/main --stat` shows no change to `scripts/required-checks.txt`, `scripts/ci-pr-selection.sh`, the preactivation/replay scripts and suites, any ADR; `CI_PR_AFFECTED` count unchanged.
- 3.3 AC9 replay over the 30 most recent markdown-only first-parent commits; table into the PR body.
- 3.4 Rollback simulation in a scratch detached worktree (AC14).
- 3.5 `python3 scripts/lint-guard-contract.py` on the plan passes.

## Phase 4: Records and handoff

- 4.1 Post the #10415 disposition comment (text in the plan, Deferrals) with `gh issue comment 10415`; issue stays OPEN.
- 4.2 PR body (authored by `soleur:ship`): `Closes #10416`, `Ref #10415`, `Ref #9729`, `## Changelog`, the transition note (own run is full by design), the replay table.
