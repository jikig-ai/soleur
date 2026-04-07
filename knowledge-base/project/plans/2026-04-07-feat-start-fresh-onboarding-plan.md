---
title: "feat: Start Fresh onboarding — guided first-run with foundation cards"
type: feat
date: 2026-04-07
updated: 2026-04-07
---

# feat: Start Fresh Onboarding

[Updated 2026-04-07: Applied review feedback from DHH, Kieran, and Code Simplicity reviewers]

## Overview

Add a guided first-run experience to the Soleur web platform dashboard. When a founder creates a new project via "Start Fresh," the dashboard captures their startup idea on the first interaction, then surfaces 4 contextual foundation cards as smart prompts. Card completion state is derived from KB file existence — no new DB schema. The dashboard conditionally renders: first-run prompt if no vision, foundation cards if vision exists but other docs missing, otherwise the existing Command Center.

## Problem Statement

When a founder creates a new project, they land on a static dashboard with generic suggested prompts and no business context. The AI team knows nothing about the startup, and the founder has no guidance on where to begin. The 2026-03-03 onboarding audit rated the "first 5 minutes" flow as FAIL.

## Proposed Solution

### Dashboard Conditional Rendering

Two conditional overrides of the existing dashboard, checked on every mount via `/api/kb/tree`:

1. **No `vision.md`** → render first-run view (welcome message + focused prompt, hide everything else)
2. **`vision.md` exists but foundation files incomplete** → render dynamic `SUGGESTED_PROMPTS` as foundation cards with done/not-done badges
3. **All 4 foundation files exist** → render existing Command Center (no changes — this is the default)

Not a three-state machine — just two early returns before the existing default.

### Foundation Cards via Dynamic SUGGESTED_PROMPTS

Rather than creating a new component, the existing `SUGGESTED_PROMPTS` array becomes dynamic — populated with foundation cards when in the foundations phase, or generic prompts when all foundations are complete.

| Card | Leader | KB File | Smart Prompt |
|------|--------|---------|--------------|
| Vision | CPO (auto) | `overview/vision.md` | N/A — auto-completed from first message |
| Brand Identity | CMO | `marketing/brand-guide.md` | "Help me define our brand identity" |
| Business Validation | CPO | `product/business-validation.md` | "Help me validate our business model" |
| Legal Foundations | CLO | `legal/privacy-policy.md` | "Help me set up our legal foundations" |

Cards use the existing `insertRef.current(text, 0)` pattern to pre-fill the chat input. Static prompt text — no vision.md content fetch needed. The agent reads the KB during the chat session and has full context.

Done cards show a checkmark badge and link to the KB file. Not-done cards are clickable smart prompts. The existing grid layout (2-col mobile, 4-col desktop) is reused.

### Vision.md Creation — Server-Side with Agent Enhancement

**Primary:** After the first message is sent from the first-run dashboard, create a minimal `vision.md` server-side from the message text. This guarantees the file exists and the dashboard transitions to foundations state.

**Enhancement:** When the CPO agent session starts and `vision.md` exists but is minimal (server-generated), the system prompt instructs the agent to enhance it with structured sections (Mission, Target Audience, Value Proposition, Key Differentiators). The agent enriches the file via its sandbox file-write tools.

This two-step approach ensures: (1) the dashboard always transitions after the first message (no LLM reliability risk), and (2) the vision document eventually contains high-quality structured content.

### State Re-Evaluation Trigger

The dashboard checks KB state on every mount (via `useEffect` + fetch). When the founder navigates from `/dashboard/chat/[id]` back to `/dashboard` (via sidebar link), the component re-mounts and re-fetches. No polling, no WebSocket push, no cross-tab communication. The existing navigation pattern (sidebar "Dashboard" link) is the trigger.

**Trade-off acknowledged:** If the agent writes a KB file and the founder is still on the chat page, they must navigate back to the dashboard to see the update. The chat page could add a contextual cue ("Your brand guide is ready — return to dashboard to see your progress") but this is a polish item, not a launch requirement.

## Technical Approach

