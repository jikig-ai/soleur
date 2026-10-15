---
title: "fix: test-all contention robustness — bounded lock wait, C8 nested-run refusal, mutation-battery ceiling"
type: fix
date: 2026-10-13
slug: test-all-contention-robustness
branch: feat-one-shot-7697-10209-8163-contention-robustness
issue: 7697
closes: [7697, 10209, 8163]
lane: cross-domain
---

# fix: test-all contention robustness — bounded lock wait, C8 nested-run refusal, mutation-battery ceiling

## Enhancement Summary

**Deepened on:** 2026-10-13
**Sections enhanced:** Technical Approach (precedent diff, fd-close race),
Research Insights (deepen-gate ledger), Hypotheses (deep-dive pass-through).

### Key Improvements

1. Plan-time reproduction of the #7697 signal-mask defect, refining the
   issue's hypothesis: the defeating condition is a **blocked** SIGALRM mask
   (verified still waiting at 6 s on a `-w 3` bound), not an ignored
   disposition (`SIG_IGN` arm returned at 3 s). `timeout(1)` fires correctly
   under the same blocked mask (rc=124) — the mechanism choice rests on a
   measurement, not a man page.
2. Root cause for #10209 narrowed past the issue text: the sandbox's own
   `build_sandbox` re-arms `TC_SIBLING_RUN_COUNT_PID=$$` while `ENV_SCRUB`
   leaves the parent's exported `TC_SIBLING_RUN_COUNT` live — the fix removes
   the false antecedent rather than exempting from it.
