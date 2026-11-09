# S4 go/no-go third re-ruling record (Ref #9729, ADR-276; non-activating)

Rule of the record (CTO R3, unchanged): GO iff every criterion passes; NO-GO iff any criterion fails outside the
10% band; UNDECIDED otherwise. The 10% band applies to the numeric thresholds (a and c) only. Computed with
`python3 -I scripts/ci-pr-affected-replay.py verdict`. **Third re-ruling** (the 2026-11-08 SCHEDULE term on
#9729, run once the queue-cancel rate settled): fresh 300-commit window `4fba0d512e…c6cd57f31d`
(2026-10-29T16:42:32Z..2026-11-08T20:07:13Z), fresh pinned-tree audit on `404e4c626f`, fresh per-run baseline.
The collect was adopted mid-flight per the plan's Phase-0 gate — see `adoption-note.md`, including the two
stale-window units found and removed.

| # | Criterion (R3) | Measured (2026-11-08) | Threshold | Status | Receipt |
|---|---|---|---|---|---|
| a | Escape rate: gating point estimate (attributable + unverified) at most 2%, AND the one-sided 95% Clopper-Pearson bound on the worst-case numerator under 12% | commits: 0 of 300 (0.00%, bound 1.57%). commits+ejections: **2 of 398 (0.50%) point; worst-case numerator 55 of 398 → bound 16.99%**. Routes of the 98 refused queue runs: 37 rule-irrelevant, 7 flake-cleared (identical-tree-green), 52 not-evaluable (29 failed-job-without-fail-line; 23 unsettled suite legs — test-webplat 19-20, test-scripts 2, affected-index-ratchet 2 — mostly from the window's 23 cancelled runs), 2 unverified, 0 attributable, 0 escape. The 55-unit worst-case numerator = those 52 refused-run not-evaluable units + 2 unverified + 1 unsettled commit unit (a `test-webplat (2/2)` cancel in the commit population). **The R2 `unclassified-job` bucket is gone: zero units** — the term-1 allowlist now names every post-umbrella job (`rule-body-lint`, `adr-ordinals`, `grok-fidelity`, `harness-discovery`, `cla-check`, `cla-evidence`), which moved to `rule-irrelevant` | point ≤ 2% and bound < 12% | **fail** (point passes; bound 16.99% ≥ 12%, outside any band) | `replay-summary.txt`, `replay-commits.tsv`, `ejections-window.json` |
| b | Index completeness: zero unexplained gaps after the accept-file exemptions | `audit --root /var/tmp/s4-audit --all-refs --accept <pinned accept file>` on the pinned detached tree `404e4c626f` (origin/main of the run): `suites=751 always_on=118 audited=633 unaudited=0 gap_suites=0 gap_refs=0 accepted=1639 stale=0 refs=4538 files_read=1269`, exit 0. (The same command WITHOUT `--accept` — the §4 spelling — reports the pre-exemption set: 266 gap suites / 1,639 refs / accepted=0; the plain `audit` subcommand does not auto-load the accept file, only `ratchet` does. Both outputs are committed.) | 0 gaps after exemptions, exit 0 | **pass** | `index-audit.out`, `index-audit-bare-noaccept.out`, `index-audit.err` |
| c | Net saving ≥ 20% of the billed job-minutes-per-pull_request-run baseline; restored selection + overhead ≤ 120 s | Fresh baseline 102.21 min/run (26,064.3 min over 255 completed PR runs, two adjacent closed 12 h censuses) → bar 20.44. Saving: 20 sampled full-battery PR runs → gross mean 68.46 suite-min/run (se 10.51), net of ~1 selection + ~3.4 ratchet = **64.06** ≥ 20.44; population-weighted by the legs' run share (test-scripts ran on 35.3% of PR runs) ≈ **19.76** vs 20.44 — 96.7% of threshold, inside the 10% band. Timing leg: PR C canary unchanged, ~29 s job path ≤ 120 s | ≥ 20.44 net; ≤ 120 s | **within-10%** (per-run reading passes; population-weighted lands 3.3% under the bar, inside the band) | `criterion-c.md`, `census-w1.txt`, `census-w2.txt` |
| d | Every documentation-mentioning test file classified, none a real reader inside a skippable suite | 285 web-platform test files mention the tree (measured at tree `761c040e98`); dropped-consumer census `test-affected-kb-consumers.test.sh` 31/31 pass (exit 0); baseline 340 rows over 130 suites (332 covered + 8 `false-positive:`, same tree); `apps/web-platform [repo-wide+component]` still sel=0 via `edge:consumed` on a README-only diff | none unclassified | **pass** (blind spots stated) | `reader-audit.md` |

Computed verdict: `computed=NO-GO reason=criterion-failed` (criterion a, the worst-case bound) from
`verdict --a fail --b pass --c within-10% --d pass`.

## Why criterion a decides it again

The escape measurement is clean where it is measurable (0 attributable, 0 escapes, 2 unverified — the point
estimate 0.50% is inside 2%), but the criterion also bounds the WORST case: the 53 `not-evaluable` units must
be counted as potential escapes, and 55 of 398 bounds at 16.99%. The bucket shrank from R2's 61 of 382
(bound 19.38%) and its composition changed: the 29 `unclassified-job` units are gone — the term-1 allowlist
classifies every post-umbrella job name now, and those runs moved to `rule-irrelevant` (37, up from 16).
What remains is 29 `failed-job-without-fail-line` units (a refused run whose failed jobs' logs name no
failing suite line — the classifier's reach, not coverage) and 23 unsettled suite legs (mostly the window's
23 cancelled runs). A counterfactual is recorded for the margin, not re-graded: had the 29 no-fail-line
units been classifiable, the worst case would be 26 of 398 → bound 8.95%, inside 12%. The contract — an
unreadable or unclassified unit is never "no failure" — is what turns unsettled legs and silent job logs
into a criterion failure, and it is deliberate: re-grading by hand would be exactly the move the contract
forbids.

## What changed since the 2026-11-07 NO-GO

- Criterion (a) stayed fail, narrowly: numerator 61 → 55 of a larger 398-unit population (bound 19.38% →
  16.99%); the allowlist fix eliminated the unclassified-job bucket entirely (29 units reclassified
  rule-irrelevant), leaving unsettled legs and silent job logs as the whole of the not-evaluable remainder.
- Criterion (c) moved pass → within-10%: the baseline re-measured down to 102.21 (bar 24.03 → 20.44) while
  the per-full-run saving moved 87.41 → 68.46 and the test-scripts leg's run share fell to 35.3% — the
  population-weighted reading now lands just under the bar. The per-run reading still passes plainly.
- Criterion (b) stayed pass (strict zero, 1,639 accepted pairs, no stale rows); (d) stayed pass.
- The window itself: 446 merge_group runs, 98 refused (75 failure, 23 cancelled) — the cancel rate
  (5.2%) is roughly R2's (5.7%), with all 23 cancels concentrated early in the window; the settled tail the
  SCHEDULE term waited for is real but the window still carries the earlier unsettled legs.

## Non-activation statement (Decision 3(c)/(d))

Nothing in this record activates S4: `CI_PR_AFFECTED` stays unset, the `PR_AFFECTED_LOCKED` lock stays in
`scripts/ci-pr-selection.sh`, and `.github/workflows/ci.yml`, `scripts/required-checks.txt`, the ruleset and
every infra file are untouched by this evidence pass. Activation still needs, in order: the budget owner's explicit go-ahead
naming the command, the admin-side control decision (issue entry gate 2), and the stage-2 reduced-run read
(`admin-merge-ready.sh` / `ci-head-verdict.sh`). The pre-activation gate's own read this evening agrees:
`SOLEUR_PR_AFFECTED_PREACTIVATION ready=false missing=lock,artifacts,verdict,prereq5` (`preactivation.out`).
With the verdict NO-GO a third time, the retire-vs-schedule decision returns to the operator per #10448 —
closing or scheduling is an operator call, never a silent close.

SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-11-08
