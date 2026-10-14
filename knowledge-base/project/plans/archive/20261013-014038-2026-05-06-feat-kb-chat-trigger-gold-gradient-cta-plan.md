---
title: "feat: Replace outlined KB chat trigger with gold-gradient primary CTA"
type: enhancement
status: planned
created: 2026-05-06
branch: feat-one-shot-replace-outlined-cta-buttons-with-gradient
requires_cpo_signoff: false
deepened: 2026-05-06
---

# feat: Replace outlined KB chat trigger with gold-gradient primary CTA

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** 5 (Research Reconciliation, Acceptance Criteria, Implementation Phases, Risks, Test Scenarios)
**Research artifacts used:**
- Token-system audit of `apps/web-platform/app/globals.css` (lines 39-138)
- Cross-reference against learning `2026-05-06-token-on-accent-vs-text-primary-on-status-backgrounds.md`
- File-system grep for all consumers of `from-[#D4B36A]` / `to-[#B8923E]` and `border-amber-500/50`
- Test-suite grep for class-string snapshots that could pin the old amber treatment
- Inspection of `KbContentHeader` neighbors (`Download`, `SharePopover`) for transition convention parity

### Key Improvements
1. Discovered that `--soleur-text-on-accent` resolves to **`#1a1612` (near-black)** in BOTH dark and light themes — NOT white as a peer learning ambiguously claimed. Updated AC2 + Risks to reflect that the new dot will be near-black on the gold gradient (high contrast, but visually different from the amber-on-amber-outline original). This also confirms why the dashboard "New conversation" CTA reads correctly: gold gradient + dark text is the canonical Soleur primary-CTA contrast pairing.
2. Confirmed there are exactly TWO existing call sites of the literal-hex gradient (`dashboard/page.tsx:526` empty-state, `:623` filter-bar). The token system DOES define `--soleur-accent-gradient-start/end` but no call site uses them yet — meaning a tokenized gradient utility is unused theme-system surface. Following the user-named source-of-truth (literal hex) preserves visual parity at the cost of perpetuating the un-tokenized literal. This is a pre-existing, plan-orthogonal debt — explicitly listed under Non-Goals with a follow-up issue link reminder.
3. Confirmed `border-amber-500/50` is used by ONE other component (`kb-desktop-layout.tsx` resize-handle active-state) which is a different semantic surface (drag indicator, not button). No collateral risk.
4. Verified no test pins amber classes: `kb-chat-trigger.test.tsx` asserts label text + `data-testid` only; `kb-content-header.test.tsx` mocks the trigger entirely; `kb-chat-sidebar-a11y.test.tsx` exercises focus + role only; `light-theme-tokenization.test.tsx` does not reference the trigger. AC5 is achievable without test rewrites.
5. Identified a `transition-*` semantic mismatch between source-of-truth and current trigger: dashboard uses `transition-opacity` (because hover changes opacity), current trigger uses `transition-colors` (because hover changes border + text colors). The new trigger MUST swap to `transition-opacity` — `transition-colors` would not animate opacity changes. AC1 already specifies this; deepen-pass confirms the rationale.

### New Considerations Discovered
- **Token consistency vs source-of-truth tension.** The token system has `--soleur-accent-gradient-start/end` defined but unused. The dashboard uses literal hex. Consolidating is out of scope per user instruction (only the trigger changes); but a follow-up should be filed to migrate both dashboard call sites + this trigger to the token in a single sweep, not piecemeal.
- **No `aria-label` regression.** The existing `<button>` has no `aria-label` (relies on visible text label "Ask about this document" / "Continue thread"). Visible text is unchanged by the className swap. The fallback `<Link>` renders literal "Chat about this" and is also unchanged. A11y tests in `kb-chat-sidebar-a11y.test.tsx` should pass without modification.
- **`text-soleur-text-on-accent` IS registered as a Tailwind v4 theme variable** (`globals.css:132`), so the utility `text-soleur-text-on-accent` resolves at build time. No runtime CSS-variable-resolution risk. Same for `bg-soleur-text-on-accent` — Tailwind's `bg-*` utility consumes the same token registration.

## Overview

