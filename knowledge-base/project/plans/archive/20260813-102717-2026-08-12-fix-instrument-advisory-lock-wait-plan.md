---
title: "fix(test): report the measured advisory-lock wait instead of asserting one"
date: 2026-08-12
slug: fix-instrument-advisory-lock-wait
branch: feat-lock-timeout-no-isolation
issue: 7484
closes: 7484
lane: cross-domain
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-08-12-lock-timeout-no-isolation-brainstorm.md
spec: knowledge-base/project/specs/feat-lock-timeout-no-isolation/spec.md
plan_review: knowledge-base/project/specs/feat-lock-timeout-no-isolation/plan-review-findings.md
related_adrs: ["ADR-133"]
revision: v2 (post plan-review; v1 cut by ~70% — see plan-review-findings.md)
---

# Report the measured advisory-lock wait instead of asserting one

## Overview

`scripts/test-all.sh` takes a cross-worktree advisory lock (ADR-133 Decision 3). It is fail-open: on
timeout it prints `LOCK_CONTENDED_PROCEEDING` and proceeds. `TC_LOCK_TIMEOUT` defaults to 900 s.

Measured 2026-08-11 (ADR-133 addendum): a run waited the **full 900 s** and proceeded while three
sibling runs executed concurrently — 15 minutes on the ship critical path, zero isolation.

**Two things are actually wrong today, and both are cheap:**

1. **The banner asserts a duration nobody measured.** `still held after ${timeout_s}s` prints
   unconditionally whenever `acquire_lock` returns non-zero — including when it returned `99` because
   `flock(1)` is missing or the lock file could not be opened. Nothing was held; the statement is
   false. `work/SKILL.md` documents an agent-facing grep on `LOCK_CONTENDED` that consumes this line
   to decide whether a RED is trustworthy.
2. **No run records how long it actually waited**, so nobody can say whether a wait ever succeeds.

This plan fixes both by **printing the duration that was measured instead of asserting one that was
not**, and by removing the `rc=99` ambiguity at its source. It changes no mechanism: the timeout keeps
its value, the lock keeps its fail-open contract, every `tc_acquire` path still returns `0`.

### What this delivers — and what it deliberately does not

**Honest claim (revised after plan review):** this produces, per run, in the operator terminal and the
agent transcript, *how long the wait took and how it ended*. Over successive runs a reader can answer
**"does the wait ever pay off, and what is the longest wait that was redeemed?"**

**It does NOT decide between raising `TC_LOCK_TIMEOUT` and short-circuiting on holder age**, and v1 of
this plan wrongly claimed it would. Two reasons, both structural:

- Contended observations are **right-censored** at the fixed 900 s budget, so they cannot answer
  "would 1,800 s have succeeded?" — precisely the raise-the-timeout question.
- The short-circuit option's parameter is the **holder's** remaining run; every measurement here is of
  the **waiter**.

That correction is why this plan no longer ships a persistence schema: v1 wrote a row to
`TEST_TIMING_LOG`, which **is set nowhere in any automated path** (four independent confirmations —
see `plan-review-findings.md`). Writing a durable row to a channel nothing sets, and calling the
resulting ratio derivable, would have shipped the second instance of a writer-with-no-reader in a repo
that already carries the learning about exactly that. Persistence is a real question with its own
blast radius (it means changing a shared default) and it belongs in its own PR — recorded as UC-1 in
`decision-challenges.md`.

Measurement-before-mechanism still stands: the two candidate fixes point opposite ways, and the
docker-healthcheck learning is the documented precedent for what happens if you guess.

## Key Design Decisions

**D1 — everything is confined to `tc_acquire`.** It measures, it classifies nothing, it prints. No
globals, no cross-file transport, no emit function. `scripts/test-all.sh` is **untouched**.

*This is what the v1→v2 cut bought.* Three separate v1 defects dissolved rather than being fixed: the
`P0` gate-wedge (a `set -euo pipefail` read of an unset global on the lib-missing stub path), the
`timeout_s`-has-no-writer bug (it is a `local` in `tc_acquire`, unreadable from `test-all.sh`), and the
collision with `test-all-killed-classification.test.sh`'s unique-anchor assertion.

