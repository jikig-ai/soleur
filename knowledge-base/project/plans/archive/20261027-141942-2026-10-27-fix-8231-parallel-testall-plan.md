# Plan: Parallelize independent local `test-all.sh` suites safely (#8231)

**Status:** Implemented
**Issue:** #8231 — workflows: parallelize independent local test-all suites safely
**Branch / PR:** `feat-one-shot-8231-parallel-testall` / draft PR #11282
**Precondition:** green baseline #8270 (merged) and its five closed children (#8238, #8250, #8261, #8263, #8266) — treated as a precondition, not redone.

## Context

The local pre-commit hook runs `scripts/test-all.sh --affected --affected-scope=staged` serially behind the repo-global advisory lock (`tc_acquire "test-all"`), while CI executes the same coverage through parallel shards (`test-scripts (N/8)`, `SCRIPTS_SHARD=k/N`). A local full battery is ~680 registrations of serial wall time. This plan adds a measured, opt-in parallel scheduler to the local runner that derives its suite set from the same registration source and preserves every exit/log/reporting contract.

## Design

### Knob

`--jobs=N|auto` flag and `SOLEUR_TEST_JOBS` env (flag wins). Values: `auto`, or a positive integer; anything else exits 2 (malformed input, never a mode guess). `SOLEUR_TEST_SUITE_MEM_MB` (default 512) and `SOLEUR_TEST_JOBS_CAP` (default 8) bound the width formula.

### Default — the explicit, measured choice

**Unset resolves to SERIAL.** Parallel ships opt-in. This is the recorded decision: the archived parallelization plan's pre-registered flip condition (e) required the #7376 interference diagnosis not to have terminated UNKNOWN; that diagnosis is open and out of this change's scope, so the default stays serial and `SOLEUR_TEST_JOBS`/`--jobs` is the opt-in. Flipping the default to `auto` is a one-line follow-up gated on #7376. When parallel IS requested, every unsafe condition degrades to serial with a named `[parallel] serial fallback — reason=<…>` banner — the bounded serial fallback. Precedence order:

1. malformed value → exit 2 (before anything runs)
2. `CI` set → serial (CI shards already isolate the battery)
3. bash < 5.1 → serial (`wait -n -p` unavailable)
4. explicit `jobs=1` → serial, silent
5. `scripts/lib/test-suite-lanes.sh` not sourceable → serial
6. advisory lock not held (skipped, unavailable, or contended) → serial — a run never goes wide without cross-worktree serialization
7. resolved width ≤ 1 → serial
8. capture dir unwritable → serial

Width: `min(nproc, floor(MemAvailable_MB / 512), cap=8)`, clamped down with a `[parallel] NOTE: … clamped` banner when an explicit N exceeds it.

### Lane model — resource-token sets

Every suite carries a token set from `scripts/lib/test-suite-lanes.sh` (data + classifier). Two suites may not be in flight together when their sets intersect; `*` intersects everything and is the drain barrier. An empty set is fully independent.

