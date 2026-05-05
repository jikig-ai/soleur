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

## Enhancement Summary

**Deepened on:** 2026-05-05

**Sections enhanced:** Research Reconciliation (added 2 rows), Open Code-Review Overlap (verification result), Implementation Phases 1 & 2 (test scaffolding + name-vs-title resolution), Risks (added R6: Concierge bare name), Cross-References (added Concierge name learning). New "## Research Insights" subsection added under Implementation Phase 2.

**Research sources used:**
- Local repo: `apps/web-platform/test/mocks/use-websocket.ts` (`createWebSocketMock` factory; routeSource/activeLeaderIds/messages overrides — perfect for the 4-test suite).
- Local repo: `apps/web-platform/test/mocks/use-team-names.ts` (`createUseTeamNamesMock`; `getDisplayName` defaults to `id.toUpperCase()` in tests).
- Local repo: `apps/web-platform/server/domain-leaders.ts:101-115` — `cc_router` has `name: "Concierge"` AND `title: "Soleur Concierge"`. Two different fields with different presentation roles.
- Local repo: `apps/web-platform/hooks/use-team-names.tsx:37,123-131` — `getDisplayName(id)` returns `name` (Concierge), not `title` (Soleur Concierge). Direct use of `getDisplayName("cc_router")` would emit bare "Concierge" — the exact regression #3225 fixed in `message-bubble.tsx`.
- Local repo: `apps/web-platform/test/chat-surface-sidebar.test.tsx` (38-line scaffold demonstrating the canonical mock pattern: `vi.mock("@/lib/ws-client", () => ({ useWebSocket: () => wsReturn }))` + `wsReturn = createWebSocketMock({...})` reset in `beforeEach`).
- Local learning: `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` — duplicated "Concierge / Soleur Concierge" header pattern; `name` vs `title` confusion is the same surface this plan must avoid re-introducing.
- `gh issue view 2223` — verified #2223's referenced location (`page.tsx:202-211`) no longer contains `respondingLeaders`. Symbol moved into `chat-surface.tsx`. Issue needs a comment + rebase before this PR ships.

### Key Improvements

1. **Concierge bare-name regression caught at deepen.** `getDisplayName("cc_router") === "Concierge"`, not `"Soleur Concierge"`. The plan now mandates `RoutedLeadersStrip` hardcodes `"Soleur Concierge"` (or reads `DOMAIN_LEADERS.find(l => l.id === "cc_router").title`) — never `getDisplayName`. Same hazard class as #3225's bare-Concierge bubble.
2. **Test scaffold reuse identified.** `createWebSocketMock` is a satisfies-typed factory with all relevant overrides (`routeSource`, `activeLeaderIds`, `messages`, `workflow`). The 4-test suite reuses it instead of building bespoke mocks.
3. **#2223 overlap verified obsolete at the referenced location.** `respondingLeaders` no longer lives in `page.tsx:202-211`. The acknowledgment in `## Open Code-Review Overlap` is upgraded to "stale reference; comment on #2223 in same PR with the new location and let the issue author decide whether to keep, rescope, or close."
4. **Test 2 setup pinned.** Test mocks need both a Concierge bubble (`leaderId: "cc_router"`) AND a domain-leader bubble (`leaderId: "cmo"`) in `messages` to assert the strip renders both identities side-by-side. Earlier test sketch under-specified.
5. **Strip-rendering gate clarified.** New gate `routeSource && respondingLeaders.some((id) => id !== CC_ROUTER_LEADER_ID)`: cleaner intent ("at least one domain leader resolved") + safer regression behavior (Concierge-only state stays in the chip flow).

### New Considerations Discovered

