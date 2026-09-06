---
title: "A dying session leaves a full test-all holding the repo-global lock forever; nothing detects it"
date: 2026-09-06
slug: fix-test-all-lock-orphan-holder
branch: feat-one-shot-7869-test-all-lock-orphan-holder
issue: 7869
closes: 7869
lane: cross-domain
type: bug-fix
brand_survival_threshold: none
---

## Overview

When the session that launched a full `scripts/test-all.sh` run goes away, the run
survives it. The kernel reparents the process tree, the run keeps working through
its suite list, and it keeps the repo-global advisory lock the whole time. Nothing
in the current contention layer asks whether the process holding that lock still
has a session that will ever read its output, so every later run on the machine
queues behind work that no longer has a consumer.

Two small changes, neither of which needs to know who owns anything. **First**, the
sibling walk the runner already performs carries each sibling's measured elapsed
time, so a run past a wall-clock ceiling is excluded from the count that refuses new
full-gate runs — capacity comes back immediately, and nothing is killed. **Second**,
a run that has itself been executing past that ceiling terminates its own
descendants and exits, saying why.

There is deliberately **no ownership discriminator**. Plan review established that
every available one resolves, on this box's topology, to a process that outlives the
session — so it could never fire. A wall-clock bound needs no discriminator, and it
is the same resolution this repo already reached for leases after a pid-liveness
read deleted two live worktrees (#5454): the time bound is the authority.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Research Insights

### Premise Validation (Phase 0.6)

Every claim the issue makes about existing protections was checked against the authority
rather than accepted. Three of the four did not survive.

| Issue claim | Verdict | Evidence |
|---|---|---|
| "The lock's own `-w 3600` does not bound the wait." | **REFUTED** | Measured. A waiter using the exact `_acquire_lock_impl` shape (`exec {fd}>>`, then `flock -w`) against a *live* 20 s holder returned `rc=1` after exactly 3 s with `-w 3`. `flock` from util-linux 2.41.3. The probe also confirms `{fd}` auto-assigns **fd 10**, which is what makes the issue's observed `flock -w 3600 -x 10` identifiable as `session-state.sh::_acquire_lock_impl` and not some other call site. |
| "Whatever the retry structure is, the practical behaviour is an unbounded wait." | **REFUTED** | `tc_acquire` (`scripts/lib/test-contention.sh`, find it at `LOCK_CONTENDED_PROCEEDING`) is advisory by construction: on timeout it prints a banner and `return 0` — it **proceeds**, never blocks further and never aborts. ADR-133 Decision 3 pins this as the load-bearing safety property. No waiter can be wedged by the lock. |
| "`SOLEUR_ALLOW_FULL_GATE` / the refusal path says nothing about a holder that has since been orphaned." | **CONFIRMED, and worse than stated** | The sibling refusal (`scripts/test-all.sh`, the `refusing a full-gate run` block) fires on a count `tc_preamble` *measures* from `/proc`. An orphaned run is still a running `test-all.sh`, so it is counted as a live sibling and every subsequent full-gate run is **refused with exit 4** — not queued. The symptom is stronger than the issue's "queues behind": the machine's full-gate capacity is held at zero by a run with no consumer. |
| "The contention preamble … is silent about 'the current holder has no owning session'." | **CONFIRMED** | `tc_epilogue` prints tmp-entry deltas, `used%` and `availMB`. Neither preamble nor epilogue carries any ownership fact, and `_tc_wait_heartbeat` deliberately carries only *which lock* and *how long this run has waited*. |

**Refinement on the refusal path, found while checking the above.** `lefthook.yml`'s `bun-test`
step sets `SOLEUR_ALLOW_FULL_GATE=1` deliberately (#7553), so a pre-commit run **bypasses** the
sibling refusal and takes the lock path instead of exiting 4. That is why the issue's blocked
`git commit` queued rather than being refused, and it means the two symptoms coexist by design:
ordinary full-gate runs are refused, pre-commit runs queue.

**Own-capability claims verified before use** (`hr-verify-repo-capability-claim-before-assert`):
the issue's "nothing detects it" is false as a universal. `scripts/orphan-process-reaper.sh`
(#7537) exists, is 54 KB, and is **already wired into the runner** — `scripts/test-all.sh` runs
`timeout 10 bash scripts/orphan-process-reaper.sh report` at suite launch on every non-CI run.
Its `reap` verb is deliberately *not* auto-invoked; `scripts/orphan-process-reaper.test.sh`
asserts that count stays zero, which is what preserves the consent boundary on destruction.

### Why the existing reaper does not fire on this orphan

The reaper anchors a pid only under a seven-gate conjunction, and every gate fails toward
*alive*. Two of them are the reason #7869's orphan survives it:

- **G2 — cwd genuinely unlinked** (`st_nlink == 0`). The #7869 orphan's cwd was
  `/var/tmp/ship7791/`, which still existed.
- **G3 — the running script, anchored via `fd/255`, is an unlinked regular file.**
  `scripts/test-all.sh` was still linked.

So the reaper is not broken and is not missing a caller. It answers *"has this process's work
been unlinked out from under it?"* — a genuinely different question from *"does this process
still have a session that will read its output?"*. The #7869 orphan is `cwd intact, script
intact, owner gone`, which no gate in the conjunction observes.

**Design constraint inherited from that file, and load-bearing here.** Its header states that
`exe` is never consulted *at all*, because reading it "would make this a polarity discipline
instead of a structural property." A discriminator that string-matches `claude` in the ancestor
chain — which is what the issue's fix direction #2 proposes — is exactly that polarity
discipline. Any remedy must be structural or it does not belong in this codebase.

### The ADR-133 gap

`ADR-133 § Alternatives Considered` REJECTS the issue's fix direction #1/#2 verbatim:

> **Implement stale-holder detection on the lock.** REJECTED as dead code. `flock` is
> kernel-managed and inode-bound, released automatically once the last fd holder dies …
> a "dead pid still holds the lock" state is unreachable with real `flock`.

That rejection is **correct and stays correct** — re-measured above. But it quantifies over a
*dead* holder. #7869's holder is **alive**: it is still executing suites, so `flock` is holding
the lock exactly as designed. The ADR's reasoning does not reach a live-but-ownerless holder,
and no other decision in the corpus does either. This is a gap the ADR left, not a decision it
made, which is why this plan amends ADR-133 rather than reversing it.

### Precedent diff — the pid-liveness trap this repo has already paid for

`plugins/soleur/scripts/lib/session-state.sh::is_lease_active` is the closest precedent to the
proposed design, and it **deliberately refuses** the mechanism this plan's first draft reached
for. Its body carries the reason in full:

> NO `kill -0 "$lease_pid" || return 1` HERE — that line reaped two live worktrees on
> 2026-08-06 (#5454), and it could never have worked.

The mechanics: `acquire_lease` records `pid=$$`, but every documented entry point is a
short-lived CLI `bash` that exits milliseconds after writing the file. So the liveness gate
reported INACTIVE for every CLI-acquired lease the instant it was taken, `cleanup-merged` removed
the worktree, **deleted the branch locally and on origin, and closed the PR**.

Two lessons, both binding on this plan:

1. **The operand was wrong, not the predicate.** The recorded pid was the pid of *the process
   that wrote the record*, which is not the owning session. Any owner record here must resolve
   the **owner**, never `$$` of the run — and must be able to say when it could not resolve one.
2. **The failure direction is the same dangerous one.** For leases, "pid looks dead" led to
   destruction. Here, "owner looks gone" ends a run that may be doing real work. So this plan
   adopts the resolution `is_lease_active` and `sweep_orphan_leases` converged on rather than
   re-deriving it: **a time bound is the authority, and pid-death is never sufficient on its
   own.** `sweep_orphan_leases` states the shape explicitly — it deletes on
   `mtime > 24h, OR (pid dead AND same host AND past its own window)`.

**Applied here, this is the argument for dropping ownership entirely.** An earlier draft of this
plan proposed an owner record plus an ancestry walk, with the time bound as one conjunct among
four. Plan review showed the ownership conjuncts could never fire (the discriminator resolves to
the terminal emulator, which outlives the session), which leaves the time bound doing all the
work — exactly what `is_lease_active` concluded for leases. So the design keeps the authority and
drops the conjuncts that were only ever decoration. The reaper's "any error reading any gate
leaves the process UNFLAGGED AND ALIVE" discipline is inherited as the fail-toward-alive rule on
the elapsed reading.

### Property List (Phase 0.6b)

- **P1** — The machine's full-gate capacity is not held at zero by a run nobody is reading.
- **P2** — A run's own lifetime is bounded, so no run can hold the repo-global lock indefinitely.
- **P3** — The next occurrence self-reports, instead of requiring a manual ancestry walk.
- ~~**P4** — never leave a partial `all.log` with no `all.rc`.~~ **WITHDRAWN — the premise is
  false.** The issue asserts this artifact pair; `git grep 'all\.rc'` over the worktree returns
  **zero** occurrences repo-wide, and `all.log` appears only in one learning file referring to a
  developer's ad-hoc `/tmp/test-all.log` redirect. There is no producer, no path, no format and no
  consumer, so there is nothing to leave partial. Recorded rather than silently dropped, because
  an earlier draft of this plan carried P4 for several revisions on the strength of the issue text
  alone. See `## Session Errors`.

### Cut List (Phase 0.6b)

| Proposed mechanism | Property it would buy | What already buys it → disposition |
|---|---|---|
| "Make the wait bounded in fact, not just in the `-w` argument." | P2 (waiter side) | `flock -w` already bounds it (measured, 3 s against a live holder), and `tc_acquire` proceeds rather than waiting again. **CUT** — defends a state that does not occur. |
| "Before waiting, and periodically while waiting, walk the holder's ancestry." | — | **CUT.** `_tc_wait_heartbeat`'s header records that per-beat `/proc` walking was already tried and removed: ~6 s and ~2,850 forks per beat (~313 CPU-seconds, ~154,000 process creations per waiter over a 3600 s wait) *on a box whose failure mode is fork/exec starvation*, and it named a fellow **waiter** ~83 % of the time. |
| "Either break the lock." | P2 | **CUT — not implementable.** An advisory `flock` held by a live process cannot be broken from outside. |
| "…or tell the operator exactly which PID to reap." | P1 | **CUT** — forbidden by `hr-never-label-any-step-as-manual-without`. |
| A new orphan-detection mechanism / a new lock primitive. | P1, P3 | **CUT** — `scripts/orphan-process-reaper.sh` already exists and is already invoked from `test-all.sh` at suite launch. |
| **An owner record + one-time ancestry walk + `/proc` starttime pin + same-host term + `SOLEUR_TEST_ALL_OWNER_PID` seam.** | P2 | **CUT at plan review — the discriminator is vacuous by construction.** "Top ancestor below the init/subreaper boundary" resolves, on this box's documented topology (`hr-the-host-terminal-is-warp`), to the **terminal emulator** — which survives session death. A healthy run and an orphaned run resolve to the *same* owner, so the guard could never fire. Two runs from one terminal are also indistinguishable. A wall-clock ceiling buys P2 with no discriminator at all. |
| **A new anchor class in the orphan reaper (former Guard 2 / Phase 4).** | P3 | **CUT.** Its `report` path is deliberately non-acting (`reap` is never auto-invoked, and this plan's own criterion pinned that), so it would buy P3 only — and P3 is already bought by the self-terminate marker on stderr. A second detector for a condition that now terminates itself is not worth edits to two 1,500-line suites. |

What survives: **P1 via a stale-sibling filter on the refusal count**, and **P2/P3 via a wall-clock
ceiling in the runner**. Both are small, and neither needs to know who owns anything.

### Value-Proposition Measurement (Phase 0.6c)

One orphan held capacity for **1d22h** having completed 72 of 369 suites; a second appeared ~1 h
later, so the class recurs within a day. The replacement worst case is `ceiling + one suite
duration` (see the calibration below), i.e. **46 h → under 5 h**, and the capacity half is restored
immediately rather than after the ceiling elapses.

### Institutional learnings applied

- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — the
  mutation matrix is derived from the design and includes a reorder row, because the property is
  about a window rather than a value at exit.
- `2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md` — the
  hypothesis table carries an explicit UNKNOWN rather than a reasoned verdict.
- `2026-07-30-one-blocked-mechanism-is-not-a-blocked-capability.md` — "nothing detects it" was
  enumerated as a universal negative; the reaper was found.

### Conventions carried from AGENTS.md

`hr-never-label-any-step-as-manual-without`, `hr-verify-repo-capability-claim-before-assert`,
`cq-assert-anchor-not-bare-token` (the runner's splice-window fixtures key on substrings in
`test-all.sh`, so no new comment may quote an anchor verbatim), `cq-write-failing-tests-before`,
`cq-ac-must-not-depend-on-concurrent-sessions`.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "`flock -w 3600` does not bound the wait." | It bounds it. Measured rc=1 at the timeout against a live holder. | Drop all waiter-side work. |
| "Nothing detects it." | `orphan-process-reaper.sh` detects a *different* orphan class and is already wired in. | Neither extend nor duplicate it — bound the holder instead. |
| "Record the holder's PID … walk the holder's ancestry." | Per-beat walking was already removed for measured cost and ~83 % misattribution; and the ancestry discriminator resolves to the terminal emulator, which outlives the session. | Cut entirely; use a wall-clock ceiling. |
| "Break the lock." | Not possible against a live holder. | Bound the holder's lifetime. |
| "Cleanup must not leave a partial `all.log` with no `all.rc`." | **Neither artifact exists** — zero repo-wide occurrences. | P4 withdrawn. |
| "Every other run queues behind it." | Full-gate runs are **refused with exit 4**; only the `SOLEUR_ALLOW_FULL_GATE=1` pre-commit path queues. | Correct the framing; the capacity fix targets the refusal count. |

## Hypotheses

The Phase 1.4 network-outage gate matched on the substring `timeout`, but this is a process- and
lock-lifetime defect with no network, DNS or SSH surface; the L3→L7 firewall-first checklist is
inapplicable and is recorded as such rather than skipped silently.

| # | Hypothesis | Verdict | Basis |
|---|---|---|---|
| H1 | `flock -w` fails to bound the wait. | **REFUTED** | Direct measurement against a live holder. |
| H2 | The orphaned **holder** has no lifetime bound. | **CONFIRMED** | No watchdog or self-terminate exists in `test-all.sh`; the only budgeted self-terminate is `_tc_wait_heartbeat`'s own, which bounds the heartbeat, not the run. |
| H3 | The blocked `git commit` observed at 46 h was continuously inside one `flock` call. | **UNKNOWN — not resolvable from the repo.** | The deciding datum is that process's start time and stderr, both discarded. No fix here depends on the answer. |
| H4 | The orphan also suppresses siblings via the refusal count, not only via the lock. | **CONFIRMED by code read** | The refusal binds to `tc_preamble`'s measured `/proc` count, which does not distinguish a fresh run from a 46-hour one. |

## User-Brand Impact

**If this lands broken, the user experiences:** a `git commit` or ship run terminated part-way with
no explanation, or refused with "refusing a full-gate run" naming a worktree they are not working
in — on a machine where nothing is progressing.

**If this leaks, the user's data is exposed via:** no new exposure vector. The change reads `/proc`
entries for the invoking uid only and writes no new persistent artifact.

**Brand-survival threshold:** `none`.

`threshold: none, reason: the change is confined to developer-machine process lifetime and an
in-memory sibling count, touching no schema, auth flow, API route, or persisted user data.`

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-133**, in two sentences rather than a new decision record:

1. The existing "Implement stale-holder detection on the lock" rejection **stands** and was
   re-measured — `flock -w` bounds the wait, and a dead holder cannot hold the lock.
2. It does not quantify over a **live but ownerless** holder; that case is bounded by the holder's
   own runtime ceiling, not by any inspection of who owns it — because every available ownership
   discriminator on this topology resolves to a process that outlives the session.

### ADR-181 (exit contract)

The runner's exit-code contract block is widened so code **3** covers a run that terminated
itself, not only a run with `>= 1` killed suite. This is a comment/contract amendment in
`scripts/test-all.sh` shipped in this PR — not a new code, and not a change to
`suite_exit_class`, whose byte-identical parity across two files is pinned by a dedicated suite.

### C4 views

**No C4 impact.** Checked all three model files —
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — against each
class the completeness mandate requires: **(a) external human actors** — none; **(b) external
systems / vendors** — none; **(c) containers / data stores** — none, and this revision removes the
one new artifact the earlier draft would have written; **(d) actor↔surface access relationships** —
unchanged. The C4 model describes the deployed web platform; `scripts/test-all.sh` is developer
tooling the model does not represent.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_TEST_ALL_RUNTIME_CEILING emitted when a run exceeds its wall-clock ceiling and
        terminates, carrying run pid, elapsed seconds, and the ceiling it crossed.
  cadence: at most once per run, on the terminating path only.
  alert_target: run stderr, in the existing [contention] banner family, and the Better Stack
        SOLEUR_* marker family already mirrored by the server-side telemetry hook.
  configured_in: scripts/test-all.sh.
error_reporting:
  destination: stderr, as a named banner alongside LOCK_ACQUIRED / LOCK_CONTENDED_PROCEEDING.
  fail_loud: true — the terminating path prints elapsed and the ceiling before exiting, and the
        stale-sibling filter prints how many siblings it excluded and why.
failure_modes:
  - mode: A run outlives its owning session and holds the repo-global lock.
    detection: the run's own elapsed-time check between suites (in-surface — the run observes
        its own runtime, not a host-side gate inferring it).
    alert_route: SOLEUR_TEST_ALL_RUNTIME_CEILING on stderr, with elapsed and ceiling.
  - mode: A stale run holds full-gate capacity at zero via the sibling-refusal count.
    detection: tc_preamble already measures each sibling's elapsed_s; siblings past the ceiling
        are excluded from the count and reported.
    alert_route: SOLEUR_TEST_ALL_STALE_SIBLING_EXCLUDED, naming pid and elapsed.
  - mode: The elapsed reading is unavailable (unreadable /proc, missing clock).
    detection: the ceiling check cannot evaluate and is skipped.
    alert_route: SOLEUR_TEST_ALL_CEILING_UNAVAILABLE; the run continues, never terminated on an
        unreadable operand.
logs:
  where: the invoking run's own stdout/stderr and TEST_TIMING_LOG; no new sink.
  retention: unchanged — as long as the invoking session's transcript.
discoverability_test:
  command: bash scripts/test-all-runtime-ceiling.test.sh
  expected_output: "=== test-all-runtime-ceiling: N passed, 0 failed ==="
```

## Guard Contract

### Guard 1 — runtime ceiling

**Property.** A `test-all.sh` run that has been executing longer than its wall-clock ceiling
terminates its own descendants and exits, saying why — checked between **every** suite, not once
at startup. The reading fails toward *keep running*.

**Assembly.** The body of `run_suite` in `scripts/test-all.sh`. Stated structurally because the
member list is a trap: there is **no dispatch loop** — `run_suite` is defined once and invoked
**194 times serially**, so a check "in the loop" has nowhere to live and a per-call-site check
would have 194 members that drift on the next suite added. The property quantifies over every
*invocation*, which is why the single function body is the only expressible chokepoint.

**Ceiling calibration — the numbers, because a relaxed ceiling kills real work.** The uncontended
full gate is ~2,700 s (ADR-133), but the same source records siblings legitimately holding for
**3,775 / 5,787 / 5,763 s** under contention, and the slowest single declared suite budget is
**2,500,000 ms (~41.7 min)**. So a ceiling sized on the uncontended figure would terminate healthy
contended runs. The ceiling is set at **4 h (14,400 s)** — ~2.5× the worst observed legitimate
hold and ~11.5× below the 46 h pathology — and is overridable by an environment seam. Worst-case
detection latency is `ceiling + one suite duration` (~41.7 min), so the honest claim is **under
5 h**, not "minutes".

**Mutation matrix** (each row MUST drive the guard RED):

| # | Mutation | Why it must redden |
|---|---|---|
| M1 | Hoist the ceiling check out of `run_suite`'s body to the top of the script. | **Reorder, not delete.** The property is about a window — the ceiling is crossed *mid-run*. A delete-only battery passes here, because a startup check still exists and still runs. This is the row the guard exists for. |
| M2 | Make the elapsed comparison always read "under the ceiling". | A guard that never fires is vacuous. |
| M3 | Terminate via a process **group** signal instead of enumerating descendants. | `orphan-process-reaper.sh` mandates "TERM only, one pid at a time, never to a process group", and `test-all.sh` never calls `setsid` — so under `lefthook.yml`'s `bun-test` the inherited pgid is git/lefthook's and a group TERM kills the operator's in-flight commit. |
| M4 | Replace descendant teardown with a bare `exit`. | **MEASURED:** a bare exit releases nothing. `_acquire_lock_impl` opens the lock via `exec {fd}>>`, bash sets no CLOEXEC, and `flock` binds to the open file description — a still-running suite child holds the lock after the parent exits (`LOCK_STILL_HELD_BY_CHILD=yes`). |
| M5 | Emit the marker *after* teardown rather than before. | Teardown can end the process before it speaks; the run must say why while it still can. |
| M6 | Make an unreadable elapsed reading terminate the run. | Every term fails toward keep-running; an unreadable operand must never end a run (#5454's direction). |
| M7 | Have the guard's own dispatch report zero checked runs and exit 0. | Anti-vacuity: "0 checked" must not pass. |

**Harness rows** (mutations to the SUITE, not the guard):

| # | Mutation | Why it must redden |
|---|---|---|
| H1 | Replace the suite's success condition with `fail == 0` while no case runs. | A suite that exits 0 on `0 passed, 0 failed` certifies nothing. |
| H2 | Derive every RED fixture from one canonical elapsed value. | RED rows from a single canonical input cannot see a guard that rejects everything. |
| H3 (must-PASS) | A run whose elapsed is *just under* the ceiling, with a different pid and a different suite count from the canonical fixture. | Permitted variation the contract explicitly allows — the row that detects a guard rejecting everything. |

### Guard 2 — stale-sibling exclusion

**Property.** A sibling whose measured `elapsed_s` exceeds the ceiling is excluded from
`TC_SIBLING_RUN_COUNT` before the full-gate refusal consults it, and the exclusion is reported —
so a stale run cannot hold the machine's full-gate capacity at zero. Fresh siblings still refuse.

**Assembly.** The count derivation in `scripts/lib/test-contention.sh` that promotes
`TC_SIBLING_RUN_COUNT` from the `_tc_scan_procs` rows (which already carry `elapsed_s` — the walk
is free and no second walk is added), plus the refusal predicate in `scripts/test-all.sh` that
reads it. Both, because a filter applied at one and not the other is the drift this contract
exists to catch.

**Mutation matrix:**

| # | Mutation | Why it must redden |
|---|---|---|
| M8 | Remove the elapsed filter, restoring the raw count. | The capacity property is lost. |
| M9 | Filter on the wrong comparison direction (exclude *fresh* siblings). | The refusal would fire only for stale runs — inverted. |
| M10 | Apply the filter to the count but not to the reported sibling list. | The operator would read a list that disagrees with the verdict. |
| M11 | Make a sibling with an unreadable `elapsed_s` be excluded. | An unreadable reading must fail toward *counting* it, i.e. toward refusing — the conservative direction for a capacity gate. |
| M12 | Add a second stale sibling after a compliant first. | A filter that stops after the first member is the defect class. |

**Harness rows:**

| # | Mutation | Why it must redden |
|---|---|---|
| H4 | Point the fixture's synthetic procfs at zero siblings. | With no siblings the assertions are vacuous; the suite must fail rather than pass empty. |
| H5 (must-PASS) | One fresh sibling and one stale sibling together. | The refusal must still fire on the fresh one — the row proving the filter did not disable the gate. |

## Open Code-Review Overlap

**None.** Queried all open `code-review`-labelled issues and matched their bodies against every
path in the Files lists below (`scripts/test-all.sh`, `scripts/lib/test-contention.sh`) — zero
matches.

## Files to Edit

- `scripts/lib/test-contention.sh` — the stale-sibling filter on the count promotion, plus the
  ceiling constant and its environment seam.
- `scripts/test-all.sh` — the ceiling check in `run_suite`'s body; the terminating path; suite
  registration.
- `scripts/test-contention.test.sh` — Guard 2 arms (M8–M12, H4–H5).
- `scripts/test-all-killed-classification.test.sh`, `scripts/test-all-capacity-signal.test.sh` —
  both splice a fixture body between the acquire and epilogue anchors and **neuter the acquire**.
  Any variable the ceiling check reads must therefore be initialised at **top level, before that
  window**, or the sandbox aborts under `set -u` on a suite this branch does not otherwise touch —
  a regression the runner's own comments record as having cost three arms red once already.
- `scripts/suite-exit-class-parity.test.sh` — consulted, not necessarily edited: it pins
  `suite_exit_class` byte-identical across two files, so no new class term may be introduced.
- `knowledge-base/engineering/architecture/decisions/ADR-133-test-all-tmpfs-contention-managed-resource-and-advisory-lock.md` — the two-sentence amendment.

## Files to Create

- `scripts/test-all-runtime-ceiling.test.sh` — Guard 1's suite (M1–M7, H1–H3).

## Alternative considered — fix the inherited fd instead of sweeping descendants

The lock fd is inherited because `_acquire_lock_impl` opens it with `exec {fd}>>` and bash sets no
CLOEXEC. Marking it close-on-exec would make a bare parent exit release the lock, removing the
need for any teardown. **Rejected**, for two reasons. It changes lock semantics in
`plugins/soleur/scripts/lib/session-state.sh`, which ships to customers' self-hosted CLIs
(ADR-178), for every consumer of the primitive rather than for this one caller. And it would
release the *lock* while leaving the suite children *running* — so the capacity property (P1) and
the CPU cost would both survive. Recorded rather than left silent, because it is the
lower-blast-radius option for the narrower goal and a future reader will ask.

## Implementation Phases

### Phase 1 — Capacity first (the dominant symptom), RED before GREEN

Write the Guard 2 arms against a synthetic procfs, then add the elapsed filter to the count
promotion and the reporting line. This alone restores full-gate capacity while a stale run is
still executing, and it kills nothing — so it carries no consent boundary and no teardown risk.

### Phase 2 — Guard 1 suite (RED before GREEN)

Write `scripts/test-all-runtime-ceiling.test.sh` with M1–M7 and H1–H3 **before** the check exists
(`cq-write-failing-tests-before`), derived from the design rather than from the implementation's
eventual shape.

### Phase 3 — The ceiling (GREEN)

The elapsed check in `run_suite`'s body. On crossing: emit `SOLEUR_TEST_ALL_RUNTIME_CEILING`
**first**, then terminate descendants **one pid at a time, never as a process group** (the rule
`orphan-process-reaper.sh` states and the reason `test-all.sh`'s inherited pgid makes it
mandatory), then exit **3**.

**The exit-code contract text must be amended, and the earlier claim that it need not be was
wrong.** `scripts/test-all.sh`'s contract block defines 3 as *"0 failures and >= 1 suite
KILLED"*; a self-terminated run has **zero** killed suites and a few hundred never-attempted
ones, so it satisfies the code's spirit (coverage unresolved, not green) but not its stated
antecedent. Reusing 3 is still right — 4 means "nothing ran", which is false, and a new code
would break `suite-exit-class-parity.test.sh`, which pins `suite_exit_class` **byte-identical**
between `scripts/test-all.sh` and `.github/scripts/test/run-all.sh`. So the contract comment is
widened to cover "the run itself was terminated", in this PR.

**The terminating path must also emit the summary line and mark the repo-write boundary
reported.** Exiting from inside `run_suite` otherwise skips the summary block entirely, so the
documented log-reading shape yields nothing, and it leaves `_repo_boundary_reported` at 0, firing
an unrelated repo-write-boundary NOTE that misattributes the cause.

### Phase 4 — ADR-133 amendment and registration

The two-sentence amendment; register the new suite in the runner; run the affected suites.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash scripts/test-all-runtime-ceiling.test.sh` exits 0 and prints
   `=== test-all-runtime-ceiling: N passed, 0 failed ===` with `N >= 10`.
2. Each of M1–M7 applied individually drives Guard 1's suite RED; H1–H2 applied to the suite drive
   it RED; H3 passes unmodified.
3. Each of M8–M12 drives Guard 2's arms RED; H4 drives them RED; H5 passes.
4. `bash scripts/test-contention.test.sh` exits 0.
5. Against a **synthetic procfs** containing one sibling with `elapsed_s` past the ceiling and one
   under it, the refusal still fires (the fresh sibling is counted) and the stale one is excluded
   and named in the report. Fixture-based, so no concurrently-running process on the machine can
   change the result (`cq-ac-must-not-depend-on-concurrent-sessions`).
6. Against a fixture whose elapsed reading is unreadable, the run is **not** terminated and
   `SOLEUR_TEST_ALL_CEILING_UNAVAILABLE` is emitted.
7. A fixture run driven past the ceiling terminates, and a fresh acquirer then obtains the
   advisory lock — asserted with a **live suite child** at termination time, the only arrangement
   in which the inherited-fd defect is observable (M4).
8. The terminating path emits its marker **before** teardown (M5), and exits **3**.
9. `git grep -c 'kill.*-- *-\$\|kill -[A-Z]* *-[0-9]' scripts/test-all.sh` returns 0 — no
   process-group signal is introduced (M3).
10. A fixture run whose elapsed is just under the ceiling completes with no terminating marker.
11. A self-terminate driven under a **real `pre-commit` invocation** leaves `git commit` alive
    and `.git/index.lock` absent — the shape in which the process-group hazard is observable, and
    the one a direct-invocation fixture cannot see.
12. The terminating path emits the summary line, and no spurious repo-write-boundary NOTE
    accompanies it.
13. The exit-code contract comment in `scripts/test-all.sh` covers the self-terminated run, and
    `bash scripts/suite-exit-class-parity.test.sh` exits 0.
14. ADR-133 carries the amendment, and its existing "Implement stale-holder detection" bullet is
    retained rather than deleted.
15. `python3 scripts/lint-guard-contract.py` accepts the `## Guard Contract` section.
16. `bash scripts/test-all-killed-classification.test.sh` and
    `bash scripts/test-all-capacity-signal.test.sh` both exit 0 — the splice-window sandboxes are
    unaffected.

### Post-merge

None. Self-contained developer tooling; no deploy, migration, or provisioning step, and nothing
deferred.

## Session Errors

1. **P4 was carried on an unverified premise for several revisions.** The issue asserts an
   `all.log` / `all.rc` artifact pair. An early `git grep 'all\.rc'` was run from the **bare repo
   root** and failed with `fatal: this operation must be run in a work tree`; that error was not
   noticed and the grep was never re-run, so an empty result stood in for evidence. Re-run from
   the worktree it returns **zero** occurrences repo-wide — the artifact does not exist. Caught at
   plan review. The generalisable rule is the one this repo already states about empty telemetry:
   an empty result is not evidence of absence until the query is known to have run.

## Domain Review

**Domains relevant:** Engineering

Assessed all eight domains. Product, Legal, Finance, Marketing, Sales, Support and Operations are
not relevant: developer tooling on a local machine, with no user-facing surface, no persisted user
data, no vendor, no cost line, no external communication. The mechanical UI-surface override did
not fire — every path in the Files lists is a `scripts/*.sh` file, a test suite, or an ADR.

### Engineering

**Status:** reviewed

**Assessment.** Reviewed twice: a CTO assessment during plan authoring, then a review panel. Every
load-bearing claim from both was verified in-session before being acted on, and two agents
verified claims by independent measurement of their own.

*Folded in from the CTO pass:* a self-`exit` does not release the lock (children inherit the fd;
measured `LOCK_STILL_HELD_BY_CHILD=yes`); `run_suite` is invoked 194 times serially with no
dispatch loop, so the chokepoint and the detection bound both had to be restated; and the
runner's exit contract has named consumers, so no new code may be minted.

*Folded in from the panel — the design was cut roughly in half.* The simplification and
correctness axes fired on the **same scope**, which the consolidation rule says to resolve by
deleting rather than fixing:

- The **owner record, ancestry walk, starttime pin, host term and test seam were cut entirely.**
  The correctness axis showed the discriminator is vacuous by construction — "top ancestor below
  the subreaper boundary" resolves to the terminal emulator on this box's documented topology,
  which outlives the session, so healthy and orphaned runs resolve identically. The simplification
  axis independently reached the same place from cost. A wall-clock ceiling buys the property with
  no discriminator.
- The **reaper anchor class (a whole guard and phase) was cut.** Its report path is
  non-acting by design, so it bought only self-reporting — already bought by the terminating
  run's own marker. Cutting it also dissolved a blast-radius finding: the new class would have had
  to relax the very gate that bounds the reaper's reap set, on the box's highest-cardinality cwd
  inode, where the file's own measurement records twelve live agent sessions under the cap.
- **P4 was withdrawn**: `all.rc`/`all.log` do not exist in this repo. See `## Session Errors`.
- **A capacity fix that was missed entirely** was added as Phase 1: the sibling walk already
  carries each sibling's `elapsed_s`, so excluding stale siblings from the refusal count restores
  full-gate capacity immediately and kills nothing.

*Surviving corrections applied after the cuts:* the exit-3 contract text must be amended (a
self-terminate has zero killed suites, so it does not satisfy the stated antecedent); the
terminating path must emit the summary and mark the repo-write boundary reported; and any variable
the ceiling check reads must be initialised outside the acquire/epilogue splice window that two
sibling suites replace wholesale.

*One reviewer correction of my own.* A reviewer sized the ceiling against the ~2,700 s uncontended
full gate. The same source records siblings legitimately holding **3,775 / 5,787 / 5,763 s** under
contention, so a ceiling on the uncontended figure would terminate healthy work. The ceiling is
set from the observed contended maximum instead, and the calibration numbers are recorded in the
Guard Contract.

**Panel coverage gap, recorded rather than papered over.** Two of five reviewers did not return —
one hit an API timeout, one stalled on the harness watchdog. The simplification axis was still
covered (by the reviewer that did return on that axis) and the correctness axis by two others, so
no axis went unreviewed; but the per-mechanism justification pass specifically did not run, and
`/deepen-plan` is the next opportunity to close it.
