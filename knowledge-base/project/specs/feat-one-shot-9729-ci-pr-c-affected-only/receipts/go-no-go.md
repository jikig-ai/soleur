# S4 PR C go/no-go record (Ref #9729, ADR-276)

Rule of the record (CTO R3): GO iff every criterion passes; NO-GO iff any criterion fails outside the 10% band; UNDECIDED otherwise. The 10% band applies to the numeric thresholds (a and c) only: it does NOT apply to (b), whose threshold is zero (10% of zero is zero), so a later reader must not re-grade (b) as within-10%. A CTO ruling
can only move a computed verdict toward NO-GO. Computed with `python3 scripts/ci-pr-affected-replay.py verdict`.

| # | Criterion (R3) | Measured | Threshold | Status | Receipt |
|---|---|---|---|---|---|
| a | Escape rate (R2): the gating point estimate with unverified counted as escapes, AND the one-sided 95% Clopper-Pearson bound on the worst-case numerator | 0 of 300 commits (0.00%, bound 0.99%); 0 of 353 with the 53 queue ejections (0.00%, bound 2.18%) | point at most 2% and bound under 12% | **pass** (inside the 90% side of both thresholds) | `replay-summary.md` |
| b | Index completeness: zero unexplained gaps (every path a suite names is declared for it or covered by the runner trigger) | 145 of 630 suites name an undeclared tracked path (964 references); a 14-pair sample found 6 real reads, 3 fixture writes, 5 mentions | 0 gaps | **fail** | `index-audit.md` |
| c | Mean net saving at least 20% of the one 99.8 baseline, and no serial edge past the 75-minute declared path (restored selection plus overhead at most 120 s) | net mean 51.58 suite-minutes per commit (mean plus two standard errors 54.75, a lower bound on the web-platform axis); restored selection about 29 s of job time on a fresh runner | at least 19.96 and at most 120 s | **pass** (the 73 minute path plus about 33 s is 73.6 of 75) | `replay-summary.md`, `sel-s-canary.md` |
| d | Every documentation-mentioning test file classified, none a real reader inside a skippable suite | 238 web-platform test files mention the tree; the dropped-consumer census passes 30 of 30, baseline 274 rows over 104 suites (266 covered, 8 classified false positives) | none unclassified | **pass** (blind spots stated) | `reader-audit.md` |

Computed verdict: `computed=NO-GO reason=criterion-failed` (criterion b).

## Why criterion b decides it

The proposed per-suite rule is safe on the evidence the history can give (criterion a) and would save well over the bar (criterion c), but the
index it relies on is incomplete: 145 suites read paths the index does not declare for them, including doc-class paths (`README.md`, read by 31
suites). A replay can only see failures that happened, and the queue's full battery refused anything that broke a skippable suite before it landed,
so the history's zero escapes cannot show that the index is complete. Closing the gaps means declaring each real read (or removing it); that is
index work, not a threshold to argue, and it is the entry condition for any later attempt.

## Deviations from the brief and the plan (each recorded in `decision-challenges.md`)

- The cold/warm vehicle is a push-triggered throwaway branch (`canary-sel-9729`), not a `pull_request` run, because every pull request starts the
  164-minute battery (R4). The selector wall time does not depend on the event.
- The organization-variable check needed no organization-admin credential: the repo-scoped read returns HTTP 200 with `total_count` 0 (R7).
- Stage 2 (the Guard 3 read, the audit probe, the census split and the lock removal) was NOT built, as the plan's NO-GO path prescribes. The lock stays
  in `scripts/ci-pr-selection.sh`, `scripts/required-checks.txt` and the ruleset names are unchanged, and nothing was activated.

## Status of this record

CTO confirmation (second spawn, 2026-10-16), full text in `decision-challenges.md`: NO-GO confirmed. (b) is correctly `fail`: a known lower bound above zero
is a measurement, so `unmeasured` does not apply, and the status changes only on a re-run of the audit against a completed index, never on a better
estimate of the real-read share. (a) passing is a necessary condition that does not carry the decision and must not be cited as support for a GO.
Follow-on recommendation: fund index completion, and retire S4 if that work is not scheduled within one quarter (the operator owns the scope call).

SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-10-16
