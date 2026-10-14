---
name: feat-support-interface
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-06-30-support-interface-brainstorm.md
branch: feat-support-interface
pr: 5741
---

# Feature: Support Chat Interface (UI shell)

## Problem Statement

Users who get lost or have questions about app.soleur.ai have no in-app way to ask
for help — there is no support surface, no "?" affordance, no contextual guidance.
The eventual answer is a "Soleur as technical support" chatbot, but that backend is
currently being fixed and cannot be wired up. We need to ship the **support
interface shell** now so the surface exists, is discoverable, and is usable in a
canned/preview mode, with a clean seam to drop the real backend in later.

## Goals

- Add a persistent, discoverable **floating help bubble** on authenticated pages.
- Open a **right-side slide-over panel** chat surface where the user talks to a
  **technical-support** Soleur persona (not a dev/leader persona).
- Make it work interface-only: sending a message shows the user's message and a
  **canned support auto-reply** — no LLM, no WebSocket, no persistence.
- Be honest: the surface clearly signals "interface preview / live chat coming soon"
  so a confused user is never misled into expecting a real answer.
- Gate the whole feature behind a `support` runtime flag (fail-closed).
- Leave a clean swap-in seam for the real backend.

## Non-Goals

- Real LLM / WebSocket wiring, conversation persistence, ticketing, or message
  storage — deferred until the backend is fixed.
- The **guided onboarding tour** (spotlight-circle over dimmed overlay, step path) —
  separate follow-up issue; designed for coherence but not built here.
- PII processing / data-retention / vendor sub-processor concerns (none in the shell;
  revisit when backend lands).
- Reusing the WS-bound `ChatSurface` component (deliberately avoided — see TR1).

## Functional Requirements

### FR1: Floating support launcher
A circular gold-accented help bubble (chat glyph) pinned bottom-right on
authenticated `(dashboard)` pages, gated behind the `support` flag. Toggles the
support panel open/closed; accessible (button, aria-label, keyboard-focusable).
Wireframe: `knowledge-base/product/design/support/screenshots/01-support-closed-floating-bubble.png`.

### FR2: Slide-over support panel
A right-side slide-over (~380–420px desktop; bottom-sheet feel on mobile) that
animates in over a mid-opacity dim backdrop; app stays visible behind. Header shows
"Support" + a subtitle ("Preview · live chat coming soon") + close (X); Escape and
backdrop-click close it; focus is trapped while open. This floating overlay is
net-new (the existing `Sheet` is a push-column without backdrop).
Wireframe: `02-support-panel-empty-state.png`.

