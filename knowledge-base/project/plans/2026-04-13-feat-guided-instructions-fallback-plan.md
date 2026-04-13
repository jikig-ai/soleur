---
title: "feat: guided instructions fallback (deep links + review gates for services without API/MCP)"
type: feat
date: 2026-04-13
issue: "#1077"
depends_on:
  - "#1050 (API+MCP tier — CLOSED)"
  - "#1049 (review gate notifications — OPEN, soft dependency)"
---

# feat: guided instructions fallback

Implement Tier 3 of the 3-tier service automation architecture: for services with no API or MCP server available, the agent provides step-by-step guided instructions with deep links and review gates. This covers the ~5% of services where neither API+MCP nor local Playwright is available.

## Background

The 3-tier service automation architecture was decided in brainstorm 2026-03-23 and tracked under #1050 (now closed). The tiers are:

| Tier | Coverage | Status |
|------|----------|--------|
| API + MCP | ~80% | Done (#1050) |
| Local Playwright | ~15% | Phase 5 (desktop app) |
| **Guided instructions** | **~5%** | **This issue** |

The service-automator agent (`plugins/soleur/agents/operations/service-automator.md`) already contains a Guided tier section, but it is incomplete:
- It says "Pause at each step with a review gate" without defining the multi-step protocol
- The existing review gate infrastructure is designed for one-shot approve/reject decisions, not sequential multi-step workflows
- No progress tracking or step-by-step state management exists
- Deep links from `service-deep-links.md` are referenced but not rendered with any special UX treatment

## Existing Infrastructure (No Changes Needed)

These components already work correctly and require no modification:

| Component | Path | What It Does |
|-----------|------|-------------|
| `review-gate.ts` | `apps/web-platform/server/review-gate.ts` | Abort-aware review gate promise with timeout, extraction, validation |
| `ReviewGateCard` | `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:457` | Amber-themed card with question, options, descriptions, resolution state |
| `ws-client.ts` | `apps/web-platform/lib/ws-client.ts` | Client-side review_gate message handling + sendReviewGateResponse |
| `ws-handler.ts` | `apps/web-platform/server/ws-handler.ts:395` | Server-side review_gate_response routing |
| `agent-runner.ts` | `apps/web-platform/server/agent-runner.ts:862` | AskUserQuestion interception + tier selection injection |
| `service-deep-links.md` | `plugins/soleur/agents/operations/references/service-deep-links.md` | URLs for all supported services |
| `providers.ts` | `apps/web-platform/server/providers.ts` | Provider config with labels and categories |
| `tool-tiers.ts` | `apps/web-platform/server/tool-tiers.ts` | Tool tier classification (auto-approve/gated/blocked) |

## What Needs to Change

### 1. Service-Automator Agent Prompt Enhancement

**File:** `plugins/soleur/agents/operations/service-automator.md`

The Guided tier section needs a formalized protocol that uses sequential AskUserQuestion calls (one per step) instead of a vague "pause at each step." The existing review gate infrastructure supports this natively -- each AskUserQuestion call creates a new review gate card in the chat UI.

**Changes:**
- Add a `## Guided Instructions Protocol` section with explicit step-by-step format
- Each step: (a) present deep link as a markdown link, (b) describe what to do on that page, (c) issue an AskUserQuestion with "Done -- proceed to next step" / "I need help" / "Skip this step" options
- Add progress tracking instructions: "Step N of M: [title]" in the question text
- Add a post-completion summary step that lists what was configured
- Add instructions to detect when a service falls to guided tier (no token stored AND no MCP session)

### 2. Service-Deep-Links Enhancement

**File:** `plugins/soleur/agents/operations/references/service-deep-links.md`

**Changes:**
- Add `## Adding New Services` section documenting the format for contributors
- Add estimated time per service setup (helps set user expectations)
- Add prerequisite notes (e.g., "Requires a domain you control" for Cloudflare)
- Ensure each service has a complete guided steps list with step numbering that matches what the agent will present

### 3. Review Gate Card Enhancement for Multi-Step Flows

**File:** `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

The current `ReviewGateCard` component works for single-question gates. For guided instructions, multiple sequential gates will appear in the chat. This works out of the box since each AskUserQuestion creates a new card. However, two improvements would help:

**Changes:**
- Add a `stepProgress` field to the review gate message type (e.g., "Step 2 of 6") that renders as a progress indicator above the question
- Style deep links within review gate questions with a distinctive button-like appearance (detect URLs in the question markdown and render them as styled links)

### 4. WebSocket Protocol Extension

**Files:** `apps/web-platform/lib/types.ts`, `apps/web-platform/lib/ws-client.ts`, `apps/web-platform/server/agent-runner.ts`

**Changes:**
- Add optional `stepProgress` field to the `review_gate` message type (e.g., `{ current: 2, total: 6, title: "Add DNS records" }`)
- The agent-runner parses this from the AskUserQuestion header field (the SDK already supports a `header` field)
- No protocol version bump needed -- the field is optional and backward-compatible

### 5. Screenshot/Annotation Support

**Approach:** The agent already has Playwright MCP tools available. For guided instructions, the agent can take screenshots of the target service pages to show the user what to look for. However, this requires the agent to navigate to the service page -- which is only possible if the user is already logged in via Playwright.

**Decision: Defer screenshots to Phase 5 (desktop app).** On web, the agent cannot access the user's browser session. Instead:
- Use text descriptions with specific CSS selectors or UI element descriptions ("Click the blue 'Create Token' button in the top-right corner")
- Link to official documentation screenshots where available
- Create a deferred issue for screenshot support when local Playwright is available

## Acceptance Criteria

- [ ] Agent detects guided tier (no API token stored, no MCP session) and provides step-by-step instructions
- [ ] Each guided step presents a deep link (markdown URL) and clear instructions
- [ ] Each step issues an AskUserQuestion that pauses the agent until the user responds
- [ ] User can mark each step "Done", "Need help", or "Skip"
- [ ] Progress indicator shows "Step N of M" in each review gate card
- [ ] After completing all steps, agent prompts user to store their API token for future automation
- [ ] Guided flow works for all 5 services in service-deep-links.md (Cloudflare, Stripe, Plausible, Hetzner, Resend)
- [ ] New services can be added by editing service-deep-links.md only (no code changes)

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** The architecture is sound -- the existing review gate infrastructure (AskUserQuestion interception, ReviewGateCard, ws protocol) already supports sequential multi-step flows. The main work is agent prompt engineering plus a small optional UI enhancement (step progress indicator). The optional `stepProgress` field extension is backward-compatible. No new server infrastructure, no new database tables, no new external dependencies. Risk is low.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)

The changes modify existing UI (adding optional progress indicators to review gate cards and styling deep links). The core review gate UX is unchanged. The guided instructions flow is entirely driven by the agent's AskUserQuestion calls through the existing review gate protocol.

## Test Scenarios

- Given a user with no Plausible API key stored, when the agent is asked to set up Plausible analytics, then the agent provides step-by-step guided instructions with deep links to plausible.io pages
- Given a guided instructions flow is in progress, when the user clicks "Done -- proceed to next step" on step 3 of 6, then the agent receives the response, acknowledges it, and presents step 4 of 6
- Given a guided instructions flow is in progress, when the user clicks "I need help" on any step, then the agent provides additional context about that step without advancing
- Given a guided instructions flow is in progress, when the user clicks "Skip this step", then the agent notes the skip and advances to the next step
- Given all guided steps are completed, when the flow ends, then the agent provides a summary and prompts the user to store their API token
- Given a user has a Plausible API key stored, when the agent is asked to set up Plausible, then the agent uses the API tier (NOT guided), confirming tier selection works
- Given a review gate card with a step progress indicator, when rendered in the chat, then "Step N of M" appears above the question

## Dependency Analysis

### Hard Dependencies (Done)

- **#1050 API+MCP tier (CLOSED):** The service-automator agent and service-deep-links.md were created as part of this issue. The guided tier section exists but needs enhancement.

### Soft Dependencies (Can Ship Without)

- **#1049 Review gate notifications (OPEN):** Without push/email notifications, if the user backgrounds the browser while a guided step is pending, they won't know the agent is waiting. This is acceptable for the initial implementation -- the user initiated the guided flow and is expected to stay engaged. Notifications will improve the experience later.

## Alternative Approaches Considered

| Approach | Decision | Reason |
|----------|----------|--------|
| Custom "guided flow" UI component (stepper, progress bar, checklist) | Rejected | Overengineering. Sequential AskUserQuestion calls through existing review gates achieve the same UX with zero new components. The chat-based flow is natural and conversational. |
| Server-side step state machine | Rejected | The agent maintains step state in its conversation context. No server-side persistence needed -- if the session drops, the conversation history shows which steps were completed. |
| Screenshot capture via Playwright on server | Deferred to Phase 5 | Cannot access user's authenticated browser session from the server. Desktop app with local Playwright solves this. |
| Embed service documentation iframes | Rejected | CSP violations, unreliable cross-origin rendering, and most service dashboards block iframe embedding. |

## Implementation Notes

- The `AskUserQuestion` tool's `header` field can carry the step progress info (e.g., "Step 2 of 6: Configure DNS"). The agent-runner already extracts and forwards this field to the client.
- The `descriptions` field on AskUserQuestion options can carry help text for each choice (e.g., "Done" description: "I completed this step successfully").
- No database schema changes needed. No migrations.
- No new npm dependencies needed.
- Test with `npm run test` from `apps/web-platform/` (vitest).

## MVP

The minimal viable implementation is **agent prompt changes only** (items 1 and 2 above). The existing review gate UI already renders questions with options and descriptions. The agent just needs to be instructed to use AskUserQuestion in a sequential step-by-step pattern with deep links.

The UI enhancements (step progress indicator, styled deep links) are polish that can ship in a follow-up.

### Phase 1: Agent Prompt + Deep Links (MVP)

1. Enhance `service-automator.md` with formalized guided protocol
2. Enhance `service-deep-links.md` with prerequisites and time estimates
3. Add tests for tier selection (guided tier triggers when no token stored)
4. Manual QA: start a chat, ask to set up a service without stored token, verify guided flow

### Phase 2: UI Polish (Optional Follow-up)

1. Add `stepProgress` to review gate message type
2. Parse step progress from AskUserQuestion header in agent-runner
3. Render progress indicator in ReviewGateCard
4. Style deep links in review gate questions

## References

- Service automator agent: `plugins/soleur/agents/operations/service-automator.md`
- Service deep links: `plugins/soleur/agents/operations/references/service-deep-links.md`
- Review gate: `apps/web-platform/server/review-gate.ts`
- Review gate card: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:457`
- AskUserQuestion SDK schema learning: `knowledge-base/project/learnings/integration-issues/2026-04-10-askuserquestion-sdk-schema-mismatch.md`
- Service tool registration learning: `knowledge-base/project/learnings/integration-issues/service-tool-registration-scope-guard-20260410.md`
- 3-tier architecture decision: `knowledge-base/product/roadmap.md` (Architecture Decision section)
- Parent issue: #1050 (service automation)
- Notification dependency: #1049 (review gate notifications)
