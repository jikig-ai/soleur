# TR3 Tool-Attempt Telemetry Collector — Brainstorm

**Date:** 2026-07-01
**Parent:** #5772 (lever 2, stays OPEN) · ADR-070 (two-tier fail-open) · #5768 (L3 phase scoping)
**Branch:** feat-tr3-tool-attempt-telemetry
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident

## What We're Building

A **fail-open telemetry collector** that records, per workflow phase (brainstorm/plan/work/review/ship)
and per session, **which available tools the agent actually attempts** on the web Concierge path.
Aggregated across real runs, the data empirically reveals the **never-needed-per-phase tool subset**
that lever 2 of #5772 (`disallowedTools` per-phase scoping) requires before it can safely ship.

This builds the **collector only**. Lever 2 itself is out of scope — it needs both the accumulated
data AND #5768's eval evidence, and `disallowedTools` is fail-CLOSED (a wrongly-denied tool is a
silent error to a paying user), so the subset must be identified **empirically, never guessed**.

**Key mechanism (settled):** availability is **static config** — `CANONICAL_DISALLOWED_TOOLS` +
`allowedTools` + `TOOL_TIER_MAP` (`tool-tiers.ts`). So:
> **never-needed-per-phase = available(static config) − attempted(observed via this collector)**

That is why we do NOT need to capture unknown/denied-tool attempts (the SDK-message-iterator
complexity the learnings flagged): PreToolUse seeing attempts at *available* tools is exactly the
observed side of the gap; the available side is computed from config.

## Why This Approach

Chosen: **standing aggregated-per-session collector, web-only, opt-in** (per operator decision
2026-07-01). Two SDK hooks share a module-level per-session accumulator:

- **PostToolUse(Skill)** — writes last-skill→phase into the accumulator (reuses the shipped
  `phase-surface-map` normalization from lever 1).
- **PreToolUse(\*)** — increments `{phase, tool_name}` counts. `tool_name` + phase ONLY, never
  `tool_input` (NO-ECHO invariant).
- **Flush** — one aggregated JSONB row per session at teardown (`SessionEnd`/runner for-await
  completion), ~1-5 writes/session.

**Sink = Supabase (aggregated row), NOT insert-per-call.** A PreToolUse hook fires hundreds of
times/session; insert-per-call ≈ 10-50k INSERTs/day on a hot path — the exact WAL hazard PR #5736
/ migrations 114-115 guard against. Aggregating in-memory and flushing one row/session collapses
that to negligible WAL. Better Stack rejected (no log-drain vendor exists → recurring-expense gate;
and Sentry breadcrumbs cannot aggregate-count "tool X in phase Y across N sessions"). This
reconciles the repo-research "use the observability sink" rec with the learnings "Supabase for
write-heavy aggregatable telemetry" rec: aggregate first (dodges the per-call volume), then the
Supabase row gives SQL-grade aggregation the analysis needs.

**Fail-open:** every collector I/O in try-catch; a flush failure `reportSilentFallback`s and never
blocks the turn. Never touches `disallowedTools`/`canUseTool`.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Capture point | PreToolUse(\*) hook + PostToolUse(Skill) for phase | PreToolUse sees attempts at available tools (incl. canUseTool-denied); phase needs session state |
| Sink | Supabase table, **one aggregated JSONB row/session** | Avoids WAL hazard of insert-per-call; SQL aggregation; no Better Stack vendor/quota |
| Data captured | `tool_name` + `phase` + pseudonymous `session_id` counts | NO-ECHO: never `tool_input`; `sanitizeToolNameForLog` on names |
| session_id | Telemetry-random, **no stored `auth.uid()` join** | CLO guardrail — keeps it pseudonymous, out of DSAR PII scope |
| Retention | Enforced TTL (~90d) via `pg_cron` purge | CLO guardrail — Supabase retains forever otherwise; purge job is a spec deliverable |
| Scope | **Web-only V1**; factor for CLI fast-follow | `disallowedTools` is the web restrictor; CLI already loads `.claude/` hooks |
| Enablement | New opt-in `enableToolAttemptTelemetry` arg (mirrors `enablePhaseSurfaceHint`) | Only the cc-Concierge path enables; legacy runner zero-change |
| Analysis consumer | Aggregation query written + tested **before** hook ships | Avoids a write-only ledger (learnings write-mostly rule) |
| #3722 subsumption | Design row schema to also serve #3722's attempt-log need | #3722 (merged) requires "Sentry log of attempted invocation" as promotion evidence — same capture |
| Architecture record | ADR under ADR-070 umbrella (insert-per-call rejection rationale) | Plan deliverable per `wg-architecture-decision-is-a-plan-deliverable` |

## Open Questions

- Exact aggregated-row schema (one row per session with a JSONB `{phase: {tool: count}}` map, vs
  one row per (session, phase)) — resolve at plan time against the analysis query shape.
- Whether the pseudonymous `session_id` needs an entry in `dsar-export-allowlist.ts` **exclusion**
  list (CLO: yes if it could ever join to a user; likely a no-op since it won't join — confirm).
- TTL value (90d proposed) and whether the `pg_cron` purge reuses an existing purge pattern
  (migration 103 `processed_github_events` 7-day retention is the precedent).

## User-Brand Impact

- **Artifact:** the TR3 tool-attempt telemetry collector (PreToolUse/PostToolUse hooks + aggregated Supabase sink).
- **Vector:** a mis-built collector that captures `tool_input` re-opens the log-injection/reflection surface; or a non-fail-open sink write that breaks a paying user's agent turn; or a per-call insert that degrades prod DB (WAL) for all users.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering, Legal, Product

### Engineering (CTO)

**Summary:** Build it — small-medium. Two SDK hooks sharing a per-session accumulator; Supabase
aggregated-row sink (reject insert-per-call on WAL grounds); web-only V1, opt-in arg. Availability
is static config so no unknown-tool capture needed. #3722 (merged) wants the same attempt-log —
design the schema to serve both; #3789 is orthogonal.

### Legal (CLO)

**Summary:** LOW-RISK with two guardrails: (1) pseudonymous `session_id` with no stored `auth.uid()`
join; (2) enforced TTL/purge (~90d, `pg_cron` if Supabase). No new Article 30 activity if
pseudonymous; add to `dsar-export-allowlist.ts` exclusion if any user-join risk. No-`tool_input`
invariant already covers injection/secrets.

### Product (CPO)

**Summary:** TRIM — the subset is a one-time analysis question, so don't over-build. Mitigated by
CTO's near-zero-cost aggregated-row design + writing the analysis query up front. Note lever 2 is
double-gated (data AND eval evidence); the collector's payoff is real but two gates deep.
