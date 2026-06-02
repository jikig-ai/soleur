---
title: "fix: align unified chat input box and apply it to the dashboard landing prompt"
type: fix
date: 2026-06-02
deepened: 2026-06-02
lane: single-domain
brand_survival_threshold: none
---

# fix: Align unified chat input box + apply ChatGPT-style unification to dashboard landing prompt

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** 3 (Risks & Mitigations / Precedent Diff added; Domain Review wireframe
reference added; Sharp Edges + realism caveats grounded against live code)
**Research approach:** local-only (strong in-repo prior art + verifiable precedent). External
research skipped — the two superseded 2026-04-12 alignment plans already grounded Tailwind v4
`min-h` / `items-end` / `field-sizing` semantics, and the unified-box precedent is verifiable by
`git`-reading `chat-input.tsx`. No high-risk domain (no security, payments, external API, data).

### Key Improvements
1. **Precedent-Diff gate (Phase 4.4):** added a side-by-side table proving the dashboard box
   mirrors `chat-input.tsx`'s container verbatim, and surfaced the load-bearing divergence — the
   precedent's auto-grow effect sets `style.height` inline (overriding `min-h`), which is why
   Part A needs visual verification while Part B (`<input>`, no auto-grow) is deterministic.
2. **Wireframe gate (Phase 4.9):** confirmed the committed `chat-ux-redesign.pen` already covers
   all three surfaces ("Chat Input", "Follow up…", "What are you building") — no new wireframe
   needed; referenced as the design source of truth.
3. **All halt gates verified green:** User-Brand Impact (threshold `none`, no sensitive path),
   Observability (skip — pure presentational), PAT-shaped sweep (no matches).

### New Considerations Discovered
- The textarea's resting height is governed by an inline `style.height = scrollHeight` effect
  (`chat-input.tsx:186-187`), NOT by the `min-h` class — so the padding value is a
  visual-verification output, not an arithmetic constant.
