# Tasks: Web Platform — Cloud CLI Engine

**Plan:** `knowledge-base/plans/2026-03-16-feat-web-platform-cloud-cli-engine-plan.md`
**Issue:** #297
**Branch:** feat/web-platform-ux

## Phase 0: Validation Spikes

Critical unknowns that must be resolved before committing to full implementation.

- [ ] 0.1 **Agent SDK licensing check** — Contact Anthropic developer relations or review SDK license terms. Can the SDK be used in a multi-tenant hosted product?
- [ ] 0.2 **Agent SDK compatibility spike** — Run 3 Soleur agents (CMO, CTO, CPO) via Agent SDK `query()`. Verify: Task tool spawns subagents, Skill tool chains work, AskUserQuestion returns, file tools operate in workspace directory.
- [ ] 0.3 **Workspace sizing estimate** — Measure Soleur plugin directory size. Calculate storage cost at 100/1000/10000 users. Evaluate shared read-only plugin mount + user-specific KB overlay.

## Phase 1: Foundation

- [ ] 1.1 Initialize monorepo structure (`apps/web/`, `apps/agent-server/`, `packages/types/`)
- [ ] 1.2 Set up Supabase project (database, auth, realtime)
- [ ] 1.3 Create initial database migration (`supabase/migrations/001_initial_schema.sql`)
  - [ ] 1.3.1 `users` table (Supabase Auth handles this)
  - [ ] 1.3.2 `api_keys` table (encrypted key, provider, validation status)
  - [ ] 1.3.3 `workspaces` table (user, fs_path, status, config)
  - [ ] 1.3.4 RLS policies (users access only own data)
- [ ] 1.4 Implement magic-link auth flow
  - [ ] 1.4.1 `app/(auth)/login/page.tsx`
  - [ ] 1.4.2 `app/(auth)/signup/page.tsx`
  - [ ] 1.4.3 Auth callback handler
- [ ] 1.5 Build BYOK key management
  - [ ] 1.5.1 `app/(auth)/setup-key/page.tsx` — key input form
  - [ ] 1.5.2 `apps/agent-server/src/byok/key-store.ts` — AES-256-GCM encrypted storage
  - [ ] 1.5.3 `apps/agent-server/src/byok/key-validator.ts` — test key against Anthropic API
  - [ ] 1.5.4 Key rotation UI (settings page)
- [ ] 1.6 Build workspace provisioner
  - [ ] 1.6.1 `apps/agent-server/src/workspace/provisioner.ts` — create dir, copy plugin, init git
  - [ ] 1.6.2 Workspace lifecycle management (provision, suspend, delete)
- [ ] 1.7 Set up Stripe subscription
  - [ ] 1.7.1 Single platform access plan
  - [ ] 1.7.2 Webhook handler for subscription events
- [ ] 1.8 Deploy to Railway/Fly.io
  - [ ] 1.8.1 Persistent volume for `/workspaces/`
  - [ ] 1.8.2 Environment variable configuration
  - [ ] 1.8.3 CI/CD pipeline

## Phase 2: Chat Interface + Agent Execution

- [ ] 2.1 Set up WebSocket server (`apps/agent-server/src/streaming/ws-server.ts`)
- [ ] 2.2 Implement session manager
  - [ ] 2.2.1 Map conversation ID → Agent SDK query
  - [ ] 2.2.2 Handle session resume (`resume: sessionId`)
  - [ ] 2.2.3 Handle session cleanup on disconnect
- [ ] 2.3 Build domain leader routing
  - [ ] 2.3.1 Map leader selection to agent file path
  - [ ] 2.3.2 Construct system prompt with agent instructions
  - [ ] 2.3.3 Load allowed tools configuration per leader
- [ ] 2.4 Implement Agent SDK integration (`apps/agent-server/src/sessions/agent-runner.ts`)
  - [ ] 2.4.1 `query()` call with workspace CWD, BYOK key, tools config
  - [ ] 2.4.2 StreamEvent relay to WebSocket
  - [ ] 2.4.3 Error handling (API errors, timeout, key issues)
- [ ] 2.5 Implement workspace sandbox hook
  - [ ] 2.5.1 PreToolUse hook — block file access outside `/workspaces/{user_id}/`
  - [ ] 2.5.2 Block Bash commands that escape workspace (cd /, rm -rf /, etc.)
- [ ] 2.6 Build chat UI
  - [ ] 2.6.1 `app/(dashboard)/chat/page.tsx`
  - [ ] 2.6.2 `MessageList.tsx` — render user/assistant messages
  - [ ] 2.6.3 `ChatInput.tsx` — message input with send button
  - [ ] 2.6.4 `LeaderSelector.tsx` — card grid showing 8 domain leaders
  - [ ] 2.6.5 Streaming text renderer (show text as it arrives)
  - [ ] 2.6.6 Tool use display (show what agent is doing)
