---
title: "chore(ci): Lever A residuals — stale suite prices + drift arm + #9323 re-measure — and S4 go/no-go re-ruling (#9729)"
type: chore
date: 2026-11-07
slug: ci-lever-residuals
branch: feat-one-shot-ci-lever-residuals
issue: 12016
closes: [12016]
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# chore(ci): Lever A residuals — stale suite prices + drift arm + #9323 re-measure — and S4 go/no-go re-ruling (#9729)

## Overview

One change-set closing three CI-machinery residuals, all demanded by the hosted-runner
demand-reduction epic (#11556 / ADR-276):

1. **#12016 (Lever A residual).** Two committed `measured` prices in
   `scripts/suite-durations.tsv` are stale by ~43–109× (`scripts/test-all-group-affected`
   priced 3,200 ms vs 349.5 s measured; `.claude/hooks/git-commit-secret-scan.test.sh` priced
   6,938 ms vs 297.1 s). Refresh both rows, and close the detection hole that let them rot:
   the `--drift-report` emission contract in `scripts/regenerate-shard-manifest.py` only
   reports `src=floor`/`estimate` rows, so a stale *measured* price is invisible to the
   weekly shard-balance watch. Add a `PRICE_DRIFT_ROW` emission + watch finding.
2. **#9323 (Lever A residual).** Its implementing PRs (#9324, #11088, #11767; #11495 is the
   sweeper-cap PR that set the 300 s kill, not a #9323 implementation) are
   merged; the only open acceptance box is the post-merge re-measure, whose soak probe
   `scripts/followthroughs/pr-battery-gate-saving-9323.sh` cannot converge inside its 270 s
   wall deadline (four consecutive `NOT YET` sweeps ending "during the artifact downloads").
   Give the probe an operator-local budget seam, run the verdict math once locally, post the
   result on the tracker, and on PASS close the issue and retire the probe per its own
   RETIREMENT block.
3. **#9729 (Lever C, S4).** The issue's "re-decide gate" is superseded: ADR-270 is
   `accepted`, the operator waived the S2/S3 census gate on 2026-10-12 (ADR-276 amendment),
   and the follow-on decision #10448 ran to **strict zero** on 2026-11-05
   (`gap_suites=0 unaudited=0`). The stage log's pending item is now "replay and go/no-go
   re-ruling". This PR produces that evidence — fresh audit, fresh 300-commit replay window,
   criterion (c) re-measured in the correct unit (billed job-minutes per pull_request run),
   the committed `verdict` arithmetic — commits the receipts, appends the ADR-276 amendment
   and stage line, and posts the result on #9729. **Nothing is activated**: `CI_PR_AFFECTED`
   stays unset, the lock stays, `ci.yml`/`scripts/required-checks.txt`/the ruleset are
   untouched, and PR3b (#10859 / open PR #12329) remains the required-context flip held for
   the budget owner.

## Problem Statement / Motivation

- Stale prices corrupt shard-balance math the same way a `floor` row does, but worse: a
  `floor` row is honest about being an estimate, while a wrong `measured` row looks
  authoritative (audit: `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md`
  finding 2). Post-refresh predicted leg totals: leg 4 26.4 min, leg 6 29.9 min, max/mean
  ratio 1.26 — real imbalance, still under the watch's 1.30 flag bound.
- #9323's re-measure has been unconverged for ~4 weeks (deadline-starved since #11495's
  300 s sweeper cap; earlier NOT YETs were insufficient-qualifying-runs): the probe needs ≥20
  qualifying runs × ~13 artifact reads inside 270 s, and the artifact phase alone exceeds
  the deadline. Every sweep exits 2 `NOT YET`; the issue carries `needs-attention`.
- #9729's NO-GO rested on criterion (b), index completeness, which is now satisfied. The
  ADR demands a re-ruled verdict before the stage proceeds or retires; leaving it pending
  keeps a dark lever, an advisory ratchet (~3.4 billed min/run), and an open P3 issue in
  limbo.

## Proposed Solution

- **#12016:** edit the two `measured` rows in place (ms, `measured` src preserved); extend
  `drift_report_group()` to emit `PRICE_DRIFT_ROW <group> <label> <committed_ms> <fresh_ms> <timed>/<sampled>`
  for `src=measured` rows past the flag bound; teach `watch-shard-balance-11564.sh` to turn
  each into a `price-drift` finding on its existing tracker. No manifest regen in this PR.
- **#9323:** add `PBG_UNBOUNDED=1` operator seam (lifts the wall deadline for local runs;
  the sweeper never sets it; `PBG_BUDGET_S` ≤300 contract unchanged), run the probe locally
  with `GH_TOKEN` from `gh auth token`, post the verdict on #9323, and branch on it (below).
- **#9729:** execute runbook `ci-pr-affected-activation.md` §3 item 3 — fresh `audit` on a
  pinned `origin/main` tree, `collect`/`ejections`/`aggregate` over a fresh 300-commit
  window, criterion (c) measured per pull_request run (census + per-PR `--print-selection`
  pricing), criterion (d) re-verified; feed the four statuses to
  `python3 scripts/ci-pr-affected-replay.py verdict`, commit the receipts, append the
  ADR-276 amendment + stage-status line, comment on #9729. CTO re-ruling is spawned at work
  time per the technical-ruling delegation rule; without spawn capability the verdict's
  machine computation stands and the ruling row records `pending - assumed`.

## Technical Approach

### Architecture

