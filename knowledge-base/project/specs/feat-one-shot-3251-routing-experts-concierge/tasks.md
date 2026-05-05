---
title: Tasks for fix(cc-routing-panel) Concierge visibility (#3251)
date: 2026-05-05
plan: knowledge-base/project/plans/2026-05-05-fix-cc-routing-panel-hides-concierge-plan.md
issue: 3251
branch: feat-one-shot-3251-routing-experts-concierge
---

# Tasks — Fix CC routing panel hiding Soleur Concierge (#3251)

## Phase 0 — Pre-implementation verification

- [ ] 0.1 Run `rg -n 'respondingLeaders' apps/web-platform/` and record all hits. Confirm `chat-surface.tsx:353-358` is the canonical derivation. Note any hits in `app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` (relevant to #2223 overlap acknowledgment).
- [ ] 0.2 Run `rg -n 'isClassifying' apps/web-platform/` and confirm only `chat-surface.tsx` consumes it.
- [ ] 0.3 Run `rg -n 'CC_ROUTER_LEADER_ID|cc_router' apps/web-platform/components/ apps/web-platform/lib/` and confirm `LeaderAvatar` is the canonical Concierge-rendering surface.
- [ ] 0.4 Run `rg -ln 'toHaveScreenshot|toMatchVisual|expect.*screenshot' apps/web-platform/test/` and confirm zero hits (no Playwright pixel-diff harness exists; DOM-state assertions are the codebase convention).
- [ ] 0.5 Run `rg "Routing to the right experts" apps/web-platform/test/` and confirm zero hits before changing the chip text.

## Phase 1 — RED tests

- [ ] 1.1 Create `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx`.
- [ ] 1.2 Mock `useWebSocket` from `@/lib/ws-client` with the Test 1 state (no-leaders-yet). Assert chip has `data-testid="cc-routing-chip"` AND a `[aria-label='Soleur Concierge avatar']` descendant. Expected: FAIL.
- [ ] 1.3 Add Test 2 (leaders-resolved with Concierge bubble in messages). Assert strip has `data-testid="cc-routed-leaders-strip"`, contains a Concierge avatar, and contains the routed-leader name. Expected: FAIL.
- [ ] 1.4 Add Test 3 (leaders-resolved WITHOUT Concierge bubble in messages). Assert Concierge avatar is still present in the strip. Expected: FAIL.
- [ ] 1.5 Add Test 4 (pre-routing). Assert strip is NOT rendered when `routeSource=null`. Expected: PASS already (regression guard).
- [ ] 1.6 Run `bun test apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` and confirm 3 FAIL + 1 PASS.

## Phase 2 — GREEN implementation

### 2.1 Extract RoutedLeadersStrip

- [ ] 2.1.1 Create `apps/web-platform/components/chat/routed-leaders-strip.tsx` with the contract from the plan body.
- [ ] 2.1.2 Add `data-testid="cc-routed-leaders-strip"`.
- [ ] 2.1.3 Filter `cc_router` from `routedLeaders` defensively (avoid duplicate Concierge chip).
- [ ] 2.1.4 Use `<LeaderAvatar leaderId={CC_ROUTER_LEADER_ID} size="sm" />` for the Concierge slot.
- [ ] 2.1.5 Wire `aria-label` to describe the routing relationship.

### 2.2 Update chat-surface.tsx

- [ ] 2.2.1 Add imports: `RoutedLeadersStrip` (new), `CC_ROUTER_LEADER_ID` (existing module), `LeaderAvatar` (existing).
- [ ] 2.2.2 Replace inline strip (lines 419-429) with `<RoutedLeadersStrip ... />` gated on `routeSource && respondingLeaders.some((id) => id !== CC_ROUTER_LEADER_ID)`.
- [ ] 2.2.3 Update `isClassifying` chip (lines 606-615): add `data-testid="cc-routing-chip"`, prepend `<LeaderAvatar leaderId="cc_router" size="sm" />`, change text to `"Soleur Concierge is routing to the right experts..."`.

### 2.3 Verify GREEN

- [ ] 2.3.1 Re-run `bun test apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` — all 4 PASS.
- [ ] 2.3.2 Run `bun run --cwd apps/web-platform typecheck` — no TS errors.
- [ ] 2.3.3 Run regression suite: `bun test apps/web-platform/test/leader-avatar.test.tsx apps/web-platform/test/message-bubble-header.test.tsx apps/web-platform/test/tool-use-chip.test.tsx apps/web-platform/test/chat-surface-sidebar.test.tsx` — no failures.

## Phase 3 — REFACTOR + manual QA

- [ ] 3.1 Visually verify Concierge avatar size in the strip (h-5 w-5 / text-xs context). Adjust `size` prop if mismatch.
- [ ] 3.2 Verify Soleur logo (`/icons/soleur-logo-mark.png`) renders, not yellow square fallback (per `leader-avatar.tsx:67-82` special-case branch).
- [ ] 3.3 Manual QA in browser: load Command Center, send a message that auto-routes to a domain leader, confirm strip shows "Soleur Concierge · Auto-routed to <leader>".
- [ ] 3.4 Manual QA: capture screenshot of the strip in the leaders-resolved state for the PR body.
- [ ] 3.5 Manual QA: capture screenshot of the chip in the no-leaders-yet state showing the new Concierge avatar prefix.

## Phase 4 — Ship

- [ ] 4.1 Commit: `git add apps/web-platform/components/chat/routed-leaders-strip.tsx apps/web-platform/components/chat/chat-surface.tsx apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx knowledge-base/project/plans/ knowledge-base/project/specs/feat-one-shot-3251-routing-experts-concierge/`.
- [ ] 4.2 Run `skill: soleur:compound` before commit.
- [ ] 4.3 Push branch.
- [ ] 4.4 Run `skill: soleur:review` against the branch (multi-agent — code-simplicity, architecture, user-impact-reviewer auto-included via `single-user incident` threshold).
- [ ] 4.5 Run `skill: soleur:qa` for any review-suggested DOM-state additions.
- [ ] 4.6 Open PR with `Closes #3251` in body. Title: `fix(cc-routing-panel): preserve Soleur Concierge identity once leaders are picked`.
- [ ] 4.7 Attach manual-QA screenshots to PR body.
- [ ] 4.8 Set semver label `semver:patch` (already on the issue).
- [ ] 4.9 Auto-merge: `gh pr merge <number> --squash --auto`. Poll until MERGED.
- [ ] 4.10 Run `cleanup-merged` post-merge.
- [ ] 4.11 Operator post-merge smoke test: open Command Center on prod after deploy, confirm strip behavior visually.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-05-fix-cc-routing-panel-hides-concierge-plan.md`
- Issue: #3251
- Sibling P1 plan (separate cycle): `knowledge-base/project/plans/2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md` (#3250)
- Open code-review overlap: #2223 (acknowledged, not folded)
- Brainstorm: `feat-cc-session-bugs-batch` branch — `knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md`
