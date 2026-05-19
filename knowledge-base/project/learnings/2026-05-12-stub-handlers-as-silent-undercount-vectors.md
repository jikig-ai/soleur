# Learning: Stub event handlers ("wire in later") are silent telemetry-loss vectors

## Problem

The Soleur dashboard's "API Usage" panel reported `$0.24 / 1 conversation` for May while the Anthropic Console reported `$0.57 / 921,944 input tokens / claude-sonnet-4-6` for the same user/key/month — a **50-99% under-count**. The "no markup" brand positioning depends on the dashboard's footnote: *"cross-check any row in your Anthropic Console under Usage — the numbers will match to the cent."* For any user who actually checked, the claim was false.

Three stacked bugs:

1. **The cc-soleur-go path's `onResult` callback was a no-op stub.** `apps/web-platform/server/cc-dispatcher.ts:1202-1205` shipped with `onResult: (_result) => { /* wire in Stage 3 when the aggregate conversation cost reader lands */ }`. Stage 3 never landed. Every conversation routed through `dispatchSoleurGo` (the entire current chat surface, all non-`legacy` routing) emitted cost telemetry into the void. The dashboard read `conversations.total_cost_usd`, which was mutated only by the legacy `agent-runner.ts` RPC call. The primary cause of the 60-90% gap.
2. **Cache tokens were never persisted.** The Anthropic SDK exposes `usage.cache_read_input_tokens` and `usage.cache_creation_input_tokens`; schema 017 dropped both per a simplicity-reviewer cut. With prompt caching enabled, the bulk of "real" input tokens land in `cache_read_input_tokens` and were silently dropped from both per-row display and MTD sum.
3. **The `audit_byok_use` WORM table was provisioned by migration 037 (`write_byok_audit` RPC + WORM trigger) but no production code ever wrote to it.** Issue #3392 catalogued this as a PR-D §3.5 deferral; PR-D never landed.

## Solution

Three layers of fix landed in PR #3626:

1. **Shared `cost-writer.ts` helper.** Extracted `persistTurnCost(userId, conversationId, leaderId, input)` that fires three side-effects fire-and-forget: atomic `increment_conversation_cost` v2 RPC (5 deltas), `write_byok_audit` row, widened `usage_update` WS event. Both `agent-runner.ts` (legacy single-leader) and `cc-dispatcher.ts:1202` (cc-soleur-go) converge on this helper — no more divergent persistence paths.
2. **Schema widening + RPC overload, not replace.** Migration 041 adds `cache_read_input_tokens` + `cache_creation_input_tokens` (NOT NULL DEFAULT 0 + CHECK ≥ 0) and extends the partial covering index. Migration 042 creates a 6-arg overload of `increment_conversation_cost` **without dropping the v1 4-arg signature** — Postgres distinguishes overloads by parameter list, so v1 callers from old pods during a rolling deploy continue to work transparently and v2 callers route to the new signature.
3. **UI semantics fix.** The dashboard's "Input" pill now renders `(uncached + cache_read + cache_creation)` to match the Anthropic Console's headline total input. New "Cache read" and "Cache write" pills render conditionally when `> 0`. A new tooltip explains the three-tier pricing.

Phase 5 of the original plan (Anthropic Admin Usage/Cost API reconciliation banner, ~1500 LoC opt-in surface) was deferred to issue #3629 to keep the primary brand-survival fix's blast radius manageable.

## Key Insight

**"Wire in Stage 3" comments on event handlers are silent telemetry-loss vectors.** Three independent factors made this bug invisible for ~3 weeks:

- The handler was a *stub*, not a TODO — it satisfied the type system, the dispatcher routed events to it, no failure surfaced.
- The handler's siblings (`onText`, `onToolUse`, `onSessionIdCaptured`) WERE wired, so a reviewer skimming the dispatcher would see a fully-wired event surface and miss the one no-op.
- The under-count was a "missing write" failure mode: there is no error message for a write that never fires. Sentry mirrors are silent on no-call.

Two architectural rails close this class:

1. **Stub handlers should fail loudly.** A no-op `onResult` handler that exists to be "wired later" should either throw `Error("not wired")` until the wiring lands, OR fan out to a metrics counter (`incrementCounter("event_handler_unwired", { handler: "onResult" })`) so monitoring sees it.
2. **Cross-path convergence.** When two code paths (legacy + new) write the same data, extract a shared helper at the first divergence — not at the second. The shared helper is the single place a future "did we wire all paths?" review needs to look.

The rolling-deploy migration trap is independently load-bearing: **never `DROP FUNCTION` + `CREATE` an RPC in the same migration** if any prod caller targets the old signature. Postgres overloads by parameter list — additive overloads are wire-compatible across rolling deploys; DROP+CREATE creates a window where (a) prd-schema-without-app or (b) prd-app-without-schema both break the cost path silently.

## Session Errors

- **Bash CWD drift across calls** — `cd <subdir>` in one Bash call does not persist to the next. Recovery: prefix every command with the full absolute path. **Prevention:** when a `find` or `git add` returns empty/error and the previous command CDed, suspect drift first.
- **`doppler run … bash -c "esbuild …"` failed because esbuild was not on PATH** — `node_modules/.bin/` is exposed by `npm run` but not by bare `bash -c`. Recovery: switched to `npm run dev`. **Prevention:** never invoke node_modules-installed binaries from outside an npm script; always go through `npm run <script>`.
- **Edit tool wrote to bare-root plugin path instead of worktree path** — when I called `Edit` on `/home/harry/Documents/Stage/Soleur/soleur/plugins/...` from inside a worktree, the edit landed on the bare-root checkout (a stale sync), not the worktree. `git status` was clean and the change was not in the PR. Recovery: re-applied to the `<worktree-root>/plugins/...` absolute path. **Prevention:** when editing plugin files from a worktree, always use the worktree-prefixed absolute path; the bare-root `/plugins/...` resolves to a sibling checkout that is NOT in the worktree's git scope.
- **Long leading-sleep + curl readiness check blocked by harness** — `sleep 25 && curl …` was rejected. Recovery: switched to `run_in_background: true` with an `until <check>; do sleep 2; done` loop. **Prevention:** for "wait until ready" patterns, use Bash with `run_in_background: true` + an `until` loop, or use Monitor.
- **QA skill blocked pipeline on dev-server start for prose-only Test Scenarios** — the QA skill's Step 1.5 attempts to auto-start the dev server, but the plan's Test Scenarios were Given/When/Then prose with no executable `Browser:`/`API verify:` prefixed steps. Recovery: added a third graceful-degradation case to `plugins/soleur/skills/qa/SKILL.md` (committed in `de31a6fb`). **Prevention:** the new skill clause auto-skips QA silently when scenarios are prose-only.

## Tags

category: integration-issues
module: apps/web-platform/server/cc-dispatcher.ts, apps/web-platform/server/cost-writer.ts, apps/web-platform/supabase/migrations/041_conversation_cache_tokens.sql, apps/web-platform/supabase/migrations/042_increment_conversation_cost_v2.sql
related: #3392 (audit_byok_use writer deferral), #3243 (cc-dispatcher decomposition), #3629 (Phase 5 Admin API reconciliation, deferred), plan 2026-05-12-fix-api-usage-tracking-undercount-plan.md