- **`name` vs `title` discipline must be encoded in the new component.** Add a comment in `routed-leaders-strip.tsx` referencing #3225: "Concierge slot uses the literal 'Soleur Concierge' (matches `DOMAIN_LEADERS.title`); never `getDisplayName('cc_router')` which returns the bare name."
- **`leader.title` is the canonical source.** Reading `DOMAIN_LEADERS.find((l) => l.id === CC_ROUTER_LEADER_ID)?.title ?? "Soleur Concierge"` gives a single source of truth and survives a future rename. Plan adopts this over a string literal.
- **Test scaffold details for `useSearchParams` and `useRouter`.** `chat-surface.tsx:178-181` reads `searchParams.get("leader")` and `searchParams.get("msg")`. The 4-test suite must mock `next/navigation` as in `chat-surface-sidebar.test.tsx:30-34` with an empty `URLSearchParams()` — otherwise the auto-start logic at lines ~310 may fire and pollute assertions.
- **`useTeamNames` mock returns `id.toUpperCase()` for `getDisplayName`** in test mode. Test 2's expectation `getByText(/Marketing/i)` would match `"CMO"` (uppercase id). Adjust the assertion to `getByText(/CMO/i)` OR override the mock to return `"Marketing"` for `cmo`. Plan locks in the second option (override mock) so the test assertion reads naturally.
- **`workflow.state === "idle"` is the canonical no-leader state**, but a session in `workflow.state === "active"` (post-routing) does NOT re-trigger the `isClassifying` chip even if `messages` changes — the chip is gated on `routeSource === null && workflow.state === "idle"`. Test 1 must explicitly set `workflow: { state: "idle" }` to satisfy the gate (already in plan; called out for clarity).
- **The `isClassifying` chip's data-testid is new** — searching the codebase for existing `cc-routing-chip` returns zero hits, confirming no naming collision.

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

**1 open scope-out touches files in this plan (verified at deepen-plan):**

- **#2223** — `perf(chat): useMemo ChatPage derivations (respondingLeaders, hasUser/Assistant, seenSoFar)`. P3, performance optimization. Issue body references `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx:202-211`. **Verified at deepen-plan via `grep -n "respondingLeaders" apps/web-platform/app/\(dashboard\)/dashboard/chat/\[conversationId\]/page.tsx`: ZERO hits.** The symbol moved into `chat-surface.tsx:353-358` (likely during a prior consolidation PR). The location cited in #2223 no longer exists.

  **Disposition: Acknowledge + comment on the issue.** The perf fix is still valid in concept (the IIFE in `chat-surface.tsx` re-runs on every parent re-render), but the file path and line numbers in the issue body are stale. This PR will:

  1. Add an inline comment on #2223 with the corrected location (`chat-surface.tsx:353-358`) and a note that the perf concern is orthogonal to this visibility fix.
  2. Leave the issue open for the original author / next planner to decide: rescope to `chat-surface.tsx` and refresh, fold into a future ChatSurface refactor, or close as superseded by structural changes.

  **No fold-in here.** Scope discipline: this PR is a 2-file presentational fix; bundling a memoization audit (which would also touch `seenSoFar` in `chat-surface.tsx:329-367`) doubles the surface area and the review cost.

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

- [x] Run `rg -n "respondingLeaders" apps/web-platform/` to confirm the symbol's full set of call sites. Expected: `chat-surface.tsx` derivation + the line referenced in #2223 (verify presence/absence).
- [x] Run `rg -n 'isClassifying' apps/web-platform/` to confirm the chip is the only consumer; expected to match `chat-surface.tsx` only.
- [x] Run `rg -n 'CC_ROUTER_LEADER_ID|cc_router' apps/web-platform/components/ apps/web-platform/lib/` to confirm `LeaderAvatar` is the canonical Concierge-rendering surface.
- [x] Confirm `apps/web-platform/test/` has no Playwright visual-regression harness via `rg -ln 'toHaveScreenshot|toMatchVisual|expect.*screenshot' apps/web-platform/test/`. Expected: zero hits. If hits exist, this plan's "DOM-state assertion" framing must be revisited.