3. Sharp-edges pass applied: `timeout`→`gtimeout`→bare portability ladder
   (#8231 — this lib ships to customer hosts), census-not-list sibling sweep
   (#8097), consumer-provenance contract for the new holder marker (#6921).

### New Considerations Discovered

- `timeout`-kills-`flock` race: if `flock -w` acquires the lock at the exact
  instant `timeout` fires, the parent fd may hold a lock the caller believes
  failed. Harmless by construction — `_acquire_lock_impl`'s existing failure
  path closes the fd (`eval "exec ${fd}>&-"`), which releases the acquisition.
- The shared lock dir is already populated and active on this box (150+
  pipeline-tally locks + `test-all.lock` + `test-all.queue.d` observed via the
  plan's own `discoverability_test` command — verified working).
- Every `acquire_lock`/`with_lock`/`tc_acquire` consumer inherits the bound
  fix for free (chokepoint edit), including `merge-main` 600 s waits and
  `worktree-manager` cleanup locks — wider blast radius of benefit than the
  issue names.

**Deepen-gate ledger:** 4.5 network-outage deep-dive → trigger matched on
`timeout`; all four layers opted out with the reproduction as artifact (no
network hop exists in any failure path). 4.6 User-Brand → pass. 4.7
Observability → pass (discoverability command executed and verified
locally). 4.8 PAT → no hits. 4.9 UI-wireframe → skipped (no UI-surface
files). 4.10 Encryption → skipped (no store/connection). 4.11 Guard Contract →
`lint-guard-contract.py` green, 4 entries. 4.12 Scope Check → 1 unfenced
section, no unmapped/unjustified rows. 4.4 precedent-diff → applied below.
4.45 verify-the-negative → all negative claims confirmed (see Research
Insights). 4.55 downtime → N/A (no serving surface). Reviewer-agent fan-out →
unavailable in this subagent context (no Task tool); recorded in
`decision-challenges.md`.

## Overview

Contention-robustness batch for the local test-all gate, closing three open
issues plus one spec-archive housekeeping item. Under sibling contention or a
wedged prior holder, three surfaces currently misbehave: the repo-wide advisory
lock's declared wait bound can fail to fire (#7697 — empirically reproduced at
plan time: a **blocked** SIGALRM mask defeats `flock -w`, an *ignored* SIGALRM
disposition does not), a nested sandboxed run inside the weight-drift suite can
refuse with rc=4 on a sibling count the sandbox never measured (#10209), and the
orphan-reaper mutation battery asserts a fixed wall-clock ceiling that machine
load alone can exceed (#8163). The plan bounds the lock wait by a mechanism
independent of the inherited signal mask, makes holder progress observable to
waiters, bounds the gitleaks suite's external invocations, makes the C8 sandbox
immune to an inherited sibling count, and makes the battery's ceiling
contention-aware rather than silently raised.

## Problem Statement / Motivation

Three measured incidents, one failure class: **the test-all contention
machinery loses correctness under exactly the condition it exists for —
contention**.

1. **#7697 (priority/p1-high).** A wedged `test-all.sh` holder owned the
   repo-wide advisory lock (`.git/soleur-session-state/locks/test-all.lock`) for
   **4.6 days**; every worktree queued behind it. Two defects: (a)
   `flock -w 3600` in `_acquire_lock_impl`
   (`plugins/soleur/scripts/lib/session-state.sh:112`) never returned — the
   issue hypothesises an inherited SIGALRM problem, and plan-time reproduction
   confirms it is the **blocked mask** arm: `sigprocmask(SIG_BLOCK, SIGALRM)`
   before exec leaves `flock -w 3` still waiting at 6 s while the control and
   `SIG_IGN` arms return at 3 s; (b) the holder itself was a suite
   (`plugins/soleur/test/gitleaks-merge-commit.test.sh`) wedged in
   `anon_pipe_read` — a command-substitution/pipeline read that never delivers,
   with no bound.
2. **#10209.** Weight-drift case C8 (the dominant bare-invocation arm) ran red
   under sibling full-gate load: the sandboxed nested `test-all.sh` exited rc=4
   on the sibling refusal ("refusing a full-gate run — N sibling full-gate
   run(s) already in flight"), failing for a reason unrelated to the drift arm
   it measures. Root cause found at plan time: `build_sandbox`
   (`scripts/test-all-weight-drift.test.sh:407-411`) neuters `tc_preamble` AND
   splices `TC_SIBLING_RUN_COUNT_PID=$$` before the refusal opener — but
   `ENV_SCRUB` (line 456) never unsets `TC_SIBLING_RUN_COUNT`, so the count the
   **parent** real run exported (it is exported deliberately, per
   `scripts/test-all.sh:4169`) leaks into the sandbox and satisfies the
   re-armed stamp conjunct. `test-all-affected.test.sh:194-195` shows the
   in-repo precedent for pinning the count from a suite-controlled variable.
3. **#8163 (priority/p2-medium).** `scripts/orphan-process-reaper-mutation.test.sh`
   asserted `wall-clock 429523ms EXCEEDS the 240000ms ceiling` on a local
   `TEST_GROUP=all` run while three sibling batteries ran; isolated re-run was
   179 s, 604/604 green, CI green. The ceiling measures machine load, and the
   battery's own message forbids silently raising it.

4. **Housekeeping.** `knowledge-base/project/specs/feat-one-shot-6752-7004-10167-tmp-gate-residuals/`
   shipped unarchived; repo convention (enforced by
   `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh`, timestamped
   `specs/archive/<YYYYMMDDHHMMSS>-<name>` destinations) is `git mv` into
   `specs/archive/` riding a feature PR.

## Proposed Solution

- **Bound the wait by something the inherited signal mask cannot defeat.**
  Wrap the `flock -w` call in `_acquire_lock_impl` in a `timeout(1)` outer bound
  (`timeout -k <kill-grace> <timeout_s + slack>`). Measured at plan time:
  `timeout` fires at its bound under a blocked-SIGALRM mask (rc=124) where
  `flock -w` did not. rc=124 maps to the same `return 99` contended path as
  `flock -w` expiry — ADR-133 Decision 3's "proceeds on expiry, never aborts"
  is preserved verbatim.
- **Make holder progress a readable signal, not an inference.** The lock
  holder records a per-name marker file beside the lock
  (`$LOCK_DIR/<name>.holder`: holder pid, acquire epoch, last-progress epoch,
  last suite) — stamped at acquire and refreshed by `run_suite` at each suite
  boundary in `scripts/test-all.sh`; removed by `release_lock`. The waiter's
  existing `LOCK_WAIT_HEARTBEAT` beat gains `holder_pid=` / `holder_alive=` /
  `holder_progress_age=` fields, so "queued behind real work" and "queued
  behind a corpse" stop being the same observable. **Report-only** — no
  detection-and-kill; ADR-133's stale-holder-detection rejection covers the
  dead-pid case and this plan does not re-open it (the observed defect is a
  *live* wedged holder — recorded as an ADR-133 addendum).
- **Bound every external invocation in the gitleaks merge-commit suite.**
  Extend `plugins/soleur/test/lib/gitleaks-probe.sh`'s existing
  `timeout`/`gtimeout`/degrade idiom (`TO=(timeout 10)` at lines 34-35) into a
  shared bounded-invocation helper, and route the suite's `gitleaks`/`git`
  calls — the `anon_pipe_read` wedge surface — through it with `</dev/null`
  stdin and `GIT_TERMINAL_PROMPT=0`.
- **Remove the false antecedent in C8's sandbox.** Add
  `-u TC_SIBLING_RUN_COUNT -u TC_SIBLING_RUN_COUNT_PID` to the suite's
  `ENV_SCRUB` and pin the spliced re-arm's count from a suite-controlled
  variable (mirroring `test-all-affected.test.sh`'s `SANDBOX_SIBLINGS` idiom),
  keeping the refusal exercisable by explicit fixture while an inherited count
  can never leak in. Add a regression arm that exports `TC_SIBLING_RUN_COUNT=3`
  around a C8-class invocation.
- **Make the battery ceiling honest about contention.** The mutation battery
  samples sibling presence (`tc_siblings` from `scripts/lib/test-contention.sh`,
  already fixture-able via `TC_PROC_ROOT`) at battery start and end; when
  siblings were present during the window it reports the over-ceiling reading
  as a `[note]` line instead of a `[FAIL]`, and the assertion is unchanged —
  still fails — on an uncontended box.
- **Archive the prior spec dir** via `archive-kb.sh` (dry-run first).

## Technical Approach

### Architecture

Chokepoints over member lists, consistent with the repo's own discipline:

- `_acquire_lock_impl` (`plugins/soleur/scripts/lib/session-state.sh:90-119`)
  is the single acquire chokepoint for every named lock (`acquire_lock`,
  `acquire_lock_shared`, `with_lock`; consumers include `tc_acquire`,
  `merge-main`, `pipeline-tally`, `worktree-manager` cleanup/fetch-prune). The
  bound lands there once and every lock inherits it.
- `LOCK_DIR` is resolved by `_session_state_init_dirs`
  (`session-state.sh:46-53`) anchored at `git rev-parse --git-common-dir` —
  shared across worktrees, which is exactly the scope the repo-wide `test-all`
  lock has. The holder marker lives there; `SOLEUR_SESSION_STATE_ROOT` is the
  existing test seam.
- `run_suite` (`scripts/test-all.sh:1640`) is the per-suite chokepoint the
  progress stamp hooks; `release_lock` (`session-state.sh`) is the removal
  chokepoint. The waiter side is `_tc_wait_heartbeat`
  (`scripts/lib/test-contention.sh:969`) — it already emits per-beat fields
  and is the single site every queued run prints through.
- The sibling-refusal conjunct lives at `scripts/test-all.sh:4216`; the
  `TC_SIBLING_RUN_COUNT_PID == $$` stamp design (non-exported, stamped by
  `tc_preamble`) is what makes an inherited count inert for a **real** nested
  run — the weight-drift sandbox re-arms the stamp deliberately, so the fix
  belongs in the suite's env/scrub, not in the refusal.
- `tc_siblings` (`scripts/lib/test-contention.sh:528`) is the public probe the
  battery reuses; `TC_PROC_ROOT` fixtures let its tests synthesize sibling
  processes without real contention.
- `SCRIPTS_SHARD`/`suite-shard-legs.tsv` engage only for
  `TEST_GROUP=scripts|scripts-heavy` (`scripts/test-all.sh:1151`) — a local
  `TEST_GROUP=all` run is never sharded, so "move the battery to its own shard"
  does not reach the failure mode the issue measured; it is recorded as an
  alternative, not the fix.

### Precedent diff (lock-acquisition pattern — deepen §4.4)

The change touches a **pattern-bound behavior** (class c — lock acquisition /
mutex). Existing canonical forms in-repo:

| Precedent | Shape | Where | This plan's delta |
|---|---|---|---|
| `flock -w "$timeout_s" "$flag" "$fd"` on a `>>`-opened fd | the single acquire idiom | `session-state.sh:112` | wrapped in a `timeout -k` outer bound — same call, signal-mask-independent deadline |
| `flock -w 5` append block | the cited canonical flock idiom | `agent-token-tee.sh` (`Append under flock`, referenced at `session-state.sh:9-10`) | untouched — its 5 s bounded append is a different contract (short wait, fire-and-forget); the same wrapper *could* apply there but is out of scope — noted for the sweep |
| `flock -n` probe per earlier ticket | deadline-poll shape (signal-free) | `_tc_queue_wait`/`_tc_queue_is_head` (`test-contention.sh:1192-1229`) | precedent for the *fallback* mechanism if `timeout` is ever absent — the poll loop, not a third shape |
| `with_lock name t -- cmd` wrapper | acquire + release on exit | `session-state.sh:150`, consumers `merge-main`/`pipeline-tally` | inherits the bound via the chokepoint for free |

The plan's new surface — the `<name>.holder` marker — has **no precedent for a
progress stamp** (the ticket queue's `.alloc` files are membership markers,
not progress); noted so reviewers scrutinize it as the novel element. Its
write/remove lifecycle is pinned by Guard 2's mutation matrix.

### Implementation Phases

#### Phase 1: #7697 — bounded lock wait + holder observability

- `session-state.sh`: wrap the `flock -w` acquire in a `timeout -k` outer
  bound sized `timeout_s + slack` (slack ~60 s, sized so the inner `-w` is
  still the semantic expiry and the outer only fires when the signal-mask
  defect strikes); map rc=124 to the existing `return 99` contended path.
  **Portability (sharp edge #8231):** use the repo's
  `timeout`→`gtimeout`→bare ladder — the same three-tier shape
  `gitleaks-probe.sh:34-35` and `.claude/hooks/git-commit-secret-scan.sh`
  already carry — because this lib ships in the plugin and runs on customer
  hosts, macOS included (where `flock` itself is a polyfill anyway); a host
  with neither falls back to today's bare `flock -w` with a `[note]`, never a
  new hard dependency. Acquire-at-deadline race is closed by construction: if
  `timeout` fires in the same instant `flock` succeeds, the parent fd can hold
  a lock the call reports as failed — the existing failure path's
  `eval "exec ${fd}>&-"` closes the fd and releases it, so the race is benign
  and needs no new handling. On successful acquire, write `$LOCK_DIR/<name>.holder`
  (`pid=`, `ppid=`, `acquired_epoch=`, `progress_epoch=`); on `release_lock`,
  remove it.
- `test-all.sh`: `run_suite` stamps `progress_epoch=`/`last_suite=`/`suites_done=`
  into the holder file at each suite boundary (cheap single-`printf` rewrite;
  only when the file exists and the run holds the `test-all` lock).
- `test-contention.sh`: `_tc_wait_heartbeat` reads `<name>.holder` each beat
  and prints `holder_pid=<n> holder_alive=<0|1> holder_progress_age=<n>s`
  (absent file → `holder=none`; dead pid → `holder_alive=0` — the two readings
  that distinguish "queued behind work" from "queued behind a corpse").
  Consumer contract for the new signal (sharp edge #6921): the heartbeat is
  the ONLY consumer and it is read-and-report — it never refuses, resumes or
  suppresses on the marker, so provenance needs are met by the marker's own
  fields (`pid`, `acquired_epoch`, `progress_epoch`); a future consumer that
  acts on staleness must re-check `kill -0` at decision time, not at
  marker-write time.
- `gitleaks-probe.sh` + `gitleaks-merge-commit.test.sh`: add a bounded-invocation
  helper (`TO` idiom extended: `timeout`/`gtimeout`, else unbounded with an
  emitted `[note]`); route `scan_git`, `scan_git_count`, `scan_git_rules`,
  `scan_dir_rules`, `patch_bytes`, and the fixture-build `git` calls through
  it; `</dev/null` stdin + `GIT_TERMINAL_PROMPT=0` on all `git` invocations.
  Sibling sweep: apply the same bound in `plugins/soleur/test/gitleaks-rules.test.sh`
  where call shapes match.
- Tests: new arms in `plugins/soleur/test/session-state.test.sh` (blocked-mask
  fixture via `python3 -c 'signal.pthread_sigmask(SIG_BLOCK,{SIGALRM}); exec…'`
  — python3 is already the suites' splice dependency) and
  `scripts/test-contention.test.sh` (holder-marker write/stamp/remove;
  heartbeat field emit; stale-progress reading).
- Success criteria: the blocked-mask arm returns within `timeout_s + slack`;
  a fixture-holder with no progress yields `holder_progress_age` growing while
  `holder_alive=1` — the incident's observable, reproduced deterministically.
- Estimated effort: medium (largest item in the batch).

#### Phase 2: #10209 — C8 inherited-count immunity

- `test-all-weight-drift.test.sh`: `ENV_SCRUB` gains
  `-u TC_SIBLING_RUN_COUNT -u TC_SIBLING_RUN_COUNT_PID`; the
  `build_sandbox` re-arm splice pins the count from a suite-controlled var
  (e.g. `TC_SIBLING_RUN_COUNT="${WD_SIBLING_RUNS:-0}"` before the refusal
  opener, mirroring `SANDBOX_SIBLINGS`); add a regression arm exporting
  `TC_SIBLING_RUN_COUNT=3` around a bare invocation → must still pass.
- Sweep (census, not a hand list — sharp edge #8097): enumerate the whole set
  with `grep -rln 'TC_SIBLING_RUN_COUNT_PID' scripts/ plugins/` and audit each
  hit. Plan-time census: `test-all-weight-drift.test.sh` (this fix),
  `test-all-group-affected.test.sh` (re-arms at :257 AND injects
  `TC_SIBLING_RUN_COUNT=2` deliberately at :407/:417 — audit whether its
  non-refusal arms still leak the inherited count),
  `test-all-affected.test.sh` (already pins via `SANDBOX_SIBLINGS`),
  `plugins/soleur/test/fanout-suite-scope.test.sh` (asserts the stamp is
  non-exported — audit for the same inherited-count reachability),
  `test-all-killed-classification.test.sh` and
  `test-all-runtime-ceiling.test.sh` (neuter `tc_preamble` without a re-arm —
  confirm no refusal can fire on an inherited count). Edit only suites where
  the inherited count actually reaches a live refusal.
- Success criteria: C8 green under an exported sibling count; refusal still
  exercisable inside the sandbox when the suite pins a count deliberately.
- Estimated effort: small.

#### Phase 3: #8163 — contention-aware battery ceiling

- `orphan-process-reaper-mutation.test.sh`: source
  `scripts/lib/test-contention.sh` (guarded — `[[ -f … ]] && source`, degrade
  to today's unconditional assert if absent, matching the file's existing
  lib-optional posture); take `tc_siblings | wc -l`-class readings at battery
  start and end; when `max_siblings > 0`, the over-ceiling branch prints
  `[note] battery wall-clock <ms> exceeded ceiling <ms> under N sibling
  full-gate run(s) — reported, not asserted` and counts as pass-with-note;
  uncontended over-ceiling remains `fail`. `ORPHAN_MUT_CEILING_MS` override
  unchanged.
- Tests: `TC_PROC_ROOT` fixture with a synthesized sibling `test-all.sh` proc
  entry + over-ceiling → note, not fail; empty procfs + over-ceiling → fail
  (assertion is not vacuous); the sibling-count read is exercised at both
  sample points.
- Success criteria: the battery's colour is a function of its own duration on
  an uncontended box and a report under load.
- Estimated effort: small-medium.

#### Phase 4: Housekeeping + decision record

- `bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh --dry-run one-shot-6752-7004-10167-tmp-gate-residuals`
  → verify the preview lists the spec dir → run without `--dry-run` → assert
  `knowledge-base/project/specs/archive/<ts>-feat-one-shot-6752-7004-10167-tmp-gate-residuals/`
  exists and the live dir is gone (`git status` shows a rename).
- ADR-133 addendum: record the live-wedged-holder class (holder alive,
  zero progress — distinct from the rejected dead-pid stale-holder detection)
  and the signal-mask-independent bound; the addendum also corrects nothing in
  the Decision — proceed-on-expiry is untouched.
- Update the stale `TC_LOCK_TIMEOUT (900 s)` comment at `scripts/test-all.sh:4165`
  (it reads 900 s; the value has been 3600 s since #7545) — one-line
  comment fix while the file is open.
- Success criteria: archive destination exists under `specs/archive/`; ADR
  addendum committed; no orphan references to the live spec path
  (`grep -rn 'feat-one-shot-6752-7004-10167' --exclude-dir=archive` clean or
  knowingly retained only where a historical citation is intended).
- Estimated effort: small.

## Alternative Approaches Considered

| Alternative | Why not chosen |
|---|---|
| Abort the run on lock-timeout instead of proceed-contended | **ADR-133 records this as a rejected alternative** ("Make the lock blocking (abort on timeout)"). This plan changes how reliably the bound fires, never the policy. |
| In-shell `trap`/signal fix for `flock -w` | Bash cannot modify an inherited *blocked* signal mask (no `sigprocmask` builtin) and cannot un-ignore a signal ignored on entry (POSIX). Measured moot anyway: the ignored disposition arm did not reproduce — the blocked mask did. |
| `flock -n` deadline-poll loop instead of `timeout` wrapper | Viable and signal-free (the ticket queue already polls `flock -n`), but reimplements `-w` semantics with poll-cadence wake latency; the wrapper is the smaller diff and preserves instant release-wake. Recorded as the fallback if `timeout` proves unavailable on a supported host. |
| Stale-holder detection that kills the holder | ADR-133's rejection stands (re-measured 2026-09-06 addendum): dead-pid lock retention is unreachable under real flock, and live-wedged detection is kept **report-only** — consistent with `orphan-process-reaper.sh`'s report-only posture pending real-world specificity evidence. |
| #10209 option B: C8 asserts on the refusal branch when siblings detected | Turns C8's verdict into a function of host state (green-by-refusal vs green-by-arm) — the same host-dependent-verdict class `2026-09-20` records as a defect. Exemption keeps C8's contract fixed: it measures the drift arm, never the gate. |
| #8163: move the battery to its own shard / trim rows | Sharding (`SCRIPTS_SHARD`) engages only under `TEST_GROUP=scripts|scripts-heavy`; the failure was a local `TEST_GROUP=all` run, which is never sharded. Trimming rows cuts the mutation coverage the ceiling exists to defend. Both recorded; contention-awareness is the only option that reaches the measured failure. |
| #8163: raise the ceiling | The battery's own message forbids it ("rather than raising this silently"), and 240 s is already re-derived (~1.9× ideal) — a raise would still break under heavier load. |
| Fix `flock -w` in util-linux / upstream | Out of scope; upstream's `-w` contract is correct where the mask is sane. The repo must be robust to inherited masks because it cannot control its parent process. |

## Research Insights

**Premise validation (Phase 0.6).** All three issues verified `OPEN` via
`gh issue view` (7697: `priority/p1-high`; 10209: `domain/engineering`,
`deferred-scope-out`; 8163: `priority/p2-medium`, `type/chore`). Every cited
artifact confirmed on this branch: `session-state.sh:112` (`flock -w
"$timeout_s" "$flag" "$fd"`), `test-contention.sh:72` (`TC_LOCK_TIMEOUT`
default 3600), `test-all.sh:4221` (sibling refusal), `test-all.sh:4169-4178`
(exported count + non-exported PID stamp), `test-all-weight-drift.test.sh`
(C8 at 628-639, `build_sandbox` re-arm at 407-411, `ENV_SCRUB` at 456),
`orphan-process-reaper-mutation.test.sh:435-442` (ceiling + fail arm),
`plugins/soleur/test/gitleaks-merge-commit.test.sh` (scan functions at
125-215), `plugins/soleur/test/lib/gitleaks-probe.sh:34-35` (existing
`timeout`/`gtimeout` idiom), `scripts/orphan-process-reaper.sh` (report-only
precedent), `scripts/suite-shard-legs.tsv` + `SCRIPTS_SHARD` group scoping
(`test-all.sh:1151`). ADR corpus grep for the proposed mechanisms:
**ADR-133** read — `abort-on-timeout` and `dead-pid stale-holder detection`
are recorded rejections and this plan honours both; **ADR-196** read —
refusal binds to measured conditions; **ADR-187** (nested-runner signals)
noted. The archive convention was verified against `specs/archive/` entries
(`YYYYMMDDHHMMSS-<name>`) and `archive-kb.sh`'s slug arg + dry-run mode.

**Mechanism measurement (plan-time).** On this box (2026-10-13): control
`flock -w 3` → rc=1 at 3.0 s; inherited `SIG_IGN` SIGALRM → rc=1 at 3.0 s;
`sigprocmask(SIG_BLOCK, SIGALRM)` → still waiting at 6 s (bound defeated);
blocked mask + `timeout 4 flock -w 60` → rc=124 at 4 s (outer bound fires).
The issue's "SIG_IGN" hypothesis is refined: the defeating condition is the
**blocked mask**, which no in-bash mechanism can clear — hence the
exec-boundary fix.

**Property List (Phase 0.6b).** P1 the declared lock-wait bound actually
fires under the conditions test-all runs in; P2 a waiter can distinguish a
progressing holder from a wedged one; P3 the gitleaks suite cannot block
indefinitely on a pipe read; P4 C8's verdict reflects only the drift arm;
P5 the battery ceiling does not redden on machine load alone; P6 the prior
spec dir sits under `specs/archive/`.

**Cut List (Phase 0.6b).** New stale-holder *detection* mechanism → P2 is
already partially served by the waiter heartbeat — cut the detect-and-act
shape, keep report-only holder fields on the existing beat (ADR-133 rejection
honoured). New sharding leg for the battery → P5 asks for the local-run class
where shards don't engage — cut. A new bounded-run primitive → the
`gitleaks-probe.sh` `TO` idiom already exists — reused, extended, not rebuilt.

**Relevant learnings.** `2026-08-13-a-lower-bound-cannot-tell-a-measurement-from-a-constant.md`
(this same module — assertions must pin a measurement, not a constant);
`2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md`
(a must-PASS row whose verdict is a property of the host — the #8163 class);
`2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`;
`2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`.

**Research decision (Phase 1.6).** External research skipped — the mechanism
space is repo-internal (flock semantics verified empirically on-box); no
community discovery (Phase 1.5): stack is bash/util-linux internals where the
repo's own `test-contention.sh` is the deepest local precedent. Functional
overlap (Phase 1.5b, manual — no Task tool in this subagent): holder-progress
markers do not exist (`LOCK_WAIT_HEARTBEAT` is waiter-side only);
`orphan-process-reaper.sh` covers deleted-cwd processes, not live-wedged
lock holders; `proc.sh` refuses deleted-cwd by design. Gap is real.

**Lane note.** Spec lacks valid `lane:` (no `spec.md` exists for this branch
yet) — defaulted to `cross-domain` (TR2 fail-closed).

**Agent-availability note.** This plan was produced inside a Task subagent
without a Task/Agent tool: `soleur:engineering:discovery:functional-discovery`,
domain leaders, `soleur:product:spec-flow-analyzer` (Phase 3), the
advisor-tier consult (Phase 4.5), and the plan-review panel could not be
spawned. Functional overlap and domain assessment were performed inline;
technical rulings were recorded `pending - assumed:` in
`knowledge-base/project/specs/feat-one-shot-7697-10209-8163-contention-robustness/decision-challenges.md`
and ruled by a single batched `soleur:engineering:cto` spawn at the pre-work
gate (2026-10-13) — see that file's `## Decision Classes` table.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "`flock -w` does not time out … worth checking whether SIGALRM is blocked or ignored" | Verified by experiment: **blocked mask** defeats `-w`; `SIG_IGN` does not; `timeout` bound fires under the blocked mask | Fix at the exec boundary (`timeout -k` wrapper) — no in-bash mechanism can unblock a mask |
| test-contention.sh's "no stale-holder detection" comment | Present and *correct for its scope* — it covers dead-pid retention, which real flock makes unreachable; the incident was a live-wedged holder | Keep the comment; add a pointer to the holder-progress mechanism + ADR-133 addendum recording the distinction |
| "the nested run hits the full-gate refusal" | Verified: sandbox neuters `tc_preamble` and re-arms `TC_SIBLING_RUN_COUNT_PID=$$`, but `ENV_SCRUB` doesn't unset `TC_SIBLING_RUN_COUNT`, so the parent's exported count leaks in | Scrub the var + pin a suite-controlled count (the `SANDBOX_SIBLINGS` idiom) |
| "trim rows or move the battery to its own shard" (issue's own words) | `SCRIPTS_SHARD` is scoped to `TEST_GROUP=scripts|scripts-heavy` — the failing run was `TEST_GROUP=all` | Shard move cannot fix the observed class; contention-aware ceiling can |
| C9's env scrub sets `SOLEUR_ALLOW_FULL_GATE=` empty | Confirmed — empty is deliberately not `1`; an `=1` injection would exempt the subagent arm too | Exemption is done by removing the *antecedent* (the count), not by bypassing the refusal — ADR-196-consistent |

## User-Brand Impact

- **If this lands broken, the user experiences:** an operator/agent staring at
  a test gate that queues forever with no indication of why, or a suite red
  for a reason unrelated to their diff — the "phantom red" and
  "invisible queue" classes these issues measure. No end-user product surface
  is touched.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the
  marker file writes pid/progress metadata into the shared
  `.git/soleur-session-state/locks/` dir on the operator's own machine —
  machine-local, no network egress, no user content.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** all changes are confined to local
  test-runner machinery (lock acquisition, heartbeat text, test suites); the
  worst reachable user harm is a continued flaky suite, which is the status
  quo ante, not a new harm class.
- `threshold: none, reason: the diff touches scripts/, plugins/soleur test
  libraries and a session-state lib — internal dev-gate machinery with no
  user-facing product surface, so no sensitive-path consumer is affected`

## Observability

```yaml
liveness_signal:
  what: "[contention] LOCK_WAIT_HEARTBEAT beat on stderr, extended with holder_pid / holder_alive / holder_progress_age; '[contention] LOCK_BOUND_FORCED' emitted when the timeout outer bound fires instead of flock -w expiry"
  cadence: "per TC_WAIT_HEARTBEAT_S (60 s default) during any queued wait; on-bound-fire for the forced path"
  alert_target: "the queued run's stderr — read by the agent/operator already watching the wait"
  configured_in: "scripts/lib/test-contention.sh (_tc_wait_heartbeat), plugins/soleur/scripts/lib/session-state.sh (_acquire_lock_impl)"

error_reporting:
  destination: "stderr contention banner lines (same channel as LOCK_CONTENDED_PROCEEDING today)"
  fail_loud: "a wedged holder is distinguishable in-band: holder_alive=1 with holder_progress_age growing; a dead holder prints holder_alive=0 — neither requires /proc archaeology"

failure_modes:
  - mode: "flock -w bound defeated by inherited signal mask"
    detection: "timeout outer bound returns rc=124 → '[contention] LOCK_BOUND_FORCED' line names the lock and the elapsed bound"
    alert_route: "queued run proceeds contended (unchanged policy) and the line is in the run log"
  - mode: "holder wedged while alive (the #7697 shape)"
    detection: "waiter heartbeats show holder_progress_age climbing with holder_alive=1"
    alert_route: "reported in-band; the orphan-process-reaper report arm remains the standing kill-decision surface"
  - mode: "holder marker write/read failure (permissions, deleted dir)"
    detection: "heartbeat omits holder fields with holder=unreadable — never a FAIL, the marker is advisory"
    alert_route: "stderr note in the beat"

logs:
  where: "test run stderr (captured to the per-run log dir) + $LOCK_DIR/<name>.holder while a run holds the lock"
  retention: "holder file lifetime = lock hold duration; run logs per the existing /var/tmp/soleur-test-all-logs retention"

discoverability_test:
  command: bash -c 'd="$(git rev-parse --git-common-dir)/soleur-session-state/locks"; ls "$d" 2>/dev/null; echo LOCKDIR_OK'
  expected_output: LOCKDIR_OK
```

## Encryption Posture

Not required — no persistent data store and no new cross-component/network
connection. The holder marker is an ephemeral file inside the existing
machine-local lock dir, not a store; deletion is covered by `release_lock`
and the marker contains only pid/epoch metadata.

## Guard Contract

The deliverable includes four assertion-based checks (regression arms). Each
is listed with the mutation that must drive it red.

### Guard 1 — bounded lock wait (session-state.test.sh arms)

**Property.** `acquire_lock` returns within `timeout_s + slack` under every
inherited signal disposition — including a blocked SIGALRM mask.

**Assembly.** The single chokepoint `_acquire_lock_impl` in
`plugins/soleur/scripts/lib/session-state.sh` — every named lock
(`acquire_lock`, `acquire_lock_shared`, `with_lock` and their consumers:
`tc_acquire`, `merge-main`, `pipeline-tally`, `worktree-manager` locks) flows
through it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Remove the `timeout -k` wrapper, restoring bare `flock -w` | RED — blocked-mask fixture exceeds the bound |
| 2 | Neuter the fixture itself (stop blocking SIGALRM in the python3 wrapper) | RED — arm must prove it measures the mask, not just contention (dispatch-vacuity row: an arm that passes either way is vacuous) |
| 3 | Second consumer: drive `with_lock x 1 -- true` through the same blocked-mask fixture | RED if the bound only covers the `acquire_lock` entry point — the property is at the chokepoint, not one caller |
| 4 | Must-PASS input differing from canonical: SIG_IGN (not blocked) inherited disposition | PASS — the ignored-disposition arm verified harmless at plan time; the guard must not reject it |

### Guard 2 — holder progress marker (test-contention.test.sh arms)

**Property.** While a `test-all` lock is held, `$LOCK_DIR/test-all.holder`
carries a freshness the waiter's heartbeat reports; after release the marker
is gone and the beat reports `holder=none`.

**Assembly.** Write sites: `tc_acquire` success path (mint), `run_suite`
per-suite boundary (stamp), `release_lock`/epilogue (remove). Read site:
`_tc_wait_heartbeat`. There is exactly one write chokepoint per lifecycle
stage; the runner's suite loop is the only stamp site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the `run_suite` stamp | RED — a fixture holder with no stamp must read `holder_progress_age` growing, not `fresh` |
| 2 | Delete the `release_lock` removal | RED — marker outlives the lock (post-release read asserts absence) |
| 3 | Heartbeat stops reading the marker (revert to waiter-elapsed-only fields) | RED — the beat loses `holder_*` fields, which is the #7697 observable the issue names |
| 4 | Must-PASS differing input: no lock held at all | PASS — beat runs without holder fields and no error |

### Guard 3 — C8 sibling-count immunity (weight-drift arm)

**Property.** A `TC_SIBLING_RUN_COUNT` present in the suite's own environment
can never satisfy the sandboxed runner's refusal conjunct; only a
suite-pinned count can.

**Assembly.** `ENV_SCRUB` (the only env channel into `run_arm`/`build_sandbox`
invocations) and the `build_sandbox` re-arm splice — the two sites an
inherited or injected count can enter through.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Remove `-u TC_SIBLING_RUN_COUNT` from `ENV_SCRUB` | RED — regression arm exporting `TC_SIBLING_RUN_COUNT=3` reddens the bare-invocation arm (the incident repro) |
| 2 | Revert the splice pin so the re-arm keeps `TC_SIBLING_RUN_COUNT` ambient | RED — same arm |
| 3 | An arm pinning `WD_SIBLING_RUNS=2` must still observe the refusal | PASS-with-rc=4 evidence — proves the splice did not delete the refusal (guard's own dispatch) |
| 4 | Suite env carrying `TC_SIBLING_RUN_COUNT=0` | PASS — boundary value must not spuriously refuse |

### Guard 4 — contention-aware ceiling (orphan-process-reaper-mutation.test.sh arms)

**Property.** The wall-clock ceiling asserts iff no sibling full-gate run was
observed during the battery window; under observed siblings the same reading
is a report line.

**Assembly.** Two sample sites (battery start, battery end) and the single
ceiling `if` at the measurement print — every path the verdict can take flows
through that conditional.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop the sibling sampling (unconditional assert) | RED — the contended-fixture over-ceiling arm must produce the note, not a FAIL |
| 2 | Sample only at start (drop the end sample) | RED — a fixture where a sibling appears mid-window must still read contended |
| 3 | Invert the downgrade (note under contention but fail *because* contended) | RED — note path must never be a fail path |
| 4 | Must-PASS differing input: uncontended + under ceiling | PASS — the common case |

## Architecture Decision (ADR/C4)

- **ADR:** amend `ADR-133` (`knowledge-base/engineering/architecture/decisions/ADR-133-test-all-tmpfs-contention-managed-resource-and-advisory-lock.md`) with a dated addendum: (1) the 2026-08-25 incident's holder class — *live* wedged holder — is disjoint from the rejected dead-pid stale-holder detection, which stays rejected; (2) the lock-wait bound is now enforced at the exec boundary (`timeout`) because an inherited blocked SIGALRM mask defeats `flock -w` — with the plan-time reproduction table; (3) proceed-on-expiry (Decision 3) is unchanged. This is an extension record, not a reversal; no `## Decision` text changes.
- **C4 views:** no C4 impact — enumerated per the completeness mandate across
  `model.c4`/`views.c4`/`spec.c4`: (a) external human actors — none touched
  (all changes are local test-runner machinery); (b) external systems/vendors —
  none (no webhook/API/store edges added); (c) containers/data-stores — none
  (the holder marker is an ephemeral file in the existing lock dir, not a
  modeled store); (d) actor↔surface access relationships — unchanged. The
  closest modeled element is the plugin's skills/agents/commands layer; the
  test-runner internals this plan edits are below the model's decomposition
  floor.
- **Sequencing:** the addendum ships in this PR alongside the code it records.

## Domain Review

**Domains relevant:** engineering (assessed inline)

### Engineering

**Status:** reviewed (partial — domain-leader spawn unavailable in the
planning subagent context; the technical rulings persisted to
`decision-challenges.md` as `pending - assumed:` rows were adjudicated by a
batched `soleur:engineering:cto` spawn at the pre-work gate, 2026-10-13)

**Assessment:** Devex/test-infrastructure change. The load-bearing judgments
are the C8 contract question (#10209 names two legitimate shapes and requires
the suite-author call), the bound mechanism (`timeout` wrapper vs `flock -n`
poll loop), and the ceiling remedy (contention-aware vs shard/trim). Defaults
chosen and recorded; all preserve ADR-133/ADR-196 boundaries.

No UI-surface files in `## Files to Edit`/`## Files to Create` — the
mechanical Product/UX override does not fire; Product tier: **NONE**.

## Hypotheses

Phase 1.4's trigger matched on the word `timeout`. The checklist's four
layers (firewall allow-list, DNS/routing, TLS/proxy, service log) were
evaluated and **opted out layer-by-layer**: every defect in this plan is a
local-process mechanism — `flock(1)` on a filesystem-local lock file, an
inherited POSIX signal mask, an anonymous-pipe read in a local test process,
and a wall-clock assertion. There is no network, host, or service hop in any
failure path, so no L3–L7 artifact exists to verify; the verification
artifact substituting for the layer checks is the plan-time reproduction
(`flock -w` defeated by a blocked SIGALRM mask, `timeout` bound firing under
the same mask — both measured on this box, recorded in Research Insights).

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` (200-issue window)
against every planned file:

- `#8659` — review: 33 test suites replace test-helpers' composed EXIT trap
  and leak the incident sandbox on direct runs — touches
  `scripts/test-all.sh` and `plugins/soleur/test/gitleaks-merge-commit.test.sh`.
  **Acknowledge** — EXIT-trap composition is a different concern than bounded
  invocations; this plan edits neither trap handling nor the incident-sandbox
  lifecycle. Not folded in: the fix belongs to a trap-design pass, not a
  pipe-bound change.
- `#7942` — two mutation batteries named `*.mutation.sh` run in no gate —
  touches `scripts/test-all.sh`. **Acknowledge** — the battery this plan
  edits is `orphan-process-reaper-mutation.test.sh` (registered, gated); the
  ungated-battery naming defect is orthogonal.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#7697 (priority/p1-high): \"test-all: a wedged holder can own the repo-wide advisory lock indefinitely, and flock -w does not time out\"" | Phase 1; FR-1, FR-2, FR-3 | mapped |
| 2 | "#10209: \"test-all-weight-drift: C8 reds under sibling full-gate contention (nested bare-invocation arm gets rc=4)\"" | Phase 2; FR-4 | mapped |
| 3 | "#8163 (priority/p2-medium, meta/machinery): \"orphan-process-reaper-mutation battery: wall-clock ceiling reddens the full run under sibling contention (429 s vs 240 s; 179 s isolated)\"" | Phase 3; FR-5 | mapped |
| 4 | "the prior arc's spec dir `knowledge-base/project/specs/feat-one-shot-6752-7004-10167-tmp-gate-residuals/` shipped unarchived — git mv it into `knowledge-base/project/specs/archive/` per repo archive conventions" | Phase 4; FR-6 | mapped |
| 5 | [issue #7697] "`flock -w` demonstrably returns after its timeout under the conditions test-all actually runs in (or the timeout is implemented in a way that does)" | FR-1 + Guard 1 | mapped |
| 6 | [issue #7697] "A holder that has made no progress for N minutes is detectable — a heartbeat the waiters can read" | FR-2 + Guard 2 | mapped |
| 7 | [issue #7697] "`gitleaks-merge-commit.test.sh` cannot block indefinitely on a pipe read" | FR-3 | mapped |
| 8 | [issue #10209] "have the C8 sandbox pin a marker that exempts it from the sibling refusal (it measures a stub, not real suites), or have C8 assert on the refusal branch explicitly when siblings are detected" | FR-4 (exemption shape — the false antecedent is removed rather than bypassed; Ruled by CTO agent, 2026-10-13, see `decision-challenges.md`) | mapped |
| 9 | [issue #8163] "read `test-all.sh --capacity`'s `measured_runs` and report rather than assert when siblings were present during the run" | FR-5 (uses `tc_siblings` — the same /proc measurement `measured_runs` reports — sampled directly, avoiding a nested runner invocation) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `session-state.sh` bounded acquire + holder marker | "flock -w does not time out" / "a heartbeat the waiters can read" | asked |
| `test-contention.sh` heartbeat holder fields | "a heartbeat the waiters can read, so 'queued behind real work' and 'queued behind a corpse' stop being the same observable" | asked |
| `test-all.sh` `run_suite` progress stamp | "A holder that has made no progress for N minutes is detectable" | asked |
| `gitleaks-probe.sh` bounded-invocation helper | "gitleaks-merge-commit.test.sh cannot block indefinitely on a pipe read" | asked |
| `gitleaks-merge-commit.test.sh` bounded calls | same quote | asked |
| `gitleaks-rules.test.sh` sweep | — | inferred — justification: shares `gitleaks-probe.sh` and the identical unbounded-invocation shape; leaving the sibling suite unbounded re-opens the same wedge class on the next incident |
| `test-all-weight-drift.test.sh` scrub + pin + regression arm | "have the C8 sandbox pin a marker that exempts it from the sibling refusal" | asked |
| Sibling-sandbox sweep (group-affected, killed-classification, runtime-ceiling) | — | inferred — justification: the same re-arm splice exists in `test-all-group-affected.test.sh:256`; a fix that leaves a sibling suite carrying the same leak is the known backdoor class |
| `orphan-process-reaper-mutation.test.sh` contention-aware ceiling | "make the ceiling contention-aware … and report rather than assert when siblings were present" | asked |
| ADR-133 addendum | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the change extends a recorded decision's boundary and must not lag it |
| archive-kb.sh run for the prior spec dir | "git mv it into `knowledge-base/project/specs/archive/` per repo archive conventions" | asked |
| `test-all.sh:4165` stale `(900 s)` comment fix | — | inferred — justification: the comment now misstates the value the plan's work makes load-bearing; one-line, same file, no behaviour |

### Split Assessment

- Subsystems touched: 3 — `scripts/` (test-all, test-contention lib, two suites), `plugins/soleur` (session-state lib, gitleaks probe lib, two suites), `knowledge-base/` (ADR-133 addendum + spec archive move)
- Planned files: ~10 edited, 0 created, 1 dir moved | Estimated changed lines: ~380
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the three issues share one failure class (contention robustness) and one reviewer context (test-all internals); a split would triple CI cost without isolating risk

## Acceptance Criteria

### Functional Requirements

- [ ] FR-1: Under a synthesized blocked-SIGALRM environment (`python3`/`perl`
  `sigprocmask` fixture), an `acquire_lock`/`with_lock` call against a held
  lock returns within `timeout_s + slack`; under a held lock with a normal
  mask the existing `flock -w` expiry path still returns rc≠0 at `timeout_s`;
  in both cases the caller proceeds contended — never aborts (ADR-133
  Decision 3 preserved). A `[contention]`-prefixed line distinguishes the
  forced-bound case from the `-w` expiry case.
- [ ] FR-2: While a `test-all` lock is held, `$LOCK_DIR/test-all.holder`
  exists and carries `pid`, `acquired_epoch`, `progress_epoch`; `run_suite`
  refreshes `progress_epoch`/`last_suite` at each suite boundary;
  `release_lock` removes the file; `_tc_wait_heartbeat` beats print
  `holder_pid=`, `holder_alive=`, `holder_progress_age=` (or `holder=none` /
  `holder=unreadable` — never an error) so a wedged live holder is
  distinguishable from a dead one and from real progress.
- [ ] FR-3: Every external invocation in
  `plugins/soleur/test/gitleaks-merge-commit.test.sh` (`gitleaks`, `git` in
  scan functions, fixture build, and `patch_bytes`) runs under a bounded
  wrapper with `</dev/null` stdin and `GIT_TERMINAL_PROMPT=0`; a stub
  `gitleaks`/`git` that never exits makes the affected arm report/skip rather
  than hang the suite. Where `timeout`/`gtimeout` are both absent, the suite
  emits a `[note]` and runs unbounded (existing probe-lib posture).
- [ ] FR-4: `scripts/test-all-weight-drift.test.sh` C8 (and all sandboxed
  arms) cannot observe an inherited `TC_SIBLING_RUN_COUNT`: `ENV_SCRUB`
  unsets it (and `TC_SIBLING_RUN_COUNT_PID`), and the `build_sandbox`
  re-arm splice pins the count from a suite-controlled variable. A new
  regression arm exporting `TC_SIBLING_RUN_COUNT=3` around a bare invocation
  passes green; an arm pinning the suite var nonzero still observes rc=4 —
  the refusal stays exercisable.
- [ ] FR-5: `scripts/orphan-process-reaper-mutation.test.sh` samples sibling
  full-gate presence at battery start and end via `tc_siblings`; when
  siblings were observed, an over-ceiling reading prints a `[note]` and does
  not fail; when none were observed, over-ceiling still fails.
  `ORPHAN_MUT_CEILING_MS` is unchanged.
- [ ] FR-6:
  `knowledge-base/project/specs/feat-one-shot-6752-7004-10167-tmp-gate-residuals/`
  is moved by `git mv` (via `archive-kb.sh`, dry-run verified first) to
  `knowledge-base/project/specs/archive/<timestamp>-feat-one-shot-6752-7004-10167-tmp-gate-residuals/`;
  the live-dir path is gone and `git status` records the rename.

### Non-Functional Requirements

- [ ] NFR-1: No semantic change to refusal/lock policy — no abort paths added,
  no kill of other processes, no consent-boundary crossing (report-only
  observability).
- [ ] NFR-2: All new external reads are fixture-able through existing seams
  (`TC_PROC_ROOT`, `SOLEUR_SESSION_STATE_ROOT`, `TC_*` knob envs); no test
  requires a real contended host to go green.
- [ ] NFR-3: The holder marker adds at most one file write per suite boundary
  (~90 writes per full gate, sub-millisecond each) — no measurable run-time
  cost; the heartbeat read is one `stat`/`cat` per 60 s beat.
- [ ] NFR-4: Backward-compatible on non-GNU hosts — `gtimeout`/`timeout`
  absence degrades to today's behaviour with a `[note]`, never a new hard
  dependency; `flock` remains the only hard requirement (unchanged).

### Quality Gates

- [ ] `bash scripts/test-all.sh` (or `TEST_GROUP=scripts`) green, including
  the new arms in `session-state.test.sh`, `test-contention.test.sh`, the
  weight-drift regression arm, and the battery's contention arms.
- [ ] `shellcheck` clean on every edited `.sh`.
- [ ] The mutation battery runs green in isolation AND its contended-window
  note path is exercised by the fixture arm (not by waiting for a real
  sibling).
- [ ] ADR-133 addendum committed in the same PR.

## Test Scenarios

Label per pyramid: `unit` = single-function/suite arm; `integration` =
synthesized multi-process fixture; `e2e` = real runner.

### Acceptance Tests (RED phase targets)

- **FR-1 (integration):** Given a lock held by a live holder, when a waiter
  invokes the acquire path under a blocked-SIGALRM mask (python3
  `sigprocmask` → exec bash fixture), then it returns rc≠0 within
  `timeout_s + slack` and emits the forced-bound line.
- **FR-1 (unit):** Given `timeout` absent from PATH, when acquire is invoked
  against a held lock, then the bare `flock -w` path runs and still returns
  at `timeout_s` (mask-normal fixture).
- **FR-2 (integration):** Given a fixture holder that mints the marker and
  never stamps progress, when a waiter heartbeat fires, then the beat shows
  `holder_alive=1` and a growing `holder_progress_age` — the #7697
  observable, deterministically.
- **FR-2 (unit):** Given release, when the waiter beats again, then
  `holder=none` appears and the marker file is gone.
- **FR-3 (integration):** Given a PATH-pinned `gitleaks` stub that sleeps
  forever, when the suite's scan path invokes it, then the bounded wrapper
  returns rc=124-class within its bound and the arm reports rather than
  hangs.
- **FR-4 (integration):** Given `TC_SIBLING_RUN_COUNT=3` exported in the
  suite's own environment, when the bare-invocation arm runs, then the
  sandboxed runner does not refuse and the arm passes.
- **FR-4 (unit):** Given the suite pins its sibling var nonzero, when the
  sandboxed runner reaches the refusal, then rc=4 — refusal still exercisable.
- **FR-5 (integration):** Given a `TC_PROC_ROOT` fixture containing a
  synthesized sibling `test-all.sh` proc, when the battery ends over ceiling,
  then the `[note]` path emits and the suite does not fail on that line.
- **FR-5 (unit):** Given an empty-procfs fixture and an over-ceiling elapsed,
  then the fail arm fires — the assertion is not vacuous under no contention.
- **FR-6 (unit):** Given `archive-kb.sh --dry-run` on the slug, when run for
  real, then `specs/archive/<ts>-feat-one-shot-6752-7004-10167-tmp-gate-residuals/`
  exists and `git status` shows `R` renames.

### Regression Tests

- The #7697 incident shape: live holder + zero progress + queued waiter →
  heartbeat distinguishes it (pre-fix: identical output to a healthy holder).
- The #10209 incident shape: exported sibling count → nested sandbox arm
  (pre-fix: rc=4 red; post-fix: green).
- The #8163 incident shape: measured siblings during window + over-ceiling →
  note not fail (pre-fix: fail).

### Edge Cases

- Holder marker absent mid-wait (holder finished between beats) → `holder=none`,
  no error.
- Marker unreadable (permissions/deleted dir) → `holder=unreadable`, never a
  FAIL — the marker is advisory.
- `TC_SIBLING_RUN_COUNT=0` exported → boundary value must not refuse.
- Sibling appears only at the end-sample → still reported contended (either
  sample point suffices).
- `TC_PROC_ROOT` pointing at a procfs with no enumerable procs → suite must
  not claim "uncontended" it cannot measure: unmeasurable counts as contended
  (fail-safe direction matches `CAPACITY_UNKNOWN` precedent).

### Integration Verification

- `bash plugins/soleur/test/session-state.test.sh` — green.
- `bash scripts/test-contention.test.sh` — green.
- `bash scripts/test-all-weight-drift.test.sh` — green, including under an
  externally exported `TC_SIBLING_RUN_COUNT`.
- `bash scripts/orphan-process-reaper-mutation.test.sh` — green isolated;
  contended-note path covered by fixture arms.

## Success Metrics

- A blocked-mask waiter demonstrably returns within its declared bound
  (asserted by the new arm, reproducing the incident environment).
- C8 cannot redden for an inherited sibling count (regression arm).
- The battery's ceiling verdict is a function of the battery's own duration
  on an uncontended box; under contention the same number is a report.
- Zero abort/kill semantics introduced — verified by no new `kill`/abort
  paths in the diff and ADR-133's Decision 3 untouched.

## Dependencies & Prerequisites

- util-linux `flock` (already a hard requirement — `_session_state_require_flock`).
- coreutils `timeout` for the outer bound (near-universal wherever `flock`
  exists; absence degrades, never hardens).
- `python3` for the blocked-mask test fixture (already the suites' splice
  dependency — `build_sandbox` uses it).
- `archive-kb.sh` for the housekeeping move (dry-run preview before apply).

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| `timeout` wrapper changes a subtle return-code contract | rc=124 and rc=1 both map to the existing `return 99` contended path; a dedicated arm asserts the forced-bound line so the two sources stay distinguishable in logs. |
| Holder marker races (concurrent holders/writers) | `flock` itself serializes holders — only one `test-all` holder exists at a time; writes are `printf`-overwrite, reads tolerate partial/absent file (`holder=unreadable`). |
| ENV_SCRUB grows and masks a future needed var | Scrub targets the two `TC_SIBLING_*` names only; the suite-controlled pin var keeps the refusal testable, so nothing is lost. |
| Contention-aware ceiling hides a real regression under permanent contention | The downgrade requires a *measured* sibling at a sample point; an always-contended box emits the note every run — visible in logs, and the uncontended arm keeps the assertion honest. |
| Sweep edits to sibling suites expand diff | Sweep is verify-first; edit only where an inherited count demonstrably reaches a re-armed refusal. |

## Resource Requirements

Single-engineer diff; no infrastructure, no new vendor/tool dependency beyond
`timeout` (coreutils, already ubiquitous).

## Future Considerations

- A future change could let the reaper consume `holder_progress_age` for a
  wedged-holder report row — deliberately NOT built here (report-only
  posture; ADR-133 addendum records the seam).
- If `timeout` proves absent on a supported host, the documented fallback is
  the `flock -n` deadline-poll loop in `_acquire_lock_impl`.

## Documentation Plan

- ADR-133 addendum (in this PR).
- `test-contention.sh` header comment updated where the
  "no stale-holder detection" paragraph lives — one clause naming the
  live-wedged class and pointing at the holder marker (the comment stays
  correct: it never claimed live holders can't wedge).
- `ship`/`work` SKILL.md rc=4 prose: no change needed — the semantics are
  unchanged; C8's fix removes a *false* rc=4 source, not a real one.

## References & Research

### Internal References

- `plugins/soleur/scripts/lib/session-state.sh:90-119` — `_acquire_lock_impl`
  (chokepoint), `:46-53` (`LOCK_DIR` resolution), `:122-127` (public entry
  points).
- `scripts/lib/test-contention.sh:969` — `_tc_wait_heartbeat`; `:528`
  `tc_siblings`; `:72` `TC_LOCK_TIMEOUT`; `:709-712` stamp/non-export.
- `scripts/test-all.sh:4216` — sibling refusal; `:1640` `run_suite`;
  `:4165` stale `900 s` comment; `:4125-4128` orphan-reaper report call site.
- `scripts/test-all-weight-drift.test.sh:355-469` — `build_sandbox`,
  `ENV_SCRUB`, `run_arm`; `:628-639` C8.
- `scripts/test-all-affected.test.sh:118,194-195` — `SANDBOX_SIBLINGS`
  pin idiom (precedent for FR-4).
- `plugins/soleur/test/lib/gitleaks-probe.sh:34-35` — `timeout`/`gtimeout`
  degrade idiom (extended for FR-3).
- `plugins/soleur/skills/archive-kb/scripts/archive-kb.sh` — slug arg,
  `--dry-run`, `git mv` semantics.
- ADRs: ADR-133 (lock + contention substrate; addendum target), ADR-196
  (measured-condition refusal), ADR-187 (nested-runner rc semantics), ADR-183.

### Related Work

- Issues: #7697, #10209, #8163 (closed by this plan); #7553 (sibling
  refusal), #7545 (timeout raise + heartbeat), #8579 (ticket queue), #7869
  (run ceiling), #8322 (affected-mode exemption), #10094/#10191 (C8
  surface), #8135 (ceiling surface).
- Learnings: `2026-08-13-a-lower-bound-cannot-tell-a-measurement-from-a-constant.md`,
  `2026-09-20-every-defect-in-my-fix-was-a-sentence-i-could-have-run.md`,
  `2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`,
  `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`.
