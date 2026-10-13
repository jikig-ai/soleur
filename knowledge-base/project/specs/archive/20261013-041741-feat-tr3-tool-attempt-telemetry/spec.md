---
title: TR3 tool-attempt telemetry collector (unblocks #5772 lever 2)
lane: cross-domain
brand_survival_threshold: single-user incident
parent_issue: 5772
adr: ADR-070
date: 2026-07-01
---

# TR3 Tool-Attempt Telemetry Collector

## Problem Statement

Lever 2 of #5772 (web per-phase `disallowedTools` scoping) is the genuinely surface-shrinking
lever, but it is fail-CLOSED: a wrongly-denied tool surfaces to a paying user as a silent "unknown
tool" error (`2026-05-13-claude-agent-sdk-canusetool-not-invoked-for-unknown-mcp-tools`). ADR-070's
binding two-tier rule therefore gates lever 2 "behind tool-attempt telemetry + eval evidence" — the
never-needed-per-phase tool subset must be identified **empirically from real runs, never guessed**.
No such telemetry exists today. This feature builds the **collector** that produces that data.

Framing (settled at brainstorm): availability is **static config** (`CANONICAL_DISALLOWED_TOOLS` +
`allowedTools` + `TOOL_TIER_MAP`), so **never-needed-per-phase = available(static) − attempted(observed)**.
Only the *attempted* side needs instrumentation.

## Goals

- G1. Record, per session and per workflow phase, which **available** tools the agent attempts on
  the web Concierge (cc-soleur-go) path, via fail-open SDK hooks.
- G2. Persist the data to a **queryable, aggregatable** sink so the never-needed-per-phase subset
  can be computed with a SQL query across N sessions.
- G3. Ship the **analysis query** (the consumer) alongside the collector, verified on real rows —
  not a write-only ledger.
- G4. Honour ADR-070's two-tier fail-open rule: additive/observability-only; never touch
  `disallowedTools`/`canUseTool`; hooks never throw into the SDK.

## Non-Goals

- N1. **Lever 2 itself** (the `disallowedTools` per-phase subset) — still gated on this data PLUS
  #5768's eval evidence. Tracked on #5772.
- N2. **Unknown/unregistered-tool-attempt capture** (SDK message-iterator instrumentation) — not
  needed: availability is static config, so the observed side only needs attempts at *available*
  tools, which PreToolUse sees. Revisit only if lever-2 mis-scope monitoring later needs it.
- N3. **CLI-side collection** — deferred to a fast-follow (factor the phase-map + accumulator so it
  can be reused). The CLI already loads `.claude/` hooks and is not the `disallowedTools` restrictor.
- N4. Any change to the `canUseTool` deny-by-default security floor.

## Functional Requirements

- FR1. A **PreToolUse(\*)** hook increments an in-memory per-session accumulator keyed by
  `{phase, tool_name}`. It records `tool_name` + phase ONLY.
- FR2. A **PostToolUse(Skill)** hook maps the invoked skill → phase (reusing the shipped
  `phase-surface-map` normalization) and writes the current phase into the shared accumulator, so
  FR1 attributes subsequent tool calls to the right phase.
- FR3. At session teardown (`SessionEnd` hook or the runner's for-await completion), the accumulator
  is flushed as **one aggregated JSONB row per session** into a new Supabase table (~1-5 writes/session).
- FR4. Enablement is opt-in via a new `enableToolAttemptTelemetry` arg in `buildAgentQueryOptions`,
  mirroring `enablePhaseSurfaceHint`. Only the cc-soleur-go Concierge path opts in; the legacy
  runner is zero-change.
- FR5. A committed, tested **analysis query** computes, per phase, the set of available tools with
  zero recorded attempts across all retained sessions (the never-needed candidate set).
- FR6. The row schema is designed to also satisfy #3722's "log of attempted invocation" promotion
  evidence for `mcp__soleur_platform__*` tools (avoid building a second attempt-logger).

## Technical Requirements

- TR1. **Fail-open:** every collector code path (accumulator, flush, DB write) is wrapped so a
  failure `reportSilentFallback`s (mirror-on-failure, debounced) and NEVER blocks or denies a tool
  call. Hooks return the empty/allow shape on any error, exactly like `phase-surface-hook.ts`.
- TR2. **NO-ECHO invariant:** `tool_input` is never read, logged, or persisted. `tool_name` is
  passed through `sanitizeToolNameForLog` (or equivalent) before serialization. Static message +
  error object only on the failure path.
- TR3. **No insert-per-call:** aggregation is in-memory; exactly one row per session is written.
  This is the WAL-safety requirement (precedent: PR #5736, migrations 114-115).
- TR4. **Pseudonymous `session_id`:** telemetry-random, with NO stored join to `auth.uid()`. If a
  join is ever added, the data inherits full personal-data (DSAR export + erasure) treatment.
- TR5. **Enforced retention:** a `pg_cron` purge job enforces a TTL (default 90d). Precedent:
  migration 103 (`processed_github_events` 7-day retention).
- TR6. **DSAR:** confirm whether the pseudonymous `session_id` needs a `dsar-export-allowlist.ts`
  **exclusion** entry (`worktree_write_lease` precedent); add it if any user-join risk exists.
- TR7. **Availability oracle:** the analysis query derives "available per phase" from static config
  (`CANONICAL_DISALLOWED_TOOLS`, `allowedTools`, `TOOL_TIER_MAP`), not from observation.

## Architecture Decision (plan deliverable)

Per `wg-architecture-decision-is-a-plan-deliverable`: capture an ADR under the ADR-070 umbrella
recording the **insert-per-call rejection** rationale (WAL hazard) and the aggregated-row +
static-availability-oracle design.

## Acceptance Criteria

- AC1. Enabling `enableToolAttemptTelemetry` on the cc path produces one aggregated row per session
  with `{phase: {tool_name: count}}`, `tool_input` absent everywhere.
- AC2. A forced flush failure does not fail the agent turn (fail-open test) and surfaces a
  debounced Sentry mirror.
- AC3. The analysis query runs against seeded rows and returns a per-phase never-needed candidate
  set (available-minus-attempted).
- AC4. WAL/write-count check: a multi-phase session produces ≤ a small constant number of INSERTs
  (not one-per-tool-call).
- AC5. Legacy (non-cc) runner path is byte-unchanged (opt-in arg defaults off).
- AC6. `pg_cron` purge job exists and is verified to delete rows older than the TTL.

## Refs

- Parent: #5772 (lever 2, stays OPEN) · ADR-070 (two-tier fail-open) · #5768 (L3 phase scoping)
- `apps/web-platform/server/agent-runner-query-options.ts` (hooks ~:203-242, `CANONICAL_DISALLOWED_TOOLS` ~:48, `enablePhaseSurfaceHint` precedent)
- `apps/web-platform/server/phase-surface-hook.ts` · `phase-surface-map.ts` · `tool-tiers.ts` (`TOOL_TIER_MAP`)
- `apps/web-platform/server/observability.ts` (`reportSilentFallback`, `mirrorWithDebounce`)
- Overlap: #3722 (merged, subsume its attempt-log) · #3789 (orthogonal)
