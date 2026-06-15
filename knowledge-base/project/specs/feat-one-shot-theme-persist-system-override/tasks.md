---
title: "Tasks — fix theme-preference persistence (OS prefers-color-scheme override)"
branch: feat-one-shot-theme-persist-system-override
lane: single-domain
plan: knowledge-base/project/plans/2026-06-15-fix-theme-preference-persistence-system-override-plan.md
date: 2026-06-15
---

# Tasks

Derived from `2026-06-15-fix-theme-preference-persistence-system-override-plan.md`.

## Phase 0 — Confirm root cause + scope edge-cache (no code change)

Root cause already pinned by the deepen pass: H2 — on the SSR-hydration path the
lazy initializer (`theme-provider.tsx:179-180`) returns `"system"`, React reuses
it, and the first-mount else-branch (line 239) writes `"system"` to
`dataset.theme` when the bootstrap didn't run → OS palette wins.

- [~] 0.1 (root cause confirmed by code trace; live Playwright repro deferred to QA phase) Playwright MCP repro: OS=dark, `localStorage["soleur:theme"]="light"`, hard reload; read `dataset.theme` + computed `--soleur-bg-base` at first paint; confirm the H2 state. Screenshot.
- [~] 0.2 (no edge-cache evidence; optional hardening skipped) Confirm whether HTML documents are edge/CDN-cached in prod (H1 residual nonce-divergence path). If yes → enable optional hardening 1.2; if no → skip it.
- [~] 0.3 (not blocking; skipped) (Optional) Query Sentry (client-observability layer, NOT dashboard) for `feature:"theme-provider"` `op:"setItem"` events to gauge H3 contribution. Not blocking.

## Phase 1 — Fix the confirmed cause (PRIMARY: H2)

- [x] 1.1 (Always — PRIMARY) `theme-provider.tsx` first-mount effect else-branch (~236-241): replace `dataset.theme = theme` (line 239, writes `"system"`) with `const stored = readStoredTheme(); dataset.theme = stored; if (stored !== theme) { setThemeState(stored); setResolvedTheme(resolveInitial(stored)); } prevThemeRef.current = stored;`. State-sync is load-bearing (avoids reintroducing the #3318 wrong-segment symptom). Bootstrap-ran branch (219-234) unaffected.
- [~] 1.2 (SCOPED OUT — line-239 fix corrects palette even when bootstrap blocked; no live edge-cache evidence gathered, primary fix is sufficient) (Optional hardening — only if Phase 0.2 confirms HTML edge caching) `lib/csp.ts`: add sha256 CSP hash for the static `NoFoucScript` body and/or `Cache-Control: no-store` on document responses. NOT required for primary fix.

## Phase 2 — Regression test (assert palette invariant, not proxy)

- [x] 2.1 Create `apps/web-platform/test/theme-explicit-choice-survives-reload.test.tsx` (under `test/` — NOT co-located; vitest happy-dom glob is `test/**/*.test.tsx`).
- [x] 2.2 MUST force the SSR-hydration buggy state (initial `theme`=`"system"`, `dataset.theme` absent, localStorage=`"light"`, `matchMedia`=OS dark) — a client-only mount masks the bug (lazy init reaches `readStoredTheme()`). Assert post-effect `dataset.theme === "light"` AND `useTheme().theme === "light"`.
- [x] 2.3 Symmetric: stored `"dark"` + OS light → resolves dark (+ context). Control: stored `"system"` + OS light → follows OS (light), context `"system"`.
- [~] 2.4 (N/A — 1.2 not shipped) (Only if 1.2 shipped) Extend `theme-csp-regression.test.tsx` (or sibling) to assert the chosen admit mechanism (hash present / no-store header).

## Phase 3 — Verify

- [x] 3.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/theme-explicit-choice-survives-reload.test.tsx test/theme-provider.test.tsx test/theme-csp-regression.test.tsx test/components/theme-no-fouc-script.test.tsx test/components/theme-toggle.test.tsx test/theme-toggle-ssr-hydration.test.tsx` — all pass.
- [ ] 3.3 (runs in QA phase via Playwright MCP) Playwright MCP re-verify: explicit Light on dark-OS survives reload; explicit Dark on light-OS survives reload; `system` follows OS. Screenshot before/after.
