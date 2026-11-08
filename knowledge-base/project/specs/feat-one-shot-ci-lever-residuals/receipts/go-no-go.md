# S4 go/no-go re-ruling record (Ref #9729, ADR-276; non-activating)

Rule of the record (CTO R3, unchanged): GO iff every criterion passes; NO-GO iff any criterion fails outside the
10% band; UNDECIDED otherwise. The 10% band applies to the numeric thresholds (a and c) only. Computed with
`python3 -I scripts/ci-pr-affected-replay.py verdict`. **Re-ruling after the index drain reached strict zero**
(PR5z, #10861, 2026-11-05): fresh 300-commit window, fresh pinned-tree audit, fresh per-run baseline.

| # | Criterion (R3) | Measured (2026-11-07) | Threshold | Status | Receipt |
|---|---|---|---|---|---|
| a | Escape rate: gating point estimate (attributable + unverified) at most 2%, AND the one-sided 95% Clopper-Pearson bound on the worst-case numerator under 12% | commits: 0 of 300 (0.00%, bound 1.57%). commits+ejections: **2 of 382 (0.52%) point; worst-case numerator 61 of 382 → bound 19.38%**. Routes of the 82 refused queue runs: 16 rule-irrelevant, 7 flake-cleared (identical-tree-green), 59 not-evaluable (25 unsettled suite legs, mostly from the window's 24 cancelled runs; 29 unclassified-job — job names absent from the tool's allowlist: `rule-body-lint` 20, `adr-ordinals` 4, `grok-fidelity`/`harness-discovery` 4, `cla-check`/`cla-evidence` 1; 5 failed-job-without-fail-line), 2 unverified, 0 attributable, 0 escape | point ≤ 2% and bound < 12% | **fail** (point passes; bound 19.38% ≥ 12%, outside any band) | `replay-summary.txt`, `replay-commits.tsv`, `ejections-window.json` |
| b | Index completeness: zero unexplained gaps after the accept-file exemptions | `audit --root /var/tmp/s4-audit --all-refs --accept <pinned accept file>` on the pinned detached tree `a2075a2e10` (origin/main of the run): `suites=745 always_on=118 audited=627 unaudited=0 gap_suites=0 gap_refs=0 accepted=1605 stale=0 refs=4474 files_read=1259`, exit 0. (The same command WITHOUT `--accept` — the §4 spelling — reports the pre-exemption set: 259 gap suites / 1,605 refs / accepted=0; the plain `audit` subcommand does not auto-load the accept file, only `ratchet` does. Both outputs are committed.) | 0 gaps after exemptions, exit 0 | **pass** | `index-audit.out`, `index-audit-bare-noaccept.out` |
| c | Net saving ≥ 20% of the billed job-minutes-per-pull_request-run baseline; restored selection + overhead ≤ 120 s | Fresh baseline 120.17 min/run (24,394.2 min over 203 completed PR runs, two adjacent closed 12 h censuses) → bar 24.03. Saving: 20 sampled full-battery PR runs → gross mean 87.41 suite-min/run (se 10.58), net of ~1 selection + ~3.4 ratchet = **83.01** ≥ 24.03; population-weighted by the legs' run share (test-scripts ran on 39.4% of PR runs) ≈ **30.0** ≥ 24.03. Timing leg: PR C canary unchanged, ~29 s job path ≤ 120 s | ≥ 24.03 net; ≤ 120 s | **pass** (both readings) | `criterion-c.md`, `census-w1.txt`, `census-w2.txt` |
| d | Every documentation-mentioning test file classified, none a real reader inside a skippable suite | 283 web-platform test files mention the tree; dropped-consumer census `test-affected-kb-consumers.test.sh` 31/31 pass (exit 0); baseline 330 rows over 124 suites (322 covered + 8 `false-positive:`); `apps/web-platform [repo-wide+component]` still sel=0 via `edge:consumed` on a README-only diff | none unclassified | **pass** (blind spots stated) | `reader-audit.md` |

Computed verdict: `computed=NO-GO reason=criterion-failed` (criterion a, the worst-case bound) from
`verdict --a fail --b pass --c pass --d pass`.

## Why criterion a decides it this time

The escape measurement is clean where it is measurable (0 attributable, 0 escapes, 2 unverified — the point
estimate 0.52% is inside 2%), but the criterion also bounds the WORST case: the 59 `not-evaluable` units must be
counted as potential escapes, and 61 of 382 bounds at 19.38%. The bucket is swollen for structural reasons the
receipts name — 24 cancelled queue runs (double the prior window's rate) leave suite legs unsettled, and 29
refused runs failed only jobs the tool's allowlist does not know (`rule-body-lint` and friends, standalone jobs
before the #12089 umbrella folded them). A counterfactual is recorded for the margin, not re-graded: had those
29 been `rule-irrelevant`, the worst case would be 32 of 382 → bound 11.09%, inside 12%. The contract — an
unreadable or unclassified unit is never "no failure" — is what turns pre-umbrella job-name drift into a
criterion failure, and it is deliberate: re-grading by hand would be exactly the move the contract forbids.

## What changed since the 2026-10-16 NO-GO

- Criterion (b) moved fail → pass: the drain series (PR4/PR4b/PR4c/PR5a–d/PR5z) took 294 gap suites to strict
  zero; the fresh audit on a current pinned tree exits 0 with 1,605 accepted pairs and no stale rows.
- Criterion (c) moved unmeasured → pass: the baseline is re-measured on the current workflow shape
  (120.17 min/run, not 99.8) and the saving is measured per pull_request run, in the bar's own unit.
- Criterion (a) moved pass → fail: the point estimate stays ~0, but this window's worst-case numerator (61)
  is ten times the prior one (6 of 356 → 3.30%), driven by cancelled-run unsettled legs and the job-name
  drift above; the bound no longer fits under 12%.

## Non-activation statement (Decision 3(c)/(d))

Nothing in this record activates S4: `CI_PR_AFFECTED` stays unset, the `PR_AFFECTED_LOCKED` lock stays in
`scripts/ci-pr-selection.sh`, and `.github/workflows/ci.yml`, `scripts/required-checks.txt`, the ruleset and
every infra file are untouched by this evidence pass. Activation still needs, in order: PR3b's
required-context flip of `affected-index-ratchet` (#10859/#12329), the budget owner's explicit go-ahead
naming the command, the admin-side control decision (issue entry gate 2), and the stage-2 reduced-run read
(`admin-merge-ready.sh` / `ci-head-verdict.sh`). With the verdict NO-GO again, the retire-vs-schedule
decision returns to the operator per #10448 — closing or scheduling is an operator call, never a silent close.

SOLEUR_PR_AFFECTED_VERDICT verdict=NO-GO ruled=confirmed date=2026-11-07
