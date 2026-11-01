---
title: "fix: epic #11556 continuation — #10865 probe budget, #10781/#11379 Lever D, #9323 soak + Lever E filings, #10448 decision record"
date: 2026-11-01
slug: epic-11556-ci-time-batch
branch: feat-one-shot-11556-epic-ci-time-batch
issue: 11556
type: fix
lane: cross-domain
closes: [10781, 11379]
---

## Overview

One PR covering the remaining batched slice of epic #11556 (cut PR required-check wall-clock toward 20 min), in five items:

1. **#10865 — bound the observation-window probe.** `scripts/followthroughs/ratchet-observation-window-10865.sh` is killed by the sweeper's 300 s `FT_PROBE_TIMEOUT` (CANNOT ESTABLISH, exit 3) because its two-epoch budget model (`SOAK_BUDGET_S` for reads from `T0` plus `SOAK_FACTS_BUDGET_S` measured from the facts-phase start) totals ~480 s+listing — designed against the sweeper's old 15-min shared ceiling, predating #11215's per-probe cap. Re-scope to one wall deadline under the cap.
2. **#10781 — Lever D close-out.** The apt-budget exhaustion behind `deploy-script-tests (1/4)` red was fixed by merged PRs #11442 (shared apt lists/archives), #11573 (leg rebalance + ci-deploy bound) and #11676 (cron-egress bound); residual trackers #11568/#11669 are closed. Verify the green stretch, post the named root cause, close the issue. The job is advisory by design (not in `ruleset-ci-required.tf`) — the epic's "non-blocking by design" arm is already satisfied and is recorded as such.
3. **#11379 — Lever D flake fix.** `ctr_collect`'s `printf | perl` producer hits EPIPE when the K18 lexstub exits without reading stdin; the stderr line contaminates `got` in `_w_lexstub`. One-line fix: `2>/dev/null` on the producer printf.
4. **#9323 — honest soak resolution.** The probe compares whole-run billable means (post-gate ~266) against an all-events pinned baseline (76): a methodology artifact — the same-shape pre-gate control is ~113 and ~113 min of unrelated suite growth swamps the gate's ~35–48 suite-min saving. The lever demonstrably fires (run 41266779224: every gated battery `0 skip=relevance`). Re-instrument arm (a) to realized-skip accounting; keep the escape arm and the honest FAIL path. Then file the epic's two unfiled Lever E trackers.
5. **#10448 — decision record.** Post the operator's 2026-11-01 ruling (FUND affected-index completion, option (i)) on #10448 and file the index-completion scheduling issue carrying forward the measured remainder (`gap_suites=272 gap_refs=1634`).

## Premise Validation (Phase 0.6)

All cited artifacts verified live 2026-11-01: issues #11556, #10865, #10781, #11379, #9323, #10448 all OPEN; PRs #11302, #11393, #11718, #11728, #10566, #10671, #10945, #11109, #11131, #11226 all MERGED. Cited files exist on branch (`ratchet-observation-window-10865.sh` 473 lines; `pr-battery-gate-saving-9323.sh` 190 lines; `followthrough-convention.md`; `commit-target-roots.sh`; `git-commit-secret-scan.test.sh`). Collision precheck: no open PRs name any of the five work issues; one foreign `test-all.sh` process in the main checkout (pid 3141631) is ambient test execution, not a work collision.

**Premise corrections found during validation:** (a) #10781 is already root-fixed on main — `lib/apt-bounded.sh` carries a `SHARED LISTS + ARCHIVES (#10781)` block merged via #11442 (Oct 29), and `deploy-script-tests` legs are green on main since 2026-10-31 21:23Z; the residual red classes seen Oct 29–30 (`ci-deploy` 540 s kills, `cron-egress-nftables` 360 s kills, `cloud-init-inngest-bootstrap` real tag drift) were all dispositioned by #11568/#11669/#11573/#11676 — so Item 2 is verify-and-close, not fix. (b) #9323's FAIL trajectory is measured on the issue itself (deruelle 2026-10-28) and corroborated here: whole-run mean drift, not gate failure.

## Research Insights

### Property List (Phase 0.6b)

