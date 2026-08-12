---
feature: lock-timeout-no-isolation
issue: 7484
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-12-fix-instrument-advisory-lock-wait-plan.md
date: 2026-08-12
---

# Tasks — report the measured advisory-lock wait

Derived from the **v2** plan (post plan-review; v1 cut ~70%). Only three files change.

## Phase 1 — Setup

- [ ] **1.1** Re-read `tc_acquire` in `scripts/lib/test-contention.sh` and `run_suite`'s
  `EPOCHREALTIME` block in `scripts/test-all.sh` (the idiom to lift, not import).
- [ ] **1.2** Confirm the branch is `feat-lock-timeout-no-isolation` and draft PR #7483 is open.

## Phase 2 — Core implementation (`scripts/lib/test-contention.sh` ONLY)

- [ ] **2.1** Add `_tc_ms_since` helper — `[[ "$start" == *.* ]]` glob guard, `10#` base-10 forcing.
  Comment it as a deliberate duplication of `run_suite`'s idiom (the lib must not depend on the script).
- [ ] **2.2** Add `command -v flock` to the precondition block, emitting the **existing**
  `LOCK_UNAVAILABLE` banner. No new outcome name.
- [ ] **2.3** Emit `LOCK_WAITING` immediately before `acquire_lock`, after all skip checks.
- [ ] **2.4** Wrap **only** the `acquire_lock` call in the measurement.
- [ ] **2.5** Rewrite the `LOCK_ACQUIRED` text to carry the measured elapsed.
- [ ] **2.6** Rewrite the `LOCK_CONTENDED_PROCEEDING` text to report the measured elapsed instead of
  asserting `still held after ${timeout_s}s`.
- [ ] **2.7** Print `unknown` (never a fabricated `0ms`) when `EPOCHREALTIME` is unavailable.
- [ ] **2.8** **Verify both banner tokens are byte-identical to before.** `work/SKILL.md`'s grep,
  ADR-133 and arms 10–13 all match on the token; only post-colon text may change.

## Phase 3 — Tests (`scripts/test-contention.test.sh`)

- [ ] **3.1** Extend arm 10 — assert the elapsed appears in `LOCK_ACQUIRED`.
- [ ] **3.2** Extend arm 11 — assert the elapsed appears in `LOCK_CONTENDED_PROCEEDING` and that the
  old asserted-duration phrasing is gone.
- [ ] **3.3** **New arm — slow acquire.** Holder releases mid-wait (`sleep 2` under a 6 s timeout);
  assert `LOCK_ACQUIRED` with non-trivial elapsed. *No existing arm produces this outcome, and it is
  the one the whole PR exists to prove reachable.*
- [ ] **3.4** **New arm — `flock` missing.** Mask `flock` off `PATH`; assert `LOCK_UNAVAILABLE` and
  NOT `LOCK_CONTENDED_PROCEEDING`.
- [ ] **3.5** Assert every `tc_acquire` exit path still returns `0` (AC6).
- [ ] **3.6** Run arm 15 — confirm its negative grep still returns zero. Avoid
  `kill -0` / `stale_pid` / `holder_pid` tokens even in **trailing** comments (it strips only
  full-line comments).

## Phase 4 — Mutation verification (Guard 1)

Each must drive the suite RED, then be reverted:

- [ ] **4.1** Replace the measured elapsed with literal `${timeout_s}` in the contended banner.
- [ ] **4.2** Delete the `command -v flock` precheck.
- [ ] **4.3** Make the slow-acquire holder never release.
- [ ] **4.4** Remove the elapsed from `LOCK_ACQUIRED`.
- [ ] **4.5** Change a banner token.

## Phase 5 — Docs and handoff

- [ ] **5.1** Append the third ADR-133 addendum. Do **not** restate the follow-up trigger there.
- [ ] **5.2** Post the Phase 4 comment on #7454 recording the reframed question (its item 3 covers
  admission control, not timeout-vs-holder-age).
- [ ] **5.3** Confirm AC8 — `git diff --name-only origin/main...HEAD` lists neither
  `scripts/test-all.sh` nor `plugins/soleur/scripts/lib/session-state.sh`.
- [ ] **5.4** Run `bash scripts/test-contention.test.sh` (the discoverability probe).

## Carried risk

**Two reviewer lenses are UNCOVERED** — Kieran (correctness/convention) and architecture-strategist
(blast radius) both died on the weekly API limit. The `_tc_ms_since` duplication in 2.1 is precisely
what Kieran was asked to judge. Re-review before ship. See `plan-review-findings.md`.
