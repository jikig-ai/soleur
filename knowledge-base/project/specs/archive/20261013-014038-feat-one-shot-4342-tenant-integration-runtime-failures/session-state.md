# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-22-fix-tenant-integration-runtime-failures-4342-plan.md
- Status: complete

### Errors
None. All deepen-plan gates passed: Phase 4.6 (User-Brand Impact present + valid threshold), Phase 4.7 (Observability skip valid — no apps/*/server/ production code edits in PR scope), Phase 4.8 (no PAT-shape variables). All 5 cited AGENTS.md rule IDs active. All 4 cited PR/issue numbers verified live (#4339 MERGED, #4338 CLOSED, #4225 MERGED, #4294 MERGED, #4342 OPEN). All Files-to-Edit paths verified to exist on disk. Open code-review overlap check returned None.

### Decisions
- User-Brand Impact upgraded from `none` → `single-user incident` after deepen-pass discovered production caller chain `components/scope-grants/scope-grant-row.tsx:74 → app/api/scope-grants/grant/route.ts:73 → supabase.rpc("grant_action_class")`. `requires_cpo_signoff: true` added; review-time `user-impact-reviewer` will validate.
- Architecture: derive `workspace_id` internally in `grant_action_class` (Option 2) rather than widening API signature (Option 1) or dropping CHECK constraint (Option 3). Preserves API back-compat for production route + tests; uses solo-canary predicate from migration 059's own backfill.
- Massive blast-radius discovery (out-of-scope, deferred): Production INSERT sites on `conversations` (ws-handler.ts:761) and `messages` (6+ sites across cc-dispatcher, agent-runner, inngest functions) do not pass `workspace_id`. Migration 059 set both to NOT NULL. P0 follow-up issue MUST be filed at /work Phase 0 after verifying prd-Supabase migration 059 state via Supabase MCP.
- 6 failure classes (A-F) explicitly enumerated vs. issue body's understated 2-class framing: (A) scope_grants check violation, (B) is_workspace_member permission denied, (C) record_byok PGRST202 signature miss, (D) conversations.workspace_id NOT NULL (4 sites), (E) DSAR pre/post-state over-broad assertion, (F) remove_workspace_member 3rd-arg call mismatch.
- Test runner verified as vitest (not bun test) via `jq -r .scripts apps/web-platform/package.json`; tenant-integration.yml triggers on pull_request paths for supabase/migrations/** and test/server/** — this PR hits both globs, no manual `gh workflow run` needed.

### Components Invoked
- soleur:plan (Phase 0 KB load, Phase 1.7.5 open code-review overlap check, Phase 2.5 domain review, Phase 2.6 User-Brand Impact, Phase 2.7 GDPR gate skip-valid, Phase 2.8 IaC skip-valid, Phase 2.9 Observability skip-valid)
- soleur:deepen-plan (Phase 4.6 User-Brand Impact halt PASS, Phase 4.7 Observability gate PASS-with-skip, Phase 4.8 PAT-shape halt PASS, KB citation verification, AGENTS.md rule-ID verification, PR/issue live verification via gh CLI, production caller chain discovery via rg, test-runner verification via jq, open code-review overlap re-check)
