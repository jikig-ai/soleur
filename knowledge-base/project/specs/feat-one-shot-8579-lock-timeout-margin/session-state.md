# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-09-22-fix-tc-lock-timeout-fifo-queue-plan.md`
- Status: complete
- Plan artifact: complete (selector=branch; `## Acceptance Criteria` present)
- Scope verification: PASS — `git status --short` shows only untracked
  `knowledge-base/project/plans/2026-09-22-fix-tc-lock-timeout-fifo-queue-plan.md` and
  `knowledge-base/project/specs/feat-one-shot-8579-lock-timeout-margin/`. No source, workflow, or
  CHANGELOG edits. No product code was modified in this phase.

### Direction chosen

**FIFO/ticket queue in front of `tc_acquire`** (issue candidate 1), plus the
**detected-long-hold signal** (candidate 3, as `position=`/`LOCK_WAIT_OVERRUN` heartbeat fields).
**Gate-cost reduction (candidate 2) cut** — out of scope: it shrinks the margin proportionally but
cannot change the synchronized-expiry release shape; tracked by #8329 / #7454 item 1.

Rationale: any finite `TC_LOCK_TIMEOUT` below the 14,400 s runtime ceiling still has a synchronized
expiry (the 2026-08-19 ADR-133 addendum already records "not a value proven sufficient for the
contended tail"); an 8,070 s sibling hold was measured on 2026-09-22. Only ordering the waiters
changes the release shape. Design constraints honoured: never-abort (ADR-133 Decision 3), CI/kill-
switch exemptions, kernel-released tickets (no stale detection), no `flock -w` in the new path
(#7697), no edit to `session-state.sh` or `test-all.sh` (four suites pin the `tc_acquire "test-all"`
anchor).

### Premise / verification record

- `gh issue view 8579` read in full (required first step); issue OPEN, `meta/machinery`,
  milestone "Post-MVP / Later".
- Cited refs verified live: #7545 CLOSED (merge `5cf9761a48`), #7869 CLOSED (`2576c64fa7`),
  #6789 CLOSED, #7537 CLOSED, #7697 OPEN, #7454 OPEN, #8231 OPEN, #8329 OPEN, #7942 OPEN.
- `tc_acquire` contract read at `scripts/lib/test-contention.sh:942-1074`; `acquire_lock` rc=99
  semantics at `plugins/soleur/scripts/lib/session-state.sh` (`_acquire_lock_impl`).
- Pins discovered by grep (would have broken naively): `test-all-capacity-signal.test.sh:1073`
  AC14 pins `TC_LOCK_TIMEOUT` default > 2700 s; `test-contention.test.sh:900-921` asserts
  `LOCK_WAITING` absent on EVERY skip path; four suites pin the literal `tc_acquire "test-all"`;
  `work/SKILL.md` triage grep keys on `LOCK_CONTENDED` (so the queue-timeout escape still emits
  `LOCK_CONTENDED_PROCEEDING`).
- Open code-review overlap: queried 75 open `code-review` issues with `jq --arg` per edited file;
  one hit (#7942 names `test-all.sh` as a runner, not as an edit target) — acknowledged, not
  folded in.
- Cloud mode probe: `plugins/soleur/scripts/cloud-detect.sh` → `not-local:no-devin-env` → normal
  path.

## Deepen-Plan Phase
- Status: complete
- Ran against: the plan file above (in place).

### Halt gates (all PASS, none halted)

- 4.5 network-outage: fired on the `timeout` token; **inapplicable** (no network/SSH surface) —
  recorded in the plan's Hypotheses section, no telemetry emitted.
- 4.55 downtime/cutover: not triggered (no infra/deploy/DB-lock-class change).
- 4.6 user-brand impact: section present, threshold `aggregate pattern`, non-placeholder.
- 4.7 observability: `scripts/lib/test-contention.sh` is code-class → section required and present;
  all five fields populated; `discoverability_test.command` is a `grep` (allowlisted), <15 s;
  `expected_output` is three literal tokens.
- 4.8 PAT-shaped variable halt: regex sweep → zero hits.
- 4.9 UI-wireframe halt: no UI-surface file in Files to Edit/Create → pass-through.
- 4.10 encryption posture: prose trigger brushes the word "queue" → section present with a
  gate-status note (zero-payload flock anchors; no store, no connection).
- 4.11 guard contract: `python3 scripts/lint-guard-contract.py <plan>` → green
  (1 guard entry, mutation matrix 6 rows incl. reorder + window-internal rows).

### Verify-the-negative greps (run inline; results folded into the plan's Enhancement Summary)

- `fifo|ticket|queue` in the two lock libs → zero pre-existing machinery.
- `LOCK_QUEUE_*|TC_QUEUE_*|LOCK_WAIT_OVERRUN|queue.d` repo-wide → zero token collisions.
- `flock` call sites across `scripts/` and `plugins/soleur/scripts/` — surveyed for precedent
  (canonical shape is `_acquire_lock_impl`'s `exec {fd}>>` + `flock -w` + fd-assoc tracking; the
  plan's deviations — `flock -n` probes, scalar fd — are recorded in Risks).
- Re-read of declaration sites for every cited identifier (`_session_state_init_dirs`, `LOCK_DIR`,
  `TC_SESSION_STATE`, `_RUN_START_EPOCH`, `TC_LOCK_TIMEOUT`, `TC_RUNTIME_CEILING_S`).

### Reviewer / research fan-out

The skill's Task-subagent fan-out (Phases 2–5) is not spawnable inside this subagent context — no
Task tool exists here. Substituted inline: the halt gates above, the verify-the-negative sweeps,
the precedent-diff (recorded in `## Dependencies & Risks`), the ADR-corpus mechanism check
(Phase 0.6.4), and the plan-sharp-edges discipline applied during authoring (named-token
consistency sweep run — `LOCK_QUEUE_DEGRADED`/`LOCK_QUEUE_TIMEOUT`/`LOCK_WAIT_OVERRUN`/
`queue_timeout=1`/`TC_QUEUE_TIMEOUT` counts verified consistent). The `## Enhancement Summary`
section in the plan records the findings. The plan-review panel (`soleur:plan-review`) remains
available to the pipeline if a heavier review pass is wanted before `soleur:work`.

### Revisions folded in

1. `flock -w` banned from the new path entirely (was "short `-w` on `.alloc`" in the first draft) —
   #7697's masked-SIGALRM defect makes any new `-w` wait a liability; `.alloc` now uses `flock -n`
   + counted retry.
2. Queue-timeout escape keeps the `LOCK_CONTENDED_PROCEEDING` token (not a new proceed name) —
   `work/SKILL.md`'s post-run triage grep keys on `LOCK_CONTENDED`; a new token would have been
   invisible to it.
3. `LOCK_WAITING` left byte-identical (new info moved to a separate `LOCK_QUEUED` line) —
   `work/SKILL.md:1508` quotes the literal and three suites pin placement/absence.
4. `TC_LOCK_TIMEOUT` default untouched — AC14 in `test-all-capacity-signal.test.sh` pins it
   `> 2700`.
5. `_RUN_START_EPOCH`-before-`tc_acquire` recorded: queue wait is charged to the 14,400 s run
   ceiling; the ADR-133 addendum task now includes correcting that arithmetic.

### Errors
None blocking. `scripts/markdown-lint.sh` reports `knowledge-base/project/` is inside
`.markdownlintignore` — the plan file is exempt by scope, not by pass.

## Work Phase
- Status: complete (implementation + suite arms + docs landed; review next).

### What shipped

- `scripts/lib/test-contention.sh`: ticket machinery (`_tc_queue_dir`,
  `_tc_alloc_lock`/`_tc_alloc_unlock`, `_tc_ticket_sweep`, `_tc_ticket_mint`,
  `_tc_queue_is_head`, `_tc_queue_position`, `_tc_queue_wait`), `tc_acquire`
  restructured between `LOCK_WAITING` and `acquire_lock`, heartbeat extended
  with `overrun_s`/`position=`/`LOCK_WAIT_OVERRUN`. New knobs:
  `TC_QUEUE_TIMEOUT` (default `TC_LOCK_TIMEOUT`), `TC_QUEUE_POLL_S` (5).
  New tokens: `LOCK_QUEUED`, `LOCK_QUEUE_DEGRADED reason=`, `LOCK_QUEUE_TIMEOUT`,
  `queue_timeout=1` on the contended tail. `test-all.sh`/`session-state.sh`
  untouched.
- `scripts/test-contention.test.sh`: Phase 3b (T1–T12), `MIN_CASES` 128→150;
  157/157 green.
- `plugins/soleur/test/fixture-relative-assert.baseline.txt`: +1 row
  (`4 scripts/lib/test-contention.sh`) — the queue's `$LOCK_DIR`-rooted runtime
  writes are scanner-unresolvable residue; regenerated per protocol.
- `plugins/soleur/skills/work/SKILL.md`: heartbeat line shape + `position=`/
  `LOCK_WAIT_OVERRUN`, queue bound corrected to 7200 s, stall-vs-queue triage
  tokens.
- ADR-133: dated addendum (ticket order, `flock -n`-only probing per #7697,
  `TC_QUEUE_TIMEOUT`, corrected `_RUN_START_EPOCH` arithmetic, mixed-version
  caveat, sweep).

### Session errors / findings worth keeping

1. **`exec {fd}>>file 2>/dev/null` silences the calling shell's stderr
   permanently.** `exec` with only redirections applies ALL of them to the
   shell — the trailing `2>/dev/null` redirected the process's stderr, so every
   later `>&2` banner vanished while rc stayed 0. Fixed with brace-group
   scoping (`{ exec {fd}>>file; } 2>/dev/null`). (Corrected during review: the
   similar-looking `eval "exec ${fd}>&-" 2>/dev/null` in `session-state.sh` is
   NOT the same defect — there the `2>/dev/null` binds to the `eval` builtin
   and ends with it, while only the fd-close inside the evaluated string
   persists. No latent bug there.)
2. **fd inheritance holds tickets past owner death.** A `kill -9`'d waiter
   mid-`acquire_lock` leaves its `flock -w` child holding the ticket fd until
   the child's `-w` resolves (bounded by `timeout_s`); same for a trailing
   `sleep`. Documented in the lib's constraint block; the heartbeat subshell
   now closes its inherited ticket fd on entry. Test arms kill only waiters
   past the acquire call or in the queue stage.
3. **`flock -n` probes on ticket paths** — the suite's `await_held`/`flock -w0`
   probe idiom reused; `%08d` serials require `10#` in arithmetic compares
   (leading-zero octal error).

### Verification

- `bash scripts/test-contention.test.sh` — 157/157
- `bash scripts/test-all-capacity-signal.test.sh` — 80/80
- `bash scripts/lib/repo-write-boundary.test.sh` — 72/72
- `bash plugins/soleur/test/fanout-suite-scope.test.sh` — 36/36
- `bash plugins/soleur/test/fixture-relative-assert.test.sh` — 62/62 (post-regen)
- `bash plugins/soleur/test/fixture-env-adoption.test.sh` — 26/26

## Next step

`soleur:review` on PR #8596, then `soleur:qa`, `soleur:compound`, `soleur:ship`.
