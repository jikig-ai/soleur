# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-kb-concierge-pdf-context-and-logo/knowledge-base/project/plans/2026-05-04-fix-kb-concierge-pdf-context-and-logo-plan.md
- Status: complete

### Errors
None. All gates passed: Phase 4.5 (no SSH/network triggers — skipped), Phase 4.6 (User-Brand Impact section present, threshold `none` with explicit scope-out reason for the sensitive-path regex match on `apps/web-platform/server/**`).

### Decisions
- **Bug #1 (PDF context regression) root-caused to PR #2901 / Stage 2.12 cc-soleur-go cutover.** The `dispatchSoleurGo` (cc-dispatcher.ts:727) and `dispatchSoleurGoForConversation` (ws-handler.ts:497, 986, 1063) silently dropped `pendingContext` when the soleur-go runner replaced the legacy `agent-runner.ts` path that previously injected document context (`agent-runner.ts:595-631`). Fix threads `artifactPath` + `documentKind` + `documentContent` through `DispatchSoleurGoArgs → runner.dispatch → buildSoleurGoSystemPrompt`, mirroring the legacy PDF-Read directive and 50KB inline cap.
- **Bug #2 (avatar) root-caused to `cc_router` having `defaultIcon: ""` and no ICON_MAP entry.** The `LeaderAvatar` component renders the lucide-icon branch with no icon over the `bg-yellow-500` background, producing the empty yellow square. Fix adds a third branch (between `isSystem` and the icon branch) that renders the soleur logo for `cc_router`, mirroring the existing `system` branch shape but without the yellow bg.
- **Bug #3 (markdown) root-caused to missing `stream_end` emission.** Confirmed `chat-state-machine.ts:484-516` already special-cases `cc_router` for `stream_end` and transitions the bubble to `state: "done"` (which engages MarkdownRenderer at message-bubble.tsx:263). Server side, `dispatchSoleurGo` emits `onText → type: "stream"` with `partial: true` but never emits `stream_end` for `cc_router`. Fix adds `events.onTextTurnEnd?.()` in `soleur-go-runner.ts:778` (right after `onResult`), and the cc-dispatcher forwards it to `sendToClient({ type: "stream_end", leaderId: CC_ROUTER_LEADER_ID })`.
- **Body-read centralized in a helper alongside `dispatchSoleurGoForConversation`** to avoid silent divergence between the first-turn (line 986) and chat-case (line 1063) dispatch paths, both of which need the same `readFile` + `isPathInWorkspace` workspace-validation guard mirrored from `agent-runner.ts:608`.
- **Sanitization parity for `documentContent`.** New arg flows through the existing `sanitizePromptString` (soleur-go-runner.ts:415-419) — control chars + U+2028/U+2029 stripped — but at a 50KB cap (mirroring `agent-runner.ts:601` `MAX_INLINE_BYTES`), not the 256-char cap intended for short identifiers like `artifactPath`.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Read, Bash, Edit, Write (direct verification: 12 line-pinned codebase claims grep-confirmed before deepening)
- No subagent fan-out
