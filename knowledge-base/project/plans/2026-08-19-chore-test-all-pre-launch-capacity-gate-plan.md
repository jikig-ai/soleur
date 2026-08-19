---
title: "test-all.sh: a session cannot tell before launching whether the box can absorb another full gate"
date: 2026-08-19
slug: chore-test-all-pre-launch-capacity-gate
branch: feat-one-shot-7545-test-all-capacity-gate
issue: 7545
closes: 7545
lane: cross-domain
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-08-19
**Review panel:** dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer, cto (plan-review) + verify-the-negative and
post-edit self-audit passes (deepen-plan Phase 4.45).

### Key improvements

1. **The design was reversed on measured evidence.** v1's hard decline (`exit 4`) was cut after four
   reviewers converged; the decisive datum is ADR-133's own record of a wait **redeemed at 616 s**
   that v1 would have refused at t=0. See §Plan Review Reversal.
2. **The real root cause was found and is now the fix.** `TC_LOCK_TIMEOUT` = 900 s against a ~45-min
   hold time means the lock expires by construction — which is *why* N runs land together. ADR-133
   names raising it as an explicitly unconsidered candidate, so it is licensed where the decline was not.
3. **Two blast-radius consumers v1 missed** were found and are now moot rather than patched:
   `lefthook`'s `pre-commit` hook (a decline would have blocked `git commit`) and `ship`/`one-shot`'s
   rc=4 documentation (which would have sent a ship session to the incident-recreating override).
4. **A P5 hole was closed:** `tc_avail_mb` and its siblings degrade an unreadable probe to `0`, so
   consuming the value alone would report "could not read" as "critically low". The plan now promotes
   a validity flag beside each value.
5. **A `set -e` abort hazard was pinned:** `grep -c` exits 1 on a zero count, and zero siblings is the
   *expected* post-wait state — so the naive re-sample would abort `tc_acquire` on the common path.

### Verification performed

All 12 factual/negative claims in the plan were independently verified against the code
(`confirms` on every one), including the EXIT CONTRACT, the promotable `tc_preamble` locals, the
degrade-to-`0` idiom, `TC_NPROC` fall-through, the lib-stub invariant, `SUITE_GLOBS` exclusion of
repo-root `scripts/*.test.sh`, `guard-vacuity-floor` auto-enrolment, and the ADR-183 `TEST_GROUP=all`
pin. `_tc_scan_procs` was measured at **~6.6 s** per walk, which is why the verdict reuses
`tc_preamble`'s values rather than walking again.

### Halt gates

Phases 4.6 (User-Brand Impact), 4.7 (Observability), 4.8 (PAT-shaped variable), 4.9 (UI wireframe —
no UI surface), 4.10 (Encryption Posture — no store), and 4.11 (Guard Contract, via
`lint-guard-contract.py`) all pass.

## Overview

`scripts/test-all.sh` already measures everything a capacity decision needs, on every run, before
the first suite: distinct sibling worktrees running the runner (`sib_count`), distinct worktrees
running an individual suite (`suite_count`), `MemAvailable`, tmpfs headroom and entry count. Those
measurements print advisory banners and nothing consumes them — so a session still cannot answer
"can the box absorb another full gate?" *before* launching one.

This plan closes that gap in the direction the issue's own title asks for — **a session cannot
tell** — by shipping the telling, and by repairing the wait so the answer is actionable:

1. **A named capacity verdict**, emitted from the values `tc_preamble` already computed, before
   `tc_acquire` takes the lock.
2. **`test-all.sh --capacity`** — a read-only query that prints that verdict, runs no suite, takes
   no lock and exits 0. This is the pre-launch check a session runs *before* deciding to launch.
3. **A wait that actually serializes.** `TC_LOCK_TIMEOUT` is 900 s against a measured ~45-minute
   uncontended full gate — the budget is roughly a third of the hold time, so it expires by
   construction and `LOCK_CONTENDED_PROCEEDING` fires. That is *why* N runs land together. Raising
   it, plus a wait heartbeat naming the holder, is hand-queueing automated.
4. **A diff-justification report**, so a session can see which shards its diff actually touches.

**What this plan deliberately does not do: block a run.** The first draft declined over-capacity
runs with `exit 4`. A six-agent review falsified that design against measured evidence — see
§Plan Review Reversal. The decline is deferred behind #7454 item 3's evidence bar, which the
verdict line above is precisely the instrument to produce.

> Note: no `knowledge-base/project/specs/feat-one-shot-7545-test-all-capacity-gate/spec.md` exists,
> so `lane:` could not be carried forward and defaulted to `cross-domain` (TR2 fail-closed). The
> domain sweep below independently concluded Engineering is the only relevant domain.

## Plan Review Reversal — why v1's decline was cut

v1 proposed declining an over-capacity run with `exit 4` at a pre-launch chokepoint. Four reviewers
(dhh, cto, spec-flow-analyzer, architecture-strategist) converged independently on the same verdict,
with the simplification and correctness panels firing on the same scope — which per plan-review's
consolidation rule means *delete*, not *fix*. Five findings, each verified against code or the ADR
corpus before this rewrite:

| # | Finding | Verified |
|---|---|---|
| R1 | **The Pareto claim was false, and ADR-133 contains the datum that falsifies it.** Its 2026-08-12 addendum records a run that queued behind **two** sibling worktrees and was `LOCK_ACQUIRED … after 616310ms` — **"redeemed at 616 s"**. v1's `TC_MAX_SIBLING_RUNS=1` declines that exact run at t=0, converting a *completed* gate into *no coverage*. v1 reasoned only about the missed-decline direction. | ADR-133 line 303 |
| R2 | **A decline blocks `git commit`.** `lefthook.yml` `pre-commit` → `bun-test` runs `bash scripts/test-all.sh` on any staged `*.{ts,tsx,js,jsx}`. Non-zero blocks the commit, so no `.ts` change could be committed while any sibling worktree ran the runner — against a workflow whose own rule is "commit each verified unit IMMEDIATELY". | `lefthook.yml:234,237` |
| R3 | **rc=4 is documented as subagent-only in two consumers v1 never touched**, and the documented remedy is the exact wrong one. `ship/SKILL.md` states rc=4 means `SOLEUR_SUBAGENT=1` was set, and notes ship reached from a drain fan-out *inherits that variable* — so a ship session hitting a capacity decline would set `SOLEUR_ALLOW_FULL_GATE=1` and re-create the incident. v1 discharged the *exit-code* union by reusing 4 but never swept the *semantic* union (`hr-type-widening-cross-consumer-grep`). | `ship/SKILL.md:345`, `one-shot/SKILL.md:67` |
| R4 | **A decline has no completion path.** Its only exit was a printed `SOLEUR_ALLOW_FULL_GATE=1`, which returns to the incident condition and simultaneously disarms the subagent refusal (the same variable). v1's Risks table used that override as the mitigation for three of six risks — an override load-bearing for a design's safety becomes the default. | `scripts/test-all.sh` refusal block |
| R5 | **The real root cause was unexamined: `TC_LOCK_TIMEOUT=900` is shorter than the thing it waits for.** Measured siblings ran 3,775 / 5,787 / 5,763 s against a ~45-minute uncontended baseline. A 900 s budget cannot serialize two full gates, so it always expires. ADR-133's addendum names raising it as **"a candidate the original Alternatives never considered"** — licensed, unlike the decline. | ADR-133 lines 208-216 |

Also cut on review: `tc_capacity_verdict()` as a second `/proc` walk (it would have produced a
second, unreconciled source of truth — a run could print `CAPACITY_OK` and then
`SIBLING_RUN_DETECTED: 2`); the `MemAvailable` decline arm (unreachable in its own design — memory
only falls that far when siblings are running, which the sibling arm already caught, and declining a
test run does not free memory); and `ADR-194` as a new decision record.

## Research Insights

### Premise Validation (Phase 0.6)

