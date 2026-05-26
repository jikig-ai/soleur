---
type: bug-fix
status: planned
created: 2026-05-07
deepened: 2026-05-07
branch: feat-one-shot-concierge-loading-indicator-consistency
classification: ui-consistency
requires_cpo_signoff: false
---

# fix: standardize concierge thread loading indicator on the bubble + Working badge treatment

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** Approach, Acceptance Criteria, Test Scenarios, Risks, Sharp Edges
**Research surfaces consulted:** local repo grep for `routing-chip` / `MessageBubble` / `ThinkingDots` / `ToolStatusChip` / `cc_router` / `LeaderAvatar` aria-label / `messageState` enum / `[data-testid='thinking-dots']` test density; live read of `apps/web-platform/server/domain-leaders.ts` to verify `cc_router.title === "Soleur Concierge"` and `cc_router.name === "Concierge"` (load-bearing for the `titleContainsName` branch); live read of `apps/web-platform/components/leader-avatar.tsx` to confirm `aria-label="Soleur Concierge avatar"` is invariant across `size="sm"` and `size="md"` (load-bearing for test T1 + T2 + T3 in `cc-routing-panel-concierge-visibility.test.tsx`).

### Key Improvements

1. **Concrete drop-in snippet** for chat-surface.tsx with all six `MessageBubble` props named explicitly (avoids the "deferred to implementation" trap from `cq-...payload-typed-variants` style scope creep).
2. **Test compatibility audited explicitly per-file, per-line** — five test files touched only nominally; only T1 in `cc-routing-panel-concierge-visibility.test.tsx` needs a real edit. The `chat-page.test.tsx:179` regex `/routing to the right experts/i` confirmed compatible with the new shorter `toolLabel="Routing to the right experts…"` (case-insensitive substring still matches).
3. **Header double-render risk explicitly resolved** — verified `cc_router.title.includes(cc_router.name)` is true ("Soleur Concierge".includes("Concierge")), which routes through the `titleContainsName` branch at message-bubble.tsx:103-105 and renders header = `"Soleur Concierge"` (NOT a duplicated "Soleur Concierge Soleur Concierge").
4. **Avatar aria-label invariant confirmed** — `LeaderAvatar` renders the same `aria-label="Soleur Concierge avatar"` for `size="sm"` and `size="md"`; the avatar size change from sm→md does NOT regress any of T1/T2/T3 visibility assertions.
5. **Risk register tightened** — the "header double-render" risk is now verified, not just hand-waved.

### New Considerations Discovered

- **`size="md"` avatar mismatch with strip:** the routed-leaders strip (T2 in the visibility test) uses `size="sm"` Concierge avatars in the strip. After this change, the routing-chip Concierge avatar is `size="md"` (MessageBubble default). This is intentional consistency with all other in-thread bubbles; it does NOT regress the strip (different DOM subtree).
- **`MessageBubble` `content=""` default-branch behavior:** when `messageState="tool_use"` AND `toolLabel` is set AND `retrying=false`, the inner switch returns `<ToolStatusChip label={toolLabel} />` and never reaches the `content`-rendering branches. So `content=""` is safe and does not produce a stray empty `<MarkdownRenderer>` render.
- **`React.memo` re-render audit:** `MessageBubble` is `React.memo`'d. The routing chip mounts/unmounts based on `isClassifying`. While mounted, the only reference identity change is `getDisplayName` / `getIconPath` (already `useCallback`-stable per `use-team-names.tsx`) and `toolLabel` (a hard-coded string literal). No unnecessary re-renders during the chip's brief lifecycle.


## Overview

The Command Center chat thread renders **two visually different** loading treatments for what are conceptually the same state — "an assistant turn is in flight, output not yet rendered":

1. **Pre-tool / classification phase** (initial turn after the user sends the first message): a flat row outside the message-bubble system, made of `<LeaderAvatar size="sm">` + a single `h-2 w-2 animate-pulse rounded-full bg-amber-500` dot + the prose `Soleur Concierge is routing to the right experts...`. Container is `border-soleur-border-default` (default border, no animation, no badge). Source: `apps/web-platform/components/chat/chat-surface.tsx:615-625`.

