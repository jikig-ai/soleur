---
title: "fix(test): technical-ruling-gate receipt-future time-bombed on UTC midnight boundary"
date: 2026-10-31
slug: fix-technical-ruling-gate-midnight-flake
branch: feat-one-shot-11578-ruling-gate-midnight-flake
issue: 11578
closes: 11578
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(test): technical-ruling-gate receipt-future time-bombed on UTC midnight boundary

## Overview

`plugins/soleur/test/technical-ruling-gate.test.sh` derives every fixture timestamp from `DTODAY`, captured once at suite start, while the gate under test reads the live wall clock. A merge-group run that straddles UTC midnight turns a `dts 1` "tomorrow" receipt into "today", so the `receipt-future` case's pristine-gate pin (rc 2) reads rc 0 and the case flakes. This plan removes the flake class by pinning the gate's view of time to the suite's fixture day inside the suite's existing stub-bin, so fixture time and gate time can never diverge.

## Research Insights

**Premise Validation (Phase 0.6).** Issue #11578 is OPEN with no closing PRs; title, labels (`priority/p2-medium`, `type/bug`, `domain/engineering`, `meta/machinery`) and body verified via `gh issue view 11578`. The cited file exists: `plugins/soleur/test/technical-ruling-gate.test.sh` carries `dts()` at line 593 and the `receipt-future` case at line 948 — both anchors confirmed. Context refs verified as context-only, not work targets: #11585 OPEN (held open for first green OIDC publish), #11633 OPEN (`action-required`, operator item), #11549 OPEN (follow-through, auto-verifies), #11553 OPEN (deferred scope-out), PR #11598 MERGED (npm OIDC trusted publishing — the prior work item). Collision precheck (`collision-precheck.sh 11578`) returned one hit: PR #11680, a WIP draft on this exact branch auto-created by this pipeline ("Draft PR created automatically") — not a foreign duplicate; reported here per the precheck contract, work proceeds. No brainstorm exists for this branch; no spec.md exists for `feat-one-shot-11578-ruling-gate-midnight-flake` (`lane:` will default `cross-domain` fail-closed at Save Tasks).

**Root cause (verified in code).** `DTODAY` is captured once at `technical-ruling-gate.test.sh:504`; `dts()` (line 593) offsets from it. The gate reads the live clock twice — `technical-ruling-gate.sh:220` (`receipt_check`, `# mut:receipt-future` line 246: `[[ "$rcre" > "$now" ]] && continue`) and `:274` (`check_delegation_row_inner`, `# mut:ran-future` line 275: `[[ -n "$dran" && "$dran" > "$now" ]]`). When the suite straddles midnight, a `dts 1` receipt lands at suite-start+1 midnight, which is `<=` the gate's live `now` — no longer future — so the pristine gate accepts the receipt (rc 0) where the case pins rc 2. Verified failure signature matches the issue: `FAIL: receipt-future: the pristine gate gives rc 0, not the pinned 2` (`killed_d`, line 874).

**Exposure inventory.** Only `dts <positive n>` values compared against the gate's live clock are bombed, and only when `n` is small enough for a midnight crossing to collapse the gap: `RCT "$(dts 1)"` at line 683 (`rx RW3 2 receipt-mismatch`) and at line 948 (`killed_d receipt-future 2`) — both +1-day receipts required strictly `> now`. The `dts 5`/`dts 11` future cases (lines 639, 702, 947) stay strictly future through any realistic crossing. Past-dated values (`dts -1`, `-5`, `-6`, `-10`, `-20`), `DNOW`, `AT`, `DEXP` (+10 days), and `RCPT_UPDATED` remain directionally correct after a crossing. So the fix must cover exactly the +1-day future class — but a principled fix should cover any offset.

**Relevant file paths.**