**D2 — print the measured elapsed; classify nothing.** v1 split `rc=99` into `contended` vs
`precondition_failed` using an elapsed-time threshold. Cut unanimously: it computed nothing a reader
cannot compute, and it required two thresholds the plan never assigned — with no enum member for the
middle band. `gave up after 3ms of 900s` **is** the precondition failure, legible without a name.

**D3 — remove the `rc=99` ambiguity at its source, using existing vocabulary.** Add `command -v flock`
to the precondition checks that already emit **`LOCK_UNAVAILABLE`**. This is exact where a time
threshold is approximate, needs no new banner and no new outcome name, and matches the case's real
meaning: the serialization layer is unavailable. `tc_acquire` already has that vocabulary for
"session-state.sh not found" and "acquire_lock not defined" — a missing `flock` is the same class.

**D4 — the `LOCK_WAITING` disclosure stays a plain line, deliberately.** It fires on every run that
reaches the wait, and `work/SKILL.md`'s grep was anchored specifically to avoid always-firing hits. It
is a live-stderr affordance so a 15-minute wait reads as a queue rather than a hang — **not** a
trustworthiness signal. Stated here because it is otherwise an invisible design choice.

## Implementation Phases

### Phase 1 — measure and report (`scripts/lib/test-contention.sh` only)

1. Add `_tc_ms_since`, a small helper wrapping the `EPOCHREALTIME` idiom already used by `run_suite`
   (`[[ "$start" == *.* ]]` glob guard, `10#` base-10 forcing). **Accepted duplication:** the idiom
   lives in `scripts/test-all.sh`; the lib must not depend on the script, so the arithmetic is
   duplicated rather than imported. Cite the source idiom in a comment.
2. Add `command -v flock` to the precondition block, emitting the existing `LOCK_UNAVAILABLE` (D3).
3. Emit `LOCK_WAITING` immediately before `acquire_lock`, after all skip checks — so its presence
   marks "this run reached the wait" (P3).
4. Wrap **only** the `acquire_lock` call in the measurement.
5. Print the measured duration in both post-wait banners, replacing the asserted one:
   - `LOCK_ACQUIRED: '<name>' after <N>ms …`
   - `LOCK_CONTENDED_PROCEEDING: '<name>' — gave up after <N>ms of <timeout_s>s …`
   Keep both **token prefixes byte-identical** (`LOCK_ACQUIRED`, `LOCK_CONTENDED_PROCEEDING`):
   `work/SKILL.md`'s grep, ADR-133, and `scripts/test-contention.test.sh` all match on the token.
   Only the text after the colon changes.
6. When timing is unavailable (bash 3.2, empty `EPOCHREALTIME`), print `unknown` rather than a
   fabricated `0ms`. One `printf` branch, no dedicated arm — `run_suite` already fabricates `0` for
   every suite on that host and `test-all.sh` documents it as accepted.

### Phase 2 — tests (`scripts/test-contention.test.sh`)

7. Extend arms 10 and 11 to assert the elapsed value appears in the banner they already grep.
8. **New arm — slow acquire.** A holder that **releases mid-wait** (`sleep 2` under a 6 s timeout),
   asserting `LOCK_ACQUIRED` with a non-trivial elapsed. This is the single outcome the whole PR
   exists to prove reachable, and no existing arm produces it: arm 10 acquires a free lock (near-zero),
   arm 11's holder never releases.
9. **New arm — `flock` missing.** With `flock` masked off `PATH`, assert `LOCK_UNAVAILABLE` and **not**
   `LOCK_CONTENDED_PROCEEDING`.
10. Confirm arm 15 still passes. It strips only **full-line** comments before grepping code for
    `kill -0|/proc/[^/]*holder|stale_pid|holder_pid` — so avoid those tokens in *trailing* comments.

### Phase 3 — ADR-133 addendum

