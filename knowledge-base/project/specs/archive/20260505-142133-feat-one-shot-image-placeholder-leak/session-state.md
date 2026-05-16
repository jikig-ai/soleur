# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-image-placeholder-leak/knowledge-base/project/plans/2026-05-05-fix-image-placeholder-leak-plan.md
- Status: complete

### Errors
None. Phase 4.6 User-Brand Impact gate passed (threshold `none` with explicit scope-out reason for sensitive-path regex match).

### Decisions
- Root cause dual: (a) cc-soleur-go path silently drops `msg.attachments` in `ws-handler.ts:1062-1071, 1145-1162`; (b) `[Image #N]` is the `claude-agent-sdk` CLI's text-editor placeholder (confirmed in `node_modules/@anthropic-ai/claude-agent-sdk/cli.js`); chat-input's `handlePaste` only intercepts `clipboardData.files`.
- Fix is multi-layer single-PR: server-side strip at WS boundary with `image_paste_lost` error code, client-side paste guard, threading `msg.attachments` through cc-dispatcher, and persisting `messages` rows on cc path.
- Critical architectural correction during deepen: cc-soleur-go path does NOT persist `messages` server-side today; would hit FK violation on `message_attachments.message_id`. Phase 3 rewritten to insert a `messages` row at cc-dispatch time.
- Shared helper extraction: `apps/web-platform/server/attachment-pipeline.ts` (NEW) lifts `agent-runner.ts:1342-1421` with snapshot test on legacy path's augmented `userMessage` shape.
- Threshold `none` justified: diff path matches sensitive-path regex by location but no auth/RLS/credentials/payment surface altered.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
