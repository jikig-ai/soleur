# Learning: a set-only state flag with no reader/clearer is a cosmetic guard; and don't conflate execution surfaces

## Problem

Planning the L5 runaway-guard (#5767), the 5-agent plan-review panel found two structural defects that
every prior phase (issue author, brainstorm, plan draft) missed — both invisible without reading the code
that *consumes* a piece of state, not just the code that *writes* it.

1. **`runtime_paused_at` is a write-only flag.** The BYOK cap RPC (`migrations/061`) sets
   `users.runtime_paused_at` when a founder trips their rolling-1h cost cap. The whole feature was framed
   around "the cap already halts, just make it notify." But a repo-wide grep found **zero readers and zero
   clearers** of the column: (a) the RPC trips `kill_tripped` only on the `NULL → set` *transition*
   (`IF v_paused_at IS NULL AND ...`), so an *already-paused* founder's next spawn gets
   `kill_tripped = false` and **keeps spending**; (b) nothing ever clears the flag, so "operator resume"
   had no implementation. The pause was **cosmetic** — window-clear ≈ silent auto-resume, the exact
   failure the feature existed to prevent.

2. **Surface conflation.** The plan put a web doom-loop counter in `routine_run_progress`. But that table
   is written **exclusively** by the cron substrate (`spawnClaudeEval`, ADR-077 §2); the web leader loop
   (`agent-on-spawn-requested.ts`) is a *different* Inngest function that never touches it and uses
   `action_sends`. The counter had nowhere to live — the plan was unimplementable as drawn. The same
   conflation made the cost cap blind to crons: crons burn the BYOK key but write nothing to
   `audit_byok_use`, so no dollar cap can see them.

## Solution

The 5-agent panel (DHH + Kieran + code-simplicity + architecture-strategist + spec-flow) at
single-user-incident threshold cut the 4-PR train to a single safety-floor PR: **fix the pause** (add a
spawn-entry reader-gate that refuses when paused, an operator-resume clearer, and a set-never-clear
contract; make the RPC return `kill_tripped` while paused, not just on transition) + **notification** +
legal/ADR reconciliation. The 24h window, doom-loop, estimate, and resume apparatus were deferred as
honestly-scoped follow-ups; the cron cost-blindness became the top-priority follow-up (#5902).

## Key Insight

- **Writing a state flag is necessary but not sufficient — a guard is only real if something READS it to
  enforce and something CLEARS it to recover.** When a plan leans on an existing state column
  (`*_paused_at`, `*_locked`, `is_disabled`, `killed_at`), grep for its **readers** and **clearers**, not
  just its writer. A set-only flag with no consumer is a cosmetic guard: it looks like protection in the
  schema and does nothing at runtime. Also check *when* the writer fires — a transition-only trip
  (`IF old IS NULL AND ...`) silently stops re-enforcing once the flag is already set.
- **Before targeting a durable table/column, grep which function writes it.** Two autonomous surfaces here
  (leader loop → `action_sends`; cron substrate → `routine_run_progress`) own different tables; a plan
  that puts state in the wrong one is unimplementable, and a cap that sums one surface's ledger is blind to
  the other. "The supervisor journals runs" is not "*this* supervisor journals *this* run."
- **Re-verify the premise against code at every phase, not against the prior phase's artifact.** Brainstorm
  found "the per-spawn ceiling exists"; plan-time ADR reading found "the per-founder 1h cap exists"; the
  review found "the pause the cap sets doesn't actually block." Each layer of verification against live
  code shrank the feature. See [[2026-07-01-brainstorm-read-code-to-resolve-agent-infra-disagreement-and-tos-prose-drift]].

## Session Errors

1. **Plan drafted the web doom-loop counter into `routine_run_progress` (cron-only table).** The brainstorm
   research (CTO/repo-research) suggested it as the counter store without distinguishing the two surfaces.
   Recovery: cut PR-C; if revived, the counter goes in `action_sends`. **Prevention:** grep the writer of a
   durable table before targeting it in a plan.
2. **Scratchpad directory absent twice** (`cat >` failed). Recovery: `mkdir -p`. **Prevention:** one-off;
   mkdir the scratchpad before first write.

## Tags
category: workflow-patterns
module: plan