11. Append a short third addendum: the banners now report a measured duration; the `rc=99` ambiguity is
    resolved via `command -v flock`; and the mechanism question remains open. **Do not restate the
    follow-up trigger here** — it lives in one place (Phase 4), and two copies of a trigger is how
    triggers drift.

### Phase 4 — give the deferred question a home

12. #7454 item 3 is scoped to *`/tmp`-headroom admission control* with the multi-run budget as its
    trigger — it does **not** cover "raise the timeout vs short-circuit on holder age", so that
    question currently has no tracker. Post a comment on #7454 recording the reframed question, what
    this PR measured, and what would answer it (an uncensored observation: either a varied timeout, or
    the holder's age at wait time). Owner and cadence named.

## Acceptance Criteria

Every criterion is a claim about the code under a **synthetic fixture the plan controls** — an
isolated `SOLEUR_SESSION_STATE_ROOT`, a synthesized holder, a masked `PATH`. None asserts the absence
of an ambient signal (`cq-ac-must-not-depend-on-concurrent-sessions`).

- **AC1** Against a free lock in an isolated state root, `LOCK_ACQUIRED` carries a measured elapsed.
- **AC2** Against a holder that outlives the timeout, `LOCK_CONTENDED_PROCEEDING` reports the measured
  elapsed and no longer asserts `still held after <timeout>s`.
- **AC3** Against a holder that **releases mid-wait**, `LOCK_ACQUIRED` is emitted with a non-trivial
  elapsed — proving a slow acquire is reachable and distinguishable from a timeout.
- **AC4** With `flock` unavailable, `LOCK_UNAVAILABLE` is emitted and `LOCK_CONTENDED_PROCEEDING` is
  not.
- **AC5** `LOCK_WAITING` precedes the wait and is absent on every skip path (verified by ordering).
- **AC6** Every `tc_acquire` exit path still returns `0` (TR2) — asserted, not assumed.
- **AC7** The banner **tokens** `LOCK_ACQUIRED` and `LOCK_CONTENDED_PROCEEDING` are unchanged, so
  `work/SKILL.md`'s grep and arms 10–13 still match.
- **AC8** *(amended at review — see below)* `plugins/soleur/scripts/lib/session-state.sh` is untouched:
  `git diff --name-only origin/main...HEAD` does not list it. `scripts/test-all.sh` is touched by
  **exactly one** change — `$EPOCHREALTIME` → `${EPOCHREALTIME:-}` at `run_suite`'s two timing reads,
  plus the comment correcting what that file claims about its own degraded behaviour. Mechanically:
  `git diff -U0 origin/main...HEAD -- scripts/test-all.sh | grep '^[+-]' | grep -v '^[+-][+-]'` shows
  only `EPOCHREALTIME` lines and comment lines, and no change to `TC_LOCK_TIMEOUT`, to the
  `tc_acquire` call site, or to any `run_suite` control flow.

  **Why AC8 was amended rather than satisfied.** The original form asserted `test-all.sh` untouched,
  to fence out the *mechanism* change (raising the timeout / short-circuiting on holder age). Review
  measured a pre-existing defect in that file of the same class this PR fixes in the lib: both timing
  reads are bare `$EPOCHREALTIME` under `set -euo pipefail`, so on a shell without the variable
  `run_suite` **aborts on its first suite** — no summary, no rc file, no `[FAIL]`, which is precisely
  the signature `work/SKILL.md` attributes to a harness reap, sending the operator into a relaunch
  loop. The file's own comment claimed the opposite ("computes 0 silently"). AC8's *intent* —
  no mechanism drift — is preserved and now asserted directly; only its literal file-list form
  changed. Fixing a two-line unbound-variable abort while shipping the identical fix one file over,
  and declining to fix it because of a boundary drawn for a different reason, would have been
  scope discipline in form and incoherence in substance.
- **AC9** Arms 10–15 pass; arm 15's negative grep still returns zero.
- **AC10** ADR-133 carries a third addendum; no new ADR file is created.
- **AC11** #7454 carries the Phase 4 comment.

### Post-merge

None. No deploy step, no infrastructure, no operator action.

## Guard Contract

### Guard 1 — the banner reports a measured duration, never an asserted one

**Property.** No `tc_acquire` output may state a wait duration that was not measured, and no
non-timeout failure may be reported as a timeout.

**Assembly.** The chokepoint is the pair of exits *after* the measured `acquire_lock` call — the only
two places a duration is printed. The structural risk is not a future seventh exit path (there are no
globals to go stale now) but a future edit re-introducing a **literal** `${timeout_s}` into the
contended banner. Mutation row 1 targets exactly that.

**Mutation matrix** (each MUST drive the suite RED):

| # | Mutation | Must redden |
|---|---|---|
| 1 | Replace the measured elapsed with the literal `${timeout_s}` in the contended banner (restores the original lie) | AC2 arm |
| 2 | Delete the `command -v flock` precheck | AC4 arm — *adds a second failure class after a compliant first* |
| 3 | Make the slow-acquire fixture's holder never release | AC3 arm — *proves the arm distinguishes a slow acquire from a timeout, rather than passing on any `LOCK_ACQUIRED`* |
| 4 | Remove the elapsed from `LOCK_ACQUIRED` | AC1 arm |
| 5 | Change either banner token | AC7 arm — *catches the contract break the text edit could silently cause* |

## Observability

```yaml
liveness_signal:
  what: "measured wait duration printed in the LOCK_ACQUIRED / LOCK_CONTENDED_PROCEEDING banners"
  cadence: "once per run that reaches the lock"
  alert_target: "none — operator terminal and agent transcript; operator-local dev tooling, not production"
  configured_in: "scripts/lib/test-contention.sh (tc_acquire)"
error_reporting:
  destination: "stderr, via the existing [contention] banner vocabulary"
  fail_loud: "no — deliberately. ADR-133 Decision 3 makes every lock path fail-open; an instrument that could wedge the run it measures would violate the contract it exists to observe."
failure_modes:
  - mode: "flock(1) unavailable or session-state lib missing"
    detection: "LOCK_UNAVAILABLE banner (exact, via command -v — not inferred from elapsed time)"
    alert_route: "operator terminal; work/SKILL.md's contention grep"
  - mode: "EPOCHREALTIME unavailable (bash 3.2)"
    detection: "the banner prints 'unknown' rather than a fabricated 0ms"
    alert_route: "visible in the banner itself"
  - mode: "a future edit re-asserts an unmeasured duration"
    detection: "Guard 1 mutation row 1"
    alert_route: "CI test failure"
logs:
  where: "operator terminal / agent transcript. No file is written and no new channel is created."
  retention: "transcript-scoped"
discoverability_test:
  command: "bash scripts/test-contention.test.sh"
  expected_output: "exit 0; every arm reports PASS, including the new slow-acquire and flock-missing arms"
```

## User-Brand Impact

Carried forward from the brainstorm:

- **If this lands broken, the user experiences:** nothing user-facing. The artifact is the
  `scripts/test-all.sh` advisory-lock wait — internal developer/agent tooling on the operator's own
  machine. A broken change degrades to a less informative banner.
- **If this leaks:** no customer surface, no shipped runtime path, no data at risk. Worst outcome is
  latency on the ship critical path.
- **Brand-survival threshold:** `single-user incident` — recorded per policy, **and recorded as a poor
  fit.** Per the CPO: that threshold catches things where one user hitting it damages trust in the
  product; nobody outside the build loop can reach this. Weigh it as throughput cost, not brand risk.
  `requires_cpo_signoff: true` is satisfied by the brainstorm-time CPO assessment.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm).

