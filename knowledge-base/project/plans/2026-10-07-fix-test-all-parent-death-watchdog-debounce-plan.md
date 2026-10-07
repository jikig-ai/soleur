---
title: "fix: test-all parent-death watchdog false-fires under main-health-monitor — debounce the liveness poll (#9686)"
type: fix
date: 2026-10-07
slug: fix-test-all-parent-death-watchdog-debounce
branch: feat-one-shot-9686-watchdog-parent-death
issue: 9686
closes: 9686
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix: test-all parent-death watchdog false-fires under main-health-monitor — debounce the liveness poll (#9686)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed; no spec.md exists — no brainstorm ran on this branch).

## Overview

The every-6h `main-health-monitor` run reports `tests=failure` on every recent run: `scripts/test-all.sh`'s `_RUN_WD` parent-death watchdog (the #8993 orphan-guard, added in PR #9034) declares the parent gone on a **single** anomalous poll — `kill -0` ESRCH, `stat==Z*`, or an `lstart` mismatch — and SIGTERMs a healthy run mid-suite. Four consecutive monitor runs show a `[KILLED]` suite at 68–413s elapsed with `exit=143` preceded by `ERROR: parent process gone`, while the step's parent shell demonstrably survived. The fix debounces the verdict: require N>=3 **consecutive** failed polls (at `_RUN_WD_POLL_S=1`) before the terminate path, re-verify parent `lstart` identity on the deciding poll, and emit a per-poll diagnostic naming the failed leg. Real orphaning still reaps within ~N+grace seconds; a transient `kill -0`/`ps` anomaly under fork churn no longer kills a run.

## Problem Statement / Motivation

Issue #9686 (priority/p2-medium): `main-health-monitor` (`.github/workflows/main-health-monitor.yml`, cron `0 */6 * * *`) has reported `tests=failure` on the last four runs — each a `[KILLED]` suite (SIGTERM, exit 143) preceded by the watchdog's `ERROR: parent process gone — orphaned test-all run terminating itself and in-flight suite children (#8993)` line. Run 37549587025 shows the sequence at 01:51:48Z: `parent process gone` → `Terminated` → `[KILLED]` → next-suite banner dispatched inside the TERM→grace→KILL window → step ends (`tests_elapsed_s=5673`). The parent (the step's `bash -e` shell) was alive — the step kept logging and exited normally.

Ruled out by the issue (verified against code in this session): not a suite hang (the killed suite runs >320s cleanly in isolation), not a suite-internal `timeout` (the 203s kill matches no `timeout 400`/`timeout 120`/`timeout 60` arm), not the 110-minute step ceiling (job conclusion would be `cancelled`).

Current code (anchors, `scripts/test-all.sh`): inside the `_RUN_WD` subshell armed before `tc_acquire "test-all"`, the poll loop does `kill -0 "$_RUN_WD_PARENT_PID" || break`, `[[ "$(ps -o stat= -p …)" == Z* ]] && break`, and `[[ -n "$_wd_plstart" && "$_wd_plstart" != "$_RUN_WD_PARENT_LSTART" ]] && break`. Any single failed poll exits the loop into the reap path. Under the fork churn this monitor run generates (one suite measured `user 2m18, sys 3m7`), a transient anomaly reads as death.

Impact: every 6h health check reports `tests=failure`, keeps the Sentry `main-health-monitor` unresolved, and appends to tracker #9457 — masking any real main regression behind a permanently red monitor.

## Proposed Solution

Debounce the `_RUN_WD` parent-liveness verdict inside the existing watchdog subshell (anchor: the `# --- Orphan watchdog, normal run path (#8993)` block, `_RUN_WD_TOP_PID=$$` … `_RUN_WD_PID=$!`):

1. **New tunable beside `_RUN_WD_POLL_S`:** `_RUN_WD_FAILS_N="${SOLEUR_TEST_ALL_WD_FAILS_N:-3}"`, parsed with the identical idiom as `_RUN_WD_POLL_S` — `[[ "$_RUN_WD_FAILS_N" =~ ^[0-9]+$ ]] && (( 10#$_RUN_WD_FAILS_N >= 1 )) || _RUN_WD_FAILS_N=3`. Floor 1 preserves the pre-fix semantics for tests; `08`-style octal traps and `0` fall back to 3.
2. **Consecutive-failure counter.** Replace the three `break`-on-first-anomaly legs with a per-poll verdict `_wd_bad` (one verdict per poll — a poll fails if ANY leg fails) plus `_wd_fails` counter: increment on a failed poll, reset to 0 on a healthy poll. `break` only when `_wd_fails >= _RUN_WD_FAILS_N`.
3. **Deciding-poll identity re-verify.** When `_wd_fails` reaches the threshold, run one extra fresh probe of the parent — `kill -0` + `stat!=Z*` + (when a baseline was captured) `lstart` equality — *before* breaking. A parent that reads alive-and-same-identity on the deciding probe resets `_wd_fails` and continues; only a still-failed probe `break`s. This is the issue's "re-verify lstart identity on the last poll rather than any single sampled mismatch" and closes the residual window between the Nth sample and the reap.
4. **Per-failure diagnostic.** On each failed poll: `printf 'WARN: parent-liveness poll failed (leg=%s, %s/%s consecutive) (#9686)\n' … >&2 || true` naming the leg (`kill0` / `zombie` / `lstart`). The incident's diagnostic gap was that a false-fire leaves zero evidence of which leg tripped; this line makes the next occurrence self-describing and is also the observable the new tests assert.
5. **Runner-death leg, same discipline (inferred scope — see Scope Check).** The `kill -0 "$_RUN_WD_TOP_PID"` runner-liveness check sits one line above the parent check and has the identical false-fire blast radius: a transient ESRCH on a live runner reaps its healthy in-flight suite children and exits — the same incident signature. Apply the same consecutive-failure counter (`_wd_top_fails`) before the reap-and-exit arm. A genuinely dead runner still gets reaped within ~N polls.
6. **Header comment update.** Extend the block comment (currently documents single-poll semantics: "A zombie or reparented-dead parent fires the same way as a dead one") to state the debounce contract: N consecutive failed polls, per-leg WARN diagnostic, deciding-poll identity re-verify; cite `#9686` beside `#8993`.

**Explicitly unchanged** (pins in the sibling suite depend on each): the terminate path's order (children TERM → grace → KILL → runner TERM → grace → KILL), the `ERROR: parent process gone` message text verbatim (consumed by `plugins/soleur/test/main-health-monitor-workflow.test.sh` fixtures and the monitor's issue-body classifier), the `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1` opt-out banner, `_run_wd_disarm`, and the runner-identity re-check before the kill. The enumerate watchdog `_ENUM_WATCHDOG` is out of scope — it watches the runner itself; a false poll there only exits the watcher early (lost coverage), never kills.

