---
title: "Tasks — fix theme-preference persistence (OS prefers-color-scheme override)"
branch: feat-one-shot-theme-persist-system-override
lane: single-domain
plan: knowledge-base/project/plans/2026-06-15-fix-theme-preference-persistence-system-override-plan.md
date: 2026-06-15
---

# Tasks

Derived from `2026-06-15-fix-theme-preference-persistence-system-override-plan.md`.

## Phase 0 — Reproduce & pin root cause (no code change)

- [ ] 0.1 Read `apps/web-platform/middleware.ts` + `apps/web-platform/lib/csp.ts`; determine whether `x-nonce` is set on every document response and whether `script-src` is strict-nonce (H1).
- [ ] 0.2 Query Sentry (client-observability layer, NOT dashboard eyeball) for `feature:"theme-provider"` events `op:"setItem"` / `op:"storage-event"` to confirm/eliminate H3.
- [ ] 0.3 Playwright MCP repro: OS=dark, `localStorage["soleur:theme"]="light"`, hard reload; read `dataset.theme` + computed `--soleur-bg-base` at first paint. Repeat with inline script blocked. Screenshot.
- [ ] 0.4 Write confirmed root-cause note (H1/H2/H3 + exact reachable state) at top of Phase 1; adjust fix target if not H1.

## Phase 1 — Fix the confirmed cause

- [ ] 1.1 (Always) `theme-provider.tsx` first-mount effect (~217-247): when `dataset.theme` absent/invalid, seed from `readStoredTheme()` (durable store) instead of React SSR-fallback `"system"`. Defense-in-depth correctness fix.
- [ ] 1.2 (If H1) Ensure inline `NoFoucScript` is CSP-admitted on every document route: fix `x-nonce` emission in `middleware.ts`/`lib/csp.ts`, and/or add a sha256 CSP hash for the static `SCRIPT` body in `lib/csp.ts` (no `'unsafe-inline'`).
- [ ] 1.3 (If H3 only) Re-scope to write-durability note; flag at review that there is no OS-override logic bug. (Gate.)

## Phase 2 — Regression test (assert palette invariant, not proxy)

- [ ] 2.1 Create `apps/web-platform/test/theme-explicit-choice-survives-reload.test.tsx` (under `test/` — NOT co-located; vitest happy-dom glob is `test/**/*.test.tsx`).
- [ ] 2.2 Case: stored `"light"` + OS dark + no bootstrap → resolves `data-theme="light"`.
- [ ] 2.3 Symmetric: stored `"dark"` + OS light → resolves dark. Control: stored `"system"` + OS light → follows OS (light).
- [ ] 2.4 (If CSP change shipped) Extend `theme-csp-regression.test.tsx` (or sibling) to assert the chosen admit mechanism.

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/theme-explicit-choice-survives-reload.test.tsx test/theme-provider.test.tsx test/theme-csp-regression.test.tsx test/components/theme-no-fouc-script.test.tsx test/components/theme-toggle.test.tsx test/theme-toggle-ssr-hydration.test.tsx` — all pass.
- [ ] 3.3 Playwright MCP re-verify: explicit Light on dark-OS survives reload; explicit Dark on light-OS survives reload; `system` follows OS. Screenshot before/after.
