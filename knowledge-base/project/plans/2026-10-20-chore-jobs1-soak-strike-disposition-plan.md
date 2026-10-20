---
title: "chore: disposition the two JOBS=1 soak strikes — bound git-data-wipe-assert and judge the rc=124 REDs (#7432, #10654)"
date: 2026-10-20
slug: chore-jobs1-soak-strike-disposition
branch: feat-one-shot-7432-jobs1-soak-strikes
issue: 7432
---

# chore: disposition the two JOBS=1 soak strikes (bound + judged-reproducing)

## Overview

The #7432 soak probe (`scripts/followthroughs/jobs1-stopgap-7432.sh`, window start
2026-10-19T18:00:00Z) exited 5 ACTION REQUIRED on 2026-10-20: monitor runs 39378082716 and
39446197504 each carried one non-allowlisted RED, `apps/web-platform/infra/git-data-wipe-assert.test.sh`
bound-killed at the 360 s default (`suite exceeded its 360s bound`, rc=124). The suite has no
`_SUITE_BOUNDS` entry; #10523 grew it ~1135 -> ~1380 assertions on 2026-10-20. This plan dispositions
the two strikes: add the measured `_SUITE_BOUNDS` entry (the H4 mechanism, #10654's CTO ruling) and —
pending the recorded technical ruling — move the two run ids into `JUDGED_REPRODUCING_RUNS`, because an
rc=124 bound overrun is a deterministic capacity defect, not the -P 4 flake the stopgap guarded against.
The grep -q linter re-evaluation runs and lands as a documented measurement comment on #7432 (the
mechanism still cannot fire; no linter is built). Issue #7432 stays open: the soak is mid-window
(4 of 12 counted runs; ~4/day, ~2 days remain).

## Research Reconciliation — Spec vs. Codebase

| Claim (source) | Reality (verified 2026-10-20) | Plan response |
|---|---|---|
| Probe exits 5 with 2 REDs outside allowlist: 39378082716 + 39446197504, both `git-data-wipe-assert.test.sh` rc=124 | CONFIRMED — re-ran the probe locally with `SOLEUR_FT_EARLIEST=2026-10-19T18:00:00Z`, exit 5, same two run ids; both logs carry `RED  apps/web-platform/infra/git-data-wipe-assert.test.sh` + `suite exceeded its 360s bound`; tallies 180/1/0 and 182/1/0, zero UNACCOUNTED | Phases 1-2 |
| Suite has no `_SUITE_BOUNDS` entry; runs at 360 s default | CONFIRMED — `run-registered-suites.sh` `_SUITE_BOUNDS` (lines ~630-691) has no `git-data-wipe-assert` row | Phase 1 |
| Infra-validation run 39370876316 (sha 1cb50078e0, same sha as strike run 39378082716) ran the suite in shard 3/4 and it PASSED | CONFIRMED via `gh run view`; no infra-validation run exists at strike-2 sha 8eed32df | Arm A fork evidence |
| rc=124 → H4 "CONFIRMED class, owned by _SUITE_BOUNDS" | CONFIRMED — ATTRIBUTION block `run-registered-suites.sh` lines 82-94: "rc=124 → H4; signal-shaped or UNACCOUNTED → H2; marker FAIL → real defect or H3" | Phase 1 |
| #10654 (OPEN) is a CTO ruling for exactly this bound fix | CONFIRMED — issue body: "measure the serial wall time once, then add `...=720` (or 2.5x) ... Small separate PR, or fold into the next PR that already touches the runner" | Phase 1 implements it |
| Serial wall ~2-4 min | MEASURED on this host: `time bash apps/web-platform/infra/git-data-wipe-assert.test.sh` → `real 2m41.8s` (162 s), 1379/0 pass, loopback tier skipped (needs root). Caveat: dev host is faster than the 4-core CI runner | Phase 1 cites the measurement |
| Soak mid-window: 4 counted + 1 in flight, needs 12 | CONFIRMED — `gh run list --workflow main-health-monitor.yml --branch main --created ">=2026-10-19T18:00:00Z"`: 39298929992, 39345015242 (clean), 39378082716, 39446197504 (struck), 39470997821 in_progress | Post-merge AC |
| Tests-step `JOBS: 1` stays by design | CONFIRMED — `main-health-monitor.yml:365` is the only `JOBS` assignment; guard (12a) pins it, (12b) asserts none elsewhere | never touched |
| Merge-group watch: new run-registered-suites REDs | Checked — only nearby failure is IV run 39476589695 `plan (apps/cla-evidence/infra)` job, unrelated to the runner | nothing to attribute |

