# Tasks: Start Fresh Onboarding

**Plan:** [2026-04-07-feat-start-fresh-onboarding-plan.md](../../plans/2026-04-07-feat-start-fresh-onboarding-plan.md)
**Issue:** #1751
**Branch:** `feat-start-fresh-onboarding`

[Updated 2026-04-07: Simplified per review — zero new files, inline state, dynamic SUGGESTED_PROMPTS]

## Prerequisites

- [ ] 0.1 Rebase `feat-start-fresh-onboarding` onto main (dependency branch merged as `54a727ee`)

## Phase 1: Dashboard State Derivation (inline in page.tsx)

- [ ] 1.1 Add inline KB state derivation to `app/(dashboard)/dashboard/page.tsx`
  - [ ] 1.1.1 Add `useEffect` + `useState` block that fetches `/api/kb/tree` on mount with cancellation guard
  - [ ] 1.1.2 Flatten `TreeNode` tree into `Set<string>` of `TreeNode.path` values (not `.name`)
  - [ ] 1.1.3 Check existence of 4 foundation paths: `overview/vision.md`, `marketing/brand-guide.md`, `product/business-validation.md`, `legal/privacy-policy.md`
  - [ ] 1.1.4 Derive: `visionExists`, `allFoundationsComplete`, `foundationCards` array with `done` booleans
  - [ ] 1.1.5 Handle errors: 401 → redirect, 503 → "workspace provisioning" state, network error → retry
- [ ] 1.2 Write tests for state derivation
  - [ ] 1.2.1 Test: empty KB tree → visionExists=false
  - [ ] 1.2.2 Test: vision.md only → visionExists=true, allFoundationsComplete=false
  - [ ] 1.2.3 Test: all 4 files → allFoundationsComplete=true
  - [ ] 1.2.4 Test: partial files → correct done booleans per card
  - [ ] 1.2.5 Test: API 503 → provisioning state shown
  - [ ] 1.2.6 Test: API error → graceful fallback

## Phase 2: Dashboard Conditional Rendering

- [ ] 2.1 Add loading skeleton
  - [ ] 2.1.1 While KB tree is loading, hide WelcomeCard, SUGGESTED_PROMPTS, and leader strip
  - [ ] 2.1.2 Show centered loading skeleton matching existing dark theme
- [ ] 2.2 Add first-run view (early return when `!visionExists && !isLoading`)
  - [ ] 2.2.1 Welcome message: "Your AI organization is ready. Tell us what you're building."
  - [ ] 2.2.2 Focused `ChatInput` with placeholder "Describe your startup idea..."
  - [ ] 2.2.3 Hide SUGGESTED_PROMPTS, WelcomeCard, and leader strip
  - [ ] 2.2.4 `handleSend` omits `leader` param — tag-and-route handles routing
  - [ ] 2.2.5 `handleSend` still calls `completeOnboarding()` for backward compatibility
- [ ] 2.3 Make SUGGESTED_PROMPTS dynamic for foundations phase
  - [ ] 2.3.1 Define `FOUNDATION_CARDS` constant: id, title, leaderId, kbPath, promptText, icon
  - [ ] 2.3.2 When `visionExists && !allFoundationsComplete`, populate SUGGESTED_PROMPTS from foundation cards
  - [ ] 2.3.3 Done cards: show checkmark badge + link to `/dashboard/kb/{kbPath}`
  - [ ] 2.3.4 Not-done cards: clickable → `insertRef.current(promptText, 0)` (existing pattern)
  - [ ] 2.3.5 Reuse existing grid layout: `grid-cols-2 md:grid-cols-4` (2-col mobile, 4-col desktop)
  - [ ] 2.3.6 Use `LEADER_BG_COLORS` for card color accents per leader
- [ ] 2.4 Write tests for conditional rendering
  - [ ] 2.4.1 Test: loading → skeleton shown, no WelcomeCard flash
  - [ ] 2.4.2 Test: first-run → welcome message + focused prompt, no leader strip
  - [ ] 2.4.3 Test: foundations → dynamic cards with correct done/not-done badges
  - [ ] 2.4.4 Test: all complete → existing SUGGESTED_PROMPTS (regression test)
  - [ ] 2.4.5 Test: card click → insertRef called with correct prompt text

## Phase 3: Vision.md Server-Side Creation

- [ ] 3.1 Add vision.md creation to `server/agent-runner.ts`
  - [ ] 3.1.1 In `sendUserMessage()`, after first message on workspace, check if `vision.md` exists
  - [ ] 3.1.2 If not, `mkdirSync('knowledge-base/overview/', { recursive: true })` in workspace
  - [ ] 3.1.3 Write minimal vision.md: `# Vision\n\n{founder's message text}`
  - [ ] 3.1.4 Wrap in try/catch — fire-and-forget with `.catch()` (Node 22 unhandled rejection)
- [ ] 3.2 Add CPO-scoped vision enhancement
  - [ ] 3.2.1 In `startAgentSession()`, only when `leaderId === "cpo"` or undefined
  - [ ] 3.2.2 Check if vision.md exists and is minimal (< 500 bytes)
  - [ ] 3.2.3 If minimal, append enhancement instruction to system prompt
  - [ ] 3.2.4 Instruction: "Enhance knowledge-base/overview/vision.md with sections: Mission, Target Audience, Value Proposition, Key Differentiators"
- [ ] 3.3 Write tests for vision creation
  - [ ] 3.3.1 Test: first message on empty workspace → vision.md created with message text
  - [ ] 3.3.2 Test: vision.md already exists → no overwrite
  - [ ] 3.3.3 Test: CPO session with minimal vision → enhancement instruction in system prompt
  - [ ] 3.3.4 Test: CMO session with minimal vision → no enhancement instruction (scoped to CPO)

## Phase 4: Polish and QA

- [ ] 4.1 Run markdownlint on all changed .md files
- [ ] 4.2 Responsive breakpoint audit: verify card grid at 375px, 768px, 1024px
- [ ] 4.3 Dark theme verification: all new UI matches existing dark theme (bg-neutral-950, amber accents)
- [ ] 4.4 Run existing test suite to verify no regressions
- [ ] 4.5 Manual QA: create a fresh "Start Fresh" project and walk through all states
- [ ] 4.6 Copywriter review of first-run prompt copy (before shipping)