- `plugins/soleur/test/technical-ruling-gate.test.sh` — the suite (995 lines). Key sites: `DTODAY` capture 504, `DEXP` 505, `dscn()` 507-520, `mkd`/`mkdr` 521/594, `rcpt`/`RCT` 598-605/681, `dts()` 593, `AT` 606, `run_d` 526-533 (`PATH="${DPATH:-$DBIN:$PATH}"`), `dscn_past` 690-696, mutation arm 860-955, SUT-marker floor 986-993.
- `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh` — the gate under test; `date -u +%Y-%m-%dT%H:%M:%SZ` at 220 and 274; documented test seams at 73 (`TRG_VERIFY_TIMEOUT`, `TRG_EXEC_LOG`, `TRG_SPECS_ROOT`, `TRG_BRANCH`) with the `[NOTE] test seam active` notice at 388.
- `plugins/soleur/scripts/delegation-verify.sh` — the verifier; `date -u +%s` at 511 (strict-mode `CHK_EPOCH`, overridden by `--at` epoch in audit mode) and `date -u +%Y-%m-%d` at 639 (render path, not exercised by the gate). `epoch_of` uses jq (line 109), not `date`.
- `plugins/soleur/test/lib/git-fixture-env.sh` — invoked inside `run_d`'s stubbed PATH; contains zero `date` calls, so a `date` stub cannot break it.

**Established prior art (mechanism already on main).** `plugins/soleur/test/ship-battery-refusal-wait.test.sh:68-93` ships an argv-strict `date` PATH-stub reading a shared fake-clock file (`cat "$STUBS/clock"`, unexpected argv → `exit 64`), with `clock_at()` to re-pin the instant. `ci-head-verdict.test.sh` documents injected-clock prior art (`CI_HEAD_VERDICT_NOW`). The suite under repair already uses the stub-bin idiom (`$DBIN/gh` at line 472-496) that only intercepts the gate's environment via `run_d`'s `PATH="${DPATH:-$DBIN:$PATH}"` — the suite's own `date` at line 504 runs on ambient PATH and stays real. The only `date` consumers under that PATH are the gate's two `+%Y-%m-%dT%H:%M:%SZ` calls and the verifier's `+%s`/`+%Y-%m-%d` calls.

**DPATH exception (verified).** When `DPATH` is set (the `mkbin_t` reduced-PATH cases at 725-737, 938-944), `$DBIN` is absent and the real `date` resolves. Those cases (TQ0-TQ3, need-timeout, gtimeout) use only past-dated or expiry-relative fixtures — no future-dependence — so they are correct under either clock. Noted as a known carve-out, not a gap.

**Mechanism Minimality Gate (0.6b).**

- Property List: (P1) "a `dts <n>` future fixture must be strictly in the future at the instant the gate evaluates it, regardless of when the suite started"; (P2) "the fix must not weaken the `# mut:receipt-future` / `# mut:ran-future` pins or any existing assertion"; (P3) "the fix should eliminate the flake class, not shrink its probability" (a partial fix re-flakes eventually); (P4) "a stubbed clock must be provably load-bearing — a silently bypassed pin must go red, not green".
- Cut List: none of the issue's proposed mechanisms is already covered on `origin/main` (the suite has no clock seam today — verified by grep). Option "bump `dts 1` to `dts 2`" CUT: survives one crossing, not two, and silently changes the fixture's semantics. No other mechanism in the ask is cut — the ask names the right properties and leaves the seam choice open, which the plan resolves below.

**External research.** Skipped — root cause is fully diagnosed in the issue and verified against code; the repo carries the exact prior-art pattern. Functional/community overlap check: skipped (bespoke internal test machinery; no Task tool in this harness — the check is non-blocking by design per `plan-functional-overlap.md`).

**Institutional learnings applied.** `2026-08-10-i-fixed-the-guard-twice-and-my-test-could-not-see-either-fix.md` (a fix must come with a control that can see it — drives the bypass-detection case); `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` (harness rows + must-pass rows in the mutation matrix); `2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` (pin the clock, not the symptom).

*Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).*

## Problem Statement

