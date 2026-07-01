# Tasks — TR3 Tool-Attempt Telemetry Collector

Plan: `knowledge-base/project/plans/2026-07-01-feat-tr3-tool-attempt-telemetry-plan.md`
Issue: #5843 · Branch: feat-tr3-tool-attempt-telemetry · Lane: cross-domain · Threshold: single-user incident
_Revised after 3-agent plan-review (DHH/Kieran/simplicity): 3 CRITICALs + value-linchpin folded in._

## Phase 0 — Preconditions + VALUE-LINCHPIN GATE
- [x] 0.1 **GATE (HIGH-4) — RESOLVED (verdict A, cc path):** Skill-routed sub-skill tool calls route through the cc query's parent `options.hooks` (`agent-runner-query-options.ts:212-214`; sandbox PreToolUse matcher already lists Write/Edit). Legacy `startAgentSession` (verdict B) is the null-`active_workflow` path, never called by `soleur-go-runner.ts`. Feature is buildable.
- [x] 0.2 Confirm `closeQuery()` (`soleur-go-runner.ts:1972`) fires once per ActiveQuery across reused turns.
- [x] 0.3 Pick a PreToolUse matcher that captures `Skill`/`Task`/`mcp__*` (shipped hooks use narrow matchers).
- [x] 0.4 Enumerate SDK built-in default toolset from `sdk.d.ts`; define `available(cc) = built-ins − (CANONICAL_DISALLOWED_TOOLS ∪ cc [Edit,Write]) + registered MCP`.

## Phase 1 — Migration
- [x] 1.1 `<NNN>_tool_attempts.sql`: `(id uuid pk, created_at, counts jsonb)` — NO session_id column joinable to a user (CRITICAL-2); `counts = {phase|unrouted: {tool: int}}`. RLS service-role-only.
- [x] 1.2 pg_cron purge `< now() - 90d` (mirror 103); guarded `cron.unschedule` DO block. `.down.sql` drops + unschedules.

## Phase 2 — Collector module (closure accumulator + ONE PreToolUse hook + flush)
- [x] 2.1 `apps/web-platform/server/tool-attempt-telemetry.ts` `createToolAttemptCollector()` factory → `{preToolUseHook, flush}` closing over `{randomId: crypto.randomUUID(), phase:"unrouted", counts}` (HIGH-5).
- [x] 2.2 Single PreToolUse hook: when `tool_name==="Skill"` → `phase = skillToPhase(tool_input.skill)` (way-IN, fixes off-by-one; the sole permitted `tool_input` read, same as shipped lever-1 hook). Extract shared `skillToPhase` from `phase-surface-hook.ts` (DHH-2). Pre-first-Skill tools → `"unrouted"` (HIGH-6).
- [x] 2.3 Otherwise: `sanitizeToolNameForLog(tool_name)` + `counts[phase][tool]++`; NEVER read `tool_input` for non-Skill tools.
- [x] 2.4 `flush()`: one JSONB row insert; try-catch → `reportSilentFallback` (op `tool-attempt-telemetry:flush`); never throw.

## Phase 3 — Wire opt-in + flush site
- [x] 3.1 `agent-runner-query-options.ts`: add `enableToolAttemptTelemetry?`; register the SINGLE PreToolUse hook as a SEPARATE gated entry with a matcher capturing `Skill`+full surface (mirror `enablePhaseSurfaceHint:239-241`, don't touch sandbox matcher). No PostToolUse(Skill) telemetry hook.
- [x] 3.2 `soleur-go-runner.ts`: `collector.flush()` from `closeQuery()` (`:1972`) (CRITICAL-3).
- [x] 3.3 `cc-dispatcher.ts` opts in; legacy passes nothing (AC5 byte-unchanged).

## Phase 4 — Analysis (throwaway, not committed)
- [x] 4.1 ~15-line throwaway TS script: `available(cc)` (0.4) − `attempted` (`jsonb_object_keys` via execute_sql), print per-phase diff; paste into #5772. No committed `.sql`, no seeded test.

## Phase 5 — ADR + C4 + tests
- [x] 5.1 Amend `ADR-070` (insert-per-call rejection + aggregated-row + static-availability-oracle + closure-id). NO new ADR (071 taken).
- [x] 5.2 Edit `model.c4:32` hook enumeration; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [x] 5.3 `test/tool-attempt-telemetry.test.ts`: fail-open, no-`tool_input`, WAL=1-insert/session, `"unrouted"` bucket, pg_cron purge.
- [x] 5.4 `agent-runner-query-options.test.ts`: hooks present-when-enabled / absent-by-default.

## Phase 6 — Verify
- [x] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [x] 6.2 `./node_modules/.bin/vitest run test/tool-attempt-telemetry.test.ts test/agent-runner-query-options.test.ts`.
- [x] 6.3 Full `package.json scripts.test`; C4 tests.

## Post-merge (operator/ship)
- [ ] 7.1 Migration applied via `web-platform-release.yml#migrate`; verify table + pg_cron via `mcp__plugin_supabase_supabase__list_tables`/`list_migrations` (no SSH).
- [ ] 7.2 Real multi-phase cc run yields non-`unrouted` tool counts (confirms Phase-0.1 linchpin in prod).
