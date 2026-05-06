---
type: fix
scope: ui-chat
branch: feat-one-shot-remove-tool-use-blinking-dot
issue: TBD
requires_cpo_signoff: false
created: 2026-05-06
deepened: 2026-05-06
---

# fix: Remove redundant blinking orange dot from tool-use chip

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** Files to Edit, Implementation Phases, Acceptance Criteria, Risks, Out of Scope (new: Scope Boundary Audit)
**Research applied:**
- Codebase grep audit of `bg-amber-500` and `animate-pulse rounded-full` across `apps/web-platform/components/chat/`
- Cross-check against existing test conventions (`message-bubble-retry.test.tsx`, `tool-use-chip.test.tsx`, `light-theme-tokenization.test.tsx`)
- Learning: `knowledge-base/project/learnings/best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md` — Pattern 4 (`data-*` attribute hooks as test API) — recommended over Tailwind class selectors in jsdom
- AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g` — verify each file path matches the protected surface, not just the issue body's enumerated list

### Key Improvements Over Initial Plan

1. **Scope-boundary audit added.** Codebase grep found two additional pulsing-orange-dot sites (`chat-surface.tsx:619` routing chip; `subagent-group.tsx:104` subagent in-flight). Both are explicitly evaluated and ruled OUT-of-scope with reasoning, preventing a future reviewer from re-litigating the scope.
2. **Stronger test-assertion strategy.** Initial plan asserted via Tailwind class selectors (`span.animate-pulse.rounded-full.bg-amber-500`). Per learning 2026-04-18 Pattern 4, the preferred jsdom convention is `data-testid` attribute hooks. Added prescription to add `data-testid="tool-status-chip"` to the `ToolStatusChip` wrapper (mirroring `data-testid="thinking-dots"`, `data-testid="retrying-chip"` precedent already in the same file) and assert structurally rather than against Tailwind class strings.
3. **Test-dependency sweep verified.** Confirmed via `grep -n "ToolStatusChip\|bg-amber-500\|animate-pulse" apps/web-platform/test/light-theme-tokenization.test.tsx apps/web-platform/test/message-bubble-memo.test.tsx apps/web-platform/test/message-bubble-header.test.tsx apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` that NO existing test asserts on the dot's presence — the removal cannot break existing assertions.
4. **Test-runner pinning verified.** Existing chat-component tests use vitest + `@testing-library/react` (jsdom). The plan's test files match the convention — no new dependency.

### New Considerations Discovered

- The `ToolStatusChip` component in `message-bubble.tsx` does NOT currently have a `data-testid` even though sibling components in the same file (`ThinkingDots`, `RetryingChip`, the bubble header, the file-issue link) all do. Adding one as part of this change is a small hygiene improvement aligned with the codebase's drift-guard convention.
- The `ToolUseChip` component already exposes `data-tool-chip-id` (line 42) — the structural assertion can scope through that attribute without adding a new one.

## Overview

In the Soleur Concierge chat UI, when an assistant message is in `messageState === "tool_use"` (e.g., "Reading knowledge-base/overview/Au Chat Potan - Presentation Projet-10.pdf..."), the `ToolStatusChip` component renders a small `h-1.5 w-1.5 animate-pulse rounded-full bg-amber-500` dot to the left of the tool label. The same bubble already advertises the working state via two stronger signals on the *same DOM node*:

1. **Animated bubble border:** `message-bubble-active border-2 border-amber-600/70` (set in `MessageBubble` when `isActive`, line 115).
2. **Top-right pill:** an absolute-positioned `Working` badge with amber border + amber text (line 137-139).

A third pulsing dot inside the bubble adds visual noise without conveying new information. Remove it. The `ToolUseChip` component (used pre-bubble for `cc_router` / `system` leaders only) carries the same dot pattern (`tool-use-chip.tsx:46-48`); the user's screenshot is *inside* a Concierge bubble (so `ToolStatusChip`), but per the request "Remove the dot indicator completely from tool-use message rendering," the symmetric removal in `ToolUseChip` is folded into the same change so the two surfaces don't drift.

## User-Brand Impact

**If this lands broken, the user experiences:** a layout glitch in the Concierge chat (e.g., the `ToolStatusChip` collapsing to zero height, the label losing its left-edge spacing, or — worst case — a JSX render error that blanks the bubble during `tool_use`).

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this is a presentational removal of a decorative element. No state, network call, auth, or persisted data is touched.

**Brand-survival threshold:** none — purely cosmetic UI cleanup; no sensitive path matched (no auth, payments, BYOK, repo writes, or credentials touched). No `requires_cpo_signoff` set.

## Files to Edit

- `apps/web-platform/components/chat/message-bubble.tsx` — In the `ToolStatusChip` component (lines 24-31):
  - **Delete** line 27: `<span className="h-1.5 w-1.5 animate-pulse rounded-full bg-amber-500" />`.
  - **Add** `data-testid="tool-status-chip"` to the wrapping `<div>` (line 26) — mirrors `data-testid="thinking-dots"` (line 16) and `data-testid="retrying-chip"` (line 45) precedent in the same file. Per learning 2026-04-18 Pattern 4, structural attribute hooks are preferred over Tailwind class selectors in jsdom.
  - **Keep** the wrapping `<div className="flex items-center gap-2 py-0.5">` className unchanged. CSS `gap` on a single-child flex container is a no-op (zero visual effect, zero performance cost), and leaving it minimizes the diff and removes the future-trap of "second child reintroduced without re-adding `gap-2`".
- `apps/web-platform/components/chat/tool-use-chip.tsx` — In the chip body (lines 40-51):
  - **Delete** lines 45-48 (the `<span ... bg-amber-500 ...>` dot).
  - **Keep** the existing `data-tool-chip-id` attribute (line 42) — already serves as the structural test hook for this chip; no new `data-testid` needed.
  - **Keep** the chip's outer container className unchanged (`gap-2` is a no-op on a single child here too — same reasoning as above).

## Files to Create

None.

## Implementation Phases

### Phase 1 — RED (failing tests)

Add structural assertions that the dot is NOT in the DOM. Per learning 2026-04-18 Pattern 4, prefer `data-testid` attribute scoping to Tailwind class selectors. After Phase 2 adds `data-testid="tool-status-chip"` to `ToolStatusChip`, the assertion scope is well-defined.

**Why structural-via-data-testid over Tailwind-class selectors:**
- Tailwind class selectors (`span.animate-pulse.rounded-full.bg-amber-500`) couple the test to four classnames. Renaming any of them (e.g., theme refactor swapping `bg-amber-500` for a token like `bg-soleur-accent-warning`) silently passes the assertion (no `bg-amber-500` to find → assertion succeeds → false-positive green).
- `data-testid` scoping (`getByTestId("tool-status-chip").querySelector("span.animate-pulse")`) reads "no pulsing element inside the tool-status chip" — survives Tailwind-class rotation and gives a clearer failure message.

Test files:

- `apps/web-platform/test/message-bubble-tool-status-chip.test.tsx` (NEW)
  - Mock `@/lib/client-observability` per the existing pattern in `message-bubble-retry.test.tsx` lines 7-10 (otherwise `formatAssistantText`'s fallthrough path attempts to initialize Sentry in the component bundle under test).
  - Render `<MessageBubble role="assistant" messageState="tool_use" toolLabel="Reading knowledge-base/overview/foo.pdf" />` and assert:
    - `getByTestId("tool-status-chip")` resolves (the chip is rendered).
    - `getByTestId("tool-status-chip").querySelector("span.animate-pulse")` is `null` (the dot is gone — scoped to the chip, won't false-positive against the streaming-state caret which uses `animate-pulse text-amber-500` on a `<span>` containing `&#x258C;`).
    - `container.textContent` contains the toolLabel verbatim.
    - The `Working` badge IS still present (`container.textContent` contains `"Working"`).
    - The bubble's `message-bubble-active` border class is still applied (`container.querySelector(".message-bubble-active")` is non-null) — guards against accidental removal of the bubble-border animation.