| Reference | Probe | State | Verdict |
|---|---|---|---|
| #7545 (this issue) | `gh issue view` | OPEN, `closedByPullRequestsReferences: []` | Live; not resolved by any merged PR |
| #7538 | `gh pr view` | MERGED | Closes 7402/7429/7523, **not** 7545. Not a duplicate |
| #7537 (sibling) | `gh issue view` | OPEN — orphan reaper | Ships as its own PR |
| #7498 (sibling) | `gh issue view` | OPEN — vitest split | Ships as its own PR |
| #7429 / #7402 / #7523 | `gh issue view` | CLOSED | Correctly filed under "already done" |
| #7352 / ADR-183 | `gh issue view` | CLOSED, ADR present | Full battery already at `/ship` Phase 4 |
| #7454 item 3 | `gh issue view` | **OPEN** | Sets the evidence bar for a lock *mechanism* change — binding |
| `scripts/test-all.sh` | `ls` | 109 355 bytes | Exists |
| `scripts/lib/test-contention.sh` | `ls` | 31 993 bytes | Exists |
| `scripts/lib/test-relevance-paths.sh` | `ls` | 18 247 bytes | Exists |

**Mechanism-vs-ADR-corpus check (Phase 0.6 item 4).** Grepping the corpus for the *mechanism*
returned ADR-133. Its `## Alternatives Considered` rejects **"Make the lock blocking (abort on
timeout)"**; its 2026-08-11 addendum rejects replacing the mutex with admission control (TOCTOU;
non-monotonic degradation) and names **"a headroom bypass on top of the mutex, not a replacement"**
as the follow-up. Critically, the same addendum records that **raising `TC_LOCK_TIMEOUT` is a
candidate the original Alternatives never considered** — so the timeout raise this plan ships is
explicitly unconsidered-and-open, not rejected. ADR-133 Decision 3's load-bearing property
("proceeds on timeout, NEVER aborts") is preserved verbatim by every change here.

### Property List (Phase 0.6b)

| # | Property (observable outcome) |
|---|---|
| P1 | Before launching, a session can obtain a named verdict on whether the box can absorb a full gate — without running a suite or taking the lock. |
| P2 | `LOCK_CONTENDED_PROCEEDING` stops being the routine mechanism by which N full runs land together. |
| P3 | A session can tell which shards its own diff warrants. |
| P4 | Every new check can be mutated out individually and the suite reddens. |
| P5 | No uncertainty (unreadable `/proc`, missing `nproc`, unparseable reading) is ever reported as a healthy box. |
| P6 | No change reduces the coverage any run obtains today, and no consumer's exit-code contract changes. |

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Verdict |
|---|---|---|
| **Hard decline on over-capacity (`exit 4`)** | P1 | **CUT — see §Plan Review Reversal.** Falsified by ADR-133's 616 s redeemed-wait datum (R1), breaks `git commit` (R2), misreads at ship (R3), no completion path (R4). Deferred behind #7454 item 3. |
| Abort / block at `TC_LOCK_TIMEOUT` | P2 | **CUT.** Verbatim ADR-133's rejected alternative. |
| A new exit code (5), or reuse of 4, for a capacity verdict | P1 | **CUT with the decline.** With no blocking verdict there is no new exit semantics at all — the strongest form of the union-widening argument, and it keeps `lefthook`, `ci.yml` ×3, `main-health-monitor.yml`, `grok-pre-push-gate.sh` and `package.json` untouched. |
| `tc_capacity_verdict()` as a new decision function doing its own `/proc` walk | P1 | **CUT.** `tc_preamble` already computes `sib_count`, `avail_mb`, `memavail_mb`; a second walk is a second non-atomic snapshot, which `_tc_scan_procs`'s own header forbids. Promote the three locals instead. |
| `TC_MIN_MEMAVAIL_MB` + a `MemAvailable` decline arm | P1 | **CUT.** Unreachable by its own design: at-rest `MemAvailable` is 6391 MB and the floor was 2048, so it can only fire when siblings are already running (caught by the sibling signal) or when something unrelated ate the box — where declining a test run fixes nothing. Retained as the banner `tc_preamble` already prints. |
| `TC_MAX_SIBLING_RUNS` | P1 | **CUT with the decline.** Also carried a naming defect: `=1` with "decline at `>= 1`" means *zero* siblings permitted. |
| Overloading `SOLEUR_ALLOW_FULL_GATE=1` as the capacity override | P1 | **CUT with the decline.** It already means "I am the sanctioned lead"; overloading made the capacity escape disarm the subagent refusal and made the gate unreachable on the lead path. |
| A 5th `*_PATHS` relevance array for whole-run diff justification | P3 | **SCOPED DOWN.** Six-site change; measured ceiling **4** gated suites of **167** top-level `run_suite` registrations (~2.4%), of which 3 declined in the run cited in the brief. Ships as a report. See DC-1. |
| A new lock / serialization primitive | P2 | **CUT.** `tc_acquire` + `session-state.sh acquire_lock` already serialize; the issue says so explicitly. |
| Gating on raw `loadavg` | P1 | **CUT — measured.** Issue records `3.99 / 7.04 / 9.35` idle on 16 cores; independently re-measured for this plan on the same box at `7.37 / 5.50 / 3.28`. The 15-minute idle baseline moved 9.35 → 3.28 between two idle readings. |

### Value-Proposition Measurement (Phase 0.6c)

- **The wait budget is undersized by ~3×.** `TC_LOCK_TIMEOUT` = **900 s**; the measured uncontended
  full gate is **~45 min (~2700 s)**, and siblings were observed holding for **3,775 / 5,787 /
  5,763 s**. A budget below the hold time guarantees expiry, which is the mechanism behind
  `LOCK_CONTENDED_PROCEEDING`. Raising it is a one-constant change that preserves ADR-133 Decision 3.
- **Waits do get redeemed.** ADR-133's 2026-08-12 addendum: `LOCK_ACQUIRED … after 616310ms` behind
  two siblings — the longest redeemed wait on record. Any design that refuses at t=0 forfeits it.
- **Contention's measured cost to a run that proceeds:** the registry mutation battery took
  **860 692 ms** with one sibling suite vs **1 675 430 ms** with three concurrent sessions — **1.9×**
  — both `rc=0` on this 16-core host (`_suite_budget_ms` in `scripts/test-all.sh`).
- **Reported frequency:** three hand-queued gates in one day (2026-08-13), plus the issue's
  reproduction where a session that knew the failure class still launched two shards onto a box
  already running two.

Live baseline measured for this plan (2026-08-19, this box): `nproc` → 16; `/proc/loadavg` →
`7.37 5.50 3.28`; `MemAvailable` **6391 MB** of MemTotal **31187 MB**; `df -P -k /tmp` → 4 GiB
tmpfs, **3699 MB** avail, **10%** used.

### Relevant file paths

Cited by content anchor rather than line number where the file is long and churning.