## Research Insights

**Premise Validation (Phase 0.6):** #7432 OPEN (labels include `follow-through`, `needs-attention`); #10654 OPEN; PR #10459 MERGED 2026-10-19T12:25Z (infra pin removal); cbe4e051 (the -P4 flake fix, #10658) is an ancestor of this branch. Cited files all exist on the branch. #7376 remains OPEN (mitigated not fixed). No stale premise found.

**Property List (Phase 0.6b):** (1) the two strikes stop counting against the soak once correctly classified; (2) the suite stops dying at a bound smaller than its real cost; (3) every probe claim remains machine-verifiable (the judged-id mechanism already exists and is suite-covered); (4) the issue gets a current, honest status comment. **Cut List:** the grep-q linter (issue item 2) — re-evaluated below; the trigger conditions still do not hold, so it produces a measurement comment, not code. No revert-trigger helper machinery — the existing `JUDGED_REPRODUCING_RUNS` list is the sanctioned vehicle.

**grep -q linter re-evaluation (issue #7432 item 2, re-run 2026-10-20):** trigger 1 — any `| grep -q` site whose producer streams a >64 KiB file. Census: ~1267 `| grep -q` sites in `*.sh`. Cross-referenced producers against the 558 tracked text files >64 KiB: **zero live sites** stream one. `ci-deploy.sh`/`workspaces-cutover.sh`/`server.tf` are only ever *file operands* of `grep -q P FILE` (no pipe) or are discussed in comments documenting the deliberate avoidance. One latent site: `plugins/soleur/skills/ship/SKILL.md:161` `git show "HEAD:$f" | grep -q "code-review"` iterates `todos/` files (all ~1 KB today) — latent-capable, inert now. Trigger 2 — a captured `PIPESTATUS[0]==141` failure: none in the soak-window CI history; the two REDs are rc=124, and `test-all.sh:1834-1840` reads PIPESTATUS correctly through tee. **Verdict: mechanism still unreachable — no linter; comment on #7432 carries this measurement.** CTO ruling 2026-10-20 sharpens it to SUPERSEDED: the contemplated linter already exists as `.claude/hooks/grep-q-pipe-guard.test.sh`'s `scan_sweep` derived sweep (zero `producer | grep -q` shapes outside an 11-row SWEEP_DEFERRALS table), and the 64 KiB premise was a refuted bound — the comment proposes closing item 2 on that basis.

**Learning reconciliation (deepen pass):** `2026-10-18-the-fix-for-the-gated-thing...` says bounds ship in a separate PR that merges first — because a branch diff touching `apps/web-platform/infra/` arms the nested infra runner and a *dispatch from that branch* would no longer measure the cold shape. That precedent does not bind here: this PR **is** the bound fix; nothing is validated by dispatching the monitor from this branch — the soak counts post-merge runs on `main`, where the new bound is the production shape being measured. `2026-10-19-a-soak-probe-owns-the-verdict...` binds positively: the judged-runs edit keeps the gate's controls (run-granular whole-token match, PASS line still names judged runs, suite re-anchors the committed literal).

**Relevant learnings:** `2026-08-09-the-monitor-reported-success...` (read the runner's verdict fields, not conclusion); `2026-07-28-a-ten-run-sample...` (sample-size bounds); the parent Item-I plan's own `## Measurement`/`## Decision` sections.

## Implementation Phases

### Phase 0 — ruling check

Read `knowledge-base/project/specs/feat-one-shot-7432-jobs1-soak-strikes/decision-challenges.md` row for the strike fork. If a CTO ruling landed (Arm B: letter-stands), take `## Phase 5b` instead and skip Phases 1-2's probe edits (Phase 1's bound entry still applies — the H4 defect is real either way).

### Phase 1 — `_SUITE_BOUNDS` entry (either arm)

In `apps/web-platform/infra/run-registered-suites.sh`, add
`"apps/web-platform/infra/git-data-wipe-assert.test.sh=720"` with a comment citing: #10654's CTO ruling, #10523's growth (~1135→~1380 assertions), the two bound-kills at 363 s in monitor runs 39378082716/39446197504, and the measured 162 s serial on the dev host (with the faster-than-CI caveat; 720 s ≈ 4.4× local serial, matching the 2.5-3× contention-plus-headroom precedent of the sibling entries). Place it after the `run-registered-suites.test.sh` entry, keeping the list's existing comment style.

### Phase 2 — Arm A: judge the strikes (only if the fork rules reproducing-in-intent)

In `scripts/followthroughs/jobs1-stopgap-7432.sh`, set
`JUDGED_REPRODUCING_RUNS="39378082716 39446197504"` and extend its comment block by one line: these ids are judged-reproducing because the REDs are rc=124 bound-kills (H4, a deterministic capacity defect under the monitor's unsharded 181/183-suite `-P 4` pool — a real defect the bound fix addresses, not the `-P 4` flake the stopgap guarded), cited to the ATTRIBUTION block and #10654.

**Same-diff test maintenance (load-bearing):** `scripts/followthroughs/jobs1-stopgap-7432.test.sh` mutates the literal `JUDGED_REPRODUCING_RUNS=""` at the rows R4b3 (line ~261), R4q (~290), K12 (~423) and K22 (~445). `mutate()` asserts `s.count(old) == 1`, so these needles must be re-anchored in the same commit — e.g. mutate `JUDGED_REPRODUCING_RUNS="39378082716 39446197504"` → `JUDGED_REPRODUCING_RUNS="90030 90031"` (and the K-rows' second mutation retains the same base text). Without this the suite goes RED on "the mutation did not land exactly once". Re-run the suite and confirm green.

### Phase 3 — issue comment on #7432

Post (via `gh issue comment 7432`): soak status 4/12 counted runs (2 clean, 2 struck — disposition recorded here), 1 in flight, ~2 days at ~4/day to reach 12; the strike disposition (bound fix + judged-reproducing, or the revert if Arm B fired); and the grep -q re-evaluation — per the CTO ruling it is SUPERSEDED, not merely deferred: the contemplated linter already exists as `.claude/hooks/grep-q-pipe-guard.test.sh`'s `scan_sweep` derived sweep (zero `producer \| grep -q` shapes asserted outside an 11-row SWEEP_DEFERRALS table), and the 64 KiB premise was itself a refuted bound (the guard header documents the race firing on a 3-line producer); the comment proposes closing item 2 on that basis, and still carries the re-measurement figures for the record.

### Phase 4 — ship

PR body: `Ref #7432` and `Closes #10654` (the ruling sanctions folding into a runner-touching PR), the measurement, the strike dispositions, and the pending/landed ruling line. `soleur:ship`, then `soleur:postmerge`. Do not emit DONE.

### Phase 5b — Arm B (only if the fork rules letter-stands non-reproducing)

Restore the infra-step `JOBS` pin in `.github/workflows/main-health-monitor.yml` AND flip guard (12b) in `plugins/soleur/test/main-health-monitor-workflow.test.sh` to assert the pin's presence again (the guard's own comment documents this exact procedure — "Restoring the infra pin therefore means editing (12b) in the same diff"). Phase 1's bound entry still ships. The #7432 comment then records: revert fired per the probe's letter; Item I does not hold; note on #9217.

## Files to Edit

- `apps/web-platform/infra/run-registered-suites.sh` — one `_SUITE_BOUNDS` entry + comment (Phase 1).
- `scripts/followthroughs/jobs1-stopgap-7432.sh` — `JUDGED_REPRODUCING_RUNS` value + comment (Phase 2, Arm A only).
- `scripts/followthroughs/jobs1-stopgap-7432.test.sh` — re-anchor the four `mutate` needles (Phase 2, Arm A only).
- `.github/workflows/main-health-monitor.yml` + `plugins/soleur/test/main-health-monitor-workflow.test.sh` — Phase 5b only (Arm B).

All paths verified with `git ls-files` on this branch.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-7432-jobs1-soak-strikes/decision-challenges.md`, `evidence.md`, `tasks.md` (plan artifacts).

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` (96 issues) against every planned path: **None** name them. (#10654 is a `chore` CTO ruling, not a `code-review` scope-out; it is folded in, not overlapped.)

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the monitor is an internal backstop. Wrong arm A: the probe silently stops counting real bound-kills as strikes (a too-generous allowlist); mitigated because the bound-kill still renders `RED <path>` in every run log and the monitor still files `ci/main-broken`. Wrong arm B (an unnecessary revert): the infra step returns to ~30% ceiling-kill rate with no verdict — the worse state, which is why the fork was ruled, not guessed.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no vector; a CI bound entry and a run-id allowlist touch no credential, data store or user-facing path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none`, not `aggregate pattern` — worst case is internal alert quality, bounded by the revert trigger and the probe's own exit codes.

threshold: none, reason: the touched sensitive path (`apps/web-platform/infra/run-registered-suites.sh`) receives a data-only bound entry; no credential, user data or request path is involved.

## Observability

```yaml
liveness_signal:
  what: the SOLEUR_MAIN_HEALTH notice annotation (tests=, infra=, infra_elapsed_s=) per monitor run, plus the soak probe's daily sweep verdict
  cadence: monitor every ~6h (Inngest dispatch); probe daily via scheduled-followthrough-sweeper.yml
  alert_target: the ci/main-broken tracker and #7432 sweeper comments
  configured_in: .github/workflows/main-health-monitor.yml; scripts/followthroughs/jobs1-stopgap-7432.sh
error_reporting:
  destination: GitHub issue labelled ci/main-broken (monitor filer); #7432 comment (sweeper)
  fail_loud: probe exit 5 prints the run ids and suite names; exit 1 names killed runs
failure_modes:
  - mode: another suite exceeds its bound under -P 4 contention
    detection: `RED  <path>` line + `suite exceeded its Ns bound` error annotation; probe exits 5 naming run and suite
    alert_route: ci/main-broken P1 comment
  - mode: the bound fix is insufficient and git-data-wipe-assert strikes again
    detection: same rc=124 signature in a later counted run; probe exits 5 again (nstrikes re-accumulate)
    alert_route: #7432 sweeper comment + ci/main-broken
  - mode: a child suite is OOM-killed (no .meta)
    detection: UNACCOUNTED line in the runner tally; probe hard-fails the run
    alert_route: ci/main-broken tracker
logs:
  where: health-check job log + check-run annotations of each monitor run
  retention: 90 days
discoverability_test:
  command: grep -c git-data-wipe-assert apps/web-platform/infra/run-registered-suites.sh
  expected_output: 1
```

## Guard Contract

### Guard 1 — the probe's judged-reproducing disposition (Arm A)

**Property.** A counted run whose only non-allowlisted REDs are in `JUDGED_REPRODUCING_RUNS` is not a strike; the list is run-id-granular (whole-token match) and only ever shrinks the strike count — it can never turn a RED into clean silently (the PASS line still names judged runs) nor judge a run whose RED set it doesn't cover.

**Assembly.** The chokepoint is `classify()`'s strike arm: `case " $JUDGED_REPRODUCING_RUNS " in *" $rid "*)` in `scripts/followthroughs/jobs1-stopgap-7432.sh` — every non-allowlisted RED run flows through it. The committed list is one literal the test mutates; assembly is that single assignment plus the single match site, not an enumeration of run ids.

**Mutation matrix** (existing suite rows already cover the mechanism; the four needles get re-anchored to the new literal):

| # | Mutation | Expected |
|---|---|---|
| 1 | judged list names both struck runs (R4b3 shape) | exit 0, PASS line names them as judged |
| 2 | judged id that merely CONTAINS a run id — `900301` vs run `90030` (R4q) | exit 5 — no judging |
| 3 | a second non-allowlisted RED run NOT in the list after a judged first (R4b2 shape) | exit 5 — judging is per-run, not per-suite |
| 4 | own dispatch: judged-arm code removed (`*" zz "*` mutant, K12) | exit 5 — list never consulted |

**Anchor.** The list is a committed value the PR diff shows; the suite's cross-check row re-reads the real probe text. A revert of the disposition is one line — and the probe re-counts the strikes on next sweep.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "remove the JOBS=1 stopgap from the main-health monitor now that the -P4 flake fix has landed" [#7432 / brief] | soak completes through the probe; this PR dispositions the 2 strikes | mapped |
| 2 | "read scripts/followthroughs/jobs1-stopgap-7432.sh ... and the soak runs before touching any pin" [brief] | Research Reconciliation; Phase 0 | mapped |
| 3 | "run the grep -q linter follow-up named in the issue body" [brief] | Research Insights re-evaluation; Phase 3 comment | mapped |
| 4 | "attribute exit-code-first per the ATTRIBUTION block" [brief] | Phase 1 bound entry (rc=124 → H4 → _SUITE_BOUNDS); checked IV failure — unrelated job | mapped |
| 5 | "the CTOrules them reproducing → JUDGED_REPRODUCING_RUNS update ... non-reproducing → restore the infra pin AND flip guard (12b) AND still carries the _SUITE_BOUNDS entry" [brief fork] | Phase 2 / Phase 5b two-arm design | mapped |
| 6 | "do NOT absorb" adjacent arc work [brief] | Non-Goals | mapped |
| 7 | "Do NOT remove the tests-step JOBS pin — it stays by design" [brief] | never touched; guard (12a) continues to pin it | mapped |
| 8 | "Persist every decision as a row of the `| Item | Class | Ruling |` table" [brief] | decision-challenges.md | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|---|---|---|
| `_SUITE_BOUNDS` entry | "attribute exit-code-first ... rc=124 → _SUITE_BOUNDS H4"; #10654 action text | asked |
| `JUDGED_REPRODUCING_RUNS` update | "the two rc=124 H4 REDs satisfy 'reproduces' ... → JUDGED_REPRODUCING_RUNS by PR" | asked (conditional on ruling) |
| test-file needle re-anchoring | — | inferred — justification: `mutate()` asserts the old literal lands exactly once; the suite goes RED otherwise (safety dependency) |
| #7432 status comment | "an issue comment on #7432 documenting soak status ... and the grep -q re-evaluation result" | asked |
| pin restore + guard 12b flip | "If the CTO rules the strikes non-reproducing, the PR instead restores the infra pin AND flips guard (12b)" | asked (conditional, Arm B) |

### Split Assessment

- Subsystems touched: 3 (apps, scripts, knowledge-base)
- Planned files: 5 max (3 Arm A + 2 Arm B-exclusive) | Estimated changed lines: ~80
- Thresholds: >= 4 subsystem roots OR > 25 files OR > 800 lines — none met
- Recommendation: single PR

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed (pending CTO seat)
**Assessment:** Internal CI tooling only — no product, marketing, legal, finance, sales, support or operations surface. The one technical fork (do the two rc=124 REDs satisfy the probe's "reproduces" intent) is recorded in `decision-challenges.md` for the CTO seat per the pipeline's technical-ruling delegation. Prior CTO rulings in this arc (Option D pin removal, the #10654 bound action) bound the design space; this plan implements within them.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `run-registered-suites.sh` `_SUITE_BOUNDS` carries exactly one `git-data-wipe-assert.test.sh` entry, value `720`, with a comment citing the 162 s serial measurement and the two bound-kill run ids (Phase 1; both arms).
- [ ] Arm A only: `JUDGED_REPRODUCING_RUNS` names `39378082716` and `39446197504`, and `bash scripts/followthroughs/jobs1-stopgap-7432.test.sh` is green — including rows R4b3/R4q/K12/K22 re-anchored against the new literal (mutation needles must land exactly once).
- [ ] Arm A only: re-running the probe with `SOLEUR_FT_EARLIEST=2026-10-19T18:00:00Z` and live `GH_TOKEN` exits 2 NOT YET (strikes judged; <12 runs), never 5 — unless a new counted run struck since authoring, which is recorded, not masked.
- [ ] Arm B only: `grep -cE '^\s+JOBS' .github/workflows/main-health-monitor.yml` returns 2 and `bash plugins/soleur/test/main-health-monitor-workflow.test.sh` is green with (12b) flipped.
- [ ] `git diff origin/main...HEAD --stat` touches only the Files-to-Edit/Create set; the tests-step `JOBS: 1` line at `main-health-monitor.yml:365` is unchanged in Arm A.
- [ ] `python3 scripts/lint-guard-contract.py <this plan>` passes; `npx markdownlint-cli2` clean on plan + tasks.
- [ ] PR body: `Ref #7432`, `Closes #10654`, the measurement, strike dispositions and ruling lines; no literal `JOBS: 1` token outside need.
- [ ] #7432 has the status comment (soak 4/12, dispositions, grep -q re-eval measurement) — posted pre-merge since it documents a live sweeper state.

### Post-merge (operator-free)

- [ ] Next sweep of `jobs1-stopgap-7432.sh` on #7432 posts NOT YET (exit 2) with a rising counted-runs figure — or FAIL/ACTION REQUIRED naming a NEW run id (a fresh strike is data, not a revert of this PR).
- [ ] `soleur:postmerge` ran for the PR; #9217 gets a one-line note only if Arm B fired (Item I reverted).

## Test Scenarios

- Given the probe and a stub run set with two judged runs, when `JUDGED_REPRODUCING_RUNS` names them, then exit 0 names them in the PASS line (unit — suite row R4b3).
- Given a run id in the list that is a superstring of a struck run's id, when the probe runs, then nothing is judged (unit — R4q).
- Given the bound entry, when the runner dispatches the suite, then `timeout` gets 720 not 360 (integration — exercised by the next monitor/IV run; the plan asserts it via the comment + entry shape, not a new CI consumer).
- Regression: the Aug-2026 silent `-P 4` regression class — covered by guards (12a)/(12b), untouched in Arm A.

## Dependencies & Risks

- **Fork dependence:** Arm A vs Arm B is decided by the decision-challenges ruling. Both arms ship Phase 1. The work phase reads the ruling first; a `pending` ruling at work time means spawn `soleur:engineering:cto` with the packaged evidence before touching the probe.
- **Risk: a third strike before merge** — the probe re-check at AC time catches it; a NEW non-allowlisted RED is a new datum for the CTO, not something this PR masks.
- **Risk: bound too tight.** 720 s is ~2× the observed kill point (363 s) and ~4.4× measured local serial; the ATTRIBUTION rule (≥1.5× worst observed) and #10654's ruling support it. A real bound hit still renders as a named RED, not a step kill.
- **suite-durations.tsv note:** the `git-data-wipe-assert` row is `1000 floor` (unmeasured at generation time); `regenerate-shard-manifest.py` re-derives floor rows from real runs, so it self-corrects — noted, not edited.

## Non-Goals

- The adjacent arc items named in the brief: test-all orphan-log-retention, suite `.meta` rc forge/erase, test-gate second-stage narrowing, runner derivation residuals, parallelism/CI-time follow-ups — separate issues/PRs, not absorbed here.
- Removing or loosening the tests-step `JOBS` pin; editing the monitor's issue-filing logic or ceilings; closing #7376 (mitigated, not fixed).
- Building the `grep -q` linter — re-evaluation says the mechanism is still unreachable (see Research Insights).

## Rollback

`git revert` of the merge commit restores the empty `JUDGED_REPRODUCING_RUNS` and the missing bound entry; the probe then re-exits 5 on the same two runs (data preserved — run ids are re-derivable from the sweep comments). An Arm-B tree additionally reverts the pin restore. Either way #7432 stays open and the sweeper keeps reporting state truthfully.

## Sharp Edges

- The four `mutate` needles in the probe's test pin the literal `JUDGED_REPRODUCING_RUNS=""`; the suite fails loudly ("mutation did not land exactly once") if the probe's value changes without re-anchoring them — same commit, always.
- The probe's run-id match is space-fenced (`*" $rid "*`); a pasted id with a stray character silently judges nothing — keep the list to bare decimal ids separated by single spaces.
- `elapsed=363s` in the brief is consistent with the bound (360) plus timeout granularity; cite the bound value, not the elapsed figure, in the bound comment.
- The discoverability probe uses `grep -c` on a file path with no pipe, no shell metacharacters — survives Check 10's sandbox.