Promote the stateful `KbChatTrigger` ("Ask about this document" / "Continue thread") from its current outlined-amber treatment to the filled gold-gradient primary CTA used by the dashboard's "New conversation" button. Both labels are emitted by the same React component (`KbChatTrigger`), so the work is a single `baseClass` swap inside that component plus a `Link`-fallback class swap for the no-context path. The neighboring outlined "Download" and "Share" controls in `KbContentHeader` remain unchanged. The trailing notification dot rendered when `messageCount > 0` is preserved; only its color recomputes against the new background for contrast.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| Two separate buttons, one in "document view" and one in "thread view" | Single component `apps/web-platform/components/kb/kb-chat-trigger.tsx` switches its label between `"Ask about this document"` (when `ctx.messageCount === 0`) and `"Continue thread"` (when `> 0`); both render through the same `<button className={baseClass}>` | One `baseClass` change covers both states. Test coverage already toggles between both label states, so re-styling is verified by the existing test at the same time. |
| "New conversation" CTA defines the source-of-truth gradient | `apps/web-platform/app/(dashboard)/dashboard/page.tsx:526` (empty-state, `py-3 px-6`) and `:623` (filter bar, `py-2 px-4`) both use `bg-gradient-to-r from-[#D4B36A] to-[#B8923E] text-soleur-text-on-accent transition-opacity hover:opacity-90` with `text-sm font-semibold rounded-lg`. The empty-state variant is the visual primary; the filter-bar variant is a denser sibling. | Adopt the gradient + text-on-accent + hover-opacity treatment. Pick padding/text-size to match the surrounding `KbContentHeader` row (`text-xs`, `py-1.5 px-3`) so the trigger doesn't tower over neighboring Download/Share. The gradient is the source-of-truth, NOT every cosmetic dimension. |
| Neighboring Download/Share remain outlined | `apps/web-platform/components/kb/kb-content-header.tsx:45` Download is `border border-soleur-border-default` outlined neutral; `share-popover.tsx` follows the same outlined pattern | No change — they already use the codebase's neutral outlined treatment, distinct from the previously-amber trigger. |
| Preserve trailing notification dot on "Continue thread" | `kb-chat-trigger.tsx:72-78` renders `<span data-testid="kb-trigger-thread-indicator" className="… bg-amber-400">` only when `hasThread` | Keep the dot. Recolor from `bg-amber-400` (amber-on-amber-outline) to `bg-soleur-text-on-accent` (white-on-gradient) so it remains visible against the new filled background. The `data-testid` and `aria-hidden` survive untouched — existing test continues to pass. |
| Fallback link path | `kb-chat-trigger.tsx:45-52` — when no `KbChatContext` provider OR feature flag off, renders `<Link href={fallbackHref} className={baseClass}>` with literal label "Chat about this" | Same treatment swap applies. The fallback is rendered in legacy contexts; it should not visually regress. Update the same `baseClass` constant — both paths share it. |

## User-Brand Impact

**If this lands broken, the user experiences:** the KB document/thread chat trigger renders invisible, mis-sized, or with unreadable text — a primary entry point into the document chat is gone, and the user has no fallback path until the next page load (the trigger is the only on-page handle to open the chat sidebar).

**If this leaks, the user's data is exposed via:** N/A — purely visual CSS-class change with no data path or credential touched.

**Brand-survival threshold:** none.