- Two open code-review issues (#2590 god-component extraction, #3334 gold-gradient CTA) touch
  `dashboard/page.tsx`; both acknowledged out-of-scope (different concerns, different lines).

## Overview

Commit `4c52fc1c` ("fix(chat): unify chat input into one bordered box (ChatGPT-style)", #4832)
reworked `apps/web-platform/components/chat/chat-input.tsx` so the paperclip, textarea, and
send button live inside ONE bordered/rounded container (the textarea borderless + transparent
inside it). That commit touched **only** the shared `ChatInput` component. Two problems remain:

1. **ALIGNMENT (regression inside the unified box).** Inside the new container the textarea
   carries `min-h-[40px]` + `py-2`, while the paperclip / send / stop buttons are `h-[36px]`,
   pinned to the bottom edge by the container's `items-end`. The 40px-vs-36px height mismatch
   plus the textarea's internal `py-2` padding leaves the controls visually 4px low and the
   text baseline off-center relative to the buttons. This is the SAME component on both the
   conversation/chat bottom bar AND the KB document ask panel — both surfaces render
   `ChatSurface → ChatInput`, so the misalignment is one defect manifesting in two places, not
   two separate surfaces that "did not land cleanly."

2. **NOT DONE ON DASHBOARD (never unified).** The Dashboard first-run landing prompt
   ("Tell your organization what you're building." / `placeholder="What are you building?"`) at
   `apps/web-platform/app/(dashboard)/dashboard/page.tsx:505-553` is a separate, hand-rolled
   input: a bordered paperclip `<button>` on the left, a bordered single-line `<input>` in the
   middle, and a bordered orange send `<button>` on the right — the pre-4c52fc1c style. The
   ChatGPT-style unification was never applied here. This surface needs the unified single-
   bordered-box treatment so it visually matches the chat and KB surfaces.

The fix is a CSS/markup change only — no behavior, data, schema, or route changes.

## Research Reconciliation — Spec vs. Codebase

| Premise (from task description) | Reality in codebase | Plan response |
|---|---|---|
| "alignment did not land cleanly across **all** chat input surfaces (KB panel + conversation view)" | KB panel and conversation view BOTH mount `ChatSurface → ChatInput` (verified: `kb-chat-content.tsx:176 <ChatSurface>`, `chat-surface.tsx:805 <ChatInput>`). The misalignment is in the single shared `ChatInput`, not per-surface. | Fix the alignment once in `chat-input.tsx`; it propagates to both surfaces automatically. Verify on both. |
| "Dashboard chat input is still the OLD style; unification was NOT applied here" | Confirmed: `dashboard/page.tsx:505-553` is a bespoke `flex items-center gap-3` row with three separately-bordered controls and a single-line `<input>` (not the shared component). | This is a **build** (apply unification to the dashboard markup), not a patch of a shared component. Wrap the three controls in one bordered container mirroring `ChatInput`'s box; make the input borderless/transparent inside. |
| The shared component is "the chat input component(s) introduced/modified in 4c52fc1c" | `git show 4c52fc1c --stat` → only `apps/web-platform/components/chat/chat-input.tsx` (plus tests + AGENTS docs). | Single shared component is `chat-input.tsx`. Dashboard does NOT import it today. |

**Premise Validation:** No external GitHub issues/PRs are cited by reference in the task beyond
commit `4c52fc1c`, which is verified present on this branch's history (`git show 4c52fc1c`). All
cited file/symbol paths confirmed to exist on the working tree: `chat-input.tsx` unified box at
lines 604-698; dashboard old-style input at `dashboard/page.tsx:505-553`. Both surfaces are
"UI exists but is misaligned/not-unified" (behavioral fix + markup build), not never-built.
Prior art exists: `knowledge-base/project/plans/2026-04-12-fix-chat-input-vertical-alignment-plan.md`
documents the PRE-unification alignment approach (`items-end` + `min-h-[44px]` matching 44px
buttons) — superseded by 4c52fc1c which shrank buttons 44→36px and the textarea floor to 40px,
introducing the current 4px mismatch.

## User-Brand Impact

**If this lands broken, the user experiences:** a chat input box on the dashboard, chat view, or
KB panel where the paperclip and send button sit visibly low/off-center relative to the typed
text — the same "controls floating beside the field" cosmetic defect 4c52fc1c set out to fix,
now half-finished. It looks unpolished but remains fully functional (send, attach, @mention all
work).
**If this leaks, the user's data / workflow / money is exposed via:** N/A — no data path, auth,
or persistence is touched. Pure presentational CSS/markup.
**Brand-survival threshold:** none — cosmetic alignment of an existing, working control. No
sensitive-path file is touched (no schema, migration, auth flow, API route, or `.sql`).

## Problem Statement

### Problem 1 — alignment inside the unified box (`chat-input.tsx`)

Current unified container (`chat-input.tsx:604-608`):

```tsx
<div
  className={
    "flex items-end gap-1.5 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 px-2 py-1.5 transition-shadow focus-within:border-soleur-border-emphasized" +
    (flashQuote ? " ring-2 ring-amber-400" : "")
  }
>
```

Children inside it:

- Paperclip button: `h-[36px] w-[36px] ... rounded-lg` (`:615`)
- Textarea (wrapped in `<div className="relative flex-1">` at `:635`):
  `... px-1 py-2 pr-8 ... min-h-[40px] max-h-[140px] ...` (`:646`)
- Stop button: `h-[36px] min-w-[36px] ... rounded-lg` (`:669`)
- Send button: `h-[36px] w-[36px] ... rounded-lg` (`:682`)

With `items-end`, every child is pinned to the container's bottom edge. The textarea's outer
box is `min-h-[40px]` (its `py-2` = 8px top + 8px bottom around a ~20px line ≈ 36px content,
floored to 40px); the buttons are 36px. The 4px delta means, in the single-line default state,
the 36px buttons sit 4px below the textarea's top and their vertical centers do not line up with
the text. The result reads as "paperclip + send slightly low" — the alignment defect in the
screenshots. (Same root cause class as the pre-unification 2026-04-12 plan, but the numbers
changed: that plan matched a 44px textarea floor to 44px buttons; 4c52fc1c shrank buttons to
36px but left the textarea floor at 40px.)

### Problem 2 — dashboard landing prompt is un-unified (`dashboard/page.tsx`)

`dashboard/page.tsx:505-553` renders three separately-styled, separately-bordered controls in a
`flex items-center gap-3` row:

- Paperclip `<button>` with its OWN `rounded-xl border border-soleur-border-default` (`:510`)
- A single-line `<input name="idea">` with its OWN `rounded-xl border ... bg-soleur-bg-surface-1` (`:534`)
- Send `<button>` with its OWN `rounded-xl bg-amber-600` box (`:545`)

This is exactly the pre-4c52fc1c "three floating boxes" pattern the unification eliminated for
the chat surface. It must be wrapped into a single bordered container mirroring `ChatInput`'s
box, with the input made borderless/transparent inside.

## Proposed Solution

### Part A — Fix alignment in the shared `ChatInput` (`chat-input.tsx`)

Goal: in the single-line default state the paperclip, text baseline, and send/stop buttons line
up; in the multi-line state the buttons stay pinned to the bottom edge (the `items-end` intent).

Make the textarea's resting outer height equal the 36px button height, and align its internal
text padding so the single-line baseline sits on the button centerline. Concretely:

1. **Match the textarea floor to the buttons.** Change the textarea's `min-h-[40px]` →
   `min-h-[36px]` so its resting outer box equals the 36px buttons. The `max-h-[140px]` and
   `overflow-y-auto` are unchanged. (`chat-input.tsx:646`)
2. **Re-balance the textarea's vertical padding** so a single line is vertically centered within
   the 36px box rather than top-weighted. With `text-sm` (20px line-height) inside a 36px box,
   `py-2` (16px total) overshoots (20+16 = 36 exactly, but the auto-grow effect resets
   `height:auto` then sets `scrollHeight`, which includes padding — see `chat-input.tsx:186-187`).
   Reduce to `py-1.5` (12px total → 20+12 = 32, floored up to 36 by `min-h`), which leaves the
   single line vertically centered against the 36px buttons. **The exact padding value MUST be
   chosen by visual verification (Playwright, below), not asserted blind** — `py-1.5` is the
   starting hypothesis; `py-2` with `min-h-[36px]` may already be correct once the floor matches.
3. **Keep `items-end`** on the container (correct for multi-line growth — buttons stay at the
   bottom alongside the last line). Do NOT switch to `items-center` (it would break multi-line
   by floating the buttons to the vertical middle of an expanded textarea — see the 2026-04-12
   plan "Why not items-center?").
4. **Re-check the auto-grow effect interaction.** `chat-input.tsx:186-187` does
   `el.style.height = "auto"; el.style.height = Math.min(el.scrollHeight, 140) + "px"`. After
   the `min-h`/`py` change, confirm the resting (empty) textarea still renders at the 36px floor
   and growth still caps at 140px. No JS change is expected, but this is a verification step.
5. **Mobile @ button position** (`chat-input.tsx:649-657`, `absolute bottom-2 right-1`) must
   stay visually inside the textarea after the padding change — verify at the 375px breakpoint.

> The textarea-class change interacts with two tests (see Test Strategy) that assert
> `min-h-[40px]` literally. Both must be updated to the new floor value in the SAME commit.

### Part B — Apply the unified box to the dashboard landing prompt (`dashboard/page.tsx`)

Mirror `ChatInput`'s container exactly so the three surfaces look identical. Replace the
`flex items-center gap-3` row (`:505-553`) and its three separately-bordered controls with ONE
bordered container holding borderless children:

- **Container:** `flex items-end gap-1.5 rounded-xl border border-soleur-border-default
  bg-soleur-bg-surface-1 px-2 py-1.5 transition-shadow focus-within:border-soleur-border-emphasized`
  (identical to `chat-input.tsx:606`, minus the `flashQuote` ring which has no analogue here).
- **Paperclip button:** drop its own border; use
  `flex h-[36px] w-[36px] shrink-0 items-center justify-center rounded-lg text-soleur-text-secondary
  transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary` (mirror
  `chat-input.tsx:615`). Keep its `onClick`, `aria-label`, and the existing paperclip SVG.
- **Input:** drop its own border + background; make it borderless/transparent inside the box:
  `w-full resize-none border-none bg-transparent px-1 text-sm text-soleur-text-primary
  placeholder:text-soleur-text-muted focus:outline-none` plus a height that matches the chat
  textarea resting state (`min-h-[36px]` or the verified `py` value). Wrap it in
  `<div className="flex-1">` so it flexes like the chat textarea wrapper. Keep `name="idea"`,
  `placeholder="What are you building?"`, `autoFocus`, and the existing `onPaste` handler.
  (Decision: keep it as a single-line `<input>` — the dashboard prompt is a one-shot idea entry,
  not a multi-turn textarea. Do NOT convert to `<textarea>`; that is scope creep and would change
  Enter-to-submit semantics. The visual unification is achieved by the borderless-in-box styling
  regardless of element type.)
- **Send button:** drop its own bordered box; use
  `flex h-[36px] w-[36px] shrink-0 items-center justify-center rounded-lg bg-amber-600
  text-soleur-text-on-accent transition-colors hover:bg-amber-500` (mirror `chat-input.tsx:682`).
  Keep `type="submit"`, `aria-label`, and the existing send SVG.

The surrounding `<form onSubmit={handleFirstRunSend}>` (`:454-464`), drag-over wrapper, the
attachment preview strip (`:466-498`), the error message (`:501-503`), the hidden file `<input>`
(`:517-527`), and all handlers (`fileInputRef`, `validateAndAddFiles`, `firstRunAttachments`,
`removeFirstRunAttachment`) are UNCHANGED — only the visible control row's markup/classes change.

**DRY consideration (explicit decision):** Do NOT refactor the dashboard to import the shared
`ChatInput` component. `ChatInput` is tightly coupled to chat concerns it doesn't need here
(@mention dropdown wiring via `onAtTrigger`/`insertRef`, `streamState`/`onStop` turn lifecycle,
`draftKey` sessionStorage, presigned upload via `conversationId`, the WS-connected `onSend`
contract). Forcing the first-run one-shot prompt through that surface would require threading or
stubbing ~10 props and would entangle the dashboard's `handleFirstRunSend` (which POSTs to start
a NEW conversation) with the chat surface's send semantics. The cost/benefit favors mirroring
the ~30 lines of container/control markup. The shared styling is the contract being unified, not
the component. (If a future change makes the two truly identical, extract a presentational
`UnifiedInputBox` wrapper then — YAGNI for now.)

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/components/chat/chat-input.tsx` | Part A: textarea `min-h-[40px]`→`min-h-[36px]`; re-balance `py` (verified value); keep `items-end`. Lines ~646 (and container `:604-608` only if the focus/ring stays put). |
| `apps/web-platform/app/(dashboard)/dashboard/page.tsx` | Part B: replace the `:505-553` control row with one bordered container holding a borderless paperclip button, borderless transparent `<input>`, and borderless orange send button mirroring `ChatInput`'s box. |
| `apps/web-platform/test/chat-input.test.tsx` | Update `:136` `expect(textarea.className).toContain("min-h-[40px]")` → the new floor (`min-h-[36px]`). |
| `apps/web-platform/test/chat-input-auto-grow.test.tsx` | Update `:46` `expect(textarea.className).toMatch(/min-h-\[40px\]/)` → new floor regex. The `:44` negative `h-[\d+px]` guard and `:47` `max-h-[140px]` assertions are unchanged. |

> **Class-assertion sweep (per learning `2026-06-02-test-class-assertion-sweep-must-use-bare-token-not-bracketed.md`,
> authored by 4c52fc1c itself):** grep the BARE token, not the bracketed form, before freezing
> the test edits. Run `grep -rn "min-h-\[40px\]" apps/web-platform` AND
> `grep -rn "40px" apps/web-platform/test/chat-input*.tsx` to catch BOTH the `toContain("min-h-[40px]")`
> literal AND the `toMatch(/min-h-\[40px\]/)` regex-literal (escaped brackets) sibling. The
> 4c52fc1c PR shipped a CI break precisely because the first sweep matched the `toContain` test
> but missed the `toMatch` regex test. There are exactly two assertions today (verified above);
> the grep confirms the count before editing.

## Files to Create

None.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open --json number,title,body --limit 200` and
checked each planned file path against the bodies.

Two open code-review issues touch `dashboard/page.tsx`:

- **#2590** (refactor: extract `useFirstRunAttachments` + `FirstRunComposer` from DashboardPage):
  **Acknowledge.** My Part B restyles the same first-run composer markup, but the god-component
  extraction is a materially larger refactor (new hook + new component file, target <500 lines)
  and a different concern. Folding it in would balloon a cosmetic fix into an architectural one.
  The styling change leaves the composer markup smaller/cleaner, which eases the later
  extraction. #2590 stays open; its re-eval criterion ("a new feature forces editing this file")
  is acknowledged but the alignment fix is not the right vehicle for the extraction.
- **#3334** (consolidate gold-gradient primary CTA): **Acknowledge.** Touches the "New
  conversation" gold-gradient CTAs at `dashboard/page.tsx:526`/`:623`, NOT the first-run input
  send button (which uses solid `bg-amber-600`, unchanged by this plan). Different lines,
  different concern. Out of scope; #3334 stays open.

No overlap with `chat-input.tsx` or the two test files.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] In the conversation/chat bottom input bar, single-line state: the paperclip, the typed-text
      baseline, and the send button are visually aligned (no 4px low offset). Verified by
      Playwright screenshot at 1280px.