### Architecture

```text
Dashboard page (page.tsx)
  └─ Inline state derivation (useEffect + fetch /api/kb/tree)
       ├─ Flatten tree into Set<string> of paths
       ├─ Check 4 foundation paths against the set
       └─ Derive: visionExists, allFoundationsComplete

Rendering (early returns):
  if (isLoading) → loading skeleton (hides WelcomeCard, prompts, leader strip)
  if (!visionExists) → <FirstRunView /> (welcome + focused ChatInput)
  if (!allFoundationsComplete) → dynamic SUGGESTED_PROMPTS (foundation cards)
  else → existing Command Center (unchanged)
```

### Key Implementation Details

**1. Inline state derivation in `page.tsx`**

A `useEffect` + `useState` block directly in the dashboard page:

- Calls `GET /api/kb/tree` on mount with cancellation guard (pattern from KB viewer: `let cancelled = false`)
- Flattens the `TreeNode` tree into a `Set<string>` of relative paths for O(1) lookups
- Matches paths against `TreeNode.path` values (not `TreeNode.name` — avoids false positives from files with the same name in different directories)
- Sets: `visionExists: boolean`, `foundationCards: Array<{...card, done: boolean}>`, `isLoading: boolean`
- Handles errors: 401 → redirect to login, 503 → show "workspace provisioning" state, network error → retry with backoff
- No separate hook file — extract only if this grows

**2. Dashboard page modifications** (`app/(dashboard)/dashboard/page.tsx`)

- While `isLoading`, hide everything (WelcomeCard, SUGGESTED_PROMPTS, leader strip) and show a loading skeleton — prevents flash from `useOnboarding` and KB tree racing
- First-run: replace hero text with welcome message + focused `ChatInput` with placeholder "Describe your startup idea..."
- First-run: `handleSend` does NOT set `leader=cpo` in URL params — omits leader entirely so tag-and-route handles it (tag-and-route already defaults to CPO for startup-idea messages, and omitting the param avoids locking the conversation to a single leader)
- First-run: still calls existing `completeOnboarding()` on send (updates `onboarding_completed_at` in DB — prevents old WelcomeCard from showing if new state logic fails)
- Foundations: `SUGGESTED_PROMPTS` array is dynamically populated with foundation cards (done cards show checkmark + KB link, not-done cards keep click-to-prefill behavior)
- Command-center: existing behavior, no changes

**3. Vision.md server-side creation** (`server/agent-runner.ts` or new utility)

- In `sendUserMessage()`, after the first message on a fresh workspace, check if `{workspace}/knowledge-base/overview/vision.md` exists
- If not, create a minimal vision file server-side:

  ```markdown
  # Vision

  {founder's first message text}
  ```

- Ensure `knowledge-base/overview/` directory exists (`mkdirSync` with `recursive: true`)
- This runs in the server process (not the sandbox) — it's a one-time bootstrap, not an agent operation
- Fire-and-forget with `.catch()` (per learnings: unhandled rejections terminate Node 22+)

**4. Agent vision enhancement** (`server/agent-runner.ts`)

- In `startAgentSession()`, only when `leaderId === "cpo"` (or undefined/auto-routed), check if `vision.md` exists but is minimal (< 500 bytes)
- If minimal, append to system prompt: "The founder's vision document at knowledge-base/overview/vision.md is a stub. Enhance it with structured sections: Mission, Target Audience, Value Proposition, Key Differentiators. Write the enhanced version to the same path."
- Scoped to CPO sessions only — prevents CMO/CLO/other leaders from getting irrelevant instructions

**5. `useOnboarding` interaction**

- `useOnboarding` stays as-is (no subsumption needed with the inline approach)
- The loading skeleton while KB tree fetches prevents the race condition between `useOnboarding` and KB state
- `completeOnboarding()` still fires on first-run send as a fallback/compatibility measure

### Files to Create

None. Zero new files.

### Files to Modify

