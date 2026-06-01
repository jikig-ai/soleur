# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-share-a-key-toggle-not-enabling/knowledge-base/project/plans/2026-06-01-fix-share-a-key-delegation-rpc-param-mismatch-plan.md
- Status: complete

### Errors
None.

### Decisions
- Root cause is a verified RPC named-argument mismatch, not a UI/precondition bug. `POST /api/workspace/delegations` (route.ts:79-86) calls `grant_byok_delegation` with `p_daily_cap_cents`, `p_hourly_cap_cents`, `p_created_by_user_id` and omits required `p_expires_at`; the canonical signature (migration 064) expects `p_daily_usd_cap_cents`, `p_hourly_usd_cap_cents`, `p_expires_at`, `p_actor_user_id`. PostgREST fails resolution → 400 → client's `if (res.ok)` silently swallows it → toggle reverts. Working precedent: byok-grant.ts:173-180.
- Fix is caller-only. Align the route's named args to the 064 contract; no migration, schema, RPC, or infra change. Do NOT touch the RPC (would break the working CLI and WORM/tenant-isolation tests).
- Hourly-cap default = daily cap (RPC rejects NULL hourly with ERRCODE 22003; UI exposes only a daily stepper) — deliberate documented UX choice.
- Secondary UX fix in scope (AC5): delegation-toggle.tsx `handleToggle` should surface non-OK responses instead of silently no-op'ing.
- TDD-first via new route test (api-delegation-grant-route.test.ts) asserting the exact 7-key RPC call shape. Threshold: single-user incident; requires_cpo_signoff: true.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