- [ ] In the KB document ask panel (right sidebar), the same alignment holds — verified by
      screenshot (same `ChatInput`, confirm it propagated).
- [ ] When the chat textarea grows to multiple lines, the paperclip and send/stop buttons stay
      pinned to the bottom edge alongside the last line (`items-end` preserved).
- [ ] The mobile @ button stays visually inside the textarea at the 375px breakpoint.
- [ ] On the Dashboard first-run landing page ("Tell your organization what you're building."),
      the paperclip, `"What are you building?"` input, and orange send button render inside ONE
      bordered rounded container (no three separate boxes), visually matching the chat/KB box.
      Verified by Playwright screenshot at 1280px.
- [ ] The dashboard input box's focus state highlights the whole container
      (`focus-within:border-soleur-border-emphasized`), like the chat box.
- [ ] Dashboard send still submits via `handleFirstRunSend`; paperclip still opens the file
      picker and attachments still preview above the box (handlers untouched).
- [ ] `apps/web-platform/test/chat-input.test.tsx` and `chat-input-auto-grow.test.tsx` pass with
      the updated floor assertion. No remaining `min-h-[40px]` reference anywhere in
      `apps/web-platform` (grep returns zero).
- [ ] `tsc --noEmit` and the web-platform test suite pass (use the project's configured runner,
      not a hardcoded one — see Sharp Edges).

