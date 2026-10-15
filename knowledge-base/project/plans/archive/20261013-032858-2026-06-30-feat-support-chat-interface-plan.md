---
name: 2026-06-30-feat-support-chat-interface-plan
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5742
branch: feat-support-interface
worktree: .worktrees/feat-support-interface
pr: 5741
brainstorm: knowledge-base/project/brainstorms/2026-06-30-support-interface-brainstorm.md
spec: knowledge-base/project/specs/feat-support-interface/spec.md
---

# Plan: Support Chat Interface (UI shell)

✨ **feature** · interface-only · backend deferred

## Overview

Build the **Support chat interface shell** for app.soleur.ai: a flag-gated floating
help bubble (bottom-right) that opens a right-side slide-over panel where the user
chats with a **technical-support** Soleur persona. Interface only — sending a
message renders the user's bubble plus a **canned support auto-reply** (no LLM, no
WebSocket, no persistence), with honest "preview · coming soon" framing and a single
swap-in seam for the real backend when it's fixed.

Design is signed off (wireframes approved 2026-06-30,
`knowledge-base/product/design/support/`). This plan is the HOW.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| Reuse visual primitives, NOT `ChatSurface` | `ChatSurface` is hard-wired to `useWebSocket(conversationId)` (`lib/ws-client.ts`); cannot mount without a live backend | Build a dedicated `components/support/*` tree; reuse only styling/tokens |
| Slide-over needs net-new overlay | No floating overlay primitive exists. `components/ui/sheet.tsx` is a desktop push-column / mobile bottom-sheet **without backdrop or focus trap** | Build a small portal + backdrop + focus-trap panel; may reuse `Sheet`'s mobile bottom-sheet idiom |
| Gate behind `support` flag | `RUNTIME_FLAGS` in `lib/feature-flags/server.ts` (e.g. `command-palette` → `FLAG_COMMAND_PALETTE`); consumed via `useOptionalFeatureFlag` | Add `"support": "FLAG_SUPPORT"`; gate via `useOptionalFeatureFlag("support")` |
| Mount globally | `app/(dashboard)/layout.tsx` mounts `<CommandPalette />` + `<HelpOverlay />` at ~L570, after `</main>` | Mount `<SupportLauncher />` adjacent to those |
| Support persona ≠ leader | `LeaderAvatar` (`components/leader-avatar.tsx`) is leader/dev-colored | Dedicated support identity/avatar (life-buoy glyph, gold) in `components/support/` |
| Tokens, no raw hex | `app/globals.css` exposes `soleur-*` tokens; `GoldButton` uses `GOLD_GRADIENT` | All styling via `soleur-*` utilities |

No spec fiction detected — all reuse anchors exist on `main`.

## Files to Create

All under `apps/web-platform/`:

- `components/support/support-launcher.tsx` — flag-gated floating bubble; owns
  open/closed state; renders the panel. Mounted globally.
- `components/support/support-panel.tsx` — slide-over: React portal + dim backdrop +
  focus trap + Escape/backdrop-click close + `prefers-reduced-motion` aware slide;
  header ("Support" + subtitle + close X); body = conversation; footer = composer.
- `components/support/support-conversation.tsx` — message list (empty state with
  persona greeting + 3 starter chips; or rendered messages), auto-scroll to latest.
- `components/support/support-message.tsx` — user vs support bubble styling
  (mirrors `message-bubble.tsx` token usage) + support avatar + `PREVIEW` badge on
  support replies.
- `components/support/support-composer.tsx` — textarea + gold send button
  (`GoldButton` look); Enter-to-send, Shift+Enter newline; disabled-when-empty;
  footnote "responses are previews for now".
- `components/support/support-avatar.tsx` — support persona avatar (life-buoy glyph,
  gold gradient), sizes sm/md.
- `components/support/support-persona.ts` — constants: name, greeting, 3 starter
  questions, the canned reply copy, the "coming soon" note text.
- `components/support/canned-responder.ts` — **the single backend seam**:
  `getSupportReply(userMessage: string, chipKey?: string): Promise<string> | string`.
  Chip-keyed lookup (3 keyed answers) + generic free-text fallback; every reply
  restates "coming soon" + a KB/docs escape-hatch link. The only file the real backend swaps.
- `hooks/use-support-chat.ts` — local React state: `messages`, `isOpen`, `send()`,
  `open()`, `close()`. No network. (Co-locate in `components/support/` if simpler.)

Tests (paths must match `vitest.config.ts` `include:` — `test/**/*.test.tsx`):

- `test/components/support/support-launcher.test.tsx`
- `test/components/support/support-panel.test.tsx`
- `test/components/support/support-composer.test.tsx`

## Files to Edit

