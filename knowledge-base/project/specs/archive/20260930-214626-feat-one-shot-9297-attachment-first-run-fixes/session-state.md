# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-30-fix-attachment-first-run-and-fresh-conversation-presign-plan.md
- Status: complete

### Errors
None.

### Decisions
- Server-assisted fix: presign validates a lowercase UUID, uses `maybeSingle()`, and gives an absent-row valid UUID an own-folder path; `chat` guard in `ws-handler.ts` accepts attachments-only first messages. Client-only alternative recorded in `decision-challenges.md`.
- Composer gate in `chat-surface.tsx`: `"new"` resolves to `realConversationId` only after `sessionConfirmed`, else `null` (attach disabled, never presigns for "new").
- First-run flow: new `lib/first-run-send.ts` uploads first, sends once; dashboard adds `fr=1` when files are staged; 45s upload deadline; distinct Sentry ops.
- Tile copy in `lib/attachment-error-copy.ts`; UX tier advisory; PR says `Ref #9297` (not Closes).
- Follow-ups filed: #9316 (surface first-run upload failures), #9318 (pre-existing security gap: co-member read of private conversation attachments, no presign rate limit, no bucket limits).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; dhh/kieran/simplicity reviewers, cpo, ux-design-lead, cto; security-sentinel, architecture-strategist, spec-flow-analyzer, test-design-reviewer; learnings-researcher.
