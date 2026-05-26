# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-12-fix-api-usage-tracking-undercount-plan.md
- Status: complete

### Errors
None. Self-correction at deepen pass: prescribed migration `043_write_byok_audit_function.sql` was dropped after live grep proved `write_byok_audit` RPC already shipped in migration 037. Phase 3.1 rebound to the existing signature `(uuid invocation_id, uuid founder_id, text agent_role, int token_count, int unit_cost_cents)`.

### Decisions
- Root cause: `cc-dispatcher.ts:1202-1205` `onResult` is a no-op stub ("wire in Stage 3"). All conversations through `dispatchSoleurGo` emit cost telemetry into the void while the dashboard reads `conversations.total_cost_usd` — the 60-90% undercount.
- Cache tokens never persisted: schema (017) lacks `cache_read_input_tokens` + `cache_creation_input_tokens`. SDK at `sdk-tools.d.ts:69-70` exposes them. Add via migration 041 + extend `increment_conversation_cost` to v2 in 042.
- `audit_byok_use` writer wiring: migration 037 shipped the table + RPC + WORM trigger but no caller. Phase 3.1 binds to existing `write_byok_audit` RPC, closes #3392 sub-bullet.
- Optional Phase 5 Admin Usage/Cost API integration: `X-Api-Key` auth, supports `api_key_ids[]` filter (critical to avoid multi-key over-count); nested `cache_creation.{ephemeral_1h, ephemeral_5m}` normalized to SDK-flat. Banner: "Verified ✓" (green) when delta ≤ $0.001, "Discrepancy" (yellow) with Report link otherwise.
- R8 (deepen pass): SDK `usage.input_tokens` is uncached-input-only. UI "Input" pill widened to render `(input + cache_read + cache_creation)` so Console cross-check holds for cached prompts; otherwise 4-25x gap persists even after cc-dispatcher fix.
- Brand-survival threshold: `single-user incident` — `requires_cpo_signoff: true`. The 2026-04-17 "Actual API cost — cross-check any row" footnote is currently false; this plan reinstates the contract without changing positioning.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan (inline-executed, with WebFetch verification of Anthropic Admin API docs)
- WebFetch: platform.claude.com/docs/en/api/admin-api/usage-cost/{get-messages-usage-report,get-cost-report}
- gh issue list --label code-review --state open (#3392 folded in; #3243/#3242/#3343/#3370 acknowledged out of scope)