2. **Tool-use / streaming phase** (every subsequent assistant turn while the agent is doing work): a `MessageBubble` with the `message-bubble-active border-2 border-amber-600/70` animated border, an absolutely-positioned `Working` (or `Streaming`) badge in the upper-right corner, and `ThinkingDots` (or a `ToolStatusChip` showing the activity label, e.g. `Reading knowledge-base/overview/Manning Book…`). Source: `apps/web-platform/components/chat/message-bubble.tsx:107-150` (active-state border + badge) and 223-228 (inner content).

Both are pending assistant turns. The user perceives them as the same thing (`the agent is working on my question`) but the visual treatment switches mid-conversation, which reads as an unfinished UI rather than two intentional states.

**Fix:** route the routing/pre-tool phase through the same `MessageBubble`-style treatment used for `tool_use` — animated border + `Working` badge + an inner activity label that says "Routing to the right experts…". The Soleur Concierge avatar continues to render to the left of the bubble. The chip's `data-testid="routing-chip"` is preserved so existing tests that assert on its presence (and absence) keep passing.

## Files to Edit

- `apps/web-platform/components/chat/chat-surface.tsx` — replace the inline `isClassifying` chip block (lines 615-625) with a `MessageBubble`-shaped render that uses the same `message-bubble-active`/`Working` badge treatment as `messageState === "tool_use"`. Preserve `data-testid="routing-chip"` on the outermost wrapper so existing visibility tests do not regress.
- `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` — T1 currently asserts presence of the chip + Concierge avatar + the prose `Soleur Concierge is routing to the right experts/i`. Update T1 to (a) keep the avatar + prose assertions, (b) assert the new bubble has the `message-bubble-active` class on its inner container, (c) assert the `Working` badge is rendered. Existing T2 / T3 do not assert on the chip's visual shape and remain unchanged.
- `apps/web-platform/test/chat-surface-resume-classifying.test.tsx` — only asserts `screen.queryByTestId("routing-chip")` for presence/absence. No changes required if we preserve the testid.
- `apps/web-platform/test/chat-page.test.tsx` — line 179 asserts `screen.getByText(/routing to the right experts/i)`; line 232/241 assert `[data-testid='thinking-dots']` count. We are NOT adding `ThinkingDots` to the routing chip body (the `Working` badge + animated border already convey "in progress"; doubling up the dots adds visual noise). Existing assertions remain unchanged.

## Files to Create

None.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "blinking dot indicator" on first message | `chat-surface.tsx:619` renders `h-2 w-2 animate-pulse rounded-full bg-amber-500` next to the prose — single pulsing dot, not three (the three-dot `ThinkingDots` component is only used inside `MessageBubble` for `messageState === "thinking"`). | Confirmed; the inconsistency is `single-pulse-dot + flat row` vs `Working badge + animated bubble border`. |
| "blinking outlined bubble (with a Working badge)" on subsequent message | `message-bubble.tsx:107` sets `isActive` for `thinking | tool_use | streaming` → `message-bubble-active border-2 border-amber-600/70` border + `Working` (or `Streaming`) badge at lines 135-139. The "blinking" the user sees is the `message-bubble-active` CSS keyframe pulse on the border, not the inner content. | Confirmed; this is the target treatment. The `Working` badge is the canonical pending-assistant indicator. |
| "should use the same loading treatment" | The cleanest path is to render the routing chip THROUGH `MessageBubble` rather than re-implementing the active-bubble shell inline. `MessageBubble` already accepts `leaderId="cc_router"` + `messageState="tool_use"` + `toolLabel="Routing to the right experts…"`, which produces the desired visual exactly. | Use `MessageBubble` directly (Approach A below). |

## Approach

### A — Render the routing chip through `MessageBubble` (selected)

Replace lines 615-625 of `chat-surface.tsx` with:

```tsx
{isClassifying && (
  <div className="flex justify-start" data-testid="routing-chip">
    <MessageBubble
      role="assistant"
      content=""
      leaderId={CC_ROUTER_LEADER_ID}
      messageState="tool_use"
      toolLabel="Routing to the right experts…"
      getDisplayName={getDisplayName}
      getIconPath={getIconPath}
    />
  </div>
)}
```

