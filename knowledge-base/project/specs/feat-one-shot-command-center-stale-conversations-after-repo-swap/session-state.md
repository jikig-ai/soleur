# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-command-center-stale-conversations-after-repo-swap/knowledge-base/project/plans/2026-04-22-fix-command-center-stale-conversations-after-repo-swap-plan.md
- Status: complete

### Errors
None. Context7 MCP returned "Monthly quota exceeded" once; substituted with WebSearch + in-tree sibling migrations — no load-bearing gap.

### Decisions
- **Root cause:** `conversations` table has no repo/project scoping column. `hooks/use-conversations.ts` filters on `user_id` only; `/api/repo/disconnect` clears `users.repo_url` but never touches `conversations`. Swapping repos leaks every prior conversation into the new project's Command Center.
- **Fix shape:** add `conversations.repo_url` column (nullable, backfilled from `users.repo_url`), stamp it at every INSERT site, filter Command Center + KB context-path lookup by `(user_id, repo_url)`. Old rows become hidden, recoverable if user reconnects the same URL — no cascade delete.
- **Secondary fix:** rotate the `conversations_context_path_user_uniq` index to include `repo_url` so two repos with the same `overview/vision.md` path no longer collide (direct cause of the "Tell me about the file at overview/vision.md" rows leaking in the screenshot).
- **Realtime limitation acknowledged:** Supabase Realtime `filter:` supports only single-column equality (realtime-js#97); client-side drop + a second `users` table subscription for cross-tab disconnect detection is the only viable design.
- **RLS deliberately not tightened:** this is in-user tenancy (not cross-user), so RLS isn't the defense layer — recorded as a defensible Non-Goal with rationale. Future org-level sharing would revisit.
- **Deferrals tracked in tasks.md:** (1) first-class `projects` table for future multi-repo-per-user model, (2) billing-page lifetime conversation count (product question: per-user vs per-project).

### Components Invoked
- soleur:plan (primary) — drafted the plan + tasks.md
- soleur:deepen-plan (primary) — enhanced Migration safety, Realtime semantics, Race conditions, Related learnings sections
- WebSearch × 4 — Supabase Realtime filter, PostgreSQL UPDATE-FROM perf, multi-tenant SaaS scoping, Supabase migration runner
- mcp__plugin_soleur_context7__resolve-library-id — quota exceeded, fell through to WebSearch
- Read / Bash / Edit — code & schema inspection
