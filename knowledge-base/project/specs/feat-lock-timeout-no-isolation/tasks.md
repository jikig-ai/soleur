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

- [x] **1.1** Re-read `tc_acquire` in `scripts/lib/test-contention.sh` and `run_suite`'s
  `EPOCHREALTIME` block in `scripts/test-all.sh` (the idiom to lift, not import).
- [x] **1.2** Confirm the branch is `feat-lock-timeout-no-isolation` and draft PR #7483 is open.

## Phase 2 — Core implementation (`scripts/lib/test-contention.sh` ONLY)

- [x] **2.1** Add `_tc_ms_since` helper — `[[ "$start" == *.* ]]` glob guard, `10#` base-10 forcing.
  Comment it as a deliberate duplication of `run_suite`'s idiom (the lib must not depend on the script).
- [x] **2.2** Add `command -v flock` to the precondition block, emitting the **existing**
  `LOCK_UNAVAILABLE` banner. No new outcome name.
- [x] **2.3** Emit `LOCK_WAITING` immediately before `acquire_lock`, after all skip checks.
- [x] **2.4** Wrap **only** the `acquire_lock` call in the measurement.
- [x] **2.5** Rewrite the `LOCK_ACQUIRED` text to carry the measured elapsed.
- [x] **2.6** Rewrite the `LOCK_CONTENDED_PROCEEDING` text to report the measured elapsed instead of
  asserting `still held after ${timeout_s}s`.
- [x] **2.7** Print `unknown` (never a fabricated `0ms`) when `EPOCHREALTIME` is unavailable.
- [x] **2.8** **Verify both banner tokens are byte-identical to before.** `work/SKILL.md`'s grep,
  ADR-133 and arms 10–13 all match on the token; only post-colon text may change.

## Phase 3 — Tests (`scripts/test-contention.test.sh`)

- [x] **3.1** Extend arm 10 — assert the elapsed appears in `LOCK_ACQUIRED`.
- [x] **3.2** Extend arm 11 — assert the elapsed appears in `LOCK_CONTENDED_PROCEEDING` and that the
  old asserted-duration phrasing is gone.
- [x] **3.3** **New arm — slow acquire.** Holder releases mid-wait (`sleep 2` under a 6 s timeout);
  assert `LOCK_ACQUIRED` with non-trivial elapsed. *No existing arm produces this outcome, and it is
  the one the whole PR exists to prove reachable.*
- [x] **3.4** **New arm — `flock` missing.** Mask `flock` off `PATH`; assert `LOCK_UNAVAILABLE` and
  NOT `LOCK_CONTENDED_PROCEEDING`.
- [x] **3.5** Assert every `tc_acquire` exit path still returns `0` (AC6).
- [x] **3.6** Run arm 15 — confirm its negative grep still returns zero. Avoid
  `kill -0` / `stale_pid` / `holder_pid` tokens even in **trailing** comments (it strips only
  full-line comments).

## Phase 4 — Mutation verification (Guard 1)

Each must drive the suite RED, then be reverted:

- [x] **4.1** Replace the measured elapsed with literal `${timeout_s}` in the contended banner.
- [x] **4.2** Delete the `command -v flock` precheck.
- [x] **4.3** Make the slow-acquire holder never release.
- [x] **4.4** Remove the elapsed from `LOCK_ACQUIRED`.
- [x] **4.5** Change a banner token.

## Phase 5 — Docs and handoff

- [x] **5.1** Append the third ADR-133 addendum. Do **not** restate the follow-up trigger there.
- [x] **5.2** Post the Phase 4 comment on #7454 recording the reframed question (its item 3 covers
  admission control, not timeout-vs-holder-age).
- [x] **5.3** Confirm AC8 — `git diff --name-only origin/main...HEAD` lists neither
  `scripts/test-all.sh` nor `plugins/soleur/scripts/lib/session-state.sh`.
- [x] **5.4** Run `bash scripts/test-contention.test.sh` (the discoverability probe).

## Carried risk

**Two reviewer lenses are UNCOVERED** — Kieran (correctness/convention) and architecture-strategist
(blast radius) both died on the weekly API limit. The `_tc_ms_since` duplication in 2.1 is precisely
what Kieran was asked to judge. Re-review before ship. See `plan-review-findings.md`.

## Evidence — 2026-08-12

Each box above was checked against a run, not a recollection.

**UC-1 decided** (DHH's position: no persistence row). The premise was re-derived, not restated:
`git grep -nE 'TEST_TIMING_LOG='` returns ten hits, every one a test arm redirecting into its own
sandbox or a plan documenting a manual one-off. Recorded append-only in `decision-challenges.md`.

**RED → GREEN.** RED run: 8 failures, all in the new assertions, and the flock arm reproduced the
`rc=99` ambiguity verbatim (`session-state: flock(1) not found` followed by a
`LOCK_CONTENDED_PROCEEDING` for a wait that never happened). GREEN: **92 passed, 0 failed**.

**The arms discriminate by VALUE, not shape.** One run produced three distinct elapsed readings —
free lock `8ms`, wait redeemed mid-flight `1961ms`, wait abandoned at budget `2011ms`. Before this
change the first and third were the only reachable outcomes and both were constants.

**Cardinality floor 76 → 92**, derived by running the as-written file. A floor guessed from prose is
the same unmeasured claim this change exists to remove.

**Mutation battery: 6/6 RED** (row 1 in two forms), each with a green sandbox baseline first and each
mutation proven landed via `diff -q` against a pristine copy:

| Row | Mutation | Result |
|---|---|---|
| 1a | restore `still held after ${timeout_s}s` | RED — AC2 (both assertions) |
| 1b | `${timeout_s}ms` — new text, new unit, budget substituted for measurement | RED — AC2, caught **only** by the `>= 1000ms` floor |
| 2 | delete the `command -v flock` precheck | RED — AC4 ×2, plus AC5 (LOCK_WAITING fired on a run that never waited) |
| 3 | slow-acquire holder never releases | RED — AC3 ×3 |
| 4 | drop the elapsed from `LOCK_ACQUIRED` | RED — AC1 |
| 5 | rename the `LOCK_ACQUIRED` token | RED — positive control + AC1 + AC5 |

Row 1b is the row that matters: it keeps the new wording *and* the `ms` unit, so every shape-based
assertion passes it. The floor is what makes the arm a measurement check rather than a format check.

**Fixture cost, measured and corrected.** The AC4 mask first shadowed the entire PATH minus `flock`
(~3,600 symlinks): **18.9s of a 32s suite**, on a suite registered in the full gate. Replaced with a
curated shim whose self-check asserts the property the arm actually rests on — under the mask,
`flock` is gone AND `session-state.sh` still sources to a defined `acquire_lock`, which is precisely
the precondition mutation row 2 needs. Suite now **15.3s**; row 2 still RED.

**AC sweep: 10/10 positive HITs** (one grep per AC asserting the thing that had to appear — a
prohibition sweep cannot detect an omission). AC9 is covered by the 92/0 run.
