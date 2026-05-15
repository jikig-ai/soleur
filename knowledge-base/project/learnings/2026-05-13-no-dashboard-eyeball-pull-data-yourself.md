---
title: No dashboard-eyeball — pull data yourself
date: 2026-05-13
category: best-practices
tags: [agents-md, hard-rule, dashboards, observability]
pr: 3356
issue: 3372
---

# Learning: When a check returns a technical signal that needs interpretation, never punt to operator dashboard-watching

This learning file backs the AGENTS.core.md rule `[id: hr-no-dashboard-eyeball-pull-data-yourself]`. The body in the rule is trimmed for byte-budget (≤600 B per `cq-agents-md-why-single-line`); the full evidence and prescription live here.

## The rule

When a monitoring/recovery/health check returns technical signal that needs interpretation, never punt to operator dashboard-watching or "human-judgment" if the underlying data is API-accessible. Follow `hr-exhaust-all-automated-options-before` to pull readings via Management APIs (Supabase `/database/query`, Vercel, Cloudflare, Sentry), MCP tools, or CLIs, then make the close/escalate call yourself.

## Templates that violate the rule

Any template (in a runbook, scheduled-workflow output, ship-skill post-merge checklist, etc.) that concludes with one of these phrases on a technical metric is a workflow violation:

- "check the dashboard"
- "eyeball the gauge"
- "operator decision: is the curve recovering?"
- "human-judgment recovery curve evaluation"

Replace each with:

1. A **concrete query** that pulls the same data (`pg_stat_io`, `pg_stat_statements`, `/api/v1/metrics`, etc.).
2. A **deterministic verdict rule** (e.g., "if `idx_blks_read = 0` AND `pg_stat_io.reads = 0` over 60 s → close; else escalate").

Subjective calls (design taste, strategy, prioritization) stay human. **Interpretation of technical signal (recovery curves, IOPS budgets, error rates, latency percentiles) does NOT qualify as human judgment** — if the data is API-accessible, the verdict rule must be deterministic.

## API surfaces (non-exhaustive)

| Class | Surface |
|---|---|
| Postgres internals | `pg_stat_io`, `pg_stat_statements`, `pg_stat_database`, `pg_stat_activity` |
| Supabase | `/database/query` (Management API), MCP server queries |
| Vercel | Project metrics endpoints |
| Cloudflare | Analytics GraphQL, Workers metrics |
| Sentry | Events, sessions, performance |
| App-level | Anything emitted by `reportSilentFallback` / structured logger |

If the metric you need lives on a dashboard but is not yet API-accessible, file a separate issue to expose the API; do not write a "check the dashboard" handoff in the meantime.

## Why

PR #3356's +7d Disk IO Budget check (2026-05-13) defaulted to "human-judgment recovery curve evaluation" when gauge state was fully derivable from `pg_stat_io` (0 IOPS over 60 s) + `pg_stat_statements` (`shared_blks_read: 0` across top-10 since reset). Soleur users should never be asked to interpret technical dashboards they don't understand — the LLM has the same access to the API the dashboard renders from, so it must make the call.

## Related

- AGENTS.core.md `[id: hr-exhaust-all-automated-options-before]`
- AGENTS.core.md `[id: hr-no-dashboard-eyeball-pull-data-yourself]` (this rule's home)
- `knowledge-base/project/learnings/2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale.md`

## Tags

category: hard-rule-evidence
module: AGENTS.core.md
