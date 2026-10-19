# Chat Attachments Brainstorm

**Date:** 2026-04-11
**Issue:** [#1961](https://github.com/jikig-ai/soleur/issues/1961)
**Participants:** Founder, CPO, CMO, CTO
**Status:** Decision captured

---

## What We're Building

File attachment support in chat conversations on the Soleur cloud platform (app.soleur.ai). Users can upload images (PNG, JPEG, GIF, WebP) and PDFs to provide visual context when communicating with AI domain leader agents — screenshots of errors, competitor pages, design mockups, contracts, invoices.

Attachments are uploaded to Supabase Storage via presigned URLs, displayed inline in chat messages, and passed to the AI agent by writing files to the workspace filesystem (workaround for the Agent SDK's string-only `query()` limitation).

## Why This Approach

1. **Supabase Storage** over R2/self-hosted: integrates with existing auth/RLS, JS client already in use, zero new infra. Costs are equivalent at current scale (<100 users). Migrate to R2 if egress becomes material at 1000+ users.

2. **Presigned URL upload** over server proxy: client uploads directly to Supabase Storage, server never touches file bytes. Lower server memory pressure (8 GB Hetzner), faster uploads, standard pattern.

3. **Filesystem write** for AI processing: Agent SDK `query()` only accepts `prompt: string`. Upload file to Supabase Storage → download to workspace filesystem → reference path in prompt text. The agent reads files via Claude Code's native vision/PDF capabilities. Replace with direct multimodal content blocks when SDK adds support.

4. **Images + PDFs** only: matches what Claude can actually process. Video is not supported by Claude (despite the issue description mentioning it). Broader file types deferred until there's user demand.

5. **Conversation-scoped** persistence: attachments live with the conversation, deleted when the conversation is deleted. Keeps GDPR purge simple. Independent KB file upload is a separate follow-up issue.

6. **20 MB size limit** per file: matches Claude's input limit. Server-side validation via presign endpoint.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage backend | Supabase Storage | Built-in RLS, JS client exists, zero new infra. Migrate to R2 at scale. |
| Upload flow | Presigned URL (client-direct) | Server doesn't handle file bytes. Lower memory, faster uploads. |
| AI processing | Filesystem write workaround | SDK limitation. Write to workspace, reference path in prompt. |
| File types | Images (PNG/JPEG/GIF/WebP) + PDF | Matches Claude's vision + PDF capabilities. |
| Size limit | 20 MB per file | Matches Claude input limit. |
| Persistence | Conversation-scoped | Deleted with conversation. Simpler GDPR purge. |
| KB upload | Separate issue | Different UI surface (KB viewer). Shared upload infra. |
| Chat UX | Paperclip button + drag-drop + paste | Full desktop experience, good mobile support. |
| Marketing | Bundle into Phase 3 narrative | Table stakes feature. Don't announce in isolation. |

## Open Questions

1. **Per-user storage quota:** What total storage cap per user before requiring an upgrade? Needs pricing model input.
2. **File retention policy:** Keep attachments forever (until conversation deleted) or auto-expire after N days?
3. **Multiple attachments per message:** Allow 1 file or multiple? If multiple, what's the max count?
4. **Agent SDK multimodal timeline:** When will `query()` support content blocks? This determines when to remove the filesystem write workaround.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Recommended deferral to Phase 4 due to Phase 3 deadline pressure (6 days, 9 open issues) and no documented user signal. Flagged that #1961 is not in the roadmap feature table. If kept in Phase 3, needs spec and CTO architecture decision first. Minimum viable scope is images-only. Founder overrode deferral recommendation — keeping in Phase 3.

### Marketing (CMO)

**Summary:** Attachments are table stakes — every competitor (Cowork, Cursor, Copilot, Codex, Lovable) already supports multimodal input. Do not market in isolation. Bundle into Phase 3 "Make it Sticky" narrative. Strong angle for non-technical founder recruitment in Phase 4: "Upload a photo of your competitor's booth. Your CMO agent writes the counter-positioning before you leave the floor."

### Engineering (CTO)

**Summary:** Medium complexity (3-5 days) for images + PDFs. Recommends Supabase Storage. Critical finding: Agent SDK `query()` only accepts strings, not multimodal content blocks — filesystem write workaround needed. Separate HTTP upload endpoint preferred over WebSocket binary transport. Must update CSP `img-src` for Supabase Storage origin. Key files: chat-input.tsx, types.ts, ws-client.ts, ws-handler.ts, agent-runner.ts, api-messages.ts.

## Institutional Learnings Applied

- CSP needs Supabase Storage origin in `img-src` (learning: 2026-03-20-nextjs-static-csp-security-headers)
- Never use `bytea` for file metadata — use `text` columns (learning: 2026-03-17-postgrest-bytea-base64-mismatch)
- Always destructure `{ error }` from Supabase Storage calls (learning: 2026-03-20-supabase-silent-error-return-values)
- Sanitize storage errors through `error-sanitizer.ts` (learning: 2026-03-20-websocket-error-sanitization-cwe-209)
- Use typed `WSErrorCode` for upload failures (learning: 2026-03-18-typed-error-codes-websocket-key-invalidation)
- Session key must include `leaderId` for attachment state (learning: multi-leader-session-collision)
- Verify migrations applied to production after merge (learning: unapplied-migration)
