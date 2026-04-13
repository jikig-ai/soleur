---
title: "feat: guided instructions fallback (deep links + review gates for services without API/MCP)"
type: feat
date: 2026-04-13
issue: "#1077"
depends_on:
  - "#1050 (API+MCP tier — CLOSED)"
  - "#1049 (review gate notifications — OPEN, soft dependency)"
deepened: 2026-04-13
---

## Enhancement Summary

**Deepened on:** 2026-04-13
**Sections enhanced:** 8
**Research sources:** 5 learnings, agent-native-architecture principles, ws-protocol analysis, existing test patterns

### Key Improvements

1. **Review gate timeout extension** -- Discovered the current 5-minute timeout is too short for guided instructions where users configure external services. Added configurable timeout.
2. **Discriminated union safety** -- Added mandatory grep check from learning: when extending WSMessage type, all exhaustive switch statements must be updated.
3. **Concrete AskUserQuestion format** -- Added exact SDK-compatible code example for how the agent should format each guided step, grounded in the actual SDK schema (questions[] array format).
4. **Error recovery protocol** -- Added handling for mid-flow disconnection, timeout recovery, and session resumption using existing abort-aware infrastructure.
5. **Test pattern grounding** -- All test scenarios now include specific file paths, testing commands, and patterns from documented learnings (waitFor over setTimeout, exact string matching).

### New Considerations Discovered

- Review gate timeout (5 min) needs per-gate override for guided flows (users may spend 10+ min on external service setup)
- The `descriptions` field on AskUserQuestion options is already supported -- no new protocol fields needed for option-level help text
- The `header` field already flows end-to-end (agent -> agent-runner -> ws -> client) -- step progress can use it immediately with zero protocol changes
- Sequential AskUserQuestion calls are already natively supported by the review gate infrastructure -- each creates an independent gate with its own gateId

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

#### Research Insights: AskUserQuestion Format

The SDK uses a `questions[]` array format (learned from `2026-04-10-askuserquestion-sdk-schema-mismatch.md`). The agent should use AskUserQuestion with the following structure, which the existing `extractReviewGateInput` function handles correctly:

- **header:** "Step N of M: [step title]" -- this field is already extracted and forwarded to the `ReviewGateCard` as the amber tag above the question
- **question:** Markdown text with deep link and instructions (e.g., "Navigate to [Plausible API Keys](https://plausible.io/settings/api-keys) and create a new API key with Sites API scope.")
- **options:** Array of `{ label, description }` objects:
  - `{ label: "Done -- proceed to next step", description: "I completed this step successfully" }`
  - `{ label: "I need help", description: "Show me more detail about this step" }`
  - `{ label: "Skip this step", description: "I want to skip this and continue" }`

The `descriptions` field renders below each option button in the ReviewGateCard (already implemented).

#### Research Insights: Error Recovery

- **Mid-flow disconnection:** The `abortableReviewGate` function in `review-gate.ts` already rejects the promise when the session abort signal fires. The agent session ends cleanly. When the user reconnects and starts a new session, the conversation history shows which steps were completed (visible in the chat as resolved ReviewGateCards with green checkmarks).
- **Timeout handling:** The current `REVIEW_GATE_TIMEOUT_MS` is 5 minutes. For guided instructions, users may spend 10-15 minutes on a single step (e.g., waiting for DNS propagation, completing Stripe account verification). The agent-runner already passes `timeoutMs` to `abortableReviewGate` -- pass a longer timeout for AskUserQuestion calls that come from the service-automator agent. **Approach:** Use the default timeout for now; if users hit timeouts, add a `GUIDED_FLOW_TIMEOUT_MS = 30 * 60 * 1_000` (30 minutes) constant and pass it for guided flow gates. The 5-minute timeout is likely acceptable for MVP since users actively clicking through steps won't hit it.
- **"I need help" loop:** When the user clicks "I need help", the agent provides additional context and then issues a new AskUserQuestion for the same step (same step number, same options). This creates a new review gate card -- the old one shows as resolved with "I need help" selected. This is the correct behavior: the chat scroll shows the full history of the user's interaction with each step.

### 2. Service-Deep-Links Enhancement

**File:** `plugins/soleur/agents/operations/references/service-deep-links.md`

**Changes:**

- Add `## Adding New Services` section documenting the format for contributors
- Add estimated time per service setup (helps set user expectations)
- Add prerequisite notes (e.g., "Requires a domain you control" for Cloudflare)
- Ensure each service has a complete guided steps list with step numbering that matches what the agent will present

