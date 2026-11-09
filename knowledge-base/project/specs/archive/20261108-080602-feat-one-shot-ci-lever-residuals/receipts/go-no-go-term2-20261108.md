# S4 go/no-go re-ruling — term 2 rerun record (Ref #9729, ADR-276; non-activating)

Rule of the record (CTO R3, unchanged): GO iff every criterion passes; NO-GO iff any criterion fails outside the
10% band; UNDECIDED otherwise. The 10% band applies to the numeric thresholds (a and c) only. Computed with
`python3 -I scripts/ci-pr-affected-replay.py verdict`. **Term-2 rerun (2026-11-08/09):** scheduled re-run
unblocked by #12412's merge (folded-job classification in `ci-pr-affected-replay`, 2026-11-07T20:16Z); fresh
300-commit window on a detached `origin/main` worktree at `4fba0d512e` (verified ancestor `057f1e5ac` — the
classifier fix — and replay tooling byte-identical to merged main `404e4c626f`).

| # | Criterion (R3) | Measured (term 2, 2026-11-08/09) | Threshold | Status | Receipt |
|---|---|---|---|---|---|
| a | Escape rate: gating point estimate (attributable + unverified) at most 2%, AND the one-sided 95% Clopper-Pearson bound on the worst-case numerator under 12% | commits: 0 of 300 (0.00%, bound 1.57%). commits+ejections: **2 of 398 (0.50%) point; worst-case numerator 55 of 398 → bound 16.99%**. Routes of the 98 refused queue runs (446 merge_group runs in window: 348 success / 75 failure / 23 cancelled): 38 rule-irrelevant, 7 flake-cleared (identical-tree-green), 53 not-evaluable (29 `failed-job-without-fail-line`; 24 unsettled suite legs — `test-webplat` legs dominate, 2 `affected-index-ratchet`, 2 `test-scripts` — mostly the window's 23 cancelled runs), 2 unverified, 0 attributable, 0 escape. The 55-unit worst-case numerator = those 53 refused-run not-evaluable units + 2 unverified (the 1 unsettled commit unit, a `test-webplat(2/2)` cancel, sits inside the 53-class accounting via the commits population line) | point ≤ 2% and bound < 12% | **fail** (point passes; bound 16.99% ≥ 12%, outside any band) | `replay-summary-term2.txt`, `replay-summary-term2.tsv`, `ejections-window-term2.json` |
| b | Index completeness: zero unexplained gaps after the accept-file exemptions | Carried from the 2026-11-07 fresh record: `audit --all-refs --accept` on pinned tree `a2075a2e10`, exit 0, `unaudited=0 gap_suites=0 gap_refs=0`. Not re-run in term 2 — the schedule's term-2 scope was the replay; the ratchet is a required context since #12329 so any regression red-flags in CI itself | 0 gaps after exemptions, exit 0 | **pass** (carried, disclosed) | `index-audit.out`, `index-audit-bare-noaccept.out` |
| c | Net saving ≥ 20% of the billed job-minutes-per-pull_request-run baseline; restored selection + overhead ≤ 120 s | Carried from the 2026-11-07 fresh record (baseline 120.17 min/run, net ≥ 24.03). This run's own saving line corroborates at the bar's unit: `evaluable=224, mean_skipped_suite_min=73.85 (se 2.92), selector_min=1.29, net_mean=72.56, net+2se=78.41 vs bar_min=19.96` on the 99.80-min aggregate baseline | ≥ 24.03 net; ≤ 120 s | **pass** (carried + corroborated) | `criterion-c.md`, `census-w1.txt`, `census-w2.txt`, `replay-summary-term2.txt` |
| d | Every documentation-mentioning test file classified, none a real reader inside a skippable suite | Carried from the 2026-11-07 fresh record: 283 web-platform test files classified at tree `4591c12e39`, `test-affected-kb-consumers.test.sh` 31/31, baseline 330 rows over 124 suites | none unclassified | **pass** (carried, disclosed) | `reader-audit.md` |

Computed verdict: `computed=NO-GO reason=criterion-failed` (criterion a, the worst-case bound) from
`verdict --a fail --b pass --c pass --d pass`. `cp-upper 55 398` = 0.169912.

## Why criterion a still decides it

The point estimate stays clean where measurable (0 attributable, 0 escapes, 2 unverified → 0.50%, inside 2%),
but the worst-case contract still counts every unreadable unit as a potential escape. The bucket moved
61 → 55 and the bound 19.38% → 16.99% — direction right, still ≥ 12%. Two structural contributors did NOT
settle as hoped:

- **Cancelled queue runs barely moved: 24 → 23.** The schedule term gated on "queue-cancel rate settles"; it
  did not (446 runs, 23 cancelled). Their unsettled suite legs are 24 of the 53 not-evaluable units
  (`test-webplat` shard legs dominate — the canary legs a cancel strands mid-matrix).
- **`failed-job-without-fail-line` is unchanged at 29.** These are refused runs whose failing jobs produced
  no `[FAIL]`/`[KILLED]` line the tool can classify — pre-umbrella and standalone job legs the folded-job
  classifier (#12412) does not reach. Same count as term 1's "unclassified-job" bucket; whether the
  composition is identical is not re-graded by hand (the contract forbids it).

A counterfactual for the margin only, not re-graded: had the 29 `failed-job-without-fail-line` units been
`rule-irrelevant`, the worst case would be 26 of 398 → bound ~9.4%, inside 12%. The contract — an unreadable
or unclassified unit is never "no failure" — is what turns leg-observability gaps into a criterion failure.

## Collection-integrity note (transparency, not a defect)

Two anomalies were observed and verified harmless: (i) an orphaned prior-session `collect` process set
(`feat-one-shot-9323-escape-r3-rerule`, PPID 1) appended ~3 min of units to the same `--out` dir —
`load_units`'s duplicate `(kind,sha)` check collapsed them; final counts are exact (300/300 commits,
98 ejections == `refused=98` in `ejections-window-term2.json`); (ii) transient foreign replay processes
(sibling worktree smoke runs) made a `procs==0` wait unsatisfiable — completion was established on ground
truth (units counts + window file written + zero processes targeting the out dir), not on process absence.

## Non-activation statement (Decision 3(c)/(d))

Nothing in this record activates S4: `CI_PR_AFFECTED` stays unset, the `PR_AFFECTED_LOCKED` lock stays in
`scripts/ci-pr-selection.sh`, and `.github/workflows/ci.yml`, `scripts/required-checks.txt`, the ruleset and
every infra file are untouched by this evidence pass. Activation still needs, in order: the budget owner's
explicit go-ahead naming the command, the admin-side control decision (issue entry gate 2), and the stage-2
reduced-run read (`admin-merge-ready.sh` / `ci-head-verdict.sh`). With the verdict NO-GO on term 2 as well,
the retire-vs-schedule decision returns to the operator per #10448 — closing or scheduling is an operator
call, never a silent close. The two named residual reducers are now visible in the receipts: (a) cut the
cancelled-run share so unsettled legs drain, and (b) teach `ci-pr-affected-replay.py` the
`failed-job-without-fail-line` job-name set (the same classification work #12412 did for folded jobs) —
each is a lever against the worst-case numerator, not a waiver of the contract.

SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-11-09 term=2