**Drift arm (detected hole, closed in place).** The generator is the declared measurement
authority (`drift_report_group`, `scripts/regenerate-shard-manifest.py:623`): it already
computes `fresh[label]` medians for every sampled label, but emits `DRIFT_ROW` only for
`src=floor`/`estimate`. The arm adds one emission class for `src=measured` labels past a
bound, and one finding class in the watch's flag loop
(`scripts/watch-shard-balance-11564.sh`, step (4) threshold block ~:127). Sentinel identity
is `price-drift + group + label`, consistent with the existing `floor-row` identity —
magnitude slides inside a persistent episode do not re-post.

**Probe budget seam.** `pr-battery-gate-saving-9323.sh:88` pins `BUDGET="${PBG_BUDGET_S:-270}"`
with a `<= 300` validation because the sweeper kills probes at 300 s. The seam
`PBG_UNBOUNDED=1` replaces the wall deadline with a far-future bound (`END=$((T0+86400))` —
under `set -u` an unset `END` would crash `api()`'s `rem=$((END-SECONDS-5))`, so the seam
overrides the bound, never removes it; per-call caps stay at 60 s and budget-cut rc 46 is
unreachable in practice). Sweeper behaviour is unchanged: the variable is never set there
and the `<=300` pin still guards `PBG_BUDGET_S`.

**S4 evidence.** All commands are READ-ONLY (runbook §4); the only writes are the replay's
`--out` directory (outside the repo), the committed receipts under this branch's spec dir,
the ADR-276 append, and GitHub issue comments. The replay is resumable and `--chunk I/K`
parallelizable; start it in the background while Phase 1/2 edits land.

### Implementation Phases

#### Phase 0 — Recon kickoff (~10 min active; replay runs in background)

- `git fetch origin main`; start
  `python3 -I scripts/ci-pr-affected-replay.py collect --out /var/tmp/s4-replay --commits 300 --base origin/main`
  chunked in background, then `ejections` into the same dir (runbook §4 commands verbatim).
- Fresh pinned audit: `git worktree add --detach /var/tmp/s4-audit origin/main`;
  `python3 -I scripts/ci-pr-affected-replay.py audit --root /var/tmp/s4-audit --all-refs`
  (expect `gap_suites=0 unaudited=0 stale=0`; any `stale` row exits 1 and must be drained
  in-PR per the drain-reveal rule before the re-ruling).

#### Phase 1 — #12016 price refresh + drift arm

- `scripts/suite-durations.tsv`: `scripts/test-all-group-affected` 3200→349500;
  `.claude/hooks/git-commit-secret-scan.test.sh` 6938→297100.
- `scripts/regenerate-shard-manifest.py` `drift_report_group()`: after the
  floor/estimate `DRIFT_ROW` loop, emit `PRICE_DRIFT_ROW` for `src=measured` labels where
  `timed_n[label] >= 3`, `max(committed, fresh)/min(committed, fresh) >= 4.0`, and
  `|fresh - committed| >= 120000`. Update the emission-contract docstring.
- `scripts/watch-shard-balance-11564.sh` step (4): `PRICE_DRIFT_ROW *` →
  `findings+=("price-drift $g $label committed=${committed}ms median=${fresh}ms")`.
- Tests: `plugins/soleur/test/regenerate-shard-manifest.test.sh` (emission bound, both
  directions, timed<3 suppression) and `scripts/watch-shard-balance-11564.test.sh`
  (flag parse, sentinel identity strips magnitudes, second-member flagging). Guard Contract
  matrix below is written before the code.

#### Phase 2 — #9323 re-measure

- `scripts/followthroughs/pr-battery-gate-saving-9323.sh`: add the `PBG_UNBOUNDED` seam +
  header note; `.test.sh`: seam validation rows.
- Local run: `GH_TOKEN="$(gh auth token)" PBG_UNBOUNDED=1 bash scripts/followthroughs/pr-battery-gate-saving-9323.sh`
  (backgrounded; ~15–60 min of API calls + artifact downloads).
- **PASS arm:** post the verdict output on #9323, close the issue as completed, and retire
  the probe per its RETIREMENT block — delete `pr-battery-gate-saving-9323.sh` +
  `.test.sh`, the `run_suite` line (`scripts/test-all.sh:7091`), the
  `suite-shard-legs.tsv:438` and `suite-durations.tsv:436` rows (label sets must stay equal
  across the two tables), and the probe mention in ADR-262's Consequences (:132).
- **FAIL arm:** post the verdict output on #9323, leave the issue open, keep the probe —
  the FAIL is the answer the soak exists to produce; record the follow-up decision on the
  issue (widen arrays vs revert is an operator-scope call, not decided here).
- **NOT YET arm** (cannot reach 20 qualifying runs even unbounded): post the attempt
  numbers on #9323, keep the probe, and file the structural starvation fix (parallelized
  artifact reads / resumable progress) as a follow-up issue — a probe that cannot converge
  is a defect, not a green.

#### Phase 3 — #9729 go/no-go re-ruling

- `aggregate` the replay (`--expect-commits 300`), `cp-upper` for the bound → criterion (a).
- Criterion (b): the Phase-0 audit exit code (0 expected on the strict-zero tree).
- Criterion (c), correct unit — billed job-minutes **per pull_request run**:
  - baseline: `bash scripts/ci-demand-census.sh --start <t0> --end <t1> --workflow ci.yml --summary`
    over a recent closed window (the 99.8 figure predates S3/push-dedupe/umbrella/oracle
    changes); bar = 20% of measured baseline.
  - saving: for a sample of recent completed pull_request runs, take each PR's changed-file
    list (`gh api repos/$REPO/pulls/<n>/files`), run
    `env -u CI -u SOLEUR_TEST_FORCE_ALL bash scripts/test-all.sh --print-selection --paths=<list>`,
    price the would-be-skipped suite set via `suite-durations{,-heavy}.tsv`, subtract the
    ~1 billed min selection job + the ~3.4 billed min/run advisory-ratchet overhead the
    2026-10-22 amendment counts against this criterion. Write method + raw rows to
    `receipts/criterion-c.md`. The restored-selection timing leg reuses PR C's canary
    receipt (cold 146 s / warm 13 s → ~29 s job path, ≤120 s bar).
