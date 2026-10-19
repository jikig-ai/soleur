# Tasks: feat-one-shot-10415-10416-s4-followups

Plan: `knowledge-base/project/plans/2026-10-18-fix-ci-mode-aware-doc-only-classifiers-plan.md`
Scope: build #10416; #10415 is deferred by CTO ruling R1 (no code). Reference #9729 with "Ref" only.

## Phase 1: Setup and RED tests

- [x] 1.1 Confirm worktree/branch (`feat-one-shot-10415-10416-s4-followups`), base `origin/main` 840dc667fc, configured git identity (never `s@example.invalid`).
- [x] 1.2 In `plugins/soleur/test/ci-e2e-skip-anchors.test.sh`: add the raw-row builder (`raw_row <status> <old> <new> <path>`, tab separator, 7-hex shas) with `mrow`/`arow` shorthands; rewrite every existing name-status fixture through it; add the mode matrix (A with 120000, 160000, 100755; M 100644 to 100755 and 100755 to 100644; A with non-000000 old mode; T, R100, C, D, U; legacy name-status row; bare path; uppercase-hex row; missing-tab row; extra-field row; 40-hex row; path with spaces; C-quoted path; empty input; compliant-first then symlink-second and the reverse); change the pinned diff anchor to the `--raw` spelling; raise the floor (51) to the exact new total.
- [x] 1.3 In `plugins/soleur/test/ci-shard-totality-skip.test.sh`: same builder, fixture rewrite, mode matrix, anchor, exact floor (52 raised); plus the single-sourced machinery looping over BOTH classifiers:
  - [x] 1.3.1 Grammar-derived census (8 statuses x 5 old x 5 new modes; exactly two `false`; checked count equals the product of the axis lengths; unclassified tuple fails).
  - [x] 1.3.2 Sed-mutation battery on a mktemp copy: named mutant array with pinned length; each mutant differs (`cmp`), passes `bash -n`, fall-through mutants exit 0 on their probe; control row on the unmutated copy; seds anchored `# GUARD:<ID>$`.
  - [x] 1.3.3 Marker-bounded parity assertion (exactly one marker pair each, non-empty, byte-identical) with its own mutants.
- [x] 1.4 In `plugins/soleur/test/ci-classify-step-exec.test.sh`: seed a root `README.md` in the base commit; add executed modes `symlink`, `execbit`, `modeflip` for both jobs (expect `true`), a `transition` case with an embedded frozen pre-change classifier as the base-ref copy (expect `true`), keep `md` (expect `false`); raise floor 16 to the new exact count.
- [x] 1.5 Run the three suites against the UNCHANGED classifiers/workflow and record that the new mode and grammar cases fail (RED).

## Phase 2: Core implementation

- [x] 2.1 `scripts/ci-e2e-classify.sh`: add the `mode-aware-row-parse` block (GUARD-tagged lines), keep the three-arm path case byte-for-byte, rewrite the header (stdin contract, strict-vs-driver divergence).
- [x] 2.2 `scripts/ci-shard-totality-classify.sh`: same block, byte-identical; remove the stale "accepted here" paragraph; rewrite the header.
- [x] 2.3 `.github/workflows/ci.yml`: in `Classify shard-totality applicability` and `Classify e2e applicability` only, replace `--name-status` with `--raw --no-color --no-ext-diff` and add one comment sentence; touch no job-level `if:`/`needs:`.
- [x] 2.4 (not needed: no ratchet demanded the edge; scripts/lib untouched) CONDITIONAL: `scripts/lib/test-affected-paths.sh` - add `scripts/ci-e2e-classify.sh` to the `ci-shard-totality-skip` edge array (one path) only if an affected-index ratchet goes red without it.

## Phase 3: Verification

- [x] 3.1 Run the three edited suites, `scripts/ci-pr-selection.test.sh`, `scripts/ci-push-dedupe.test.sh`, `scripts/ci-draft-light.test.sh`, `plugins/soleur/test/c4-count-parity.test.sh`, `scripts/guard-vacuity-floor.test.sh`, and the repo-global ratchets; all green.
- [x] 3.2 `git diff origin/main --stat` shows no change to `scripts/required-checks.txt`, `scripts/ci-pr-selection.sh`, the preactivation/replay scripts and `plugins/soleur/test/ci-pr-affected-*.test.sh`, any ADR; `CI_PR_AFFECTED` count unchanged.
- [x] 3.3 AC9 replay over the 30 most recent markdown-only first-parent commits; one-sentence result for the PR body.
- [x] 3.4 Rollback simulation in a scratch detached worktree (AC14).
- [x] 3.5 `python3 scripts/lint-guard-contract.py` on the plan passes.
- [x] 3.6 Run the plan's Observability discoverability probe (ordinary-mode raw row into `scripts/ci-e2e-classify.sh pull_request`): prints `false` after the change (AC15).

## Phase 4: Records and handoff

- 4.1 Post the #10415 disposition comment (text in the plan, Deferrals) with `gh issue comment 10415`; issue stays OPEN.
- 4.2 PR body (authored by `soleur:ship`): `Closes #10416`, `Ref #10415`, `Ref #9729`, `## Changelog`, the transition note (own run is full by design), the replay one-liner.