### Engineering (CTO)
**Status:** reviewed. A calibration defect, not a design defect; fail-open is correct and kept.
Flagged at plan review that `TEST_TIMING_LOG` is set nowhere — the finding that drove the v2 cut.

### Product (CPO)
**Status:** reviewed. Real cost, worth a PR now; sequence before #7376/#7432, since a no-op tax on
every evidence run slows the soak those issues need.

### Legal (CLO)
**Status:** reviewed. No legal, compliance, regulatory or licensing surface.

### Product/UX Gate
Not applicable — no UI-surface path in Files to Edit. Tier: **NONE**.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-133** with a third addendum. No new ADR, no new ordinal claimed.

### C4 views
**No C4 impact.** Checked by reading all three of `model.c4`, `views.c4`, `spec.c4` — not a keyword
grep. **External human actors:** none added (`founder`, `externalCorrespondent`, `betaContact` and the
untrusted-contributor actor are all already modeled). **External systems/vendors:** none. **Containers
/ data stores:** none — and v2 writes no file at all. **Access relationships:** none changed.
`model.c4` already describes operator-side execution of a checked-out PR head — *"running its tests,
its scripts, its hooks"* — as covered by neither the CI nor the preflight-sandbox boundary; this change
lives entirely inside that already-described space.

## Files to Edit

