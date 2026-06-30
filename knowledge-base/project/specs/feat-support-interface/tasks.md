---
name: feat-support-interface-tasks
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-30-feat-support-chat-interface-plan.md
spec: knowledge-base/project/specs/feat-support-interface/spec.md
---

# Tasks: Support Chat Interface (UI shell)

All paths under `apps/web-platform/`.

## Phase 1 — Flag wiring (default OFF)

- [x] 1.1 Add `"support": "FLAG_SUPPORT"` to `RUNTIME_FLAGS` in `lib/feature-flags/server.ts`
- [x] 1.2 Add `FLAG_SUPPORT=0` (with comment) to `.env.example`

## Phase 2 — Persona + canned responder (the seam)

- [x] 2.1 `components/support/support-persona.ts` — name ("Soleur Support"), greeting,
      3 starter questions, coming-soon note text
- [x] 2.2 `components/support/canned-responder.ts` — `getSupportReply(msg, chipKey?)`:
      chip-keyed lookup (3 answers) + generic fallback; each reply restates
      "coming soon" + KB/docs escape-hatch link. Documented as the sole backend seam.

## Phase 3 — Support primitives

- [x] 3.1 `components/support/support-avatar.tsx` — life-buoy glyph, gold gradient, sm/md
- [x] 3.2 `components/support/support-message.tsx` — user vs support bubble (soleur-* tokens,
      mirrors `message-bubble.tsx`); `PREVIEW` badge on every support reply
- [x] 3.3 `components/support/support-composer.tsx` — textarea + gold send; Enter-to-send,
      Shift+Enter newline; disabled+no-op on empty/whitespace (trim); max-height + internal
      scroll + ~2000 char cap; footnote "responses are previews for now"
- [x] 3.4 `components/support/support-conversation.tsx` — empty state (greeting + 3 chips +
      coming-soon note) → send path; message list + auto-scroll; chips dismiss after first
      send; `aria-live="polite"` region for new replies
- [x] 3.5 `components/support/support-panel.tsx` — portal + dim backdrop + focus trap +
      Escape/backdrop close + reduced-motion slide/fade; `role="dialog"` + `aria-modal` +
      labelled header (title + "Preview · live chat coming soon" + X); mobile bottom-sheet
      (large fixed height, keyboard-safe composer, safe-area inset); focus→composer on open;
      focus returns to launcher on close
- [x] 3.6 `hooks/use-support-chat.ts` — local state (`messages`, `isOpen`, `send`, `open`,
      `close`); thread retained across close/reopen within session, reset on reload; no network

## Phase 4 — Mount + gate

- [x] 4.1 `components/support/support-launcher.tsx` — `useOptionalFeatureFlag("support")`;
      null when OFF; floating bubble (chat glyph, gold) bottom-right; hides while panel open;
      unmounts cleanly if flag flips OFF
- [x] 4.2 Mount `<SupportLauncher />` in `app/(dashboard)/layout.tsx` next to
      `<CommandPalette />` / `<HelpOverlay />` (~L570)

## Phase 5 — Tests + verification

- [x] 5.1 `test/components/support/support-launcher.test.tsx` — flag OFF → null; ON → bubble;
      click → panel open; flag-flip OFF unmounts
- [x] 5.2 `test/components/support/support-panel.test.tsx` — open shows empty state (greeting
      + 3 chips + note); Esc/backdrop/X close + focus returns; send (typed + chip) → user
      bubble + canned PREVIEW reply; assert NO fetch/WS call; empty send disabled
- [x] 5.3 `test/components/support/support-composer.test.tsx` — Enter/Shift+Enter, trim,
      disabled-on-empty, char cap
- [x] 5.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
- [x] 5.5 `cd apps/web-platform && ./node_modules/.bin/vitest run test/components/support/` green
- [x] 5.6 `grep -rnE '#[0-9a-fA-F]{3,6}' apps/web-platform/components/support/` returns nothing
- [ ] 5.7 Capture a light-theme screenshot of the open panel (closes light-theme AC) — deferred to flag-on QA

## Post-merge (operator / automatable)

- [ ] P.1 `soleur:flag-create support` — provision Flagsmith + Doppler dev/prd, **default OFF** (post-merge)
