# Code Quality Analyst — PR #12127 (feat-one-shot-10861-pr5z-strict-zero)

Seat: `soleur:engineering:review:code-quality-analyst` · HEAD `79db88e18b` · diff `origin/main...HEAD` (10 commits)
Scope read: `scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/test-all.sh`, `.github/workflows/ci.yml`, `.gitattributes`, `scripts/ci-pr-affected-audit.{accept,baseline}.tsv`, ADR-276 amendment line, runbook §7. Report-only; no worktree writes; one `--help` probe (read-only).

## Executive summary

- Findings: 0 P1 · 2 P2 · 6 P3
- Overall quality: 8/10. The new `baseline-reintroduced` arm is placed correctly (before the `new`-pair block, matching the documented verdict ORDER exactly), the marker token is consistent end-to-end, the three new mutants each kill on a distinct half of `row_rt_reintroduced`, and every settled CTO ruling (9–16) is implemented as decided. The remaining defects are all the same class: pre-strict-zero "ratchet tolerates a red audit / committed baseline exists" framing survives in text surfaces this PR touched but did not fully sweep.
- Top 3: (1) the `--help` RATCHET paragraph — the text the runbook defers to as "the contract" — still opens "green on a tree whose audit exits 1 … must EQUAL a committed, shrink-only baseline (scripts/ci-pr-affected-audit.baseline.tsv …)"; (2) runbook §7 still opens "The audit exits 1 on main today" and instructs `wc -l` on the deleted file, while `receipts/audit-final.txt` on this branch records `gap_suites=0`; (3) sweep the surviving "adoption" vocabulary in the test battery and `ratchet_base`'s docstring.

## Detailed findings

### P2-1 — `--help` contract text contradicts strict zero (docstring accuracy)

- **Location:** `scripts/ci-pr-affected-replay.py:135-136` (RATCHET paragraph opening); same clause at `scripts/ci-pr-affected-replay.py:2517` (the `ratchet` subparser `help=` string).
- **Smell:** stale documentation / Speculative-Generality wording that no longer terminates in any real state.
- **Evidence:** `--help` prints `` `ratchet` is the audit as a CI check that is green on a tree whose audit exits 1: the live gap set (after the --accept exemptions) must EQUAL a committed, shrink-only baseline (scripts/ci-pr-affected-audit.baseline.tsv …)``. Post-strict-zero: (a) no committed baseline exists — `RATCHET_BASELINE` is now a watch-path, not a comparison target; (b) "green on a tree whose audit exits 1" is a vacuous antecedent — the audit exits 1 only on gap / unaudited / stale-accept, and each maps to a ratchet verdict (new-pair / unaudited / stale-accept), so audit-red ⟺ ratchet-red. The distinguishing property that made it a "ratchet" is gone.
- **Impact:** runbook §7:158-159 defers to this text verbatim as the contract ("Its contract … is the RATCHET section of `--help`"), so the cited contract now opens with a sentence the rest of the same section refutes. `tasks.md` item 1.2 lists the BASELINE STATE, verdict list, "(adoption, deletion)" and `--print-baseline` spots as updated — the opening sentence and the argparse `help=` are the two spots the sweep missed.
- **Recommended fix (low risk):** rewrite the opening sentence to the strict-zero shape ("the live gap set must be EMPTY … a baseline file at the watched path is baseline-reintroduced"), keep the rest; no test pins this phrasing (verified by grep — nothing matches "green on a tree"/"shrink-only" against this file).
- **Dependencies:** none.

### P2-2 — Runbook §7 opening is internally stale

- **Location:** `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md:155` (and the `wc -l` instruction it carries).
- **Smell:** stale documentation contradicting the same section's own rewrite two sentences later.
- **Evidence:** line 155 opens "The audit exits 1 on `main` today (the committed baseline holds whatever `wc -l scripts/ci-pr-affected-audit.baseline.tsv` reports, which is the number to quote …)". Post-merge the file does not exist (the `wc -l` fails), and `receipts/audit-final.txt` on this branch records `gap_suites=0 gap_refs=0 stale=0` — the audit exits 0 on main, so the premise "a check that simply required the audit to pass could never be green" is now false. The very next sentence was correctly rewritten to strict zero, leaving the paragraph self-contradictory.
- **Also at line ~212:** "the pairs that remain in the file (`wc -l` is the count)" — inside drain-history narrative, but the imperative `wc -l` on a deleted path is stale (fold into the same edit).
- **Recommended fix (low risk):** reframe the opening as history ("The audit exited 1 on main while the committed baseline carried gap pairs; PR5z retired the file, the audit is green and the check is strict zero").
- **Dependencies:** none.