## Technical Considerations

- **`set -euo pipefail` (scripts/test-all.sh:2) propagates into the watchdog `( … ) &` subshell.** Counter increments must use `_wd_fails=$(( _wd_fails + 1 ))` (assignment) — a bare `(( _wd_fails++ ))` returns status 1 when the result is 0 and would abort the subshell. Verdict tests must sit inside `if`/`||`/`&&` compound forms, never as bare statements. `_wd_fails`/`_wd_bad`/`_wd_top_fails` are initialized inside the subshell before the loop (`set -u` safety).
- **bash 3.2 target (stock macOS).** No associative arrays, no `$BASHPID` (the existing `_wd_self="$(bash -c 'echo "$PPID"')"` idiom is the portable spelling — reused unchanged).
- **Splice-window discipline.** The watchdog block lives BEFORE `tc_acquire "test-all"` — outside the region `test-all-killed-classification.test.sh`, `test-all-runtime-ceiling.test.sh`, and `test-all-orphan-log-retention.test.sh` splice out when building sandbox runners. New code inside the watchdog block is exercised verbatim by sandbox copies; conversely NO new top-level state may be added inside the spliced region (it would be absent under `set -u` in sandbox runs).
- **Timing math.** Detection of real parent death moves from ~1 poll to ~N polls: worst case `N × (_RUN_WD_POLL_S + probe)` ≈ 3s at defaults, then the unchanged TERM→grace(3s)→KILL→TERM→grace(5s)→KILL reap (~8–11s). The existing B1 arm's 12s post-kill deadline becomes marginal; pin `SOLEUR_TEST_ALL_WD_FAILS_N=1` on B1 (keeps its timing contract AND proves the knob's floor) and add a default-N real-death arm with a ~25s deadline.
- **Test seam for transient anomalies.** `kill -0` is a bash builtin and cannot be shimmed; `ps` resolves via `PATH` at every call inside the watchdog subshell, so a `ps` shim directory prepended to `PATH` for the sandbox run can inject a one-shot `Z` stat answer or a forged `lstart` for the parent pid (marker-file armed, keyed on the wrapper pid exported as an env var). The shim passes every other invocation through to the real binary (`command -v ps` resolved before the prepend). The `stat=` leg is safe to trip on the first matching call (arm-time never calls `stat=`); the `lstart` leg must trip on the *second* matching call (the first is the arm-time baseline capture, which must stay truthful).
- **Uniqueness-asserted anchors.** `tc_acquire "test-all"` and the epilogue call are uniqueness-asserted by sandbox builders — comments inside the watchdog block must not quote either verbatim. Anchor citations in new comments use symbol names (`_RUN_WD_PARENT_PID`, `_wd_plstart`), not line numbers.
- **Fixture-baseline coupling.** `plugins/soleur/test/fixture-relative-assert.baseline.txt` pins a count of `3` for `scripts/test-all-orphan-log-retention.test.sh`. If the new arms introduce relative-operand fixture writes matching that scanner's rules, regenerate with `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` — do not hand-edit.
- **Generated TSVs.** `scripts/suite-durations.tsv` / `scripts/suite-shard-legs.tsv` are `regenerate-shard-manifest.py` output — never hand-edited (scripts/test-all.sh:4778). The new followthrough suite gets a `run_suite` line; its TSV rows regenerate in the next manifest pass (absent row falls back to `default-weight-ms` — verify at work time that no freshness gate reds on a missing row).
- **Suite runtime growth.** New live-process arms add ~15–25s to `test-all-orphan-log-retention` (currently ~3s measured). Acceptable inside its leg budget; the `measured` duration row drifts until the next manifest regeneration — recorded, not blocking.