| File | Change |
|------|--------|
| `app/(dashboard)/dashboard/page.tsx` | Inline KB state derivation, conditional rendering (first-run/foundations/default), dynamic SUGGESTED_PROMPTS |
| `server/agent-runner.ts` | Server-side vision.md creation on first message, CPO-scoped enhancement instruction |

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| New `useDashboardState` hook | Premature abstraction — only one consumer (dashboard page). Inline and extract later if needed. |
| New `FoundationCards` component | SUGGESTED_PROMPTS already renders clickable card grid. Dynamic data change, not new component. |
| Vision.md content fetch for prompt templates | Second API call per dashboard load to customize 3 strings. Agent reads KB during chat anyway. Static prompts work. |
| Three-state enum (`first-run / foundations / command-center`) | Command-center is the existing default, not a new state. Two conditional overrides are simpler. |
| `leader=cpo` hardcoded in first-run | Locks the entire conversation to CPO. Omitting the param lets tag-and-route handle it without locking. |
| LLM-only vision.md creation | Probabilistic — agent may not follow the instruction. Server-side creation guarantees transition. |
| New `onboarding_steps` DB table | Adds schema complexity for 4 boolean checks. KB file existence is simpler. |
| Gamification (badges, points, streaks) | Brand mismatch. "Tesla/SpaceX" positioning clashes with consumer-app patterns. |

## Acceptance Criteria

### Functional Requirements

- [ ] New "Start Fresh" project shows first-run dashboard state (welcome + focused prompt, no generic cards or leader strip)
- [ ] First message creates a minimal `vision.md` server-side (guaranteed, not LLM-dependent)
- [ ] After first message, dashboard shows foundations state with Vision card marked complete
- [ ] Clicking a foundation card pre-fills the chat input with a static contextual prompt
- [ ] Card completion state derived from KB file existence via `/api/kb/tree` (matched on `TreeNode.path`)
- [ ] All 4 foundation cards complete → dashboard renders existing Command Center
- [ ] "Connect Existing Project" with pre-existing KB files shows appropriate state
- [ ] Returning founder sees correct state based on current KB contents
- [ ] Loading skeleton prevents flash of wrong state while KB tree and onboarding state load

### Non-Functional Requirements

- [ ] Single API call per dashboard mount (`/api/kb/tree`) — no second fetch for vision content
- [ ] No new Supabase migrations
- [ ] No new files created — only `page.tsx` and `agent-runner.ts` modified
- [ ] CSRF protection on any new POST routes (structural test enforces this)

## Test Scenarios

### Acceptance Tests

- Given a new "Start Fresh" project with empty KB, when the founder visits the dashboard, then they see the first-run state with a focused prompt and no suggested prompts or leader strip
- Given a first-run dashboard, when the founder types their idea and sends, then the message routes through tag-and-route and `vision.md` is created server-side
- Given a dashboard with only `vision.md` existing, when the founder visits, then they see dynamic SUGGESTED_PROMPTS as foundation cards with Vision marked complete
- Given the foundations state, when the founder clicks the "Brand Identity" card, then the chat input is pre-filled with "Help me define our brand identity"
- Given a workspace with all 4 foundation files existing, when the founder visits the dashboard, then they see the existing Command Center
- Given a "Connect Existing Project" with an existing `brand-guide.md`, when the founder visits, then the Brand Identity card shows as complete

### Edge Cases

- Given a first-run dashboard, when the server-side vision.md creation fails (disk error), then the dashboard remains in first-run state on reload (founder can retry)
- Given a workspace where `vision.md` was deleted after creation, when the founder returns, then the dashboard reverts to first-run state (KB-derived, not cached)
- Given a slow KB tree response, when the dashboard mounts, then a loading skeleton shows (hides both WelcomeCard and prompts — no flash)
- Given a KB tree endpoint returning 503 (workspace provisioning in progress), then the dashboard shows a "Setting up your workspace..." state, not first-run
- Given a founder who types "@cto" in the first-run prompt, the message still routes through tag-and-route (no hardcoded leader override)
- Given a founder who completes foundations then an agent deletes a KB file, the dashboard regresses to foundations state (KB-derived, no latch)
- Given a CLO conversation that produces `terms-of-service.md` instead of `privacy-policy.md`, the Legal card stays incomplete (file path must match exactly)

