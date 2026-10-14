---
title: "fix: serialize test-all advisory-lock waiters FIFO so a >3600s hold releases one queued run at a time"
date: 2026-09-22
type: fix
slug: fix-tc-lock-timeout-fifo-queue
branch: feat-one-shot-8579-lock-timeout-margin
issue: 8579
closes: 8579
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
status: deepened
---

# fix: serialize test-all advisory-lock waiters FIFO so a >3600s hold releases one queued run at a time

Closes #8579.

> Spec directory did not exist at plan time and carried no `lane:` — defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`tc_acquire` in `scripts/lib/test-contention.sh` gives every queued `test-all.sh` run the same
independent `flock -w 3600` wait on the repo-wide advisory lock. When a live holder's run outlasts
the budget — 8,070 s was measured for a sibling holder on 2026-09-22 — every waiter's timer expires
at roughly the same instant and they all take the `LOCK_CONTENDED_PROCEEDING` path together. The
raise from 900 s to 3,600 s (#7545) moved the boundary; it did not change the release *shape*, so
the six-concurrent-runs pileup that motivated the lock recurs, just above a higher waterline.

The fix adds a **ticket queue in front of the existing `acquire_lock` call**: every run that reaches
the wait mints a flock-anchored ticket under the same git-common-dir lock root, and only the head of
the queue makes the bounded `acquire_lock` call. A waiter whose own queue patience expires still
proceeds contended — never aborts — but the common overrun case now releases runs one at a time and
in arrival order, so a pileup becomes a drip instead of a breach. A complementary overrun beat in
the existing wait heartbeat tells a queued run (and anyone reading the log) when its wait has
outlasted the lock budget — the detected-long-hold signal the issue names as a candidate.

No primitive is added or modified: tickets are `flock(1)` locks on zero-byte files in a sibling
directory of `test-all.lock`, and the only blocking `flock -w` call in the repo remains the existing
one inside `session-state.sh`'s `_acquire_lock_impl` — the queue itself probes with non-blocking
`flock -n` so it cannot inherit the "`-w` never fired" defect recorded in #7697.

### What this plan deliberately does NOT determine

- **Whether the ~45-minute uncontended gate should shrink.** That is #8329 / #7454 item 1
  territory; shrinking the hold shrinks the margin problem proportionally but does not change the
  release shape — any finite budget still has a synchronized expiry. Out of scope here.
- **Whether a contended run's results are trustworthy.** ADR-133 already records that verdict: a
  contended run is attributable, not authoritative. The queue narrows how often that state is
  reached; it does not strengthen what it means.
- **Admission control / decline.** Cut by #7545 on the ADR-133 616 s redeemed-wait evidence and
  deferred behind #7454 item 3's evidence bar. The queue is not a decline — every waiter still runs.

## Premise Validation

| Cited premise | Probe | Result |
| --- | --- | --- |
| #8579 open, unresolved | `gh issue view 8579` | **HOLDS** — OPEN, label `meta/machinery`, milestone "Post-MVP / Later" |
| #7545 closed by merged PR (900→3600 raise + heartbeat) | `gh issue view 7545` → CLOSED; `git log --grep='#7614'` → `5cf9761a48` merged | **HOLDS** |
| #7869 closed by merged PR (14,400 s runtime ceiling) | `gh issue view 7869` → CLOSED; commit `2576c64fa7` on main | **HOLDS** |
| #6789 closed (preamble + advisory lock landed) | `gh issue view 6789` → CLOSED | **HOLDS** |
| `tc_acquire` fail-open: proceeds with banner, returns 0 | read `scripts/lib/test-contention.sh:1039-1073` | **HOLDS** — `acquire_lock` fail → `LOCK_CONTENDED_PROCEEDING`, `return 0` |
| `acquire_lock` returns 99 on timeout/unavailable | `plugins/soleur/scripts/lib/session-state.sh` `_acquire_lock_impl` | **HOLDS** — `flock -w` fail → `return 99` |
| flock releases on holder death; stale-detection is dead code | ADR-133 + #7869 addendum; AC5b arm `test-contention.test.sh:669-691` | **HOLDS** — kernel releases on last-fd close, measured under SIGKILL |
| "flock grants in arrival order" (issue body) | issue prose | **UNRELIABLE** — Linux `flock` wait ordering is not a documented FIFO guarantee; the plan does not lean on it (tickets provide the order) |
| Mechanism vs ADR corpus | read ADR-133 `## Alternatives Considered` + all addenda | **HOLDS** — a ticket queue is absent from the rejected list; "making acquisition blocking with a documented escape" is named a *candidate never considered*; abort-on-timeout stays rejected and is preserved |
| #7697: `flock -w` can fail to fire (SIGALRM hypothesis) | `gh issue view 7697` → OPEN, waiter stuck in `locks_lock_inode_wait` 4.6 d | **HOLDS** — the queue therefore uses no new `flock -w` call |

## Research Reconciliation — claim vs. measured codebase

| Claim | Reality (measured) | Plan response |
| --- | --- | --- |
| **R1.** "the lock serializes runs; waiters queue" | `flock` has no application-level queue. Every waiter independently calls `flock -w 3600`; on a >3600 s hold they all time out near-simultaneously and proceed together. | Add the ticket stage in front of `acquire_lock`; only the head blocks on the main lock. |
| **R2.** "`session-state.sh` initializes `LOCK_DIR` for its callers" | `_session_state_init_dirs` runs **inside** `_acquire_lock_impl`; `$LOCK_DIR` is unset in a caller until the first `acquire_lock`. Test harnesses also stub session-state.sh entirely (`test-all-capacity-signal.test.sh` provides only `acquire_lock`). | The queue calls `_session_state_init_dirs` itself when declared; when it is not declared (stub), the run degrades to today's direct-acquire path with a named `LOCK_QUEUE_DEGRADED` line. |
| **R3.** "`TC_LOCK_TIMEOUT`'s default is free to retune" | `test-all-capacity-signal.test.sh:1073-1079` (AC14) extracts the default and asserts it **exceeds 2700 s**. | The default is untouched (3600). Any future retune must update AC14 in lockstep. |
| **R4.** "`tc_acquire \"test-all\"` can be re-anchored" | Four suites splice or grep the literal call site: `fanout-suite-scope.test.sh:95,329`, `test-all-killed-classification.test.sh:218`, `test-all-runtime-ceiling.test.sh:85`, `repo-write-boundary.test.sh:407,569`. | `scripts/test-all.sh` is **not edited**. All change lives inside `tc_acquire` in the lib. |
| **R5.** "`LOCK_WAITING` placement is cosmetic" | `test-contention.test.sh:900-921` iterates every skip path asserting `LOCK_WAITING` absent; `:540-617` assert it precedes every outcome line. | `LOCK_WAITING` stays byte-identical and positioned after all skip paths; a new `LOCK_QUEUED` line is emitted only after a ticket is minted. |
| **R6.** "post-run triage catches any new proceed line" | `work/SKILL.md` triage grep anchors on `LOCK_CONTENDED` (and `[contention] BANNER`). A differently-named proceed token would be invisible to it. | The queue-timeout path still emits the canonical `LOCK_CONTENDED_PROCEEDING` line (with a `queue_timeout=1` field); the preceding `LOCK_QUEUE_TIMEOUT` line is explanatory. |
| **R7.** "queueing time is unbounded overhead" | `_RUN_START_EPOCH` is stamped at `test-all.sh:1434`, **before** `tc_acquire` (:1551); the 14,400 s ceiling already meters queue+wait time (ADR-133 #7869 addendum). | No new bound needed for run lifetime; `TC_QUEUE_TIMEOUT` bounds only the *ticket* wait and exists so the queue cannot do worse than today's shape. |
| **R8.** "the holder can be identified for diagnostics" | ADR-133 #7545 addendum: `/proc`-walk holder naming was measured wrong ~83% of the time (names fellow waiters) and cost ~313 CPU-s per wait. | The heartbeat gains `position=N` (knowable exactly from ticket files) and nothing else; `--capacity` remains the "who is running" answer. |

## Open Code-Review Overlap

Query run 2026-09-22 over 75 open `code-review` issues, `jq --arg path … contains($path)` per
edited file (`scripts/lib/test-contention.sh`, `scripts/test-contention.test.sh`,
`plugins/soleur/skills/work/SKILL.md`, `ADR-133-*.md`). One hit:

- **#7942** ("Two mutation batteries in `plugins/soleur/test/` are named `*.mutation.sh` and run in
  no gate") names `scripts/test-all.sh` only as the runner that fails to reach the batteries.
  **Acknowledge** — different concern; this plan neither registers nor renames a suite, and does not
  touch `test-all.sh`.

## Hypotheses (network-outage gate)

The Phase-1.4 gate fired on the token `timeout` (`TC_LOCK_TIMEOUT` appears throughout). **Inapplicable**:
no network path, no remote host, no sshd/firewall surface is involved — this is kernel `flock`
behaviour on local files. L3→L7 ordering has nothing to order; `hr-ssh-diagnosis-verify-firewall`
telemetry is deliberately not emitted (emitting `applied` for a rule that did not apply is false
telemetry). Recorded for auditability only.

## User-Brand Impact

- **If this lands broken, the user experiences:** a local `test-all.sh` gate that either wedges at
  the queue stage (a run that never starts and never explains why — the exact hang the heartbeat
  exists to prevent) or silently stops serializing (the pileup returns, and contended false-REDs
  get misdiagnosed as real regressions — the class ADR-133 was written to kill).
- **If this leaks, the user's workflow is exposed via:** the shared state root
  (`.git/soleur-session-state/`) is local-only; no data leaves the machine. The exposure is time —
  a defective queue burns gate-hours across every worktree on the box.
- **Brand-survival threshold:** `aggregate pattern` — not a user-facing surface, but a repeated
  false-RED/wedge pattern across the agent sessions this repo runs is how the original incident
  earned its ADR.

## Technical Approach

### Architecture

New state, all inside `tc_acquire` and `_tc_*` helpers in `scripts/lib/test-contention.sh`
(`session-state.sh` and `test-all.sh` are untouched):

```
$LOCK_DIR/test-all.lock            # existing — the serialization primitive (unchanged)
$LOCK_DIR/test-all.queue.d/        # NEW — one entry per queued-or-running waiter
    .alloc                         # NEW — flock serializing ticket mint/scan (~ms holds)
    00000007                       # a ticket: zero-byte-ish file, flock -x held by its owner
    00000008                       # … next serial; contents = "pid worktree epoch" (diagnostic)
```

**Minting.** Under `.alloc` (acquired via `flock -n` in a bounded retry loop — no `flock -w`, so the
#7697 masked-SIGALRM defect is unreachable): `serial = 1 + max(numeric filenames)`, create the file,
open `>>` fd, `flock -x` it — all before releasing `.alloc`, so a ticket is never observable as
created-but-unlocked. The fd stays open for the life of the `tc_acquire` caller (mirroring
`_SESSION_LOCK_FDS` semantics); the kernel releases it on death — no reaper needed, and suite
children inheriting the fd keep the ticket alive exactly as they keep the main lock alive today.

**Head-check.** Under `.alloc`, a waiter is head iff no numeric filename strictly below its serial
is still flock-held (each probed with non-blocking `flock -n -x <file> -c true`). Holding `.alloc`
for the scan makes the check atomic against minting.

**Waiting.** Non-head waiters poll the head-check every `TC_QUEUE_POLL_S` (default 5 s — two flock
probes and a readdir; the old `/proc` walk's ~6 s-per-beat cost is the measured anti-pattern this
avoids). The existing `_tc_wait_heartbeat` brackets the whole wait (queue stage + lock stage) with a
combined budget of `TC_QUEUE_TIMEOUT + timeout_s`, gains a `position=N` field, and switches its
banner token to `LOCK_WAIT_OVERRUN` once `waited ≥ timeout_s` — the detected-long-hold signal.

**Release paths (all `return 0`, never abort):**

| State | Action | Line emitted |
| --- | --- | --- |
| head + lock acquired | proceed | `LOCK_ACQUIRED` (unchanged) |
| head + `acquire_lock` times out | proceed contended | `LOCK_CONTENDED_PROCEEDING` (unchanged) |
| `TC_QUEUE_TIMEOUT` while non-head | proceed contended | `LOCK_QUEUE_TIMEOUT` + `LOCK_CONTENDED_PROCEEDING queue_timeout=1` |
| queue unavailable (no state root, mint fails) | skip queue, direct `acquire_lock` | `LOCK_QUEUE_DEGRADED reason=<…>` |

**Ticket sweep.** While holding `.alloc` for a mint, delete ticket files that are both unlocked
(probe `flock -n`) and older than `TC_RUNTIME_CEILING_S`. Locked tickets are never swept, so `max+1`
numbering can never regress below a live ticket; a dead waiter's unlocked file is the only thing
removed. Bounds directory growth to ~live waiters + one ceiling's worth of history.

**`TC_QUEUE_TIMEOUT` default = `TC_LOCK_TIMEOUT` (3600 s).** Worst case stays today's shape
(bounded wait → contended proceed), spaced by arrival rather than synchronized; the common case —
one overrun holder — serializes fully. Raising it strengthens serialization at the price of longer
bounded waits; it is env-tunable like its sibling.

### Implementation Phases

#### Phase 1 — ticket machinery in `scripts/lib/test-contention.sh`

- Add `_tc_queue_dir` (resolves `$LOCK_DIR/<name>.queue.d`, mints `.alloc`), `_tc_ticket_mint`
  (alloc-loop → serial → create+flock under alloc → sweep), `_tc_queue_position` (count earlier
  held tickets), `_tc_queue_wait` (poll head-check; rc 0 at head, 1 at `TC_QUEUE_TIMEOUT`).
- Restructure `tc_acquire` between the existing `LOCK_WAITING` emit and the `acquire_lock` call:
  heartbeat start moves above the queue stage; degrade path emits `LOCK_QUEUE_DEGRADED` and falls
  through to today's acquire block; queue-timeout emits `LOCK_QUEUE_TIMEOUT` then the existing
  contended tail.
- Extend `_tc_wait_heartbeat` with `position=` and the `LOCK_WAIT_OVERRUN` token past budget.
- No `flock -w` anywhere in the new code; every new failure arm ends in `return 0` or a degrade to
  the pre-queue path.

#### Phase 2 — arms in `scripts/test-contention.test.sh`

New Phase-3b arms, all under `SOLEUR_SESSION_STATE_ROOT="$SS_ROOT"` + `lock_env`, each carrying its
named mutation control per the suite's authoring constraints. Deterministic ordering comes from
holding processes alive with a trailing `sleep` after `tc_acquire` returns (the ticket fd outlives
the call inside its owning shell) and gating each step on `await_held` probes of the ticket files —
never on wall-clock guesses.

#### Phase 3 — docs + ADR addendum

- ADR-133 addendum: the ticket queue decision, the mixed-version semantics, the `TC_QUEUE_TIMEOUT`
  escape, and the corrected ceiling arithmetic (queue wait is no longer ≤ `TC_LOCK_TIMEOUT`).
- `plugins/soleur/skills/work/SKILL.md`: the two queue-behaviour paragraphs (`:1144` queued-run
  semantics, `:1508` LOCK_WAITING stall-vs-queue triage) gain the ticket/position reality — a queued
  run now reports `position=` and can outlast `TC_LOCK_TIMEOUT` before proceeding.

#### Phase 4 — verification

- `bash scripts/test-contention.test.sh`, `bash scripts/test-all-capacity-signal.test.sh`,
  `bash scripts/lib/repo-write-boundary.test.sh`, `bash plugins/soleur/test/fanout-suite-scope.test.sh`
  — all green; then `scripts/test-all.sh scripts` includes the contention suite (registered at
  `test-all.sh:1901`).

## Alternative Approaches Considered

| # | Alternative | Why rejected |
| --- | --- | --- |
| **A1** | Raise `TC_LOCK_TIMEOUT` again | The 2026-08-19 addendum already records the honest claim: "a bounded improvement, not a value proven sufficient for the contended tail." Any finite budget below the 14,400 s ceiling has a synchronized expiry; 8,070 s was already measured. Treats the margin, not the release shape. |
| **A2** | Chain/tail lock (each waiter holds `<name>.tail` while blocking on the main lock) | Serializes *entry into the wait* but not *exit from the run*: a timed-out head proceeds contended and releases the tail, so two contended runs can still overlap — the defect survives in a slower costume. Tickets held for the run's lifetime close that hole. |
| **A3** | PID-file / pid-liveness queue | `flock` fd-liveness is the authoritative liveness oracle in this codebase; pid reads killed two live worktrees in #5454 and ADR-133 records why hand-rolled liveness is the rejected shape. |
| **A4** | Blocking-with-abort past a longer budget | ADR-133 `## Alternatives Considered` rejection stands verbatim; preserved by design. |
| **A5** | Stale-ticket reaper on pid/mtime heuristics | Dead holders release their flock on fd close (AC5b-measured); the only sweep needed is bounded garbage collection of *unlocked* files, and that runs under `.alloc` where the check is atomic. |
| **A6** | Reduce the ~2700 s gate cost (issue candidate 2) | Out of scope — proportionally shrinks the margin but cannot change the release shape; tracked by #8329 (affected-suites gate) and #7454 item 1. |
| **A7** | Do nothing — accept the synchronized release | The issue's evidence (8,070 s hold, multiple queued waiters) is the pileup mechanism recurring at a higher waterline; "nothing" re-litigates #7545's incident. |

## Observability

The deliverable's observable surface is the named stderr line set — extended, not replaced:

```yaml
liveness_signal:
  what: "LOCK_WAIT_HEARTBEAT beat carrying position=N while queued; LOCK_WAIT_OVERRUN token once waited >= TC_LOCK_TIMEOUT"
  cadence: "TC_WAIT_HEARTBEAT_S (default 60 s) for the duration of queue+lock wait"
  alert_target: "run stderr — surfaced to whoever reads the gate log; post-run triage grep in work/SKILL.md"
  configured_in: "scripts/lib/test-contention.sh (_tc_wait_heartbeat / tc_acquire)"
error_reporting:
  destination: "stderr of the invoking run (no remote target exists for local dev tooling — ADR-133 records this)"
  fail_loud: "LOCK_QUEUE_DEGRADED / LOCK_QUEUE_TIMEOUT / LOCK_CONTENDED_PROCEEDING / LOCK_WAIT_OVERRUN are all named, greppable lines"
failure_modes:
  - mode: "ticket machinery unusable (no state root, mint fails)"
    detection: "LOCK_QUEUE_DEGRADED line + direct-acquire fallback; suite arm asserts both"
    alert_route: "run log; contention suite goes red if the line or the fallback vanishes"
  - mode: "holder outlives budget (the incident shape)"
    detection: "LOCK_WAIT_OVERRUN beats with position=; LOCK_QUEUE_TIMEOUT on the escape arm"
    alert_route: "run log + work/SKILL.md triage grep (LOCK_CONTENDED still fires on the proceed)"
  - mode: "waiter killed mid-queue"
    detection: "successor's position= decrements; kernel release, no reaper needed"
    alert_route: "none needed — flock release is kernel-automatic (AC5b)"
logs:
  where: "run stderr (captured into the run's log file by the calling harness)"
  retention: "whatever retains the run log; ticket files themselves are swept after TC_RUNTIME_CEILING_S once unlocked"
discoverability_test:
  command: "grep -oE 'LOCK_QUEUE_[A-Z_]+|LOCK_WAIT_OVERRUN' scripts/lib/test-contention.sh | sort -u"
  expected_output: "LOCK_QUEUE_DEGRADED, LOCK_QUEUE_TIMEOUT, LOCK_WAIT_OVERRUN"
```

## Encryption Posture

**Gate status: satisfied — no data store or connection is introduced.** Phase 4.10's prose trigger
brushes the word "queue"; the queue directory holds zero-payload flock anchors (name = ordinal;
content = a diagnostic `pid worktree epoch` line written and read on the same host, never
transmitted). No persistent data store, no cross-component or network connection, nothing encrypted
or decryptable is at issue — there is nothing to protect because nothing is stored.

## Guard Contract

The ordering property is an ORDER/LIFETIME invariant, so the matrix carries a reorder row and a
window-internal observation row per the contract's own rules.

### Guard 1 — a waiter may proceed only when every strictly-earlier ticket is released (or its own queue timeout expired)

**Property.** No `tc_acquire` invocation reaches the `acquire_lock` call (or the contended
proceed tail) while a strictly-earlier ticket in `<name>.queue.d` is still flock-held, unless that
waiter's `TC_QUEUE_TIMEOUT` has expired — one release at a time, in mint order.

**Assembly.** The single chokepoint is `_tc_queue_wait`'s head-check inside `tc_acquire` in
`scripts/lib/test-contention.sh` — every waiter holding a ticket passes through exactly that loop;
there is no second path to `acquire_lock` once a ticket exists. The assembly quantifies over all
numeric entries of `<name>.queue.d` resolved under `.alloc` — not a list of today's files but the
mint-scan-probe structure itself (minting, sweeping, and head-checking all flow through the `.alloc`
critical section, which is what makes the enumeration race-free).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Head-check ignores earlier tickets (`return 0` unconditionally — the guard's own dispatch never discriminates) | RED: two-waiter arm asserts B emits no proceed line while A's ticket is held |
| 2 | Probe direction inverted (`<` → `>` — a check that stops at / scans the wrong half of the queue) | RED: three-waiter arm asserts release order == serial order |
| 3 | Second member: with A(head, held ticket) and B queued, C mints a third ticket; C must not proceed while EITHER A or B is held | RED if the check counts only the immediately-previous ticket or only ticket-minus-one |
| 4 | Reorder: move the ticket `flock -x` outside the `.alloc` critical section | RED: the simultaneous-mint arm asserts no two waiters ever observe each other as unordered (a created-but-unlocked ticket is invisible-but-real under the mutation) |
| 5 | Observe inside the window: harness fixture that reports B's `position=` while A still holds ticket 1 | must-PASS asserting `position=2` and zero proceed lines; mutating the fixture's `await_held` to always-report-held must drive the arm RED |
| 6 | Non-contiguous serials (a killed middle waiter leaves a numbering gap) | must-PASS: later waiters still serialize correctly — the contract permits gaps |

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-133** (`knowledge-base/engineering/architecture/decisions/ADR-133-test-all-tmpfs-contention-managed-resource-and-advisory-lock.md`)
with a dated addendum — "waiters release in ticket order, not on a shared expiry" — recording:
Decision 3 is extended, not reversed (still advisory, still never aborts, still kernel-released);
the `flock -w`-free probing choice and its #7697 motivation; `TC_QUEUE_TIMEOUT` semantics and its
default; the corrected claim that queueing time charged to `_RUN_START_EPOCH` is no longer bounded
by `TC_LOCK_TIMEOUT`; and the mixed-version caveat (a worktree running pre-queue code ignores
tickets — degradation is to today's behaviour, never worse). No new ordinal.

### C4 views

Read of `model.c4`, `views.c4`, `spec.c4` (824 + 104 + 54 lines). **No C4 impact** — enumeration:
(a) external human actors: unchanged — the same `founder`/`devin` actors run the same runner; no new
sender/receiver exists; (b) external systems/vendors: none — `flock` on git-common-dir files is
kernel-local, no service edge is added; (c) containers/data stores: none touched — the ticket
directory lives under `.git/soleur-session-state/locks/`, local test-tooling state the model does
not (and should not) represent; (d) actor↔surface relationships: unchanged — the change is internal
to `tc_acquire`, invisible to every modeled element. A reader of the ADRs + C4 would not be misled:
the architecture record for this lock lives in ADR-133, which the addendum keeps true.

### Sequencing

The ADR addendum lands in the same PR as the mechanism (Phase 3) — not a follow-up issue.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — local test-infrastructure change. No UI-surface file in
Files to Edit/Create; the mechanical UI-surface override does not fire; Product tier: none.

## Acceptance Criteria

- [ ] **AC1** — Given the main lock held and two queued waiters, when the hold exceeds `TC_LOCK_TIMEOUT`, then at most one waiter is on a proceed path at a time: the head proceeds (acquired or contended) while the next remains queued until the earlier ticket is released.
- [ ] **AC2** — Release order equals ticket mint order for any set of waiters that started in distinct order.
- [ ] **AC3** — A `SIGKILL`ed queue head's ticket releases with no reaping code; the next waiter's head-check passes (the AC5b property applied to tickets).
- [ ] **AC4** — `TC_QUEUE_TIMEOUT` expiry on a non-head waiter emits `LOCK_QUEUE_TIMEOUT` + `LOCK_CONTENDED_PROCEEDING queue_timeout=1` and returns `rc=0`. No path returns non-zero or aborts the run.
- [ ] **AC5** — Unresolvable queue state (stubbed session-state, unwritable dir, mint failure) emits `LOCK_QUEUE_DEGRADED reason=<…>` and falls through to today's direct `acquire_lock` path with `rc=0`.
- [ ] **AC6** — Every existing skip path (`SOLEUR_DISABLE_SESSION_STATE=1`, `CI` set, missing session-state.sh, missing `flock`, missing `acquire_lock`, empty name) returns before any ticket is minted — no `*.queue.d` entry is created by a skipped run.
- [ ] **AC7** — `LOCK_WAITING` remains byte-identical and precedes every outcome; `LOCK_QUEUED`/`LOCK_QUEUE_*` lines appear only after the skip-path gauntlet; `LOCK_ACQUIRED`, `LOCK_CONTENDED_PROCEEDING`, `LOCK_SKIPPED_*`, `LOCK_UNAVAILABLE` texts are unchanged.
- [ ] **AC8** — The heartbeat carries `position=N` during the queue stage, keeps the `waited=<N>s of <M>s` shape, does not self-terminate before `TC_QUEUE_TIMEOUT + timeout_s`, and switches token to `LOCK_WAIT_OVERRUN` once `waited ≥ timeout_s`.
- [ ] **AC9** — No new `flock -w` call is added to the queue path (`flock -n` probes + the bounded `-n` retry loop on `.alloc`); the only blocking `flock -w` in the repo's lock path remains `_acquire_lock_impl`'s.
- [ ] **AC10** — `scripts/test-all.sh` is unmodified; the literal `tc_acquire "test-all"` call site and `tc_epilogue "${_TC_RUN_START_ENTRIES:-0}"` anchors are untouched.
- [ ] **AC11** — `bash scripts/test-contention.test.sh`, `bash scripts/test-all-capacity-signal.test.sh`, `bash scripts/lib/repo-write-boundary.test.sh`, and `bash plugins/soleur/test/fanout-suite-scope.test.sh` are all green; `pass_n + fails == cases` and the anti-vacuity floors hold in the edited suite.
- [ ] **AC12** — ADR-133 gains the dated addendum; `work/SKILL.md` queue/triage prose matches shipped behaviour.
- [ ] **AC13** — Ticket state lives only under `$LOCK_DIR` (the git common dir session-state root) — no writes into the worktree, `/tmp`, or the suite's `TESTROOT` boundary at runtime.

## Test Scenarios

New arms land in `scripts/test-contention.test.sh` (Phase 3b), driven through `lock_env` +
`SOLEUR_SESSION_STATE_ROOT` so the real `session-state.sh` and real `flock` are exercised against
`TESTROOT`. Ordering is made deterministic by keeping each waiter's shell alive after `tc_acquire`
returns (trailing `sleep` holds the ticket fd) and by gating on `await_held`-style `flock -n`
probes of ticket files rather than sleeps.

| # | Scenario | Expected |
| --- | --- | --- |
| T1 | Free lock, single waiter | `LOCK_WAITING` → `LOCK_QUEUED` → `LOCK_ACQUIRED` in that order; `rc=0`; a `test-all.queue.d` ticket exists and is released on shell exit |
| T2 | Held main lock + waiters A then B; hold exceeds A's `timeout_s` | A proceeds contended **while holding its ticket** (its shell stays alive); B emits no proceed line and reports `position=2` — the defect's exact regression arm |
| T3 | T2 then A's shell exits | B becomes head, acquires or proceeds contended — release is serialized by ticket release, not by wall clock |
| T4 | Three waiters minted in order, holder released mid-way | proceed order == serial order (FIFO), each waited's `LOCK_ACQUIRED`/`LOCK_CONTENDED_PROCEEDING` sequence-numbered |
| T5 | `kill -9` the head waiter's shell mid-queue | ticket lock releases (kernel); next waiter becomes head with no reaper code |
| T6 | Non-head waiter with `TC_QUEUE_TIMEOUT=2` behind a held ticket | `LOCK_QUEUE_TIMEOUT` + `LOCK_CONTENDED_PROCEEDING queue_timeout=1`; `rc=0` |
| T7 | session-state stub lacking `_session_state_init_dirs` (capacity-suite shape) | `LOCK_QUEUE_DEGRADED` + direct `acquire_lock` call; `rc=0` |
| T8 | Each skip path (kill switch, CI, no flock, no lib, no `acquire_lock`) | the existing LOCK_WAITING-absent arms stay green AND `*.queue.d` gains no entry — asserted by counting dir entries |
| T9 | Queued waiter across `waited ≥ timeout_s` | heartbeat beats carry `position=2`; post-budget beats use `LOCK_WAIT_OVERRUN`; self-terminate fires at the combined budget |
| T10 | Mutation controls: `_tc_queue_wait` returns 0 unconditionally; probe direction `>` ; third-waiter arm with gap-numbered tickets | each mutation drives the named arm RED (Guard 1 matrix rows 1–6) |
| T11 | Mint sweep | an unlocked ticket older than the ceiling is removed under `.alloc`; a held ticket of any age is never removed; `max+1` never regresses below a live ticket |
| T12 | Regression: existing Phase-3 arms (free/contended/CI/kill-switch/noflock/degraded-timing) | all still green — byte-identical `LOCK_WAITING`, `LOCK_ACQUIRED`, `LOCK_CONTENDED_PROCEEDING` texts |

## Success Metrics

- Under a synthetic >`TC_LOCK_TIMEOUT` hold, N queued waiters produce **serialized** proceed lines —
  never two `LOCK_CONTENDED_PROCEEDING`/`LOCK_ACQUIRED` events in flight simultaneously without a
  `queue_timeout=1` escape.
- The contention suite stays deterministic: ordering asserted by ticket probes and held-alive
  shells, zero wall-clock-guess sleeps in the new arms.
- Heartbeat cost stays O(1) per beat (a readdir + `flock -n` probes), not the ~6 s `/proc` walk the
  holder-naming draft cost.

## Dependencies & Risks

**Precedent diff (deepen-plan 4.4 — lock-acquisition pattern).** Canonical form lives in
`_acquire_lock_impl` (`session-state.sh`): `exec {fd}>>"$file"` → `flock -w` → track fd in an assoc
array → release by fd close. The ticket code mirrors it with two deliberate, recorded deviations:
(1) probes use `flock -n` (never `-w`) because #7697 measured `-w` not firing under a masked
SIGALRM; (2) the fd is held in a plain scalar (`_TC_TICKET_FD`), not `_SESSION_LOCK_FDS`, because
tickets are a `tc_acquire`-local concern and session-state.sh is unmodified per ADR-133's "reuse
the primitive, don't modify the shared one." Sibling flock users surveyed:
`tmpfs-guard.sh`, `raise-tmp-tmpfs-ceiling.sh`, `rule-metrics-aggregate.sh`, `cutover-inngest.sh` —
none implement queueing; no second implementation is being created.

**R1 — the queue adds a failure mode the lock never had (directory state).** Mitigation: every
queue failure arm degrades to the pre-queue acquire path with a named line (AC5); the queue cannot
wedge a run because every bounded wait still ends in proceed.

**R2 — the queue wait charges against the 14,400 s ceiling.** A run queued past its ceiling exits 3
(UNRESOLVED) having run nothing — vs. today's contended-but-completed run. Accepted: that is the
honest serialization cost, bounded by `TC_QUEUE_TIMEOUT`, and the ceiling's own ADR-133 arithmetic
gets corrected in the Phase-3 addendum.

**R3 — mixed-version fleet.** A worktree on pre-queue code ignores tickets; its waiters contend as
today and a new-code holder's ticket does not block them. Degrades to status quo, never worse.

**R4 — `.alloc` hold leaks.** A `kill -9` inside the mint critical section releases `.alloc`
automatically (flock is fd-bound); no wedged-alloc state is reachable — the same argument ADR-133
uses for the main lock, now applied one level down.

**R5 — heartbeat subshell probes diverge from the main loop's.** `position=` is advisory
instrumentation, not a control input; a stale or divergent reading changes a log line, never a
decision.

## Files to Edit

- `scripts/lib/test-contention.sh` — the ticket machinery + `tc_acquire` restructure + heartbeat
  extension (the only product-code file).
- `scripts/test-contention.test.sh` — Phase-3b arms (T1–T12) with per-arm mutation controls.
- `plugins/soleur/skills/work/SKILL.md` — queue-position semantics in the two contention paragraphs.
- `knowledge-base/engineering/architecture/decisions/ADR-133-…md` — dated addendum.

## Files to Create

None. The ticket directory is runtime state under the existing session-state lock root, not a
source artifact.

## Research Insights

**Premise Validation** — see the section of that name; all cited issues/files verified live
2026-09-22.

**Property List** (the ask restated; Phase 0.6b):

- P1 — on lock-budget expiry under a long hold, waiters release **one at a time**, not all at once.
- P2 — releases follow a bounded FIFO (mint order), not whatever order `-w` timers happen to fire.
- P3 — every wait path still ends in proceed-with-banner; nothing aborts (ADR-133 Decision 3).
- P4 — a queued run (and a log reader) can see its position and an overrun signal — the
  detected-long-hold candidate from the issue.
- P5 — no new lock primitive and no edit to the shared `session-state.sh` (ADR-133 constraint).

**Mechanism mapping:** FIFO ticket queue → P1, P2 (nothing on main provides it — grepped
`fifo|ticket|queue` across `scripts/lib/` and `plugins/soleur/scripts/lib/`, zero hits);
overrun/position beat → P4 (the existing heartbeat covers `waited=` but no overrun token and no
position); gate-cost reduction → covers none of P1–P3 → **cut** (tracked by #8329/#7454 item 1).

**Cut List:** abort-on-timeout (ADR-133 rejected), stale-holder/-ticket detection (dead code —
kernel release measured), tail-chain lock (A2 — serializes entry not exit), pid-liveness queue
(A3 — #5454 footgun), gate-cost reduction (A6 — out of scope).

**Institutional learnings applied:** `2026-08-19-the-budget-was-shorter-than-the-thing-it-was-waiting-for.md`
(budget < hold time = scheduled simultaneous release — the property this fix removes, not extends);
`2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` (harness rows
in Guard 1); `work/SKILL.md` authoring constraints (no `producer | grep -q` under pipefail, `|| true`
in substitutions, `cases` incremented at call sites); #7697 (no new `flock -w`).

## Sharp Edges

- **The ticket fd must outlive `tc_acquire`.** Closing it on return would re-create the
  simultaneous-release defect one level down — the ticket is held for the *run's* lifetime, exactly
  like `_SESSION_LOCK_FDS["test-all"]`. A "cleanup" that closes it early is the mutation Guard 1
  row 1 is built to catch.
- **`flock -w` is not a timeout guarantee here.** #7697 measured waiters parked 4.6 days in
  `locks_lock_inode_wait` (masked-SIGALRM hypothesis). Every new wait in this change is either a
  `flock -n` probe or a counted-retry loop — no new alarm-dependent wait exists.
- **Created-but-unlocked tickets are the only real race.** Mint (create + flock) and head-check
  (scan + probe) must both run inside the `.alloc` critical section; moving either half out opens
  the window Guard 1 row 4 pins.
- **`grep -c` returns 1 on zero matches** — every new count in the lib carries `|| true`, same as
  the `sibs_now` re-sample whose comment explains why.
- **Do not name the holder.** ADR-133 measured `/proc`-walk holder identification at ~83% wrong;
  `position=` and ticket-file contents are exact, `--capacity` answers "who is running."
- **Suite-harness anchors.** Four suites pin `tc_acquire "test-all"` verbatim and the contention
  suite pins `LOCK_WAITING` placement/absence across every skip path — the change stays inside the
  function body and emits new tokens only on the engaged path.

## References & Research

- Issue: #8579 (OPEN, `meta/machinery`); sibling evidence run: worktree `#8586` session held the
  lock ~8,070 s on 2026-09-22.
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-133-test-all-tmpfs-contention-managed-resource-and-advisory-lock.md`
  (Decision 3; Alternatives rejections; 2026-08-11 / 2026-08-12 / 2026-08-19 / 2026-09-06 addenda).
- Code: `scripts/lib/test-contention.sh:942-1074` (`tc_acquire`), `:835-870` (advisory-queue
  rationale), `plugins/soleur/scripts/lib/session-state.sh` (`_acquire_lock_impl`, `acquire_lock`,
  `_session_state_init_dirs`, `LOCK_DIR`), `scripts/test-all.sh:1434` (`_RUN_START_EPOCH`),
  `:1551` (`tc_acquire "test-all"`).
- Related: #7545 (budget raise + heartbeat), #7869 (runtime ceiling), #7697 (OPEN — `flock -w` may
  not fire), #7454 item 3 (decline evidence bar — untouched), #8231 (suite parallelism — orthogonal),
  #8329/#8322 (gate-cost work — the candidate direction cut here).
- Learning: `knowledge-base/project/learnings/2026-08-19-the-budget-was-shorter-than-the-thing-it-was-waiting-for.md`.

## Enhancement Summary (deepen-plan pass, 2026-09-22)

**Sections enhanced:** Premise Validation (issue-state re-verification incl. #7697, #7454, #7537);
Research Reconciliation (R2 stub-shape, R3 AC14 pin, R5 LOCK_WAITING absence-arms, R6 triage-grep
anchor, R7 ceiling arithmetic); Guard Contract (reorder + window-internal rows per the order/
lifetime rule); Risks (precedent diff vs `_acquire_lock_impl` and sibling flock users; #7697
motivation for `flock -n`-only probing); Test Scenarios (queue-timeout and degrade arms).

**Verify-the-negative results (all run against the worktree, 2026-09-22):**

- "No existing ticket/FIFO machinery" — `grep -rn 'fifo\|ticket' scripts/lib/test-contention.sh
  plugins/soleur/scripts/lib/session-state.sh` → zero hits. **CONFIRMS.**
- "`flock -w` only in `_acquire_lock_impl`" — the queue path adds `flock -n` + counted retry only;
  AC9 pins it. **CONFIRMS** (by construction).
- "Stubbed session-state reaches tc_acquire" — `test-all-capacity-signal.test.sh` injects a stub
  defining only `acquire_lock`; `_session_state_init_dirs`/`LOCK_DIR` are unset there → degrade
  path required and T7 covers it. **CONFIRMS.**
- "AC14 pins `TC_LOCK_TIMEOUT` default > 2700 s" — `test-all-capacity-signal.test.sh:1073-1079`.
  **CONFIRMS** → the default is untouched.
- "Triage grep keys on `LOCK_CONTENDED`" — `work/SKILL.md` §"`rc` is the verdict". **CONFIRMS** →
  queue-timeout path still emits `LOCK_CONTENDED_PROCEEDING`.
- "No `LOCK_QUEUE_`/`TC_QUEUE_`/`LOCK_WAIT_OVERRUN` token collisions" — repo-wide grep zero hits.
  **CONFIRMS.**

**New considerations discovered:** #7697 (OPEN) makes `flock -w` unreliable as a timeout under a
masked SIGALRM — the design now bans new `-w` waits outright rather than trusting them; the
`_RUN_START_EPOCH` stamp before `tc_acquire` means the runtime ceiling already bounds a queued
run's total lifetime (ADR addendum must restate that arithmetic); mixed-version worktrees degrade
to today's behaviour rather than deadlocking.