## Implementation Phases

Phase ordering follows `cq-write-failing-tests-before`: Phase 1 lands the new assertions against the CURRENT single-poll code — the transient-shim, non-consecutive, and N-then-recover arms MUST be red before the fix; sustained/real-death arms stay green (they pin behavior that must not regress). Phase 2 then implements the debounce.

### Phase 1 — Test coverage first (`scripts/test-all-orphan-log-retention.test.sh`) — RED

1.1. Structural pins: `_RUN_WD_FAILS_N` parsed once with the numeric-floor idiom; `_wd_fails` counter present in `wd_block`; the parent legs contain NO remaining `|| break`/`&& break` forms (the three old lines are gone); the counter-reset-on-healthy-poll line exists; the WARN diagnostic line exists. (Red pre-fix: none of these exist yet.)
1.2. Pin `SOLEUR_TEST_ALL_WD_FAILS_N=1` on the existing B1 real-parent-death arm (preserves its 12s deadline semantics; proves floor=1 restores single-poll behavior — green both pre- and post-fix).
1.3. New arm — real parent death under default N=3 still terminates (deadline ~25s), runner AND suite children reaped, `parent process gone` line printed (green pre-fix, stays green).
1.4. New arm — transient zombie-stat does NOT fire: `ps` PATH-shim returns `Z` once for the parent's `stat=` poll, then passes through; run completes, no `parent process gone`, rc=0. **Anti-vacuity:** the arm asserts the shim's injection marker file exists post-run — a shim that never fired proves nothing. (RED pre-fix: current code fires on the single anomaly.)
1.5. New arm — transient forged `lstart` does NOT fire: shim returns a wrong lstart on the SECOND `lstart=` call for the parent pid; run completes. Same marker-file anti-vacuity assertion. (RED pre-fix.)
1.6. New arm — non-consecutive failures never accumulate: shim fails the parent `stat=` poll on alternating calls (counter-file modulo); run completes, no fire. This is the consecutive-vs-cumulative anti-vacuity arm — a cumulative counter reds it. (RED pre-fix.)
1.7. New arm — sustained `Z` stat answers DO fire after >=N polls: the zombie leg still terminates the run under debounce (equivalent-to-real-death path through the counter). (Green pre-fix — single failure suffices today; keeps pinning the must-fire direction.)
1.8. New arm — deciding-poll re-verify aborts a recovered fire: shim fails the parent's `stat=` poll on exactly the first N matching calls then passes through; the correct implementation's deciding-probe reads call N+1 healthy and does NOT fire — under a threshold-`break`-without-reverify mutant this arm reds. (RED pre-fix.)
1.9. Run the suite against the CURRENT `scripts/test-all.sh` — arms 1.4/1.5/1.6/1.8 MUST be red; if they are green the shim harness is vacuous and must be fixed before proceeding.
1.10. If `fixture-relative-assert` reds on new assertion shapes, regenerate its baseline via its `--write-baseline` mode (never hand-edit).

### Phase 2 — Debounce the `_RUN_WD` verdict (`scripts/test-all.sh`) — GREEN

2.1. Add `_RUN_WD_FAILS_N` declaration + parse directly beside the `_RUN_WD_POLL_S` parse (same `=~ ^[0-9]+$` + `10#` + `>= 1` idiom, default `3`).
2.2. Inside the watchdog subshell: initialize `_wd_fails=0` and `_wd_top_fails=0` before the `while :; do`.
2.3. Convert the runner-liveness check to a counted verdict: `kill -0 "$_RUN_WD_TOP_PID"` failure increments `_wd_top_fails`; reap-and-exit only at `>= _RUN_WD_FAILS_N`; success resets `_wd_top_fails=0`.
2.4. Convert the three parent legs to a single per-poll `_wd_bad` verdict recording the failing leg name; on `_wd_bad`: increment `_wd_fails`, print the WARN diagnostic, and at threshold run the deciding-poll re-verify (fresh `kill -0` + `stat` + `lstart`); break only when the re-verify still fails. On a healthy poll: `_wd_fails=0`.
2.5. Update the block header comment to state the debounce contract (N consecutive, WARN per failure, deciding-poll re-verify); cite `#9686`.
2.6. Leave terminate path, message text, opt-out banner, disarm, and runner-identity re-check byte-identical.
2.7. `bash scripts/test-all-orphan-log-retention.test.sh` all green; `bash -n` clean; `bash scripts/test-all-killed-classification.test.sh` and `bash scripts/test-all-runtime-ceiling.test.sh` still green (splice-window regression check).

