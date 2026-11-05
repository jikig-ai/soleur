# Tasks: S4 affected-index PR5z — strict zero (Ref #10861)

Plan: `knowledge-base/project/plans/2026-11-05-feat-one-shot-10861-pr5z-strict-zero-plan.md`. Canonical contract: `specs/archive/20261103-165953-feat-one-shot-10861-pr5-strict-zero/tasks.md` §Phase 4 + Verification. Decisions: `decision-challenges.md`. Receipts → `receipts/`. Holds: no `CI_PR_AFFECTED`, no lock removal, no PR D, no PR3b, no evidence re-run. One `s4-drain` PR at a time.

## Phase 0 — claim, stamp, measure, coordinate (before any edit)

- [ ] 0.1 `gh pr list --label s4-drain --state open` empty → `gh pr edit 12127 --add-label s4-drain` + mirror comment on #10448.
- [ ] 0.2 `git fetch origin main`, rebase, `BASE=$(git rev-parse origin/main)` + `date -u` → `receipts/measurement-stamp.txt`.
- [ ] 0.3 Red-gate: `audit --accept --all-refs > receipts/audit-all-refs.txt`; `ratchet --base origin/main > receipts/ratchet-initial.txt`. Expected at plan time: `stale-accept`, `live=3` (main red — #12110). If red → `gh pr view 12128 --json state`: MERGED → rebase+re-measure; OPEN → SEQUENCE after it — no pre-merge absorption (duplicates the claimed repin, collides on accept.tsv); if it stalls/closes-unmerged → absorb residual (delete stale rows + mention-class accepts for the 3 `components.test.ts` drift pairs) recorded in `receipts/drift-disposition.tsv`; never duplicate the repin. (CTO ruling — decision-challenges row 13.)
- [ ] 0.4 `receipts/live-pairs.tsv` + `receipts/pairs-decisions.tsv` for any absorbed residual.

## Phase 1 — the deletion commit (ONE commit)

- [ ] 1.1 Re-assert: `audit --accept` exit 0 `gap_suites=0 unaudited=0 stale=0`; `ratchet --base origin/main` `reason=pass live=0 baseline=0` (task 4.1).
- [ ] 1.2 replay.py: `baseline-reintroduced` arm before the `if new and head_text is None and base_text is not None:` block (:2058); docstring BASELINE STATE + verdict list + "(adoption, deletion)" + `--print-baseline` paragraph updated.
- [ ] 1.3 `git rm scripts/ci-pr-affected-audit.baseline.tsv`; remove `.gitattributes:2`.
- [ ] 1.4 Delete the 42 orphaned accept rows (`$2=="scripts/ci-pr-affected-audit.baseline.tsv"`, 14×3 on `-a`/`-b`/`-c`); C-locale order + 2 header comments kept; `audit` → `stale=0`.
- [ ] 1.5 Test rework: `row_rt_adopt`/`row_rt_adopt_unequal` → reintroduced rows (contentful + `bl-empty` arms, plus `! grep -q '^grown'`); `rt_p_weak` + `row_rt_helper_pr_tree_ignored` comments; new mutants (`ratchet-reintroduced-tolerated`, content-weakening `head_text`, live-gated); keep grown/stale/dup/order rows + machinery; chk texts updated.
- [ ] 1.6 `python3 -m py_compile`; replay state-table rows + new mutants green; `ratchet --base origin/main` on the commit → `pass live=0 baseline=0` + `oracle-inputs-changed` once (record in body).

## Phase 2 — sweep (task 4.5)

- [ ] 2.1 `ci.yml` :398-416 comment → strict-zero wording; job name/`if:`/`continue-on-error`/`permissions`/`fetch-depth`/env/step name untouched.
- [ ] 2.2 `RATCHET_BASELINE` still in `RATCHET_ORACLE`; probe parity row (:85-87) still in sync; run the probe's baseline-absent-at-tip `row_ow_*` rows.
- [ ] 2.3 Re-grep `inngest-probe-row.test.sh` (expect zero baseline hits — :143 is the test-affected-paths ALLOW row) and `ci-pr-affected-preactivation.sh` (zero coupling).
- [ ] 2.4 Residual-reference sweep (`grep -rln ci-pr-affected-audit.baseline` non-archive): only replay.py constants/docstring, suite fixtures, probe, runbook/ADR history; `test-affected-kb-consumers.baseline.txt` regenerate only if rows moved; re-verify rows :2860-2864 still classify the literal.

## Phase 3 — docs (tasks 4.6+4.7)

- [ ] 3.1 ADR-276 `### Stage status`: append dated closing line — `audit exits 0, ratchet strict; replay and go/no-go re-ruling pending` (#10861, PR #12127).
- [ ] 3.2 Runbook §7 strict-zero rewrite: failure table retires stale-line/dup/order/grown/adoption, adds `baseline-reintroduced`, keeps `baseline-deleted`; §7 intro; `--print-baseline` = live-pair listing; adoption paragraphs + "only the strict-zero end state may delete it" clause dropped (fulfilled); baseline-conflict recipe retired; drain claim + schedule marked complete; revert bullet updated (`baseline-reintroduced`); rollback recipe updated; observation-log deletion entry.

## Phase 4 — verify + battery (task 4.8)

- [ ] 4.1 Full replay suite; `test-affected-kb-consumers.test.sh`; `inngest-probe-row.test.sh`; observation-window rows; shellcheck; `py_compile`.
- [ ] 4.2 Final assertions: `test ! -f` the baseline; audit `gap_suites=0 unaudited=0 stale=0`; ratchet `live=0 baseline=0`; ADR grep matches; `PR_AFFECTED_LOCKED` matches; `CI_PR_AFFECTED` 404.
- [ ] 4.3 `--affected` degradation measured at work time (no RUNNER_TRIGGERS file touched); CI `test` is the merge gate.

## Phase 5 — close-out (task 4.9)

- [ ] 5.1 PR body: markers, `wc -l` accept.tsv, same-commit set, oracle-notice-once disclosure, receipts, `Closes #10861`.
- [ ] 5.2 Post-merge: #10861 final-marker comment + audit line + per-slice links; `s4-drain` label released (probe floor falls back to sentinel #11226 — conservative); #10448 mirror comment.

## Verification (final, on the merged tree)

- [ ] `test ! -f scripts/ci-pr-affected-audit.baseline.tsv`
- [ ] `audit --accept` → exit 0, `gap_suites=0 unaudited=0 stale=0`
- [ ] `ratchet --base origin/main` → `exit=0 reason=pass live=0 baseline=0`
- [ ] `grep -n "audit exits 0, ratchet strict" knowledge-base/engineering/architecture/decisions/ADR-276-*.md`
- [ ] `grep -n PR_AFFECTED_LOCKED scripts/ci-pr-selection.sh` matches; `gh api repos/jikig-ai/soleur/variables/CI_PR_AFFECTED` → 404
