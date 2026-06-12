---
feature: shared-doc-waitlist-dismiss
date: 2026-06-12
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-06-12-shared-doc-waitlist-dismiss-brainstorm.md
wireframe: knowledge-base/product/design/shared-document/cta-banner-visibility-states.pen
related_prs: ["#5035", "#5075", "#5076", "#5153"]
---

# Spec: Remember "already joined" on the shared-doc waitlist banner

## Problem Statement

On the public shared-document page, the CTA waitlist banner
(`apps/web-platform/components/shared/cta-banner.tsx`) keeps its expanded/collapsed
and success states in-memory (`useState`) only. A reload restores the full empty
form even immediately after a successful join, so a visitor who already joined the
waitlist from that browser is re-prompted — the system appears to "forget" them.

The visitor is anonymous on a public page and the `/api/waitlist` route
deliberately returns an identical `{ok:true}` for new vs. already-subscribed
emails (anti-enumeration). So the only viable "remember" signal is a per-browser
client-side marker written after a confirmed join.

## Goals

- A visitor who has joined the waitlist from a given browser is **not shown the
  banner at all** on subsequent visits/reloads in that browser.
- Immediate in-session feedback ("You're on the list ✓") is preserved right after
  a successful join.
- Zero new server surface; zero new PII at rest; no enumeration vector.

## Non-Goals

- Cross-device / cross-browser / incognito memory (would require a server
  existence-check — CLO-prohibited; idempotent re-submit covers the edge).
- A distinct "you're already subscribed" message (preserves anti-enumeration).
- Persisting a manual collapse/dismiss (stays in-memory per the #5075 decision).
- Any change to `/api/waitlist` or `waitlist.ts`.

## Functional Requirements

- **FR1** — On mount, `CtaBanner` reads `localStorage["soleur:shared:waitlist-joined"]`.
  If present, the component renders `null` (no banner, no re-expand affordance).
  Wireframe **State C**.
- **FR2** — When a submit resolves to `status === "success"` (covers both a new
  join and Buttondown already-subscribed, both `{ok:true}`), the component writes
  `localStorage["soleur:shared:waitlist-joined"] = "1"`. Wireframe transition A→B.
- **FR3** — The flag is **never** written on `status === "error"`, on a network
  failure, on `status === "submitting"`, or on a banner toggle/collapse. On error
  the banner stays in the expanded form state with the form re-enabled (State A).
- **FR4** — In the same session as the successful join, the existing in-session
  "You're on the list ✓ — check your inbox to confirm." confirmation is unchanged
  (Wireframe **State B**); the hide-entirely behavior takes effect on the next
  mount/reload.
- **FR5** — Memory is permanent (no expiry). Only clearing browser storage resets it.

## Technical Requirements

- **TR1** — Read storage in a lazy `useState` initializer
  (`useState(() => readJoinedFlag())`), not a `useEffect`. The banner is rendered
  as `{data && <CtaBanner />}` on a `"use client"` page
  (`app/shared/[token]/page.tsx:150`) that fetches `data` client-side, so the
  banner is never in server-rendered HTML — no hydration mismatch and no
  `mounted`-gate flash. Re-verify this render-after-fetch flow still holds at
  build time.
- **TR2** — All `localStorage` access (read and write) is wrapped in try/catch.
  On any failure (private mode, storage disabled, quota), fall back to today's
  in-memory behavior (banner shows) — never throw.
- **TR3** — Store a boolean marker (`"1"`) only. Never persist the entered email
  or any identifier.
- **TR4** — Key is `soleur:shared:waitlist-joined`, distinct from the legacy
  `soleur:shared:cta-dismissed` key asserted non-persistent by
  `test/shared-cta-banner-close.test.tsx`. Do not reuse or write that legacy key.
- **TR5** — No cookie; `localStorage` only (keeps the marker off every HTTP
  request and out of the cookie-consent surface). Functional/strictly-necessary
  storage — no consent banner, no Art. 30 change.

## Test Requirements

- **TST1** — Seeding `localStorage["soleur:shared:waitlist-joined"]="1"` before
  mount renders no banner (query for the email input returns null). Seed before
  mount; do **not** rely on remount carrying in-component state.
- **TST2** — A successful submit (mock `/api/waitlist` → `{ok:true}`) writes the
  flag; an errored submit (non-2xx / fetch reject) does **not** write it
  (`vi.spyOn(Storage.prototype, "setItem")`).
- **TST3** — Existing `shared-cta-banner-close.test.tsx` stays green: toggling
  still writes nothing, and the legacy `soleur:shared:cta-dismissed` key is still
  ignored.
- **TST4** — Clear `localStorage` in both `beforeEach` and `afterEach` (jsdom/
  happy-dom does not reset storage between tests).

## User-Brand Impact

- **Threshold:** `single-user incident`.
- **Worst single-user outcome:** a flag written on a *failed* signup silently
  suppresses the CTA so a genuine prospect never joins. Mitigated by FR3 (write
  only on confirmed success).
- **PII:** never persist the email (TR3) — shared docs open on shared machines.
- **Enumeration:** client-only; no server existence-check (CLO-prohibited).