### Post-merge (operator)

- [ ] None. Automation: the PR merge deploys via `web-platform-release.yml` (path-filtered on
      `apps/web-platform/**`); no manual step.

## Domain Review

**Domains relevant:** Product

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — `ux-design-lead` N/A: this modifies the styling of EXISTING
input controls to match an already-shipped, already-designed pattern (4c52fc1c's ChatGPT-style
box). No new page, no new flow, no new interactive surface, no new component file. Both edited
files already exist. The target design is the committed wireframe (below), so a new wireframe
would be redundant.
**Pencil available:** committed `.pen` already covers the surfaces (no new artifact needed).

**Wireframe (committed, authoritative for this change):**
`knowledge-base/product/design/command-center/chat-ux-redesign.pen` — verified committed
(`git ls-files`), 119 KB. It already contains the target design for ALL THREE surfaces in scope:
the **"Chat Input"** box, the conversation **"Follow up…"** bottom bar, and the dashboard
**"What are you building"** landing prompt (verified by string-grep into the `.pen`). This plan
brings the implementation into conformance with that committed design — the wireframe is the
source of truth, not a new deliverable. Satisfies `wg-ui-feature-requires-pen-wireframe` /
deepen-plan Phase 4.9.

#### Findings

CSS/markup-only correction bringing two surfaces into visual parity with the already-approved
unified-box design captured in `chat-ux-redesign.pen`. No copy changes (placeholder/heading text
unchanged). No brand-voice or flow implications. Visual verification via Playwright (against the
committed wireframe) is the appropriate gate, not a new wireframe.