- `apps/web-platform/lib/feature-flags/server.ts` — add `"support": "FLAG_SUPPORT"`
  to `RUNTIME_FLAGS` (default fail-closed mirror).
- `apps/web-platform/app/(dashboard)/layout.tsx` — import + mount `<SupportLauncher />`
  adjacent to `<CommandPalette />` / `<HelpOverlay />` (~L570), gated internally by
  `useOptionalFeatureFlag("support")`.
- `apps/web-platform/.env.example` — add `FLAG_SUPPORT=0` with a comment.

## Implementation Phases

### Phase 1 — Flag wiring (RED-light off by default)
1. Add `"support": "FLAG_SUPPORT"` to `RUNTIME_FLAGS` in `server.ts`.
2. Add `FLAG_SUPPORT=0` to `.env.example`.
3. (Provisioning of Flagsmith + Doppler dev/prd is a **separate `soleur:flag-create`
   step**, not raw `doppler secrets set` — see Post-merge AC. Default OFF in both.)

### Phase 2 — Persona + canned responder (the seam)
1. `support-persona.ts`: name ("Soleur Support"), greeting, 3 starter questions
   (from spec/wireframes), canned reply copy, coming-soon note.
2. `canned-responder.ts`: `getSupportReply()` returns the canned reply; documented as
   the sole real-backend swap-in point.

### Phase 3 — Support primitives
1. `support-avatar.tsx`, `support-message.tsx` (token-faithful bubbles + PREVIEW badge).
2. `support-composer.tsx` (Enter/Shift+Enter, disabled-when-empty, gold send, footnote).
3. `support-conversation.tsx` (empty state + chips → send; message list + auto-scroll).
4. `support-panel.tsx` (portal + backdrop + focus trap + Escape + reduced-motion;
   header/body/footer; mobile bottom-sheet behavior).
5. `use-support-chat.ts` (local state, `send` appends user msg then awaits
   `getSupportReply` and appends support reply).

### Phase 4 — Mount + gate
1. `support-launcher.tsx`: `useOptionalFeatureFlag("support")` → render nothing if
   off; else floating bubble that toggles the panel.
2. Mount `<SupportLauncher />` in `layout.tsx` next to `<CommandPalette />`.

### Phase 5 — Tests + verification
1. Component tests (see Test Scenarios).
2. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
3. `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/support/`.
4. Manual theme check: dark + light render via `soleur-*` tokens (no raw hex grep:
   `grep -rnE '#[0-9a-fA-F]{3,6}' components/support/` returns nothing).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] With `support` flag ON, the floating bubble renders bottom-right; OFF → nothing
      renders (`useOptionalFeatureFlag` fail-closed). (component test)
- [ ] Clicking the bubble opens the slide-over over a dim backdrop; empty state shows
      persona greeting + 3 starter chips + composer + "coming soon" note.
- [ ] Sending a typed message OR tapping a chip renders a user bubble then a canned
      support reply with a `PREVIEW` badge; **no network request is made** (assert no
      `fetch`/WS call in test).
- [ ] Empty/whitespace-only message cannot be sent (send disabled).
- [ ] Escape, backdrop click, and X all close the panel; focus returns to the launcher.
- [ ] `grep -rnE '#[0-9a-fA-F]{3,6}' apps/web-platform/components/support/` returns
      nothing (tokens only).
- [ ] `tsc --noEmit` clean; `vitest run test/components/support/` green.

### Post-merge (operator / automatable)
- [ ] Provision the `support` flag via `soleur:flag-create support` (Flagsmith +
      `server.ts` already done here + `.env.example` already done here + Doppler
      dev/prd), **default OFF** in dev and prd. (Automatable via the flag-create skill.)

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carry-forward from brainstorm
`## Domain Assessments`)

### Engineering
**Status:** reviewed (carry-forward)
**Assessment:** Do not reuse the WS-bound `ChatSurface`; build a lightweight support
shell reusing visual primitives + tokens, gated behind a `support` flag, with a clean
seam (`canned-responder.ts`) for the future backend. Floating overlay is net-new but small.

### Legal
**Status:** reviewed (carry-forward)
**Assessment:** Interface-only shell with no message transmission/storage and no PII
processing in v1 — minimal exposure. Revisit (data handling, retention, vendor
sub-processors) when the real backend is wired (#5743 sibling / backend follow-up).

### Product/UX Gate
**Tier:** blocking (new chat interface — mechanical UI-surface override)
**Decision:** reviewed
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55 — wireframes committed &
operator-approved), spec-flow-analyzer (this plan)
**Skipped specialists:** none
**Pencil available:** yes (`knowledge-base/product/design/support/support-chat-interface.pen`)