## Dependencies and Risks

| Dependency | Risk | Mitigation |
|------------|------|------------|
| Rebase onto main (dependency branch already merged as `54a727ee`) | LOW — straightforward rebase | Rebase before starting implementation |
| Agent must produce specific KB files for card completion | MEDIUM — agent may write to wrong path or not write at all | Smart prompt copy should hint at expected output; card stays incomplete if file not created (retry-safe) |
| KB tree endpoint performance | LOW — already exists and is fast | No change to endpoint; just consuming it |
| Brand-voice copy for first-run prompt | MEDIUM — high-stakes copy moment | Flag for copywriter review before shipping |
| Single-turn agent sessions | MEDIUM — agent cannot ask follow-up questions | Each card interaction must complete in one turn; multi-turn is a separate roadmap item |

## Domain Review

**Domains relevant:** Product, Marketing, Engineering

### Engineering (CTO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** Prior art exists (ChooseState, CreateProjectState, useOnboarding, WelcomeCard). Dependency branch already merged. Recommended guided prompts approach (days of work, not weeks). No multi-step workflow primitive in web platform — must work within single-turn chat.

### Marketing (CMO)

**Status:** reviewed (carried from brainstorm)
**Assessment:** First 60 seconds are the highest-leverage activation moment. Startup idea capture is a commitment device. Prompt copy is high-stakes — needs copywriter attention. Framing should be "executive briefing readiness," not "tutorial completion."

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed (partial)
**Agents invoked:** spec-flow-analyzer
**Skipped specialists:** ux-design-lead (wireframes needed before implementation — run separately), copywriter (prompt copy needed before implementation — run separately)
**Pencil available:** N/A (deferred to pre-implementation phase)

#### Findings

Brainstorm validated the idea, not the page design. Wireframes and copywriter review are needed before implementation begins. Spec-flow-analyzer identified 23 gaps — critical ones addressed in this plan revision (state re-evaluation trigger, agent file-write contract, loading states, 503 handling).

## References and Research

### Internal References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-07-start-fresh-onboarding-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-start-fresh-onboarding/spec.md`
- Onboarding audit: `knowledge-base/project/specs/feat-product-strategy/onboarding-audit.md`
- Dashboard page: `apps/web-platform/app/(dashboard)/dashboard/page.tsx`
- ChatInput: `apps/web-platform/components/chat/chat-input.tsx` (insertRef pattern)
- useOnboarding: `apps/web-platform/hooks/use-onboarding.ts`
- KB tree API: `apps/web-platform/app/api/kb/tree/route.ts`
- Agent runner: `apps/web-platform/server/agent-runner.ts`
- Domain leaders: `apps/web-platform/server/domain-leaders.ts`
- Leader colors: `apps/web-platform/components/chat/leader-colors.ts`

### Institutional Learnings Applied

- UX review gap: visual polish != information architecture (2026-02-17) — validate navigation ordering and first-time user flow
- Context-blindness: onboarding artifacts must read brand guide first (2026-02-22) — smart prompt copy must align with brand voice
- Grid divisibility rule: verify card count % column count == 0 at all breakpoints (2026-02-22) — 4 cards in 2-col/4-col grid = clean
- Supabase silent errors: always destructure `{ data, error }` (2026-03-20) — applies to any new queries
- Middleware path matching: use exact-or-slash-boundary (2026-03-20) — if adding new exempt paths
- CSRF coverage: new POST routes need `validateOrigin` (2026-03-20) — structural test catches gaps
- Fire-and-forget promises need `.catch()` (2026-03-20) — applies to server-side vision.md creation

### Related Issues

- #1751 — Start Fresh onboarding (this feature)
- #1756 — worktree-manager.sh partial creation bug
- #674 — Phase 2 onboarding walkthrough (closed — broader scope)
- #75 — Bootstrap skill (Post-MVP — deferred orchestration)