- `scripts/lib/test-contention.sh` — `_tc_ms_since`, the `command -v flock` precheck, `LOCK_WAITING`,
  the measurement, and the two rewritten banner texts.
- `scripts/test-contention.test.sh` — extend arms 10–11; add slow-acquire and flock-missing arms.
- `knowledge-base/engineering/architecture/decisions/ADR-133-…-advisory-lock.md` — third addendum.

- `scripts/test-all.sh` — **added at review**, and bounded by the amended AC8: the two
  `${EPOCHREALTIME:-}` guards in `run_suite` plus the comment that misdescribed the degradation.
  No mechanism change.
- `plugins/soleur/skills/work/SKILL.md` — **added at review**: the queue-vs-hang prose documented the
  parked-run signature as "the contention preamble and then nothing (~1206 bytes)", which
  `LOCK_WAITING` invalidates. Re-anchored on the new marker.

**Explicitly NOT edited** (asserted by AC8): `plugins/soleur/scripts/lib/session-state.sh`,
`scripts/test-all-killed-classification.test.sh`, `scripts/test-all-infra-coverage-notice.test.sh`.

## Files to Create

None.

## Open Code-Review Overlap

**None** — `gh issue list --label code-review --state open --limit 200` returned no issue body
containing any file in this plan.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Editing banner text breaks a downstream matcher | Tokens held byte-identical; AC7 + mutation row 5 assert it. |
| `_tc_ms_since` duplicates `run_suite`'s arithmetic | Accepted and commented — the lib must not depend on the script. **Flagged as an uncovered lens:** this is exactly what the failed Kieran review was asked to check. |
| The measurement perturbs what it measures | Two `EPOCHREALTIME` reads around an already-blocking call. Nothing added inside the wait. |
| Scope drift into the mechanism change | Non-Goals below; AC8 mechanically asserts both out-of-scope files are untouched. |
| **Panel coverage gap** | Kieran (correctness/convention) and architecture-strategist (blast radius) both died on the weekly API limit. Their lenses are UNCOVERED — see `plan-review-findings.md`. A re-review is owed before ship. |

## Non-Goals

`/tmp`-headroom admission control including the "headroom bypass on top of the mutex" (gated behind
#7454 item 3); changing `TC_LOCK_TIMEOUT`'s value; short-circuiting on sibling detection or holder
age; abort-on-timeout (REJECTED in ADR-133 Alternatives); concurrency-N semaphores, per-suite locks,
fair-share queueing, defaulting the lock off; any change to the CI exemption or the
`SOLEUR_DISABLE_SESSION_STATE` kill switch; any change to `session-state.sh`; **persisting the
measurement to any file or making `TEST_TIMING_LOG` default to a real path** (UC-1); any of #7454's
three deferred items.

## Deferred

1. **Persistence / cross-run accumulation** — UC-1 in `decision-challenges.md`. Requires changing a
   shared default; deserves its own blast-radius argument.
2. **The mechanism change** — raise `TC_LOCK_TIMEOUT` vs short-circuit on holder age. Mutually
   exclusive; must not both ship. **Re-evaluate when** an *uncensored* observation exists — either a
   varied timeout, or the holder's age recorded at wait time. Tracked via the Phase 4 comment on
   #7454, since that issue's item 3 covers a different question (admission control).
