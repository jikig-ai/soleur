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
warned_seats=0   # at-count recorded when WARN first fires; 0 = none
warned_ci_cycles=0 / warned_fix_rounds=0 / warned_agent_rounds=0
capped=            # empty or one dim name
run_id=<ts>
started_at=<epoch>
```

Subcommands (`tally` is the file's own basename; invoked as
`bash …/pipeline-tally.sh <cmd> …`):

- `init [--reset] [--max-seats N --max-ci-cycles N --max-fix-rounds N --max-agent-rounds N]`
  Idempotent MERGE: creates file if absent; preserves counters; merges caps.
  Auto-RESET (fresh ledger, same effect as `--reset`) when the file carries a
  non-empty `capped` OR `started_at` older than 24h — UNLESS `--reset` already
  given (same outcome). After auto-reset, `gate` verdicts come from the fresh
  file. Sweeps sibling files in `counters/` with mtime >30 days. Prints
  `tally-init: <slug> [reset|capped-reset|stale-reset|fresh|continued]`.
  Flag validation: `10#`-normalize; reject non-numeric, negative, `0` with
  `SOLEUR_TALLY_ERROR reason=bad-flag` on stderr and exit 0 (fail-open).
- `incr <dim> [n]` (`<dim>` ∈ seats|ci_cycles|fix_rounds|agent_rounds;
  `ci-cycles` accepted as alias → `ci_cycles`; `n` default 1, `10#` normalized)
  Missing/unreadable file → stderr `SOLEUR_TALLY_ERROR reason=missing-file`,
  stdout `UNKNOWN`, exit 0 — NEVER auto-creates.
- `show` — absent file → `UNKNOWN`; else prints
  `tally: seats=N ci_cycles=N fix_rounds=N agent_rounds=N` and, when set,
  `warned:<dim>=<at>` / `capped:<dim>` annotations on a second line.
- `gate <dim>` — reads `cap_<dim>` from the FILE (never argv). Verdicts on
  stdout: `STOP` when `capped` is set (any dim) or `<dim>` count ≥ `cap_<dim>`
  (cap > 0); `WARN` when count ≥ `ceil(cap*0.8)` (records `warned_<dim>`);
  `OK` otherwise (incl. cap unset). On `STOP` also sets `capped=<dim>` if empty.
  Substrate failure (missing file, no flock, unreadable) → stdout `UNKNOWN` +
  stderr `SOLEUR_TALLY_ERROR reason=<k>`. Exit 0 always.
- `selfcheck` — prints `SOLEUR_TALLY_OK` on stdout, exit 0, writes NOTHING
  (safe in a read-only sandbox with tmpfs HOME).
- Fail-open invariant: every subcommand except `selfcheck` exits 0 even on
  internal error; errors surface as `SOLEUR_TALLY_ERROR reason=<k>` on stderr.

### `stop-hook.sh` edit (Guard 4 — Claude-only floor)

Inside `plugins/soleur/hooks/stop-hook.sh`, BEFORE the `{"decision":"block"}`
emit path: resolve `<git-common>/soleur-session-state/counters/<slug>` for the
current branch (`git branch --show-current`, `_safe_worktree_name`-equivalent
slug — the hook already sources `scripts/resolve-git-root.sh` for
`$GIT_COMMON_ROOT`; replicate the sanitize inline or via the session-state lib
if already sourced — do NOT add a heavy dependency). If the file exists and
greps `^capped=.` (non-empty value): exit 0 WITHOUT emitting `block` and print
`SOLEUR_TALLY_CAPPED dim=<d> cap=<n>` + a one-line resume hint to stderr.
Absent/corrupt/unreadable file → unchanged behavior (fail-open; never blocks
FOR the tally). `init --reset` clearing `capped` restores normal blocking.

### Exit/stdout discipline

`selfcheck` output is exactly `SOLEUR_TALLY_OK` (substring-matched by
preflight Check 10). All other stdout lines are `tally…`/`UNKNOWN`/verdict
tokens only — no prose decoration, no `$`/`USD`/`cost_usd` anywhere.
