# Tasks: Start Fresh Onboarding

**Plan:** [2026-04-07-feat-start-fresh-onboarding-plan.md](../../plans/2026-04-07-feat-start-fresh-onboarding-plan.md)
**Issue:** #1751
**Branch:** `feat-start-fresh-onboarding`

[Updated 2026-04-07: Simplified per review — zero new files, inline state, dynamic SUGGESTED_PROMPTS]

## Prerequisites

- [x] 0.1 Rebase `feat-start-fresh-onboarding` onto main (dependency branch merged as `54a727ee`)

## Phase 1: Dashboard State Derivation (inline in page.tsx)

- [x] 1.1 Add inline KB state derivation to `app/(dashboard)/dashboard/page.tsx`
  - [x] 1.1.1 Add `useEffect` + `useState` block that fetches `/api/kb/tree` on mount with cancellation guard
  - [x] 1.1.2 Flatten `TreeNode` tree into `Set<string>` of `TreeNode.path` values (not `.name`)
  - [x] 1.1.3 Check existence of 4 foundation paths: `overview/vision.md`, `marketing/brand-guide.md`, `product/business-validation.md`, `legal/privacy-policy.md`
  - [x] 1.1.4 Derive: `visionExists`, `allFoundationsComplete`, `foundationCards` array with `done` booleans
  - [x] 1.1.5 Handle errors: 401 → redirect, 503 → "workspace provisioning" state, network error → fallback to Command Center
- [x] 1.2 Write tests for state derivation
  - [x] 1.2.1 Test: empty KB tree → visionExists=false
  - [x] 1.2.2 Test: vision.md only → visionExists=true, allFoundationsComplete=false
  - [x] 1.2.3 Test: all 4 files → allFoundationsComplete=true
  - [x] 1.2.4 Test: partial files → correct done booleans per card
  - [x] 1.2.5 Test: API 503 → provisioning state shown
  - [x] 1.2.6 Test: API error → graceful fallback

## Phase 2: Dashboard Conditional Rendering

- [x] 2.1 Add loading skeleton
  - [x] 2.1.1 While KB tree is loading, hide all content
  - [x] 2.1.2 Show centered loading skeleton matching existing dark theme
- [x] 2.2 Add first-run view (early return when `!visionExists && !isLoading`)
  - [x] 2.2.1 Welcome message: "Tell your organization what you're building."
  - [x] 2.2.2 Focused input with placeholder "What are you building?"
  - [x] 2.2.3 Hide SUGGESTED_PROMPTS and leader strip
  - [x] 2.2.4 `handleSend` omits `leader` param — tag-and-route handles routing
  - [x] 2.2.5 `handleSend` still calls `completeOnboarding()` for backward compatibility
- [x] 2.3 Make SUGGESTED_PROMPTS dynamic for foundations phase
  - [x] 2.3.1 Define `FOUNDATION_PATHS` constant: id, title, leaderId, kbPath, promptText
  - [x] 2.3.2 When `visionExists && !allFoundationsComplete`, render foundation cards
  - [x] 2.3.3 Done cards: show checkmark badge + link to `/dashboard/kb/{kbPath}`
  - [x] 2.3.4 Not-done cards: clickable → navigate to `/dashboard/chat/new?msg=...`
  - [x] 2.3.5 Reuse existing grid layout: `grid-cols-2 md:grid-cols-4` (2-col mobile, 4-col desktop)
  - [x] 2.3.6 Use `LEADER_BG_COLORS` for card color accents per leader
- [x] 2.4 Write tests for conditional rendering
  - [x] 2.4.1 Test: loading → skeleton shown, no flash
  - [x] 2.4.2 Test: first-run → welcome message + focused prompt, no leader strip
  - [x] 2.4.3 Test: foundations → dynamic cards with correct done/not-done badges
  - [x] 2.4.4 Test: all complete → existing Command Center (regression test)
  - [x] 2.4.5 Test: card click → navigates to new chat with prompt text

## Phase 3: Vision.md Server-Side Creation

- [x] 3.1 Add vision.md creation to `server/agent-runner.ts` (via `server/vision-helpers.ts`)
  - [x] 3.1.1 In `sendUserMessage()`, after saving message, check if `vision.md` exists
  - [x] 3.1.2 If not, `mkdir('knowledge-base/overview/', { recursive: true })` in workspace
  - [x] 3.1.3 Write minimal vision.md: `# Vision\n\n{founder's message text}`
  - [x] 3.1.4 Wrap in fire-and-forget with `.catch()` (Node 22 unhandled rejection)
- [x] 3.2 Add CPO-scoped vision enhancement
  - [x] 3.2.1 In `startAgentSession()`, only when `effectiveLeaderId === "cpo"`
  - [x] 3.2.2 Check if vision.md exists and is minimal (< 500 bytes)
  - [x] 3.2.3 If minimal, append enhancement instruction to system prompt
  - [x] 3.2.4 Instruction: "Enhance knowledge-base/overview/vision.md with sections: Mission, Target Audience, Value Proposition, Key Differentiators"
- [x] 3.3 Write tests for vision creation
  - [x] 3.3.1 Test: first message on empty workspace → vision.md created with message text
  - [x] 3.3.2 Test: vision.md already exists → no overwrite
  - [x] 3.3.3 Test: CPO session with minimal vision → enhancement instruction in system prompt
  - [x] 3.3.4 Test: vision.md does not exist → no enhancement instruction

## Phase 4: Polish and QA

- [x] 4.1 Run markdownlint on all changed .md files
- [ ] 4.2 Responsive breakpoint audit: verify card grid at 375px, 768px, 1024px
- [ ] 4.3 Dark theme verification: all new UI matches existing dark theme (bg-neutral-950, amber accents)
- [x] 4.4 Run existing test suite to verify no regressions (633 pass, 0 fail)
- [ ] 4.5 Manual QA: create a fresh "Start Fresh" project and walk through all states
- [x] 4.6 Copywriter review of first-run prompt copy (completed — artifacts at `knowledge-base/product/design/onboarding/start-fresh-copy.md`)