`plugins/soleur/test/technical-ruling-gate.test.sh` captures `DTODAY` once at suite start (line 504) and derives every fixture instant from it via `dts()` (line 593). The gate under test reads the live wall clock at two sites (`technical-ruling-gate.sh:220`, `:274`). When a merge-group shard starts before midnight UTC and the `receipt-future` case executes after it, `dts 1` resolves to a timestamp that is `<=` the gate's `now`, the pristine gate accepts the "future" receipt (rc 0), and the pinned expectation (rc 2) fails — a calendar flake, not a real defect. The same latent bomb sits in `rx RW3` (line 683) and in every future `dts <+n>` case a contributor adds. Issue #11578.

## Proposed Solution

Pin the gate's view of time to the suite's fixture day, inside the suite's existing stub-bin — the same fake-clock idiom `ship-battery-refusal-wait.test.sh:68-93` already ships. Fixture time and gate time then share one source of truth (`DTODAY`) and can never diverge, eliminating the flake class rather than shrinking its window.

Concretely, inside `plugins/soleur/test/technical-ruling-gate.test.sh` only:

1. **`$DBIN/date` stub** (new heredoc beside the existing `$DBIN/gh` stub, ~line 496): argv-strict — serves `-u +%Y-%m-%dT%H:%M:%SZ` (the gate's two call sites), `-u +%s` (the verifier's strict-mode epoch), and `-u +%Y-%m-%d` (the verifier's render path) from a pin file; appends its argv to `$DBIN/dcalls.log` for the dispatch floor; exits 64 loudly on any other argv so a future `date` consumer fails in the open instead of silently bypassing the pin. Real `date` is never exec'd (no passthrough — a passthrough is a bypass).
2. **`dclock_at <iso>` helper + `$DBIN/clock` / `$DBIN/clock.epoch` pin files**: writes the ISO instant to `clock` and its epoch (via `jq -rn --arg p '$p|fromdateiso8601'`, jq already a suite dependency) to `clock.epoch`; called once after `DTODAY`/`DEXP` are set (~line 505) with `DNOON="${DTODAY}T12:00:00Z"` — noon gives margin: every "present" fixture instant (`DNOW` `T00:00:00Z`, `T00:07:00Z`) stays strictly `<` the pin and every `dts +n` (`n>=1`) stays strictly `>`.
3. **CLK control cases** (new, placed after the Arm 6g2 receipt block ~line 689): repin `dclock_at "$(dts -1)"`, run a `mkdr`-with-ran scenario, assert the gate now reports `delegation-invalid` / rc 1 (the `ran` instant `DNOW` reads as future under a yesterday pin) — a verdict that can only occur if the stub is serving; under a bypassed stub the real clock yields rc 2 `receipt-missing` (the ran row passes the future check and dies at the receipt check), so this case is the bypass detector. Restore `dclock_at "$DNOON"` immediately after. Plus a `clock`/`clock.epoch` consistency assertion.
4. **Dispatch floor** (new, beside the existing SUT-marker floor ~line 989): assert `dcalls.log` has at least the committed-count invocations and contains only the three sanctioned argv — a stub never invoked, or invoked with an unexpected argv, cannot pass vacuously.

**Alternatives considered.** (A) Recompute `DTODAY` inside `dscn()` per scenario — test-only and smaller, but the window shrinks from ~48 minutes (suite duration) to ~seconds per case rather than closing; a partial flake fix re-flakes. Rejected. (B) `TRG_NOW` env seam inside `technical-ruling-gate.sh` (mirroring the existing `TRG_*` seams at line 73) — equally deterministic, but it mutates a ship-time security gate to fix a test-side flake; the stub achieves identical determinism with zero production diff. Rejected on blast radius. (D) `dts 1` → `dts 2` — cut at the minimality gate (survives one crossing, not two, and silently changes fixture semantics). The A/B/C fork is recorded as a `pending - assumed: C` technical row in this branch's `decision-challenges.md` for the post-plan ruling spawn.

**Why the pin is noon, and why `run` arms are untouched.** The pin must sit strictly between the suite's "present" instants (`DNOW`, `T00:07`) and `dts 1`. Noon of the fixture day does that under any real start time. The `run` helper (line 44) invokes the gate on ambient PATH for shape-check fixtures that contain no delegation rows, so its `date` calls never fire — it needs no stub and gets none (`$DBIN` is only on `run_d`'s PATH). The `mkbin_t` reduced-PATH cases (`DPATH` set) bypass `$DBIN` by design; their fixtures are all past-dated or expiry-relative, verified case-by-case — no future-dependence, so they are correct under the real clock. This carve-out is documented in the suite comment.

