---
title: 'fix(cc-routing-panel): "Routing to the right Experts" hides Soleur Concierge once leaders are picked'
date: 2026-05-05
status: ready-for-work
type: bug-fix
issue: 3251
sibling_issues: [3250, 3252, 3253]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md
bundle_spec: knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md
branch: feat-one-shot-3251-routing-experts-concierge
---

# Fix CC routing panel hiding Soleur Concierge once leaders are picked (#3251)

## TL;DR

In the Command Center chat surface, the visible "routing panel" is **two distinct UI surfaces** that the issue body conflates into one:

1. **`isClassifying` chip** (`apps/web-platform/components/chat/chat-surface.tsx:606-615`) — renders the literal `"Routing to the right experts..."` string. It is gated on `hasUserMessage && !hasAssistantMessage && routeSource === null && workflow.state === "idle"`. The user reports this as "showing Soleur Concierge while leaders are still being matched," but the chip itself contains no Concierge avatar — the perception of "Concierge is shown" comes from the chip living next to a Concierge bubble that the cc-soleur-go path emits during routing.
2. **Routed-leaders strip** (`chat-surface.tsx:419-429`) — once `routeSource` flips to `"auto"` or `"mention"` AND `respondingLeaders.length > 0`, this strip renders `Auto-routed to <names>` / `Directed to @<names>`. `respondingLeaders` is derived from `messages.filter((m) => m.role === "assistant" && m.leaderId)` — Concierge (`cc_router`) only appears here if the Concierge bubble is included AND `cc_router` is treated as a leader by the strip's rendering. In practice, once domain leaders begin streaming, the strip shows only the routed *domain* leaders and the Concierge identity drops out of the panel header, even though the Concierge has been (and remains) the orchestrator of the conversation.

The user's expectation: **"Soleur Concierge should remain visible in the routing panel alongside the routed leaders, the same way it appears in the no-leaders-yet state."**

The fix is **explicit Concierge prefix in the routed-leaders strip**, not a structural change to the message list:

- When `routeSource` is set, render the strip as `<ConciergeChip /> + <separator> + <routed-leader chips>` so Concierge is always present alongside the routed leaders, regardless of whether `cc_router` is in `respondingLeaders`.
- Use `LeaderAvatar leaderId="cc_router"` for visual consistency with the Concierge bubble already in the message list.
- A11y: prefix the strip's accessible label with "Soleur Concierge" so screen readers announce the orchestrator.

A regression test (RTL) renders `<ChatSurface />` with the WS hook mocked into both states (no-leaders-yet AND leaders-resolved) and asserts the Concierge identity is present in both. **Visual regression** in this codebase is implemented as `@testing-library/react` DOM assertions, not Playwright pixel-diff — see `apps/web-platform/test/leader-avatar.test.tsx` and `apps/web-platform/test/message-bubble-header.test.tsx` for the pattern. The acceptance criterion in the issue body asks for a "screenshot test"; this plan reframes that to "DOM-state assertion test in both routing states" and explicitly scopes out a Playwright pixel-diff harness (none exists in `apps/web-platform/test/`; introducing one is out of scope and warrants its own brainstorm + plan).

## Issue context