## Observability

Skipped — pure presentational change. No new code-class behavior under `apps/*/server/`,
no new infra surface, no new failure mode. The edited files are a client component
(`chat-input.tsx`) and a client page (`dashboard/page.tsx`); the change is CSS classes + JSX
structure with zero new runtime logic, network call, or error path. (Plan Phase 2.9 skip
condition: no new code/infra surface that could fail silently.)

## Test Strategy

- **Unit (jsdom, existing):** update the two class assertions to the new floor; the auto-grow
  test's negative `h-[\d+px]` guard and `max-h-[140px]` assertion already cover the
  no-fixed-height + cap invariants and must still pass.
- **Visual (Playwright MCP):** the load-bearing verification for an alignment fix. Per
  institutional learning (`footer-layout-redesign-flex-children-visual-verification`), capture
  screenshots at 1280 / 768 / 375 px, before and after, for ALL THREE surfaces:
  (1) `/dashboard/chat/[id]` bottom bar, (2) KB doc panel ask box, (3) `/dashboard` first-run
  prompt. Confirm single-line alignment and multi-line button-pinning on the chat surfaces, and
  the single-box rendering on the dashboard. **The exact `py` value in Part A step 2 is chosen
  from this visual pass, not asserted blind.**

### Test Scenarios

- Given a chat page with a single-line input, when rendered, then paperclip + text baseline +
  send button line up at 1280px.