### FR3: Support persona + empty state
A dedicated **technical-support** identity: support avatar (life-buoy glyph on gold
gradient, visually distinct from leader/dev `LeaderAvatar`), a warm greeting, and
3 suggested starter-question chips (e.g. "How do I create a routine?", "Where's my
knowledge base?", "What is the Workstream?"). Tapping a chip prefills/sends it.
Includes a gold "interface preview / coming soon" note.

### FR4: Canned conversation behavior
On send (or chip tap): the user's (trimmed) message renders as a user bubble, then a
canned Soleur Support reply renders as an assistant bubble (support avatar + name +
`PREVIEW` badge). No network call. **Replies are chip-keyed** (resolves spec-flow
gap #1 — the wireframe shows a topic-specific answer): a small lookup maps each of
the 3 starter chips to its own canned answer, with a generic friendly fallback for
free-text input. Every reply restates "live support is coming soon" and includes one
real escape hatch (a link to the knowledge base / docs) so a stuck user is never
dead-ended. Conversation lives in local React state, **retained across close/reopen
within the page session** but reset on full reload (not persisted).
Wireframe: `03-support-conversation-canned-reply.png`.

### FR5: Composer
Text input + gold send button (`GoldButton` look). Send disabled when empty,
enabled (gold) when typed; Enter-to-send, Shift+Enter newline. A composer footnote
reiterates "responses are previews for now."
Wireframe: `04-support-composer-send-states.png`.

## Technical Requirements

### TR1: Lightweight dedicated shell (do NOT reuse ChatSurface)
Build a purpose-built support component tree (e.g.
`components/support/support-launcher.tsx`, `support-panel.tsx`, plus support-styled
bubbles/composer). Reuse **visual primitives only** — `message-bubble.tsx` styling,
`chat-input.tsx` look, `components/ui/gold-button.tsx`, `card.tsx`, and `soleur-*`
tokens from `app/globals.css`. Do NOT pull in `useWebSocket` / `lib/ws-client.ts`.
Encapsulate the canned responder behind a single function so the real backend swaps
in at one seam.

### TR2: Mount point
Mount the launcher + panel in `app/(dashboard)/layout.tsx` alongside existing global
chrome (`CommandPalette`, `HelpOverlay`, banners).

### TR3: Feature flag
Add `"support": "FLAG_SUPPORT"` to `RUNTIME_FLAGS` in
`lib/feature-flags/server.ts`; gate UI with `useOptionalFeatureFlag("support")`.
Provision via the `soleur:flag-create` tooling (Flagsmith + server.ts + .env.example
+ Doppler dev/prd, default OFF) as a separate operator step.

### TR4: Theming + a11y
All colors via `soleur-*` tokens (never raw hex); works in dark (default) and light
themes. Panel is keyboard-navigable, focus-trapped, Escape-closable, with proper
aria roles/labels. Respects reduced-motion for the slide animation.

### TR5: Tokens / styling fidelity
Match existing idioms: cards `rounded-xl border border-soleur-border-default`,
surfaces step `bg-base → surface-1 → surface-2`, gold accents for CTAs/active.

## Interaction Details (spec-flow resolved)

- **Reply mapping (#1):** chip→reply lookup (3 keyed answers) + generic fallback; every
  reply restates "coming soon" + a KB/docs escape-hatch link.
- **Launcher while open (#2):** the floating bubble hides while the panel is open; the
  header X (plus Escape / backdrop) is the close affordance (matches wireframes 02/03).
- **Empty/whitespace send (#3):** input is trimmed; Enter on empty/whitespace is a
  no-op; send button disabled until non-empty. No blank user bubble can render.
- **Rapid send (#4):** composer briefly disabled during the (synchronous) reply tick;
  starter chips are empty-state-only and dismiss after the first send (no chip spam).
- **Motion (#5):** panel slide, backdrop fade, and bubble appearance all honor
  `prefers-reduced-motion`. Reply is rendered promptly (no deceptive fake-typing delay).
- **Focus / a11y (#6):** on open, focus moves to the composer; Tab order =
  chips → composer → send → X; focus returns to the launcher on every close path
  (Esc / backdrop / X); new reply bubbles announced via an `aria-live="polite"` region;
  panel has `role="dialog"` + `aria-modal` + labelled header.
- **Mobile (#7):** bottom-sheet covers a large fixed fraction of viewport height,
  composer stays above the on-screen keyboard, backdrop tap closes, launcher clears the
  OS safe-area inset.
- **Scroll / growth (#8):** conversation auto-scrolls to latest; chips do not return
  once a conversation starts; thread retained across close/reopen within the session.
- **Input ceiling (#9):** composer max height with internal scroll; soft character cap
  (~2000) to keep the mobile sheet from being overrun.
- **Light theme (#12):** capture a light-mode screenshot of the open panel during build
  to close the light-theme AC (backdrop opacity + gold contrast differ in light mode).
- **Flag-flip mid-session (#13):** if the flag re-evaluates OFF, the launcher/panel
  unmount cleanly without trapping focus in a detached node.

## Acceptance Criteria

- With `support` flag ON, an authenticated user sees the floating bubble; clicking
  opens the slide-over over a dimmed app.
- Empty state shows the support persona, greeting, 3 starter chips, and the
  "coming soon" note.
- Sending a message (typed or via chip) renders the user message + a canned support
  reply with a `PREVIEW` badge; no network request is made.
- Escape / backdrop / X all close the panel; focus returns to the launcher.
- With the flag OFF, nothing renders (fail-closed).
- Dark + light themes both render correctly using `soleur-*` tokens; no raw hex.

## Design Artifacts

- Wireframes (operator-approved 2026-06-30):
  `knowledge-base/product/design/support/support-chat-interface.pen`
  + `screenshots/01-04-*.png`.

## Follow-ups (deferred)

- **Guided onboarding tour** — spotlight-circle over dimmed overlay, step-by-step
  walkthrough of app basics. Build the tour engine on `hooks/use-onboarding.ts`
  persisted-flag pattern and the `help-overlay.tsx` overlay scaffolding. Separate issue.
- **Real support backend** — wire the canned-responder seam (TR1) to the live
  support-configured Soleur once it's fixed; revisit data-handling/retention/CLO.