#### Findings (SpecFlow — resolved)
Wireframes approved 2026-06-30. spec-flow-analyzer ran on the flows; all gaps resolved
into spec `## Interaction Details`:
- HIGH #1 fixed-vs-keyed reply → **chip-keyed** lookup + generic fallback (matches
  wireframe); #2 launcher hides while panel open; #3 trim + Enter-on-empty no-op;
  #4 composer disabled during reply tick + chips dismiss after first send.
- MED #5 reduced-motion on slide/fade/bubble; #6 focus→composer, tab order, focus
  return on all close paths, `aria-live` for replies; #7 mobile sheet height/keyboard/
  safe-area; #8 auto-scroll + thread retained across close/reopen (reset on reload);
  #9 composer max-height + ~2000 char cap.
- LOW #10 PREVIEW badge persists on every reply + copy restates coming-soon;
  #11 escape-hatch link in reply; #12 capture light-theme screenshot in build;
  #13 flag-flip OFF unmounts cleanly.

## User-Brand Impact

**If this lands broken, the user experiences:** a help affordance that fails to open,
or a support panel that silently drops their question — failing them at the exact
moment they're lost.
**If this leaks, the user's data is exposed via:** N/A in v1 — the shell transmits and
stores nothing (canned reply, local state only). Data exposure becomes in-scope only
when the real backend is wired.
**Brand-survival threshold:** single-user incident.

> CPO sign-off carried forward from brainstorm (USER_BRAND_CRITICAL triad). The diff
> will be checked by `user-impact-reviewer` at PR review.

## Observability

Client-only UI shell — no new server route, Inngest function, or cron; no new
server-side error path.

```yaml
liveness_signal:    none required — static client surface; no scheduled/background work
error_reporting:    client render errors surface via the existing browser error boundary / Sentry browser SDK already wired in app/layout (no new server destination)
fail_loud:          n/a (no silent server fallback introduced)
failure_modes:
  - mode: panel fails to open on bubble click
    detection: component test (open → panel visible)
    alert_route: CI (vitest) — not a runtime alert (no backend)
  - mode: flag-gating regression (renders when OFF)
    detection: component test (flag OFF → null)
    alert_route: CI (vitest)
logs:               none added (no server surface)
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/components/support/
  expected_output: all support component tests pass
```

## Open Code-Review Overlap

None — no open `code-review` issues touch `components/support/**` (new directory),
`lib/feature-flags/server.ts` flag-add, or the `layout.tsx` global-chrome mount block.

## Architecture Decision (ADR/C4)

**No architectural decision.** Checked all three `.c4` files
(`knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`):
- External human actors: only `founder` interacts with `webapp`/`dashboard` — no new actor.
- External systems: none new — the shell is canned/local (no backend edge). The future
  real backend would route through the already-modeled `webapp → engine` WebSocket edge.
- Containers/data-stores: the `Dashboard` container already covers "Conversation UI" —
  the support shell is part of it; no new container or store.
- Access relationships: `founder -> dashboard` already exists — unchanged.
No element to add, no description falsified → no C4 edit, no ADR. (The "lightweight
shell vs ChatSurface" choice is a local implementation decision, not a system-level one.)

## Test Scenarios

1. Flag OFF → `<SupportLauncher />` renders `null`.
2. Flag ON → bubble visible; click → panel open, backdrop present, focus moves into panel.
3. Empty state → greeting + 3 chips + composer + coming-soon note present.
4. Type "hello" + send → user bubble "hello" then a support reply bubble with `PREVIEW`
   badge; spy asserts no `fetch`/WebSocket call.
5. Tap a starter chip → same send path fires with the chip's text.
6. Empty/whitespace send → send button disabled; no message added.
7. Rapid repeated sends → each pair appends in order; no dropped/duplicated bubbles.
8. Very long input → composer grows/scrolls; no layout break.
9. Escape / backdrop / X → panel closes; focus returns to the bubble.
10. `prefers-reduced-motion` → slide animation suppressed (no transition).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty/`TBD` fails `deepen-plan`
  Phase 4.6 — this one is filled (single-user incident, carry-forward).
- **Test paths must match `vitest.config.ts` `include:`** (`test/**/*.test.tsx`) — a
  co-located `components/support/*.test.tsx` is silently never run. Put tests under
  `test/components/support/`.
- **Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`**, NOT
  `npm run -w … typecheck` (no root `workspaces` field).
- The floating overlay is net-new — must hand-roll portal + backdrop + focus trap +
  Escape; do NOT assume `components/ui/sheet.tsx` provides a backdrop (it does not).
- Keep `canned-responder.ts` as the ONLY backend touch point so the real backend swaps
  at one seam — do not scatter canned copy across components.
- Provision `FLAG_SUPPORT` default **OFF** in BOTH dev and prd (fail-closed); never
  ship it ON before the backend exists, or the "coming soon" honesty breaks.
