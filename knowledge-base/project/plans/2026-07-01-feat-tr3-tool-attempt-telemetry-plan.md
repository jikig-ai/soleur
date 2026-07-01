---
title: TR3 tool-attempt telemetry collector
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5843
parent_issue: 5772
adr: ADR-070 (amend — no new ADR; 071/072/073 already exist)
date: 2026-07-01
---

# TR3 Tool-Attempt Telemetry Collector — Plan

_Revised 2026-07-01 after 3-agent plan-review (DHH, Kieran, code-simplicity). Kieran surfaced 3
CRITICAL correctness defects + a value linchpin; all folded in below._

## Overview

Build a fail-open, web-only, opt-in collector that records **which available tools the agent
attempts per workflow phase** on the cc-Concierge path, aggregated one-row-per-session into a
Supabase table, so the never-needed-per-phase subset can be computed empirically to unblock #5772
lever 2. Design from the 2026-07-01 brainstorm; spec `feat-tr3-tool-attempt-telemetry/spec.md`.

Core identity: **never-needed-per-phase = available(per-path config) − attempted(observed)**. See
CRITICAL-1 below for the corrected definition of `available`.

## Research Reconciliation — Spec vs. Codebase (plan-review verified)

| Claim | Reality (verified) | Plan response |
|---|---|---|
| "#3722 (merged) wants the same attempt-log" | **#3722 OPEN**; merged piece is `tool-tiers.ts` (sibling #3720) | Reframed: #3722 is a live sibling that *may* reuse the data. FR6 dropped as a scope constraint (simplicity). |
| `available = TOOL_TIER_MAP + allowedTools − CANONICAL_DISALLOWED_TOOLS` | **Both sources wrong for cc** (CRITICAL-1). `TOOL_TIER_MAP` = `mcp__soleur_platform__*` only (`tool-tiers.ts:20-137`); cc registers `mcpServers:{}` (`cc-dispatcher.ts:2441,:304`). cc `allowedTools` = auto-approve subset (`cc-dispatcher.ts:1099-1113`), not the available surface. | `available` = SDK built-in default toolset − (`CANONICAL_DISALLOWED_TOOLS` ∪ cc `[Edit,Write]` at `cc-dispatcher.ts:2452`) + actually-registered MCP tools, computed per-path. |
| Flush at `agent-runner.ts:756,960` | **Wrong runner** (CRITICAL-3). cc runs through `soleur-go-runner.ts`; abort-covering chokepoint is `closeQuery()` (`:1972`). | Flush in `closeQuery`. |
| Key accumulator on hook `session_id` | **Re-identifiable** (CRITICAL-2). `BaseHookInput.session_id` (SDK) is UNIQUE-indexed to `user_id` (`028_conversations_user_id_session_id_unique.sql:8`). | Mint a fresh `crypto.randomUUID()` in the per-query closure; never let the SDK session_id reach the table. |
| ADR-071 (new) | **Filename collision** — `ADR-071-l1-constraint-gates.md` exists (also 072/073). | Amend ADR-070; no new ADR. |

## User-Brand Impact