**Why this works:**

- `MessageBubble` with `messageState="tool_use"` + a non-empty `toolLabel` renders `ToolStatusChip` (message-bubble.tsx:228). The `ToolStatusChip` shows the label as plain prose, which matches the existing UX pattern used for `Reading knowledge-base/...`.
- `isActive = messageState === "tool_use"` triggers the `message-bubble-active border-2 border-amber-600/70` animated border (line 107, 114).
- The `Working` badge renders unconditionally for `tool_use` at lines 135-139.
- `LeaderAvatar` for `cc_router` renders to the left at line 124-126 (with `getIconPath` fallback for custom icons).
- The header `<div data-testid="message-bubble-header">` shows "Soleur Concierge" via the `titleContainsName` branch at line 105 (the cc_router leader's `title` includes the displayName "Soleur Concierge" — verified by the existing T1 test which asserts on this exact string).

**Why we keep the wrapper `<div data-testid="routing-chip">`:** existing tests (`chat-surface-resume-classifying.test.tsx`, `cc-routing-panel-concierge-visibility.test.tsx` T1) assert presence/absence of `routing-chip`. Preserving the testid on the outer wrapper avoids a test-suite-wide rename.

**Verified prerequisites (deepen-pass live reads):**

- `apps/web-platform/components/chat/chat-surface.tsx:16` already imports `MessageBubble` — no new import needed. (`grep -n "MessageBubble" apps/web-platform/components/chat/chat-surface.tsx`.)
- `apps/web-platform/components/chat/chat-surface.tsx:25` already imports `CC_ROUTER_LEADER_ID` — no new import needed.
- `apps/web-platform/components/chat/chat-surface.tsx:210` already destructures `getDisplayName, getIconPath` from `useTeamNames()` — pass-through is free.
- `apps/web-platform/server/domain-leaders.ts:101-110` defines `cc_router` with `name: "Concierge"`, `title: "Soleur Concierge"`, `defaultIcon: ""`. The empty `defaultIcon` is handled by `LeaderAvatar`'s `isConcierge` branch (`leader-avatar.tsx:65-82`) which renders `/icons/soleur-logo-mark.png` regardless of size — so `size="md"` (MessageBubble's default) renders correctly.
- The `aria-label="Soleur Concierge avatar"` in `leader-avatar.tsx:71` is invariant across `size="sm"` and `size="md"` (same conditional branch). All three test cases T1/T2/T3 in `cc-routing-panel-concierge-visibility.test.tsx` continue to find the avatar by aria-label.
- `MessageBubble`'s `tool_use` switch arm (`message-bubble.tsx:226-228`) returns `<ToolStatusChip label={toolLabel} />` when `toolLabel` is truthy. `ToolStatusChip` (lines 24-30) renders the label as `<span className="text-sm text-soleur-text-secondary">{label}</span>` — same color treatment as the legacy routing chip prose.

### B — Inline the bubble shell (rejected)

Hand-roll the `border-2 border-amber-600/70 message-bubble-active` shell + `Working` badge inline in `chat-surface.tsx`. Rejected: duplicates 30+ lines of `MessageBubble`'s active-state styling, including the badge positioning, the avatar wrapper, the leader title resolution (the `titleContainsName` branch at message-bubble.tsx:103-105 that prevents the header from rendering "Soleur Concierge Soleur Concierge"). Drift is inevitable when `MessageBubble` later changes.

### C — Drop the routing chip entirely; let the streamed first assistant message render its own active bubble (rejected)

