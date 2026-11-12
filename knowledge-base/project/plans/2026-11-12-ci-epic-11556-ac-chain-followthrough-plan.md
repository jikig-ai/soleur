---
title: "ci: epic #11556 remaining AC chain — scheduled-run confirmation, applicability-classifier follow-up, Lever-A re-rank, p90 re-measurement"
type: chore
date: 2026-11-12
slug: ci-epic-11556-ac-chain-followthrough
branch: feat-one-shot-11556-epic-ac-chain
issue: 11556
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# ci: epic #11556 remaining AC chain — scheduled-run confirmation, applicability-classifier follow-up, Lever-A re-rank, p90 re-measurement

## Overview

Continuation of epic #11556 (cut PR required-check time to 20 min or less). The previous slice (merged squash `34634d7431`, PR #12654, closed #12626, merged 2026-11-12T19:46:34Z) moved three web-platform mutation batteries onto a dedicated `test-webplat-mutations` 3-leg matrix job in `ci.yml` and `main-health-monitor.yml`, added a `VITEST_SHARD`-set `skip_suite` decline in `scripts/test-all.sh`, and un-censored the ~25-minute `mut-approval-guard1` leg. This plan closes the remaining acceptance chain: confirm the fix holds on the scheduled `soleur-ai[bot]`-dispatched main-health-monitor cadence (not just the manual post-merge dispatch), file the deferred applicability-classifier follow-up issue for the new job, re-derive the Lever-A shard outlier ranking on fresh merge_group artifacts, and re-measure the epic's required-check p90 targets now that the mutation batteries no longer ride the webplat legs.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch; the user brief is the spec of record.

## Problem Statement / Motivation

Five open threads of the epic's acceptance chain remain after #12654 merged:

1. **Scheduled-run proof is still empty.** Every post-merge green datapoint so far is the manual dispatch `43295978800` (actor `deruelle`, 2026-11-12T20:00:46Z, 18/18 legs green, `approval-guard1-mutation` 1493 s). The Inngest `cron-main-health-monitor` (`apps/web-platform/server/inngest/functions/cron-main-health-monitor.ts`, `cron: 0 */6 * * *` → 00/06/12/18Z, dispatches `workflow_dispatch` as `soleur-ai[bot]`) has not yet produced a post-merge run — the next slot is 2026-11-13T00:00Z. The 18:00:38Z run `43275349911` failed on **pre-merge** code (merged 19:46Z), so it is not a regression signal. Trackers #12455 and #12618 are CLOSED.
2. **The named follow-up was never filed.** The previous slice's session-state explicitly deferred "applicability classifier for `test-webplat-mutations`" (a `ci-shard-totality-classify.sh` analog, #9729 class) — the job pays ~3×25–30 leg-min on KB-only PRs whose diffs cannot move the batteries. `gh issue list` shows no open issue covering it.
3. **Shard prices are stale.** `scripts/suite-durations.tsv:429` prices `scripts/followthroughs/ci-push-dedupe-soak-9512` at `185400` ms but a real merge-group run measured `80676` ms; leg balance measured on post-merge run `43286327218` shows `test-scripts` legs spanning 423 s–2483 s. The committed manifests were last priced before the atomic-suite splits bedded in.
4. **The epic's p90 targets are unmeasured post-slice.** The 2026-11-06 watch report (tracker #12089, now CLOSED; next weekly run Fri 2026-11-14 09:07Z re-files it) recorded `test` p90 = 3624 s (PR) / 3205 s (MQ) against goals 1200 s / 900 s. Post-merge run `43286327218` shows the new `test` critical path is `test-scripts (6/8)` at 2483 s ≈ 41.4 min — the batteries are off the webplat legs as designed, but the binding constraint has moved to `test-scripts` leg skew. `test-webplat-mutations (approval-guard1)` measured 1158 s on that run — under both the epic 20-min goal and Lever F's ~30-min internal gate.
5. **Adjacent trackers must not be disturbed.** #12269 (Lever-E `max_entries_to_build` experiment) carries its probe directive (`earliest=2026-11-30T23:01:58Z`, `mq-lever-e-verdict-12269.sh`) in a 2026-11-09 comment — leave soaking. #12647 (`/tmp` tmpfs leak) and #12651 (Fable 5.2 launch-review flake) are OPEN and tracked separately.

## Proposed Solution

A measurement-and-enrollment slice, not a workflow change:

- **Phase 1 — scheduled-run probe + tracker.** New `scripts/followthroughs/main-health-monitor-mutations-12626.sh` verifies post-merge *scheduled* (`actor.login == soleur-ai[bot]`, `head_branch == main`, `created_at >= 2026-11-12T19:46:34Z`) `main-health-monitor.yml` runs: PASS once ≥2 completed scheduled runs are all `conclusion=success` with all three `test-webplat-mutations (*)` jobs green; FAIL on any non-success scheduled run or missing/red mut leg; NOT YET (exit 2) while fewer than 2 qualifying runs exist; CANNOT ESTABLISH (exit 3) on `gh` failure. Committed with its `.test.sh` suite + `run_suite` registration + shard-manifest rows. A new `follow-through`-labeled tracker issue carries the unfenced column-0 directive (`secrets=GH_TOKEN`; `earliest=` = filing timestamp — the script self-gates).
- **Phase 2 — file the classifier follow-up.** One issue covering both cost levers the previous slice deferred to "the named follow-up": (a) an in-job applicability classifier for `test-webplat-mutations` copied from the `shard-totality-mutations` detect-step shape (`ci.yml:2137`), base-sourced, fail-closed; (b) the `--rows` row-split of `approval-guard1-mutation` (per the archived CTO ruling `decision-challenges.md` row 2). Issue body is a committed artifact under `specs/<branch>/`.
- **Phase 3 — Lever-A re-rank + re-price.** Download `suite-timings-scripts-*` (and `-heavy-*`) artifacts from the most recent green `merge_group` `ci.yml` runs (the runbook's canonical source — `push` runs elide the shards job via push-dedupe), run `regenerate-shard-manifest.py --timings-dir … --drift-report`, then `--write` to re-price committed manifests where drift warrants. Reconcile the `185400` ms soak-suite row against artifact-measured values. Emit the fresh top-15 suite-time ranking into `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` "Measured history".
- **Phase 4 — p90 + Lever-F measurement.** `bash scripts/watch-wallclock-p90-11774.sh --dry-run` for the instrument-of-record p90 on both surfaces; record vs goals (1200 s / 900 s) and Lever F's ~30-min gate; comment the verdict on #11556 and note #11563's status. The 14-consecutive-days epic AC is noted as still-gated (one measurement cannot satisfy it).
- **Phase 5 — tracker hygiene + close-out.** Verify #12647, #12651 remain open and undisturbed; #12269's directive untouched; commit all artifacts.

## Technical Considerations

- **Probe dispatch discrimination.** `workflow_dispatch` events from the Inngest cron carry `actor.login == soleur-ai[bot]` (verified on runs `43275349911`, `43270980378`, `43073594297`); manual dispatches carry the human login (`deruelle` on `43295978800`). Actor is the discriminator — `created_at` cadence-matching alone would misclassify a manual dispatch at a cadence hour.
- **`cancelled` scheduled runs** are excluded from the sample (neither PASS nor FAIL evidence — the monitor's own missed-check-in watchdog owns "run never happened").
- **The probe asserts the mut legs itself** rather than trusting the run-level `EXPECTED_LEGS` census — belt over the leg-silently-dropped shape, at the cost of one `jobs` read per sampled run (bounded: `per_page` + the latest 2 runs only).
- **No job-level `if:`/`needs:` change anywhere.** `scripts/ci-push-dedupe.test.sh` (`GATED_PINNED`, `DL_GATED_PINNED`, `OR_GATED_PINNED`, `SEVEN_LEGS`) and `scripts/ci-draft-light.test.sh` pin those lines verbatim including `test-webplat-mutations` — the follow-up issue must prescribe the same in-job detect-step shape shard-totality uses (`ci.yml:2137–2162`).
- **`test` aggregator needs no change** for an in-job skip: the job still checks out, reports `success` with the battery step skipped, and posts the skip notice — identical to the existing shard-totality arm (`ci.yml:2164–2168`).
- **NFR:** performance (the whole epic) — measured, not asserted; observability — the probe IS the observability deliverable; reliability — every unknown arm runs the battery (fail-closed).
- No new persistent store, connection, secret, host, workflow file, Inngest function, CHECK_REGISTRY arm, or daemon → Task Design, Encryption Posture, and IaC gates do not fire. No architectural decision a future engineer would be surprised to find undocumented → no ADR/C4.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the worst case is internal: a tracker that false-closes while scheduled monitor runs are red (an issue the probe's own suite must pin), stale shard prices that keep `test` legs skewed, or a misfiled follow-up.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data surface — the probe reads public-to-the-repo GitHub Actions metadata with an `issues:write`-scoped `GITHUB_TOKEN`; the classifier issue is design prose.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** all touchpoints are internal CI measurement/enrollment machinery; a wrong verdict degrades internal signal (a tracker closed early, a leg priced wrong), never user-visible behavior.

*Scope-out:* `threshold: none, reason: the touched paths (scripts/followthroughs probe, suite manifests, runbook, spec artifacts) are internal CI machinery with no user-facing or regulated-data surface`

## Observability

```yaml
liveness_signal:
  what: the follow-through probe's per-sweep verdict comment on its tracker (PASS/FAIL/NOT YET/CANNOT ESTABLISH) — the enrolled confirmation that scheduled monitor runs stayed green
  cadence: every scheduled-followthrough-sweeper sweep until the tracker closes
  alert_target: tracker issue comment thread (sweeper posts every non-0/1 verdict)
  configured_in: scripts/followthroughs/main-health-monitor-mutations-12626.sh + the tracker's soleur:followthrough directive; the sweeper is .github/workflows/scheduled-followthrough-sweeper.yml (existing, unchanged — GH_TOKEN already bound at env:120)
error_reporting:
  destination: tracker issue comments (probe stdout tail, last 4 KB per sweep)
  fail_loud: a red scheduled run produces exit 1 → a FAIL comment naming the failing run id and the red/missing leg, left open for the sweeper to repost until resolved
failure_modes:
  - mode: probe exits 1 (regression found — a scheduled run red or a mut leg absent)
    detection: sweeper posts FAIL comment with the probe's evidence line
    alert_route: tracker thread; the monitor's own ci/main-broken issue family is the upstream alarm
  - mode: probe stuck at 2/3 every sweep (API failure, no qualifying runs)
    detection: repeated CANNOT ESTABLISH/NOT YET comments on the tracker
    alert_route: tracker thread accumulation is the visible signal (convention §exit contract)
  - mode: probe file unregistered from test-all.sh (silent drop)
    detection: lint-orphan-test-suites.sh census reds CI — run_suite row is required
    alert_route: blocking `test` required check on the offending PR
logs:
  where: probe stdout → sweeper comment tail; locally `bash scripts/followthroughs/main-health-monitor-mutations-12626.sh` prints its evidence line
  retention: tracker comments persist for the issue's life; sweep logs ~90 days on the workflow
discoverability_test:
  command: grep -c 'scripts/followthroughs/main-health-monitor-mutations-12626' scripts/test-all.sh
  expected_output: "1"
```

## Research Insights

### Relevant files (verified this session)

- `.github/workflows/ci.yml:1664` — `test-webplat-mutations` job (3-battery matrix, job-level-only timeout, oracle-skip arm already present); `:2137–2175` — the shard-totality in-job classifier arm being copied; `:2446–2456` — `test` aggregator `entries=` + oracle-skip regex already includes `test-webplat-mutations`.
- `.github/workflows/main-health-monitor.yml` — 18-leg `EXPECTED_LEGS` census incl. the three mut legs (prior slice verified).
- `apps/web-platform/server/inngest/functions/cron-main-health-monitor.ts:117` — `cron: "0 */6 * * *"`, dispatches `workflow_dispatch` on `ref: main` via a GitHub-App installation token (→ `soleur-ai[bot]`).
- `scripts/ci-shard-totality-classify.sh` — the fail-closed raw-diff classifier contract (verbatim allowlist semantics to reuse or mirror).
- `scripts/followthroughs/{ci-push-dedupe-soak-9512,mq-lever-e-verdict-12269,post-deploy-incident-soak}.sh` — probe conventions: header credential posture, exit vocabulary (0/1/2/3/78), fake-`gh` fixture suite (`ci-push-dedupe-soak-9512.test.sh`), `run_suite` registration at `scripts/test-all.sh:7171/7220`.
- `scripts/regenerate-shard-manifest.py` — `--timings-dir` (repeatable, one dir per run's artifact set), `--drift-report`, `--write`, `--incremental`, `--runs N`.
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` — canonical regen procedure (merge_group timings + `--timings-dir`, because push-dedupe elides shard jobs on `push` runs); "Measured history" is the record home.
- `scripts/watch-wallclock-p90-11774.sh` + `scripts/required-check-wallclock-bounds.tsv` + `scripts/required-checks.txt` — instrument of record (`--dry-run` prints the would-be report); bounds `test` = 3300/2820 s at margin 0.30.
- `scripts/followthroughs/mq-lever-e-verdict-12269.sh` — #12269's probe; its directive lives in a 2026-11-09T23:03:12Z comment (`earliest=2026-11-30T23:01:58Z`, `secrets=GH_TOKEN`).

### Measured evidence (this session)

- Monitor runs: `43295978800` green manual dispatch 2026-11-12T20:00:46Z (actor `deruelle`, all 3 mut legs success: approval-guard1 1493 s); `43275349911` failed 18:00:38Z on pre-merge code (merged 19:46:34Z); **zero** post-merge `soleur-ai[bot]` runs exist yet — next slot 2026-11-13T00:00Z.
- Post-merge merge_group run `43286327218` (green): `test` critical path `test-scripts (6/8)` = 2483 s; legs 7/8 2092 s, 4/8 2047 s, 3/8 1940 s, 1/8 1824 s; `test-webplat-mutations (approval-guard1)` = 1158 s; `test-webplat` legs 355–509 s. Latest run `43308874521` (21:18Z) still in progress at plan time.
- #12089's 2026-11-06 report: `test` p90 3624 s PR / 3205 s MQ (goals 1200/900); tracker since CLOSED — next Fri 09:07Z run re-files it. Watch "failures" are the designed breach exit-1, not instrument breakage.
- Suite leg-times: `ci-push-dedupe-soak-9512` committed `185400` ms vs `80676` ms observed — awaiting artifact re-price.

### Premise Validation

Ask items checked against live state: (1) scheduled cadence confirmed `0 */6 * * *`; the cited trackers #12455/#12618 are CLOSED; no post-merge scheduled run exists → the confirmation is a time-gated enrollment, not a one-shot read. (2) No existing issue covers the classifier → file it. (3) `--runs`/`--timings-dir` regen path confirmed against the runbook. (4) #11563 OPEN (Lever F placeholder); the ~30-min internal gate is a brainstorm-era figure — the plan measures, never asserts. (5–6) #12647/#12651 OPEN; #12269's soak directive verified in its comments. (7) The `185400` ms row is committed at `suite-durations.tsv:429` (leg 5 per `suite-shard-legs.tsv:431`). (8) p90 instrument verified — `--dry-run` is the canonical local invocation.

### Property List (mechanism-minimality restatement)

| # | Property (observable outcome) | Mechanism chosen | Already covered by `origin/main`? |
|---|---|---|---|
| P1 | A machine-verifiable record exists that ≥N post-merge **scheduled** monitor runs stayed green with un-censored mut legs — and it closes itself when true | new `scripts/followthroughs/main-health-monitor-mutations-12626.sh` + `follow-through` tracker | Partially — the monitor files `ci/main-broken` on failure, but absence-of-issue ≠ green proof (the #7307 silence failure the Sentry heartbeat exists for); `post-deploy-incident-soak.sh` measures "zero new incidents/issues", not "runs ran green" |
| P2 | The deferred `test-webplat-mutations` applicability classifier is tracked with an implementable design | one GitHub issue (committed body artifact) | No — verified absent |
| P3 | Committed shard prices/legs reflect post-split reality | `regenerate-shard-manifest.py --timings-dir … --write` | The tooling exists; the committed values are stale — a data fix, not a mechanism |
| P4 | A fresh p90 measurement exists on record vs the epic's 1200/900 goals and Lever F's ~30-min gate | `--dry-run` + runbook/issue comment | Instrument exists (`watch-wallclock-p90-11774.sh`); the measurement itself is the deliverable |
| P5 | #12269/#12647/#12651 states verified and undisturbed | `gh issue view` checks | No new mechanism |

### Cut List

- Reuse `post-deploy-incident-soak.sh` for the scheduled-run confirmation → cut: it proves "zero new `ci/` issues + zero Better Stack incidents", i.e. absence-of-alarm — exactly the silence-as-health failure mode (#7307) the ask wants positive evidence against.
- A new `schedule:` workflow or Inngest poll for the confirmation → cut: `scheduled-followthrough-sweeper.yml` already runs every probe daily; the enrollment substrate exists.
- A job-level `if:` skip arm for `test-webplat-mutations` in this slice → cut: the ask is to *file* the follow-up, and the `if:`/`needs:` lines are pinned by `ci-push-dedupe.test.sh`/`ci-draft-light.test.sh` — the design belongs to the issue.
- Editing `required-check-wallclock-bounds.tsv` bounds → cut: bounds are seeded from measured p90 by a deliberate process; re-seeding is a separate ratchet decision, not asked for.
- Extending the classifier issue's v1 allowlist beyond the shard-totality markdown-only set → cut: any wider set requires a per-battery mutation-target census; v1 stays provably inert.

### Institutional learnings applied

- `followthrough-convention.md`: directive unfenced at column 0; `secrets=GH_TOKEN` mandatory for gh-using probes; probe must exist in the MAIN checkout before `gh issue create` (worktree caveat); earliest= filing date (script self-gates); exit 2 for not-yet.
- `plan-sharp-edges` #298-class: the probe reads run *records* — it must pin the window by `created_at >= merge`, and a `total_count` shrinkage means count-based completeness is unsafe (probe asserts on enumerated runs, not counts).
- `ci-push-dedupe-soak-9512.test.sh` pattern: fake-`gh` fixtures, injected clock, exit-code contract driven per arm.

## Open Code-Review Overlap

5 open scope-outs touch planned files; none is folded in — all acknowledged (different concern, each keeps its own cycle):

- **#7942** (`scripts/test-all.sh`): two `plugins/soleur/test/*.mutation.sh` batteries run in no gate — acknowledged; unrelated to the probe `run_suite` registration this plan adds.
- **#11312** (`scripts/followthroughs/`): `monitor_sig` blind spot in `monitor-pr-checks.sh` — acknowledged; different probe.
- **#10462, #10463, #10464** (`scripts/followthroughs/`): zot fill-rate probe rename/parse/blind-window — acknowledged; different probe.
- **#8435** (`scripts/followthroughs/`): `gsc-indexing-drain-8332.sh` evidence scope-out — acknowledged; different probe.
- **#8890** (`main-health-monitor` mention): `deploy-script-tests` K=4 design pass — acknowledged; different surface.

## Files to Create

- `scripts/followthroughs/main-health-monitor-mutations-12626.sh` — the scheduled-run confirmation probe (P1)
- `scripts/followthroughs/main-health-monitor-mutations-12626.test.sh` — its fake-`gh` fixture suite (P1)
- `knowledge-base/project/specs/feat-one-shot-11556-epic-ac-chain/classifier-issue-body.md` — committed body for the follow-up issue (P2)
- GitHub tracker issue: `ci: post-merge scheduled-run confirmation for test-webplat-mutations legs (#12626)` — `follow-through` label + directive (external artifact)
- GitHub issue: the `test-webplat-mutations` applicability classifier follow-up (external artifact)

## Files to Edit

- `scripts/test-all.sh` — one `run_suite "scripts/followthroughs/main-health-monitor-mutations-12626" …` line beside the sibling probe registrations (~line 7171–7220 block)
- `scripts/suite-shard-legs.tsv` — new suite's leg placement (`--incremental --write`) + any `--timings-dir --write` re-balance
- `scripts/suite-durations.tsv` — floor row for the new suite + re-priced rows (incl. the `ci-push-dedupe-soak-9512` 185400 ms row)
- `scripts/suite-shard-legs-heavy.tsv`, `scripts/suite-durations-heavy.tsv` — only if the heavy-group drift report shows material skew
- `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` — "Measured history" rows: fresh top-15 ranking + the p90 measurement

## Implementation Phases

### Phase 1 — scheduled-run confirmation probe + tracker

1.1 Write `scripts/followthroughs/main-health-monitor-mutations-12626.sh`: header (property, CREDENTIAL POSTURE `secrets=GH_TOKEN`, exit vocabulary, RETIREMENT list); fetch `GET /repos/{owner}/{repo}/actions/workflows/main-health-monitor.yml/runs?event=workflow_dispatch&per_page=30`; filter `actor.login == "soleur-ai[bot]" && head_branch == "main" && created_at >= "2026-11-12T19:46:34Z" && conclusion in {success, failure}` (exclude `cancelled`/in-progress); require ≥2 qualifying runs; for each, fetch jobs and assert ≥3 jobs named `test-webplat-mutations (*)` all `conclusion == "success"`. Exit: 0 all-green; 1 on any failing/incomplete run (names run id + leg); 2 while <2 qualifying runs; 3 on gh/API failure; 78 under xtrace.
1.2 Write `scripts/followthroughs/main-health-monitor-mutations-12626.test.sh` per the `ci-push-dedupe-soak-9512.test.sh` fake-`gh` fixture pattern; drive every matrix row below.
1.3 Register: `run_suite "scripts/followthroughs/main-health-monitor-mutations-12626" bash scripts/followthroughs/main-health-monitor-mutations-12626.test.sh` in `scripts/test-all.sh`.
1.4 `python3 scripts/regenerate-shard-manifest.py --incremental --write` to place the new suite label + floor price in the TSVs.
1.5 Copy the probe into the MAIN checkout's `scripts/followthroughs/` (untracked; the directive gate resolves under `HOOK_CWD`) — then `gh issue create` the tracker with `follow-through` label and the unfenced column-0 directive:
    `script=scripts/followthroughs/main-health-monitor-mutations-12626.sh earliest=<filing ISO-8601> secrets=GH_TOKEN`
1.6 Verify the directive parses (hook output) and record the tracker number in the session summary.

### Phase 2 — file the applicability-classifier follow-up

2.1 Write `knowledge-base/project/specs/feat-one-shot-11556-epic-ac-chain/classifier-issue-body.md` (content sketched under Context below).
2.2 `gh issue create` with labels `type/chore`, `domain/engineering`, `meta/machinery`, `priority/p3-low`; body refs #11556, #12626, #9729, and the archived decision-challenges ruling deferring `--rows`.
2.3 Record the issue number; link it back from the plan/tasks artifacts.

### Phase 3 — Lever-A re-rank + re-price

3.1 List the N most recent green `merge_group` `ci.yml` runs (post-`34634d7431` preferred; at minimum the freshest 5 green runs); `gh run download <id> -p 'suite-timings-scripts-*' -D <dir>` per run into per-run dirs (heavy family included).
3.2 `python3 scripts/regenerate-shard-manifest.py --timings-dir <d1> --timings-dir <d2> … --drift-report` (light + `--group heavy`); if drift is material, re-run with `--write` to re-price `suite-shard-legs{,-heavy}.tsv` and `suite-durations{,-heavy}.tsv`.
3.3 Reconcile `scripts/followthroughs/ci-push-dedupe-soak-9512` `185400` ms vs the artifact-measured value — the regenerated table is authoritative; record both figures.
3.4 Emit the fresh top-15 suite-time ranking (per-label median ms, descending) into `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` "Measured history" with the run ids used.

### Phase 4 — p90 + Lever-F measurement

4.1 `bash scripts/watch-wallclock-p90-11774.sh --dry-run` (needs `GH_TOKEN`); record the `test` rows for both surfaces + any breach/untracked findings.
4.2 Write the measurement into the runbook "Measured history" (vs 3246 s 2026-11-02 baseline and the 2026-11-06 report's 3624/3205 s).
4.3 Comment on #11556: AC-chain status — scheduled-run enrollment, classifier issue #N, Lever-A re-rank result, `test` p90 now vs goals, and the honest verdict (expected: still >20 min PR — the binding constraint is now `test-scripts` leg skew, measured 2483 s on `43286327218`). Note #11563's ~30-min internal gate against the measured legs (mut legs ≤26 min; `test` aggregate >30 min — the gate's exact predicate is Lever-F-scoped, so the comment states the raw numbers and leaves the gate call to that issue).
4.4 Note that the epic's "14 consecutive days ≤ goal" criterion remains gated; do not assert it.

### Phase 5 — tracker hygiene + close-out

5.1 `gh issue view` #12647, #12651 (OPEN, no state change), #12269 (directive comment `earliest=2026-11-30T23:01:58Z` intact — do not touch).
5.2 Verify `git status` limited to the prescribed file set; commit.

## Guard Contract

### Guard 1 — `main-health-monitor-mutations-12626.sh` scheduled-run verdict

**Property.** The tracker may close only after ≥2 completed post-merge scheduled (`soleur-ai[bot]`) `main-health-monitor` runs are all green with all three `test-webplat-mutations` legs successful; any non-success or mut-leg-incomplete scheduled run is FAIL, and fewer than 2 qualifying runs is NOT YET — never PASS.

**Assembly.** The probe's only verdict path: the `runs?event=workflow_dispatch` listing → the actor/branch/timestamp/conclusion filter → the per-run `jobs` read for the three `test-webplat-mutations (*)` members → the exit code the sweeper reads. The enrollment chokepoint is the tracker's `soleur:followthrough` directive (column 0, unfenced) + the `run_suite` registration; both are pinned by `.claude/hooks/follow-through-directive-gate.sh` and `lint-orphan-test-suites.sh` respectively.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture: newest post-merge scheduled run `conclusion=failure` | RED (probe exits 1, names the run id) |
| 2 | Fixture: a green scheduled run missing `test-webplat-mutations (approval-guard1-mutation)` from its jobs list | RED (exit 1 — leg absence is FAIL, never silently green) |
| 3 | Fixture: two scheduled runs where the FIRST (older) is green and a LATER second member is red | RED (exit 1 — a check that stops at the first member is the defect class) |
| 4 | Fixture: only `actor=deruelle` post-merge dispatches exist (no `soleur-ai[bot]` runs) | exit 2 — manual dispatches must not count toward the cadence proof |
| 5 | Fixture: ≥2 qualifying green scheduled runs but one carries `conclusion=cancelled` between them | cancelled excluded from the sample; still exits 0 — a cancel is not regression evidence |
| 6 | Suite harness: fake `gh` returns malformed jobs JSON for one sampled run | exit 3 (CANNOT ESTABLISH — a read failure is never a verdict) |
| 7 | Must-PASS non-canonical: a `deruelle` manual dispatch concludes `failure` between two green `soleur-ai[bot]` scheduled runs | exit 0 — a red MANUAL dispatch is not cadence evidence; the scheduled population alone carries the verdict |
| 8 | xtrace arm: probe run under `bash -x` with `GH_TOKEN` set | exit 78 (refusal, never a verdict) |

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — no subagent-spawn capability in this harness; recorded per the #12446 pattern, parent carries any batched spawn)
**Assessment:** Internal CI measurement/enrollment slice. Risks: (a) probe false-PASS via wrong discrimination (actor pinning verified against live runs) or vacuous leg check (mitigated by asserting mut legs per run + the Guard Contract matrix); (b) re-price regen landing a large manifest diff (bounded by `--drift-report` review first); (c) follow-up issue under-specifying the fail-closed contract (the committed body enumerates it). No other domain's assessment question fires: no user-facing surface (Product), no vendor/procurement (Operations), no legal docs (Legal), no revenue/pipeline/finance/support surfaces.

**Brainstorm-recommended specialists:** none (no brainstorm ran for this slice).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Confirm the dedicated mutation-job fix holds on scheduled `main-health-monitor` runs at the `00/06/12/18Z` cadence; inspect the latest scheduled runs and related trackers #12455 and #12618." | Phase 1 + probe + tracker + Guard 1 | mapped |
| 2 | "File the named follow-up for an applicability classifier for `test-webplat-mutations`, analogous to `scripts/ci-shard-totality-classify.sh`; the job currently costs roughly three 25–30 minute leg-minutes on KB-only PRs." | Phase 2 + `classifier-issue-body.md` | mapped |
| 3 | "Re-derive Lever-A outlier ranking using fresh green `merge_group` artifacts and `scripts/regenerate-shard-manifest.py --runs`." | Phase 3 (`--timings-dir` per the runbook's canonical merge_group path; `--runs` named in the ask is the same tool's run-count arm) | mapped |
| 4 | "Check whether mutation-battery relocation moved Lever F / #11563 toward its internal p90 ≤30-minute gate; the critical path should no longer include the batteries on webplat legs." | Phase 4 + #11563 note | mapped |
| 5 | "Continue tracking #12647 (`/tmp` tmpfs leak in `infra-config-apply.test.sh`) and #12651 (Fable 5.2 `model-launch-review` timeout flake) separately." | Phase 5.1 | mapped |
| 6 | "Leave #12269 soaking through 2026-11-30 with `max_entries_to_build` changed from 2 to 1." | Phase 5.1 (verify-only, do-not-touch) | mapped |
| 7 | "Investigate the stale `ci-push-dedupe-soak-9512` committed price of `185400ms` versus an observed `80676ms` on a real merge-group run; fresh green runs should re-price it." | Phase 3.3 | mapped |
| 8 | "Determine whether required-check p90 has reached ≤20 minutes for PRs and ≤15 minutes for merge queue after the slice beds in." | Phase 4 (`--dry-run` measurement + #11556 comment) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/followthroughs/main-health-monitor-mutations-12626.sh` (+suite, registration, manifest rows, tracker) | "Confirm the dedicated mutation-job fix holds on scheduled `main-health-monitor` runs at the `00/06/12/18Z` cadence" | asked |
| `classifier-issue-body.md` + `gh issue create` | "File the named follow-up for an applicability classifier for `test-webplat-mutations`" | asked |
| `scripts/test-all.sh` run_suite line | — | inferred — justification: `lint-orphan-test-suites.sh` reds CI on an unregistered `.test.sh`; registration is the enforcement contract the new suite needs |
| `suite-shard-legs.tsv` / `suite-durations{,-heavy}.tsv` edits | "Re-derive Lever-A outlier ranking using fresh green `merge_group` artifacts" + "fresh green runs should re-price it" | asked |
| `ci-test-scripts-sharding.md` Measured-history rows | — | inferred — justification: the runbook's Measured history is the repo's record home for rankings/p90 figures; an unrecorded measurement does not exist |
| #11556 comment / #11563 note | "Determine whether required-check p90 has reached ≤20 minutes" + "Check whether mutation-battery relocation moved Lever F / #11563" | asked |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `knowledge-base/`
- Planned files: 8 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: headless pipeline run — no founder present; no founder_check block (ADR-275 no-block arm) -->

- [ ] **AC1 — probe + registration.** `scripts/followthroughs/main-health-monitor-mutations-12626.sh` exists, is executable, carries the credential-posture + exit-vocabulary + RETIREMENT header; `scripts/followthroughs/main-health-monitor-mutations-12626.test.sh` drives every Guard-Contract matrix row; `scripts/test-all.sh` carries its `run_suite` line; `suite-shard-legs.tsv` + `suite-durations.tsv` carry the new label (floor-priced).
- [ ] **AC2 — tracker enrolled.** A `follow-through`-labeled tracker issue exists naming the probe in an unfenced column-0 `<!-- soleur:followthrough script=… earliest=<filing ISO> secrets=GH_TOKEN -->` directive; the probe file was present in the MAIN checkout at filing time.
- [ ] **AC3 — classifier issue filed.** A new issue exists whose body specifies: in-job detect-step modeled on `ci.yml:2137`, base-sourced classifier, `applicable != 'false'` step guard, fail-closed enumeration (unknown event/malformed-diff/empty-diff/API-failure → run the battery), v1 allowlist = the `ci-shard-totality-classify.sh` markdown-only set, the per-battery mutation-target census required before any widening, the pinned `if:`/`needs:` constraint (`ci-push-dedupe.test.sh`, `ci-draft-light.test.sh`), no aggregator change needed, and the `--rows` `approval-guard1-mutation` split as the adjacent deferred lever; refs #11556, #12626, #9729.
- [ ] **AC4 — Lever-A re-rank.** The fresh top-15 suite-time ranking from post-merge green `merge_group` `suite-timings-scripts-*` artifacts is recorded in the runbook's Measured history with the run ids; the `ci-push-dedupe-soak-9512` row is reconciled to the artifact-measured price (committed value updated or the discrepancy explained).
- [ ] **AC5 — p90 verdict recorded.** `watch-wallclock-p90-11774.sh --dry-run` output for the `test` check on both surfaces is recorded (runbook + #11556 comment) with the explicit verdict vs 1200 s / 900 s and the note that the 14-day criterion remains gated.
- [ ] **AC6 — Lever-F status.** #11563 carries the measured leg/aggregate figures and the explicit statement of whether its ~30-min internal gate now holds (mut legs ≤ ~26 min; `test` aggregate measured).
- [ ] **AC7 — tracker hygiene.** #12647 and #12651 remain OPEN with no state change; #12269's directive comment is untouched; #12455/#12618 confirmed CLOSED with the 18Z failure explained as pre-merge.
- [ ] **AC8 — no silent drops.** `bash scripts/lint-orphan-test-suites.sh` (or the registered-suite census) is green for the new suite, and `git status` at close-out shows only the prescribed file set.

## Test Scenarios

- **Probe arms (unit/integration, fixture-driven):**
  - Given 2 post-merge `soleur-ai[bot]` runs both `success` with 3/3 mut legs green → exit 0.
  - Given a post-merge scheduled run `conclusion=failure` → exit 1 naming the run id.
  - Given a green run missing one `test-webplat-mutations` leg → exit 1.
  - Given only manual (`deruelle`) post-merge dispatches → exit 2.
  - Given a `cancelled` scheduled run interleaved between two green ones → excluded, exit 0.
  - Given fewer than 2 qualifying completed runs → exit 2.
  - Given `gh api` failure / malformed JSON → exit 3.
  - Given `bash -x` with `GH_TOKEN` set → exit 78.
- **Registration (integration):** Given the new suite file exists, when the orphan census runs, then the suite is registered exactly once and `test-all.sh` executes it.
- **Regen (integration):** Given downloaded post-merge `suite-timings-scripts-*` artifact dirs, when `--drift-report` runs, then it prints the per-leg predicted-vs-measured table without erroring on the new suite's floor row.
- **Measurement (verification):** `bash scripts/watch-wallclock-p90-11774.sh --dry-run` prints the `test` p90 rows for `pull_request` and `merge_group`; the output is quoted verbatim in the runbook row.

## Context

**Classifier issue body (sketch for `classifier-issue-body.md`).** Title `feat(ci): applicability classifier for test-webplat-mutations — skip on provably-inert diffs (#12626 follow-up)`. Body covers: the measured cost (~3 legs/battery-run; `approval-guard1-mutation` 19–26 min on every PR incl. KB-only); the shard-totality precedent (#9729, in-job detect step at `ci.yml:2137`, base-sourced classifier, `!= 'false'` guard, recorded skip notice, job still reports `success` so the `test` aggregator is unchanged); v1 allowlist identical to `ci-shard-totality-classify.sh` (markdown under `knowledge-base/` + root `*.md` — reuse the script vs a sibling copy is the implementer's call, with the parity-suite requirement either way); the census-of-mutation-subjects gate before any allowlist widening (the three batteries mutate app-tree surfaces: the approval consume gate / `createCanUseTool` gated branch, the destroy-ask hook, home-census); every unknown runs the battery; merge_group/push/non-PR events always run; and the adjacent `--rows` row-split lever deferred by the archived CTO ruling — to be scheduled if the measured `test` p90 keeps `approval-guard1-mutation` on the critical path above the 20-min goal.

**Why a probe, not a one-shot read:** no post-merge scheduled run exists yet (next 2026-11-13T00:00Z); a one-shot inspection would record zero runs and the confirmation would rot unverified — the follow-through substrate exists exactly for time-gated closers.

## References

- Epic #11556; prior slice PR #12654 / issue #12626 / squash `34634d7431`; trackers #12455, #12618 (closed), #12269 (soaking to 2026-11-30), #12647, #12651; precedents #9729, #9512, #12089; Lever-F placeholder #11563.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`, `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.
- `knowledge-base/project/specs/archive/20261030-170617-feat-11556-required-check-time/` (Lever-A spec artifacts); `knowledge-base/project/specs/archive/20261111-210708-feat-one-shot-12626-webplat-monitor-timeout/decision-challenges.md` (deferred-lever rulings).
