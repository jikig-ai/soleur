# Interface Contract — feat-one-shot-9403-cost-tally

Plan: `knowledge-base/project/plans/2026-10-01-feat-pipeline-cost-tally-plan.md`
(read it for full context; AC1–AC11 are the binding acceptance list)

## File Scopes

| Agent | Files |
|-------|-------|
| Agent 1 (Code) | `plugins/soleur/scripts/pipeline-tally.sh` (new), `plugins/soleur/hooks/stop-hook.sh` (edit) |
| Agent 2 (Tests) | `plugins/soleur/scripts/pipeline-tally.test.sh` (new), `plugins/soleur/test/ralph-loop.test.sh` (edit — Guard 4 rows only) |

`plugins/soleur/test/components.test.ts` is OUT of Tier-0 scope — its sentinel
asserts SKILL.md call-forms that only exist after the sequential Phase 2a/2b
edits, so it lands in Phase 3.

## Public Interfaces

### `pipeline-tally.sh` (bash 3.2-safe, sources `scripts/lib/session-state.sh`)

Counter file: `<session-state-root>/counters/<slug>` where
`<slug> = _safe_worktree_name("$(git branch --show-current || echo HEAD)")` —
if `_safe_worktree_name` is not exported by the lib, implement the same
sanitization (non-`[a-zA-Z0-9._-]` → `-`). When `_session_state_root` resolves
to the `/tmp/soleur-session-state-orphan` fallback, append `-<repo-basename>` to
the counters dir. Flat `key=value` lines, rewritten wholesale under `with_lock`:

```
seats=0
ci_cycles=0
fix_rounds=0
agent_rounds=0
cap_seats=0        # 0 = unset
cap_ci_cycles=0
cap_fix_rounds=0
cap_agent_rounds=0
warned_seats=0   # level at which WARN first fired (lookahead ask included); 0 = none
warned_ci_cycles=0 / warned_fix_rounds=0 / warned_agent_rounds=0
capped=            # empty or one dim name
```

The ledger filename is `<sanitized-branch>-<sha1-6 of raw branch>` — the hash
suffix keeps `feat/x` and `feat-x` (which sanitize identically) on distinct
ledgers. A `run_id`/`started_at` pair was in an earlier draft; both were dropped
— staleness keys on file mtime (inactivity), not a written start time.

Subcommands (`tally` is the file's own basename; invoked as
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/pipeline-tally.sh" <cmd> …` — the
fully-qualified form every SKILL.md call-out carries):

- `init [--reset] [--branch <b>] [--max-seats N --max-ci-cycles N --max-fix-rounds N --max-agent-rounds N]`
  Idempotent MERGE: creates file if absent; preserves counters; merges caps.
  Prints `tally-init: <slug> <outcome>` — outcome ∈ `fresh | continued |
  reset | capped-reset | stale-reset | repaired`:
  - `continued` on a capped ledger keeps the latch (`continued capped=<dim>`);
    the next `gate` still STOPs — a bare init can never accidentally resume a
    capped run.
  - `capped-reset` = capped ledger + raised `--max-*` argv: clears latch AND
    `warned_*`, preserves counts. Beats `stale-reset` — an explicit raised cap
    is operator intent to resume THIS run; a bare init on the same stale file
    still takes `stale-reset`.
  - `stale-reset` = file mtime >24h (inactivity; every `gate` read and every
    write refreshes it, so a live multi-day run survives): fresh ledger.
  - `repaired` = existing file failed validation — rewritten clean (fail-open)
    with `SOLEUR_TALLY_ERROR reason=unreadable`; never misreported `continued`.
  Ratchet guard: without `--reset`, a `--max-*` LOWER than a persisted nonzero
  cap is refused (`cap-kept:` line, `<dim>=<kept>` tokens). Armed caps print as
  `armed: cap:<dim>=<n>` on every init. Sweeps sibling files >30d.
  Flag validation: `^[1-9][0-9]{0,9}$`; `--max-ci_cycles` aliases
  `--max-ci-cycles`. Rejects → `SOLEUR_TALLY_ERROR reason=bad-flag`, exit 0.