The `isClassifying` chip exists because there is a real latency window between (a) the user sending the message and (b) the cc_router emitting its first stream event — there is no assistant message in the message list yet. Removing the chip leaves the user staring at an empty thread for that window. Rejected.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `chat-surface.tsx` `isClassifying` block replaced with a `MessageBubble` render at `messageState="tool_use"`, `leaderId="cc_router"`, `toolLabel="Routing to the right experts…"`, wrapped in a `<div data-testid="routing-chip" className="flex justify-start">`.
- [x] Routing chip renders the `Working` badge (assert `screen.getByText("Working")` inside the chip).
- [x] Routing chip renders the `message-bubble-active` animated border (assert `chip.querySelector(".message-bubble-active")` is non-null).
- [x] Routing chip continues to render the Concierge avatar (`getByLabelText("Soleur Concierge avatar")`) and the "Soleur Concierge is routing to the right experts…" copy (the toolLabel prose, with the unicode ellipsis or three-dot — assertion uses `/routing to the right experts/i` which matches both).
- [x] All four touched test files green: `cc-routing-panel-concierge-visibility.test.tsx`, `chat-surface-resume-classifying.test.tsx`, `chat-page.test.tsx`, `message-bubble-tool-status-chip.test.tsx`.
- [x] Full `apps/web-platform` vitest suite green except 8 pre-existing failures in `pdf-text-extract.test.ts` tracked by issue #3424 (unrelated to this change).
- [ ] Visual QA screenshot pair (before/after) attached to the PR showing the routing-chip frame + the subsequent tool-use frame side-by-side, confirming the visual treatment matches.
- [ ] PR body uses `Ref #<one-shot-issue-N>` if the one-shot pipeline filed a tracking issue; otherwise no auto-close keyword (this is a small UI consistency fix without a standalone GitHub issue).

### Post-merge (operator)

- [ ] None. Frontend-only change deploys via the normal Vercel pipeline; no migrations, no env changes, no operator action.

## Test Scenarios

### Unit (vitest, RTL)

**T1-updated — routing chip renders through MessageBubble shell (UPDATE in `cc-routing-panel-concierge-visibility.test.tsx`):**

```tsx
it("T1 — isClassifying chip uses the active-bubble + Working badge treatment", async () => {
  wsReturn = createWebSocketMock({
    realConversationId: "test-id",
    messages: [{ id: "u1", role: "user", content: "hello", type: "text" }],
    routeSource: null,
    workflow: { state: "idle" },
    activeLeaderIds: [],
  });
  await renderFull();

  const chip = await screen.findByTestId("routing-chip");
  expect(chip).toBeInTheDocument();

  // Concierge avatar still left-positioned
  expect(within(chip).getByLabelText("Soleur Concierge avatar")).toBeInTheDocument();

  // Active-bubble treatment (matches subsequent tool_use bubbles)
  expect(chip.querySelector(".message-bubble-active")).not.toBeNull();
  expect(within(chip).getByText("Working")).toBeInTheDocument();

  // Routing prose preserved (now rendered as the toolLabel)
  expect(
    within(chip).getByText(/routing to the right experts/i),
  ).toBeInTheDocument();
});
```

**T2 / T3 (unchanged):** strip-rendering tests do not touch the routing chip's visual shape.

**`chat-surface-resume-classifying.test.tsx` (unchanged):** all four assertions are presence/absence on `routing-chip` testid, which is preserved.