## Implementation Phases

### Phase 1 — Clock stub and pin (test file only)

- Add the `$DBIN/date` argv-strict stub (heredoc + `chmod +x`) after the `gh` stub block (~line 496), logging each argv to `$DBIN/dcalls.log`.
- Add `DNOON`, `dclock_at()`, and the initial `dclock_at "$DNOON"` call immediately after `DEXP` is set (~line 505).
- Add a suite comment naming the mechanism and the DPATH carve-out.

### Phase 2 — Controls

- Add the CLK bypass-detection case (+ repin/restore) after the Arm 6g2 receipt block.
- Add the `clock`/`clock.epoch` consistency assertion.
- Add the `dcalls.log` floor beside the existing SUT-marker floor; commit the count measured on a green run (same convention as `n_rows >= 222` at line 989).

### Phase 3 — Verify

- `bash plugins/soleur/test/technical-ruling-gate.test.sh` green locally.
- Confirm the diff touches only the test file: `git diff --name-only origin/main...HEAD -- plugins/ | grep -v 'test/technical-ruling-gate.test.sh'` is empty.

## Files to Edit

- `plugins/soleur/test/technical-ruling-gate.test.sh` — the only code change. Estimated ~60 lines added (stub ~25, `dclock_at`+pin ~15, CLK case ~10, floor ~5, comments ~5), zero removed except comment context.

## Files to Create

