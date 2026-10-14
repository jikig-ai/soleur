# Brainstorm: Support Chat Interface (UI shell)

**Date:** 2026-06-30
**Branch:** feat-support-interface
**PR:** #5741 (draft)
**Lane:** cross-domain
**Status:** design captured — wireframes pending sign-off

## What We're Building

A **Support** chat interface inside app.soleur.ai where a user talks to "Soleur"
configured purely as **technical support for the app** (not a dev/engineering or
enterprise-leader persona). Its job: help users who are lost or have questions
about how the app works.

**SCOPE NOW = INTERFACE ONLY.** The chatbot backend is being fixed and cannot be
wired up. We build the UI shell; sending a message produces a **canned auto-reply**
(no real LLM / no WebSocket). The send path is deliberately a placeholder so the
surface is usable and honest about its "coming soon" state.

A later **guided tour** (spotlight-circle over a dimmed overlay, step-by-step
explanation of app basics) is explicitly out of scope here but kept in mind for
design coherence — see Non-Goals / follow-up.

## Decisions (operator-confirmed)

| Decision | Choice | Notes |
|---|---|---|
| Entry point | **Floating help bubble** (bottom-right `?`/chat button) | Persistent on authenticated pages; Intercom/Crisp pattern; no nav slot consumed |
| Surface | **Right-side slide-over panel** | App stays visible (dimmed) behind; user keeps context |
| Backend-off behavior | **Canned auto-reply** | Input works; on send, user msg appears + fixed Soleur support reply; no real backend |
| Persona | **Technical support**, not leader/dev | Own support identity + avatar; warm helpful tone; not `LeaderAvatar` leader colors |
| Gating | New `support` runtime flag | `useOptionalFeatureFlag("support")`, fail-closed |
| Visual design | Wireframes in `.pen` (ux-design-lead) — **operator-approved 2026-06-30** | `knowledge-base/product/design/support/support-chat-interface.pen` + `screenshots/01-04-*.png` |

## Why This Approach

- **Floating bubble + slide-over** is the lowest-friction, most-discoverable help
  pattern and keeps the user in-context — ideal for "I'm lost on this page."
- **Lightweight dedicated shell, not `ChatSurface`.** The existing
  `components/chat/chat-surface.tsx` is hard-wired to `useWebSocket`
  (`lib/ws-client.ts`) — reusing it would pull the entire live-backend machinery
  into a surface that has no backend. Instead, **reuse the visual building blocks**
  (message-bubble styling, chat-input look, `soleur-*` tokens, `GoldButton`) in a
  small purpose-built support component with local React state and a canned-reply
  responder. Clean swap-in point for the real backend later.
- **Canned auto-reply over disabled input**: feels alive, sets the "coming soon"
  expectation, and lets us ship/test the full interaction shell now.

## Key Implementation Anchors (from repo research)

- Mount global chrome (bubble + panel) in `app/(dashboard)/layout.tsx` (where
  `CommandPalette`, `HelpOverlay`, banners already mount).
- No floating overlay drawer exists — `components/ui/sheet.tsx` is a desktop
  push-column / mobile bottom-sheet **without** a backdrop. A true floating
  slide-over (portal + dim backdrop + focus trap + Escape) is **net-new** but small.
- Reuse styling references: `components/chat/message-bubble.tsx`,
  `components/chat/chat-input.tsx`, `components/ui/gold-button.tsx`,
  tokens in `app/globals.css` (`soleur-bg-*`, `soleur-border-*`, `soleur-text-*`,
  `soleur-accent-gold-*`).
- Persisted "seen/dismissed" state pattern: `hooks/use-onboarding.ts`
  (fire-and-forget `updateUserField`) — relevant for first-open nudge later.
- Gating pattern: `lib/feature-flags/server.ts` `RUNTIME_FLAGS` +
  `components/feature-flags/provider.tsx` `useOptionalFeatureFlag`.

## Interface States to Design

1. **Closed** — floating `?`/chat bubble pinned bottom-right.
2. **Open / empty** — slide-over panel header ("Support"), support persona
   intro/empty state (avatar + greeting + a few suggested starter questions),
   composer at bottom, subtle "coming soon / interface preview" affordance.
3. **Conversation** — user message bubble + Soleur support canned-reply bubble,
   support avatar, timestamps optional.
4. **Composer** — active text input + send button (`GoldButton`), within token theme.

## Non-Goals

- No real LLM / WebSocket wiring (backend being fixed).
- No conversation persistence across reloads (local state only for the shell;
  revisit when backend lands).
- No guided onboarding tour — **deferred** to a follow-up (spotlight-circle over
  dimmed overlay, step path). File as separate issue.
- No mobile-specific redesign beyond responsive panel (reuse bottom-sheet idiom
  if needed).

## Open Questions

- Exact canned-reply copy + suggested starter questions (draft in spec; operator
  can tweak).
- Should the bubble show an unread/"new" affordance on first run? (lean: simple
  nudge later, not in v1 shell.)
- Final swap-in contract for the real backend (out of scope; note seam in spec).

## User-Brand Impact

- **Artifact:** the Support slide-over chat surface + floating launcher in
  app.soleur.ai.
- **Vector:** a support surface that silently appears "live" but drops user
  messages (no backend) would erode trust at the exact moment a confused user
  reaches for help; honesty of the "coming soon" framing is the brand-load-bearing
  detail.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Product, Engineering, Legal (triad, USER_BRAND_CRITICAL auto per #5175)

### Product
**Summary:** Floating-bubble + slide-over is the right discoverability/low-friction
help pattern; the canned-reply must be unambiguously "coming soon" so users aren't
misled into expecting live answers. Pairs coherently with the later guided tour.

### Engineering
**Summary:** Do not reuse the WS-bound `ChatSurface`; build a lightweight support
shell reusing visual primitives + tokens, gated behind a `support` flag, with a
clean seam for the future backend. Floating overlay is net-new but small.

### Legal
**Summary:** Interface-only shell with no message transmission/storage and no PII
processing in v1 — minimal exposure. Revisit (data handling, retention, vendor
sub-processors) when the real backend is wired.