- `scripts/test-all.sh` — the `--print-suite-globs` early-exit (the `--capacity` precedent; its
  comment states the required discipline: "BEFORE anything with a side effect … no `tc_acquire` —
  a code path that blocks on it would deadlock the gate on itself")
- `scripts/test-all.sh` — the `EXIT CONTRACT` block (unchanged by this plan)
- `scripts/test-all.sh` — the lib-stub block guarded on `declare -F tc_acquire` ("the LAST-defined
  function in the lib")
- `scripts/test-all.sh` — the `tc_preamble` → `tc_acquire "test-all"` window
- `scripts/test-all.sh` — `_diff_touches()` and `_diff_names`, both defined *before* `tc_preamble`
- `scripts/lib/test-contention.sh` — `tc_preamble()`'s `sib_count` / `avail_mb` / `memavail_mb` locals
- `scripts/lib/test-contention.sh` — `TC_LOCK_TIMEOUT`, `TC_MIN_AVAIL_MB` and the other `TC_*` seams
- `scripts/lib/test-contention.sh` — `tc_acquire()`'s `LOCK_WAITING` / `LOCK_CONTENDED_PROCEEDING` arms
- `scripts/test-contention.test.sh` — `make_fake_proc` + `tc_env`: the fake-`/proc` harness
- `scripts/test-all-infra-coverage-notice.test.sh` — sandbox + Python `run_suite` recorder pattern
- `plugins/soleur/scripts/grok-pre-push-gate.sh` — `run_step` and the ten-step order
- `lefthook.yml` — `pre-commit` → `bun-test` → `bash scripts/test-all.sh`

### Institutional learnings that bind this plan

| Learning | Why it binds |
|---|---|
| `2026-08-13-i-wrote-two-guards-against-vacuity-and-both-guards-were-vacuous.md` | An anti-vacuity floor routed through `fail()` cannot witness a broken `fail()`. The new suite's floor must `exit 1` **directly**. |
| `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md` | Threshold comparisons need below / at / far-above rows. v1 shipped a `>= 1` threshold with no at-threshold fixture, making its own `>=`→`>` mutation row vacuous. |
| `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` | The deliverable *is* a guard; scenarios must be "mutation M → guard G reddens". |
| `2026-08-09-my-suites-were-hermetic-so-they-certified-a-gate-reached-through-a-dead-read.md` | A faked-`/proc` suite certifies logic, never that the live read works. Needs a `-live` calibration arm. |
| `2026-08-10-six-times-a-check-certified-something-other-than-what-it-named.md` | "Low tmpfs" must measure the filesystem the suites write to (`TC_TMPDIR`), not the root partition. |
| `2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md` | Fixtures must instantiate more than one sibling. |
| `2026-05-12-cross-session-lock-lease-bash-primitives.md` | Sibling sessions coordinate through `session-state.sh`; do not invent a second primitive. |

### CLAUDE.md / AGENTS.md conventions in force

`cq-write-failing-tests-before`; `hr-type-widening-cross-consumer-grep` and
`cq-union-widening-grep-three-patterns` (**the finding that reshaped this plan** — v1 swept the
exit-code union and missed the semantic one; v2 discharges both by changing no exit code);
`hr-verify-repo-capability-claim-before-assert`; `cq-assert-anchor-not-bare-token`;
`cq-cite-content-anchor-not-line-number`; `cq-ac-must-not-depend-on-concurrent-sessions`.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured) | Plan response |
|---|---|---|
| Issue: "The lever is ~70% built already" | Confirmed. `tc_preamble` computes every input; each banner is a `printf`. | Build only the decision/report layer; reuse the existing measurement. |
| Issue: "a pre-launch decision" | Confirmed feasible, but the *shape* matters — see the four review findings. The `--print-suite-globs` early-exit is an exact precedent for a side-effect-free pre-launch query. | Ship `--capacity` (query) + a verdict line, not a block. |
| Issue bullet 2: "a decision about the `LOCK_CONTENDED_PROCEEDING` path" | ADR-133 rejected abort-on-timeout, but explicitly names **raising `TC_LOCK_TIMEOUT`** as never-considered. | D2: raise the budget above the measured hold time + heartbeat. Semantics (proceeds, never aborts) unchanged. |
| Brief: "relevance-gating declined 3 of 325 suites" | Bounded tighter: **167** top-level registrations, **4** gated arrays. Ceiling ~2.4%. | D3: report, not a 5th array. DC-1. |
| Learnings research recommended "fail-closed design" | **Contradicts issue constraint 3**, which is binding. | Constraint wins: uncertainty ⇒ `CAPACITY_UNKNOWN`, never a false healthy reading. Recorded and overruled. |
| Repo research reported: "exit 4 … no existing consumer branches on it" | **False.** `grok-pre-push-gate.sh` routes rc=4 into `[FAIL]`; `ship/SKILL.md` and `one-shot/SKILL.md` document it as subagent-only. | Moot in v2 — no exit code changes. Recorded because it is what falsified v1's Cut List entry. |
| v1 claim: "a declined run cannot render as green anywhere" | True but incomplete — it can render as a *blocked commit* (`lefthook`) and as a *misdiagnosed subagent refusal* (`ship`). | Decline cut. |
| ADR-133 §Consequences: "No product runtime surface, user data, or tenant boundary is touched" | Holds. | `brand_survival_threshold: none`; GDPR/IaC/Encryption gates skip. |

## Open Code-Review Overlap

**None.** Queried 64 open `code-review` issues; zero mention `scripts/test-all.sh`,
`scripts/lib/test-contention.sh`, `scripts/lib/test-relevance-paths.sh`,
`scripts/test-contention.test.sh` or `scripts/test-all-infra-coverage-notice.test.sh`.

Adjacent-but-separate: PR #7616 (`feat-one-shot-7580-7553-vacuity-floor-subagent-gate`) touches
guard-vacuity floors. Disposition: **acknowledge** — different scope, no file overlap at plan time.
`/work` Phase 0 re-checks after the ship-time rebase.

## Design Decisions

### D1 — One capacity verdict, from one measurement

`tc_preamble` gains three script-scope assignments alongside its existing `printf`s —
`TC_LAST_SIB_COUNT`, `TC_LAST_AVAIL_MB`, `TC_LAST_MEMAVAIL_MB` — and emits **zero additional
output bytes**, so the `[contention] BANNER` contract `work/SKILL.md` greps is untouched.

A single named verdict line is then emitted between `tc_preamble` and `tc_acquire`:

| Verdict | Condition |
|---|---|
| `CAPACITY_OK measured_siblings=N tmp_avail_mb=N memavail_mb=N` | every reading healthy |
| `CAPACITY_CONTENDED reason=<sibling_runs\|low_tmp> measured=N threshold=N` | a reading is over the line |
| `CAPACITY_UNKNOWN reason=<unreadable_proc\|no_nproc\|unparseable_df\|unparseable_meminfo>` | any reading degraded |

Every line carries **the measured value and the threshold**, so a reader can judge rather than obey.
`CAPACITY_CONTENDED` is a *statement*, not a refusal: the run proceeds, and the existing three-way
confirmation doctrine in `work/SKILL.md` §9 tells a reader what a RED under it is worth. Because no
verdict changes the exit code, P6 holds by construction.

`CAPACITY_UNKNOWN` is a **distinct token from `CAPACITY_OK`** — a degraded read can never present as
a healthy box (P5, issue constraint 3). Uncertainty is evaluated **per signal**: one unreadable
reading does not suppress a `CONTENDED` verdict derived from a different, healthy one, and the
`reason=` field names which reading degraded.

**P5 needs a validity flag, because the existing probes degrade to `0`, not to "unknown".** Verified:
`tc_avail_mb()` ends `[[ "$kb" =~ ^[0-9]+$ ]] || { printf '0\n'; return 0; }`, and `tc_used_pct()` /
`tc_used_bytes()` share that convention. So an unparseable or failed `df` yields **0 MB**, which is
below every floor and would read as `CAPACITY_CONTENDED reason=low_tmp` — a *degraded* reading
presenting as a *measured* one, which is exactly the collapse P5 forbids. Simply consuming
`tc_preamble`'s numbers therefore cannot satisfy P5.

`tc_preamble` accordingly promotes a **validity flag beside each value** —
`TC_LAST_AVAIL_MB_OK` / `TC_LAST_MEMAVAIL_MB_OK` / `TC_LAST_SIB_COUNT_OK`, each `0|1` — set from the
same shape assertions the function already performs, and still emitting zero additional output bytes.
The verdict reads value-and-flag, never the value alone. This keeps one measurement and one source
of truth while making "could not read" distinguishable from "read a low number".

**Verdict precedence is defined and ordered** (v1 left it undefined, which made its own mutation
rows unsound): `UNKNOWN` reasons and `CONTENDED` reasons are both accumulated, and the line reports
`CONTENDED` when any threshold is crossed, listing every reason; `UNKNOWN` only when no threshold is
crossed and at least one reading is degraded; `OK` only when every reading is healthy and present.

### D2 — Make the wait serialize (`LOCK_CONTENDED_PROCEEDING`)

**`tc_acquire`'s timeout semantics do not change**: it proceeds, never aborts (ADR-133 Decision 3).
Three changes around it, all licensed:

1. **Raise `TC_LOCK_TIMEOUT`'s default above the measured hold time.** At 900 s against a ~45-minute
   gate the budget expires by construction — the lock cannot serialize what it is waiting for.
   Phase 0 measures the current full-gate wall clock and derives the default from it (plan-time
   proposal: **3600**). Still env-tunable; still advisory; still proceeds on expiry.
2. **A wait heartbeat.** While blocked, emit the holder's worktree, pid and elapsed seconds every
   `TC_WAIT_HEARTBEAT_S` (default 60). A silent multi-minute block is indistinguishable from a hang
   — which is what produces hand-kills and hand-queueing. The heartbeat is also what keeps a long
   wait legible to a stall detector, and `work/SKILL.md` already instructs agents to grep
   `LOCK_WAITING` before killing.
3. **Re-sample the sibling count in the `LOCK_CONTENDED_PROCEEDING` banner**, which after a long wait
   is otherwise reporting a reading up to a full budget stale. Pure observability.

**The re-sample carries a verified abort hazard that must be written into the code, not just the
prose.** `tc_preamble` counts with `sib_count=$(cut -f2 <<<"$sibs" | sort -u | grep -c . || true)`,
and the `|| true` is load-bearing: **`grep -c` exits 1 when the count is zero** (measured: rc 1 on
empty input). Copying that idiom into `tc_acquire` without the `|| true` makes the assignment return
1, which under `set -e` aborts `tc_acquire` mid-function; because `tc_acquire "test-all"` is a bare
top-level command in the runner, the whole run dies with no summary, no rc file and no `[FAIL]`
line. And **zero siblings is the *expected* post-wait state** — the holder usually exited, which is
why the lock was released — so the naive implementation breaks ADR-133 Decision 3's never-abort
property on the single most common path. M18 pins it; AC11's contended arm asserts the **zero-sibling**
case specifically, not merely "returns 0 on some arm".

Each re-sample is a second `_tc_scan_procs` walk, measured at **~6.6 s** on this box. That is
acceptable against a budget measured in tens of minutes, and it happens only on the contended path —
but it is why the *pre-launch* verdict reuses `tc_preamble`'s values rather than walking again.

Together these buy P2 by making the *wait* the thing that serializes, rather than making the *run*
the thing that is refused.

### D3 — Diff justification ships as a report

An advisory line names which `TEST_GROUP` shards the current diff touches, reusing `_diff_touches`
and `_diff_names` (both defined before `tc_preamble`, so the data is in hand). It buys P3 without a
fifth `*_PATHS` array — a six-site change against a ~2.4% ceiling, whose own guard comment records a
live defect from exactly that edit.

**Scoped so it cannot contradict ADR-183.** ADR-183 pins `/ship` Phase 4 at `TEST_GROUP=all` as the
load-bearing constraint of that change, asserted by `plugins/soleur/test/fullsuite-merge-gate.test.ts`.
The report therefore states which shards are touched and explicitly **does not recommend narrowing**
when `TEST_GROUP=all` was requested.

### D4 — `test-all.sh --capacity`

A read-only query mode modeled byte-for-byte on the `--print-suite-globs` precedent: it answers and
exits **before anything with a side effect** — no `TMPDIR` export, no bare-repo guard, no
`TEST_GROUP` validation, and critically **no `tc_acquire`** (that file's own comment notes a path
which blocks on the lock would deadlock the gate on itself). It prints the D1 verdict plus the
per-sibling pid / worktree / elapsed detail, and exits **0**.

This is the deliverable that most directly answers the issue title: a session runs it *before*
launching, in under a second, and gets a named answer. It is also what `grok-pre-push-gate.sh` calls
as step 0, so a contended box is reported at second 0 rather than after ~11 completed steps.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — local developer tooling, the same
scope ADR-133 §Consequences records. The indirect path is coverage: a change that caused a gate not
to run could let an untested regression reach the web platform. v2 closes that by construction —
**no verdict changes any exit code and no verdict prevents any suite from running**, so the set of
runs that complete today is a subset of those that complete after this change. The one behavioural
change to an existing run is a *longer* wait before proceeding, which preserves coverage rather than
reducing it. (This is precisely the property v1 lacked: its decline blocked `git commit` via
`lefthook` and could decline ADR-183's single remaining full battery at `/ship` Phase 4.)

**If this leaks, the user's data/workflow/money is exposed via:** no exposure vector. The change
reads `/proc/meminfo`, `/proc/<pid>/stat`, `/proc/<pid>/cwd` and `df` on the local machine,
transmits nothing, persists nothing. No user data, no tenant boundary, no network call, no credential.

**Brand-survival threshold:** `none`

- `threshold: none, reason:` the diff touches only repo-root `scripts/`, `plugins/soleur/scripts/`
  and `plugins/soleur/skills/*/SKILL.md` prose — no schema, migration, auth flow, API route or
  `.sql` file, and no product runtime surface.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-133 with a dated addendum** — not a new ADR. v1 proposed ADR-194 on the grounds that it
was "the first enforcement point"; with the enforcement cut, what remains is exactly the instrument
ADR-133 Decision 1 mandates ("instrumentation ships ahead of every fix") plus a tuning of Decision
3's own parameter. The addendum records:

- the capacity verdict and `--capacity` query, as the instrument that answers the pre-launch question;
- the `TC_LOCK_TIMEOUT` raise, with the measurement that motivates it (900 s budget vs ~2700 s hold),
  stating explicitly that Decision 3's advisory/never-abort property is **unchanged**;
- the heartbeat and the contended-banner re-sample;
- **why the decline was cut**, with the 616 s redeemed-wait datum, so the next session inherits the
  evidence rather than the argument — and a pointer to #7454 item 3 as the bar a future decline must
  meet.

Append-only, per ADR-181 §8's stated convention ("appended rather than edited above … citation-by-date
is what `principles-register.md` relies on"). **No new ordinal is claimed**, which removes v1's
ordinal-collision risk, its all-`origin/*` probe, and its renumber-sweep obligation entirely.

**ADR-181 and ADR-183 need no change.** v1 required both because it altered rc=4's meaning and added
a third way ADR-183's single full battery could fail to happen. v2 does neither.

### C4 views

**No C4 impact.** Enumerated against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External human actors:** none added; the change introduces no correspondent, reviewer or recipient.
- **External systems / vendors:** none — no network call; `/proc` and `df` on the local machine only.
- **Containers / data stores:** none; nothing persisted, the existing `TC_TMPDIR` tmpfs is read only.
- **Actor↔surface access relationships:** none change.

Checked that no existing element is *falsified*: a grep for
`test-all|test runner|local gate|test suite|contention|worktree` across all three files returns only
(a) `platform.plugin`'s description of shipped bash primitives and (b) product-side *per-user
worktrees* on Hetzner hosts plus the `coordinator`/`gitDataStore` lease edges — a different concept
from a developer's local git worktree, untouched here. No `.c4` edit is in scope, so
`c4-code-syntax.test.ts` / `c4-render.test.ts` are unaffected.

### Sequencing

Nothing is soak-gated. The ADR-133 addendum lands in the same PR as the code it describes.

## Observability

```yaml
liveness_signal:
  what: "one named capacity verdict per run — CAPACITY_OK / CAPACITY_CONTENDED / CAPACITY_UNKNOWN,
         each carrying measured values and thresholds — plus the same line on demand via
         `bash scripts/test-all.sh --capacity`"
  cadence: "once per test-all.sh invocation, before tc_acquire; on demand in query mode"
  alert_target: "the invoking terminal and the run log; local developer tooling has no remote alert
                 target and must not acquire one"
  configured_in: "scripts/lib/test-contention.sh (tc_preamble's promoted values, tc_acquire's
                  heartbeat) and scripts/test-all.sh (the verdict emitter and --capacity mode)"
error_reporting:
  destination: "stderr, alongside the existing [contention] channel"
  fail_loud: "the verdict is emitted on every run and cannot be absent; a missing verdict line is
              itself asserted against by the suite"
failure_modes:
  - mode: "a degraded reading is reported as a healthy box"
    detection: "CAPACITY_UNKNOWN is a DISTINCT token from CAPACITY_OK, carrying reason=<which
                reading degraded>; uncertainty is evaluated per signal"
    alert_route: "invoking terminal; pinned by the suite's uncertainty arms"
  - mode: "the verdict and tc_preamble's banners disagree about the same machine"
    detection: "both derive from ONE _tc_scan_procs walk via tc_preamble's promoted values, so
                disagreement is structurally impossible rather than merely unlikely"
    alert_route: "pinned by an arm asserting verdict and banner agree on sibling count"
  - mode: "a wedged or orphaned sibling holds the lock, so every run waits the full budget"
    detection: "the wait heartbeat names the holder's worktree, pid and elapsed seconds every
                TC_WAIT_HEARTBEAT_S, so a multi-hour holder is visible while waiting rather than
                only afterwards"
    alert_route: "invoking terminal. Reaping is #7537, not this PR; the raised budget makes the
                  visibility more important, which is why the heartbeat ships with it"
  - mode: "the contention lib is missing or truncated, so the verdict silently vanishes"
    detection: "the lib-stub block gains a tc_capacity_line stub emitting CAPACITY_UNKNOWN
                reason=lib_unavailable, and the stub guard's 'LAST-defined function' invariant is
                preserved by defining new functions BEFORE tc_acquire in the lib"
    alert_route: "invoking terminal; pinned by a mutation row that removes the lib"
logs:
  where: "stderr of the run, captured into the caller's log file; TEST_TIMING_LOG is untouched"
  retention: "per-run only; nothing new is persisted"
discoverability_test:
  command: "bash scripts/test-all-capacity-signal.test.sh"
  expected_output: "a terminal PASS line reporting a non-zero arm count, with no [FAIL] lines"
```

## Implementation Phases

### Phase 0 — Preconditions (no code)

0.1 `git status --porcelain` empty before any gate run.
0.2 Confirm the injection seams by content anchor: `TC_PROC_ROOT`, `TC_NPROC`, `TC_DF_CMD`,
`TC_MIN_AVAIL_MB`, `TC_LOCK_TIMEOUT` in `scripts/lib/test-contention.sh`.
0.3 **Measure the current uncontended full-gate wall clock** and derive `TC_LOCK_TIMEOUT`'s new
default from it (budget must exceed the hold time; plan-time proposal 3600). Record the measurement
in the ADR addendum. If a full run is not affordable in-session, use the ADR-133 recorded ~45-minute
baseline and say which source was used.
0.4 Re-measure at-rest tmpfs headroom **immediately after a full run completes**, not only at rest:
ADR-133 records `/tmp` dipping to 699 MB during a run against the 1024 MB floor, so `low_tmp` will
legitimately fire in the tail of a healthy run. Confirm the verdict's wording reflects that this is
a statement, not a fault.

### Phase 1 — RED: the verdict

1.1 Create `scripts/test-all-capacity-signal.test.sh` on the `test-contention.test.sh` harness
(`make_fake_proc` + `tc_env`), extended with fake `df` (`TC_DF_CMD`) and fake `meminfo`. **Write the
mutation matrix rows before the code exists.**
1.2 Arms per threshold at below / at / far-above — **including the at-threshold sibling row v1
omitted**, without which the `>=`→`>` mutation is vacuous.
1.3 Arms asserting two distinct sibling worktrees count as 2 and two PIDs in one worktree count as 1.
1.4 Arms asserting every degraded input yields `CAPACITY_UNKNOWN` with the right `reason=`, and never
`CAPACITY_OK`; plus a mixed arm (one reading degraded, another over threshold) pinning per-signal
precedence.
1.5 **Satisfy ADR-193 in full, because the new suite auto-enrols into the vacuity floor.**
`scripts/guard-vacuity-floor.test.sh` declares `COVERED_DIRS='^(scripts/|plugins/soleur/test/)'` and
is registered in the runner, and ADR-193 Decision 5 makes that population *derived* — so
`scripts/test-all-capacity-signal.test.sh` is enrolled the moment it lands, and a suite satisfying
only Decision 1 reds the floor. All four:
  - **D1** — the floor `exit 1`s directly, never through the suite's own `fail()`.
  - **D2** — the case counter is incremented at the **call site**, never inside a verdict helper and
    never inside `$( … )` (a subshell increment is lost).
  - **D3** — an accounting-conservation check asserting `passes + fails == cases`, reported directly.
  - **D4** — the conservation check runs **before** the floor.
1.6 A must-PASS non-canonical fixture.
1.7 Confirm RED.

### Phase 2 — GREEN: promote the measurements, emit the verdict

2.1 In `tc_preamble`, assign `TC_LAST_SIB_COUNT` / `TC_LAST_AVAIL_MB` / `TC_LAST_MEMAVAIL_MB` **and
their validity flags `TC_LAST_SIB_COUNT_OK` / `TC_LAST_AVAIL_MB_OK` / `TC_LAST_MEMAVAIL_MB_OK`** at
script scope alongside the existing `printf`s, each flag set from the shape assertion the function
already performs. The flags are required by D1, AC5(b) and M11b — without them an unparseable `df`
degrades to `0` and reads as `CONTENDED`, not `UNKNOWN`. **Zero output bytes change.**
2.1b Update the lib's **`TEST SEAMS` header block**, which enumerates the overridable seams: add
`TC_WAIT_HEARTBEAT_S` (new in Phase 4) and `TC_DF_CMD` (a pre-existing omission — the seam exists and
the suite uses it, but the block never listed it).
2.2 Add `tc_capacity_line()` to `scripts/lib/test-contention.sh`, **defined before `tc_acquire`** so
the lib-stub block's "LAST-defined function" invariant still holds, and add a matching stub to that
block emitting `CAPACITY_UNKNOWN reason=lib_unavailable`.
2.3 Emit the verdict from `scripts/test-all.sh` between `tc_preamble` and `tc_acquire`.
2.4 Confirm GREEN, and confirm `tc_preamble`'s stderr is byte-identical to `origin/main`'s for a
fixed fake `/proc`.

### Phase 3 — RED→GREEN: `--capacity` query mode

3.1 RED arms: `--capacity` prints the verdict and the sibling detail, exits **0**, records **zero**
suite invocations, and takes **no lock** (asserted by the absence of any `LOCK_` line).
3.2 Implement beside `--print-suite-globs`, before every side effect.
3.3 Confirm GREEN.

### Phase 4 — RED→GREEN: the wait

4.1 RED arms: the heartbeat emits holder worktree/pid/elapsed at the configured interval;
`LOCK_CONTENDED_PROCEEDING` names a **re-sampled** sibling count; `tc_acquire` returns **0** on every
arm including both new ones.
4.2 Raise the `TC_LOCK_TIMEOUT` default per Phase 0.3; implement heartbeat and re-sample. Every read
uses `${VAR:-}` and asserts numeric shape before arithmetic — a bare expansion here is an
unbound-variable abort in the one function whose contract is that it cannot abort.
4.3 Confirm GREEN.

### Phase 5 — RED→GREEN: the diff-justification report

5.1 RED arms: the report names touched shards; degrades to a named "diff undeterminable" line; and
**does not recommend narrowing when `TEST_GROUP=all`** (ADR-183 Ceiling 1).
5.2 Implement as an advisory line. No new `*_PATHS` array.
5.3 Confirm GREEN.

### Phase 6 — Registration, consumers and docs

6.1 Register `scripts/test-all-capacity-signal.test.sh` with an explicit `run_suite` line under
`want_scripts` — `SUITE_GLOBS` covers `scripts/lib/*.test.sh` but **not** repo-root `scripts/*.test.sh`
(verified), so nothing auto-discovers it.
6.2 `bash scripts/lint-orphan-test-suites.sh` reports no orphan.
6.3 `plugins/soleur/scripts/grok-pre-push-gate.sh`: call `test-all.sh --capacity` as step 0 and print
its verdict. It is advisory — it must **not** gate the push (exit code unchanged).
6.4 `plugins/soleur/skills/work/SKILL.md`: document the verdict line and `--capacity` in §9's
contention passage. No rc-contract change.
6.5 `plugins/soleur/skills/ship/SKILL.md`: note `--capacity` as the pre-launch probe before Phase 4's
`TEST_GROUP=all` run. No rc-contract change.
6.6 Write the ADR-133 addendum.

### Phase 7 — Exit gate

7.1 Clean tree, then `TEST_GROUP=scripts bash scripts/test-all.sh` (the shard this diff touches).
7.2 Read the preamble and epilogue, not just `rc`; state which shards ran.

## Acceptance Criteria

### Pre-merge (PR)

- **AC1** `bash scripts/test-all-capacity-signal.test.sh` exits 0 and reports a non-zero arm count.
- **AC2** Fake `/proc` with **two** distinct sibling worktrees ⇒ verdict names `siblings=2`; two PIDs
  in **one** worktree ⇒ `siblings=1`.
- **AC3** Sibling count at **0 / 1 / 5** ⇒ `CAPACITY_OK` / `CAPACITY_CONTENDED reason=sibling_runs` /
  `CAPACITY_CONTENDED` (the at-threshold row v1 lacked; without it the `>=`→`>` mutation is vacuous).
- **AC4** tmpfs avail at **1023 / 1024 / 3000 MB** ⇒ `CONTENDED reason=low_tmp` / not / not.
- **AC5** Each degraded input ⇒ `CAPACITY_UNKNOWN` with the matching `reason=`, and **never**
  `CAPACITY_OK` *and never a `CONTENDED` verdict derived from the degraded signal itself*. The
  witness set is exactly: (a) `/proc/meminfo` unreadable, (b) `TC_DF_CMD` pointing at a stub emitting
  non-numeric output, (c) `TC_PROC_ROOT` pointing at a directory with no readable process entries.
  **Two witnesses from an earlier draft were dropped as incoherent, verified:** `TC_NPROC=""` does
  not simulate a missing `nproc` (the read is `${TC_NPROC:-$(nproc …)}`, so an empty value falls
  through to the real binary) and core count is not an input to any check here; and a missing
  `/proc/<pid>/cwd` is substituted with an `<unreadable>` sentinel by `_tc_scan_procs` and the row is
  still emitted, so it yields a *count*, not an unknown.
- **AC6** Mixed input (one reading degraded, another over threshold) ⇒ `CAPACITY_CONTENDED`, with the
  degraded reading named — pinning per-signal precedence.
- **AC7** Every verdict line carries both the measured value and the threshold.
- **AC8** `bash scripts/test-all.sh --capacity` exits **0**, records **zero** suite invocations, and
  emits no `LOCK_` line (it takes no lock).
- **AC9** `tc_preamble`'s stderr is **byte-identical** to `origin/main`'s for a fixed fake `/proc`.
  The baseline is materialized by the repo's existing idiom — `git -C "$REPO_ROOT" show
  origin/main:scripts/lib/test-contention.sh > "$MAIN_LIB"`, as
  `scripts/test-all-killed-classification.test.sh` already does for the runner — then both are driven
  against the same fixture and the outputs diffed. Without a named mechanism this AC is unfalsifiable.
- **AC10** The verdict's sibling count equals `tc_preamble`'s banner sibling count in the same run
  (one walk, one source of truth).
- **AC11** `tc_acquire` returns **0** on every arm, including the heartbeat and re-sample arms — and
  specifically on the **zero-siblings-after-the-wait** arm, which is the expected post-wait state and
  the one the `grep -c` hazard aborts on.
- **AC11b** The new suite satisfies ADR-193 Decisions 1-4: floor `exit 1`s directly, case counter
  incremented at the call site (never in a subshell), `passes + fails == cases` conservation check
  present, and conservation evaluated before the floor. `bash scripts/guard-vacuity-floor.test.sh`
  exits 0 with the new suite enrolled.
- **AC12** The wait heartbeat emits holder worktree, pid and elapsed at the configured interval.
- **AC13** `LOCK_CONTENDED_PROCEEDING` names a sibling count re-sampled after the wait.
- **AC14** `TC_LOCK_TIMEOUT`'s new default exceeds the full-gate wall clock measured in Phase 0.3,
  and the ADR addendum records both numbers.
- **AC15** With the lib absent, the runner emits `CAPACITY_UNKNOWN reason=lib_unavailable` and still
  completes — the verdict never silently vanishes.
- **AC16** The diff report names touched shards and does **not** recommend narrowing under
  `TEST_GROUP=all`.
- **AC16b** With an undeterminable diff (no `origin/main`, shallow clone, fresh repo) the report emits
  a **named** "diff undeterminable" line rather than nothing, and with a diff touching only
  `scripts/` it names `scripts` and not `webplat`. (Without this, M20 and M21 cite no criterion.)
- **AC17** No exit code changes: `git diff origin/main -- scripts/test-all.sh` shows no edit to any
  `exit` statement, and the EXIT CONTRACT block is unmodified.
- **AC18** `bash scripts/lint-orphan-test-suites.sh` exits 0 and reports no orphan, **and** the
  registration is asserted on the invoked **path**, not only the label:
  `grep -c 'bash scripts/test-all-capacity-signal\.test\.sh' scripts/test-all.sh` returns the
  registered count. Asserting the label alone would pass a registration whose path is typo'd — the
  linter derives coverage from the path. If the `-live` calibration arm is registered as its own
  `run_suite` line (the repo's `-live`/`-unit` convention), the expected count is **2** and both
  labels are asserted; if it is folded into the single suite, the count is **1** and this plan's
  `-live` wording says "folded in" rather than claiming to mirror the existing pairs.
- **AC19** The ADR-133 addendum exists, is dated and append-only, and records the cut decline with
  the 616 s redeemed-wait datum and the #7454 pointer.
- **AC20** Every mutation row below has been applied individually and observed to redden the suite;
  each transcript is recorded in the PR body.
- **AC21** `TEST_GROUP=scripts bash scripts/test-all.sh` on a clean tree reaches its terminal
  `=== N/M suites passed ===` marker with zero `[FAIL]` and zero `[KILLED]` lines. If a contention
  banner or `CAPACITY_CONTENDED` verdict fires, apply `work/SKILL.md` §9's three-way confirmation
  before accepting any RED — the verdict qualifies the run, it does not invalidate this AC.

### Post-merge

None. Every step runs in-session; none needs a browser, console, credential or human gate.

## Guard Contract

### Guard 1 — the capacity verdict

**Property.** Every `test-all.sh` invocation emits exactly one named capacity verdict, derived from
the same single `/proc` walk the banners use, which never reports a degraded reading as a healthy box.

**Assembly.** Structurally: *every emit path of `tc_capacity_line()`*, plus the single call site
between `tc_preamble` and `tc_acquire`, plus the lib-stub arm. One call site by construction — the
runner has one top-level control flow and `tc_acquire` has exactly one call site. Not "today's list
of three verdicts".

**Mutation matrix.** Each row must drive the suite RED.

| # | Mutation | Must redden because |
|---|---|---|
| M1 | Delete the sibling arm | AC3's 1-sibling and 5-sibling rows report `OK` |
| M2 | Delete the tmpfs arm | AC4's 1023 MB row reports `OK` |
| M3 | Change `>=` to `>` on the sibling comparison | AC3's at-threshold (1) row flips |
| M4 | Change `<` to `<=` on the tmpfs comparison | AC4's at-threshold (1024) row flips |
| M5 | Emit no verdict line at all | the guard's **own dispatch** — a verdict-less run must not pass |
| M6 | Collapse `CAPACITY_UNKNOWN` into `CAPACITY_OK` | AC5 — a degraded read must never read healthy |
| M7 | Make one degraded reading suppress a `CONTENDED` verdict from a healthy one | AC6's mixed row |
| M8 | Count PIDs instead of distinct worktrees | AC2's one-worktree/two-PID row reports 2 |
| M9 | Have the verdict re-walk `/proc` instead of using `tc_preamble`'s values | AC10 — verdict and banner can then disagree |
| M10 | Drop the measured value or the threshold from the line | AC7 |
| M11 | Remove the lib-stub arm | AC15 — the verdict vanishes silently when the lib is absent |
| M11b | **Read the promoted value without its validity flag** | AC5(b) — an unparseable `df` degrades to `0` and would emit `CONTENDED reason=low_tmp` instead of `UNKNOWN`, collapsing a degraded read into a measured one |

**Harness rows:**

| # | Mutation / input | Must redden, or pass, because |
|---|---|---|
| H1 | Neuter the suite's `fail()` to a no-op | the anti-vacuity floor `exit 1`s directly and must still fire |
| H2 | Delete every fixture so zero arms run | the arm-count floor must fail on `0 passed, 0 failed` |
| H3 | **must-PASS**: 0 siblings, 3000 MB tmpfs, healthy meminfo | a healthy box must yield `CAPACITY_OK` — only a must-PASS row catches a guard that rejects everything |
| H4 | **must-PASS**: non-canonical healthy fixture (different core count, different `TC_TMPDIR` path) | the contract permits these to vary |

### Guard 2 — `--capacity` is side-effect free

**Property.** `--capacity` answers and exits without running a suite, taking the lock, or changing
any exit code.

**Assembly.** The single early-exit branch, structurally *everything between the branch and its
`exit 0`*, quantified against the side-effect set the `--print-suite-globs` comment enumerates
(`TMPDIR` export, bare-repo guard, `TEST_GROUP` validation, `tc_acquire`).

**Mutation matrix.** Each row must drive the suite RED.

| # | Mutation | Must redden because |
|---|---|---|
| M12 | Move the branch below `tc_acquire` | AC8 — a `LOCK_` line appears |
| M13 | Make it `exit 1` on a contended box | **H5** — the must-PASS contended fixture is what pins exit 0 under contention; AC8 alone pins only the general case |
| M14 | Let it fall through into the suite loop | AC8 — the recorder logs suite invocations |

**Harness row:** H5 — **must-PASS**: `--capacity` on a *contended* fake box still exits 0.

### Guard 3 — the wait cannot abort, and is legible

**Property.** `tc_acquire` returns 0 on every path, and a session waiting on the lock can always
identify the holder.

**Assembly.** Every `return` path of `tc_acquire`, plus the heartbeat emitter — enumerated
structurally, since the function's contract is defined over *all* its exits.

**Mutation matrix.** Each row must drive the suite RED.

| # | Mutation | Must redden because |
|---|---|---|
| M15 | Make any `tc_acquire` path return non-zero | AC11 — ADR-133 Decision 3's load-bearing property |
| M16 | Delete the heartbeat | AC12 |
| M17 | Report the preamble's stale sibling count in the contended banner | AC13 |
| M18 | **Drop the trailing or-true guard from the re-sample's `grep -c` count** | verified: `grep -c` exits 1 on a zero count, so under `set -e` this aborts `tc_acquire` — on the *most common* post-wait state (the holder exited). The zero-post-wait-siblings fixture must redden |

**Harness row:** H6 — **must-PASS**: an uncontended acquire still emits `LOCK_ACQUIRED` and no heartbeat.

### Guard 4 — the diff report never narrows a pinned full run

**Property.** The report names the shards a diff touches and never recommends narrowing when
`TEST_GROUP=all` was requested.

**Assembly.** The single advisory-line emitter, quantifying over the `want_scripts` / `want_bun` /
`want_webplat` / `want_infra` path sets.

**Mutation matrix.** Each row must drive the suite RED.

| # | Mutation | Must redden because |
|---|---|---|
| M19 | Recommend a shard under `TEST_GROUP=all` | AC16 — ADR-183 Ceiling 1 |
| M20 | Delete the undeterminable-diff arm | **AC16b** — the undeterminable-diff fixture emits nothing instead of a named line |
| M21 | Hardcode the report to always name all four shards | **AC16b** — the `scripts/`-only fixture would also name `webplat` |

**Harness row:** H7 — **must-PASS**: a diff touching only `scripts/` names `scripts`, not `webplat`.

## Files to Edit

- `scripts/lib/test-contention.sh` — promote `tc_preamble`'s three measurements **and their validity
  flags** to script scope (zero output change); add `tc_capacity_line()` **before** `tc_acquire`;
  raise `TC_LOCK_TIMEOUT`'s default; add `TC_WAIT_HEARTBEAT_S`, the wait heartbeat and the
  contended-banner re-sample. Also update the file's own **`TEST SEAMS` header block**, which
  enumerates the overridable seams — it must gain `TC_WAIT_HEARTBEAT_S` (and, as a pre-existing gap
  worth closing in the same edit, `TC_DF_CMD`, which the block omits today).
- `scripts/test-all.sh` — the `--capacity` early-exit beside `--print-suite-globs`; the verdict
  emitter between `tc_preamble` and `tc_acquire`; the diff-justification line; a `tc_capacity_line`
  stub in the lib-stub block; one `run_suite` registration. **No `exit` statement is modified.**
- `plugins/soleur/scripts/grok-pre-push-gate.sh` — `--capacity` as advisory step 0 (does not gate).
- `plugins/soleur/skills/work/SKILL.md` — document the verdict + `--capacity` in §9.
- `plugins/soleur/skills/ship/SKILL.md` — note `--capacity` as the Phase 4 pre-launch probe.
- `knowledge-base/engineering/architecture/decisions/ADR-133-test-all-tmpfs-contention-managed-resource-and-advisory-lock.md` — dated, append-only addendum.

## Files to Create

- `scripts/test-all-capacity-signal.test.sh` — the mutation battery for all four guards.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **A longer `TC_LOCK_TIMEOUT` means a session blocks for longer, and an agent harness may reap a long-running background command.** `work/SKILL.md` records background-duration limits killing a gate 4× with exit 144. | The heartbeat is the mitigation: it makes the wait legible as a queue rather than a hang, and `work/SKILL.md` already instructs greping `LOCK_WAITING` before killing. Phase 6.4 extends that passage to the heartbeat. The budget stays env-tunable for a constrained harness. |
| **A wedged/orphaned sibling now holds the lock for a longer budget.** #7537 (no reaper) is OPEN. | Strictly better than today for *diagnosis*: the heartbeat names the holder's worktree/pid/elapsed while waiting, where today the wait is silent. `--capacity` surfaces the same holder in under a second without waiting at all. Reaping stays #7537. |
| **`low_tmp` will fire legitimately in the tail of a healthy run** — ADR-133 measured `/tmp` dipping to 699 MB during a run against the 1024 MB floor. | This is why the verdict is a *statement*, not a gate. Phase 0.4 re-measures post-run so the wording matches reality, and the verdict names the measured value so a reader can judge. |
| **The verdict becomes a permanently-degraded no-op on a hardened `/proc` or in a container, and nothing notices.** | `CAPACITY_UNKNOWN` is a distinct, loud token printed on every run with `reason=`, and the `-live` arm asserts the real reads are readable and numeric. Local tooling has no telemetry, so loudness is the honest mitigation; recorded in the ADR addendum rather than overclaimed. |
| **Two `/proc` walks disagreeing** (v1's defect). | Structurally impossible in v2: the verdict consumes `tc_preamble`'s values. AC10 and M9 pin it. |
| **The lib-stub guard's "LAST-defined function" invariant breaks** if a new function is appended after `tc_acquire`. | `tc_capacity_line()` is defined **before** `tc_acquire` (Phase 2.2), preserving the invariant the guard's own comment states; M11 pins the stub arm. |
| **Concurrent-session flake in the ACs** (`cq-ac-must-not-depend-on-concurrent-sessions`). | No AC asserts a live sibling count or the absence of a banner. Every threshold AC runs against a faked `/proc`; only the `-live` arm touches the real host, asserting readability and shape, never a value. AC21 explicitly permits a contention banner rather than requiring its absence. |
| **Scope reversal vs. the operator's stated ask.** | Recorded as **DC-2** and persisted to `decision-challenges.md`; the decline is deferred, not abandoned, and this PR ships the instrument that would meet its evidence bar. |

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Hard decline on over-capacity (v1) | **Rejected on review** — see §Plan Review Reversal (R1-R4). Deferred behind #7454 item 3. |
| Abort at `TC_LOCK_TIMEOUT` | **Rejected** — verbatim ADR-133's rejected alternative. |
| Replace the mutex with admission control | **Rejected** — ADR-133's 2026-08-11 verdict (TOCTOU, non-monotonic degradation). |
| Reuse `exit 4`, or mint `exit 5` | **Rejected** — with no blocking verdict, no exit semantics change at all; five consumers stay untouched. |
| A 5th `*_PATHS` relevance array | **Rejected** — six-site change, ~2.4% ceiling, documented live defect from that edit. DC-1. |
| Gate on `loadavg` | **Rejected** — measured non-signal (idle 15-min average moved 9.35 → 3.28 between two idle readings). |
| A new `tc_capacity_verdict()` doing its own `/proc` walk | **Rejected** — second non-atomic snapshot; `_tc_scan_procs`'s header forbids it. |
| A separate `scripts/check-capacity.sh` | **Rejected** — "a paragraph in a prompt IS agent discretion"; and `--capacity` on the runner itself cannot drift from the runner's own measurement. |

## Test Scenarios

Every scenario is "mutation → guard reddens"; the matrix (M1-M21, H1-H7) is authoritative.
Additionally:

1. Healthy fake box ⇒ `CAPACITY_OK` with measured values.
2. One sibling ⇒ `CAPACITY_CONTENDED reason=sibling_runs measured=1 threshold=1`.
3. Two PIDs in one worktree ⇒ `siblings=1`.
4. tmpfs 1023 / 1024 / 3000 MB ⇒ contended / not / not.
5. Each degraded input ⇒ `CAPACITY_UNKNOWN` with the right `reason=`.
6. Mixed degraded + over-threshold ⇒ `CONTENDED`, degraded reading named.
7. `--capacity` on healthy and contended boxes ⇒ exit 0 both times, zero suites, no `LOCK_` line.
8. Verdict sibling count == banner sibling count in one run.
9. `tc_acquire` returns 0 on every arm; heartbeat emits holder identity; contended banner re-samples.
10. Lib absent ⇒ `CAPACITY_UNKNOWN reason=lib_unavailable`, run completes.
11. Diff touching only `scripts/` ⇒ names `scripts`; under `TEST_GROUP=all` ⇒ no narrowing advice.
12. `-live` calibration: real `/proc/meminfo`, `nproc`, `df` readable and numeric.
13. `git diff origin/main -- scripts/test-all.sh` shows no modified `exit` statement (AC17).

## Sharp Edges

- **`tc_acquire` must return 0 on every path, and the live hazard is `grep -c`, not the expansions.**
  Measured: `_tc_scan_procs` is *already* errexit-safe (every internal read is guarded and it ends
  `return 0`), so the usual `${VAR:-}` / numeric-shape discipline, while still required, is not what
  breaks here. What breaks is the counting idiom: **`grep -c` exits 1 on a zero count** (verified),
  which is why `tc_preamble` writes `… | grep -c . || true`. Omit that `|| true` in the re-sample and
  `set -e` aborts `tc_acquire` — and since `tc_acquire "test-all"` is a bare top-level command, the
  entire run dies with no summary, no rc file and no `[FAIL]` line. Zero post-wait siblings is the
  *expected* case, so the naive version fails on the common path. M15 and M18 pin this.
- **A degraded reading must be carried as a flag, never inferred from the value.** `tc_avail_mb`,
  `tc_used_pct` and `tc_used_bytes` all degrade an unreadable or unparseable probe to **`0`**, which
  is below every floor — so "could not read" and "read a critically low number" are the same number.
  The verdict must consume the promoted validity flag, not the value alone, or P5 is false for the
  tmpfs and memory signals. M11b pins this.
- **The new suite auto-enrols into `scripts/guard-vacuity-floor.test.sh`** via its derived
  `COVERED_DIRS='^(scripts/|plugins/soleur/test/)'` population. Satisfying only "the floor exits 1
  directly" is not enough — ADR-193 Decisions 2, 3 and 4 (call-site case counter, `passes + fails ==
  cases` conservation, conservation *before* the floor) are all enforced, and a suite missing any of
  them reds the exit gate on its own construction.
- **Define `tc_capacity_line()` BEFORE `tc_acquire` in the lib.** The runner's stub block guards on
  `declare -F tc_acquire` and its comment states the reason: `tc_acquire` is "the LAST-defined
  function in the lib", which is what closes the truncated-file edge. Appending after it silently
  breaks that rationale.
- **`--capacity` must exit before every side effect**, exactly as `--print-suite-globs` does — its
  comment records that a path blocking on `tc_acquire` would deadlock the gate on itself.
- **Do not fold the verdict into `tc_preamble`'s output.** The `[contention] BANNER` names are a
  grepped contract in `work/SKILL.md`; AC9 pins byte-identity. Promoting *variables* changes no bytes.
- **Repo-root `scripts/*.test.sh` is NOT auto-discovered.** `SUITE_GLOBS` carries
  `scripts/lib/*.test.sh` but not `scripts/*.test.sh` (verified), so the new suite needs an explicit
  `run_suite` line or it runs in zero runners and stays green forever. AC18 pins both directions.
- **Do not reintroduce a blocking verdict without #7454 item 3's evidence bar.** The bar is: an
  in-suite sampler at ≤2 s resolution, ≥3 single-runner runs, ≥2 runs at N=2 and ≥1 at N=3 with the
  lock disabled, a re-verified filesystem premise, and one adversarial run. The verdict line this PR
  ships is the instrument that produces most of it.
- **A raised `TC_LOCK_TIMEOUT` is tuning, not a mechanism change** — but only while the
  proceeds-on-expiry behaviour is preserved. If a future change makes expiry abort, that is
  ADR-133's rejected alternative and needs the bar.

## Decision Challenges

**DC-1 (User-Challenge).** The brief scoped in a diff-justification check reusing
`scripts/lib/test-relevance-paths.sh`. This plan ships it as a **report**, not a decline, and adds no
fifth `*_PATHS` array: the measured ceiling is 4 gated suites of 167 registrations (~2.4%), the
brief's own steer records 3 declines of 325, and the `GATED` table's comment records a live defect
where a fifth gate left the linter, the harness floor and every behavioural arm green.

**DC-2 (User-Challenge) — the significant one.**

- **The operator's stated direction:** a pre-launch *decision* that declines a full gate the box
  cannot absorb, plus a decision about the `LOCK_CONTENDED_PROCEEDING` path.
- **What this plan ships instead:** a pre-launch *verdict and query* (`--capacity`) that answers the
  same question without blocking, plus a raised lock budget and a wait heartbeat so the contended
  path stops firing routinely.
- **Why:** four independent reviewers converged, and the decisive evidence is in the ADR the issue
  itself rests on — ADR-133 records a run redeemed after a **616 s** wait behind two siblings, which
  a `>= 1` sibling decline would have refused at t=0, converting a completed gate into no coverage.
  A decline would also block `git commit` through `lefthook`'s `pre-commit` hook, and would be
  misread at `/ship` Phase 4, whose docs state rc=4 means "you are a spawned agent" — sending a ship
  session to set the very override that re-creates the incident.
- **What the operator gets anyway:** the pre-launch check they asked for, in under a second, before
  launching — and hand-queueing removed rather than renamed, because a raised budget plus a
  heartbeat makes the wait complete unattended instead of expiring into a 6-way pile-up.
- **How to reverse:** the decline is deferred, not abandoned. #7454 item 3 holds the evidence bar,
  and the verdict line shipped here is the instrument that produces most of that evidence. Say the
  word and it ships as its own PR on measurement rather than on argument.

Issue constraint 4 explicitly licenses this shape: *"a gate may therefore let a run proceed and
qualify its output — it does not have to block to be useful."*

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Local developer tooling; no product runtime surface, user data, tenant boundary,
network call or credential. The architectural weight sits entirely in ADR-133's territory, and after
the review reversal the change is what that ADR's Decision 1 mandates — instrumentation ahead of
mechanism — plus a tuning of Decision 3's own parameter, which its 2026-08-11 addendum explicitly
names as an unconsidered candidate. Decision 3's advisory/never-abort property is preserved verbatim
and pinned by M15. No exit-code contract changes, so the five downstream consumers are untouched.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Create` and `## Files to Edit`
matches no UI-surface path (no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, nor any
term from the shared UI-surface list), so the override does not fire and Product = NONE stands.

**Gates skipped, with reason:** GDPR/compliance (Phase 2.7) — no regulated-data surface and none of
the four expansion triggers fire. Infrastructure-as-Code (Phase 2.8) — no server, service, secret,
vendor, DNS record or persistent runtime process. Encryption Posture (Phase 2.11) — no persistent
store, no new cross-component connection. Skill-description budget (Phase 1.8) — the only `SKILL.md`
edits are body prose, not `description:`.
