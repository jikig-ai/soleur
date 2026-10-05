# Tasks: pipefail early-exit grep sweep, PR-1

Plan: `knowledge-base/project/plans/2026-10-05-fix-pipefail-early-exit-grep-q-sweep-plan.md`

## Phase 0: re-measure and reconcile (read-only)

- [ ] 0.1 Re-run the repo-wide `git grep` count and the production and test split; record the commands and counts.
- [ ] 0.2 Assert the pathspec-derived non-deferred set equals the classifier set file by file; list production-looking files inside deferred globs.
- [ ] 0.3 Assert V2 total equals V1 plus the wrapper site `scripts/lint-migrated-rule-ids.sh:200`.
- [ ] 0.4 Count non-code hits (comments, quoted strings, prompt literals, heredoc payload) in PR-1's set and decide reword, mark, or a second exclusion list.
- [ ] 0.5 Count non-bash scripts (expect 0 `.sh`); read the two constraint-scaffold templates, the generated `apps/web-platform/.github/workflows/constraint-gates.yml` and the `.workflow.js`.
- [ ] 0.6 Record the armed-battery set (including the `.github/workflows` and `apps/web-platform/` directory entries) and the `--affected` selected-suite count with a CI wall-clock estimate.

## Phase 1: guard first, red

- [ ] 1.1 Add `scan_sweep <root>` (`git -C <root> grep --no-index`) by giving `scan_pipes` a pattern and optional root.
- [ ] 1.2 Add the deferral table (`path | ceiling | tracker`) with stale, ceiling and tracker checks and the `DEFERRED:` lines.
- [ ] 1.3 Add `PATTERN_V2` (named passes keep V1) and put it in the compile pre-check loop.
- [ ] 1.4 Add probe fixtures and the Guard 1 and Guard 2 mutation rows; each mutation reports NOT LANDED if its anchor is absent.
- [ ] 1.5 Confirm the derived pass is RED on the unconverted tree; commit.

## Phase 2: convert, one commit per root

- [ ] 2.1 `scripts/` (mechanical class by scratch transformer, then hand queue); `bash -n`, per-suite before/after counts.
- [ ] 2.2 `plugins/soleur/` including the two templates and `.workflow.js` DATA lines.
- [ ] 2.3 `apps/web-platform/` (scripts and the nested workflow together with its template).
- [ ] 2.4 `apps/cla-evidence/`; convert the one continued pipe by hand.
- [ ] 2.5 Convert the four `-m1` output-consuming sites with `grep -m1 P <<<"$v"`; send every bare pipeline under `set -e` to the capture form.
- [ ] 2.6 Contention run (four isolated copies, collected by pid) for the hand-converted and verdict-bearing suites.

## Phase 3: item 5 documentation

- [ ] 3.1 Rewrite the header's "Not matched" paragraph into the closed/residual table with measured counts.
- [ ] 3.2 Add the three-row conversion table, the marker syntax and the `| head` danger sentence; make the FAIL message print the remediation.

## Phase 4: producer-side hand-off

- [ ] 4.1 Post the measured producer-side population on #9217 (join and stub fixes are wave B).

## Phase 5: evidence, learning, ratchets, one push

- [ ] 5.1 Append one corrected SIGPIPE-disposition row to the audit; write one learning linking to it.
- [ ] 5.2 Post the evidence comment on #9217, cross-links on #7005, #6601, #7376, and a note on draft PR #9552.
- [ ] 5.3 Run every file from `grep -lis ratchet scripts/*.test.sh scripts/lib/*.test.sh .claude/hooks/*.test.sh`, `scripts/pre-push-ratchet-lane.sh`, the guard directly, the orphan lint and `scripts/test-affected-kb-consumers.test.sh`.
- [ ] 5.4 Verify the diff touches no machinery file (`git diff --name-only origin/main...HEAD`), re-compare the armed-battery set, then push once.
