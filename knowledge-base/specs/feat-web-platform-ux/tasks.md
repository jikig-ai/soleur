# Tasks: Web Platform — Cloud CLI Engine

**Plan:** `knowledge-base/plans/2026-03-16-feat-web-platform-cloud-cli-engine-plan.md`
**Issue:** #297
**Branch:** feat/web-platform-ux

[Updated 2026-03-16 — rewritten after plan review. 3 phases + spike.]

## Phase 0: Agent SDK Spike (blocker)

- [x] 0.1 Create `spike/agent-sdk-test.ts`
- [x] 0.2 Import Agent SDK, point `cwd` at workspace with Soleur plugin + test KB
- [x] 0.3 Run `query()` with CMO agent prompt — verify streaming, file tools, subagents
- [x] 0.4 Test `canUseTool` callback — fires for non-pre-approved tools, receives file_path
- [x] 0.5 Verify SDK license field — "SEE LICENSE IN README.md" → Anthropic legal terms (needs legal review)
- [x] 0.6 Document findings: `spike/FINDINGS.md` — ALL PASS

**Gate:** Spike must PASS before Phase 1 begins.

## Phase 1: Working Loop

Auth → BYOK → chat → agent execution → review gates. One phase. Ship it.

- [ ] 1.1 Initialize `apps/web-platform/` (Next.js + custom `server.ts`)
- [ ] 1.2 Set up Supabase project (database, auth)
- [ ] 1.3 Database migration: USER, API_KEY, CONVERSATION, MESSAGE + RLS + indexes
- [ ] 1.4 Magic-link auth flow (login + signup pages)
- [ ] 1.5 BYOK key setup page
- [ ] 1.6 Encrypted key storage (AES-256-GCM) + validation against Anthropic API
- [ ] 1.7 Workspace provisioner (create dir, symlink plugin, init git)
- [ ] 1.8 WebSocket server (auth, session routing)
- [ ] 1.9 Agent SDK runner (`query()` with streaming input, `canUseTool`, BYOK env injection, systemPrompt, permissionMode)
- [ ] 1.10 Domain leader selector UI (card grid, 8 leaders)
- [ ] 1.11 Chat UI (message list, streaming text, review gate buttons inline)
- [ ] 1.12 WebSocket client (connect, reconnect, message handling)
- [ ] 1.13 Persist conversations + messages to Supabase
- [ ] 1.14 Stripe subscription (single plan, webhook handler)
- [ ] 1.15 Deploy to Railway/Fly.io (persistent volume)

## Phase 2: Visibility

Build after Phase 1 users say what they need. Likely:

- [ ] 2.1 KB REST API (file tree, content, search)
- [ ] 2.2 KB viewer UI (sidebar tree, markdown rendering, search)
- [ ] 2.3 Conversation list with status badges (the "inbox")
- [ ] 2.4 Email notifications for offline review gates (Resend)
- [ ] 2.5 Execution history (completed conversations with outcomes)

## Phase 3: Hardening

Build after real users exist:

- [ ] 3.1 Security audit (workspace isolation, BYOK, path traversal, OWASP)
- [ ] 3.2 Upgrade to container-per-workspace if needed
- [ ] 3.3 Rate limiting (per-user concurrency, API rate)
- [ ] 3.4 Monitoring (execution metrics, error rates)
- [ ] 3.5 Error tracking (Sentry)
- [ ] 3.6 CSP headers, CORS
- [ ] 3.7 Session timeout
- [ ] 3.8 Load testing (50+ concurrent users)