- None (the stub and pin are heredoc-created inside the suite's own `$TMP`/`$DBIN` at run time; `knowledge-base/project/specs/feat-one-shot-11578-ruling-gate-midnight-flake/decision-challenges.md` is a planning artifact, already written).

## Observability

```yaml
liveness_signal:
  what: merge-group `test-scripts` shard runs this suite on every PR; a green `=== Results ===` block with `Failed: 0` is the signal the flake class is gone
  cadence: per merge-group run
  alert_target: GitHub check run on the merge-group commit (auto-blocks the merge)
  configured_in: .github/workflows/ (the test-scripts shard that executed run 40970866637) — no new wiring in this PR
error_reporting:
  destination: the merge-group job log (the same channel that surfaced #11578)
  fail_loud: a `FAIL:` line per case plus a non-zero suite exit — and, if the clock stub is bypassed, the CLK case's `delegation-invalid` assertion reddens on any calendar day, not only at midnight
failure_modes:
  - mode: `date` stub absent or bypassed (PATH regression, stub made non-executable)
    detection: CLK bypass-detector case goes red (pinned-past verdict flips to rc 2 receipt-missing)
    alert_route: merge-group job failure
  - mode: new future-dependent fixture added under a `DPATH` reduced-PATH case (pin does not reach it)
    detection: suite comment at the `dclock_at` call site names the carve-out; review of the new case
    alert_route: PR review
logs:
  where: suite stdout + `$DBIN/dcalls.log` inside the suite's `$TMP` (per-run, not persisted)
  retention: merge-group job log retention
discoverability_test:
  command: grep -c '# mut:receipt-future' plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh
  expected_output: "1"
```

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the blast radius is a merge-group CI shard reporting a spurious `FAIL: receipt-future` on a green gate (developer experience, not product surface).
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing — the change adds a PATH-local `date` stub inside one test suite's `$TMP`; it cannot reach the production gate, the verifier, or any operator-facing surface (verified: `run_d` is the only PATH consumer and it is suite-internal).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal test machinery only; no user data, no production code path, no distribution surface — a `none` threshold, not `single-user incident`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — engineering test-machinery fix confined to one suite file. The mechanical UI-surface override was checked: `## Files to Create`/`## Files to Edit` contain no UI-surface paths (`plugins/soleur/test/*.sh` matches no term or glob in `ui-surface-terms.md`), so Product stays NONE and no Product/UX gate runs.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (2026-10-31) bodies contain no mention of `plugins/soleur/test/technical-ruling-gate.test.sh` or `technical-ruling-gate` generally.

## Gate Dispositions

- Phase 1.4 network-outage checklist: no trigger pattern — skipped.
- Phase 1.5 community discovery: bash test machinery, no stack gap — skipped.
- Phase 1.5b functional overlap: bespoke internal machinery; agent not spawnable in this harness — skipped (non-blocking by design).
- Phase 2.7 GDPR gate: no regulated-data surface, no (a)-(d) trigger — skipped.
- Phase 2.8 IaC routing: no infrastructure — skipped.
- Phase 2.9 Observability: not required by plan 2.9's code-class detection set (`apps/*/server|src|infra`, `plugins/*/scripts`); **emitted anyway** — deepen-plan Phase 4.7's mechanical trigger (non-docs Files-to-Edit) treats a test `.sh` as in-scope, and the block is genuinely useful: it names the merge-group failure signal this fix restores.
- Phase 2.9.1 soak enrollment: no post-deploy soak criterion — skipped.
- Phase 2.9.3 task design: no new autonomous-task surface — skipped.
- Phase 2.10 ADR/C4: no architectural decision (would a reader of the ADR corpus be misled after this ships? No — the gate, verifier and C4 are unchanged) — skipped.
- Phase 2.11 encryption posture: no persistent store or new connection — skipped.
- Phase 2.13 founder check: headless run — skipped.
- Phase 4.5 scoped advisor / Phase 3 SpecFlow: no Task tool in this harness — the spec-flow review was performed inline (per-case clock analysis in Research Insights); a panel review may still run post-plan via the one-shot parent.

## Guard Contract

### Guard 1 — pinned SUT clock (`$DBIN/date` + `dclock_at`)

**Property.** Every `date` invocation the gate or verifier resolves under `run_d`'s stubbed PATH returns the suite-pinned instant, so a `dts`-derived fixture can never be on the wrong side of "future" relative to the instant the gate evaluates it — the midnight-crossing flake class is eliminated, not narrowed.

**Assembly.** All `date` call sites reachable under `run_d`'s `PATH="${DPATH:-$DBIN:$PATH}"` with `DPATH` unset: `technical-ruling-gate.sh:220` and `:274` (`date -u +%Y-%m-%dT%H:%M:%SZ`), `delegation-verify.sh:511` (`date -u +%s`), `:639` (`date -u +%Y-%m-%d`, render path unused by the gate). The chokepoint is `$DBIN` on PATH — `run()` (line 44) never carries it and never reaches a `date` call site (no delegation rows under `run`); the `DPATH` arm is a second, declared chokepoint where the pin does not reach, bounded by the verified invariant that no `DPATH` case builds a future-dependent fixture (inventory in Research Insights — a new `DPATH` case using `dts +1` receipts would need the pin and must not be added under `DPATH`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `$DBIN/date` (or `chmod -x`) so the real `date` resolves | RED — CLK case: the pinned-past scenario reads rc 2 `receipt-missing` under the real clock, not the asserted rc 1 `delegation-invalid` |
| 2 | Replace the stub body with `exec /bin/date "$@"` (silent passthrough) | RED — same CLK divergence; a passthrough is a bypass the argv log also shows as absent-vs-real |
| 3 | Repin `dclock_at` to an instant after a `dts 1` receipt inside a `receipt-future`-shaped scenario | RED — the pinned rc-2 verdict flips to rc 0, proving the pin (not luck) supplies the future relationship (order/lifetime row: the mutation observes inside the fixture-build→gate-exec window) |
| 4 | Give the gate a new `date` call with a fifth argv shape (e.g. `date -u +%H`) | RED — argv-strict stub exits 64 loudly; `now` goes empty and the verdicts flip rather than silently serving real time (second-member/dispatch row) |
| 5 | Remove the `dcalls.log` line from the stub | RED — dispatch-floor assertion `wc -l < dcalls.log >= N` reads 0 |
| 6 | (harness, must-PASS) `date -u +%s` on the stub must equal `jq -rn --arg p "$PIN" '$p|fromdateiso8601'` and `date -u +%Y-%m-%d` must equal `${PIN%%T*}` for a non-canonical pin value (e.g. `dclock_at "$(dts -3)"`) | PASS — a stub serving inconsistent ISO/epoch pairs would pass CLK but silently break verifier expiry math |

**Anchor.** The pin, the stub, and every `dts`-derived fixture share one source of truth — `DTODAY` — committed in the same diff; the CLK case manufactures a controlled divergence (pin = `dts -1` vs fixtures = `DTODAY`) that only a live stub can produce, so the pin cannot rot silently inside its own commit.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Freeze `DTODAY` per-case (recompute inside the case, or pin `dts` to the assertion's own reference instant) so \"future\" is evaluated against the same `DTODAY` the gate sees at case time — or make the gate-fixture clock injectable and pin it in the suite." | Proposed Solution (Option C `$DBIN/date` stub + `dclock_at` pin) / Phase 1 | mapped |
| 2 | "`receipt-future` failed in merge-group run 40970866637 … expected rc 2, gate returned rc 0." | AC1, AC3 (receipt-future class made deterministic; CLK bypass detector) | mapped |
| 3 | "Any `dts <n>` \"future-date\" case is time-bombed the same way whenever the suite straddles a UTC midnight." | Proposed Solution (pin covers every offset, not just +1) / Guard 1 Property | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `$DBIN/date` argv-strict stub + pin files | "make the gate-fixture clock injectable and pin it in the suite" | asked |
| `dclock_at` repin helper | "pin `dts` to the assertion's own reference instant" | asked |
| CLK bypass-detection case | — | inferred — justification: a pinned clock that is silently bypassed re-opens the exact flake with no signal; the repo's own learning corpus requires the fix ship with a control that can see it (`2026-08-10-i-fixed-the-guard-twice`) |
| `dcalls.log` dispatch floor | — | inferred — justification: anti-vacuity for the stub itself; a never-invoked stub must not read green (`2026-08-13-every-guard-i-shipped`) |
| DPATH carve-out suite comment | — | inferred — justification: documents the one PATH arm where the pin does not reach so a future case under `DPATH` does not re-introduce the bomb |

### Split Assessment

- Subsystems touched: 1 — `plugins/soleur`
- Planned files: 1 (edit) | Estimated changed lines: ~60
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `plugins/soleur/test/technical-ruling-gate.test.sh` contains an argv-strict `$DBIN/date` stub serving exactly `-u +%Y-%m-%dT%H:%M:%SZ`, `-u +%s`, `-u +%Y-%m-%d` from the pin, logging argv to `dcalls.log`, exit 64 otherwise; no production file is modified (`git diff --name-only origin/main...HEAD -- plugins/` lists only the test file).
- [ ] AC2 — `dclock_at` is invoked once at setup with `DNOON="${DTODAY}T12:00:00Z"` after `DTODAY`/`DEXP` are captured and before the first `run_d` call; `clock`/`clock.epoch` are written consistently (epoch = `fromdateiso8601` of the ISO pin).
- [ ] AC3 — The suite is deterministic under a simulated crossing: the CLK case repins `dclock_at "$(dts -1)"`, runs a `mkdr`-with-ran scenario, and asserts rc 1 + `delegation-invalid` (verdict flips only if the stub serves); the pin is restored to `$DNOON` after the case.
- [ ] AC4 — The dispatch floor asserts `dcalls.log` reaches at least the committed count and contains only the three sanctioned argv (a stub never invoked, or a passthrough, cannot pass vacuously).
- [ ] AC5 — `bash plugins/soleur/test/technical-ruling-gate.test.sh` exits 0 with every pre-existing assertion unchanged in expectation (`receipt-future` still kills its mutant, `RW3` still pins rc 2 — under the pin they can never again see a non-future `dts 1`).
- [ ] AC6 — All mutation pins survive: every `# mut:` line in `technical-ruling-gate.sh` is byte-identical to `origin/main` (the fix does not touch the SUT).

## Test Scenarios

- Given the suite runs with the pin at fixture noon, when `receipt-future` builds `RCT "$(dts 1)"` and runs the pristine gate, then the receipt reads strictly `> now` and rc 2 holds — on any calendar day, at any start time. (`unit` — suite-internal)
- Given `dclock_at "$(dts -1)"`, when a `mkdr`-with-ran scenario runs the pristine gate, then `ran=DNOW` reads as future → rc 1 `delegation-invalid`; under a bypassed stub the same fixture reads rc 2 `receipt-missing` → the CLK assertion is the bypass detector. (`unit`)
- Given the stub is replaced by `exec /bin/date "$@"`, when the suite runs, then CLK fails (guard matrix row 2). (`unit` — mutation coverage)
- Given a green run's `dcalls.log`, when the floor assertion runs, then `wc -l` meets the committed count and `grep -vc` of the sanctioned argv is 0. (`unit`)
- Given `DPATH` is set (mkbin_t arm), when TQ0-TQ3 run under the real clock, then their verdicts are unchanged — verified because no `DPATH` case builds a future-dependent fixture. (`unit` — carve-out control)

## Context

The failed merge-group run (issue body): shard start 2026-10-29 23:12Z, `receipt-future` executed 2026-10-30 00:00:25Z — `dts 1` resolved to 2026-10-30 = evaluation day. Failure line: `FAIL: receipt-future: the pristine gate gives rc 0, not the pinned 2` (`killed_d`, test line 874). The gate's time reads are `date -u +%Y-%m-%dT%H:%M:%SZ` string comparisons (`>` is lexicographic on the ISO form — correct because the format is fixed-width UTC).

## References

- Issue: #11578 (target); context only: #11585, #11633, #11549, #11553; prior work: PR #11598 (merged)
- Suite: `plugins/soleur/test/technical-ruling-gate.test.sh` (`dts` L593, `RCT` L681, `receipt-future` L948, `RW3` L683, floor L989)
- Gate: `plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh` (clock reads L220, L274; seams L73)
- Verifier: `plugins/soleur/scripts/delegation-verify.sh` (`date -u +%s` L511)
- Prior-art stub idiom: `plugins/soleur/test/ship-battery-refusal-wait.test.sh:68-93`

## Deepen Pass (soleur:deepen-plan, 2026-10-31)

All mechanical halt gates verified inline: 4.6 User-Brand (present, threshold `none` — `plugins/soleur/test/` matches no `SENSITIVE_PATH_RE` arm, no scope-out needed); 4.7 Observability (block added — the mechanical non-docs trigger covers `plugins/*/test/*.sh` even though plan 2.9's code-class set does not); 4.8 PAT scan (zero hits); 4.10 encryption (no store/connection in Files lists — skip); 4.11 Guard Contract (`lint-guard-contract.py` scanned: 1 entry, ≥3-row matrix, Property/Assembly non-placeholder; adequacy read: Assembly names the `$DBIN`-on-PATH chokepoint plus the declared `DPATH` second arm, matrix rows derived from the design not the implementation); 4.12 Scope Check (one unfenced section, all asks mapped, inferred rows justified, `Recommendation: single PR`); 4.13 task design (no new autonomous-task surface — skip). 4.5 network-outage, 4.55 downtime, 4.9 UI-wireframe: no trigger. 4.4 precedent-diff: the fake-clock stub is pattern-bound — precedent `ship-battery-refusal-wait.test.sh:68-93` adopted verbatim in shape (argv-strict, clock file, exit-64 refusal); noted in Proposed Solution. Round-1 realism sweeps: negative claims in the plan ("no passthrough", "cannot reach production code", "zero `date` calls in `git-fixture-env`") each verified by grep during planning; every prescribed command was executed once before commit (grep counts, `git diff --name-only origin/main...HEAD -- plugins/` = empty). Agent fan-out (research seats, review seats, SpecFlow) could not spawn in this harness — no Task tool; performed as inline analysis instead, recorded here so a later phase knows the deepen was mechanical-only. Enhancement applied this pass: `## Observability` block (deepen 4.7 trigger) and the Gate Dispositions correction naming it.