- P1: the #10865 probe always reaches its own verdict (0 or 2) inside `FT_PROBE_TIMEOUT` — the sweeper's kill never lands first; exit contract (0=pass, 2=NOT YET, 3=cannot establish) preserved.
- P2: #10781 closed honestly — root cause named from evidence (leg membership + apt-budget accounting), green state verified, no new machinery.
- P3: the K18 suite case can no longer see a stray `printf: write error: Broken pipe` line in `got`.
- P4: the #9323 probe measures the lever's own realized saving (drift-immune), keeps the escape arm, and FAILs honestly if the realized saving is under the bar.
- P5: the two unfiled Lever E trackers exist and name requirements, not mechanism.
- P6: #10448 records the fund ruling and the scheduling issue carries forward the measured remainder.

### Cut List (Phase 0.6b)

- Raising `FT_PROBE_TIMEOUT` — cut; the runbook forbids it (§Per-probe wall-clock cap: "a defect in the probe … not a reason to raise the cap").
- New telemetry/artifact machinery for the soak — cut; `skip=relevance` rows already exist in `suite-timings-*` artifacts (emitted by `SUITE_COMMAND_DECLINED`, test-all.sh), and prices exist in `scripts/suite-durations{,-heavy}.tsv`.
- `deploy-script-tests` job re-architecture — cut; already advisory (non-blocking) by design; the residual suite classes were dispositioned by merged siblings.
- Digest rendering machinery for Lever E — cut to the filed issue; this PR files requirements only.

### Key evidence

