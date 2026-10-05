# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-07-feat-per-workflow-agent-cost-observability-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

- Initial commit blocked by `markdown-lint` pre-commit hook (9 violations across plan, tasks,
  decision-challenges, copy spec). All fixed; re-commit passed every hook.
- `plugin:github:github` MCP server failed to connect (bad Authorization header, reported at
  session start). Non-blocking — all GitHub reads went via the `gh` CLI.
- Supabase MCP not connected. Non-blocking — schema facts came from migration source; the
  `ROLLUP` aggregate was verified by a review agent executing it on live PG17.6 and PG16.
- No CWD mismatch; verified on first tool call.

### Decisions

- **Scope is aggregation + exposure only.** `conversations.active_workflow` (migration 032)
  already co-exists with `total_cost_usd` on one row — independently verified at
  `apps/web-platform/server/conversation-routing.ts:56` and the
  `conversations_active_workflow_chk` CHECK constraint. No capture, no new table, no column,
  and nothing on the `audit_byok_use` WORM ledger (its cent-rounding makes it the wrong cost
  source anyway).
- **Cut the ADR-108 log-marker half in full** after simplicity review showed it was a 90-day
  lossy copy of a source Postgres holds exactly and forever. Removed 12 of 17 edited files,
  the ADR-108 amendment, and an entire type-widening obligation. Fleet-wide view is one
  documented SQL query.
- **One `ROLLUP` statement returns buckets AND grand total**, with `sum_user_mtd_cost` as a
  sequential fallback only. Two statements are two MVCC snapshots; a per-turn cost increment
  landing between them would break the sum under a UI promising "match to the cent".
- **Per-agent is NOT delivered → PR uses `Ref #1055`, not `Closes`.** `SDKResultMessage`
  carries no agent identity, and leader grain is a constant on the dominant path. Recorded as
  a User-Challenge rather than silently accepted.
- **Attribution is conversation-grain, first-Skill-wins** — a declared, disclosed limitation
  with a worked example in UI copy, not turn-grain (which reopens a rejected non-goal).

### Scope verification (one-shot Step 2)

Diff vs merge-base touched no product code. Out-of-`plans/specs` files are all legitimate
plan-phase outputs: the Phase 3.55 `.pen` wireframe + 7 screenshots, the hook-generated
`knowledge-base/INDEX.md`, and an edit to the pre-existing
`specs/feat-restore-byok-usage-dashboard/copy.md` (same "API Usage" section being extended).

### Collision re-probe (post-plan)

Plan frontmatter `issue: 1055`, `refs: 1055`. No new refs introduced by planning; #1055 was
already cleared at Step 0a.5 (OPEN, no linked PRs, two body-probe hits discriminated as
citations — neither touches `apps/web-platform`).

### Components Invoked

`soleur:plan`, `soleur:deepen-plan`, `soleur:gdpr-gate` · Explore x2, repo-research-analyst,
learnings-researcher, functional-discovery · CTO, CFO, CLO, CPO, spec-flow-analyzer,
ux-design-lead, copywriter · code-simplicity-reviewer, architecture-strategist,
kieran-rails-reviewer, scoped advisor (`model: fable`) · Pencil MCP (wireframe), `gh` CLI,
`lint-infra-no-human-steps.py`, `lint-guard-contract.py`, deepen-plan halt gates 4.5-4.11