### Phase 3 — Soak follow-through enrollment

3.1. Create `scripts/followthroughs/watchdog-debounce-soak-9686.sh`: detect-only probe (exit-code vocabulary per `scripts/followthroughs/watchdog-arm-soak-9237.sh` — `2` NOT YET / `3` CANNOT ESTABLISH / `5` ACTION REQUIRED; never `0`/`1`) that counts `main-health-monitor` runs completed after this PR's merge SHA lands and reports how many contain a `parent process gone`/`[KILLED]` line. Clean verdict = two consecutive post-merge runs with zero watchdog kills. **Proof-by-absence discipline:** absence of the watchdog line is only evidence in a run where the emitter was armed — the probe MUST count only runs whose tests step actually dispatched `bash scripts/test-all.sh` (verifiable via `gh run view <id> --log` containing the run's suite banner/`=== N suites` marker); a run that never reached the tests step is excluded from the denominator, not counted as clean.
3.2. Create `scripts/followthroughs/watchdog-debounce-soak-9686.test.sh` (sibling convention) and register it via an explicit `run_suite "scripts/watchdog-debounce-soak-9686" bash scripts/followthroughs/watchdog-debounce-soak-9686.test.sh` line beside the other followthrough registrations (`scripts/followthroughs/*.test.sh` is NOT in SUITE_GLOBS — an unregistered suite runs in zero runners).
3.3. PR body / issue tracker comment carries the `<!-- soleur:followthrough script=scripts/followthroughs/watchdog-debounce-soak-9686.sh earliest=<merge+1d> secrets=GH_TOKEN -->` directive and the `follow-through` label on #9686.

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator sees `main-health-monitor` continue reporting `tests=failure` (false-fire survives) OR — the worse arm — a debounce regression that never fires lets a genuinely orphaned run hold the repo flock again, re-opening the #8993 incident class where sibling worktree gates serialize behind a dead run.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no data or money surface — the blast radius is CI signal integrity (masked real regressions) and the repo-wide advisory lock.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the diff touches only CI test-runner machinery (`scripts/test-all.sh`, its sibling test, a followthrough probe) — no user-facing surface, no credentials, no data store; the worst user-visible outcome is a continued red internal monitor, an aggregate-quality concern, not a single-user incident.

## Observability