**If this lands broken:** a stalled/errored agent turn on cc (if a write isn't fail-open), or
prod DB latency for all users (if writes are per-tool-call).
**If this leaks:** `tool_input` in logs/Sentry (injection/secrets) — closed by NO-ECHO; or a
`session_id` joinable to `auth.uid()` — closed by the **closure-minted random id** (CRITICAL-2).
**Brand-survival threshold:** single-user incident → `requires_cpo_signoff: true` (CPO carry-forward);
`user-impact-reviewer` at review time.

## Domain Review
**Domains relevant:** Engineering, Legal, Product (carry-forward from brainstorm `## Domain Assessments`).
CTO: build, small-medium, aggregated-row, web-only. CLO: LOW-RISK — pseudonymous session_id + enforced
pg_cron TTL. CPO: TRIM (one-time analysis; mitigated by throwaway analysis script). **Product/UX Gate:**
none — no UI surface.

## Architecture Decision (ADR/C4)
### ADR — amend ADR-070 (no new file; 071 is taken)
Add an amendment section to `ADR-070-l3-phase-tool-scoping-two-tier-fail-open.md` recording: (a)
insert-per-call rejection (WAL, PR #5736 / migrations 114-115), (b) aggregated in-memory→one-row-per-session,
(c) static-availability-oracle (available from config, not observation → no SDK-iterator unknown-tool capture),
(d) closure-minted pseudonymous id.
### C4 views
Checked all three `.c4` files. DB is coarse-grained (`supabase = database`, `model.c4:147`); `tool_attempts`
adds no element; write edges `engine/api -> supabase` exist (`:241,:260`). One falsified line: `model.c4:32`
hook enumeration — add the tool-attempt hook. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Infrastructure (IaC)
Migration-only (new table + pg_cron purge) via `web-platform-release.yml#migrate` on merge. No SSH, no
dashboard, no new vendor/secret/Terraform. Per-file `psql --single-transaction` (verified via `run-migrations.sh`);
no `CREATE INDEX CONCURRENTLY`.

## Observability

```yaml
liveness_signal:
  what: aggregated tool_attempts row inserted per closed cc query
  cadence: per closeQuery (~1 row/conversation-session)
  alert_target: none (analytics, not health) — absence is not an incident
  configured_in: apps/web-platform/server/tool-attempt-telemetry.ts (flush at closeQuery)
error_reporting:
  destination: Sentry via reportSilentFallback + pino (mirrorWithDebounce 5-min dedup)
  fail_loud: false (fail-open — never surfaces to user / never blocks a turn)
failure_modes:
  - mode: flush DB write fails
    detection: reportSilentFallback op="tool-attempt-telemetry:flush"
    alert_route: Sentry (debounced); non-paging
  - mode: hook throws mid-session
    detection: try-catch returns empty/allow; mirrorWithDebounce
    alert_route: Sentry (debounced); non-paging
logs:
  where: pino stdout (Better Stack) — failure path only; NO success-path per-call logging
  retention: Better Stack plan window (failure path); rows purged by pg_cron TTL (~90d)
discoverability_test:
  # Runnable, ssh-free pre/post-merge probe: an UNAUTHENTICATED PostgREST GET
  # against the table must be denied (proves the anon/authenticated default-deny
  # RLS posture — CRITICAL-2 — since tool_attempts is service-role-only).
  command: curl -sS -o /dev/null -w "%{http_code}\n" --max-time 10 https://api.soleur.ai/rest/v1/tool_attempts
  expected_output: "401"
  # Post-deploy ANALYTICS check (the actual data verification, AC9; run once):
  #   (via mcp__plugin_supabase_supabase__execute_sql) select count(*), max(created_at)
  #   from tool_attempts where created_at > now() - interval '1 day'  → non-zero after cc-sessions run
```

## Implementation Phases

### Phase 0 — Preconditions + VALUE-LINCHPIN GATE (verify, no code)
- **0.1 (HIGH-4) — RESOLVED 2026-07-01 (verdict A for the cc path; feature is buildable).** Code-trace
  confirmed: on the cc-soleur-go path (unconditional prod default since Stage 8/#3270), the SDK **Skill**
  tool runs the routed sub-skill (brainstorm/plan/work/review) within the **same subprocess/`query()`**, and
  its Bash/Edit/Grep/Write calls **route through the parent query's `options.hooks`** — evidence:
  `agent-runner-query-options.ts:212-214` (subagent tool calls currently route through parent `canUseTool`),
  and the sandbox PreToolUse matcher already includes `Write`/`Edit` (tools only sub-skills can request).
  Agent-tool sub-agents (domain leaders/research) on the cc path also route through parent hooks. The
  separate `agent-runner.ts startAgentSession` (verdict B) is the **legacy null-`active_workflow` path**,
  which `soleur-go-runner.ts` never calls — NOT our target. ⇒ A PreToolUse hook on the cc query captures real
  per-phase tool usage. **Also confirmed:** SDK `PreToolUse` hooks fire at tool-execution time, distinct from
  `state.events.onToolUse` (which only sees the router's own `assistant` messages) — so the hook is NOT
  subject to the `msg.type==="assistant"` guard and DOES see sub-skill tool calls.
- 0.2 Confirm the abort-covering flush chokepoint `closeQuery()` (`soleur-go-runner.ts:1972`) fires once per
  ActiveQuery even across reused turns (`:2496`) → one row/session.
- 0.3 Confirm a wildcard/empty PreToolUse matcher captures `Skill`/`Task`/`mcp__*` (shipped hooks use narrow
  matchers, `agent-runner-query-options.ts:204-211`); pick the matcher that captures the full surface.
- 0.4 Enumerate the SDK built-in default toolset (the real `available` universe) from
  `@anthropic-ai/claude-agent-sdk/sdk.d.ts`; define `available(cc)` = built-ins − (`CANONICAL_DISALLOWED_TOOLS`
  ∪ cc `[Edit,Write]`) + registered MCP.

### Phase 1 — Migration: table + pg_cron purge
- `apps/web-platform/supabase/migrations/<NNN>_tool_attempts.sql`:
  `tool_attempts(id uuid pk default gen_random_uuid(), created_at timestamptz default now(), counts jsonb not null)`
  — one aggregated row/session; `counts` = `{ "<phase|unrouted>": { "<tool_name>": <int> } }`. **No session_id
  column that could join to a user** (CRITICAL-2); the row is anonymous per-session. RLS service-role-only.
- pg_cron purge `< now() - interval '90 days'` (mirror `103_github_events_retention_7day`); guarded
  `cron.unschedule` `DO` block. `.down.sql` drops table + unschedules.

### Phase 2 — Collector module (closure accumulator + ONE PreToolUse hook + flush) [merged 2+3]
- `apps/web-platform/server/tool-attempt-telemetry.ts` exports a **factory** `createToolAttemptCollector()`
  (mirrors `createPhaseSurfaceHook()`): returns `{ preToolUseHook, flush }` both closing over ONE per-query
  object `{ randomId: crypto.randomUUID(), phase: "unrouted", counts }` (HIGH-5 — no module-level Map, no SDK
  session_id).
- **Single PreToolUse hook, phase tracked on the way IN (off-by-one fix — the trace showed PostToolUse(Skill)
  fires AFTER the routed skill runs, misattributing that skill's own tools to the PREVIOUS phase):**
  - When `tool_name === "Skill"`: `phase = skillToPhase(tool_input.skill)` — reading the skill-NAME enum from
    `tool_input.skill` is the exact safe normalization the shipped lever-1 hook uses (a known map key, not
    free-form content); this is the sole permitted `tool_input` read and does NOT violate NO-ECHO. `skillToPhase`
    is a shared helper extracted from `phase-surface-hook.ts` (DHH-2).
  - Otherwise: `sanitizeToolNameForLog(tool_name)` then `counts[phase][tool]++`. Tools before the first
    `Skill` land under `"unrouted"` (HIGH-6). Never read/persist `tool_input` for non-Skill tools.
- `flush()` builds one JSONB row, inserts, wrapped in try-catch → `reportSilentFallback(err,
  {feature:"tool-attempt-telemetry", op:"flush"})`; never throws.

### Phase 3 — Wire opt-in + flush site
- `agent-runner-query-options.ts`: add `enableToolAttemptTelemetry?: boolean`; when set, register the
  collector's SINGLE PreToolUse hook as a **separate, gated hook entry** with a matcher that captures the full
  surface incl. `Skill` (do NOT modify the sandbox `PreToolUse` matcher; mirror how `enablePhaseSurfaceHint`
  conditionally adds its hook at `:239-241`). No PostToolUse(Skill) hook needed for telemetry (phase is tracked
  on the PreToolUse(Skill) way-in).
- `soleur-go-runner.ts`: call `collector.flush()` from `closeQuery()` (`:1972`) — the single abort-covering
  teardown chokepoint (CRITICAL-3).
- `cc-dispatcher.ts`: opt in via the new arg. Legacy runner passes nothing → byte-unchanged (AC5).

### Phase 4 — Analysis (throwaway, not a committed tested artifact) [simplicity]
- A ~15-line throwaway TS script (run once, not committed as product): imports the config to build
  `available(cc)` (per 0.4), runs one `execute_sql` `jsonb_object_keys` query for `attempted`, prints the
  per-phase set difference. Paste the result into #5772. No committed `.sql`, no seeded-row test suite.

### Phase 5 — ADR-070 amendment + C4 + tests
- Amend ADR-070; edit `model.c4:32`; run C4 tests.
- Tests (`test/tool-attempt-telemetry.test.ts`): fail-open (forced flush failure → turn survives + debounced
  mirror); no-`tool_input` (grep + unit); WAL write-count (multi-phase session → 1 insert at closeQuery);
  `"unrouted"` bucket; pg_cron purge. `agent-runner-query-options.test.ts`: hooks present when enabled, absent
  by default (AC5 drift snapshot).

### Phase 6 — Verify
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; `./node_modules/.bin/vitest run` the new suites;
  full `package.json scripts.test`; C4 tests.

## Files to Create
- `apps/web-platform/server/tool-attempt-telemetry.ts`
- `apps/web-platform/supabase/migrations/<NNN>_tool_attempts.sql` (+ `.down.sql`)
- `apps/web-platform/test/tool-attempt-telemetry.test.ts`

## Files to Edit
- `apps/web-platform/server/agent-runner-query-options.ts` (gated hooks + arg)
- `apps/web-platform/server/soleur-go-runner.ts` (flush at `closeQuery`)
- `apps/web-platform/server/cc-dispatcher.ts` (opt in)
- `apps/web-platform/server/phase-surface-hook.ts` (extract shared `skillToPhase`)
- `apps/web-platform/test/agent-runner-query-options.test.ts` (hooks present-when-enabled / absent-by-default)
- `knowledge-base/engineering/architecture/decisions/ADR-070-l3-phase-tool-scoping-two-tier-fail-open.md` (amendment)
- `knowledge-base/engineering/architecture/diagrams/model.c4` (hook enumeration line 32)

## Open Code-Review Overlap
Scanned 61 open `code-review` issues. Two touch `cc-dispatcher.ts`: **#3243** (decompose) — Acknowledge,
orthogonal; **#3242** (tool_use WS raw name) — Acknowledge, different surface (PreToolUse ≠ WS event). Both stay open.

## Acceptance Criteria
### Pre-merge (PR)
- AC1. Enabling `enableToolAttemptTelemetry` on cc produces one aggregated row/session with `{phase:{tool:count}}` incl. an `"unrouted"` bucket; `tool_input` absent from row/logs/Sentry.
- AC2. Forced flush failure does NOT fail the agent turn; debounced Sentry mirror (fail-open).
- AC3. The throwaway analysis script prints a per-phase `available(cc, per 0.4) − attempted` set on real/sample data (not a committed tested artifact).
- AC4. A multi-phase session produces exactly one INSERT (at `closeQuery`) — WAL-safe.
- AC5. Legacy runner path byte-unchanged (opt-in defaults off); drift-snapshot test asserts hooks absent by default.
- AC6. No table column joins to `auth.uid()` (CRITICAL-2); the SDK `session_id` never reaches `tool_attempts`.
- AC7. `tsc` clean; full suite green; C4 tests green; ADR-070 amended; `model.c4:32` updated.
### Post-merge (operator/ship)
- AC8. Migration applied via `web-platform-release.yml#migrate`; `tool_attempts` + pg_cron verified via `mcp__plugin_supabase_supabase__list_tables`/`list_migrations` (no SSH).
- AC9. Phase-0.1 linchpin confirmed in prod: a real multi-phase cc run yields non-`unrouted` tool counts (proves work tools traverse the instrumented session).

## Sharp Edges
- **HIGH-4 (RESOLVED).** Verified: Skill-routed sub-skill tool calls DO route through the cc query's parent hooks on the cc-soleur-go path — the feature captures real per-phase usage. The dataset would only be router-only on the legacy null-`active_workflow` path, which the cc runner never uses.
- **Phase attribution is on the PreToolUse(Skill) way-IN, never PostToolUse(Skill).** PostToolUse(Skill) fires AFTER the routed skill runs, so it would attribute that skill's own tools to the prior phase (off-by-one). Reading `tool_input.skill` (a known enum key) at PreToolUse to set phase is the sole permitted `tool_input` read and matches the shipped lever-1 hook — it does NOT violate NO-ECHO (which forbids capturing arbitrary tool_input for non-Skill tools).
- Flush at `closeQuery` (`soleur-go-runner.ts:1972`), NOT SessionEnd (unreliable under session reuse) nor `agent-runner.ts` (legacy runner never opts in).
- Closure-scoped accumulator with a minted random id — NOT a module-level `Map<sessionId>` (re-identification + leak + unbounded growth).
- `sanitizeToolNameForLog` on every tool_name before serialization (MCP names carry config/model-influenced bytes).
- New PreToolUse must be a *separate* gated hook entry, not a modification of the sandbox matcher (preserves AC5 drift snapshot).
- Empty `## User-Brand Impact` fails deepen-plan 4.6 — filled above.
