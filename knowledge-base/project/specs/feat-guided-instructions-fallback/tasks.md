# Tasks: feat-guided-instructions-fallback

Guided instructions fallback for services without API/MCP (Tier 3 of 3-tier service automation).

## Phase 1: Agent Prompt Enhancement (MVP)

### 1.1 Formalize guided instructions protocol in service-automator

- [x] 1.1.1 Read current `plugins/soleur/agents/operations/service-automator.md`
- [x] 1.1.2 Add `## Guided Instructions Protocol` section with sequential AskUserQuestion pattern
- [x] 1.1.3 Define step format: header="Step N of M: [title]", question with deep link + instructions, options=["Done -- proceed to next step", "I need help", "Skip this step"]
- [x] 1.1.4 Add tier detection instructions: check connected services context, if no token for requested service AND no MCP session, use guided tier
- [x] 1.1.5 Add "I need help" handling: provide additional context without advancing step
- [x] 1.1.6 Add "Skip this step" handling: note skip, advance to next step, warn if skip may cause issues
- [x] 1.1.7 Add post-completion summary and token storage prompt
- [x] 1.1.8 Run `npx markdownlint-cli2 --fix` on the file

### 1.2 Enhance service-deep-links.md

- [x] 1.2.1 Read current `plugins/soleur/agents/operations/references/service-deep-links.md`
- [x] 1.2.2 Add estimated setup time per service (e.g., "~5 min" for Plausible, "~15 min" for Cloudflare with DNS)
- [x] 1.2.3 Add prerequisites per service (e.g., "Requires a domain you control" for Cloudflare)
- [x] 1.2.4 Add `## Adding New Services` section documenting the format
- [x] 1.2.5 Ensure step numbers are explicit and consistent across all services
- [x] 1.2.6 Run `npx markdownlint-cli2 --fix` on the file

## Phase 2: Testing

### 2.1 Write tests for guided tier selection

- [x] 2.1.1 Add test in `apps/web-platform/test/` verifying that when no API token is stored for a service, the agent system prompt includes connected services context WITHOUT that service
- [x] 2.1.2 Add test verifying connected services context includes/excludes services based on stored tokens
- [x] 2.1.3 Run tests: `cd apps/web-platform && npm run test`

## Phase 3: UI Polish (Optional)

### 3.1 Add step progress to review gate protocol

- [x] 3.1.1 Add optional `stepProgress` field to `ChatGateMessage` in `apps/web-platform/lib/ws-client.ts`
- [x] 3.1.2 Add optional `stepProgress` to `WSMessage` review_gate type in `apps/web-platform/lib/types.ts`
- [x] 3.1.3 Forward `stepProgress` from agent-runner review gate emission in `apps/web-platform/server/agent-runner.ts`
- [x] 3.1.4 Parse step progress from AskUserQuestion `header` field (pattern: "Step N of M: title")

### 3.2 Render progress in ReviewGateCard

- [x] 3.2.1 Read `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`
- [x] 3.2.2 Add `stepProgress` prop to ReviewGateCard
- [x] 3.2.3 Render progress bar or "Step N of M" indicator above the question
- [ ] 3.2.4 Style deep links (detect URLs in question text, render as styled buttons/links) -- deferred, MVP uses copy-pasteable URLs

### 3.3 Test UI changes

- [x] 3.3.1 Add test for ReviewGateCard with stepProgress prop in `apps/web-platform/test/chat-page.test.tsx`
- [x] 3.3.2 Run full test suite: `cd apps/web-platform && npm run test`

## Phase 4: Deferred Items

### 4.1 Create tracking issues

- [x] 4.1.1 Create issue for screenshot/annotation support in guided mode (deferred to Phase 5 desktop app) → #2038