### 3. Review Gate Card Enhancement for Multi-Step Flows (Phase 2 Polish)

**File:** `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx`

The current `ReviewGateCard` component works for single-question gates. For guided instructions, multiple sequential gates will appear in the chat. This works out of the box since each AskUserQuestion creates a new card. However, two improvements would help:

**Changes:**

- Add a `stepProgress` field to the review gate message type (e.g., "Step 2 of 6") that renders as a progress indicator above the question
- Style deep links within review gate questions with a distinctive button-like appearance (detect URLs in the question markdown and render them as styled links)

#### Research Insights: No Protocol Change Needed for MVP

The `header` field is already rendered as an amber tag above the question text in the ReviewGateCard (line 506-508 in the chat page). Setting the header to "Step 2 of 6: Configure DNS" achieves the progress indicator effect with zero code changes. The Phase 2 polish adds a dedicated progress bar UI, but the MVP gets step progress for free through the existing header field.

#### Research Insights: Markdown in Question Text

The ReviewGateCard renders the question text as a plain `<p>` tag (line 516). For deep links to render as clickable links, the question text needs markdown-to-HTML rendering. **Options:**

1. **MVP (no code change):** The agent includes the full URL in the question text (e.g., "Navigate to <https://plausible.io/settings/api-keys> and create a new API key"). URLs are not clickable but are copy-pasteable.
2. **Phase 2 (small code change):** Replace the `<p>` tag with a component that renders basic markdown (links only). Use a simple regex or a lightweight library like `markdown-it` (already available if the project uses it elsewhere).
3. **Phase 2 alternative:** Render deep links as separate styled elements below the question text, extracted from a structured `links` field on the review gate message.

**Recommendation:** Start with option 1 (MVP). The agent writes clear prose with the URL inline. Users can copy-paste or click if the browser auto-links URLs. Move to option 2 in Phase 2 if user feedback indicates friction.

### 4. WebSocket Protocol Extension (Phase 2 Only)

**Files:** `apps/web-platform/lib/types.ts`, `apps/web-platform/lib/ws-client.ts`, `apps/web-platform/server/agent-runner.ts`

**Changes:**

- Add optional `stepProgress` field to the `review_gate` message type (e.g., `{ current: 2, total: 6, title: "Add DNS records" }`)
- The agent-runner parses this from the AskUserQuestion header field (the SDK already supports a `header` field)
- No protocol version bump needed -- the field is optional and backward-compatible

#### Research Insights: Discriminated Union Safety (Learning)

From `discriminated-union-exhaustive-switch-miss-20260410.md`: When adding fields to the `WSMessage` type in `lib/types.ts`, run this grep to find all exhaustive switch statements that must be updated:

```bash
grep -rn "const _exhaustive: never" apps/web-platform/
```

The `review_gate` variant already exists in the union -- adding an optional `stepProgress` field does NOT require updating switch statements (the variant type is unchanged). However, if a future change adds a new variant, this grep is mandatory.

**Current exhaustive switch locations:**

- `apps/web-platform/server/ws-handler.ts` (server-side message routing)
- `apps/web-platform/lib/ws-client.ts` (client-side message handling -- uses case-based routing, not exhaustive switch, but still needs coverage)

#### Research Insights: Backward Compatibility