- Given the KB doc ask panel open, when rendered, then the same alignment holds (shared component).
- Given a chat input expanded to 3 lines, when rendered, then buttons stay at the bottom edge.
- Given the dashboard first-run page, when rendered, then the three controls sit inside one
  bordered box and the box border-emphasizes on focus.
- Given the dashboard input focused and an idea typed, when send is clicked, then
  `handleFirstRunSend` fires (behavior unchanged).
- Given a 375px viewport on the chat surface, when rendered, then the mobile @ button stays
  inside the textarea.

## Risks & Mitigations — Precedent Diff (deepen-plan Phase 4.4)

The dashboard unified box is a **pattern-bound behavior** with an in-repo precedent: the
`ChatInput` container. Side-by-side (verified `git`-read at deepen time):

| Element | Precedent (`chat-input.tsx`) | Dashboard target (`page.tsx`) |
|---|---|---|
| Container | `:606` `flex items-end gap-1.5 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 px-2 py-1.5 transition-shadow focus-within:border-soleur-border-emphasized` | identical, minus the `flashQuote` ring (no quote-flash analogue on the dashboard) |
| Paperclip | `:615` borderless `h-[36px] w-[36px] rounded-lg ... hover:bg-soleur-bg-surface-2` | identical |
| Send | `:682` borderless `h-[36px] w-[36px] rounded-lg bg-amber-600 ... hover:bg-amber-500` | identical |
| Text field | `<textarea>` borderless transparent, auto-grow effect (`:186-187`) | `<input>` borderless transparent, **no auto-grow** (single-line by nature) |

