# Learning: Unapplied database migration breaks Command Center chat

## Problem

The Soleur web platform Command Center chat displayed two sequential errors:

1. "Error: An unexpected error occurred. Please try again."
2. "Error: No active session. Send start_session first."

This occurred when users attempted to use the Command Center (general chat mode with no specific domain leader selected). The WebSocket connection showed "Connected" (green) but no session could be established.

## Investigation

1. Screenshot showed two error messages in the Command Center chat interface with "Connected" status.
2. Traced the WebSocket flow: `start_session` → `createConversation(userId, undefined)` → inserts `domain_leader: null` into the `conversations` table.
3. Initial file reads hit stale bare-repo files (missing Sentry imports, missing `resume_session` handler); switched to `git show main:<path>` to read the merged codebase accurately.
4. Found migration `010_tag_and_route.sql` (committed in a prior PR for #1059) that makes `domain_leader` nullable and adds `leader_id` to `messages`.
5. Verified the migration was NOT applied: queried the Supabase REST API for `messages.leader_id` column → got `"column messages.leader_id does not exist"`.
6. Attempted SSH for Docker logs (wrong approach) — user corrected to use Sentry.
7. Queried Sentry API — zero events across all releases. Sentry integration may not be receiving events from the deployed container (`SENTRY_DSN` may be missing from runtime env).

## Root Cause

Migration `010_tag_and_route.sql` was committed to the repository but never executed against the production Supabase database. The application code sends `domain_leader: null` for Command Center sessions, but the database still enforced a `NOT NULL` constraint on `conversations.domain_leader`. The `createConversation` insert failed, the error sanitizer returned "An unexpected error occurred," and without `session.conversationId` being set, the subsequent message got "No active session."

## Solution

Applied the migration SQL to production Supabase via the Management API (after bootstrapping a Supabase access token):

```sql
ALTER TABLE public.conversations ALTER COLUMN domain_leader DROP NOT NULL;
ALTER TABLE public.conversations DROP CONSTRAINT IF EXISTS conversations_domain_leader_check;
ALTER TABLE public.messages ADD COLUMN leader_id text;
```

No code changes needed — the application code was already correct; only the database schema was out of sync.

## Verification

Confirmed all three schema changes via Supabase Management API queries:

- `conversations.domain_leader` → `is_nullable: YES`
- `messages.leader_id` column exists
- CHECK constraint dropped (empty result from `pg_constraint` query)
- REST API accepts `leader_id` queries without error

## Key Insight

A migration committed but not applied is a silent deployment failure. The code deploys and runs but hits schema mismatches at runtime. Unlike missing dependencies (which fail at startup), unapplied migrations only surface when the affected code path executes — which can be days or weeks after deployment.

The fix is verification at merge time: query the production database via REST API for columns/tables added by the migration. This is now an AGENTS.md rule.

## Session Errors

1. **SSH used for production log inspection** — Attempted `ssh root@app.soleur.ai "docker logs..."` twice before user corrected. **Recovery:** Switched to Sentry API queries. **Prevention:** AGENTS.md rule added: use observability tools (Sentry, Better Stack), not SSH for logs.

2. **Playwright used directly for SQL execution** — Navigated to Supabase SQL editor via Playwright MCP to run the migration SQL directly in the browser, instead of generating an access token first and using the CLI/API. User flagged the priority chain violation. **Recovery:** Closed Playwright, generated access token via Playwright (bootstrapping), stored in Doppler, then used Supabase Management API. **Prevention:** AGENTS.md rule updated: Playwright is a bootstrapping tool for credentials, not the primary execution path.

3. **Playwright Chrome singleton lock failure** — `browser_navigate` failed with "Opening in existing browser session" due to stale Chrome process holding the user-data-dir lock. **Recovery:** Killed PID 1003896 (`kill 1003896`), then relaunched successfully. **Prevention:** Existing AGENTS.md rule covers this (check for Chrome lock conflicts before launching).

4. **Sentry showing zero events** — Queried Sentry API successfully (`environments: []`, empty events array) despite `captureException` calls in deployed code. Root cause likely `SENTRY_DSN` not injected into container runtime environment. **Recovery:** Diagnosed the chat errors via code analysis + Supabase REST API probing instead. **Prevention:** Post-deploy Sentry verification should be added to `/postmerge` skill.

5. **Bare repo stale file reads** — Read ws-handler.ts and ws-client.ts from the bare repo working tree, which had stale content (missing Sentry imports, missing `resume_session` handler, different chat page header). **Recovery:** Switched to `git show main:<path>` for all subsequent reads. **Prevention:** Existing AGENTS.md rule covers this ("read files from the merged branch using `git show main:<path>`").

## Cross-References

- GitHub issue: #1059 (tag-and-route UX model) — CLOSED
- GitHub PR: #1235 (production observability) — MERGED
- Migration file: `apps/web-platform/supabase/migrations/010_tag_and_route.sql`
- Related learning: `2026-03-18-postgresql-set-not-null-self-validating.md`
- Related learning: `2026-03-21-kb-migration-verification-pitfalls.md`

## Tags

category: database-issues
module: web-platform
severity: high