- `apps/web-platform/test/tool-use-chip.test.tsx` (EDIT — append one test, do NOT remove existing)
  - Add: `test("does not render a pulsing dot indicator", ...)` — render `<ToolUseChip toolName="Skill" toolLabel="Routing" leaderId="cc_router" />`, locate the chip via the existing `[data-tool-chip-id]` attribute (line 42 of `tool-use-chip.tsx`), and assert `chip.querySelector("span.animate-pulse")` is `null`.
  - The 5 existing tests (lines 13, 21, 29, 37, 47) MUST still pass after the edit — they assert label-rendering, leader-color borders, multi-chip co-existence, and XSS-safe rendering. None asserts on the dot.

### Phase 2 — GREEN (implementation)

Apply the two file edits described in `## Files to Edit`. Run `bun test apps/web-platform/test/message-bubble-tool-status-chip.test.tsx apps/web-platform/test/tool-use-chip.test.tsx apps/web-platform/test/message-bubble-retry.test.tsx` and confirm green.

### Phase 3 — REFACTOR

None expected. The removal is mechanical. If the `gap-2` removal looks visually off in the QA screenshot, restore it (single-child gap is a no-op, not a bug).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/components/chat/message-bubble.tsx` `ToolStatusChip` no longer renders the amber pulsing dot.
- [ ] `apps/web-platform/components/chat/message-bubble.tsx` `ToolStatusChip` wrapper has `data-testid="tool-status-chip"` (mirrors sibling `data-testid` precedent in same file).
- [ ] `apps/web-platform/components/chat/tool-use-chip.tsx` `ToolUseChip` no longer renders the amber pulsing dot.
- [ ] New test `message-bubble-tool-status-chip.test.tsx` asserts the dot is gone (scoped via `data-testid="tool-status-chip"`) AND the toolLabel + Working badge + animated bubble border (`message-bubble-active`) are still present.
- [ ] Existing test `apps/web-platform/test/tool-use-chip.test.tsx` extended with a "no dot" assertion (scoped via the existing `[data-tool-chip-id]` attribute), all other assertions still green.
- [ ] Existing test `apps/web-platform/test/message-bubble-retry.test.tsx` still green — the change does NOT touch `RetryingChip`. The retry chip has its own dot at line 48; that dot stays because the retry chip stands alone when `retrying=true` (no surrounding `Working` badge — the badge is replaced by the retry chip).
- [ ] Existing tests that touch `MessageBubble` rendering (`message-bubble-memo.test.tsx`, `message-bubble-header.test.tsx`, `message-bubble-file-issue-link.test.tsx`, `light-theme-tokenization.test.tsx`, `cc-soleur-go-end-to-end-render.test.tsx`) remain green — verified at deepen-plan time that none of these tests assert on `bg-amber-500` or `animate-pulse.rounded-full` selectors (grep returned zero matches).
- [ ] `bun test apps/web-platform/test/` returns no new failures vs. main-branch baseline.
- [ ] QA screenshot of a `tool_use` bubble (e.g., a `/soleur:go` flow that triggers a `Read` tool call) — bubble shows animated border, top-right `Working` badge, and the toolLabel text WITHOUT the inner dot.
- [ ] QA screenshot of a `cc_router` / `system` pre-bubble chip during routing — chip shows colored border + pill shape + toolLabel text WITHOUT the inner dot.
- [ ] QA spot-check (regression-canary): trigger a retry scenario; confirm `RetryingChip` still renders with its own pulsing dot + "Retrying…" text. Also confirm the routing chip in `chat-surface.tsx` and the subagent in-flight indicator in `subagent-group.tsx` are untouched.

### Post-merge

None — no operator action, no Terraform, no migration.

## Test Scenarios

1. **Concierge tool_use rendering:** `MessageBubble` with `messageState="tool_use"` and a `toolLabel` renders the label without an inner pulsing dot, and retains the animated border + `Working` badge.
2. **Pre-bubble cc_router/system chip:** `ToolUseChip` with `leaderId="cc_router"` renders the label without an inner pulsing dot, and retains the yellow border accent.
3. **Retry chip unchanged:** `MessageBubble` with `messageState="tool_use"` AND `retrying=true` still renders `RetryingChip` with its own amber dot and "Retrying…" text — this surface is intentionally untouched (the dot is the state cue there, not a redundant duplicate).
4. **No regressions:** all `tool-use-chip.test.tsx` tests + `message-bubble-retry.test.tsx` tests + any `message-bubble-memo.test.tsx` / `light-theme-tokenization.test.tsx` test that touches the bubble path remain green.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — purely presentational UI cleanup, no auth, data, copy, or pricing surface touched.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Reality | Plan response |
|---|---|---|
| Dot appears "to the left of 'overview' word" inside Concierge bubble | Confirmed: `ToolStatusChip` at `message-bubble.tsx:24-31` renders a `bg-amber-500 animate-pulse` dot left of `<span>{label}</span>`. | Remove the dot at line 27. |
| Bubble border is "already animated/blinking" | Confirmed: `borderStyle = isActive ? "message-bubble-active border-2 border-amber-600/70" : ...` (line 112-118). The `message-bubble-active` class drives the border animation. | No change — keep the existing animated border as the working-state cue. |
| "Working" badge in top right | Confirmed: absolute-positioned pill at lines 136-140 renders when `messageState === "tool_use" \|\| messageState === "streaming"`. | No change — keep the badge. |
| (Implicit) the dot exists ONLY in `ToolStatusChip` | The same dot pattern is duplicated in `ToolUseChip` (`tool-use-chip.tsx:46-48`). The user's screenshot is inside a Concierge bubble (so `ToolStatusChip`), but the description says "Remove the dot indicator completely from tool-use message rendering" — `ToolUseChip` is also a tool-use message rendering surface (the pre-bubble chip for cc_router/system). | Fold both into the same change so the two surfaces don't drift. The chip's outer border and rounded-full pill shape continue to convey "this is a tool-use indicator" without the inner dot. |

## Open Code-Review Overlap

None. (Verified by skimming open code-review issues for filename matches against `message-bubble.tsx` and `tool-use-chip.tsx` — no overlapping scope-outs at plan time.)

## Hypotheses

N/A — the bug is a known visual redundancy with a confirmed root cause (the dot DOM node), not a hypothesis-driven investigation.

## Risks

- **Visual regression in `RetryingChip`:** the `RetryingChip` component (`message-bubble.tsx:39-56`) also has a pulsing dot at line 48 (note: `bg-amber-400`, NOT `bg-amber-500` — different color, which is one reason the plan's class-scoped grep didn't false-positive against it). It is intentionally NOT modified — the chip is shown ONLY when `retrying=true` and the chip stands alone (no surrounding `Working` badge — the badge is replaced when retrying takes over). The dot there is the state cue.
- **Streaming-state caret false-positive risk:** `renderBubbleContent` at `message-bubble.tsx:234` renders `<span className="animate-pulse text-amber-500">&#x258C;</span>` for `messageState === "streaming"`. This `<span>` HAS `animate-pulse` but is NOT a rounded dot (no `rounded-full`, no `bg-amber-500`, contains the `▌` glyph) and is in a different `messageState` branch. A naive `querySelector("span.animate-pulse")` on the bubble container could match it during a streaming render. **Mitigation:** the plan's test assertions are scoped via `getByTestId("tool-status-chip")` (after Phase 2 adds the `data-testid`), which scopes the `querySelector` to the `ToolStatusChip` subtree only — the streaming-state caret lives on the bubble's content `<p>`, not inside the chip, so the scoping is sufficient. Tests render with `messageState="tool_use"`, NOT `"streaming"`, so the caret is never rendered in the test render path anyway. Belt-and-suspenders: the test asserts `getByTestId("tool-status-chip").querySelector("span.animate-pulse")` is `null` — scoped to the chip, which post-fix has zero pulsing children.
- **Tests asserting on the dot's presence:** none found via `grep -rn "ToolStatusChip\|bg-amber-500\|animate-pulse" apps/web-platform/test/light-theme-tokenization.test.tsx apps/web-platform/test/message-bubble-memo.test.tsx apps/web-platform/test/message-bubble-header.test.tsx apps/web-platform/test/cc-soleur-go-end-to-end-render.test.tsx` (verified at deepen-plan time — query returned zero matches against the dot's class signature in any test file). The only places the dot string appears outside the components themselves are the 3-dot `ThinkingDots` (`bg-soleur-text-secondary`, different color) and the `RetryingChip` (`bg-amber-400`, different color). Neither is touched.
- **Test-runner / framework verification:** the existing chat-component tests use `vitest` + `@testing-library/react` with jsdom (verified by reading `tool-use-chip.test.tsx` and `message-bubble-retry.test.tsx`). The plan adds NO new test framework, NO new dev dependencies. Run via `bun test <path>` — matches the project's existing convention.
- **Component-test snapshot drift:** the codebase does not appear to use serialized snapshots for these components (verified via `find apps/web-platform/test -name "*.snap"` returning no chip/bubble snapshots). If any are added later, this change MAY require a regeneration — flag at QA time.
- **`gap-2` removal cosmetic:** if a future change adds a second child back to `ToolStatusChip` or `ToolUseChip`, the missing `gap-2` would re-emerge as a missing visual gap. **Decision (deepen-plan):** leave `gap-2` in place to minimize the diff and remove the future-trap. CSS `gap` is a no-op on a single-child flex container — zero visual effect, zero performance cost. The `## Files to Edit` paragraph reflects this — only the dot `<span>` is removed, not the `gap-2` class.
- **Theme drift across light/dark:** `light-theme-tokenization.test.tsx` references `MessageBubble` for theme-token coverage. Re-read at deepen-plan time confirmed it does NOT assert on `bg-amber-500` or the dot — it asserts on theme-color tokens. No theme regression risk from this change. The bubble's animated border (`border-amber-600/70`) and the `Working` badge (`text-amber-500`) survive untouched, so the light-theme rendering of the working state is unchanged.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The threshold here is `none` with explicit reasoning in the Risks section — no sensitive path is touched.
- The `RetryingChip` dot at `message-bubble.tsx:48` is intentionally OUT of scope. Confirm during review that it is still rendered and pulsing when `retrying=true`.
- Do NOT change `ThinkingDots` (line 14-22) — the three pulsing dots are the canonical loading indicator for the `thinking` state and the *only* visual cue there (no border animation precedes thinking — the bubble materializes at thinking-time).

