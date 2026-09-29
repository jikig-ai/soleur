---
title: "flake: cloud-init-inngest-provision-unit T9 exit-143 timing assertion misses under CI runner load"
date: 2026-09-29
slug: fix-provision-unit-t9-exit-143-flake
branch: feat-one-shot-9195-t9-exit-143-flake
issue: 9195
closes: 9195
type: fix
priority: medium
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# flake: cloud-init-inngest-provision-unit T9 exit-143 timing assertion misses under CI runner load

## Enhancement Summary

**Deepened on:** 2026-09-29
**Sections enhanced:** Hypotheses (network-outage deep-dive), Technical Considerations (sibling precedent), References (open sibling issue), Observability (probe corrected to a non-suite-shaped command)

### Key Improvements

1. Replaced the `discoverability_test` probe — the original named the `*.test.sh` path and would have hit deepen-plan Phase 4.7's suite-shaped-command reject; the directory-scoped marker grep verifies the same property in ~80 ms.
2. Verified every cited issue/PR live (#7374 CLOSED, #7376 OPEN, #9159 MERGED, #8562 OPEN, #9126 OPEN) — #7376 turned out to be an OPEN sibling issue on this exact runner-load flake class, not only the diagnostics precedent.
3. Confirmed by source inspection that `bootstrap start` rows carry no `attempt=` field in either tier (Tier A emit `bootstrap start DOPPLER_PROJECT=… planted=…`; Tier B stub emits the bare form) — the pairing hazard is real, and the `attempt=` anchors are load-bearing.
4. Sibling precedent for the chosen pattern exists inside the same suite: T11 already bounds a measured event (`timer start within 15 s of multi-user.target`) rather than a fixed slack — the design extends an established idiom.

### New Considerations Discovered

- #7376 (`run-registered-suites.sh` flaky under its default `-P` on a 4-core runner) is open and adjacent; this fix removes one symptom source, not the runner-level load problem it tracks. Cross-reference added — no scope fold-in.

## Overview

The Tier B systemd-in-Docker exercise T9 in `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` asserts that `provision-attempt-exit-143` lands within a fixed bound after the timeout kill. On loaded CI runners the killed attempt's phone-channel row is absent from the captured call log while its sibling `emit provision_attempt_failed rc=143` row is present, so both T9 rows go red on a suite whose production behavior is correct. The fix re-anchors the assertion on the reporting evidence the design actually guarantees.

## Problem Statement / Motivation

T9 arms a five-second start timeout on the provision unit, forces the bootstrap stub into a 60 s sleep, starts the service, and then reads one snapshot of the container's append-only call log. Two assertions consume that snapshot:

- a timing row: `(exit-143 timestamp) - (bootstrap start timestamp) <= 15`, and
- an ordering row: the `provision-attempt-exit-143` line precedes `provision-attempt-start attempt=2`.

Both read the **phone channel only**, and neither anchors on `attempt=`.

Evidence pulled from the failing run's retained per-suite artifact (`infra-suite-logs-2` on run 36525271493, job 109266901611 — the timestamped call-log dump the suite prints at teardown):

```text
1790659166.596  PHASE T9
1790659166.875  phone provision-attempt-start attempt=1 iid=i-tierb
...                (attempt-1 stub pipeline, ~0.15 s)
1790659167.034  bootstrap start                                  <- attempt 1
1790659172.040  emit provision_attempt_failed warning rc=143.attempt=1.why=pre-bootstrap-run.iid=i-tierb
1790659172.042  docker rm -f tierbcid                            <- on_exit cleanup ran to completion
                (no "phone provision-attempt-exit-143 attempt=1" row — the FIRST on_exit emit was lost)
1790659174.306  phone provision-attempt-start attempt=2 iid=i-tierb   <- RestartSec=2s restart; the poll succeeds on this row
1790659174.867  phone provision-attempt-exit-143 attempt=2 ...        <- written LATER, by the T15 reset_state unit stop — not by a timeout
1790659175.029  PHASE T15
```

Three facts follow, none of which a wider landing window fixes:

1. **The row is absent, not late.** Attempt 1's `emit ...rc=143.attempt=1` row landed at +5.006 s after its `bootstrap start` — essentially perfect timing — while the `phone provision-attempt-exit-143` row that precedes it inside `on_exit` never landed at all. The production script reports the kill on two independent channels (`inngest-boot-phone-home.sh` then `soleur-boot-emit`); under load the first emit was lost and the second survived. A single-channel assertion cannot distinguish "TERM-trap reporting broken" from "one best-effort emit lost under runner load".
2. **The unanchored matchers can capture the wrong attempt.** `bootstrap start` rows carry no `attempt=` field, and `provision-attempt-exit-143` appears again for `attempt=2` (written by the next phase's teardown, not by a timeout). A first-match `awk` pairs rows across attempts whenever the snapshot lands late or attempt 1 is killed before its bootstrap stage.
3. **The ordering row reds on absence.** With no exit-143 row in the snapshot, `e` is unset and the `e < s` check fails — the second red is a follower of the first, not an independent signal.

Suite cadence per the issue: ~351 s on the Infra Validation leg; observed on two unrelated PRs within ~1 h on 2026-09-29 (runs 36520108194 and 36525271493). The org runs ~250 Actions runs/hr against a 20-job ceiling (see the 2026-09-21 runner-concurrency brainstorm), so "loaded runner" is the steady state, not the exception — every recurring red leg costs a full-leg re-run and erodes the gate's credibility.

## Hypotheses

The feature description triggers the network-outage checklist (`timeout`); the required L3 → L7 accounting, per `plan-network-outage-checklist.md`:

1. **L3 — firewall allow-list.** Opt-out: the failing surface is a systemd instance inside a privileged Docker container on an ephemeral GitHub-hosted runner; the T9 path makes no network calls (docker/doppler/phone/emit are in-container stubs appending to the shared calls log). Verification artifact: the timestamped call-log dump in artifact `infra-suite-logs-2` (run 36525271493) shows the entire kill sequence in-container with no network step between `bootstrap start` and the rc=143 report.
2. **L3 — DNS / routing.** Opt-out on the same artifact and reasoning: no resolver or routing step participates in the T9 path; every command the attempt runs between `provision-attempt-start` and the kill is a stubbed local append.
3. **L7 — TLS / proxy.** Not applicable: no HTTPS endpoint exists in the T9 path.
4. **L7 — application layer.** Verified: the suite's own teardown dump (the service-equivalent log) shows `emit provision_attempt_failed rc=143.attempt=1` present and `phone provision-attempt-exit-143 attempt=1` absent — the kill and the report chain executed; only one emit's row is missing. The defect is in the test's single-channel read of the evidence, not in the provision script's TERM-trap behavior.

### Network-Outage Deep-Dive

Layer-by-layer verification status (deepen-plan Phase 4.5 re-check): L3 firewall — not applicable, opted out with the artifact citation above (the failing surface is inside a Docker container on an ephemeral runner; no host firewall participates). L3 DNS/routing — same opt-out; the T9 path resolves nothing. L7 TLS/proxy — not applicable, no HTTPS surface in the path. L7 application — verified against the retained artifact's timestamped dump. No gaps remain to close before implementation: the only "connectivity" in play is a synchronous append to a container-local file, and its failure mode (a lost emit) is exactly what the fix tolerates.

## Research Insights

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

**Premise validation** (Phase 0.6): Issue #9195 is OPEN with no closing PR (`gh issue view 9195 --json state,title,closedByPullRequestsReferences`). The asserted file exists on this branch at `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` (last touched by #9159, `95ac2fd4f2`). Cited context issue #9123 is CLOSED — context, not a blocker. Both cited CI jobs were re-fetched (`gh api .../jobs/<id>/logs`): the same two FAIL rows appear in both, and the retained artifact log confirms the absent phone row + present emit row shape (not just the empty interpolation in the FAIL text). No stale premises.

**Property list** (Phase 0.6b) — the observable outcomes this change must buy:

- P1: T9 greens when the killed attempt's rc=143 is reported on at least one of the two designed reporting channels, promptly, even when the other channel's row was lost.
- P2: T9 reds when NO channel reports the killed attempt's rc=143 — the reporting path is what the exercise exists to prove.
- P3: T9's ordering evidence pairs rows of the same attempt (`attempt=1` exit before `attempt=2` start); teardown or later-attempt rows must not satisfy or pollute it.
- P4: On red, the diagnostic names which channels were observed, so the next flake investigation starts with evidence rather than an empty interpolation.

**Cut list** (Phase 0.6b) — mechanisms considered and cut before research:

- Widen the landing window (issue's option A) → buys nothing against a permanently-absent row; the artifact shows the emit-channel row already at +5.006 s, far inside the current 15 s bound. Cut by evidence.
- A secondary `poll` for the exit-143 row after `attempt=2` appears → the row is lost, not delayed: when emitted it precedes `attempt=2` by ≥2 s (RestartSec), and the full-log dump shows it never landed. Polling a row that will never exist only lengthens every loaded run. Cut.
- Retry-on-fail wrapping of T9 or the suite → masks the real regression the assertion exists to catch; repo convention treats flakes as defects, not as retriable noise. Cut.

**Relevant file paths:**

- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` — T9 block (search anchor `# ---- T9:`), helpers `mark` / `lines_from` / `poll` / `reset_state` (search anchor `LOGF=/var/lib/tierb/calls.log`), Tier B stubs `inngest-boot-phone-home.sh` and `soleur-boot-emit` (search anchor `for stub in docker doppler`).
- `apps/web-platform/infra/cloud-init-inngest.yml` — the provision script under test: `on_exit()` emits `provision-attempt-exit-$rc` on the phone channel and `provision_attempt_failed` via `soleur-boot-emit` (search anchor `on_exit()`), armed by `trap '... exit 143' TERM INT` (search anchor `dash runs NO EXIT trap`).
- `apps/web-platform/infra/run-registered-suites.sh` — glob registration + per-suite log retention (search anchor `DIAGNOSTICS ON RED`).
- `.github/workflows/infra-validation.yml` — matrix legs, `timeout-minutes: 15` (the cap the issue mentions), `docker info` fail-closed ordering note.

**Applicable learnings:**

- `2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md` — assert a positive identity, never an absence; T9 currently reads an absent row as a failed property.
- `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md` — the inverse matters here too: a check that cannot distinguish "reported on channel 2" from "not reported" flakes; the fix asserts evidence presence, not a single channel's survival.
- `2026-09-25-the-flake-was-sigpipe-at-4kib-...md` (test-failures) — the repo's flake discipline: deterministic regression inputs plus a load check (N concurrent copies at high load), not window-widening alone.
- `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — two-stage `--json` then `jq --arg` used for the overlap query.

**Related issues/PRs:** #9195 (this), #8562 (parent: the retrying provision unit this suite covers), #9123 (surfaced during its boot-unlock stack), #9126 (sibling load-dependent flake), #7374/#7376 (the diagnostic-excerpt precedent this analysis consumed), PR #9159 (`95ac2fd4f2`, last change to this file).

**External research:** skipped (Phase 1.6) — all evidence is in-repo plus CI artifacts; the mechanism is pinned by the retained log. Community/functional discovery: no uncovered stack signatures (Phase 1.5 check found no `pubspec.yaml`/`Cargo.toml`/`mix.exs`/`go.mod`/`Package.swift`/`build.gradle`/`composer.json` at repo root), and a repo-internal test assertion has no community-artifact equivalent (Phase 1.5b assessed inline — no agent-spawn capability exists in this subagent process).

## Proposed Solution

Rework the T9 evidence capture in `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` (the `# ---- T9:` block) so the assertions read the property the design guarantees — *the start-timeout kill is reported on at least one channel, promptly, before the next attempt* — instead of the survival of one specific emit:

1. **Dual-channel, attempt-anchored exit evidence.** Capture `t9_x` as the earliest timestamp among rows matching either channel for `attempt=1`:
   - phone: `$2 == "phone" && $3 == "provision-attempt-exit-143" && $4 == "attempt=1"`
   - emit: `$2 == "emit" && $3 == "provision_attempt_failed" && $5 ~ /^rc=143\.attempt=1\./` (the trailing `.` distinguishes `attempt=1.` from `attempt=10.`; `$5` is the `rc=...` field in the emit row's fixed shape)
   Record which channel satisfied (`via=phone`, `via=emit`, `via=both`, `via=none`) for the diagnostic line.
2. **Anchor the bound on the attempt's own start row.** `t9_b` = timestamp of `phone provision-attempt-start attempt=1` (it carries the `attempt=` field `bootstrap start` lacks, and it is emitted before any deferrable window). Bound stays `(e - b) <= 15`: the start timeout is 5 s, so the bound still proves the trap's report lands far inside the 90 s SIGKILL horizon while tolerating deferred-trap and emit-stub latency under load. If attempt-1's start row is absent, fall back to the last `bootstrap start` row preceding `e` — and if neither exists, the row reds with a diagnostic naming the missing anchor (an attempt that never reported starting is a different failure than a timing miss and the message must say so).
3. **Anchor the ordering row on the same evidence.** Compare log positions of the chosen attempt-1 exit-evidence row and `provision-attempt-start attempt=2` — `e < s` — so a later attempt's or a teardown's exit-143 row can neither satisfy nor break it.
4. **Extend the restart-wait poll.** `poll 40` for `provision-attempt-start attempt=2` → `poll 90` (matching T10's bound): `RestartSec=2s` makes arrival near-certain, and the current 40 s converts runner starvation into an ordering-row red on a snapshot that simply predates the restart.
5. **Diagnostic richness.** Both `tb_ok` messages interpolate `via=` and the observed timestamps (`attempt=1` start, exit evidence, `attempt=2` start presence), so the next miss reads as evidence rather than `exit-143 )`.

The provision unit's rendered script (`cloud-init-inngest.yml`) is **unchanged** — the dual-channel report already exists there by design; the test was reading only half of the designed evidence. Phone-channel emit health for the non-TERM path stays pinned by Tier A's T7 row (`provision-attempt-exit-1` phone assertion), so accepting either channel in T9 does not reduce coverage.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| Widen the 10 s slack / 15 s bound (issue option A) | Rejected | The artifact proves the row is absent, not late — no width fixes absence. Also widens the false-negative window for a real TERM-trap regression. |
| Re-derive the bound from measured `bootstrap start` (issue option B) | Partially adopted | `bootstrap start` is already the anchor; the real defect is single-channel evidence + unanchored attempt matching. Kept as fallback anchor when `attempt=1` start is missing. |
| Poll longer for the exit-143 row itself | Rejected | Emit is synchronous before unit exit; if `attempt=2` started, a *written* exit row is already in the log. The observed row is lost, not pending. |
| Make the production `on_exit` retry its phone emit | Out of scope | Production phone-home is inherently best-effort (a curl); that is exactly why the script dual-reports. No evidence of a production regression — the emit channel fired. |
| Assert BOTH channels land | Rejected | Reintroduces the flake: the observed failure is exactly one channel lost under load. Channel-level coverage remains via T7. |
| Retry the suite/leg on T9 failure | Rejected | Hides regressions; repo flake discipline is deterministic repro + fix, per the SIGPIPE learning. |

## Technical Considerations

- **dash signal semantics** (why the trap chain behaves this way): `dash` defers a trap until its foreground child exits; the provision script runs the bootstrap as `cmd & child=$!; wait` so the TERM trap is interruptible. The emit loss occurred inside `on_exit`'s foreground stub exec — consistent with a transient exec/write loss under cgroup CPU starvation, not with trap-ordering defects. The fix must not depend on which micro-cause lost the row — dual-channel anchoring is robust to all of them.
- **`lines_from T9` returns all rows after the T9 mark**, including later-phase rows in the end-of-run dump — but the assertion consumes a *point-in-time* snapshot taken before T15 runs, so cross-phase pollution is impossible at assertion time; the `attempt=` anchors additionally protect against attempt-2 teardown rows already inside the snapshot.
- **`reset_state` deletes the attempts counter**, so later phases reuse `attempt=1` — one more reason the matchers anchor on `attempt=1` *within this snapshot* rather than on line shape alone.
- **Sibling precedent (deepen-plan Phase 4.4).** The same suite already bounds a *measured* timestamp rather than fixed slack: T11 asserts the timer-driven unit start lands within 15 s of a captured `multi-user.target` timestamp (`(s - u) <= 15`), and T4/T17 order events by log position (`e < s` on slice row numbers). The T9 rework extends both idioms — measured anchors, position ordering — with attempt-scoped matching. No novel pattern is introduced.
- **No NFR-register impact** — test-harness change only; no production latency, availability, or security surface moves.
- **Rule conformance:** assertions anchor on content fields (`attempt=1`, `rc=143`), never bare tokens (`cq-assert-anchor-not-bare-token`); any new comments cite symbol anchors (`on_exit`, `trap … TERM INT`, `tb_ok`), never line numbers (`cq-cite-content-anchor-not-line-number`).

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` — the `# ---- T9:` block only: evidence-capture awk, the two `tb_ok` rows, the `poll` bound, and the diagnostic text.

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** a still-flaky or silently-weakened Infra Validation leg — engineers (the users of this CI surface) keep seeing red legs on unrelated PRs, or worse, a real start-timeout-reporting regression slips through because the assertion now greens on nothing.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the diff is confined to a test harness asserting on a stubbed in-container log; it touches no user data, credential path, or provisioning behavior.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the only file touched is a test harness asserting on stubbed container log rows; the sensitive-path match is the apps/*/infra/ prefix on a *.test.sh, and no runtime infra or user-facing behavior changes`

## Observability

```yaml
liveness_signal:
  what: "Infra Validation matrix legs green — 'Run registered infra suites' step"
  cadence: "per pull_request run and per main push"
  alert_target: "PR required-check status; on main-red, ops email via the workflow's on-main-red notification step"
  configured_in: ".github/workflows/infra-validation.yml (matrix legs; suite executed via apps/web-platform/infra/run-registered-suites.sh)"

error_reporting:
  destination: "GitHub Actions job log + uploaded artifact infra-suite-logs-<leg>"
  fail_loud: "RED apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh + '##[error]suite failed (rc=1)'; per-row 'FAIL: T9: ...' lines name via= and observed timestamps"

failure_modes:
  - mode: "T9 exit-143 evidence absent on BOTH channels again under load"
    detection: "T9 rows red with via=none and the observed-row listing in the FAIL line"
    alert_route: "PR check red; ops email if on main"
  - mode: "real TERM-trap regression (kill no longer reported)"
    detection: "T9 reds identically — the dual-channel read only tolerates single-channel loss, never total absence"
    alert_route: "PR check red; ops email if on main"
  - mode: "attempt=2 restart never observed inside the widened poll"
    detection: "ordering row reds with s=missing in the diagnostic"
    alert_route: "PR check red; ops email if on main"

logs:
  where: "GH Actions job log (SOLEUR| marker-anchored excerpt) + artifact apps_web-platform_infra_cloud-init-inngest-provision-unit.test.sh.log (full timestamped call-log dump)"
  retention: "artifact retention-days: 14"

discoverability_test:
  command: grep -rn 'provision-attempt-exit-143' apps/web-platform/infra/
  expected_output: "provision-attempt-exit-143"
```

## Guard Contract

The deliverable modifies rows of an assertion-based CI check — one guard entry covers the reworked T9 assertions as a unit.

### Guard 1 — T9 exit-143 reporting assertions

**Property.** When the start timeout kills an in-flight provision attempt, the attempt's rc=143 is reported on at least one designed channel (phone or emit) within 15 s of that attempt's recorded start, and strictly before the next attempt's start row; absence on both channels must red.

**Assembly.** The T9 block of `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` (evidence-capture awk, both `tb_ok` rows, the `poll` for `attempt=2`), plus the emit chain it observes: the `trap ... TERM INT` → `on_exit()` → `inngest-boot-phone-home.sh` / `soleur-boot-emit` path in `cloud-init-inngest.yml`'s provision script. The single chokepoint every member flows through is the container's `/var/lib/tierb/calls.log` append — the assertions read only that file, so the assembly is complete by construction.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Render mutation: change the TERM trap to `exit 1` (kills the 143 propagation) | RED — no rc=143 evidence on either channel for `attempt=1` |
| 2 | Render mutation: delete the `on_exit` EXIT trap (dispatch row — the guard's subject produces no exit reports at all) | RED — T9 must not certify a system that reports nothing |
| 3 | Harness/fixture mutation: emit stub drops `provision_attempt_failed` rows, phone stub intact | PASS — single-channel survival is the contract's permitted shape (non-canonical must-PASS) |
| 4 | Harness/fixture mutation: phone stub drops `provision-attempt-exit-*` rows, emit stub intact — the observed flake shape | PASS — the exact loss this fix tolerates |
| 5 | Harness/fixture mutation: BOTH stubs drop the attempt-1 exit rows | RED — total-evidence absence must still red |
| 6 | Order/lifetime row: craft the log slice so `provision-attempt-start attempt=2` precedes the attempt-1 exit evidence | RED — the ordering row asserts a happens-before, not mere presence |

**Anchor.** The guard compares no stored values; its fixture-mutation rows (3–5) cover the one-diff-both-sides risk — the fixture and the assertion live in the same file, and each row names whether the mutation lands on the fixture or the assertion path.

Rows 1–2 execute against the rendered script via the suite's existing `row <id> <RED|PASS>` mutation battery if practical; rows 3–6 are exercisable as deterministic fixture edits or, cheaper, by unit-testing the extraction awk against canned log slices — the implementation may choose the cheapest form that still drives each row's stated expectation.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — a test-harness assertion fix inside one CI suite. Assessment per the Phase 2.5 sweep: no user-facing pages/flows (Product — mechanical UI-surface override also clear: the only edited file is `*.test.sh`, matching no UI-surface term), no legal documents or regulated-data surfaces (Legal), no content/brand/messaging (Marketing), no vendors/procurement (Operations), no revenue pipeline (Sales), no budgeting (Finance), no support workflows (Support), and no architectural or new-infrastructure decision (Engineering — a timing-assertion repair on an existing suite is normal implementation). No Task-spawning capability exists in this subagent process; the sweep was assessed inline against the config's Assessment Questions.

## Acceptance Criteria

- [ ] **AC1** — In `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`'s T9 block (`# ---- T9:`), the exit-evidence capture accepts either the phone row `provision-attempt-exit-143` with `attempt=1` or the emit row `provision_attempt_failed` with `rc=143.attempt=1.`, and the timing row evaluates `e - b <= 15` against the attempt-1 `provision-attempt-start` anchor (bootstrap-start fallback permitted when the start row is absent).
- [ ] **AC2** — The ordering row compares only the attempt-1 exit evidence's position against `provision-attempt-start attempt=2`'s; a teardown-produced `attempt=2` exit-143 row can neither satisfy nor break it.
- [ ] **AC3** — The `attempt=2` wait uses a bound no smaller than T10's (`poll 90`), and both `tb_ok` diagnostics print the satisfying channel (`via=`) plus the observed timestamps.
- [ ] **AC4** — With the phone stub made to drop `provision-attempt-exit-*` writes (the observed flake shape, Guard-matrix row 4), the suite's T9 rows are green.
- [ ] **AC5** — With BOTH emit channels suppressed for the killed attempt (row 5), or the TERM trap changed to `exit 1` (row 1), the suite reds on T9 — the fix tolerates channel loss, never evidence absence.
- [ ] **AC6** — `bash apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` exits 0 locally (docker present) with T9 green; a load run consistent with the SIGPIPE learning's convention (repeated/parallel suite copies) shows no T9 miss.
- [ ] **AC7** — The diff's code surface is confined to the single test file: `git diff --name-only origin/main...HEAD` shows `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` plus `apps/web-platform/infra/run-registered-suites.sh` (the `_SUITE_BOUNDS` pin added at review) as the only non-`knowledge-base/` paths (planning artifacts — this plan, `specs/<branch>/tasks.md`, and pipeline bookkeeping — are expected and out of the code-scope claim; the merge-base `...` form is required so a sibling merge does not false-red the check).

## Test Scenarios

- **Given** the T9 fixture running under a starved runner where the phone stub's exit-143 write is lost, **when** T9 evaluates the snapshot, **then** both T9 rows pass using the emit-channel `rc=143.attempt=1.` row (the exact artifact shape from run 36525271493).
- **Given** the emit stub's `provision_attempt_failed` write is dropped instead, **when** T9 evaluates, **then** the phone-channel row satisfies both assertions (`via=phone`).
- **Given** both channels drop the killed attempt's exit rows, **when** T9 evaluates, **then** both rows red and the FAIL text contains `via=none`.
- **Given** `provision-attempt-start attempt=2` appears before any attempt-1 exit evidence in the slice, **when** the ordering row evaluates, **then** it reds (reorder case, matrix row 6).
- **Given** the rendered script's TERM trap exits 1 instead of 143, **when** the suite reaches T9, **then** the timing row reds — the guard still detects a broken kill-report path.
- **Local verification:** `bash apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh` (docker required; Tier B runs systemd 255 in a privileged container) — expect `TIERB_RESULT` reporting T9 PASS and suite rc=0, ~350 s.
- **Fixture-level check (fast):** exercise the new evidence-capture awk against a canned log slice reproducing the artifact's T9 window — absent phone row, present emit row — and assert `via=emit`.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (87 issues) contains no body mention of `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`.

## Success Metrics

- Zero T9 reds attributable to single-channel emit loss on the next 20 Infra Validation runs that execute this suite; the 2026-09-29 failure shape (present `emit rc=143`, absent `phone exit-143`) greens deterministically under the fixture-level repro of AC4.
- No increase in suite wall time beyond the widened `attempt=2` poll's idle headroom (suite currently ~351 s).

## Dependencies & Risks

- **Risk:** the emit channel could also be lost under extreme load, re-flaking T9 on `via=none`. Mitigation: two independent emit sites ~2 ms apart make double-loss orders of magnitude rarer; if it recurs, the honest fix is queueing the writes, not relaxing the assertion — file a new issue rather than widening again.
- **Risk:** a future edit to `on_exit()`'s emit ordering or field shape breaks the `rc=143.attempt=1.` matcher. Mitigation: the matcher anchors on the documented emit format (`rc=<n>.attempt=<n>.why=…`); the suite's own mutation battery and G-guard static checks pin the script shape.
- **Dependency:** Tier B needs docker + a privileged systemd container — unchanged; the workflow's `docker info` fail-closed step already precedes suite execution.

## References & Research

- Issue: #9195; context: #9123 (closed), #8562; sibling flakes: #9126 (suite-load flake), #7376 (OPEN — `run-registered-suites.sh` flaky under its default `-P` on a 4-core runner: the systemic runner-load surface this issue is one symptom of; this fix removes one assertion-level victim, not the load itself); diagnostics precedent: #7374/#7376
- Failing runs: 36520108194 (job 109250958452), 36525271493 (job 109266901611, artifact `infra-suite-logs-2` — timestamped call log quoted in Problem Statement)
- Provision script under test: `apps/web-platform/infra/cloud-init-inngest.yml` (`on_exit()` / `trap … TERM INT` anchors)
- Learnings: `2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md`, `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`, `test-failures/2026-09-25-the-flake-was-sigpipe-at-4kib-and-my-fix-leaked-a-pipe-status-through-a-bare-return.md`
- Runner-load context: `knowledge-base/project/brainstorms/2026-09-21-ci-runner-concurrency-brainstorm.md` (~250 runs/hr vs 20-job ceiling)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 — filled above with the `threshold: none` scope-out bullet this sensitive-path diff requires.
- The T9 assertions must be edited inside the existing `# ---- T9:` block; the `awk` matchers quote `attempt=1` / `rc=143.attempt=1.` literally — do not relax them to bare-token greps, and do not cite line numbers in new comments.
- `lines_from`/`poll`/`tb_ok` are shared helpers consumed by T10–T15; changes must stay inside the T9 block (AC7) — a helper signature change ripples into every other phase's assertions.