- `incr <dim> [n] [--branch <b>]` (`<dim>` ∈ seats|ci_cycles|fix_rounds|agent_rounds;
  `ci-cycles` accepted as alias → `ci_cycles`; `n` default 1, `^[0-9]{1,10}$`)
  Missing/unreadable file → stderr `SOLEUR_TALLY_ERROR reason=missing-file`,
  stdout `UNKNOWN`, exit 0 — NEVER auto-creates. `--branch` posts to another
  branch's ledger (fleet-skill item attribution).
- `show [--branch <b>]` — absent/unreadable file → `UNKNOWN`; else prints
  `tally: seats=N ci_cycles=N fix_rounds=N agent_rounds=N`, a `cap:<dim>=<n>`
  token line when caps are set (the stop-hook floor consumes this), and, when
  set, `warned:<dim>=<at>` / `capped:<dim>=<cap>` annotations.
- `gate <dim> [n] [--branch <b>]` — reads `cap_<dim>` from the FILE (never argv).
  Verdicts on stdout: `STOP` when `capped` is set (any dim) or count ≥
  `cap_<dim>` (cap > 0, sets `capped=<dim>` when empty — sticky) or, with
  lookahead `n`, `count+n > cap` (STOP WITHOUT latching — a smaller ask may
  still fit); `WARN` when `count+n` ≥ `ceil(cap*0.8)` (records `warned_<dim>`
  at the projected level on first fire); `OK` otherwise (incl. cap unset).
  A successful `gate` refreshes the ledger mtime — a polling caller is ledger
  activity. Substrate failure (missing file, no flock, unreadable,
  `SOLEUR_DISABLE_SESSION_STATE=1`) → stdout `UNKNOWN` +
  stderr `SOLEUR_TALLY_ERROR reason=<k>`. Exit 0 always.
- `selfcheck` — prints `SOLEUR_TALLY_OK` on stdout, exit 0, writes NOTHING
  (safe in a read-only sandbox with tmpfs HOME).
- Fail-open invariant: every subcommand exits 0 even on internal error
  (the sole refusal is the xtrace guard, exit 78 — a refusal, not a failure);
  errors surface as `SOLEUR_TALLY_ERROR reason=<k>` on stderr.

### `stop-hook.sh` edit (Guard 4 — ralph-loop floor)

Inside `plugins/soleur/hooks/stop-hook.sh`, BEFORE the `{"decision":"block"}`
emit path: run `pipeline-tally.sh show` and parse its stdout (`tally:` counts,
`cap:<dim>=<n>` tokens, `capped:<dim>=<cap>`) — the hook NEVER resolves or
reads the ledger file, so there is exactly one path resolver. Floor fires
when `capped:<dim>` is latched OR any count ≥ its `cap:<dim>` (catches a latch
that never got set — a skipped gate, an UNKNOWN gate): exit 0 WITHOUT emitting
`block`, print `SOLEUR_TALLY_CAPPED dim=<d> cap=<n>` + a resume hint
(`pipeline-tally.sh init --max-<dim> N` — `capped-reset` preserves counts;
`--reset` is deliberately NOT suggested) to stderr, and append a
`budget-capped: <dim>=<count>/<cap>` marker to the ralph state file.
Absent/corrupt/UNKNOWN output → unchanged behavior (fail-open in both
directions; never blocks FOR the tally). **Coverage boundary:** the floor
runs only inside a ralph-loop session on a harness whose Stop hook fires —
skill call-outs and the components.test.ts sentinel are the enforcement on
every other path; `SOLEUR_TALLY_CAP_IGNORED` in the PR body is the detector
for an ignored verdict.

### `write-budget-marker.sh`

Helper for the ship/merge-pr Phase-7 poll fence: `write-budget-marker.sh <dim>`
appends `status: budget-capped` + `budget-capped: <dim>=<count>/<cap>` + a
resolvable `resume:` line to `knowledge-base/project/specs/<sanitized-branch>/
session-state.md` — the same classified-stop shape the skill call-outs write —
then exits 0 unconditionally (fail-open). Extracted so the byte-mirrored poll
fence dispatches one implementation instead of duplicating the show-parse +
printf in both files; the `session-state.md` fixture token lives in its body
and in the fence's gate comment.

### Exit/stdout discipline

`selfcheck` output is exactly `SOLEUR_TALLY_OK`. All other stdout lines are
`tally…`/`tally-init:`/`armed:`/`cap-kept:`/`UNKNOWN`/verdict tokens only —
no prose decoration, no `$`/`USD`/`cost_usd` anywhere.