**Key precedent-divergence note (realism pass):** the precedent's `<textarea>` height is driven by
a `useIsomorphicLayoutEffect` that sets `el.style.height = scrollHeight` inline (`chat-input.tsx:186-187`),
which **overrides the `min-h` Tailwind class via the higher-specificity inline `height`**. That is
why the Part A padding/`min-h` change MUST be visually verified — the inline-height effect, not the
class alone, determines the resting height. The **dashboard `<input>` has NO such effect**, so its
`min-h-[36px]` behaves predictably (a plain single-line input clamps to the padding+line-height,
floored by `min-h`). Conclusion: Part B's alignment is low-risk (deterministic); Part A's is the
one requiring the Playwright pass.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold `none`, with a
  sensitive-path scope-out rationale since the diff touches no sensitive path.)
- **Two test assertions, two forms.** The textarea height class is asserted both as
  `toContain("min-h-[40px]")` (literal) and `toMatch(/min-h-\[40px\]/)` (escaped-bracket regex)
  in two different files. A bare-token grep (`grep -rn "min-h-\[40px\]"`) catches both; a
  bracket-escaped grep can miss one. This is the exact CI break 4c52fc1c shipped — do not repeat.
- **Use the project's configured test runner, not a hardcoded one.** `apps/web-platform`
  uses vitest with `test/**/*.test.tsx` discovery (the two chat-input tests live under `test/`).
  Check `apps/web-platform/vitest.config.ts` `include:` globs and `package.json scripts.test`
  before prescribing a run command; `apps/web-platform/bunfig.toml` may carry a
  `pathIgnorePatterns` that blocks `bun test` discovery entirely.
- **Padding is a visual-verification output, not a constant to assert blind.** The `py` value in
  Part A step 2 (`py-1.5` hypothesis) must be confirmed by the Playwright pass. Picking it from
  arithmetic alone risks an off-by-a-few-pixels result because the auto-grow effect resets
  `height:auto` and reads `scrollHeight` (which includes padding) at `chat-input.tsx:186-187`.
- **Do not switch `items-end` → `items-center`.** It fixes single-line at the cost of breaking
  multi-line button pinning (documented in the superseded 2026-04-12 vertical-alignment plan).
- **Both toggle states.** The chat input has a single-line resting state and a multi-line grown
  state, and a Send-vs-Stop swap (`showStop`). Verify alignment in single-line AND multi-line,
  and that the Stop button (`h-[36px] min-w-[36px]`, `chat-input.tsx:669`) aligns identically to
  Send — per learning `2026-04-17-alignment-fixes-must-verify-both-toggle-states.md`.

## Context

- Superseded prior art: `knowledge-base/project/plans/2026-04-12-fix-chat-input-vertical-alignment-plan.md`
  and `2026-04-12-fix-chat-input-alignment-plan.md` (pre-unification 44px-floor approach).
- Unification commit: `4c52fc1c` (#4832) — the source of the current box and the 36px buttons.
- Learning authored by that same commit:
  `knowledge-base/project/learnings/2026-06-02-test-class-assertion-sweep-must-use-bare-token-not-bracketed.md`.

### Related files

- `apps/web-platform/components/chat/chat-input.tsx` — shared unified box (Part A target).
- `apps/web-platform/components/chat/chat-surface.tsx:805` — mounts `ChatInput` (conversation + KB).
- `apps/web-platform/components/chat/kb-chat-content.tsx:176` — KB panel → `ChatSurface`.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx:505-553` — dashboard old-style input (Part B target).
- `apps/web-platform/test/chat-input.test.tsx`, `chat-input-auto-grow.test.tsx` — class assertions to update.