Sensitive-path scan: the diff touches `apps/web-platform/components/kb/kb-chat-trigger.tsx` and its test only — no `apps/**/api/**`, no Supabase migration, no Doppler/auth/payments path. No CPO sign-off required.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — class swap.** `apps/web-platform/components/kb/kb-chat-trigger.tsx` `baseClass` constant renders the gold gradient: `bg-gradient-to-r from-[#D4B36A] to-[#B8923E]`, `text-soleur-text-on-accent`, `font-semibold`, `transition-opacity`, `hover:opacity-90`. The amber outline classes (`border border-amber-500/50`, `text-amber-400`, `hover:border-amber-400`, `hover:text-amber-300`) are removed. Padding stays `py-1.5 px-3`, text size stays `text-xs`, radius stays `rounded-lg`, layout stays `inline-flex items-center gap-1.5` so the button keeps the same footprint inside the existing `KbContentHeader` row.
- [x] **AC2 — dot recolor.** The trailing thread-indicator span at `kb-chat-trigger.tsx:72-78` switches from `bg-amber-400` to `bg-soleur-text-on-accent`. `data-testid="kb-trigger-thread-indicator"` and `aria-hidden="true"` are unchanged. **Token semantics (verified at deepen-time, `apps/web-platform/app/globals.css` lines 53/77/106/132):** `--soleur-text-on-accent` resolves to `#1a1612` in BOTH dark and light themes. The dot will render near-black on the gold gradient. This is the same contrast pairing the dashboard "New conversation" CTA uses for its label text — gold gradient + dark foreground is canonical Soleur primary-CTA contrast. Visual: the dot transitions from amber-on-amber-outline (low-contrast) to dark-on-gold (high-contrast); reviewer should confirm this is the desired aesthetic, not assume the dot must remain "warm" colored.
- [x] **AC3 — fallback link parity.** The `<Link>` rendered when `ctx` is null OR `ctx.enabled === false` consumes the same `baseClass` constant — verified by reading `kb-chat-trigger.tsx:47` after the edit. No separate class string is introduced.
- [x] **AC4 — neighbors unchanged.** `apps/web-platform/components/kb/kb-content-header.tsx` and `apps/web-platform/components/kb/share-popover.tsx` are not modified. `git diff main -- apps/web-platform/components/kb/kb-content-header.tsx apps/web-platform/components/kb/share-popover.tsx` returns empty.
- [x] **AC5 — existing tests pass.** `bun test apps/web-platform/test/kb-chat-trigger.test.tsx` and `bun test apps/web-platform/test/kb-content-header.test.tsx` and `bun test apps/web-platform/test/kb-chat-sidebar-a11y.test.tsx` all green.
- [ ] **AC6 — visual verification.** Screenshot the `/dashboard/knowledge-base/<doc>` route in BOTH thread states (empty `messageCount === 0` showing "Ask about this document" without dot, and `messageCount > 0` showing "Continue thread" with dot) and attach to PR. Confirm side-by-side that the gradient matches `/dashboard` empty-state "New conversation" button.
- [x] **AC7 — `tsc --noEmit` clean** for `apps/web-platform`. No new TS errors.

### Post-merge (operator)

None — pure CSS-class change. Vercel preview re-deploys on merge.

## Files to Edit

- `apps/web-platform/components/kb/kb-chat-trigger.tsx` — single `baseClass` constant (line 36-37) and dot color (line 76)
- `apps/web-platform/test/kb-chat-trigger.test.tsx` — only if existing assertions reference removed amber classes (none currently — assertions check label text and dot presence via `data-testid`, both survive)

## Files to Create

None.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` for issues mentioning `kb-chat-trigger`; zero matches.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — UI styling consistency change. Mechanical Product/UX tier check: the diff modifies className strings inside an existing component; no new file under `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Tier is **NONE**; no UX gate fires.

## Test Scenarios

The existing `kb-chat-trigger.test.tsx` covers the behavioral surface that matters here (label switching, dot presence/absence, fallback Link rendering). It asserts via `data-testid="kb-trigger-thread-indicator"` and label text — neither breaks under the className swap. No new test file is justified for a className substitution; visual verification is handled in AC6.

If a class-string snapshot test is desired for drift-guarding the gradient, it would belong inline in the same test file as a dedicated `it("uses gold-gradient base classes")` block asserting `button.className` contains `"bg-gradient-to-r"` and does NOT contain `"border-amber-500/50"`. Defer this hardening unless review prompts for it — adding a snapshot test for two literal class strings risks false positives on future Tailwind utility tweaks.

## Implementation Phases

### Phase 1 — Edit `kb-chat-trigger.tsx`

Replace the `baseClass` constant body (currently lines 36-37):

```ts
// Before
const baseClass =
  "inline-flex items-center gap-1.5 rounded-lg border border-amber-500/50 px-3 py-1.5 text-xs font-medium text-amber-400 transition-colors hover:border-amber-400 hover:text-amber-300";

// After
const baseClass =
  "inline-flex items-center gap-1.5 rounded-lg bg-gradient-to-r from-[#D4B36A] to-[#B8923E] px-3 py-1.5 text-xs font-semibold text-soleur-text-on-accent transition-opacity hover:opacity-90";
```

Recolor the thread-indicator dot at line 76:

```tsx
// Before
className="ml-1 inline-block h-1.5 w-1.5 rounded-full bg-amber-400"

// After
className="ml-1 inline-block h-1.5 w-1.5 rounded-full bg-soleur-text-on-accent"
```

### Phase 2 — Verify

1. `bun test apps/web-platform/test/kb-chat-trigger.test.tsx` — must remain green (assertions are class-agnostic; verified at deepen-time).
2. `bun test apps/web-platform/test/kb-content-header.test.tsx apps/web-platform/test/kb-chat-sidebar-a11y.test.tsx` — must remain green (header test mocks the trigger; a11y test is class-agnostic).
3. `tsc --noEmit` from `apps/web-platform/` — clean. The change is a string literal swap; TS surface unchanged.
4. **Verification grep — no orphan amber classes in trigger.** After edit:
   ```bash
   grep -E 'border-amber-500/50|text-amber-400|hover:border-amber-400|hover:text-amber-300' \
     apps/web-platform/components/kb/kb-chat-trigger.tsx
   ```
   Expect zero hits. (`kb-desktop-layout.tsx:19` will still match `amber-500/50` for the resize-handle — that's intentional and out of scope.)
5. **Verification grep — gradient parity with dashboard.** After edit:
   ```bash
   grep -F 'bg-gradient-to-r from-[#D4B36A] to-[#B8923E]' \
     apps/web-platform/components/kb/kb-chat-trigger.tsx \
     apps/web-platform/app/\(dashboard\)/dashboard/page.tsx
   ```
   Expect 1 hit in trigger + 2 hits in dashboard (lines 526 + 623).
6. Visual: load any KB document page locally (`/dashboard/kb/<doc>`), confirm trigger renders as filled gold-gradient pill matching `/dashboard` (empty state) "New conversation" — when there are no conversations yet so the empty-state CTA is visible side-by-side. Toggle into a thread (send a message in the sidebar) and confirm "Continue thread" + indicator dot are still visible and high-contrast.
7. **Both themes.** Toggle theme via the sidebar header pill (Forge ↔ Radiance) and confirm the trigger renders correctly in BOTH. The `from-[#D4B36A] to-[#B8923E]` gradient is theme-static (literal hex) and `text-soleur-text-on-accent` is theme-static by token design (`#1a1612` cross-theme) — so both themes should render visually identical for this trigger. If they differ, the token system is mis-configured and the divergence belongs in a follow-up issue, not this PR.
8. Optional Playwright screenshot diff against `/dashboard` empty state — only if QA flags contrast.

## Risks & Mitigations

- **Risk: contrast regression on the indicator dot.** Earlier framing assumed the dot would become "white on gold" — deepen-pass confirmed the token resolves to `#1a1612` (near-black) cross-theme. The actual risk inverts: a dark dot on a gold gradient may read as a "burn mark" rather than a notification indicator. **Mitigation:** AC2 + AC6 visual check. If the dot reads wrong aesthetically, the next-best fallback is `bg-soleur-bg-base` (renders as the page background — high contrast against gold in both themes). Do NOT use `bg-white` (untokenized literal) or `bg-amber-*` (perpetuates the legacy amber palette the user is leaving behind). This is a single-line follow-up swap if review prefers an alternate semantic.
- **Risk: gradient colors don't match dashboard exactly because of theme drift.** Both buttons hardcode `from-[#D4B36A] to-[#B8923E]` — they will match by construction. **Mitigation:** copy the literal class string verbatim from `dashboard/page.tsx:526`; do not paraphrase. Verified at deepen-time: only TWO existing call sites use the literal-hex gradient (dashboard `:526` and `:623`), and the token system has `--soleur-accent-gradient-start/end` defined but unused — meaning the literal-hex form is the de-facto convention.
- **Risk: padding/sizing makes the trigger oversize next to the smaller outlined Download/Share.** The dashboard "New conversation" empty-state uses `py-3 px-6 text-sm`; the trigger currently uses `py-1.5 px-3 text-xs` and sits in a header row. **Mitigation:** keep current padding/text-size — adopt only the gradient + text-on-accent + hover-opacity. The "source-of-truth" is the gradient styling, not the dashboard's empty-state size. Confirmed at deepen-time by reading `kb-content-header.tsx:38-80`: the row uses `gap-2` with three children at consistent `text-xs py-1.5 px-3` sizing — adopting dashboard's larger padding would break the header rhythm.
- **Risk: light-theme rendering.** `text-soleur-text-on-accent` is a theme token registered in `globals.css:132` as a Tailwind v4 `@theme` variable — utility resolves at build time, no runtime CSS-variable-lookup latency. The token is intentionally `#1a1612` in both Forge (dark) and Radiance (light) themes, so the dark-foreground-on-gold pairing is theme-stable. The `from-[#D4B36A] to-[#B8923E]` literal hex is theme-stable by definition (no theme-awareness). **Mitigation:** none needed; perpetuates current dashboard contract.
- **Risk: snapshot tests elsewhere lock the amber classes.** Verified at deepen-time:
  - `apps/web-platform/test/kb-chat-trigger.test.tsx` — asserts label text + `data-testid="kb-trigger-thread-indicator"` only. No class-string assertions.
  - `apps/web-platform/test/kb-content-header.test.tsx` — `vi.mock`s `KbChatTrigger` to a stub. Doesn't see the real component's classes at all.
  - `apps/web-platform/test/kb-chat-sidebar-a11y.test.tsx` — exercises focus management + role; class-agnostic.
  - `apps/web-platform/test/light-theme-tokenization.test.tsx` — does NOT reference `kb-chat-trigger` or `KbChatTrigger`. Not in scope of this guard.
  **Mitigation:** none needed; the suite is class-agnostic on this surface.
- **Risk: peer learning ambiguity on `text-soleur-text-on-accent` semantics.** The 2026-05-06 token-on-accent learning describes the token as "white in both Forge and Radiance by design." The actual `globals.css` resolves it to `#1a1612` (near-black) in both. The learning's phrasing was approximate; the actual implementation is dark-on-accent. **Mitigation:** This plan trusts the source code (`globals.css`), not the prose summary. Filed as a session-error candidate for the deepen-plan compound capture: peer learning prose drifted from token implementation, caught by deepen-pass cross-reference. (Will be captured by `/soleur:compound` if the divergence persists post-merge.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares threshold `none` with explicit reasoning above — proceed.
- The dashboard source-of-truth has TWO callsites (`page.tsx:526` empty-state and `page.tsx:623` filter-bar) with different padding (`py-3 px-6` vs `py-2 px-4`). The user explicitly named the empty-state variant as the "design source-of-truth", so its gradient/color treatment is what we copy. Padding for THIS trigger keeps its existing header-row dimensions because the trigger lives in a different layout context than either dashboard variant — adopting `py-3 px-6` here would push the trigger out of vertical alignment with the outlined Download/Share neighbors. Documented above as Risk-3.
- Do not introduce a new theme token for the gradient; this would create a third source of truth and is out of scope. The `from-[#D4B36A] to-[#B8923E]` literal already exists at three call sites in the dashboard alone — consolidating them is a larger refactor that should be planned separately if needed.

## Non-Goals

- Theming the dashboard "New conversation" button to a token-based gradient.
- Modifying the Download / Share / KB-sidebar resize-handle styling.
- Adding a class-string drift-guard test for the gradient.
- Refactoring the inline-hex gradient into a Tailwind theme token. (Defer to a separate issue: the token `--soleur-accent-gradient-start/end` exists in `globals.css` but is unused by the dashboard CTA; consolidating both the dashboard's two call sites AND this trigger to the token in a single sweep is the correct shape — piecemeal migration risks a third "tokenized" variant diverging from the literal-hex pair. Per `wg-when-deferring-a-capability-create-a`, this deferral needs a tracking issue if the user accepts the literal-hex form here.)
- Migrating other amber-outline surfaces (e.g., `kb-desktop-layout.tsx` resize-handle active-state). Those are different semantic classes (drag indicator vs primary CTA) and the user explicitly scoped only "the primary action in each row."

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-05-06-feat-kb-chat-trigger-gold-gradient-cta-plan.md
Branch: feat-one-shot-replace-outlined-cta-buttons-with-gradient.
Worktree: .worktrees/feat-one-shot-replace-outlined-cta-buttons-with-gradient/.
One-line: swap KbChatTrigger baseClass from amber-outline to gold-gradient (matches dashboard empty-state "New conversation" CTA); preserve thread-indicator dot, recolor it to text-on-accent.
```