- **Issue:** [#3251](https://github.com/jikig-ai/soleur/issues/3251) — P2, trust/visibility (not a hard blocker but a brand-trust regression).
- **Brainstorm:** [`2026-05-05-cc-session-bugs-batch-brainstorm.md`](https://github.com/jikig-ai/soleur/blob/feat-cc-session-bugs-batch/knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md) (lives on `feat-cc-session-bugs-batch` branch).
- **Bundle spec:** [`feat-cc-session-bugs-batch/spec.md`](https://github.com/jikig-ai/soleur/blob/feat-cc-session-bugs-batch/knowledge-base/project/specs/feat-cc-session-bugs-batch/spec.md).
- **Sibling issues:** #3250 (P1 prefill — separate one-shot), #3252 (P2 read-only OS allowlist), #3253 (P3 PDF availability message).
- **Branch:** `feat-one-shot-3251-routing-experts-concierge` off `main` (NOT off the bundle branch — keeps the cycle independent and avoids cross-bug rebase friction).
- **Draft PR coordination point:** #3249 (informational only; this PR will not target it).

## User-Brand Impact

**If this lands broken, the user experiences:** The routing strip continues to elide Concierge while domain leaders are streaming, OR a regression introduces double-rendered Concierge chips, OR the Concierge chip renders but with the wrong avatar/label (e.g., yellow-square fallback when the Soleur logo should render — see `leader-avatar.tsx:61-65`). The user reads "I lost track of who is actually answering" and trust in the routing UX erodes further.

**If this leaks, the user's data/workflow is exposed via:** No data exposure. The bug is a trust/visibility regression on the brand-front-door (Command Center chat). The risk class is the same as #3250: a brand-survival event for a first-touch user, even though the technical severity is P2.

**Brand-survival threshold:** `single-user incident`.

This threshold is inherited from the bundle brainstorm. The Concierge surface is the brand-visible front door for `/soleur:go`. Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`:

- CPO sign-off required at plan time (this plan; CPO assessment is captured in `## Domain Review`).
- `user-impact-reviewer` agent invoked at review time (handled by `plugins/soleur/skills/review/SKILL.md` conditional-agent block).

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (codebase as of HEAD on `main`) | Plan response |
|---|---|---|
| "Routing to the right Experts" panel exists as a single component | The string is `"Routing to the right experts..."` (lowercase `e`, ellipsis, no "panel" wrapper). It lives inline in `chat-surface.tsx:611` as the `isClassifying` chip's text. There is no separate "panel" component. The routed-leaders *strip* (`chat-surface.tsx:419-429`) is the second piece; it renders `Auto-routed to <names>` / `Directed to @<names>`. | Plan addresses the routed-leaders strip (line 419-429) where Concierge is structurally elided once `respondingLeaders` populates. The `isClassifying` chip is correct in the no-leaders-yet state and does not need modification. |
| Investigation pointer: `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` | The chat-page route file delegates to `<ChatSurface variant="full" />`. All routing-panel rendering lives in `apps/web-platform/components/chat/chat-surface.tsx`. The route file is a thin wrapper; the bug is not there. | Plan scopes edits to `chat-surface.tsx` (and a new sibling `routed-leaders-strip.tsx` extracted for testability). Route file is not edited. |
| "Concierge appears in the panel in both the no-leaders-yet AND leaders-resolved states" | The no-leaders-yet state renders the `isClassifying` chip, which is a generic spinner — Concierge does NOT actually appear in the chip itself. The user's perception of "Concierge is shown" comes from the cc-soleur-go path emitting Concierge bubbles into the message list. The leaders-resolved state's strip excludes Concierge by construction. | Plan reframes the AC: Concierge identity (avatar + name) appears in the routed-leaders strip in the leaders-resolved state. The no-leaders-yet `isClassifying` chip gets a Concierge avatar prefix so the two states are visually consistent (per the user's mental model). |
| Acceptance: "visual regression / screenshot test covers both states" | `apps/web-platform/test/` uses `@testing-library/react` for DOM-state assertions (see `leader-avatar.test.tsx`, `message-bubble-header.test.tsx`, `chat-surface-sidebar.test.tsx`). There is no Playwright pixel-diff harness — `playwright.config.ts` exists but is configured for E2E flows (`apps/web-platform/test/fixtures/qa-auth.ts`), not visual regression. | Plan implements DOM-state assertion tests for both states. A Playwright pixel-diff harness is explicitly **out of scope** and tracked as a separate enhancement issue if the operator wants pixel-perfect coverage. |
| `cc_router` is treated as a leader id everywhere | `cc_router` is the audit-log attribution id (`apps/web-platform/lib/cc-router-id.ts`). It IS in the `DOMAIN_LEADERS` array (`apps/web-platform/server/domain-leaders.ts:101`). It has special-case rendering in `LeaderAvatar` (`leader-avatar.tsx:65-82`) and `LEADER_BG_COLORS` / `LEADER_COLORS` (`leader-colors.ts:20,40`). Existing components (`MessageBubble`, `LeaderAvatar`, `ToolUseChip`) handle `cc_router` as a first-class leader. | Plan reuses the existing `LeaderAvatar` Concierge-rendering path. No new Concierge-special-casing is introduced; the strip becomes `cc_router`-aware via the same shared component. |

## Open Code-Review Overlap

**1 open scope-out touches files in this plan:**

- **#2223** — `perf(chat): useMemo ChatPage derivations (respondingLeaders, hasUser/Assistant, seenSoFar)`. P3, performance optimization. Touches `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:202-211` (the **route page**, not `chat-surface.tsx`). Even though the symbol name `respondingLeaders` collides, **the symbol lives in two places**: this plan modifies `chat-surface.tsx`'s `respondingLeaders` derivation (line 353-358); #2223 references the route-page derivation (which delegates to ChatSurface and may not even exist in current code — verification at work-time required).

  **Disposition: Acknowledge.** The perf fix is orthogonal to the visibility fix. Folding it in would balloon the scope (memoization audit across three IIFEs in two different files) and conflate "fix trust regression" with "shave parent re-render cost." The scope-out remains open. Rationale recorded for the next planner.

  **Verification at work-time:** `rg -n "respondingLeaders" apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — if zero hits, the issue's referenced location was already restructured (likely consolidated into `chat-surface.tsx`) and #2223 needs a comment + close. If non-zero, leave the issue alone.

## Hypotheses

### H1 — Routed-leaders strip filters out `cc_router` because it relies on `respondingLeaders`, which is derived from message-list `leaderId` values

**Mechanism:**

1. `respondingLeaders` is computed in `chat-surface.tsx:353-358`:
   ```ts
   const respondingLeaders = messages
     .filter((m) => m.role === "assistant" && m.leaderId)
     .reduce<DomainLeaderId[]>((acc, m) => {
       if (m.leaderId && !acc.includes(m.leaderId)) acc.push(m.leaderId);
       return acc;
     }, []);
   ```
2. The strip at `chat-surface.tsx:419-429` renders only when `routeSource && respondingLeaders.length > 0`. Concierge `cc_router` IS a valid `leaderId` and CAN appear in `respondingLeaders` if a Concierge assistant bubble has been emitted, but the visual presentation `Auto-routed to <getDisplayName(id)>...` does not distinguish Concierge from a domain leader — and worse, the moment domain leaders' bubbles arrive, the user's mental model is "Concierge handed off; domain leaders responded." The strip text reinforces that handoff narrative even when Concierge is still part of the orchestration.
3. Even when `cc_router` IS in `respondingLeaders`, the strip joins all names with a comma — so "Soleur Concierge, Marketing Lead" reads as a peer relationship, not "Concierge routing to Marketing Lead." The fix is presentational: prefix the strip with a dedicated Concierge slot so the orchestrator is always visually distinct.

**Confidence:** High. Direct code read confirms the structural issue.

### H2 — `isClassifying` chip is missing the Concierge avatar so the two states are visually inconsistent (no-leaders-yet → generic spinner; leaders-resolved → leader-name list)

**Mechanism:**

1. `chat-surface.tsx:606-615`:
   ```tsx
   {isClassifying && (
     <div className="flex justify-start">
       <div className="flex items-center gap-2 rounded-xl border border-neutral-800 bg-neutral-900 px-4 py-3">
         <span className="h-2 w-2 animate-pulse rounded-full bg-amber-500" />
         <span className="text-sm text-neutral-400">
           Routing to the right experts...
         </span>
       </div>
     </div>
   )}
   ```
2. There is no `LeaderAvatar` in this chip. The user's mental model "Concierge is matching me to leaders" is implicit — the *adjacent* Concierge bubble in the message list is what conveys it. When the chip disappears (leaders-resolved), the visual cue collapses.
3. Adding a `<LeaderAvatar leaderId="cc_router" size="sm" />` to the chip head + a "Soleur Concierge is routing..." accessible label produces the **visual consistency** the user is asking for: same Concierge identity in both states.

**Confidence:** Medium-High. Aligns with the user's verbatim "the same way it appears in the no-leaders-yet state."

### H3 (rejected) — The bug is in `routeSource` flipping too early or `activeLeaderIds` filtering out `cc_router`

`routeSource` is set in `lib/ws-client.ts:510` from a routing WS event; `activeLeaderIds` is derived from `state.activeStreams` (`lib/ws-client.ts:284`). Both are correct — the bug is **presentation**, not state. No state-machine change required.

## Implementation Phases

### Phase 0 — Pre-implementation verification

- [ ] Run `rg -n "respondingLeaders" apps/web-platform/` to confirm the symbol's full set of call sites. Expected: `chat-surface.tsx` derivation + the line referenced in #2223 (verify presence/absence).
- [ ] Run `rg -n 'isClassifying' apps/web-platform/` to confirm the chip is the only consumer; expected to match `chat-surface.tsx` only.
- [ ] Run `rg -n 'CC_ROUTER_LEADER_ID|cc_router' apps/web-platform/components/ apps/web-platform/lib/` to confirm `LeaderAvatar` is the canonical Concierge-rendering surface.
- [ ] Confirm `apps/web-platform/test/` has no Playwright visual-regression harness via `rg -ln 'toHaveScreenshot|toMatchVisual|expect.*screenshot' apps/web-platform/test/`. Expected: zero hits. If hits exist, this plan's "DOM-state assertion" framing must be revisited.

### Phase 1 — RED tests (failing before implementation)

Test file: `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` (NEW).

The test mocks `useWebSocket` from `@/lib/ws-client` and renders `<ChatSurface conversationId="test" variant="full" />` in three states:

**Test 1 — no-leaders-yet state shows Concierge identity**

```ts
// State: hasUserMessage=true, hasAssistantMessage=false, routeSource=null, workflow.state="idle"
mockUseWebSocket({
  messages: [{ id: "u1", role: "user", content: "hello", ... }],
  routeSource: null,
  workflow: { state: "idle" },
  activeLeaderIds: [],
  ...
});
render(<ChatSurface conversationId="test" variant="full" />);

const chip = await screen.findByText(/Routing to the right experts/i);
const chipContainer = chip.closest("[data-testid='cc-routing-chip']");
expect(chipContainer).toBeInTheDocument();
expect(chipContainer.querySelector("[aria-label='Soleur Concierge avatar']")).toBeInTheDocument();
```

**Test 2 — leaders-resolved state shows Concierge alongside routed leaders**

```ts
// State: hasUserMessage=true, hasAssistantMessage=true, routeSource="auto",
// respondingLeaders=["cmo"] (Concierge has handed off but user expects to still see Concierge)
mockUseWebSocket({
  messages: [
    { id: "u1", role: "user", content: "hello", ... },
    { id: "a1", role: "assistant", content: "routing to CMO", leaderId: "cc_router", ... },
    { id: "a2", role: "assistant", content: "marketing answer", leaderId: "cmo", ... },
  ],
  routeSource: "auto",
  workflow: { state: "idle" },
  activeLeaderIds: ["cmo"],
  ...
});
render(<ChatSurface conversationId="test" variant="full" />);

const strip = await screen.findByTestId("cc-routed-leaders-strip");
expect(strip).toBeInTheDocument();
// Concierge identity is present, regardless of whether cc_router is in respondingLeaders
expect(within(strip).getByLabelText("Soleur Concierge avatar")).toBeInTheDocument();
expect(within(strip).getByText(/Soleur Concierge/)).toBeInTheDocument();
// Routed leaders are also present
expect(within(strip).getByText(/Marketing/i)).toBeInTheDocument();
```

**Test 3 — leaders-resolved state with no Concierge bubble in messages STILL shows Concierge**

```ts
// State: respondingLeaders does NOT contain cc_router (Concierge bubble was elided
// or pruned), but routeSource is set — Concierge MUST still appear.
mockUseWebSocket({
  messages: [
    { id: "u1", role: "user", content: "hello", ... },
    { id: "a1", role: "assistant", content: "answer", leaderId: "cmo", ... },
  ],
  routeSource: "auto",
  ...
});
render(<ChatSurface conversationId="test" variant="full" />);

const strip = await screen.findByTestId("cc-routed-leaders-strip");
expect(within(strip).getByLabelText("Soleur Concierge avatar")).toBeInTheDocument();
```

**Test 4 — strip is NOT rendered when routeSource is null**

```ts
// State: pre-routing, strip should not render
mockUseWebSocket({
  messages: [...],
  routeSource: null,
  ...
});
render(<ChatSurface conversationId="test" variant="full" />);

expect(screen.queryByTestId("cc-routed-leaders-strip")).not.toBeInTheDocument();
```

Expected: all four tests **fail** before implementation:

- T1: chip has no Concierge avatar.
- T2 + T3: strip has no `data-testid` (line 420 has no testid attribute) and no Concierge avatar.
- T4: passes already (strip is gated on `routeSource && respondingLeaders.length > 0`).

### Phase 2 — GREEN implementation

**File 1: `apps/web-platform/components/chat/routed-leaders-strip.tsx` (NEW)**

Extract the strip into a dedicated component so the test surface is narrow. Component contract:

```tsx
"use client";

import { LeaderAvatar } from "@/components/leader-avatar";
import { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";
import type { DomainLeaderId } from "@/server/domain-leaders";

interface RoutedLeadersStripProps {
  routeSource: "auto" | "mention";
  routedLeaders: DomainLeaderId[]; // domain leaders only — cc_router is excluded
  getDisplayName: (id: DomainLeaderId) => string;
  /** Sidebar variant tightens left/right padding. */
  isFull: boolean;
}

export function RoutedLeadersStrip({
  routeSource,
  routedLeaders,
  getDisplayName,
  isFull,
}: RoutedLeadersStripProps) {
  // Filter cc_router out of routedLeaders defensively — the Concierge slot
  // is rendered explicitly so we never want a duplicated Concierge chip.
  const domainOnly = routedLeaders.filter((id) => id !== CC_ROUTER_LEADER_ID);

  return (
    <div
      data-testid="cc-routed-leaders-strip"
      className={`border-b border-neutral-800/50 px-4 py-2 ${isFull ? "md:px-6" : ""}`}
    >
      <span
        className="inline-flex items-center gap-1.5 rounded-full bg-neutral-800/50 px-3 py-1 text-xs text-neutral-400"
        aria-label={`Routing: Soleur Concierge ${routeSource === "auto" ? "auto-routed to" : "directed to"} ${domainOnly.map(getDisplayName).join(", ")}`}
      >
        {/* Concierge slot — always present once routeSource is set */}
        <LeaderAvatar leaderId={CC_ROUTER_LEADER_ID} size="sm" />
        <span>Soleur Concierge</span>
        <span className="text-neutral-600">·</span>
        {routeSource === "auto" ? (
          <>Auto-routed to {domainOnly.map(getDisplayName).join(", ")}</>
        ) : (
          <>Directed to @{domainOnly.map(getDisplayName).join(", @")}</>
        )}
      </span>
    </div>
  );
}
```

**File 2: `apps/web-platform/components/chat/chat-surface.tsx`** (modify)

- Import `RoutedLeadersStrip`.
- Replace lines 419-429 (the inline strip) with `<RoutedLeadersStrip routeSource={routeSource} routedLeaders={respondingLeaders} getDisplayName={getDisplayName} isFull={isFull} />` gated on `routeSource && respondingLeaders.some((id) => id !== CC_ROUTER_LEADER_ID)`. Reasoning for the gate refinement: the strip should render once at least one *domain* leader has resolved — pure-Concierge-only state is covered by the `isClassifying` chip below.
- Update lines 606-615 (the `isClassifying` chip) to add a Concierge avatar prefix:
  ```tsx
  {isClassifying && (
    <div className="flex justify-start" data-testid="cc-routing-chip">
      <div className="flex items-center gap-2 rounded-xl border border-neutral-800 bg-neutral-900 px-4 py-3">
        <LeaderAvatar leaderId={CC_ROUTER_LEADER_ID} size="sm" />
        <span className="h-2 w-2 animate-pulse rounded-full bg-amber-500" />
        <span className="text-sm text-neutral-400">
          Soleur Concierge is routing to the right experts...
        </span>
      </div>
    </div>
  )}
  ```
  - The text changes from `"Routing to the right experts..."` to `"Soleur Concierge is routing to the right experts..."` — this makes the orchestrator explicit and matches the user's mental model. Previous implicit "the chip means Concierge" becomes explicit.
- Add `import { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";` and `import { LeaderAvatar } from "@/components/leader-avatar";` if not already imported.

**Why a new component instead of inline?** Three reasons:

1. **Test isolation.** `RoutedLeadersStrip` can be unit-tested without rendering the full `ChatSurface` (which mounts a WS client, message list, input, etc.). Reduces test setup from ~80 LoC of mocks to ~10 LoC of props.
2. **Re-use surface.** If a future surface (KB-doc sidebar, embedded chat preview) needs the same strip, it imports the component instead of duplicating the JSX.
3. **Code-simplicity-reviewer compliance.** YAGNI is preserved — we extract because the test needs the seam, not because we anticipate a re-use. The new file is ≤60 LoC.

### Phase 3 — REFACTOR

- [ ] Verify `LeaderAvatar` size prop accepts `"sm"` (it does — `apps/web-platform/components/leader-avatar.tsx:29-33`).
- [ ] Verify the `cc_router` Concierge rendering renders the Soleur logo (per `leader-avatar.tsx:67-82`) — no yellow square fallback.
- [ ] Run `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` — all 4 tests pass.
- [ ] Run `apps/web-platform/test/chat-surface-sidebar.test.tsx` — confirm no regression. The sidebar variant uses the same code path.
- [ ] Run `bun test apps/web-platform/test/leader-avatar.test.tsx apps/web-platform/test/message-bubble-header.test.tsx apps/web-platform/test/tool-use-chip.test.tsx` — all Concierge-aware tests still pass.
- [ ] Run `bun run --cwd apps/web-platform typecheck` — no TS errors.
- [ ] Manual QA: load a Command Center session, send a message that triggers auto-routing to a domain leader, confirm the strip shows "Soleur Concierge · Auto-routed to <leader>" with the Soleur logo avatar.

### Phase 4 — Domain Review carry-forward and CPO sign-off

The `## User-Brand Impact` threshold is `single-user incident`. Per AGENTS.md `hr-weigh-every-decision-against-target-user-impact`:

- Plan-time CPO sign-off captured in `## Domain Review` (Phase 2.5 of the plan skill).
- Review-time `user-impact-reviewer` agent runs against the diff, scoped to `apps/web-platform/components/chat/**` and `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx`.

## Files to Edit

- `apps/web-platform/components/chat/chat-surface.tsx` (lines 419-429 routed-leaders strip; lines 606-615 isClassifying chip; imports).

## Files to Create

- `apps/web-platform/components/chat/routed-leaders-strip.tsx` (extracted strip component).
- `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` (RED→GREEN regression test).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` exists with 4 tests covering: no-leaders-yet shows Concierge identity, leaders-resolved shows Concierge + domain leaders, leaders-resolved-without-Concierge-bubble still shows Concierge, strip-not-rendered-pre-routing.
- [ ] All 4 tests pass on the feature branch.
- [ ] `apps/web-platform/components/chat/routed-leaders-strip.tsx` exists with a `data-testid="cc-routed-leaders-strip"` hook and an explicit Concierge slot via `<LeaderAvatar leaderId="cc_router" />`.
- [ ] `apps/web-platform/components/chat/chat-surface.tsx` `isClassifying` chip has `data-testid="cc-routing-chip"` and a Concierge avatar prefix.
- [ ] `bun run --cwd apps/web-platform typecheck` passes.
- [ ] `bun test apps/web-platform/test/leader-avatar.test.tsx apps/web-platform/test/message-bubble-header.test.tsx apps/web-platform/test/tool-use-chip.test.tsx apps/web-platform/test/chat-surface-sidebar.test.tsx` — no regression.
- [ ] No new dependencies introduced (no Playwright pixel-diff harness).
- [ ] PR body uses `Closes #3251` (not in the title — per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`).
- [ ] `user-impact-reviewer` agent reviewed the diff and signed off (handled by review skill conditional-agent block).
- [ ] Manual QA: screenshot of the routing strip in the leaders-resolved state attached to the PR description, showing "Soleur Concierge · Auto-routed to <leader>" with the Soleur logo avatar.

### Post-merge (operator)

- [ ] Visual smoke test on the deployed Command Center: open a fresh chat, send a message, confirm the routing strip shows Concierge alongside the routed leader. (No automated post-merge script — this is one operator-driven check.)

## Test Strategy

- **Unit**: `cc-routing-panel-concierge-visibility.test.tsx` mocks `useWebSocket` and renders `<ChatSurface />`. Assertions are DOM-state-based via `@testing-library/react`. This is the codebase's established pattern for "visual regression" — see `apps/web-platform/test/leader-avatar.test.tsx` for precedent.
- **Integration**: `chat-surface-sidebar.test.tsx` already exists; no edits needed — confirm no regression.
- **No new E2E test**. The Playwright fixtures in `apps/web-platform/test/fixtures/qa-auth.ts` are scoped to auth flows. Adding a routing-panel E2E test is a separate scope.
- **Visual regression (Playwright pixel-diff): explicitly out of scope.** No `toHaveScreenshot` harness exists in the repo. Introducing one is a multi-day infra add (CI image baselines, OS font drift handling, baseline storage strategy) that warrants its own brainstorm + plan. The issue's "screenshot test" requirement is satisfied via DOM-state assertions per the codebase convention.

## Risks

### R1 — Strip-rendering condition becomes too restrictive and the strip never appears

**Mechanism:** The plan changes the strip's gate from `routeSource && respondingLeaders.length > 0` to `routeSource && respondingLeaders.some((id) => id !== CC_ROUTER_LEADER_ID)`. If the only assistant message in `messages` is from `cc_router` (e.g., Concierge replied directly without routing to a domain leader), the strip won't render. This is intentional — pure-Concierge-only state is covered by the `isClassifying` chip + Concierge bubble — but if `routeSource` ever flips to `"mention"` or `"auto"` for a Concierge-only response, the strip would silently disappear.

**Mitigation:**

- T4 in the test suite asserts the strip does NOT render when `routeSource=null`.
- Add a manual QA step: trigger a `@cc_router` mention (if such a flow exists) and confirm the strip behavior.
- Defer to behavior: if `routeSource` is set but only Concierge has responded, the user already sees the Concierge bubble + the `isClassifying` chip handed off — the strip's absence is correct.

### R2 — `LeaderAvatar` component breaks when `leaderId="cc_router"` is passed in a strip context

**Mechanism:** `LeaderAvatar` has special-case rendering for `cc_router` (`leader-avatar.tsx:65-82`). The strip's parent has different padding/font sizing than the message-bubble parent. If `LeaderAvatar` makes container-context assumptions, the avatar could clip or misalign in the strip.

**Mitigation:**

- `LeaderAvatar` size prop accepts `"sm"` (h-5 w-5, icon 12px). Strip parent is text-xs leading-relaxed — the size matches.
- Test 2 asserts the avatar is in the DOM via `getByLabelText("Soleur Concierge avatar")`. Visual alignment is verified manually in QA + PR screenshot.

### R3 — Widening the `isClassifying` chip text breaks an existing test

**Mechanism:** Some test may assert the literal string `"Routing to the right experts..."`. Changing it to `"Soleur Concierge is routing to the right experts..."` breaks that assertion.

**Mitigation:**

- Pre-implementation: `rg "Routing to the right experts" apps/web-platform/test/`. Expected: zero hits (verified during plan research; no test currently asserts this string).
- If hits surface: update the test in the same PR.

### R4 — `respondingLeaders` carries `cc_router` in some sessions, producing a duplicated Concierge chip

**Mechanism:** Without the `domainOnly` filter in `RoutedLeadersStrip`, a session where `cc_router` is in `respondingLeaders` would render Concierge twice (once in the explicit slot, once in the comma-joined leader list).

**Mitigation:**

- The strip filters `cc_router` defensively: `const domainOnly = routedLeaders.filter((id) => id !== CC_ROUTER_LEADER_ID);`. Test 2 covers this case explicitly.

### R5 — Conflict with #2223 (perf scope-out) at merge time

**Mechanism:** If #2223 lands first and introduces `useMemo` around `respondingLeaders`, this plan's edit to the strip-rendering gate creates a merge conflict.

**Mitigation:**

- #2223 is open (P3, not yet started). This plan ships first. If #2223 lands during this plan's review window, rebase and adopt the memoized symbol — the conflict is mechanical (same line moved into a `useMemo`).

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled and threshold is `single-user incident`.
- **The `cc_router` symbol has special-case rendering in three files** (`leader-avatar.tsx`, `leader-colors.ts`, `message-bubble.tsx`). Any future widening of "what it means to be a Concierge" must update all three. This plan does not introduce a fourth special case — it reuses `LeaderAvatar`.
- **Concierge "is/handed off" wording.** The strip says "Soleur Concierge · Auto-routed to <leader>". This is technically accurate but may read as "Concierge handed off and is no longer involved." If a future PR introduces a "currently active orchestrator" indicator, this strip is the surface that should evolve. Out of scope here.
- **A11y label uses `aria-label`** which clobbers descendant text for screen readers. The strip's contents (Soleur logo via decorative `<img alt="">`, "Soleur Concierge" text, dot separator, "Auto-routed to..." text) are all readable, but the `aria-label` overrides the tree. Reviewer may prefer `aria-describedby` or wrapping text in a `<span role="status">`. The current shape is consistent with the rest of `chat-surface.tsx` (e.g., the message-bubble pattern), so we preserve consistency.

## Cross-References

- AGENTS.md `hr-weigh-every-decision-against-target-user-impact` — single-user incident threshold + CPO sign-off + user-impact-reviewer.
- AGENTS.md `cq-write-failing-tests-before` — TDD gate for plans with Test Scenarios.
- AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to` — `Closes #3251` in PR body.
- AGENTS.md `cm-when-proposing-to-clear-context-or` — resume prompt provided post-plan.
- Sibling plan: [`2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md`](./2026-05-05-fix-cc-concierge-prefill-on-resume-plan.md) — #3250, P1, separate one-shot.
- Brainstorm: [`2026-05-05-cc-session-bugs-batch-brainstorm.md`](https://github.com/jikig-ai/soleur/blob/feat-cc-session-bugs-batch/knowledge-base/project/brainstorms/2026-05-05-cc-session-bugs-batch-brainstorm.md).
- Code-review overlap: #2223 (P3 perf, acknowledged not folded).
- Learning precedent: `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` (Concierge / Soleur Concierge duplicated header — same domain, separate surface).

## Domain Review

**Domains relevant:** Product (CPO).

**Brainstorm carry-forward:** The bundle brainstorm (`2026-05-05-cc-session-bugs-batch-brainstorm.md`) assessed Engineering and Product domains for the bundle. For #3251 specifically, the Product lens is load-bearing (trust-collapse pattern); Engineering is a straightforward presentational fix. CMO/CLO/CFO/COO/CTO domain leaders are not relevant — no new capability, no marketing/legal/finance/ops/architectural implications.

### Product (CPO)

**Status:** reviewed (carry-forward from brainstorm + plan-time refresh).

**Assessment:** First-touch Concierge surface is brand-load-bearing. The fix preserves the user's mental model "Concierge is orchestrating" across both routing states, eliminating a trust-collapse moment when domain leaders begin streaming. The presentational change (Concierge slot + explicit "Soleur Concierge is routing..." text) is the minimum-viable fix for the visibility regression — no new product capability, no copy review needed beyond the existing brand voice for "Soleur Concierge" (consistent with `message-bubble.tsx:99-100` and `leader-avatar.tsx:71`).

**CPO sign-off (plan-time):** Approved. The fix is scoped, reversible, and aligned with the brand-front-door framing in the bundle brainstorm. Defer copy-review specialist (no copywriter recommended in brainstorm Domain Assessments — the strings are existing brand-voice usage extended, not net-new copy).

### Product/UX Gate

**Tier:** advisory.

**Decision:** auto-accepted (pipeline). This plan modifies an existing user-facing component (`chat-surface.tsx`) and adds a small extracted sibling (`routed-leaders-strip.tsx`). It does not create new user-facing pages, modals, dialogs, or multi-step flows. Per the Product/UX Gate criteria, this is **ADVISORY**, not BLOCKING. The plan is being run in pipeline mode (one-shot) — Step 2 ADVISORY auto-accepts in pipeline.

**Agents invoked:** none (CPO carry-forward sufficient for this scope).

**Skipped specialists:** ux-design-lead (justification: no new user-facing surface; modifying an existing chip + strip with brand-consistent identity rendering — no wireframes needed); copywriter (justification: no new copy; reuses existing "Soleur Concierge" brand voice; brainstorm Domain Assessments did not recommend a copywriter for #3251).

**Pencil available:** N/A.

#### Findings

- The fix is minimum-viable and reversible.
- The `aria-label` pattern is consistent with the rest of `chat-surface.tsx`. Reviewer may prefer a more granular a11y treatment; if so, fix-inline at review time.
- The `isClassifying` chip text widening ("Soleur Concierge is routing to the right experts...") makes the orchestrator explicit, addressing the user's verbatim "the same way it appears in the no-leaders-yet state."

## Resume Prompt (post-plan)

```text
/soleur:work knowledge-base/project/plans/2026-05-05-fix-cc-routing-panel-hides-concierge-plan.md

Branch: feat-one-shot-3251-routing-experts-concierge.
Worktree: .worktrees/feat-one-shot-3251-routing-experts-concierge/.
Issue: #3251.
PR: TBD (open on /ship).
Plan reviewed and deepened. Implementation next: extract RoutedLeadersStrip, add Concierge slot, widen isClassifying chip, write 4-test RED→GREEN suite.
```