### Phase 1 — RED tests (failing before implementation)

Test file: `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` (NEW).

**Test scaffold (canonical pattern, mirroring `chat-surface-sidebar.test.tsx`).**

```tsx
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, within } from "@testing-library/react";
import { createUseTeamNamesMock } from "./mocks/use-team-names";
import { createWebSocketMock } from "./mocks/use-websocket";

let wsReturn = createWebSocketMock();

vi.mock("@/lib/ws-client", () => ({
  useWebSocket: () => wsReturn,
}));

// Override `getDisplayName` so the strip's leader-list renders human names,
// not the default `id.toUpperCase()` shim. Avoids matching against "CMO"
// when the assertion reads more naturally as `Marketing Lead`.
vi.mock("@/hooks/use-team-names", () => ({
  useTeamNames: () => createUseTeamNamesMock({
    getDisplayName: (id) =>
      id === "cmo" ? "Marketing Lead" : id.toUpperCase(),
  }),
  TeamNamesProvider: ({ children }: { children: React.ReactNode }) => children,
}));

const mockSearchParams = new URLSearchParams();
vi.mock("next/navigation", () => ({
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({ replace: vi.fn(), push: vi.fn() }),
  usePathname: () => "/dashboard/chat/test-id",
}));

describe("ChatSurface — Soleur Concierge visibility in routing panel (#3251)", () => {
  beforeEach(() => {
    wsReturn = createWebSocketMock();
  });

  async function renderFull() {
    const { ChatSurface } = await import("@/components/chat/chat-surface");
    return render(<ChatSurface conversationId="test-id" variant="full" />);
  }

  // ... tests below
});
```

**Test 1 — no-leaders-yet state shows Concierge identity in the chip**

```tsx
it("T1 — isClassifying chip has Concierge avatar + 'Soleur Concierge is routing...' text", async () => {
  wsReturn = createWebSocketMock({
    messages: [
      { id: "u1", role: "user", content: "hello", type: "text" },
    ],
    routeSource: null,
    workflow: { state: "idle" },
    activeLeaderIds: [],
  });
  await renderFull();

  const chip = await screen.findByTestId("cc-routing-chip");
  expect(chip).toBeInTheDocument();
  expect(within(chip).getByLabelText("Soleur Concierge avatar")).toBeInTheDocument();
  expect(within(chip).getByText(/Soleur Concierge is routing to the right experts/i))
    .toBeInTheDocument();
});
```

**Test 2 — leaders-resolved state shows Concierge alongside routed leaders**

```tsx
it("T2 — strip renders Concierge slot + routed-leader name when both bubbles present", async () => {
  wsReturn = createWebSocketMock({
    messages: [
      { id: "u1", role: "user", content: "hello", type: "text" },
      { id: "a1", role: "assistant", content: "routing", leaderId: "cc_router", type: "text" },
      { id: "a2", role: "assistant", content: "answer", leaderId: "cmo", type: "text" },
    ],
    routeSource: "auto",
    workflow: { state: "idle" },
    activeLeaderIds: ["cmo"],
  });
  await renderFull();

  const strip = await screen.findByTestId("cc-routed-leaders-strip");
  expect(within(strip).getByLabelText("Soleur Concierge avatar")).toBeInTheDocument();
  // Hardcoded "Soleur Concierge" — NOT getDisplayName('cc_router') which returns "Concierge"
  expect(within(strip).getByText("Soleur Concierge")).toBeInTheDocument();
  // Routed leaders are also present
  expect(within(strip).getByText(/Marketing Lead/i)).toBeInTheDocument();
});
```

**Test 3 — leaders-resolved with NO `cc_router` in messages still shows Concierge**

