# Tasks: registration-only runner edits take the bounded selection

Plan: `knowledge-base/project/plans/2026-10-05-fix-registration-only-runner-edit-narrows-affected-gate-plan.md`
Branch: `feat-one-shot-registration-only-runner-edit` | Draft PR: #9552

## Phase 0 - Setup

- 0.1 Re-run the collision check (open issues/PRs for `runner-changed` x registration).
- 0.2 File ONE deferral issue for second-stage narrowing (runner-edge heavy batteries that are not runner-SUT, 13.6 min of 58.6); roadmap milestone; re-evaluation criteria. No issue for the known flakes (tracked on 7376).
- 0.3 Re-run the commit hit-rate measurement (152 of 226 fit the grammar; 139 add a registration) and put the numbers in the PR body.
- 0.4 Remember: this PR is itself a semantic runner edit; verify with targeted suites, not a local full battery.

## Phase 1 - Banner and `--help` (own commit; independent of the classifier)

- 1.1 Rewrite the `runner-changed` banner (cost `N` from `suite-durations*.tsv`, commit window, up to three offenders as `<file>:<line> [rule-code]` with fixed sentences and NEVER source text, preview command, staged-scope line only for could-not-classify/anchor refusals; verbatim em-dash `MODE=full` line) and the bounded-path cost line and add the `--help` `RUNNER EDITS` block plus the index-only caveat on `--affected-scope`.
- 1.2 Banner rows beside row k in `scripts/test-all-affected.test.sh`.

## Phase 2a - Runner-only classifier (RED then GREEN)

- 2a.1 RED: classifier rows in `scripts/test-all-affected.test.sh` after row k (outside pinned spans): function-level rows via awk-range extraction, three end-to-end rows through the trimmed-corpus sandbox with a build-time-injected diff seam; scratch git repos by copy, never links (#8800).
  - 2a.1.1 Guard Contract rows 1-4, 7-13, 15-18 (semantic edits must stay full; vacuity; reorder; label collision against loop/glob labels; parser pitfalls; charset/option-shaped argv; anchor-in-string; banner never prints source text).
  - 2a.1.2 Harness rows H1-H5.
- 2a.2 GREEN: `_aff_classify_runner_diff` (G0, G1, G2 + anchor, G4; any index hunk is semantic) beside `_diff_edge_hit`; class computation after the membership block (never edit the neutered lines); extra elif conjunct; `AFFECTED_RUNNER_IN_SCOPE reason=registration-only` emitted AFTER the uniqueness check (not in the pre-walk else); post-walk label-uniqueness degrade (exact-field count over `_aff_label[]`, note emitted after the check, `enumerate-unavailable` pattern, current-shell variables); `|| undecidable` under `set -e`; hardening: `LC_ALL=C`, exact blank/comment, CR rejected, option-shaped argv refused, git env hygiene, `bash -n` under `env -u BASH_ENV -u ENV --noprofile --norc`.
- 2a.3 Re-read the sc rows asserting `AFFECTED_RUNNER_IN_SCOPE` (about lines 1317/1332/1357) and update them deliberately for `reason=registration-only`. Verify pinned consumers: `fanout-suite-scope` neuter anchor, `test-all-affected` rows k / sc1-sc9 / q4 / w1 / A7, `test-affected-derive` A5.

## Phase 2b - Index declarations (separate commit; droppable; User-Challenge in decision-challenges.md)

- 2b.1 RED then GREEN: G3 (anchored array block, `ALWAYS_ON_SUITES` entry), G5 binding, injectivity rules (i)-(iv) against the enumerate stream; matrix rows 5, 6, 14; H3 index forms.

## Phase 3 - ADR

- 3.1 Short amendment to ADR-242 (decision 20, `amended_by`, option-d pointer) via `soleur:architecture`; update the lib header comment (index file edit; this PR is semantic by design).

## Phase 4 - Learning and verification

- 4.1 ONE learning: `knowledge-base/project/learnings/2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`.
- 4.2 Targeted verification: `test-all-affected`, `fanout-suite-scope`, `test-affected-derive`, `test-all-group-affected`, `lint-orphan-test-suites`, `scripts-shard-totality`, `python3 scripts/lint-guard-contract.py`, `c4-count-parity`; scratch registration edit on a base-derived tree (revert; `git status` clean).
- 4.3 CI's sharded full battery is the merge gate; confirm AC1-AC9 in the plan.