- [ ] 2.7 Persist conversations to Supabase
  - [ ] 2.7.1 `supabase/migrations/002_conversations.sql`
  - [ ] 2.7.2 Save messages as they arrive
  - [ ] 2.7.3 Load conversation history on page load
- [ ] 2.8 WebSocket client library (`apps/web/lib/ws-client.ts`)

## Phase 3: Plan Review + Execution Monitoring

- [ ] 3.1 Implement review gate hook (`apps/agent-server/src/hooks/review-gate.ts`)
  - [ ] 3.1.1 Intercept AskUserQuestion calls
  - [ ] 3.1.2 Create notification record
  - [ ] 3.1.3 Pause query via promise, resolve on user response
- [ ] 3.2 Build plan detection
  - [ ] 3.2.1 Parse agent output for plan structure (markdown task lists)
  - [ ] 3.2.2 Create PLAN record in database
  - [ ] 3.2.3 Link plan to KB file path
- [ ] 3.3 Build plan review UI
  - [ ] 3.3.1 `app/(dashboard)/plans/page.tsx`
  - [ ] 3.3.2 `PlanViewer.tsx` — render plan with checkboxes, structure
  - [ ] 3.3.3 `PlanActions.tsx` — approve/reject/modify buttons
  - [ ] 3.3.4 Plan modification editor (edit text before approving)
- [ ] 3.4 Build execution monitoring UI
  - [ ] 3.4.1 `app/(dashboard)/exec/page.tsx`
  - [ ] 3.4.2 `StreamingLog.tsx` — real-time output display
  - [ ] 3.4.3 Status indicator (running, paused, completed, failed)
  - [ ] 3.4.4 Cancel button with confirmation
- [ ] 3.5 Execution management
  - [ ] 3.5.1 Concurrent execution limit per user
  - [ ] 3.5.2 Execution cancellation (abort SDK query)
  - [ ] 3.5.3 Failure handling (capture error, create notification)
- [ ] 3.6 Database migration (`supabase/migrations/003_plans_executions.sql`)

## Phase 4: Knowledge-Base Viewer

- [ ] 4.1 Build KB REST API
  - [ ] 4.1.1 `apps/agent-server/src/kb-api/tree.ts` — file tree endpoint
  - [ ] 4.1.2 `apps/agent-server/src/kb-api/content.ts` — markdown content + frontmatter
  - [ ] 4.1.3 `apps/agent-server/src/kb-api/search.ts` — grep across all KB files
- [ ] 4.2 Build KB viewer UI
  - [ ] 4.2.1 `app/(dashboard)/kb/page.tsx`
  - [ ] 4.2.2 `FileTree.tsx` — sidebar tree navigation
  - [ ] 4.2.3 `MarkdownViewer.tsx` — render with syntax highlighting, mermaid
  - [ ] 4.2.4 `SearchBar.tsx` — search with highlighted results
- [ ] 4.3 Implement real-time KB updates
  - [ ] 4.3.1 Detect file changes in workspace (inotify or polling)
  - [ ] 4.3.2 Push updates to browser via Supabase Realtime

## Phase 5: Inbox + Notifications

- [ ] 5.1 Build notification service (`apps/agent-server/src/notifications/notification-service.ts`)
- [ ] 5.2 Implement notification types: plan_proposed, review_gate, completed, failed
- [ ] 5.3 Build inbox UI
  - [ ] 5.3.1 `app/(dashboard)/inbox/page.tsx`
  - [ ] 5.3.2 `NotificationList.tsx` — sorted by priority
  - [ ] 5.3.3 `NotificationItem.tsx` — clickthrough to relevant view
- [ ] 5.4 Supabase Realtime subscription for live notifications
- [ ] 5.5 Email notifications (Resend) for offline users
- [ ] 5.6 Notification preferences UI
- [ ] 5.7 Database migration (`supabase/migrations/004_notifications.sql`)

## Phase 6: Security Hardening + Production

- [ ] 6.1 Linux namespace isolation for workspace filesystem
- [ ] 6.2 Rate limiting (per-user execution concurrency, API requests)
- [ ] 6.3 Monitoring setup (execution metrics, error rates, active sessions)
- [ ] 6.4 BYOK key rotation flow
- [ ] 6.5 Session timeout handling
- [ ] 6.6 Workspace archival for inactive users
- [ ] 6.7 Security audit (OWASP top 10, BYOK exposure vectors, workspace isolation)
- [ ] 6.8 CSP headers, CORS configuration
- [ ] 6.9 Error tracking (Sentry)
- [ ] 6.10 Load testing (50+ concurrent users)