```tsx
it("T3 — strip shows Concierge even when respondingLeaders excludes cc_router", async () => {
  wsReturn = createWebSocketMock({
    messages: [
      { id: "u1", role: "user", content: "hello", type: "text" },
      { id: "a1", role: "assistant", content: "answer", leaderId: "cmo", type: "text" },
    ],
    routeSource: "auto",
    activeLeaderIds: ["cmo"],
  });
  await renderFull();

  const strip = await screen.findByTestId("cc-routed-leaders-strip");
  expect(within(strip).getByLabelText("Soleur Concierge avatar")).toBeInTheDocument();
  expect(within(strip).getByText("Soleur Concierge")).toBeInTheDocument();
});
```

**Test 4 — strip NOT rendered when `routeSource` is null**

```tsx
it("T4 — strip is absent when routeSource is null (pre-routing regression guard)", async () => {
  wsReturn = createWebSocketMock({
    messages: [
      { id: "u1", role: "user", content: "hello", type: "text" },
    ],
    routeSource: null,
  });
  await renderFull();

  expect(screen.queryByTestId("cc-routed-leaders-strip")).not.toBeInTheDocument();
});
```

**Test 5 — bare "Concierge" string never appears alongside "Soleur Concierge" (drift guard)**

```tsx
it("T5 — strip never emits the bare 'Concierge' alongside 'Soleur Concierge' (#3225 regression)", async () => {
  wsReturn = createWebSocketMock({
    messages: [
      { id: "u1", role: "user", content: "hello", type: "text" },
      { id: "a1", role: "assistant", content: "routing", leaderId: "cc_router", type: "text" },
      { id: "a2", role: "assistant", content: "answer", leaderId: "cmo", type: "text" },
    ],
    routeSource: "auto",
    activeLeaderIds: ["cmo"],
  });
  await renderFull();

  const strip = await screen.findByTestId("cc-routed-leaders-strip");
  // Match the pattern from `2026-05-05-defense-relaxation-must-name-new-ceiling.md`:
  // count occurrences of "Concierge" in the textContent — should be exactly 1
  // (from "Soleur Concierge"), never 2 (which would mean a duplicated bare "Concierge").
  const concierges = strip.textContent?.match(/Concierge/g) ?? [];
  expect(concierges).toHaveLength(1);
});
```

Expected before implementation:

- T1: FAIL — chip has no `data-testid="cc-routing-chip"` and no Concierge avatar.
- T2 + T3: FAIL — strip has no `data-testid="cc-routed-leaders-strip"`, no Concierge avatar, no "Soleur Concierge" literal.
- T4: PASS already (strip is gated on `routeSource && respondingLeaders.length > 0`).
- T5: PASS-vacuous (no strip with the testid yet — `findByTestId` would throw before the regex check). Becomes load-bearing after Phase 2.

### Phase 2 — GREEN implementation

**File 1: `apps/web-platform/components/chat/routed-leaders-strip.tsx` (NEW)**

Extract the strip into a dedicated component so the test surface is narrow. Component contract:

```tsx
"use client";

import { LeaderAvatar } from "@/components/leader-avatar";
import { CC_ROUTER_LEADER_ID } from "@/lib/cc-router-id";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { DomainLeaderId } from "@/server/domain-leaders";

/**
 * Concierge presentation literal.
 *
 * Resolves to "Soleur Concierge" via `DOMAIN_LEADERS[cc_router].title`,
 * NOT the bare `name: "Concierge"`. `getDisplayName('cc_router')` returns
 * the bare name — using it here re-introduces the duplicated header
 * regression #3225 fixed in `message-bubble.tsx`. See
 * `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md`.
 */
const CONCIERGE_TITLE =
  DOMAIN_LEADERS.find((l) => l.id === CC_ROUTER_LEADER_ID)?.title ??
  "Soleur Concierge";

interface RoutedLeadersStripProps {
  routeSource: "auto" | "mention";
  routedLeaders: DomainLeaderId[]; // any leader ids — cc_router is filtered defensively below
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
  // Filter cc_router out defensively — the Concierge slot is rendered
  // explicitly so we never want a duplicated chip from the comma-joined list.
  const domainOnly = routedLeaders.filter((id) => id !== CC_ROUTER_LEADER_ID);

  return (
    <div
      data-testid="cc-routed-leaders-strip"
      className={`border-b border-neutral-800/50 px-4 py-2 ${isFull ? "md:px-6" : ""}`}
    >
      <span
        className="inline-flex items-center gap-1.5 rounded-full bg-neutral-800/50 px-3 py-1 text-xs text-neutral-400"
        aria-label={`Routing: ${CONCIERGE_TITLE} ${routeSource === "auto" ? "auto-routed to" : "directed to"} ${domainOnly.map(getDisplayName).join(", ")}`}
      >
        {/* Concierge slot — always present once routeSource is set */}
        <LeaderAvatar leaderId={CC_ROUTER_LEADER_ID} size="sm" />
        <span>{CONCIERGE_TITLE}</span>
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
3. **Code-simplicity-reviewer compliance.** YAGNI is preserved — we extract because the test needs the seam, not because we anticipate a re-use. The new file is ≤70 LoC.

### Research Insights (deepen-plan)

**Best practices applied:**

- Reuse the existing test scaffold (`createWebSocketMock` + `createUseTeamNamesMock`) rather than building bespoke mocks. Both factories use `satisfies` against `ReturnType<typeof useWebSocket>` / `ReturnType<typeof useTeamNames>`, so a future hook-shape change fails compile here, not at test runtime — exactly the drift-resistance pattern documented in the factory comments.
- Use `module-scope const` for the Concierge title (`CONCIERGE_TITLE`) so it resolves once at import time (cheap) and the source-of-truth is the `DOMAIN_LEADERS` array, not a string literal scattered across components. This survives a future rename of the `title` field without a grep-and-replace.
- Pin the `next/navigation` mock with an empty `URLSearchParams()` so the auto-start-on-mount logic (gated on `searchParams.get("leader")` + `searchParams.get("msg")`) does NOT fire during tests and pollute `wsReturn.startSession` call counts.

**Anti-patterns avoided:**

- DON'T call `getDisplayName(CC_ROUTER_LEADER_ID)` in the strip — returns bare "Concierge". Direct read of `DOMAIN_LEADERS.find(...).title` is the only safe path.
- DON'T pass `respondingLeaders` directly into the strip's `routedLeaders` prop without filtering — Concierge appears twice (explicit slot + comma-list).
- DON'T add a Concierge-special-case to `getDisplayName` itself — the hook's current contract returns `name`, and changing it would ripple through every leader-list rendering surface (header, message-bubble, footer cost line). Special-case the strip, not the hook.

**Edge cases:**

- Concierge-only response (Concierge replied without routing to a domain leader): the new strip-render gate `routeSource && respondingLeaders.some((id) => id !== CC_ROUTER_LEADER_ID)` evaluates false → strip is hidden, chip continues to show. Correct behavior — the user sees the Concierge bubble + chip, no orphan strip.
- `routeSource === "mention"` with a `@cc_router` mention (if such a flow ever exists): `respondingLeaders` would contain only `cc_router`, the gate evaluates false, no strip renders. Same behavior as Concierge-only response — the chip + bubble cover the UX.
- `routeSource` flips between values mid-conversation: the strip re-renders with the new `routedLeaders`. Concierge slot is stable (always present once `routeSource` is set + at least one domain leader resolved).

**References:**

- `apps/web-platform/test/mocks/use-websocket.ts` — `createWebSocketMock` factory.
- `apps/web-platform/test/mocks/use-team-names.ts` — `createUseTeamNamesMock` factory.
- `apps/web-platform/test/chat-surface-sidebar.test.tsx` — canonical scaffold pattern.
- `apps/web-platform/server/domain-leaders.ts:101-115` — `cc_router` definition (`name`, `title`, `internal: true`).
- `knowledge-base/project/learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` — the bare-Concierge drift hazard this plan inherits the regression guard from.

### Phase 3 — REFACTOR

- [x] Verify `LeaderAvatar` size prop accepts `"sm"` (it does — `apps/web-platform/components/leader-avatar.tsx:29-33`).
- [x] Verify the `cc_router` Concierge rendering renders the Soleur logo (per `leader-avatar.tsx:67-82`) — no yellow square fallback.
- [x] Run `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` — all 4 tests pass.
- [x] Run `apps/web-platform/test/chat-surface-sidebar.test.tsx` — confirm no regression. The sidebar variant uses the same code path.
- [x] Run `bun test apps/web-platform/test/leader-avatar.test.tsx apps/web-platform/test/message-bubble-header.test.tsx apps/web-platform/test/tool-use-chip.test.tsx` — all Concierge-aware tests still pass.
- [x] Run `bun run --cwd apps/web-platform typecheck` — no TS errors.
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

- [x] `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` exists with 5 tests covering: no-leaders-yet shows Concierge identity (T1), leaders-resolved shows Concierge + domain leaders (T2), leaders-resolved-without-Concierge-bubble still shows Concierge (T3), strip-not-rendered-pre-routing (T4), bare-Concierge drift guard (T5).
- [x] All 5 tests pass on the feature branch.
- [x] `apps/web-platform/components/chat/routed-leaders-strip.tsx` exists with a `data-testid="cc-routed-leaders-strip"` hook and an explicit Concierge slot via `<LeaderAvatar leaderId="cc_router" />`.
- [x] `apps/web-platform/components/chat/chat-surface.tsx` `isClassifying` chip has `data-testid="cc-routing-chip"` and a Concierge avatar prefix.
- [x] `bun run --cwd apps/web-platform typecheck` passes.
- [x] `bun test apps/web-platform/test/leader-avatar.test.tsx apps/web-platform/test/message-bubble-header.test.tsx apps/web-platform/test/tool-use-chip.test.tsx apps/web-platform/test/chat-surface-sidebar.test.tsx` — no regression.
- [x] No new dependencies introduced (no Playwright pixel-diff harness).
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
- Deepen-plan verified #2223's referenced location is stale (`page.tsx:202-211` no longer contains `respondingLeaders`). PR will leave a comment on #2223 with the corrected location; merge conflict probability is low.

### R6 — Concierge bare-name regression re-introduced via `getDisplayName('cc_router')`

**Mechanism:** `getDisplayName(id)` in `apps/web-platform/hooks/use-team-names.tsx:123-131` reads from `leaderNameMap` which maps `id → name` (NOT `id → title`). For `cc_router`: `name = "Concierge"`, `title = "Soleur Concierge"`. A naive implementation that calls `getDisplayName("cc_router")` for the Concierge slot emits the bare "Concierge" — the exact text PR #3225's `message-bubble.tsx` fix removed. If the strip then ALSO emits "Soleur Concierge" via the routed-leader fallback, the user sees `"Concierge · Soleur Concierge"` — the same duplicated-header pattern.

**Mitigation:**

- The `RoutedLeadersStrip` component reads `CONCIERGE_TITLE` from `DOMAIN_LEADERS.find((l) => l.id === CC_ROUTER_LEADER_ID)?.title` at module scope (resolves to "Soleur Concierge" at compile time). It NEVER calls `getDisplayName(CC_ROUTER_LEADER_ID)`.
- The `domainOnly` filter strips `cc_router` from `routedLeaders` before the comma-joined list, preventing the fallback `getDisplayName(cc_router)` from firing.
- Test 5 (T5) is the explicit regression guard — counts occurrences of `/Concierge/` in the strip's `textContent`, asserts exactly 1 match (from "Soleur Concierge"). If a future refactor accidentally re-introduces a bare "Concierge", T5 fails.

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