### P3-1 — Same vacuous clause in the edited ci.yml comment

- **Location:** `.github/workflows/ci.yml:400-403` — "`ratchet` is green on a tree whose audit exits 1 when the live set … is empty". Vacuous antecedent identical to P2-1; the comment block was rewritten in this PR and kept the framing. The remainder of the comment correctly describes strict zero, so this is misleading rather than wrong; harmonize when P2-1 is fixed.

### P3-2 — Runbook failure-table row overclaims "unreachable"

- **Location:** `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md:191` — the merged row "`stale-line`, `baseline-dup`, `baseline-order`, `grown` … unreachable at the default path now that no committed baseline exists". At the default path these tokens CAN print — a PR that re-adds a malformed baseline fires `baseline-reintroduced` AND co-fires `stale-line`/`baseline-dup`/`baseline-order` detail (they are computed unconditionally at `ratchet_run` 2066-2078; `row_rt_big_baseline` at test line 2504-2511 proves the dup/stale checks still run under the reintroduced marker). Only `grown` is truly base-gated. Suggested wording: "unreachable at the default path unless a baseline is re-added (then they co-fire under `baseline-reintroduced`)".

### P3-3 — Contradictory remedies when reintroduced co-fires present/present checks

- **Location:** `scripts/ci-pr-affected-replay.py:2090-2097` — the `stale-line`/`baseline-dup`/`baseline-order`/`grown` remedy tail ("restore main's copy with `git checkout origin/main -- <rel>`, then `--print-baseline` > … > mv") prints whenever those checks fire, including under a co-firing `baseline-reintroduced`. On a re-added file the suggested `git checkout origin/main --` fails (main has no such file), and the prune-and-keep recipe it proposes is exactly the re-adoption strict zero forbids. The correct "remedy: delete <rel>" prints first under the reintroduced finding, so this is confusing rather than dangerous; consider suppressing the tail (or qualifying it) when `baseline-reintroduced` is in `names`. Deferred-fix acceptable.

### P3-4 — "adoption" vocabulary survives in five test/helper spots

- `plugins/soleur/test/ci-pr-affected-replay.test.sh:2273` — fixture `rt_b_adopt`/`rt_p_adopt` and the `adopt` scenario token now build the reintroduced shape; the name describes a verdict that no longer exists. Defensible as "the absent-at-base shape", but a rename (`rt_*_reintro`) would match the row names this PR already renamed.
- `plugins/soleur/test/ci-pr-affected-replay.test.sh:2970` — chk description still says "a PR-tree helper that always reports adoption changes no verdict" while the PR updated the same row's inline comment (line 2514) to "baseline-reintroduced" — an inconsistency introduced inside this diff.
- `plugins/soleur/test/ci-pr-affected-replay.test.sh:4889,4895` — mutant names `ratchet-adoption-refused` and `ratchet-unresolved-base-is-an-adoption` (the latter now produces `baseline-reintroduced`-shaped outcomes, not "adoptions").
- `scripts/ci-pr-affected-replay.py:1869` — `ratchet_base` docstring "An unresolvable base is exit 2, never an adoption." Retired term; "never silently a verdict" or "never baseline-reintroduced" is the current semantics.
- All are naming/comment drift only; the settled token `baseline-reintroduced` is used everywhere it matters.

### P3-5 — PR3b entry-condition line references a now-moot check

- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md:266` — the PR3b entry condition still names "the cumulative baseline check evaluated at PR3b merge time (`git diff <PR3a-merge-sha> origin/main -- scripts/ci-pr-affected-audit.baseline.tsv` has no added line)". Still evaluable (a deletion shows no added lines) and the observation-window probe `ratchet-observation-window-10865.sh:497-498` already treats tip-absence as the end state, so nothing breaks — but under `baseline-reintroduced` the condition is superseded in kind. Worth a parenthetical, not a rewrite.

### P3-6 — Historical measurement paragraph ordering nit

- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md:155` — the dated measurements (294/1,884 gap suites/pairs, `wc -l` figure) are retained inline in a sentence whose framing is now false (P2-2). When that sentence is reframed as history, the measurements belong with the drain-completion paragraph rather than the operating instruction.

## Verified consistent (no finding)