- **#10865 defect shape:** probe `T0` at script start; `SOAK_BUDGET_S` (300, cap 600) gates oldest-first read launches (`SECONDS - T0 >= BUDGET`); `SOAK_FACTS_BUDGET_S` (180, cap 300) gates the serial facts loop measured from `TF0` (its own start) — worst case ≈ listing + 300 + 180 + tail. Runbook records "~300 s of reads plus up to 180 s of facts, about 480 s" — calibrated to the sweeper's pre-#11215 15-min shared ceiling. 2026-10-31 sweep: `phase=listed seen=1285 readable=797 to_read=260 parallel=4 budget_s=300 elapsed_s=47` then killed at 300 s. Per-unit read ≈ 3.2 s (jobs 2.1 + log 1.1); 260 units / PAR 4 ≈ 208 s; listing 26 pages ≈ 47 s; facts ≈ 2.4 s/PR serial.
- **Fit math for the fix:** deadline `END = T0 + 270` (30 s margin under the 300 kill; the probe itself measured listing 47 + reads ~104 at PAR 8 + facts ~60 + verdict/baseline ~10 ≈ 221 s).
- **#10781:** `APT_BUDGET_S=420` shared per suite run; ~12 containers × full private `apt-get update`+`install` exhausted it on slow-mirror days (`spent_before=420s budget=420s`); #11442's shared `Dir::State::lists`/`Dir::Cache::archives` makes only the first container pay downloads. Leg membership: `git-data-runcmd-rehearsal` is leg 1/4 (suite-shard-legs.tsv). Main runs green ×8 since 2026-10-31 21:23Z.
- **#11379:** `_w_lexstub` (`.claude/hooks/git-commit-secret-scan.test.sh`) captures `2>&1` into `got`; `ctr_collect`'s `printf '%s' "$cmd" | perl "$CTR_LEXER"` SIGPIPEs when the stub exits without reading stdin — scale/timing-dependent, same class as `learnings/workflow-issues/2026-10-02-early-exit-pipe-consumers-sigpipe-under-pipefail.md`.
- **#9323:** baseline 76 was an all-events mean; same-shape pre-gate control 113.1; post-gate qualifying 202→266 (growing with suite count). Realized-skip accounting: gated batteries on run 41266779224 all `0 skip=relevance`; priced sum = registry-gate 491178 + battery-tag-mutations 379182 + lint-orphan a+b 239863 + cf-tunnel 115034 + test-all-affected a..d 1684693 ms ≈ **48.5 suite-min/run** ≥ 20 bar with margin. Queue-wait AC (≤10 min at similar load) is met (18.3 → ~3–7 min).
- **Lever E surfaces:** digest = `plugins/soleur/skills/operator-digest/SKILL.md` + `assets/operator-digest.workflow.yml` (installed into private `jikig-ai/operator-digest`, ADR-057); ratchet precedent = `scripts/followthroughs/deploy-script-tests-legs-8736.sh` (per-job `completed_at − started_at` pattern) and `scripts/watch-shard-balance-11564.sh` (weekly drift watch, #11728 — cite, don't duplicate); tally = `plugins/soleur/scripts/pipeline-tally.sh` + `skills/ship/references/pipeline-tally-render.md` (dims: seats, ci_cycles, fix_rounds, agent_rounds; machine line `Pipeline-Tally:` in PR body).
- **#10448:** audit run 2026-11-01 on this worktree: `suites=707 always_on=122 audited=585 gap_suites=272 gap_refs=1634 accepted=0 refs=3522`; baseline 1,510 lines, accept 241. Drain continuation evidence: merged #10671/#10945/#11109/#11131/#11226. Entry condition text is verbatim on #10448's "Entry condition for any re-attempt (option i)".
- **Conventions:** `secrets=GH_TOKEN` mandatory for gh-using probes; probe retirement blocks; `Fix-Size:`/`User-Impact:` fields on filings; `action-required` label only for operator asks (Lever E trackers are engineering work — no action-required); two-stage `gh --json` + `jq --arg` piping rule observed.

## Files to Edit

- `scripts/followthroughs/ratchet-observation-window-10865.sh` — re-scope budget model to one wall deadline (Item 1).
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — the probe's test rows (the "ratchet observation window" section): cover deadline semantics, facts sub-allocation, PAR default, verdict-preserving cut.
- `scripts/followthroughs/pr-battery-gate-saving-9323.sh` — realized-skip arm (a) re-instrument + `rate_limit` precheck (Item 4).
- `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` — fixture rows for realized-skip accounting (skip rows priced vs durations TSVs; quota-cut → NOT YET never FAIL).
- `.claude/hooks/lib/commit-target-roots.sh` — `printf '%s' "$cmd" 2>/dev/null |` in `ctr_collect` (Item 3).
- `.claude/hooks/git-commit-secret-scan.test.sh` — K18 regression row (assert producer-stderr silencing; see Test Scenarios).
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — update the probe's documented time arithmetic ("~480 s typical") to the new deadline model.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — only if the probe-budget wording needs the 300 s world clarified (probe-side change is the fix; edit only on drift found).

## Files to Create

None — Lever E trackers and the scheduling issue are GitHub issues, not repo files.

## Implementation Phases

### Phase 1 — #10865: bound the probe inside the sweeper cap

- Re-anchor: single `END = T0 + BUDGET` deadline; `SOAK_BUDGET_S` semantics become total wall (default 270, cap 300 — env seam kept for tests); `SOAK_FACTS_BUDGET_S` becomes `min(FACTS_BUDGET, END − SECONDS − TAIL)` where `TAIL` ≈ 20 s reserves verdict + baseline reads.
- Gate every phase against `SECONDS - T0` (or `SECONDS >= END`): listing loop (cut → `TRUNC=1` listing flag), read dispatch (existing check re-pointed at the deadline), facts loop (re-anchor from `TF0` to the deadline), per-read `timeout` capped at `min(60, END − SECONDS − 5)`.
- `SOAK_PARALLEL` default 4→8 (existing 1..8 validation unchanged).
- Keep: newest-10-merge_group priority dispatch exempt from the read budget (bound it by the deadline too — it must never be the overrun), oldest-first certification order, all quota/`planned=` logic, exit codes, the `truncated`/`units_read` status fields, header documentation (update the arithmetic paragraphs and CREDENTIAL POSTURE wording as needed).
- Update `plugins/soleur/test/ci-pr-affected-replay.test.sh` rows for the new seams (deadline-bound cut, facts sub-allocation, PAR 8) and `ci-pr-affected-activation.md`'s time-arithmetic paragraph.
- Dry-run the REAL probe locally with `SOAK_PROGRESS=1` against the live window (GH token) per runbook §"dry-run the REAL sweeper on the branch" — record `phase=read-done`/`facts-done` elapsed and the status line in the PR body.

### Phase 2 — #10781: verify and close (Lever D)

- Pull leg membership + apt accounting evidence (done in Research Insights; re-verify at work time).
- Confirm `deploy-script-tests` legs green on a run containing current main and on this PR's own head.
- Post root-cause comment on #10781 (named mechanism + the three merged fix PRs + green-run evidence + "already advisory / non-blocking by design" Lever D disposition), then `gh issue close 10781`.

### Phase 3 — #11379: K18 SIGPIPE fix (Lever D)

- Edit `ctr_collect` producer: `printf '%s' "$cmd" 2>/dev/null | perl "$CTR_LEXER" 2>/dev/null || true`.
- Add a K18 regression row asserting a stub that closes stdin early cannot contaminate `got` (see Test Scenarios).
- Close #11379 with the fix link.

### Phase 4 — #9323: honest soak + Lever E filings

- Re-instrument arm (a): per qualifying run, enumerate `suite-timings-*` artifacts, read the TSVs, sum `scripts/suite-durations{,-heavy}.tsv` prices for rows `label\t0\tskip=relevance` matching the `--pr-gated` battery set (derive the set from `scripts/test-all.sh` `--pr-gated` call sites as `ci-battery-gate-replay.sh` does — never a hand list).
- New bar: mean realized saving ≥ `REQUIRED_SAVING_MIN` (20) over ≥ `MIN_RUNS` qualifying runs → PASS; under → FAIL (honest, unchanged direction); unreadable/missing artifact evidence → NOT YET, never FAIL.
- Add `rate_limit` precheck + artifact-read budget; whole-run mean and queue wait become informational status fields.
- Update the probe's `.test.sh` (fixtures: full-skip run ≈ 48.5 min realized; partial skip; quota cut; missing artifact).
- Report the investigation on #9323 (methodology finding + realized-saving evidence + queue-wait AC met) — the probe continues soaking under the re-instrumented bar; do NOT close the issue in this PR (the soak itself decides).
- File Lever E trackers:
  - (a) "required-check wall-clock p50/p90 per job in the weekly operator digest + regression ratchet" — names the digest section (new source arm in `operator-digest` skill + workflow), per-job `completed_at − started_at` percentiles over required-check jobs, and a follow-through-registered ratchet that FAILs on p90 regression vs a pinned baseline; cites the `deploy-script-tests-legs-8736.sh` leg-measurement pattern and `watch-shard-balance-11564.sh` (no duplicate).
  - (b) "CI wall-clock in the ship pipeline tally" — extend `pipeline-tally.sh` dims + `pipeline-tally-render.md` machine line so slow merges are attributable (sums required-check wall-clock per merge), `Fix-Size:` small.
- Update epic #11556: comment ticking the Lever E filing bullets and noting #11564's shipped drift watch covers the "extend per-suite time bounds" bullet's first half.

### Phase 5 — #10448: decision record

- Post the operator's 2026-11-01 ruling on #10448 (FUND option (i); reference CTO recommendation 2026-10-16; holds unchanged: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D #10414, no PR3b #10859, no flip PR — PR3b stays held for the budget owner).
- File the index-completion scheduling issue: entry condition verbatim (audit `gap_suites=0` OR every remaining row a human `false-positive:` reason; required-ratchet check; escape-replay re-run); carries forward measured remainder (`gap_suites=272 gap_refs=1634` at 2026-11-01; baseline 1,510 lines); names merged drain PRs so the work continues, not restarts.

## Acceptance Criteria

- [ ] **AC1** — `ratchet-observation-window-10865.sh` run under `timeout -k 10 300` (and under `SOAK_BUDGET_S=270`) against the live window exits 0 or 2 with `truncated=`/`units_read=`/`window opened=`/`quota:` status fields — never killed (no rc 124/137), never CANNOT ESTABLISH on a budget cut; a `NOT YET:` on unmet criteria names the cut (`read budget ended after N of M runs` or `in the PR-facts phase`) exactly as today.
- [ ] **AC2** — the probe's quota/`planned=` guard, newest-10 merge_group priority dispatch, restart-floor logic, defect/incident/unclassified classification, baseline-set comparison and exit-code contract are unchanged (the `ci-pr-affected-replay.test.sh` rows covering them stay green plus new rows for the deadline semantics).
- [ ] **AC3** — `gh run` evidence that `deploy-script-tests` legs are green on a head containing current main; root-cause comment posted and #10781 closed citing #11442/#11573/#11676 and the advisory-by-design Lever D disposition.
- [ ] **AC4** — `git-commit-secret-scan.test.sh` K18 battery green; a stub that exits without reading stdin produces exactly `S=unavailable K=parse` in `got` (no stderr contamination); no other `printf |` producer under `.claude/hooks/lib/` regresses (grep the lib for sibling early-reader producers).
- [ ] **AC5** — `pr-battery-gate-saving-9323.sh` computes realized saving from `skip=relevance` rows priced via committed durations TSVs; a fixture full-skip run yields ≥ 20 and a fixture under-20 run FAILs; quota-cut → NOT YET; escape arm unchanged (a red merge-commit push run still FAILs).
- [ ] **AC6** — two Lever E tracker issues filed, each carrying requirements + `Fix-Size:`/`User-Impact:`; epic comment ticks the filing bullets.
- [ ] **AC7** — #10448 carries the 2026-11-01 fund ruling comment and the scheduling issue exists naming the verbatim entry condition, the measured remainder and the merged-drain continuation (no restart).

## Open Code-Review Overlap

None — checked 2026-11-01 against `gh issue list --label code-review --state open` for all six files above (0 hits).

## Scope Check

### Ask Mapping

| Ask (quoted from the brief) | Plan item | Status |
|---|---|---|
| "#10865: … bound its own reads … keep its exit-code contract (0=window passed, 2=NOT YET, 3=cannot establish)" | Phase 1 | mapped |
| "#10781 … fix or make it non-blocking by design per the epic's Lever D wording" | Phase 2 | mapped — resolved as verify+close: evidence shows already fixed on main (#11442/#11573/#11676) and the job is advisory by design |
| "#11379: git-commit-secret-scan K18 flakes on 'printf: write error: Broken pipe' in CI. Lever D." | Phase 3 | mapped |
| "#9323 soak posture + Lever E filing: … investigate whether the soak bar measures the right thing … resolve the soak posture honestly — do NOT weaken the bar" | Phase 4 probe re-instrument + issue report | mapped — re-instrument shape ruled by CTO (see decision-challenges.md) |
| "file the epic's unfiled Lever E trackers: (a) required-check wall-clock p50/p90 per job in the weekly operator digest + a regression ratchet, (b) CI wall-clock added to the ship-skill pipeline tally" | Phase 4 filings | mapped |
| "the operator ruled 2026-11-01 to FUND affected-index completion … Post the decision on #10448 and file the index-completion scheduling issue naming the entry condition" | Phase 5 | mapped |
| "re-price PR #11718 merged; drift watch PR #11728 merged 2026-11-01" | context only — both already merged, cited in Research Insights | mapped — justification: named as context, not work |

### Plan-Item Provenance

| Plan item | Provenance |
|---|---|
| Phase 1 probe deadline re-scope | asked |
| Phase 2 #10781 verify+close | asked |
| Phase 3 K18 fix | asked |
| Phase 4 soak re-instrument + issue report + two Lever E filings | asked |
| Phase 5 #10448 comment + scheduling issue | asked |
| `ci-pr-affected-activation.md` time-arithmetic update | inferred — justification: the runbook documents the probe's budget arithmetic ("~480 s typical") which the Phase-1 change falsifies; the doc must not contradict the shipped code (constitution: canonicalize docs on what the code does) |
| epic #11556 comment ticking Lever E filing bullets | inferred — justification: the epic tracks lever filings as checklist items; leaving it stale re-files them next planning pass |

### Split Assessment

- Files to Edit: 7 (two probes + two test files + one hook lib + one hook suite + one runbook). Files to Create: 0.
- Recommendation: one PR — a single cohesive CI-machinery batch; the items share reviewers, CI surfaces and the follow-through runbook context; five small PRs would each pay the full required-check cost this epic exists to cut.

## User-Brand Impact

- **If this lands broken, the user experiences:** a required-check pipeline whose soak probes either never conclude (the #10865 window stalls the S4 program's PR3b gate) or certify the wrong thing (a #9323 probe that PASSES/FAILs on a methodology artifact misleads every future gating decision it informs); a merged wrong verdict propagates into the CI templates the plugin teaches to user repositories.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing user-visible — all artifacts are repo-internal CI machinery and issue ops. The privacy-sensitive surface is the operator digest (Lever E (a) filing), which already has its ADR-057 containment boundary; the filing names requirements inside that boundary, no new data egress.
- **Brand-survival threshold:** aggregate pattern (CI machinery quality the plugin teaches by example; the digest surface's privacy boundary stays intact — the filing does not widen the digest's read scope beyond Actions metadata).
- `threshold: aggregate pattern` — touches CI scripts and follow-through probes; no per-PR CPO sign-off.

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed
**Assessment:** Probe-budget re-scope and soak re-instrument are bounded shell changes on well-documented contracts; the exit-code and certification semantics are the load-bearing invariants. K18 fix is a one-line producer-stderr suppression consistent with the SIGPIPE learning class. No new substrate.

### Operations

**Status:** reviewed
**Assessment:** Lever E filings and #10448 record-keeping are ops-visible work; issue filings carry Fix-Size/User-Impact. digest privacy boundary (ADR-057) named in the filing requirements. deploy-script-tests is advisory — no merge-blocking posture change.

### Product/UX Gate

N/A — no UI-surface file in Files to Edit/Create (mechanical override did not fire; no user-facing pages/components/flows).

## Observability

```yaml
liveness_signal:    what: soak-verdict liveness of the two amended probes — their own stdout status lines (`window opened=… truncated=`; `qualifying_runs=… mean_runner_min=… realized_saving_min=…`) + sweeper exit-code comment cadence; cadence: nightly sweeper; alert_target: CANNOT ESTABLISH rendered on the tracker (existing); configured_in: scheduled-followthrough-sweeper.yml + sweep-followthroughs.sh
error_reporting:    destination: the trackers' sweeper comments (public status lines) + this PR's own checks; fail_loud: a probe that cannot decide exits 3 and the sweeper comments CANNOT ESTABLISH — after the fix a budget cut reports NOT YET with truncated=1 instead
failure_modes:      [{mode: GitHub p95 latency doubles → certified prefix shrinks each sweep, detection: `truncated=1 units_read<M` on the status line, alert_route: tracker comment}, {mode: artifact-read quota binds on #9323, detection: `quota: used_delta` vs `planned=` + NOT YET naming sampled evidence, alert_route: tracker comment}, {mode: deadline mis-scope → sweeper kill returns, detection: `TIMED OUT after 300s` sweeper log line, alert_route: tracker CANNOT ESTABLISH comment}]
logs:               where: sweeper run logs + probe status lines on the trackers; retention: workflow logs default
discoverability_test:
  command:          bash -c 'grep -n "SOAK_BUDGET_S\|FACTS_BUDGET" scripts/followthroughs/ratchet-observation-window-10865.sh | head -8'
  expected_output:  SOAK_BUDGET_S
```

## Guard Contract

### Guard 1 — probe-deadline enforcement (#10865 fix)

**Property.** The probe reaches its own verdict before the sweeper's 300 s kill — every read phase gates against `END = T0 + BUDGET`, never a per-phase epoch.

**Assembly.** The single dispatch/facts/listing chokepoints: the run-listing `while` loop, the `o_launched` deadline check in the read-dispatch loop, the `SECONDS - TF0` check in the facts loop, and `gh_get`'s `timeout` argument — four sites, all re-anchored to the one deadline. The verdict path (`nots` accumulation → exit 2) is downstream and must stay reachable on any cut.

**Mutation matrix.**

| Mutation | Expected |
|---|---|
| Facts-loop check re-anchored to `TF0` (own epoch) while reads consume the full budget | RED — suite row asserting the facts phase cannot start after the deadline |
| `timeout` on `gh_get` left at fixed 60 s while deadline has < 30 s remaining | RED — suite row asserting per-read timeout ≤ remaining window |
| Newest-10 merge_group extras removed from the budget exemption AND launched last | RED — the pause/defect classes lose newest queue state; suite asserts dispatch order preserved |
| Deadline check deleted from the read-dispatch loop (only listing gated) | RED — suite row: dispatch must cut at `END` even when listing is instant |
| Test seam `SOAK_BUDGET_S=270` honored but kill-side margin ignored (END set to 300 exactly) | RED — a `timeout -k 10 300` wrapper row asserting the probe exits before the wrapper |
| Must-PASS: `SOAK_PARALLEL=4` override still accepted within 1..8 validation | PASS — the seam's contract widens only the default |

### Guard 2 — realized-skip verdict honesty (#9323 fix)

**Property.** Arm (a)'s verdict reflects only the lever's realized saving — skip rows priced from committed durations, never whole-run drift and never absence-of-evidence.

**Assembly.** The qualifying-run loop's per-run realized-sum computation: artifact enumeration → TSV parse → `skip=relevance` match against the `--pr-gated`-derived battery set → price lookup → mean; plus the rate_limit precheck and the NOT YET arm on missing evidence.

**Mutation matrix.**

| Mutation | Expected |
|---|---|
| Battery set hardcoded instead of derived from `--pr-gated` call sites | RED — a suite row adding a synthetic gated battery must appear in the priced sum without a list edit |
| `skip=relevance` rows counted at price 0 vs priced from durations TSV | RED — fixture whose realized sum must equal the priced total, not row count |
| Missing/unparseable artifact treated as zero-saving evidence | RED — must yield NOT YET on that run, never drag the mean toward FAIL or PASS |
| Whole-run mean re-wired back as the verdict input | RED — suite asserting mean is printed informational-only and never reaches the verdict arithmetic |
| Must-PASS: a run where only heavy-group batteries declined (light leg artifact absent) | PASS — priced sum counts what declined; absence of an artifact is evidence-absent, not evidence-of-zero |

## Task Design

No new autonomous-task surface (no new workflow/cron/timer/daemon). Lever E filings specify requirements for issues' own pipelines — the digest-section and ratchet machinery land in those issues' plans, which will run this gate there.

## Architecture Decision (ADR/C4)

- **ADR:** no new ADR. The #9323 probe re-instrument is a measurement-instrument change under ADR-262's existing soak design — the work phase records the instrument rationale in the probe header + the issue report; ADR-262's Consequences already name the probe (amend one line there if the verdict formula description needs it). #10865's deadline model is a defect fix inside the ADR-276 PR3a amendment's already-ruled contract (the 30-day/close ceiling re-rule is a separate, later CTO step, unchanged).
- **C4 views:** enumeration performed — (a) external human actors: none new (issue comments are existing operator↔GitHub flow); (b) external systems: GitHub Actions/API (already modeled as the CI substrate the probes read), the private `jikig-ai/operator-digest` repo (Lever E filing references it as-is — no new edge created in this PR); (c) containers/data-stores: none new; (d) relationships: unchanged. Read `model.c4`/`views.c4`/`spec.c4` for these actors/systems — all already modeled; no `.c4` edit required. Conclusion: no C4 impact (supported by the enumeration above).

## Encryption Posture

Detection note: prose mentions "merge queue" and apt `Dir::Cache::archives` — neither introduces a persistent store nor a new connection; evaluated and discharged below.

```yaml
at_rest: none — no new persistent store (no volume/database/bucket/queue/cache/backup target/log sink is created; probes read GitHub Actions metadata and committed TSVs)
in_transit: none — no new cross-component or network connection (the amended probes reuse the repo's existing authenticated `gh api` reads over HTTPS with the same GH_TOKEN posture already declared in each probe header)
exception: absent — nothing plaintext, no cert_verification off
```

## GDPR / Compliance Gate

Not triggered — no regulated-data surfaces (no schemas, migrations, auth flows, API routes, `.sql`); none of the (a)-(d) expansion triggers (no new LLM processing of session data, no single-user-incident declaration, no cron reading learnings/specs, no new distribution surface — issue filings are internal).

## Test Scenarios

- **T1 (AC1/AC2):** stub-gh fixture in `ci-pr-affected-replay.test.sh`: a dispatch whose reads would overrun `SOAK_BUDGET_S` exits 2 naming `read budget ended`, `truncated=1`, under a `timeout -k 10` wrapper at the seam value — never rc 124; a facts-phase over-run fixture names the facts cut; `SOAK_NOW_EPOCH`/`SOAK_MAX_*` seams preserved.
- **T2 (AC3):** `gh run list --workflow infra-validation.yml --branch main` shows ≥3 consecutive green runs post-#11442 on a main tip containing the fix; this PR's own `deploy-script-tests` legs green.
- **T3 (AC4):** K18 battery row: a lexstub body that terminates immediately (never reads stdin) run in a loop (≥20 iterations) yields byte-exact `S=unavailable K=parse` with no stderr line; a static grep row asserts `printf '%s' "$cmd" 2>/dev/null |` in `ctr_collect`.
- **T4 (AC5):** `.test.sh` fixtures — synthesized run/artifact payloads: all-batteries-declined run prices to ~48.5 min → arm (a) satisfied direction; only-partial-decline run prices <20 → FAIL arm reachable; quota-capped sweep → NOT YET; merge-commit push run red → escape FAIL unchanged.
- **T5 (AC6/AC7):** `gh issue view` verifies the two Lever E issues and the scheduling issue exist with the named fields; `gh issue view 10448 --comments` shows the ruling comment.

## Sharp Edges

- Do NOT weaken the #9323 bar to force a pass — the re-instrumented arm is the honest isolation, and an under-20 realized saving still FAILs.
- Do NOT close #10865 — the soak window itself decides; this PR only fixes the probe's ability to reach a verdict.
- Do NOT post `Closes #11556` — the epic stays open (Lever F and remaining levers unfiled).
- Sweeper dry-run evidence for both amended probes is required before PR-ready (runbook §"dry-run the REAL sweeper on the branch").
- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6 — filled above.

## Enhancement Summary (soleur:deepen-plan, 2026-11-01)

**Mode:** sequential-fallback — this Devin subagent has no Agent/Task tool, so the
deepen fan-out (research agents, review panel, advisor consult) ran inline as
evidence-gathering + CTO Rule-interface rulings recorded in
`knowledge-base/project/specs/feat-one-shot-11556-epic-ci-time-batch/decision-challenges.md`.
`Reviewed-Coverage: sequential-fallback` — no independent agent review ran; the
review stage should still run `soleur:review` normally.

**Deepen findings applied:**

- Precedent-diff check (Phase 4.4): the `printf` producer fix mirrors the canonical
  SIGPIPE remediation (`workflow-issues/2026-10-02` learning); the probe deadline
  model follows the convention's own "bound its own reads" wording — no pattern
  divergence.
- #10781 re-scoped from "fix" to "verify-and-close" on discovered merged fixes —
  the largest premise correction of this pass; recorded in Premise Validation.
- #9323 fit math verified end-to-end (48.5 suite-min realized vs 20 bar) — the
  re-instrumented arm PASSES on evidence rather than being weakened.
- Scope Check restructured to the enforced schema; Encryption Posture given
  schema-shaped keys (detection discharges: "merge queue"/apt archives named in
  prose are not new stores/connections).
- Guard Contract lint green (2 guards, 11 mutation rows total); PAT gate clean;
  User-Brand (`aggregate pattern`) and Observability (5-field) sections verified;
  Task-Design skipped (no new autonomous surface); UI/Encryption halts
  non-triggering.

**New considerations discovered:** (a) the probe's budget model predates the
sweeper's per-probe cap (#11215) — the runbook's own "~480 s typical" paragraph
documents it; (b) #9323's `pull_requests` empty-on-merge quirk is already worked
around by head-branch resolution — artifact reads inherit its residual
(branch-reuse over/under-inclusion) unchanged.