```yaml
liveness_signal:
  what: "main-health-monitor workflow run verdict (tests= pass/fail) + per-run absence of the `ERROR: parent process gone` watchdog line"
  cadence: "every 6h (cron `0 */6 * * *`)"
  alert_target: "Sentry `main-health-monitor` issue + tracker #9457 comment append"
  configured_in: ".github/workflows/main-health-monitor.yml"

error_reporting:
  destination: "workflow step log + appended comment on #9457"
  fail_loud: "watchdog fires only after N consecutive failed polls and emits `WARN: parent-liveness poll failed (leg=…, k/N consecutive) (#9686)` per failure, then the unchanged `ERROR: parent process gone` line on fire"

failure_modes:
  - mode: "Transient poll anomaly false-fire (the #9686 class)"
    detection: "a lone WARN line with no following ERROR/fire line — the debounce absorbed it; counted via the Phase-3 soak probe"
    alert_route: "followthrough probe verdict + #9457 comment stream"
  - mode: "Debounce regression — real orphan never reaped (flock held, #8993 class)"
    detection: "Part-B arms in scripts/test-all-orphan-log-retention.test.sh (real parent death under both N=1 and default N=3) + sibling worktree lock starvation reported by tc_acquire contention lines"
    alert_route: "red suite in test-all / PR gate"
  - mode: "Fire path reordered (children not killed before runner)"
    detection: "existing structural pin — child-TERM before runner-TERM inside wd_block"
    alert_route: "red suite in test-all / PR gate"

logs:
  where: "workflow step output (gh run view <id> --log) + durable suite logs under SOLEUR_TEST_ALL_LOG_DIR"
  retention: "GitHub run-log retention; durable suite logs age-reaped at 14d (#9117)"

discoverability_test:
  command: "grep -q 'SOLEUR_TEST_ALL_WD_FAILS_N' scripts/test-all.sh && printf 'ok\\n'"
  expected_output: "ok"
```

## Hypotheses

The Phase-1.4 network-outage gate fired mechanically on the substring `timeout` (the issue's ruled-out section names `timeout 400`/`timeout-minutes: 110`). The L3–L7 probes are not applicable and are recorded as checked-off-by-shape rather than executed:

- **L3 firewall allow-list:** not applicable — the symptom is a local in-process SIGTERM emitted by the runner's own watchdog line in the step log, not a connectivity failure; no host, port, or egress path is implicated.
- **L3 DNS/routing:** not applicable — same reason; nothing in the incident involves name resolution.
- **L7 TLS/proxy:** not applicable — no HTTPS path in the failure.
- **Service-layer:** the hypothesis set is the one the issue already narrowed: (a) single-poll parent-liveness verdict false-fires under fork churn — *confirmed by code read* (three `break`-on-first-failure legs, no consecutive requirement); (b) suite-internal timeout — ruled out (issue measured 203s vs arms at 400/120/60s); (c) step ceiling — ruled out (110m vs ~95m kill, conclusion not `cancelled`). The plan implements the fix for (a).

## Research Insights

- **Premise validation (Phase 0.6):** #9686 OPEN (title/labels verified via `gh issue view`). #8993 CLOSED 2026-09-28 — predecessor/origin issue, context only, not a work target. #9457 OPEN — the health-monitor tracker receiving the false-fire comments. `scripts/test-all.sh` `_RUN_WD` block exists on `origin/main` at ~4303–4393 — the issue's "~3806" line cite has drifted; code confirmed present with exactly the single-failure `break` shape hypothesized. ADR corpus grep (`watchdog|orphan|parent-death|debounce` over `knowledge-base/engineering/architecture/decisions/`) surfaces no ADR governing poll-verdict debouncing; ADR-133 covers the test-all tmpfs/contention substrate only — no rejected-alternative conflict.
- **Mechanism minimality (Phase 0.6b):** Property list — (P1) one transient failed parent-liveness poll must not terminate a run; (P2) a genuinely-dead parent must still reap within a bounded window; (P3) pid-reuse protection (lstart identity) is retained and applied to the deciding verdict; (P4) a false-fire leaves diagnostic evidence of which leg tripped. Mechanisms named in the ask: consecutive-failure counter (P1, P2 — no existing mechanism covers it; grep of `scripts/lib/` and `test-all.sh` finds no debounce/consecutive-failure helper), deciding-poll lstart re-verify (P3 refinement — currently any single sampled mismatch breaks). **Cut list:** none — every proposed mechanism buys an uncovered property. The per-leg WARN diagnostic (P4) is planner-added; the incident was undiagnosable to leg-level from logs.
- **Key file paths:** `scripts/test-all.sh` watchdog subshell — arm at `_RUN_WD_PID=$!` before `tc_acquire "test-all"`; poll legs `kill -0`/`stat==Z*`/`lstart` inside `while :; do`; fire path after loop. Tests: `scripts/test-all-orphan-log-retention.test.sh` (sandbox splice builder `build_sandbox`, live-signal arms Part A/B, structural pins on `wd_block` extracted via `sed -n '/_RUN_WD_TOP_PID=\$\$/,/^fi$/p'`). Consumers of the fire line: `plugins/soleur/test/main-health-monitor-workflow.test.sh` fixture strings; `.github/workflows/main-health-monitor.yml` issue-body classifier (~line 580).
- **Institutional learnings applied:**
  - `2026-09-28-a-watchdogs-own-teardown-order-decides-whether-its-escalation-fires.md` (issue #8993 / PR #9034): kill order IS the mechanism — children escalate to completion before the runner is signaled; child lists are snapshot discipline (`_wd_descendants` transitive walk). The debounce must not disturb this ordering — all changes stay inside the poll loop, before the unchanged reap.
  - Same learning, fixture note: `( bash script ) &` gets bash's exec optimization — a wrapping subshell needs a trailing `wait` to remain a distinct killable parent (B1's `WRAP_PID` shape, reused for the new arms).
  - `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`: monitor verdict parsing is strict — keep the `parent process gone` line text byte-identical.
- **Functional overlap check (Phase 1.5b):** assessed inline (no Task subagent in this harness) — the feature is a modification to repo-internal bash supervision machinery; no community skill/agent overlaps a `_RUN_WD` debounce. Skipped.
- **Community discovery (Phase 1.5):** skipped — bash/proc-supervision stack is deeply covered in-repo (the #8993 watchdog + its suite are the prior art).
- **External research (Phase 1.6):** skipped — the issue specifies the fix direction, the code site is identified, and consecutive-failure debouncing is a settled pattern with no external-API surface; strong local context.
- **Conventions captured:** `set -euo pipefail` arithmetic-safety idioms; `10#` numeric parse with floor-and-default; `SOLEUR_TEST_ALL_*` env-knob naming; `run_suite` explicit registration for `scripts/followthroughs/*.test.sh`; generated TSVs never hand-edited; baseline files regenerated via `--write-baseline` modes.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| Watchdog check at "scripts/test-all.sh ~3806" | Block sits at ~4303–4393 on origin/main (`66717b6f7f`) — drifted ~500 lines | Anchor on symbols (`_RUN_WD_PARENT_PID`, `_wd_plstart`, `_RUN_WD_TOP_PID`) and the `#8993` block header, not line numbers |
| "Single failed poll" kills the run | Confirmed — three legs each `break` on first failure inside the poll loop | Debounce all three legs behind one per-poll verdict + consecutive counter |
| "kill -0 ESRCH transient anomaly" plausible | `kill -0` is a bash builtin — cannot be shimmed for tests; only `ps` legs are shim-able | Test transient injection via `ps` PATH-shim covering the `stat=`/`lstart=` legs; the counter treats all legs identically so the property is exercised |

## Open Code-Review Overlap

- `#8659` (33 test suites replace test-helpers' composed EXIT trap): **acknowledge** — concerns `plugins/soleur/test/test-helpers.sh` trap composition and a 33-suite census; touches `scripts/test-all.sh` only as the exporter of `INCIDENTS_REPO_ROOT`. This plan modifies neither the EXIT-trap chain nor test-helpers. Different concern, remains open.
- `#7942` (two `*.mutation.sh` batteries run in no gate): **acknowledge** — concerns suite-registration of two plugin batteries via the `plugins/soleur/test/*.test.sh` glob at `scripts/test-all.sh:78`. This plan's new suite registers under `scripts/followthroughs/` via an explicit `run_suite` line — a different, already-covered path. Remains open.

## Guard Contract

The deliverable's verification surface — the new debounce arms and structural pins in `scripts/test-all-orphan-log-retention.test.sh` — is an assertion-based check over a supervision property, so it carries a contract here.

### Guard 1 — parent-death verdict requires N consecutive failed polls

**Property.** A transient or non-consecutive parent-liveness anomaly never terminates a healthy run; a sustained failure (>= `_RUN_WD_FAILS_N` consecutive failed polls, still-failed on the deciding-poll re-verify) always does.

**Assembly.** Every parent-liveness verdict path inside the `_RUN_WD` subshell's poll loop in `scripts/test-all.sh` — the `kill -0` leg, the `stat==Z*` leg, and the `lstart`-mismatch leg — must funnel through the single `_wd_bad` verdict and `_wd_fails` counter; the `break` into the reap path must sit behind `(( _wd_fails >= _RUN_WD_FAILS_N ))` plus the deciding-poll re-verify. The suite-side chokepoint is `wd_block` extracted via the `_RUN_WD_TOP_PID=$$` anchor range in `scripts/test-all-orphan-log-retention.test.sh`, plus the live-process shim arms that exercise it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Restore first-failure semantics on any one parent leg (`… || break` or `== Z* ]] && break`) | RED — transient-shim arms fire the watchdog on a single anomaly |
| 2 | Drop the healthy-poll reset (`_wd_fails=0`) so failures accumulate cumulatively | RED — alternating-failure arm fires mid-run |
| 3 | Remove/bypass the counter gate so the loop never breaks (guard's own dispatch) | RED — sustained-Z and real-death arms leave the runner alive past deadline |
| 4 | Remove the deciding-poll re-verify (threshold hit `break`s immediately) | RED — the N-then-recover shim arm (2.7b) fires where correct code absorbs |
| 5 | Reintroduce a second parent-liveness leg outside the counter (e.g. a new `pgrep`-based check that `break`s directly) | RED — the structural "no remaining `\|\| break`/`&& break` on parent legs" pin fails |
| 6 | Neuter the shim so it never injects (harness row) | RED — the per-arm injection-marker assertion fails; a transient arm that never injected an anomaly is vacuous |
| 7 | Shim returns `Z` for the WRONG pid (must-pass-shaped input: anomaly on an unrelated pid) | PASS — the parent-verdict logic is keyed to `_RUN_WD_PARENT_PID`; noise elsewhere must not count toward the threshold |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Debounce the parent-liveness check: require N consecutive failed polls (N≥3 at `_RUN_WD_POLL_S=1`) before the terminate path" | Phase 1.1–1.4 (counter + knob), AC-1/2/3/4 | mapped |
| 2 | "re-verify `lstart` identity on the last poll rather than any single sampled mismatch" | Phase 1.4 deciding-poll re-verify, AC-5 | mapped |
| 3 | "A run that survives 90+ min and dies in the same second as a `kill -0` anomaly is the signature this is meant to eliminate" | AC-2/AC-3 transient + non-consecutive arms | mapped (as verification target) |
| 4 | "Every 6h health check reports `tests=failure`, keeps Sentry `main-health-monitor` unresolved, and appends a comment to #9457" | Phase 3 soak enrollment + AC-8 | mapped (impact-remediation ask) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `_RUN_WD_FAILS_N` knob + consecutive counter (Phase 1.1–1.4) | "require N consecutive failed polls (N≥3 at `_RUN_WD_POLL_S=1`)" | asked |
| Deciding-poll lstart re-verify (Phase 1.4) | "re-verify `lstart` identity on the last poll" | asked |
| Runner-death leg debounce (Phase 1.3) | — | inferred — justification: `kill -0 "$_RUN_WD_TOP_PID"` is the same transient-ESRCH class one line up and reaps healthy suite children on a false positive — the identical incident signature through the sibling leg; fixing only the parent leg leaves the defect half-patched |
| Per-leg WARN diagnostic (Phase 1.4) | — | inferred — justification: the false-fire was undiagnosable to leg level; `hr-observability-as-plan-quality-gate` / observability-layer-citation require failure modes to name their detection line, and the WARN line is that line for the absorbed-anomaly mode |
| Test arms B4–B7 + structural pins (Phase 2) | "the signature this is meant to eliminate" | asked (verification of the fix) — shim mechanics are planner-chosen because `kill -0` is unshimmable |
| B1 `SOLEUR_TEST_ALL_WD_FAILS_N=1` pin + new default-N real-death arm | — | inferred — justification: debounce adds ~2s to detection; pinning N=1 preserves B1's deadline contract and proves the floor, the new arm bounds the default-N path |
| Followthrough probe + registration + directive (Phase 3) | "keeps Sentry `main-health-monitor` unresolved" | inferred — justification: the fix's real-world done-signal is post-merge monitor runs going green; plan Phase 2.9.1 makes enrollment mandatory once a soak-shaped AC exists, and unattended verification is the rot class the sweeper exists for |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `scripts/followthroughs/` (one root)
- Planned files: 4 | Estimated changed lines: ~220
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `scripts/test-all.sh` parses `_RUN_WD_FAILS_N` from `SOLEUR_TEST_ALL_WD_FAILS_N` with default `3`, numeric-floor `>= 1`, invalid/zero/octal-trap values falling back to `3` (same idiom as `_RUN_WD_POLL_S`).
- [ ] AC2: A single transient failed parent-liveness poll (`kill -0` ESRCH, `stat==Z*`, or `lstart` mismatch) followed by a healthy poll does NOT terminate the run — proved by the `ps`-shim transient arms (zombie leg and lstart leg).
- [ ] AC3: Non-consecutive failures never accumulate — a shim that fails the parent `stat=` poll on alternating calls produces zero watchdog fire across the run.
- [ ] AC4: Real parent death still terminates the run within a bounded window — proved under both `SOLEUR_TEST_ALL_WD_FAILS_N=1` (existing B1 semantics, ~12s deadline) and the default N=3 (~25s deadline); runner AND transitive suite children are reaped and the `ERROR: parent process gone` line prints.
- [ ] AC5: On the deciding poll the parent identity is re-verified (fresh `kill -0` + `stat` + `lstart`); a recovered/alive read on that probe resets the counter instead of breaking — asserted structurally (re-verify block between the threshold check and `break`) and behaviorally (shim that fails N-1 consecutive then recovers does not fire).
- [ ] AC6: Terminate-path order, the `parent process gone` message text, `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1` opt-out banner, `_run_wd_disarm`, and the runner-identity lstart re-check are byte-identical — existing structural pins in `test-all-orphan-log-retention.test.sh` stay green and `plugins/soleur/test/main-health-monitor-workflow.test.sh` fixture expectations are unaffected.
- [ ] AC7: The runner-liveness leg (`kill -0 "$_RUN_WD_TOP_PID"` reap arm) applies the same consecutive-failure discipline — a transient runner-side anomaly does not reap healthy children (structural pin on `_wd_top_fails`; behavioral coverage via the existing real-runner-death path remaining green).
- [ ] AC8: Each failed poll emits `WARN: parent-liveness poll failed (leg=<kill0|zombie|lstart>, k/N consecutive) (#9686)` on stderr — asserted present in shim-armed runs and absent in clean runs.
- [ ] AC9: `scripts/followthroughs/watchdog-debounce-soak-9686.sh` + `.test.sh` exist, the suite is registered via an explicit `run_suite` line, and #9686 carries the `<!-- soleur:followthrough … -->` directive + `follow-through` label (the directive is added to the PR body / issue comment at ship time).
- [ ] AC10: `bash scripts/test-all-orphan-log-retention.test.sh` passes end-to-end on macOS-bash-3.2-safe idioms and Linux CI; no `set -e` arithmetic-abort idioms (`(( x++ ))`) introduced inside the watchdog subshell.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to the repo's CI test-runner machinery (`scripts/test-all.sh` watchdog subshell, its sibling test suite, a followthrough probe). Assessed against all eight domain questions from `brainstorm-domain-config.md` in a single pass: no user-facing surface, content, vendor, legal, sales, finance, or support surface; the Engineering question's bar is "significant architectural decisions … beyond normal implementation" and this is a debounce bug fix on an existing mechanism. Product/UX mechanical override checked: no Files-to-Create/Edit entry matches the UI-surface glob superset — Product tier is NONE.

## Test Scenarios

- Given a sandboxed `test-all.sh` whose parent stays alive, when a `ps` shim answers `Z` once for the parent's `stat=` poll, then the run completes normally and prints no `parent process gone` line (transient absorbed).
- Given the same sandbox, when the shim answers a forged `lstart` on the second `lstart=` read of the parent pid, then the run completes normally (single sampled mismatch absorbed).
- Given the same sandbox, when the shim fails the parent's `stat=` poll on alternating calls, then no fire occurs (consecutive, not cumulative).
- Given the same sandbox, when the shim answers `Z` on every `stat=` poll of the parent, then the watchdog fires after >= N polls and the run is reaped (sustained failure still kills).
- Given a real parent killed mid-suite (wrapper subshell TERM'd), then with `SOLEUR_TEST_ALL_WD_FAILS_N=1` the runner is reaped within the existing 12s window, and with the default N=3 within ~25s (both: children first, `parent process gone` printed).
- Given `SOLEUR_TEST_ALL_WD_FAILS_N=0`, `=abc`, or `=08`, when the run starts, then the knob falls back to 3 and the watchdog arms normally.
- Given `SOLEUR_TEST_ALL_ALLOW_ORPHAN=1`, then the opt-out banner prints and no watchdog arms (unchanged behavior, existing B3 arm).
- Given the runner itself is KILLed while the parent lives, then in-flight suite children are still reaped — under the new counter, within ~N polls (behavior identical modulo the debounce bound).
- **Verify (local, pre-PR):** `bash scripts/test-all-orphan-log-retention.test.sh` — all arms green; `git diff -- scripts/test-all.sh` shows changes confined to the `_RUN_WD` poll loop + knob parse + comments.

## Success Metrics

- `bash scripts/test-all-orphan-log-retention.test.sh` passes with the new transient/sustained/non-consecutive arms.
- The next two `main-health-monitor` runs after merge report `tests=pass` (or a real failure) with zero `parent process gone`/`[KILLED]` watchdog lines — tracked by the Phase-3 followthrough probe rather than left to memory.
- No recurrence of the #8993 orphan-lock class: a genuinely orphaned run is still reaped within ~N polls + reap chain (~11s).

## Dependencies & Risks

- **Risk — partial-leg coverage:** the `kill -0` builtin cannot be shimmed, so the transient-injection arms exercise only the `ps`-based legs; the counter's uniformity across legs is asserted structurally (single `_wd_bad` verdict feeding `_wd_fails`). Mitigation: structural pin that all three parent legs funnel into the one counter.
- **Risk — timing regression in sibling suites:** `test-all-killed-classification.test.sh` and `test-all-runtime-ceiling.test.sh` splice sandbox runners that retain the watchdog block; their runs have live parents, so the debounce only adds idle iterations — but a suite that kills its own parent would see slower reaping. Verified by running both suites in the PR gate (they run under `test-all` anyway).
- **Risk — `fixture-relative-assert` baseline drift:** new fixture writes may trip the pinned count of `3` — regenerate via `--write-baseline`, never hand-edit.
- **Risk — diagnosis ambiguity remains for kill -0:** if the real-world anomaly is an ESRCH on a live pid (kernel/proc-race), the WARN `leg=kill0` line will show it on the next occurrence — the diagnostic exists precisely so the next fire is self-describing.
- **Pre-existing fragility (not introduced):** the watchdog polls a `/proc`-shaped `ps` on every iteration; under extreme load `ps` itself can be slow — the counter makes slowness survivable (a late answer is still an answer), and `_RUN_WD_POLL_S` remains the pacing knob.

## References & Research

- Issue: #9686 (this fix); origin mechanism: #8993 (closed 2026-09-28, PR #9034); tracker: #9457.
- Code: `scripts/test-all.sh` — `_RUN_WD` block (anchors: `# --- Orphan watchdog, normal run path (#8993)` header, `_RUN_WD_PARENT_LSTART` capture, poll `while :; do`, fire path `parent process gone`); `_ENUM_WATCHDOG` block (~line 734–808) reviewed and excluded.
- Tests: `scripts/test-all-orphan-log-retention.test.sh` (sandbox builder, Part A/B arms, `wd_block` structural pins); `plugins/soleur/test/main-health-monitor-workflow.test.sh` (fire-line fixtures).
- Learning: `knowledge-base/project/learnings/2026-09-28-a-watchdogs-own-teardown-order-decides-whether-its-escalation-fires.md`; `2026-05-18-test-all-tail-masking-and-monitor-exit-condition-tightness.md`.
- Followthrough pattern: `scripts/followthroughs/watchdog-arm-soak-9237.sh` + `.test.sh` (exit-code vocabulary, registration shape); convention doc `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
- Evidence commands: `gh run view 37549587025 --log | grep -n 'KILLED\|parent process gone'`; `gh issue view 9457` comment history.
