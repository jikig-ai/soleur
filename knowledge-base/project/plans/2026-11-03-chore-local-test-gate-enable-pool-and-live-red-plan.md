---
title: "chore(tests): enable the parallel pool for the ship-time affected gate and show reds at reap"
date: 2026-11-03
slug: local-test-gate-enable-pool-and-live-red
branch: feat-local-test-gate-speed
issue: 12013
closes: none (Ref #12013; the tracker stays open for the follow-up and the post-merge measurement)
type: chore
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(tests): enable the parallel pool for the ship-time affected gate and show reds at reap

## Overview

`soleur:ship` Phase 4 runs `plugins/soleur/scripts/affected-tests.sh`, which delegates to `scripts/test-all.sh --affected`. On 2026-11-03 that took more than 30 minutes for 166 suites. The runner already has a parallel pool (`--jobs` / `SOLEUR_TEST_JOBS`, PR #11282) that defaults to serial, and nothing in the ship path turns it on. This PR:

1. Turns the pool on (width 4) for the delegated `--affected` arm, locally only. `--full`, `CI`, and the runner's own default are unchanged.
2. Makes a red visible when it happens: the existing live `[run] <label> done (rc=N)` line gains the suite's wall time and, for a non-zero rc, a provisional marker. Ship's poll loop is told to read the log for it.
3. Gives `destroy-ask-mutation` and `image-cve-verdict` measured weight rows.
4. Records the change as an ADR-242 addendum and updates the parallel-mode runbook.

**Split out (operator decision after plan review, 2026-11-03):** re-pricing the seven slow edge-selected suites moves to a follow-up issue, triggered only if the measured parallel run is still over 10 minutes. See "Deferred".

Brainstorm: `knowledge-base/project/brainstorms/2026-11-03-local-test-gate-speed-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-local-test-gate-speed/spec.md`. Draft PR: #12014.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / spec) | Reality (verified on `main` `aa2e3aed00` and by the review panel) | Plan response |
|---|---|---|
| "The runner is effectively serial" is a runner limitation | The pool exists, opt-in, default serial (`_pj_resolve_run_mode`); ship never sets `SOLEUR_TEST_JOBS` | Enable at the delegation arm (Phase 1) |
| "Red is reported only at the end" | The pool already prints `[run] <label> done (rc=N)` at reap (three print sites in `scripts/test-all.sh`: `_pj_reap` twice, `_pj_drain`'s signal-window loop); `[ok]/[FAIL] (ms)` verdicts replay at drain. But ship polls only the rc file, so the live line is never read | Add wall time + provisional marker through one helper (Phase 2); tell ship's poll loop to read it (Phase 4) |
| "Per-suite TMPDIR is missing" | Collisions are prevented by resource tokens (`scripts/lib/test-suite-lanes.sh`) | No new mechanism unless the soak measures a collision |
| "Affected runs are not queued" | False: `tc_acquire "test-all"` is unconditional (FIFO ticket queue, ADR-133). A contended run queues, then holds the lock, so the pool engages after the wait | The 30-minute figure may include queue wait; AC1 separates it |
| Pool enabled "in ship Phase 4 dispatch" (CTO ruling) | Ship's dispatch command is pinned by `plugins/soleur/test/fullsuite-merge-gate.test.ts`, so an env prefix there would break the pin | Enable inside `affected-tests.sh` instead; this also gives `work` §9, review's lead gate, `grok-pre-push-gate.sh` and one-shot the pool. Deviation recorded in the ADR addendum with a caller-impact table |
| Nine slow suites run on every diff | Only `lint-shell-trace-credential-refusal` and `image-cve-verdict` are always-on; seven are edge-selected | Deferred (follow-up) |
| `ci-battery-gate-replay.sh` can replay edge selection | It replays the `--pr-gated` arrays in `test-relevance-paths.sh`, not `AFFECTED_*` edges and never calls `--print-selection` | The follow-up builds its own loop; not part of this PR |
| Issue point 6 (push before local) | Conflicts with ADR-276 (local-first is the chosen cheaper policy; draft `test` reads red by design) | Dropped; revisit trigger on #12013 |

## Research Insights

- **Premise validation.** Cited: #12013 (open), #11282 (merged 2026-10-27), #7376 (closed 2026-10-20), ADR-133/177/181/183/196/242/262/276, epic #11556, closed #9763. All hold. Collision pre-check: no open PR names #12013; one foreign worktree has live `test-all.sh` processes, which is a sibling test run, not a duplicate of this work.
- **Property List.** (P1) a typical single-feature gate finishes under 10 minutes on a loaded machine, or the PR records the measured time and cause; (P2) a red is visible when it happens, with suite name and wall time; (P3) no suite is lost, mis-attributed or run concurrently with a resource-conflicting suite, and no provisional line is mistaken for the verdict; (P4) `--full`, CI and non-Soleur repos behave exactly as before.
- **Cut List.** Result cache (rejected twice). Push-before-local (ADR-276). Unconditional CI-only skip (ADR-196, ADR-183). Fail-fast abort (ADR-177). New `[reaped-red]` prefix (a suffix on the existing line has no new consumer surface). Edge re-pricing (deferred). Stale-comment fix and ship-SKILL "how to force serial" prose (runner banner already says it). Adapter-arm test (structurally outside the runner block).
- **Value measurement (0.6c).** The expected gain is a forecast: the issue's 101 timed suites sum to about 1,530 s against a 244 s longest suite, bounding the speedup near 6x (archived full-battery baseline: 6.22x). Phase 1.2 replaces it with a measurement. A 60% bar on a 30-minute gate is not under 10 minutes, so the P1 projection is made from the Phase 0.2 always-on floor: P1 is met only if floor / width plus the longest edge suite fits the budget; otherwise the follow-up is triggered.
- **Width 4, not `auto`.** `auto` can resolve to 8 on a 16-core host shared with sibling worktrees; 4 is predictable. The Phase 1.2 pair informs whether to change it.
- **Learnings applied.** The 2026-09-30 brainstorm rejected `xargs -P`; the shipped pool is token-scheduled, so that rejection does not apply but its failure list (env leaks, `_site/` races, ports) is the soak checklist. Commit 37e49ee fixed an env leak of `TEST_GROUP` into nested suites; the same class applies to `SOLEUR_TEST_JOBS`. The 2026-10-15 learning: assert `AFFECTED_SUMMARY` in every measurement so a run in the wrong mode is not mistaken for a result.

## Scope Check

| Ask (operator, 2026-11-03) | Plan item |
|---|---|
| Enable the pool for affected runs | Phase 1 |
| Live red at reap, report not abort | Phase 2 + Phase 4.2 (poll loop) |
| Measured weights for `destroy-ask-mutation`, `image-cve-verdict` | Phase 3 |
| Re-price slow edge-selected suites | Deferred by operator decision after plan review; follow-up issue |
| Explain point 6; revisit if warranted | Done in brainstorm; trigger recorded (Phase 4.4) |
| Soak incl. `git-data-replication`; never skip legal-register lints; ADR-242 addendum | Phase 1.3, Phase 3.2, Phase 4.1 |

No `inferred` items. One PR: about three logic files plus data and docs.

## User-Brand Impact

- **If this lands broken, the user experiences:** a regression reaches `main` and then a Soleur user because the faster gate dropped, mis-ordered or mis-reported a failing suite, or an operator read a provisional line as a verdict.
- **If this leaks, the user's workflow is exposed via:** not a data exposure; the exposure is a weakened merge-quality signal. CI's required `test` context remains the merge gate, so a local miss costs a CI red, not a silent merge.
- **Brand-survival threshold:** single-user incident. CPO sign-off obtained at brainstorm (carry-forward; no customer-visible contract changes); `soleur:engineering:review:user-impact-reviewer` runs at review.

## Open Code-Review Overlap

- #7942 (mutation batteries named `*.mutation.sh` that run in no gate) touches `scripts/test-all.sh`. **Acknowledge:** different concern (suite naming), own cycle; remains open.

## Domain Review

**Domains relevant:** Engineering, Product, Legal

### Engineering
**Status:** reviewed
**Assessment:** CTO (brainstorm and plan review): pool first, report not abort, no cache, ordering change rejected, unconditional skip conflicts with ADR-196/183; Phase 3 to a follow-up; ship's poll loop must read the live line. Six-agent plan review applied (see Plan Review Disposition).

### Product
**Status:** reviewed
**Assessment:** CPO: p3, off the roadmap frontier, fold under #11556; user-facing contract for skipping/reordering belongs to #11556 Lever F. No user-facing contract changes here.

### Legal
**Status:** reviewed
**Assessment:** CLO: no legal implications. Constraint carried: `lint-legal-registers.sh` and `check-pa-22.sh` stay registered in `run_suite` lines and are never skipped; the breach register cites `grep -c 'run_suite "scripts/check-pa-22' scripts/test-all.sh` (expects 2).

No UI surface; no Product/UX Gate.

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-242 with a dated addendum: the delegated affected gate engages the opt-in pool at width 4 locally (never under `CI`); runner default stays serial; why it lives in `affected-tests.sh` (the ship dispatch is pinned) and which callers now get it (table below); the live `done` line is provisional, the drain verdict and exit code are authoritative; point 6 is not taken (ADR-276). Cites ADR-133 (lock precondition preserved), ADR-177 (signal-shaped is unresolved, not failed).

| Caller of `affected-tests.sh` | Effect |
|---|---|
| ship Phase 4 | pool engaged (the goal) |
| work §9 | pool engaged |
| review lead gate | pool engaged |
| `grok-pre-push-gate.sh` | pool engaged; verify it does not run other test work concurrently (Phase 1.3) |
| one-shot | pool engaged; its SKILL.md warning against running the runner concurrently with the gate still applies |

### C4 views
No C4 impact. Checked against all three model files: external human actors (none added), external systems/vendors (none), containers/data stores (none; a weights TSV is not a modeled store), actor-to-surface access relationships (none changed). Internal test-runner behavior only.

### Sequencing
Authored in this PR.

## Observability

```yaml
liveness_signal:
  what: "[parallel] mode engaged — width=4 on every local delegated affected run, or an announced [parallel] serial fallback — reason=<why>"
  cadence: per ship Phase 4 / work §9 run
  alert_target: none (local tool; read from the run log)
  configured_in: scripts/test-all.sh (_pj_resolve_run_mode) and plugins/soleur/scripts/affected-tests.sh
error_reporting:
  destination: stderr of the runner and the durable suite-timings.tsv (TEST_TIMING_LOG, on by default locally)
  fail_loud: a red prints at reap with wall time; the authoritative [FAIL] verdict and exit code follow at drain
failure_modes:
  - mode: pool not engaged (lock not held, CI, width 1, bash<5.1) so the gate silently stays slow
    detection: "[parallel] serial fallback — reason=" line; ship summary prints the mode
    alert_route: stderr / ship summary
  - mode: provisional live line read as the final verdict
    detection: marker text "provisional" on every non-zero live line; ship SKILL states only the exit code counts
    alert_route: documentation + contract test on the wording
  - mode: SOLEUR_TEST_JOBS leaks into a nested runner a suite spawns
    detection: contract test over nested-runner suites
    alert_route: failing scripts-shard test
logs:
  where: the per-run log written by ship's rc-file wrapper, plus suite-timings.tsv
  retention: local, existing TEST_TIMING_LOG behavior
discoverability_test:
  command: bash scripts/test-all.sh --print-selection
  expected_output: "AFFECTED_SUMMARY"
```

## Implementation Phases

### Phase 0 — Baseline (record, do not assert)

0.1 `bash scripts/test-all.sh --print-selection` on a clean branch: record `AFFECTED_SUMMARY` fields as observations (the always-on count drifts; do not hard-code 116).
0.2 With the timing log on, run the always-on set serial once (`SOLEUR_TEST_JOBS=1 bash scripts/test-all.sh --affected` on a docs-only diff) and keep `suite-timings.tsv`: this is the floor that feeds the P1 projection.

### Phase 1 — Enable the pool (FR1, TR1, TR3, TR4)

1.1 `plugins/soleur/scripts/affected-tests.sh`, runner-delegation arm, `--affected` only, and only when `CI` is unset: pass `SOLEUR_TEST_JOBS="${SOLEUR_TEST_JOBS:-4}"` in the environment of the `affected_bound bash "$RUNNER" "$_flag"` call only (not exported for the rest of the script). `--full`, `CI` set, and an explicit `SOLEUR_TEST_JOBS=1` stay as they were; document that `SOLEUR_TEST_JOBS=1` is the override (an operator `--jobs` flag cannot reach the runner through this script).
1.2 Nested runners: suites that re-invoke `test-all.sh` (`test-all-affected.test.sh`, `test-all-group-affected.test.sh`, and any other found by `git grep -l "test-all.sh" -- 'scripts/*.test.sh' 'plugins/soleur/test'`) must not inherit the width. Scrub it where they already scrub `TEST_GROUP` (commit 37e49ee shape); add a test that proves it.
1.3 Measure and soak (records in the PR body, no pass/fail threshold on live numbers): the same diff serial then default, `AFFECTED_SUMMARY` equal, `[parallel] mode engaged — width=4` present, `uptime` load noted, lock-queue wait separated from run time. Soak at most 2 parallel runs, run once in the background while Phases 2-4 proceed, diffing the `[ok]/[FAIL]` label set against serial and including `git-data-replication`. A suite red only under the pool is a missing lane token: add it with `lane_declare` and a cited reason (`scripts/lib/test-suite-lanes.sh`), do not quarantine. Add per-suite `TMPDIR` only if a shared-path collision is measured. Check `grok-pre-push-gate.sh` and one-shot do not run other test work beside the gate.
1.4 Tests first (`cq-write-failing-tests-before`), a new `plugins/soleur/test/affected-tests-pool-default.test.sh` using the stub-runner fixture pattern of `test-all-group-affected.test.sh` (stub `scripts/test-all.sh` registering `--print-selection` and dumping its env): (a) `--affected` local → `SOLEUR_TEST_JOBS=4`; (b) explicit `=1` respected; (c) `--full` → unset; (d) `CI` set → unset; (e) the value is absent from the script's own later environment (not exported globally); (f) exit-code map under the pool: runner rc 3 → 1, 2/4 → 4, 124 → deferral/1 as today. Mutations: delete the default → (a) red; drop the `--full` guard → (c) red; drop the `CI` guard → (d) red; make it a global export → (e) red. Register the file in `scripts/test-all.sh` for `lint-orphan-test-suites`.
1.5 Deterministic benchmark: extend `scripts/test-all-parallel-benchmark.test.sh` (stub suites with fixed sleeps) to assert the pool beats serial by a stated margin on non-conflicting stubs; this, not a live host, is the pre-merge speed claim.

### Phase 2 — Make a red visible at reap (FR2)

2.1 In `scripts/test-all.sh`, add one helper (for example `_pj_fmt_done`) used by all three `[run] <label> done` print sites (`_pj_reap` wait path, `_pj_reap` sidecar-rc path, `_pj_drain` signal-window loop). Output: `[run] <label> done (rc=N, <ms>ms)`; for rc 128+n append ` — signal-shaped, unresolved until drain`, for any other non-zero rc append ` — provisional, verdict at drain`. `[ok]/[FAIL]/[KILLED]` text is untouched. Wall time from `_pj_start`/`_pj_end` (`EPOCHREALTIME`).
2.2 Tests first, extending `scripts/test-all-parallel-scheduler.test.sh`: a pool run with one passing and one failing stub shows both live lines with numeric ms, the failing one marked provisional, `^\[FAIL\]` count unchanged (exactly one), and `scripts/test-all-parallel-contention.test.sh`'s `^\[run\] (\S+) (started|done)` parse and `battery-refusal-wait.sh`'s `\[FAIL\]|\[KILLED\]` grep produce the same results. Mutations: drop the helper at one site → red; strip the provisional marker → red; rename the line prefix → the consumer test goes red.

### Phase 3 — Measured weights (FR3, TR2)

3.1 Add measured weight rows for `apps/web-platform/test/destroy-ask-mutation` (no row exists) and `scripts/image-cve-verdict` (1223 ms floor row today; the `-consumers` row is a separate suite and is not touched). `scripts/suite-durations.tsv` is generated: use the documented regeneration path (`regenerate-shard-manifest.py`, with the growth-acknowledgement flow for the digest stamp), not a hand edit. Keep `scripts/test-all-corpus-weight-budget.test.sh` green; if a measured weight exceeds the cap, add a `scripts/suite-weight-exemptions.tsv` row with a `#NNN` reason.
3.2 Guard: assert `lint-legal-registers` and `check-pa-22` remain registered, and `grep -c 'run_suite "scripts/check-pa-22' scripts/test-all.sh` is 2; add the labels to an existing selection test if nothing pins them.

### Phase 4 — Record and close the loop

4.1 ADR-242 addendum (see Architecture Decision).
4.2 `plugins/soleur/skills/ship/SKILL.md` Phase 4: one sentence that the delegated affected run engages the pool, that the 30-second rc-file poll must also grep the log for `^\[run\] .* done \(rc=[1-9]` and surface it immediately, and that the provisional line is not the verdict (only the exit code and the final `affected-tests:` line count). Do not alter the pinned dispatch command; run `plugins/soleur/test/fullsuite-merge-gate.test.ts`.
4.3 Update `knowledge-base/engineering/operations/runbooks/local-gate-parallel-mode.md`: the "while the #7376 diagnosis is open" default rationale (closed 2026-10-20), the "everyday local affected run → nothing" row, and the `[run] … done (rc=N)` format.
4.4 Comment on #12013 with the measured numbers and the follow-up issue number; the revisit trigger for the dropped points is already recorded there.
4.5 File the deferred follow-up (below) in this PR's session.

## Deferred

- **Edge re-pricing** (the seven slow edge-selected suites; selection-rate replay with its own loop; high-churn `scripts/lib/test-affected-paths.sh`): tracked as #12025, triggered only if the Phase 1.3 measured parallel run is still over 10 minutes. Milestone and body satisfy the filing gate (`Mandated-By: wg-when-deferring-a-capability-create-a`).

## Files to Edit

- `plugins/soleur/scripts/affected-tests.sh`
- `scripts/test-all.sh` (helper + three print sites + new suite registration)
- `scripts/test-all-parallel-scheduler.test.sh`, `scripts/test-all-parallel-benchmark.test.sh`
- nested-runner suites that need the scrub (found in Phase 1.2)
- `scripts/suite-durations.tsv` (via regeneration), `scripts/suite-weight-exemptions.tsv` (only if needed)
- `scripts/lib/test-suite-lanes.sh` (only if the soak finds a missing token)
- `plugins/soleur/skills/ship/SKILL.md`
- `knowledge-base/engineering/operations/runbooks/local-gate-parallel-mode.md`
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`

## Files to Create

- `plugins/soleur/test/affected-tests-pool-default.test.sh`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: Deterministic speed claim: the benchmark suite shows the pool beats serial on non-conflicting stub suites. The live host pair (serial vs default, same diff, equal `AFFECTED_SUMMARY`, `[parallel] mode engaged — width=4` present, lock-queue wait separated from run time, `uptime` noted) is recorded in the PR body with the Phase 0.2 floor and the P1 projection, with no live pass/fail threshold.
- [ ] AC2: The soak (at most 2 parallel runs) yields the same `[ok]/[FAIL]` label set as serial, including `git-data-replication`, with the mode-engaged line asserted, not just an announced fallback; any divergence is root-caused (a token added or documented).
- [ ] AC3: Every non-zero live `done` line carries wall time and the provisional/signal-shaped marker, `^\[FAIL\]` output and the three existing consumers are unchanged (tests pinned with mutation rows), and the ship SKILL sentence states the exit code is authoritative.
- [ ] AC4: `--full`, `CI` set, explicit `SOLEUR_TEST_JOBS=1`, and nested runner suites behave exactly as before; the rc map (3→1, 2/4→4, 124→deferral) is unchanged under the pool (tests pinned).
- [ ] AC5: Both weight rows exist via the generator; the weight-budget ratchet, `fullsuite-merge-gate.test.ts`, `lint-orphan-test-suites` and `grep -c 'run_suite "scripts/check-pa-22' scripts/test-all.sh` (2) are green; `bash scripts/test-all.sh --affected` passes on this branch through the real dispatch.
- [ ] AC6: ADR-242 addendum, runbook update and ship SKILL sentence committed; the follow-up issue is filed and linked from #12013.

### Post-merge (operator)

- [ ] AC7: On the next two single-feature PRs the ship Phase 4 gate finishes under 10 minutes or the PR test plan records the measured time and cause. The implementing session posts the first measurement on #12013; if neither holds after two PRs, the follow-up is triggered and the point-6 question is reopened per the recorded trigger.

## Test Scenarios

- Local `--affected`, no env → the runner sees `SOLEUR_TEST_JOBS=4`; `SOLEUR_TEST_JOBS=1` → serial, no banner; `--full` and `CI` set → no injected value.
- Pool run with one red stub → live `done (rc=1, Nms) — provisional` before the drain, exactly one `[FAIL]` at drain, non-zero exit.
- Pool run with a signal-killed stub → live line marked signal-shaped/unresolved; runner exits 3; `affected-tests.sh` maps it to 1.
- Lock not held → announced serial fallback, behavior unchanged.
- A suite that re-invokes `test-all.sh` does not inherit the width.

## Risks and Sharp Edges

- **Pool defect under load (highest).** #7376 was a flake in an earlier parallel runner and this pool is under two weeks old. Mitigation: the soak, the `SOLEUR_TEST_JOBS=1` override, and the pool's own serial fallbacks. If the soak fails for a reason other than a missing token, stop and file a tracker rather than ship the enablement.
- **The 30-minute figure may include lock-queue wait**, which the pool cannot shorten; AC1 separates the two so the result is not over-claimed.
- **A provisional line mistaken for the verdict.** Marked in the text and in the ship SKILL sentence; only the exit code counts.
- **`affected-tests.sh` is a customer-facing script.** The default is applied only when the Soleur repo runner arm is taken (`scripts/test-all.sh` registers `--print-selection`) and `CI` is unset; a customer runner that does not read `SOLEUR_TEST_JOBS` ignores it.
- **Anchors are symbols, not line numbers** (`_pj_reap`, `_pj_drain`, `_pj_resolve_run_mode`); line numbers cited in review drift.
- An empty or placeholder `## User-Brand Impact` fails deepen-plan Phase 4.6; this one is filled.

## Plan Review Disposition (2026-11-03, 6 agents: DHH, Kieran, simplicity, architecture, spec-flow, CTO)

Applied (mechanical): gate on `CI` unset; scope env to the runner call; nested-runner scrub; one helper for three print sites; extend the existing `done` line instead of a new prefix; provisional marker (ADR-177); ship poll loop reads the log; runbook added; deterministic ACs and a benchmark suite; separate queue wait from run time; named test file and fixture pattern; weight rows via the generator; cut the adapter-arm test, the stale-comment fix and the C4 parity run; width 4 justified; baseline recorded not asserted. Applied (operator decision): Phase 3 edge re-pricing deferred to a follow-up.
