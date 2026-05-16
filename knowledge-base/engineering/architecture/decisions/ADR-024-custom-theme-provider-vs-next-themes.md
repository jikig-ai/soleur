---
adr: ADR-024
title: Custom Theme Provider over `next-themes`
status: active
date: 2026-05-06
related_pr: 3271
related_issue: 3232
---

# ADR-024: Custom Theme Provider over `next-themes`

## Context

PR #3271 (issue #3232) ships a Light/Dark/System theme toggle for the dashboard. Two implementation paths were on the table:

1. **`next-themes`** — the de-facto-standard React/Next.js theming library (~14k weekly downloads, MIT-licensed). Battle-tested no-FOUC handling via injected inline script, supports the same three-mode contract (light/dark/system) we want, integrates with Next.js App Router, well-documented.
2. **Custom `<ThemeProvider>`** — a hand-rolled provider in `apps/web-platform/components/theme/` consisting of (a) a no-FOUC inline script (`no-fouc-script.tsx`), (b) a React context provider with a lazy `useState` initializer reading `localStorage`, (c) a cross-tab `storage` event listener, (d) a dynamic `<meta name="theme-color">` updater, (e) a 3-segment toggle.

Both options ship the same user-visible behaviour. The decision turns on infrastructure fit, not feature parity.

## Decision

We ship the **custom `<ThemeProvider>`**. `next-themes` is rejected for now.

## Consequences

### Why custom

- **First-class integration with our Sentry-via-`reportSilentFallback` pattern.** AGENTS.md rule `cq-silent-fallback-must-mirror-to-sentry` requires every silent-fallback path (storage event with garbage value, `localStorage.setItem` quota error, etc.) to mirror to Sentry. With `next-themes`, those failure paths sit inside library code we cannot instrument without forking. Our custom provider wires `reportSilentFallback` directly at every degraded branch.
- **Exact surface, no library bloat.** We need three modes and storage-event sync. `next-themes` ships additional surface (forced theme override on a per-page basis, theme cookie support, value/attribute customization, custom storage-key mapping) we do not consume. Bundle delta avoided is small (~3 KB gzipped) but every dependency is also a supply-chain entry and a CSP-script-source decision.
- **Direct alignment with our `data-theme` + `@custom-variant dark` contract.** Tailwind v4 requires explicit `@custom-variant` mapping when using a custom selector (`[data-theme="dark"]`). `next-themes` defaults to a class-based `dark` selector, so we would either configure it to use `data-attribute="theme"` (extra wiring) or rewrite our CSS to a class-based selector (touches every tokenized component). The custom provider lets `data-theme` stay first-class.
- **No-FOUC guarantee under our CSP.** Our middleware sets a per-request CSP nonce; our `<NoFoucScript nonce={nonce}>` reads `await headers()` from the Server Component layout and emits the nonce attribute. `next-themes`'s injected script does support nonce passthrough via the `nonce` prop on `<ThemeProvider>`, but the wiring (header read + prop drilling) is identical complexity to the custom version, and any deviation surfaces as a silent CSP block (script doesn't run → wrong palette on first paint).
- **Test surface we control.** `test/theme-provider.test.tsx`, `test/components/theme-toggle.test.tsx`, `test/components/dynamic-theme-color.test.tsx`, and `test/theme-csp-regression.test.tsx` directly assert the contract we depend on. With `next-themes` we would test our wrapper around the library, not the underlying behaviour, and a library upgrade could silently break the no-FOUC invariant without our tests catching it.

### Why not `next-themes`

- **No new behaviour we need.** The whole reason a third-party library is worth taking on is because it solves a hard problem we'd get wrong. The hard parts here (nonce passthrough, storage event sync, hydration mismatch handling, lazy initializer) are all small and well-understood. Adopting a dependency to avoid ~150 lines of code is a poor trade.
- **Coupling to library evolution.** A `next-themes` major version bump or a Next.js App Router contract change at the library layer becomes our bug to track. With a custom provider, our contract is whatever our tests assert.

### What we give up

- **Battle-testing across many apps.** `next-themes` has weathered hydration edge cases that we may rediscover. Mitigation: our component test suite covers the cases the original review (10-agent multi-agent review, snapshot at `knowledge-base/project/specs/feat-theme-toggle/review-2026-05-05.md`) called out: hydration flicker, cross-tab sync, garbage storage values, quota errors, OS preference live-update, CSP nonce.
- **Familiarity for new contributors.** A new developer who has used `next-themes` elsewhere will need a few minutes to read `theme-provider.tsx`. Mitigation: the file has explicit invariant comments cross-linking the no-FOUC script render order in `app/layout.tsx`.

### When to revisit

Revisit this decision if any of the following are true:

1. We add a second app to the monorepo that needs theming, and copy-pasting `theme-provider.tsx` becomes a duplication problem (extract to `packages/`, then re-evaluate library adoption at extraction time).
2. We ship a settings page with server-persistence and an MCP `set_theme` tool (deferred — see issue filed alongside this PR), and the additional surface area starts to look like reinventing `next-themes`.
3. A future Tailwind / Next.js / React contract change makes the manual `data-theme` integration noticeably harder to maintain than the library version.

## Related

- PR #3271 — implementation
- Issue #3232 — original feature request
- Review snapshot: `knowledge-base/project/specs/feat-theme-toggle/review-2026-05-05.md`
- AGENTS.md `cq-silent-fallback-must-mirror-to-sentry`