- Criterion (d): `bash scripts/test-affected-kb-consumers.test.sh` + re-run the
  dropped-consumer census into `receipts/reader-audit.md`.
- `python3 scripts/ci-pr-affected-replay.py verdict --a <s> --b <s> --c <s> --d <s>` —
  read `computed=` (exit code carries no verdict). Commit receipts under
  `knowledge-base/project/specs/feat-one-shot-ci-lever-residuals/receipts/` ending in
  `SOLEUR_PR_AFFECTED_VERDICT verdict=<v> ruled=<confirmed|computed> date=<YYYY-MM-DD>`.
- Append `## Amendment <date> (S4 go/no-go re-ruling, #9729)` to ADR-276 (verdict, the four
  criterion figures, receipt path line `Go/no-go receipt: <path>`, explicit non-activation)
  + a dated stage-status line under `### Stage status`.
- Update runbook `ci-pr-affected-activation.md` §2 "Where things stand".
- Comment the result on #9729: verdict, criteria table, and the remaining blockers —
  PR3b required-context flip (#10859/#12329), the budget owner's explicit activation
  go-ahead, the admin-side control decision (issue entry gate 2), and the stage-2
  reduced-run read (`admin-merge-ready.sh` / `ci-head-verdict.sh`) that a GO would owe.
- If the verdict is NO-GO again (the rough per-run estimate ~11.6 net billed min is under
  the ~20 bar), the amendment recommends the retire-vs-schedule decision to the operator —
  that is an operator (scope/priority) call, never silently closed.

#### Phase 4 — Consolidate

- `specs/<branch>/tasks.md`, decision-challenge rows resolved, plan finalized, PR #12354
  body filled.

## Alternative Approaches Considered

| Option | Rejected because |
|---|---|
| Full manifest regen (`--runs 5 --write`) alongside the price refresh | Not asked for; regen re-seats unrelated drifted rows (noisy diff); post-refresh max/mean = 1.26 is under the 1.30 flag bound, so the watch itself confirms no forced rebalance |
| Run the #9323 verdict math as an uncommitted one-off script | Duplicates ~200 lines of verdict logic unmaintained; leaves the probe's starvation unaddressed if the verdict isn't PASS; a 15-line tested seam is cheaper and auditable |
| Parallelize artifact downloads inside the 270 s budget | Doesn't fix the cumulative examine+escape phases; adds concurrency complexity to a retiring probe; retained as the contingency if the local run still can't converge |
| Marker-comment convention (like `S2-EXIT-CENSUS`) so the sweeper passes on posted local evidence | Changes the probe's verdict contract for a one-shot close; the local run IS the evidence the acceptance box wants — the probe retires on PASS rather than learning a bypass |
| Close #9729 as superseded by the oracle lane (#12156) | The lane is a different classifier surface (literal oracle paths, not the learned index); ADR-276 keeps S4 NO-GO pending the re-ruling — closing skips the owed evidence |
| Plan the full S4 activation machinery (stage-2 build, `[full]` marker, `admin-merge-ready.sh` read) | Explicitly gated: the re-ruling precedes the stage-2 build, and activation needs the budget owner's go-ahead naming the command + the admin-side control decision + PR3b. Out of scope by the ADR's own ordering |

## User-Brand Impact

- **If this lands broken, the user experiences:** mispriced shard scheduling — `test-scripts`
  leg imbalance (CI slower/flakier for every open PR); or a wrongly-recorded S4 verdict
  misleading the next lever decision. No end-user surface: all edits are repo-internal CI
  machinery (`meta/machinery`).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure —
  the probe seam reads public-to-`gh`-auth Actions data with the operator's own token; the
  replay and audit are read-only.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches pricing tables, watch/probe
  scripts, receipts and one ADR append — no credential, auth, data, payment or user-owned
  resource path (sensitive-path regex verified against the file list below: zero matches),
  so the next tier does not apply.

## Observability

```yaml
liveness_signal:
  what: "weekly shard-balance-watch.yml run + its owned tracker 'ci-shard-balance-watch: manifest drift findings' (findings comment on flag-set change, resolution comment + close on all-clear); the sweeper's per-probe NOT YET/PASS comments on each followthrough tracker"
  cadence: "weekly (shard-balance-watch.yml) / ~4x daily sweeps (scheduled-followthrough-sweeper.yml)"
  alert_target: "GitHub tracker issues + Actions run conclusion"
  configured_in: ".github/workflows/shard-balance-watch.yml, .github/workflows/scheduled-followthrough-sweeper.yml"
error_reporting:
  destination: "Actions run log + tracker comments; watch exit 3 = cannot-establish (never a green all-clear)"
  fail_loud: "watch exit 3 line '::error::<reason>'; probe exit 3 'CANNOT ESTABLISH'; PRICE_DRIFT findings land as tracker comments"
failure_modes:
  - mode: "suite-timings artifact retention expires across all sampled runs"
    detection: "watch: zero artifact-bearing runs -> exit 3 (existing)"
    alert_route: "red weekly workflow run"
  - mode: "emission contract drift between generator and watch (row silently unparsed)"
    detection: "the two pinned test files exercise the row shape end-to-end"
    alert_route: "red test-scripts leg on the PR that drifts it"
  - mode: "a measured price goes stale again"
    detection: "the new price-drift finding on the weekly watch (this PR)"
    alert_route: "tracker issue comment on flag-set change"
logs:
  where: "GitHub Actions run logs for both workflows"
  retention: "GitHub default (~90 days)"
discoverability_test:
  command: "grep -l PRICE_DRIFT_ROW scripts/regenerate-shard-manifest.py"
  expected_output: "scripts/regenerate-shard-manifest.py"
```

No new soak enrollment (Phase 2.9.1): #9323's soak already exists and retires on PASS;
the #9729 re-ruling is a one-shot measurement, not a time-gated criterion. No new
autonomous-task surface (Phase 2.9.3): the watch and sweeper already exist.

## Architecture Decision (ADR/C4)

### ADR

- **ADR-276 (append-only amendment, in-scope task):** `## Amendment <date> (S4 go/no-go
  re-ruling, #9729)` + dated `### Stage status` line — the Decision-3(g) record this
  evidence step owes; non-activating (no flip, no lock removal, no ci.yml/ruleset edit).
- **ADR-262 (pointer edit, conditional):** on the #9323 PASS arm, remove/adjust the probe
  mention in its Consequences (:132) per the probe's RETIREMENT block.
- No new ADR: the plan executes decisions ADR-276 already made (re-ruling on completed
  index); a fresh GO/NO-GO verdict is recorded inside ADR-276, not as a new number.

### C4 views

No C4 impact. Enumeration checked against `model.c4`/`views.c4`/`spec.c4` (all three read):
(a) external human actors — none added (the watch, sweeper and replay are repo automation;
`founder`, `external-reader`, `untrusted-contributor` already model the human surfaces);
(b) external systems/vendors — none added (GitHub Actions/API is the existing CI surface
these scripts already run against); (c) containers/data-stores — none (receipts are
committed docs; no store); (d) actor↔surface access relationships — unchanged. The C4
validation tests are unaffected.

### Sequencing

The verdict amendment lands in this PR; if GO, activation remains a separate authorized
step (budget owner's go-ahead) sequenced after PR3b — recorded in the amendment, not
deferred to a silently-untracked issue.

## Guard Contract

### Guard 1 — measured-price drift arm (`PRICE_DRIFT_ROW` → `price-drift` finding)

**Property.** A committed `src=measured` suite price that diverges from its fresh
multi-run median beyond the flag bound (ratio ≥4× in either direction, |Δ| ≥120 000 ms,
timed ≥3 of the sampled runs) is surfaced as a `price-drift` finding on the shard-balance
watch's tracker — a wrong-but-present measured price is never invisible to the balance
math.

**Assembly.** One emission chokepoint — `drift_report_group()` in
`scripts/regenerate-shard-manifest.py`, through which every group's `--drift-report` output
flows (light, heavy, infra loop the same function). One flag/tracker chokepoint — the
findings loop in `scripts/watch-shard-balance-11564.sh` step (4) feeding the sentinel-hashed
tracker. The guard quantifies over every `src=measured` row of the committed
`suite-durations{,-heavy}.tsv` crossed with every label the sampled `suite-timings-*`
artifacts measure — membership is structural (the row src + the sample intersection), not
an enumerated list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture durations row `m/a 3000 measured`, synthetic fresh median 350000 ms | `PRICE_DRIFT_ROW` emitted; `price-drift` finding flagged — RED if absent |
| 2 | Suppress the emission arm (e.g., guard `src == "measured"` never taken / emission loop dropped) while fixture row 1 exceeds the bound — the guard's own dispatch | RED (suite asserts the row class exists for a qualifying input) |
| 3 | Two drifting measured labels in one group, both over bound | BOTH flagged — a break-after-first emission is the defect itself |
| 4 | Fixture row `m/b 100000 measured`, fresh 260000 ms (ratio 2.6, |Δ|=160000) | must-PASS: no `PRICE_DRIFT_ROW`, no finding — the audit's ordinary +12%…+190% drift band must not alert |
| 5 | Fixture row over bound but `timed=2/5` | must-PASS: under-sampled rows never flag (a two-run contention spike is not staleness) |
| 6 | Harness mutation: the watch's findings line drops the `price-drift` prefix from the sentinel-identity slice | RED (identity must exclude magnitudes but include the type+label) |
| 7 | Reverse direction: committed 400000, fresh 90000 (over-priced) | `price-drift` flagged — staleness is symmetric |

**Anchor.** The flag's inputs are (a) the committed durations table and (b) fresh medians
computed from downloaded CI artifacts. Weakening it in one diff requires editing both the
committed prices AND the artifact stream the median is computed from (outside the commit) —
a self-consistent lie needs two write sites, and the weekly cadence bounds a single-sided
one to the window until artifacts roll.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Refresh both rows" [issue #12016] | Phase 1 / `scripts/suite-durations.tsv` | mapped |
| 2 | "consider a price-vs-measure drift arm on the shard-balance watch" [issue #12016] | Phase 1 / `regenerate-shard-manifest.py` + `watch-shard-balance-11564.sh` + Guard Contract | mapped |
| 3 | "Re-measure after merge: runner-minutes per PR CI run, and `test-scripts` queue wait (targets: ≥20 runner-min saved; mean queue wait ≤10 min at similar load)" [issue #9323 Acceptance] | Phase 2 / local probe run + tracker comment | mapped |
| 4 | "PASS needs a mean saving of at least 20 runner-min over at least 20 qualifying PR runs after PR #9324 merged, and no escape on the merge-commit push runs" [issue #9323 Verification directive] | Phase 2 PASS arm (close + retire) | mapped |
| 5 | "ADR recording the PR-vs-main coverage split" / "Batteries declare subject paths; the PR CI run skips…" / "Main push and nightly runs execute every battery" [issue #9323 Acceptance] | — | descoped — already shipped by #9324, #11088, #11767 (verified in repo: `_diff_touches --pr-gated` call sites and ADR-262 committed) |
| 6 | "Evidence is a replay, not a live shadow: `--print-selection` over the last 300 first-parent commits against suite failures, replay escape rate under 2%" [issue #9729 Re-decide gate] | Phase 3 / replay + receipts | mapped |
| 7 | "verify each gate condition against the repo (ADR-270 status …, S2/S3 states …) and record the evidence" [parent brief] | Overview + Phase 3 + Research Insights premise section | mapped |
| 8 | "Extend ADR-262's call-site opt-in … to the affected set on `pull_request` only; `merge_group`, `push`, `workflow_dispatch`, `schedule` … keep the full battery" [issue #9729 Scope] | — | descoped — gated: activation requires the re-ruled verdict, the budget owner's explicit go-ahead, the admin-side control decision, and PR3b (#10859) all landing first; the ADR orders evidence before any stage-2 build |
| 9 | "`admin-merge-ready.sh` demands the full-battery marker … teaches `admin-merge-ready.sh` to read it through the runs API" [issue #9729 Scope entry gate 1] | — | descoped — stage-2 build owed only by a GO; the reduced-run read was never built (recorded in the 2026-11-05 oracle-lane amendment as pending S4 machinery) |
| 10 | "This stage's PR appends its ADR-276 amendment, pointer amendments to ADR-262 … and ADR-183, and `amends:` frontmatter" [issue #9729 Scope] | Phase 3 ADR-276 amendment (this PR's part); pointer amendments | partially mapped — ADR-276 amendment mapped; ADR-262/ADR-183 pointer amendments belong to the activating PR and are descoped with it |
| 11 | "All three ship in ONE PR (draft #12354). Plan them as one coherent change-set" [parent brief] | whole plan, single-PR split recommendation | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/suite-durations.tsv` two-row refresh | "Refresh both rows" | asked |
| `PRICE_DRIFT_ROW` emission + `price-drift` finding | "consider a price-vs-measure drift arm on the shard-balance watch" | asked |
| Watch/generator test-file edits | — | inferred — the drift arm is a guard; repo convention (`cq-write-failing-tests-before`) and the Guard Contract require coverage or the arm rots silently |
| `PBG_UNBOUNDED` seam + `.test.sh` rows | "Re-measure after merge" + the directive's PASS bar | inferred — the acceptance box cannot be checked while the probe starves inside a deadline sized for the sweeper, not for a full local sweep |
| Local verdict run + tracker comment + conditional close/retire | "no escape on the merge-commit push runs" + RETIREMENT block in the probe header | asked (retirement is the probe's own documented exit) |
| Replay collect/ejections/aggregate + receipts | "Evidence is a replay, not a live shadow" | asked |
| Criterion-(c) per-PR-run measurement + `receipts/` | "Minutes target: PR `CI` job-minutes per run down at least 20%" | asked |
| ADR-276 amendment + stage line + runbook §2 update + #9729 comment | "This stage's PR appends its ADR-276 amendment" + runbook §3 "the go/no-go is re-ruled" | asked |
| `decision-challenges.md` ruling rows | pipeline rule — technical rulings without spawn capability record `pending - assumed` | inferred — the ruling ledger is the prescribed channel for the drift bound, seam shape, criterion-(c) method, regen deferral and the re-ruling itself |

### Split Assessment

- Subsystems touched: 3 — `scripts/` (repo-root), `knowledge-base/`, `plugins/soleur/test/`
- Planned files: ~12 | Estimated changed lines: ~450 (incl. receipts/amendment text)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — three small, same-domain machinery residuals; the issues are
  all `domain/engineering` + `meta/machinery` under epic #11556's demand-reduction umbrella.

## Acceptance Criteria

### Functional Requirements

- [ ] FR-1: `scripts/suite-durations.tsv` carries `scripts/test-all-group-affected	349500	measured` and `.claude/hooks/git-commit-secret-scan.test.sh	297100	measured`; `git diff` on the file touches exactly those two rows.
- [ ] FR-2: `python3 scripts/regenerate-shard-manifest.py --drift-report` on a fixture set emits `PRICE_DRIFT_ROW` for a `src=measured` label where ratio ≥4× (either direction) AND |Δ| ≥120000 ms AND timed ≥3; emits nothing for under-bound or under-sampled rows (`scripts/regenerate-shard-manifest.py` `drift_report_group`).
- [ ] FR-3: `bash scripts/watch-shard-balance-11564.sh --print-report` (fixture seam `WATCH_DRIFT_GROUP`/`WATCH_DURATIONS`/`WATCH_MANIFEST`) lists a `price-drift` finding per `PRICE_DRIFT_ROW` and the sentinel identity excludes magnitude fields (`scripts/watch-shard-balance-11564.sh` step (4)).
- [ ] FR-4: `bash scripts/followthroughs/pr-battery-gate-saving-9323.sh` under `PBG_UNBOUNDED=1` never emits a wall-deadline `NOT YET`; under the sweeper contract (`PBG_BUDGET_S` unset/`<=300`) behaviour is byte-identical (probe `:88` seam + `.test.sh` rows).
- [ ] FR-5: the local verdict run's full output is posted as a comment on #9323; on PASS the issue is closed and the RETIREMENT block's six artifacts are removed (probe, `.test.sh`, `run_suite` line, legs row, durations row, ADR-262 mention); on FAIL/NOT YET the issue stays open with the numbers and a named follow-up.
- [ ] FR-6: `receipts/` under `knowledge-base/project/specs/feat-one-shot-ci-lever-residuals/` holds the replay summary, fresh audit output, criterion-(c) method+data, reader audit, and `go-no-go.md` ending in the `SOLEUR_PR_AFFECTED_VERDICT` machine line.
- [ ] FR-7: ADR-276 gains a dated `## Amendment` recording the re-ruled verdict and a dated `### Stage status` line; the amendment states non-activation explicitly.
- [ ] FR-8: #9729 receives a comment with the verdict, criteria table, and the named remaining blockers; `CI_PR_AFFECTED` is not set, the activation lock is untouched, and `ci.yml`/`required-checks.txt` are unmodified by this PR.

### Non-Functional Requirements

- [ ] NFR-1: replay evidence uses a fresh window (`--commits 300 --base origin/main` at run time) and the audit runs on a pinned `origin/main` detached worktree — never this branch's tree.
- [ ] NFR-2: no required context, merge authority, ruleset entry or repo variable changes.
- [ ] NFR-3: NFR register assessment — `knowledge-base/engineering/architecture/nfr-register.md` reviewed; this change is internal CI machinery with no product NFR surface beyond CI duration (the very thing it measures).

### Quality Gates

- [ ] `bash scripts/watch-shard-balance-11564.test.sh` green with the new `price-drift` rows.
- [ ] `bash plugins/soleur/test/regenerate-shard-manifest.test.sh` green with the new emission rows.
- [ ] `bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` green incl. seam rows.
- [ ] On the retire arm: `bash scripts/test-all.sh --enumerate` (or its registered-suite enumeration surface) shows no `pr-battery-gate-saving-9323` suite, and the legs/durations label sets stay equal.

## Test Scenarios

- Given a measured durations row priced 3.2 s whose sampled medians are 349.5 s, when
  `--drift-report` runs, then `PRICE_DRIFT_ROW` is emitted and the watch flags
  `price-drift` — unit.
- Given an over-priced measured row (committed 400 s, fresh 90 s), when `--drift-report`
  runs, then `PRICE_DRIFT_ROW` is emitted — unit.
- Given a measured row drifting 2.6× (under the 4× bound), when the report runs, then no
  drift row is emitted — unit.
- Given a drifting row timed in only 2 of 5 sampled runs, when the report runs, then no
  drift row is emitted — unit.
- Given two drifting measured labels in one group, when the report runs, then two drift
  rows are emitted — unit.
- Given `PBG_UNBOUNDED` unset and `PBG_BUDGET_S=301`, when the probe starts, then it exits
  3 `CANNOT ESTABLISH` — unit; with `PBG_UNBOUNDED=1` the budget validation is bypassed and
  rc-46 budget cuts cannot fire — unit.
- Given the local verdict output, when it is posted to #9323, then the comment carries the
  `qualifying_runs=…` / `realized_saving_min=…` lines verbatim — integration (operator-run,
  evidenced by the issue comment).
- Given the re-ruled criteria, when `verdict` computes, then the receipt's last non-blank
  line matches `SOLEUR_PR_AFFECTED_VERDICT verdict=<GO|NO-GO|UNDECIDED> ruled=… date=…` —
  unit/format assertion.
- Given the ADR-276 append, when the pre-activation gate reads the ADR, then the LAST
  `Go/no-go receipt:` line names this PR's receipt path — integration assertion via
  `scripts/ci-pr-affected-preactivation.sh --adr <file>` (seam exists for tests).

## Success Metrics

- #12016 closed; the next weekly watch run reports the arm operational (a `--print-report`
  fixture run in CI demonstrates it).
- #9323 closed (PASS arm) or carrying a posted measured verdict (FAIL/NOT-YET arm); the
  sweeper's daily `NOT YET` noise on that tracker ends either way the verdict resolves.
- #9729 carries a dated re-ruled verdict and the ADR stage log records it; the issue's
  remaining work is enumerated on it.

## Dependencies & Risks

- **Replay wall time:** ~2.5 h serial + ~25 min ejections — runbook §4; mitigated by
  Phase-0 background start and `--chunk` parallelism. Resumable; a session stall costs one
  re-invocation, not the window.
- **Criterion (c) may re-rule NO-GO:** the only prior per-run estimate (~11.6 net billed
  min) sits under the ~20 bar, and the advisory ratchet now costs ~3.4 billed min/run.
  A repeat NO-GO is a valid deliverable — the stage then needs the operator's
  retire-vs-schedule call, which the amendment + issue comment surface explicitly.
- **Audit staleness:** the fresh audit on `origin/main` may print `stale` accept rows or
  new gap pairs since the 2026-11-05 strict-zero snapshot; the drain-reveal rule (declare
  edge or accept row, re-run to fixpoint) applies inside this PR before the re-ruling.
- **Merge-order conflict on ADR-276:** open PR #12329 (`feat-one-shot-10859-pr3b-required-context`)
  also appends amendments + stage lines. Same-file appends at EOF will conflict; whoever
  merges second rebases and re-appends. Noted; the stage log is append-only so order is
  preserved by re-application, not by merge.
- **Sibling live processes:** collision precheck found running `test-all.sh` processes in
  `.worktrees/feat-one-shot-12320-stall-check-headcommit-oid` and
  `feat-one-shot-10859-pr3b-required-context` (reported; disjoint file sets — this PR does
  not touch `required-checks.txt` or the ratchet job).
- **Local probe run cost:** ~1 000 GitHub API reads + ~500 artifact downloads over up to
  ~6 days of runs; gh auth token has `repo`/`workflow` scope — sufficient for reads.
- **Follow-through directive:** #9323's `soleur:followthrough` directive lives in its body;
  closing the issue stops the sweeper (it sweeps open trackers only) — no directive edit
  needed.

## Research Insights

### Premise Validation (Phase 0.6)

- #12016 OPEN; stale rows verified in repo (`suite-durations.tsv:21` = 6 938,
  `:607` = 3 200); audit report committed at the cited path.
- #9323 OPEN; implementing PRs #9324 (merged 10-01), #11088 (10-25), #11767 (11-01),
  #11495 (10-30) all MERGED — `_diff_touches --pr-gated` call sites verified at
  `scripts/test-all.sh` (5 batteries + canary + extra relevance skips). Residual = the
  re-measure box only: probe exits 2 `NOT YET` on wall deadline 4 sweeps running.
- #9729 OPEN; issue-body gate **superseded**: ADR-270 frontmatter `status: accepted`
  (2026-10-09 amendment by operator direction); S2 #9512 CLOSED (exit-census marker still
  pending on tracker #9818 — soak criteria hold: 98/100 elided, mean 16.5 vs 29.08 bar);
  S3 #9728 OPEN (soak criteria hold, `S3-EXIT-CENSUS` pending); **the operator waived the
  S2/S3 census gate on 2026-10-12** (ADR-276 PR-A amendment, recorded verbatim). The
  operative gate chain is the ADR's: index strict-zero DONE (2026-11-05, PR5z via #12127,
  `gap_suites=0 unaudited=0 accepted=1548`), "replay and go/no-go re-ruling pending".
- Collision precheck (#10333): `prs=none` for all three issues; foreign live processes
  in two sibling worktrees — reported (feat-one-shot-12320, feat-one-shot-10859-pr3b).
- Mechanism-vs-ADR check (item 4): the drift arm rides the *existing* watch rather than
  adding a new cron — consistent with ADR-276's demand-first posture (no new runner cost:
  zero added jobs).

### Property List (Phase 0.6b)

1. The two prices reflect measured medians (balance math uncorrupted). → row refresh.
2. Future measured-price staleness is detected without a human re-audit. → drift arm.
3. #9323's re-measure evidence is produced and attached; the tracker stops emitting
   daily NOT YET. → local verdict run + close-or-record.
4. #9729's pending re-ruling is executed and recorded (replay + audit + criterion-c +
   verdict + ADR amendment), with activation structurally impossible in this PR.

### Cut List (Phase 0.6b)

- New watch/workflow file → covered by the existing weekly watch (same artifacts, same
  tracker): CUT.
- New soak probe for #9323 → the existing probe's verdict math is the authority; the seam
  unblocks it: CUT.
- S4 activation machinery (`[full]` run-name, `admin-merge-ready.sh` reduced-run read,
  lock removal) → buys no property this PR may deliver (operator authorization + PR3b
  outstanding): CUT / deferred to a GO's own PR.
- Marker-comment bypass convention → the local run is itself the evidence; the probe
  retires on PASS rather than learning a second pass condition: CUT.

### Files & Authorities

- `scripts/suite-durations.tsv` (:21, :607) — the two stale rows; label-sorted
  `label<TAB>ms<TAB>src`.
- `scripts/regenerate-shard-manifest.py` `drift_report_group` (:623) — emission contract
  (docstring :626-643); `read_durations_rows` src semantics (:432-445).
- `scripts/watch-shard-balance-11564.sh` (:1-60 header, :127 findings loop) — tracker +
  sentinel identity convention; fixture seams `WATCH_DRIFT_GROUP`/`WATCH_DURATIONS`/
  `WATCH_MANIFEST`; `FLOOR_DRIFT_BOUND_MS=300000`, `LEG_DRIFT_RATIO=1.30`.
- `scripts/followthroughs/pr-battery-gate-saving-9323.sh` (:88 budget seam, :230-278
  verdict math, :56-58 RETIREMENT block).
- `scripts/ci-pr-affected-replay.py` — subcommands: collect/ejections/aggregate/verdict/
  cp-upper/audit/ratchet/glob-rate; runbook `ci-pr-affected-activation.md` §3-5 is the
  re-attempt contract.
- `scripts/ci-pr-affected-preactivation.sh` — the seven-prerequisite read-only gate; reads
  the ADR's `Go/no-go receipt:` / `Skippable set:` / `Waiver:` lines (last wins).
- ADR-276 stage log + amendments (2026-10-16 NO-GO, 2026-10-22 ratchet, 2026-11-02/03
  ceilings, 2026-11-04 lever evaluation, 2026-11-05 strict zero + oracle lane,
  2026-11-06 umbrella consolidation).
- Learnings applied: `2026-11-07-a-required-shard-on-its-timeout-edge…` (timeout-edge =
  systemic, fix in own PR); `workflow-issues/2026-11-03-draft-prs-fail-the-test-aggregate…`
  (draft PR `test` is expected-red — this draft PR's own CI will run draft-light);
  `2026-09-19-a-generated-artifact-in-my-diff…` (generated TSVs are merge-conflict
  magnets — regen excluded by scope anyway).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change (`meta/machinery`
labels on all three issues). Mechanical UI-surface scan of Files to Edit/Create: zero
matches (`components/**`, `app/**/page.tsx`, `app/**/layout.tsx`, ui-surface-terms list) —
Product/UX gate does not fire. Spawn-dependent domain-leader consults were not available
in this harness (no subagent spawn); the semantic sweep is recorded directly.

## Open Code-Review Overlap

1 open code-review issue touches a planned file: **#7942** ("Two mutation batteries in
plugins/soleur/test/ are named *.mutation.sh and run in no gate") — mentions
`scripts/test-all.sh`. **Disposition: Acknowledge** — different concern (unregistered
`*.mutation.sh` batteries vs our conditional one-line `run_suite` removal on the #9323
retire arm); no fold-in, the issue remains open.

## Enhancement Summary (deepen-plan, 2026-11-07)

Deepen-plan ran on Devin CLI without subagent-spawn capability: the mechanical halt
gates executed and passed; the spawn-dependent phases (skill/learnings/research/review
agent fan-outs, spec-flow, advisor consult) were degraded to the inline research already
recorded in `## Research Insights` and are listed as degraded, not skipped-silently.

### Halt-gate results

- **4.6 User-Brand Impact:** PASS — section present, `threshold: none` with a decision
  line; sensitive-path regex verified zero matches against the file list (no scope-out
  bullet required).
- **4.7 Observability:** PASS — all five fields populated; `discoverability_test.command`
  first token `grep` is on the Check-10 allowlist, `expected_output` is the literal path
  string the command prints, no `ssh`, finishes in <1 s.
- **4.8 PAT-shaped variable:** PASS — zero matches; the plan's `GH_TOKEN` use is the
  probe's existing operator-local read contract, not an infra-time write credential.
- **4.9 UI wireframe:** does not fire — zero UI-surface files.
- **4.10 Encryption Posture:** does not fire — no new persistent store or cross-component
  connection.
- **4.11 Guard Contract:** PASS — `scripts/lint-guard-contract.py` scanned 1 plan, 1 guard
  entry, no FAIL; the Assembly names the two structural chokepoints
  (`drift_report_group()` emission, the watch findings loop), the matrix has 7 rows incl.
  own-dispatch, second-member, must-PASS (under-bound, under-sampled), harness and anchor
  rows; matrix authored before the guard.
- **4.12 Scope Check:** PASS — exactly one unfenced `## Scope Check`; every ask mapped or
  descoped-with-justification; every `inferred` item justified; no `status: BLOCKED`.
- **4.13 Task Design:** does not fire — no new autonomous-task surface (the watch and
  sweeper already exist; this PR deletes a suite registration, adds none).
- **4.5/4.5x network-outage & downtime gates:** not triggered — no SSH/network symptom
  patterns, no offline-inducing operation.

### Enrichments applied during the deepen pass

- Corrected the `PBG_UNBOUNDED` seam description: under `set -u` an unset `END` crashes
  `api()` — the seam sets `END=$((T0+86400))`, it never removes the bound.
- Confirmed `lane: cross-domain` (fail-closed; no spec.md `lane:` to carry forward) and
  `closes: [12016]` only — #9323 closes by verdict evidence in-work, never by autoclose.

### Degraded phases (recorded, not silently skipped)

- Phase 2/4/5 agent fan-outs (community-discovery, functional-overlap, per-section
  research, all review agents), spec-flow analyzer, and the scoped advisor consult could
  not spawn in this harness. The plan's design decisions rest on the inline evidence in
  `## Research Insights`; open technical rulings are parked in
  `specs/feat-one-shot-ci-lever-residuals/decision-challenges.md` as `pending - assumed`
  rows for a spawn-capable surface (or the operator) to confirm.

### New considerations discovered

- The post-refresh predicted leg totals (leg 6 → 29.9 min, max/mean 1.26) sit just under
  the watch's 1.30 flag — the first live datapoint the new drift arm may legitimately
  surface is leg-balance drift, not price staleness; that is the watch working as
  designed, not a false positive.
- Criterion (c) may still re-rule NO-GO even on a complete index (the prior rough per-run
  estimate ~11.6 net billed min is under the ~20 bar, and the advisory ratchet adds ~3.4
  billed min/run). The plan treats a repeated NO-GO as a valid, recorded outcome with the
  retire-vs-schedule call routed to the operator — not a failure of this PR.

## References & Research

### Internal References

- `knowledge-base/engineering/audits/2026-11-03-suite-time-top-15-report.md` (the two stale
  rows, findings 1–2).
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (re-attempt
  contract §3-7).
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` (manifest
  regen discipline; durations table contract).
- ADR-262, ADR-270 (`status: accepted`), ADR-276 (stage log + all amendments).
- PR C receipts: `knowledge-base/project/specs/archive/20261016-210509-feat-one-shot-9729-ci-pr-c-affected-only/receipts/`
  (verdict-line format, criterion figures).

### Related Work

- Issues: #12016, #9323, #9729, #9728 (S3, exit census pending), #9818 (S2 tracker),
  #10448 (index drain, closed), #10859/#10861/#10865 (PR3b/PR5z/window), #12156 (oracle
  lane, dark), #12030 (starvation eval), #11556 (epic), #9721 (parent plan), #7942.
- PRs: #9324, #11088, #11767, #11495, #9808, #12127 (PR5z merge), #12329 (PR3b in flight —
  ADR-276 append-order conflict risk), #12354 (this PR).