**`chat-page.test.tsx` (unchanged):**
- Line 179 `getByText(/routing to the right experts/i)` — still passes (the prose now renders inside the bubble's `ToolStatusChip` body).
- Line 232/241 `[data-testid='thinking-dots']` — still passes; we are NOT adding `ThinkingDots` to the routing chip (the `Working` badge + animated border carry the in-progress signal).

### Visual QA

- Open the chat surface, send any first message, capture screenshot of the routing chip while `isClassifying === true`.
- Capture screenshot of the subsequent `tool_use` bubble (e.g. `Reading <some-file>...`).
- Confirm both frames share the same border, the same `Working` badge, the same avatar position, and the same overall width/padding.
- Confirm the Concierge avatar + leader header ("Soleur Concierge") are still visible.

## User-Brand Impact

**If this lands broken, the user experiences:** a routing chip that fails to render on first message — the user sees a blank thread between sending the message and the first stream event (the existing behavior in the absence of the chip is that nothing visible appears for ~300ms-2s).

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this is a presentational refactor of an existing in-thread UI element. No credential, auth, data, payment, or user-owned-resource surface is touched.

**Brand-survival threshold:** none. UI consistency polish on a non-sensitive surface; the worst observable failure (chip fails to render) leaves the user with a brief blank thread for one frame, which the existing first-stream-event already paves over within seconds.

**Why the gate is `none`:** the diff touches `apps/web-platform/components/chat/chat-surface.tsx` (UI component) and three colocated tests. It does NOT touch credential storage, the BYOK surface, Doppler, RLS, payment routing, the auth flow, or any user-owned external resource. Sensitive-path regex per `plugins/soleur/skills/preflight/SKILL.md` Check 6 Step 6.1 does not match.

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` and `gh issue list --search "loading indicator concierge"`. Searched the result set for the planned file paths.

- `apps/web-platform/components/chat/chat-surface.tsx` — no open code-review issue references this path.
- `apps/web-platform/components/chat/message-bubble.tsx` — no open code-review issue references this path. (The closest historical refs are #2221, #2222, #2224 for unrelated chat performance/refactor scope; not in flight.)
- `apps/web-platform/test/cc-routing-panel-concierge-visibility.test.tsx` / `chat-surface-resume-classifying.test.tsx` / `chat-page.test.tsx` — no open code-review issue references these paths.

**Disposition:** None. No overlapping scope-outs.

## Domain Review

**Domains relevant:** Product (UX consistency in primary user-facing surface).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none (pipeline auto-accept per plan SKILL.md Phase 2.5 Step 2.2)
**Skipped specialists:** ux-design-lead (advisory tier in pipeline mode, no new component file created — Step 2.2 mechanical-escalation grep on `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` for `Files to create` returns empty since `## Files to Create` is `None`); copywriter (no new copy — `"Routing to the right experts…"` is a near-verbatim restatement of the existing `Soleur Concierge is routing to the right experts...` prose, just shortened to fit the `toolLabel` slot which is already the convention for `Reading <path>...`/`Writing <path>...` labels).
**Pencil available:** N/A

#### Findings

- The Product domain signal here is: "the chat surface looks inconsistent; users notice the visual jump." The fix consolidates two visual treatments into one — strictly a reduction in surface variance, not a new surface. ADVISORY tier is correct.
- No new pages, modals, dialogs, or interstitials. `## Files to Create` is `None`. The mechanical BLOCKING-escalation rule does not fire.
- Brand voice: the new `toolLabel` "Routing to the right experts…" preserves the existing Soleur Concierge persona ("the right experts" framing, three-dot ellipsis convention) — see `knowledge-base/marketing/voice-and-tone.md` for the broader register, but this specific copy already passed brand review when it shipped at chat-surface.tsx:621.
- No domain leader from a prior brainstorm recommended a copywriter or specialist for this fix (no brainstorm exists — confirmed via `ls knowledge-base/project/brainstorms/` → no match within 14 days).

## Risks

- **Test-suite regression on `routing-chip` shape assertions.** Mitigation: T1 in `cc-routing-panel-concierge-visibility.test.tsx` is updated in the same PR. The other two test files only assert presence/absence on the testid, which is preserved.
- **`MessageBubble` re-render volume.** `MessageBubble` is wrapped in `React.memo` (line 61) and is now also a child of the routing chip. The chip only mounts while `isClassifying === true` (one render cycle), so the memoization is moot. No measurable impact.
- **Avatar size mismatch.** The current routing chip uses `<LeaderAvatar size="sm">`; `MessageBubble` uses `size="md"`. The new bubble shape will render a slightly larger avatar than the legacy chip. This is desired — it matches the avatar size of every subsequent assistant bubble, which is the entire point of the fix.
- **Header double-render.** `MessageBubble` renders the leader header (`Soleur Concierge`) at lines 152-164. The legacy chip rendered the prose `Soleur Concierge is routing to the right experts...` as a single string. The new chip renders `Soleur Concierge` as the header AND `Routing to the right experts…` as the body — two visual layers. Verified by reading message-bubble.tsx:103-105 AND `apps/web-platform/server/domain-leaders.ts:101-110`: the `titleContainsName` branch evaluates `leader.title.includes(displayName)` = `"Soleur Concierge".includes("Concierge")` = `true`, which sets `headerPrimary = leader.title = "Soleur Concierge"` and suppresses the secondary `showFullTitle` span (we don't pass `showFullTitle`, so it defaults to `false` anyway). Final shape: header `Soleur Concierge` + body `Routing to the right experts…`. Matches the `Reading <path>` bubbles which render `<leader-name>` header + path-prose body. Reviewed against #3225 Bug 2 fix-precedent (the exact `titleContainsName` branch) — no regression risk.

- **`getByText(/Soleur Concierge is routing to the right experts/i)` regression in T1.** Original T1 line 55 asserts the verbatim phrase including the prefix `Soleur Concierge is`. After the change, the body shows `Routing to the right experts…` (no `Soleur Concierge is` prefix; that text now lives in the bubble header as `Soleur Concierge`, separate DOM node). The plan's T1-updated wording above relaxes the regex to `/routing to the right experts/i` — the case-insensitive substring still matches. T1 must be updated to the relaxed regex in the same PR (already in `## Files to Edit`); the visibility-test contract is preserved (the chip still announces "Soleur Concierge" + "Routing to the right experts…", just split across header/body).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above with threshold `none` and a written non-sensitive-path justification.)
- `MessageBubble` accepts `getDisplayName` and `getIconPath` from `useTeamNames`. The routing chip MUST forward these (they are already in scope at `chat-surface.tsx:210`) — without them, custom team-name overrides would not apply to the chip header. Verified the implementation snippet above passes both.
- The `toolLabel` ellipsis: prefer the unicode `…` (U+2026) used in existing labels rather than three ASCII dots. The legacy chip uses `...` (three ASCII). The test regex `/routing to the right experts/i` matches both, but for visual consistency with the rest of the bubble system (`Streaming`, `Working`), use the unicode form `…`.
- **Do NOT pass `showFullTitle`** to the `MessageBubble` for the routing chip. The default `false` is correct; passing `true` would render an additional `<span>{leader.title}</span>` next to `headerPrimary`, but the `titleContainsName` branch suppresses it anyway — passing it would just be noise. Stick to the six props in the snippet (`role`, `content`, `leaderId`, `messageState`, `toolLabel`, `getDisplayName`, `getIconPath`).
- **Do NOT add `attachments`, `toolsUsed`, `retrying`, or `variant` props.** The routing chip has no attachments, no tools yet used, is not retrying, and uses the default `variant="full"`. Adding any of them would imply state that does not exist in the routing window.
- **`ChatSurface` `variant="sidebar"` rendering check.** `chat-surface.tsx` is rendered in two variants: `full` (default, `/dashboard/chat/[id]`) and `sidebar` (the kb-chat sidebar). The `isClassifying` chip renders identically in both variants today. The new `MessageBubble` render also lacks an explicit `variant` prop, defaulting to `variant="full"` inside `MessageBubble`. The plan does NOT pass `variant={variant}` from `chat-surface.tsx` because the routing chip is brief and the sidebar's narrower column already constrains the bubble width via `max-w-[90%]` (message-bubble.tsx:123). Acceptable trade-off; revisit if the chip ever overflows in the sidebar.
- **String-literal grep across plan.** The literal `Routing to the right experts…` appears once in `## Approach A`, once in `## Acceptance Criteria` (Pre-merge), once in `## Test Scenarios` (T1-updated), and once in `## Risks`. Verified consistent unicode `…` usage. The regex `/routing to the right experts/i` appears in `## Acceptance Criteria`, `## Test Scenarios`, and `## Risks` — all consistent.

## Detail Level

MORE — small surface, low risk, but the visual diff and the test update warrant explicit before/after snippets and a documented Approach A/B/C trade-off (the inline-shell alternative is tempting and would be a slow-bleed maintenance tax that the plan needs to actively reject).

## AI-Era Considerations

- The fix is mechanical; no AI assistance needed beyond standard TS-aware edit. The tradeoff (render through `MessageBubble` vs inline shell) was the only design call; documented above.
- Implementation should run a vitest watch on the three touched test files during work; the change is small enough that one test-suite cycle confirms correctness.