- **Arm placement/order:** `ratchet_run` 2058-2060 sits between `stale-accept` (2055) and `baseline-deleted`/`new-pair` (2061-2065) — exactly the documented ORDER at 149-150. `q(rel)` in the detail line vs bare `rel` in the remedy mirrors the adjacent `baseline-deleted` arm.
- **Settled rulings all implemented:** token `baseline-reintroduced`; present/present machinery retained (2042, 2066-2078); arm before the new-pair block; `! grep -q '^grown'` absent-grown assertion present (test:2473); baseline deletion in exactly one commit (`ab487915f1`); ci.yml step name untouched; `st["baseline"]` semantics unchanged.
- **Mutant coverage:** the three new mutants are each killed by a distinct mechanism — `tolerated`/`live-gated` by the `std adopt` half (live==baseline → without the arm, exit 0), `content-weakened` by the `good adopt` half (empty `head_text` falsy → arm skipped → exit 0); `ratchet-adoption-refused` (grown-check widening) is killed by the absent-grown assertion. Clean design.
- **Row-range consistency:** `^mutate `=473 + `^ow_mutate `=126 = `DECLARED_TOTAL=599`; arms tile 1-193 / 194-386 / 387-599 contiguously; `chk` sites are ungated by design (line 67-77 comment); `rows-range.sh` FATALs on count drift; `scripts-shard-totality.test.sh` asserts the tiling. Receipt `suite-c-arm-v2.rc`=0.
- **Accept-TSV sweep:** exactly the 42 `scripts/ci-pr-affected-audit.baseline.tsv` rows removed (replay-a/b/c × 14); each would be `stale-accept` (`path-untracked`) post-deletion — confirmed by `audit-final.txt` `stale=0`. `.gitattributes` line correctly removed with the file (keeping it would be dead config; a re-add is caught by the new arm anyway).
- **New edge declaration:** `AFFECTED_..._CODEQL_TO_ISSUES_SWEEP_WIRING_TEST_SH_PATHS` (test-affected-paths.sh:519-523) declares the pair that main's `2e0593a3aa` left live — required for strict-zero green; naming/placement convention matches (alphabetical slot, `file:line` anchor comment verified at test line 25, `THIS FILE` self-edge).
- **Oracle/probe compatibility:** `row_rt_oracle` correctly expects `baseline-reintroduced` + the three-name notice; probe `MARKER_RE` `[a-z0-9-]+` accepts the token; probe handles absent-at-tip.
- **Docstring spots updated:** ORDER list, BASELINE STATE paragraph, "(adoption, deletion)" → "(reintroduction refusal, deletion)", `--print-baseline` live-pair-listing wording, runbook `--print-baseline` paragraph, revert bullet, drain claim/schedule marked COMPLETE, observation-log entry.

## Dissent notes

None blocking. All eight settled rulings are implemented as decided and verified in the diff. The only naming tension is the retained `adopt` fixture token / `adoption`-suffixed mutant names (P3-4) — the rulings fixed the verdict token, not the fixture vocabulary, and renaming would churn ~6 sites for zero behavioural gain; flagging for the record, not disputing. The un-suppressed present/present remedy tail under `baseline-reintroduced` (P3-3) is consistent with the "keep present/present machinery" ruling — the concern is only the contradictory remediation text, fixable later.

## Refactoring roadmap / effort

1. P2-1 + P2-2 (single doc-sweep commit, Small): `--help` opening + `help=` string + runbook §7 opening/`wc -l` — all the same sentence shape.
2. P3-1, P3-2 (trivial, fold into 1): ci.yml clause, table-row "unreachable" wording.
3. P3-4 (Small, optional): vocabulary rename sweep in the test battery + `ratchet_base` docstring.
4. P3-3 (Small, optional): suppress/qualify the prune tail under `baseline-reintroduced`; no test churn expected beyond `row_rt_big_baseline`'s output shape.
Expected state after 1-2: zero stale references to a committed baseline in any surface an operator reads during triage.

## Commands run

`git fetch origin main`; `git diff origin/main...HEAD` (+ per-file); `git log`/`merge-base --is-ancestor` (ancestry + single-commit deletion check); `grep`/`sed`/`read` on the five focus files, the probe, and `rows-range.sh`; `python3 -c "import ast…"` + `python3 -I scripts/ci-pr-affected-replay.py --help` (read-only probe); `git status` (worktree untouched). No test suite was executed (existing receipt `suite-c-arm-v2.rc`=0 relied upon); no writes to the live tree.