The `stepProgress` field is optional (`stepProgress?: { current: number; total: number; title: string }`). Existing review gates (tool approval, generic AskUserQuestion) will not include this field. The ReviewGateCard must handle `stepProgress === undefined` gracefully -- render the card normally without a progress indicator. This is the standard pattern for extending the WS protocol (see `usage_update` addition in #1691).

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
- Given a guided instructions flow is in progress, when the user disconnects and reconnects, then the conversation history shows which steps were completed (resolved ReviewGateCards with green checkmarks)

### Research Insights: Test Patterns

From `2026-04-06-chat-page-test-determinism-and-coverage.md`:

- **Test runner location:** Always run tests from `apps/web-platform/` directory, not the worktree root. Use `cd apps/web-platform && npm run test` or the project's test script.
- **Async assertions:** Use `waitFor` from `@testing-library/react` instead of `setTimeout` for negative assertions (`expect(fn).not.toHaveBeenCalled()`).
- **Text matching:** Prefer exact string matches (`getByText("Done -- proceed to next step")`) over regex to avoid multi-element collisions as the ReviewGateCard renders multiple text nodes.
- **ReviewGateCard test file:** `apps/web-platform/test/chat-page.test.tsx` -- add test cases for multi-step guided flow rendering alongside existing review gate tests.
- **Review gate server tests:** `apps/web-platform/test/review-gate.test.ts` -- add tests for sequential gate resolution (gate 1 resolved, gate 2 pending, gate 3 not yet created).

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

### Research Insights: Agent-Native Architecture Alignment

This feature exemplifies the agent-native architecture principles from the agent-native-architecture skill:

1. **Parity:** The guided tier gives the agent a way to help with ALL services, not just those with API/MCP integrations. Without it, the agent would be stuck saying "I can't help with this service" -- violating the parity principle.
2. **Granularity:** Each step is an atomic AskUserQuestion call. The agent composes these primitives into a multi-step flow. No monolithic "guided flow" tool is needed.
3. **Context injection:** The connected services list (injected into the system prompt by `agent-runner.ts:464-475`) tells the agent which tier to use. The agent doesn't need to query the database -- the context is pre-injected.

### Research Insights: Service-Deep-Links as the Single Source of Truth

The `service-deep-links.md` file should be the ONLY place where service URLs and guided steps are defined. The agent reads this file at prompt time (it's linked from the agent definition). To add support for a new service:

1. Add a section to `service-deep-links.md` with the URL table, token permissions, and guided steps
2. Add the provider to `providers.ts` (for Connected Services UI)
3. No changes to `service-automator.md` -- the agent's protocol is generic, and it reads the service-specific steps from the deep links file

This separation is important because deep links change (services update their dashboard URLs) and should be updatable without modifying agent prompts.

### Sharp Edges

- **Cloudflare nameserver propagation:** Step 4 of the Cloudflare guided flow ("Wait for nameserver propagation") can take up to 24 hours. The agent should NOT issue an AskUserQuestion that blocks for this -- instead, advise the user to continue with other setup and return to Cloudflare verification later. This is the one step where "Skip" is the expected response.
- **Stripe account activation:** Stripe requires business verification before full API access. The guided flow should warn that some features (live payments, payouts) require verification that may take 1-2 business days.
- **MCP OAuth sessions vs stored API tokens:** A user may have a Cloudflare MCP OAuth session but no stored Cloudflare API token (or vice versa). The tier selection must check BOTH. The service-automator agent already documents this in its Sharp Edges section.
- **Rate limiting on external services:** The agent should not instruct the user to create multiple API keys or sites in rapid succession. Add a note in the guided steps for services with aggressive rate limits.
- **Plausible Sites API plan requirement:** If the user creates a Plausible account on the free/personal plan, the Sites API (needed for API tier) may not be available. The guided flow should mention this and suggest checking the plan level.

## MVP

The minimal viable implementation is **agent prompt changes only** (items 1 and 2 above). The existing review gate UI already renders questions with options and descriptions. The agent just needs to be instructed to use AskUserQuestion in a sequential step-by-step pattern with deep links.

The UI enhancements (step progress indicator, styled deep links) are polish that can ship in a follow-up.

### Phase 1: Agent Prompt + Deep Links (MVP)

1. Enhance `service-automator.md` with formalized guided protocol
   - Add `## Guided Instructions Protocol` with the sequential AskUserQuestion pattern
   - Define the three response options with descriptions
   - Add tier detection logic (check connected services context)
   - Add post-completion summary and token storage prompt
   - Add "I need help" re-prompt logic
   - Add "Skip" with skip-reason tracking
2. Enhance `service-deep-links.md` with prerequisites and time estimates
   - Add `Estimated time:` per service
   - Add `Prerequisites:` per service
   - Add `## Adding New Services` contributor guide section
   - Verify all step numbering is explicit (1, 2, 3...) and consistent
3. Add tests for tier selection (guided tier triggers when no token stored)
   - Test: connected services context without Plausible key -> agent system prompt includes instructions for guided tier
   - Test: connected services context WITH Plausible key -> agent system prompt includes Plausible as connected (API tier used)
   - Test file: `apps/web-platform/test/agent-runner-tools.test.ts` (extend existing service tool tests)
4. Manual QA: start a chat, ask to set up a service without stored token, verify guided flow

### Phase 2: UI Polish (Optional Follow-up)

1. Add `stepProgress` to review gate message type in `lib/types.ts`
2. Parse step progress from AskUserQuestion header in `agent-runner.ts` (regex: `/^Step (\d+) of (\d+): (.+)$/`)
3. Render progress indicator in `ReviewGateCard` when `stepProgress` is present
4. Add markdown link rendering in review gate question text (basic URL auto-linking)
5. Test: ReviewGateCard with stepProgress prop shows progress bar (add to `chat-page.test.tsx`)

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