## Test Strategy

- Vitest + jsdom (the existing chat-component test runner — confirmed by reading `tool-use-chip.test.tsx` which imports from `vitest` + `@testing-library/react`).
- Run via `bun test <path>` (matches the project's existing convention — `package.json scripts.test`).
- No new test framework, no new dev dependencies.

## Scope Boundary Audit (Deepen-Plan)

Per AGENTS.md `hr-when-a-plan-specifies-relative-paths-e-g`, when a plan paraphrases an issue body's enumeration, every same-class site must be inventoried via `git ls-files | grep -E` (or equivalent grep) before scoping. Audit performed at deepen-plan time:

```bash
grep -rn "bg-amber-500" apps/web-platform/components/chat/ --include="*.tsx" | grep -E "animate-pulse.*rounded-full.*bg-amber-500|h-[12](\.5)?\s+w-[12](\.5)?\s+animate-pulse\s+rounded-full\s+bg-amber-500"
```

Results — five sites use the `animate-pulse rounded-full bg-amber-500` pattern. Per-site disposition:

| File:Line | Component / Surface | Has companion border-animation + Working badge? | Disposition | Reasoning |
|---|---|---|---|---|
| `components/chat/message-bubble.tsx:27` | `ToolStatusChip` (in-bubble, `messageState === "tool_use"`) | YES — bubble has `message-bubble-active` animated border + top-right `Working` pill | **REMOVE** | Three redundant cues; this is the user's reported bug. |
| `components/chat/tool-use-chip.tsx:46` | `ToolUseChip` (pre-bubble chip for `cc_router` / `system` leaders) | NO bubble border, but YES — the chip itself has a colored border + rounded-full pill shape that conveys "this is a tool-use indicator" | **REMOVE** | Symmetric removal — the chip's outer border + pill shape is the visual contract; the inner dot is decorative duplication on a tool-use surface. Including this in the same PR prevents drift between the two `tool-use` rendering surfaces. |
| `components/chat/message-bubble.tsx:48` | `RetryingChip` (color is `bg-amber-400`, NOT `bg-amber-500` — different shade) | NO — the chip stands alone when `retrying=true`; the `Working` pill is replaced when retrying takes over | **KEEP** | The dot is the state cue — there is no other working-state indicator on this surface. Removing it would leave only static text. |
| `components/chat/chat-surface.tsx:619` | Routing chip, `isClassifying === true` ("Soleur Concierge is routing to the right experts...") | NO — flat chip on the page background, no surrounding bubble | **KEEP** | Pre-bubble routing surface is NOT a tool-use message (it's a classifier-pending cue). The dot is the only animated working-state indicator on this surface. Removing it would leave only static text + a `LeaderAvatar`. Out of scope per the user's request ("tool-use messages"). |
| `components/chat/subagent-group.tsx:104` | `SubagentStatusIcon` for `status === "running"` (default case) | NO — single per-subagent indicator inside a group | **KEEP** | Carries `aria-label="Subagent in flight"` — accessibility-load-bearing. The dot IS the visual cue (no other state indicator on this surface). Out of scope per the user's request. |

The two REMOVE rows are the only two sites that match the user's "tool-use messages" scope AND have redundant working-state cues at the same layer. The three KEEP rows are deliberate scope boundaries — each is documented in this audit so a reviewer can confirm the boundary is intentional.

## Out of Scope

- Removing or changing the bubble's animated border or the `Working` badge — these are the surviving working-state cues.
- Touching `ThinkingDots` (`thinking` state) or `RetryingChip` (`tool_use + retrying`) — different states, different visual contracts.
- Touching the routing chip in `chat-surface.tsx:619` or the subagent in-flight indicator in `subagent-group.tsx:104` — see Scope Boundary Audit above for reasoning.
- Restyling the chip — the chip's outer border + pill shape conveys the tool-use semantic without the inner dot.
- A general "remove all `animate-pulse rounded-full bg-amber-500` instances" cleanup — that would break the three KEEP surfaces. The fix is scoped to redundant tool-use indicators only.