- **Derived first** (self-correcting): suite file readable → grep for `test-all.sh` (`lock:test-all`), live-repo `git -C $REPO_ROOT <state-changing verb>` (`repo:index`), `xargs -P`/`--max-pool-size` (`cpu:pool`), `_site/` (`artifact:_site`). Unreadable/unmappable → `*` (fail closed per suite, never per run).
- **Override table** for what a grep cannot see — the collision inventory: `scripts/cf-tunnel-liveness-gate-mutations` (`*`, live-worktree TREE_BEFORE/AFTER assertion), `scripts/orphan-process-reaper{,-mutations}` and `scripts/test-all-capacity-signal` (`*`, whole-box /proc observers), `apps/web-platform/infra/run-registered-suites.sh` (`*`, inner `xargs -P min(nproc,6)` pool), the two vitest registrations (`fs:node_modules_vite`, shared node_modules/.vite), `plugins/soleur` + `blog-link-validation` (`artifact:_site`, shared Eleventy output), `scripts/md-to-mrkdwn` (`*`, #6496 wall-clock assertion), and the three new self-SUT suites (`lock:test-all`).

Registration-order launch is preserved (strict FIFO), so ordering between registration-ordered pairs needs no separate `after=` edge — a named simplification, recorded.

### Scheduler shape — dispatch/reap split at the run_suite chokepoint

`run_suite` keeps all of: `_shard_selects`, `--enumerate`/`--print-*` early returns, `suites` increment, affected and runtime-ceiling declines (evaluated at DISPATCH, before the parallel branch). Only the suite body `"$@"` defers: each job gets an index, tokens, and a capture file pair `<idx>.out`/`<idx>.err`. Workers are `( exec "$@" ) >cap.out 2>cap.err &` — the `exec` is load-bearing (a bare subshell would keep the parent's argv and read as a sibling *run* to other worktrees' census). Reap via `wait -n -p` (bash ≥ 5.1, hence the fallback arm). All verdicts render at `_pj_drain` — called after the last registration, before the repo-boundary end-sample — in registration order through `_run_suite_verdict`, the single emitter factored out of `run_suite`'s tail so classification, budget lines, durable-log retention, TEST_TIMING_LOG rows and `=== N/M suites passed ===` are produced by the same code as serial mode.

Per-suite stdout/stderr are captured separately and replayed onto the fd the suite wrote — no interleaving, no marker-forgery channel. `[run] <label> started/done (rc=N)` stderr pairs give in-flight liveness. `tmp_delta=unattributed` records when a window intersected a sibling's (AP-021: report only what was measured); barrier (`*`) suites keep numeric deltas.

### UNACCOUNTED class

A suite submitted but never measured (parent signalled mid-pool, parity mismatch, unmapped reaped pid) renders `[UNACCOUNTED] <label>` and exits **1** — unmeasured coverage outranks a terminated suite that at least named itself. SIGINT/SIGTERM stop dispatch, reap what's observable within a bounded window, KILL stragglers, mark the rest UNACCOUNTED, and exit 1. The in-run parity check (`submitted == rendered`) is the dynamic twin of shard totality.

### What is untouched

Serial mode is byte-for-byte the pre-change path (the `_pj_mode` guard sits after the chokepoint; the serial exec/verdict code is the same code). `--affected`, `--print-selection`, `--enumerate`, `--capacity`, refusal arms (exit 4), the sibling census, `tc_acquire`, the repo-write boundary (drain runs before the end-sample; `_repo_last_suite` tracks dispatch position), durable-log retention, and the single EXIT trap. Affected runs keep their selection semantics — parallel applies to the RUN path only, and an affected run without the knob stays sequential as today.

## Files

| File | Change |
|---|---|
| `scripts/test-all.sh` | `--jobs`/env parse + validation, lanes source, `_pj_*` scheduler (state, resolve, submit/fill/launch/reap/render/drain/retain), `run_suite` dispatch branch + `_run_suite_verdict` extraction, `_pj_drain` call site, UNACCOUNTED in breakdown + exit ladder, mid-termination pool retention, help text |
| `scripts/lib/test-suite-lanes.sh` | NEW: token classifier + override table + `lane_tokens_conflict` |
| `scripts/lib/test-suite-lanes.test.sh` | NEW: lane census (glob-registered) |
| `scripts/test-all-parallel-scheduler.test.sh` | NEW: focused guard — population parity, ordering, exit contract incl. [FAIL]/[KILLED], token/`*` serialization, liveness + tmp_delta fields, all fallback arms, jobs validation |
| `scripts/test-all-parallel-contention.test.sh` | NEW: shared-resource serialization — lock-precedes-pool ordering, lock-not-held never goes wide, real-flock token arm, `*` under pressure |
| `scripts/test-all-parallel-benchmark.test.sh` | NEW: two-arm serial/parallel measurement harness (records, doesn't gate ratio) |
| `scripts/lib/test-affected-paths.sh` | `AFFECTED_*_PATHS` declarations for the four new suites |
| `knowledge-base/engineering/operations/runbooks/local-gate-parallel-mode.md` | NEW: when to use local parallel vs CI shards + serial fallback |

## Verification record

- `scripts/test-all-parallel-scheduler.test.sh`: **23/23 pass** — population parity, registration-order rendering, exit 1 on FAIL / exit 3 on KILLED / `[KILLED]` for rc=143, token mutual exclusion, `*` drain barrier, `[run]` liveness, `tmp_delta`, all fallback arms, exit-2 validation.
- `scripts/test-all-parallel-contention.test.sh`: **5/5 pass** — anchored ordering (acquire < resolve < drain < epilogue), lock-not-held → serial, real-flock token serialization, `*` under width-4.
- `scripts/lib/test-suite-lanes.test.sh`: **6/6 pass** — 686 emitted registrations all resolve; overrides non-stale, reasoned, deduped; conflict contract.
- `scripts/test-all-parallel-benchmark.test.sh`: **4/4 pass** — fixture corpus (4 sleep + 4 CPU-bound): serial 4642 ms → parallel 2472 ms @ jobs=4 (**1.88×**) on this host (nproc=16, ~15 GB avail).
- `bash -n` clean on every changed shell file.
- Serial contract spot-checks (below).

## Hazards found and handled

- **`for x in $1` glob expansion dissolved `*` tokens** into the CWD file list — the barrier check silently passed; caught by the `*` arm, fixed via `read -ra`.
- **Compound `local idx=.. label=${_pj_label[idx]}`** expands RHS words before `local` runs — `idx` unbound under `set -u`; split into two `local`s.
- **`bash -c` argv is unmappable** to a suite file → classifier returns `*` (fail closed); fixture suites must be file paths.
- Sandbox splice convention: the body needs a leading newline after the neutered-acquire comment.
- Sibling-run detection (`tc_preamble`, `--capacity`) sees worker processes as *suite* processes (the `exec` fix), not phantom runs — verified by inspection; the pool never runs without the advisory lock held.

## Guard Contract

### Guard 1 — `test-all-parallel-scheduler.test.sh`: parallel scheduling preserves the registered population and the top-level exit contract

**Property.** A sandboxed copy of the real runner under `SOLEUR_TEST_JOBS=4` produces exactly one rendered verdict per `run_suite` registration, in registration order, with the serial classification semantics: planted FAIL → `[FAIL]` + exit 1, planted signal-shaped exit → `[KILLED]` + exit 3, clean run → exit 0, and the `=== N/M ===` marker counts the true denominator. A malformed jobs value exits 2; every fallback condition resolves serial with a named banner.

**Assembly.** The sandbox splices fixture `run_suite` calls between the real `tc_acquire` and `tc_epilogue` anchors (each asserted unique), neuters only the lock and preamble, and re-arms the scheduler via `_pj_lock_held=1` + `_pj_resolve_run_mode` — so the dispatch, pool, reaper, drain, classifier, epilogue and exit ladder under test are the shipped ones, not a re-implemented mirror. Window overlap is computed from nanosecond timestamps the fixtures write to a shared timeline, not inferred.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | A fixture exits 1 mid-pool | `[FAIL]` on stdout/stderr + run exits 1 — never masked by the scheduler. |
| 2 | A fixture dies by SIGTERM (rc=143) | `[KILLED]` + exit 3 — signal shapes survive `wait` status mapping. |
| 3 | `*` token on a mid-walk fixture | Drained pool: its window intersects no other fixture's. |
| 4 | Shared `artifact:` token on two fixtures | Their windows never overlap, though a third fixture overlaps freely. |
| 5 | `SOLEUR_TEST_JOBS` unset / =1 | Serial walk, no `[parallel] mode engaged` banner. |
| 6 | `SOLEUR_TEST_JOBS=banana` | Exit 2 — malformed input refuses before any work. |
| 7 | `_pj_lock_held=0` with jobs=4 | `serial fallback — reason=lock-not-held` and zero workers launched. |
| 8 | Delete the `*` arm from `lane_tokens_conflict` | The `*` fixtures overlap → arm reds (the measured `for x in $1` glob defect class). |

**Anchor.** The verdict-ordering and population assertions grep the rendered output against the registration sequence the fixture body emitted — a scheduler that drops, reorders or double-runs a registration reds deterministically.

### Guard 2 — `test-all-parallel-contention.test.sh`: shared-resource suites remain serialized across worktrees

**Property.** A run goes wide only while holding the repo-global advisory lock (so two worktrees still serialize at run granularity), and suites sharing a resource token never run concurrently within the pool.

**Assembly.** Anchored ordering on the shipped file (`tc_acquire` precedes `_pj_resolve_run_mode` precedes `_pj_drain` precedes `tc_epilogue`), the lock-verdict read on `_SESSION_LOCK_ACQUIRED`, a lock-not-held sandbox arm, a real `flock` critical-section fixture pair (the shared resource is a real lock file, not a timing proxy), and a `*` barrier under width-4 pressure.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | Resolve called before `tc_acquire`, or reading a different lock verdict | Ordering/verdict anchors red — parallel must never precede the lock. |
| 2 | Lock-not-held under an explicit jobs request | Serial fallback; zero `[parallel] mode engaged`. |
| 3 | Two same-token fixtures taking an exclusive flock on a shared file | Flock windows never interleave — the token mechanism must serialize a real resource. |
| 4 | `*` fixture submitted between independent fixtures | Runs alone both directions — drains the pool before, blocks dispatch until reaped. |

**Anchor.** The flock arm fails on any overlap of the critical-section log — a scheduler regression cannot be hidden by a coincidentally serial schedule.

### Guard 3 — `test-suite-lanes.test.sh`: the lane table can never leave a registration unclassifiable or silently stale

**Property.** Every `--enumerate` registration resolves to a token set; every override names a live registration label, carries a reason, and is unique; `*` conflicts with everything and disjoint sets do not.

**Assembly.** Reads the same `SUITE_COMMAND` channel the scheduler's input flows through, unions in `run_suite` literals for conditionally-emitted labels, and evaluates `lane_tokens_for` + `lane_tokens_conflict` from the shipped lib.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| 1 | A new registration the classifier cannot map to a file | Resolves to `*` (fail closed per suite), never unresolvable. |
| 2 | An override for a renamed/removed registration | Stale-label arm reds — a dead override protects nothing. |
| 3 | Override with empty reason | Reds — the exclusion shape requires a machine-checked reason. |
| 4 | `lane_tokens_conflict` returning "disjoint" for `*` vs anything | Conflict-contract arm reds — the drain barrier is the one unsafe-to-lose semantic. |

**Anchor.** The census is exhaustive over the emitted population, so no registration can slip past the classifier unnoticed.

## Rollback

`SOLEUR_TEST_JOBS=1` or `--jobs=1` restores the unchanged serial path; unsetting the knob is identical (serial is the default).
