---
title: "fix(theme): explicit choice must survive reload — stop OS prefers-color-scheme from overriding persisted theme"
type: bug
branch: feat-one-shot-theme-persist-system-override
date: 2026-06-15
lane: single-domain
brand_survival_threshold: none
status: planned
---

# 🐛 fix(theme): explicit theme choice overridden by OS `prefers-color-scheme` on reload

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Hypotheses (re-ranked), Implementation Phases (root cause pinned), Files to Edit (scoped down)
**Research agents used:** Explore ×3 (CSP/nonce verification, ThemeProvider H2 reachability, theme learnings), architecture-strategist

### Key Improvements
1. **Root cause pinned without needing Phase 0 guesswork.** The deepen agents traced the exact reachable bug state in `theme-provider.tsx`: on the **SSR-hydration path** (the production path) the lazy `useState` initializer at line 180 returns `"system"` (`typeof window === "undefined"` is true server-side), React 18 reuses that snapshot on the client, and when the inline bootstrap also did not write `dataset.theme`, the first-mount effect's else-branch at **line 239 writes `theme` (= `"system"`)** to `dataset.theme` — so the `@media (prefers-color-scheme)` block drives the palette. **This is the bug.** The fix is to seed line 239 from `readStoredTheme()` (durable store) and sync React state, mirroring the bootstrap-ran branch at lines 230-232.
2. **H1 (CSP nonce-miss block) demoted from leading to low-probability.** `lib/csp.ts:84-90` always includes `'unsafe-inline'` in `script-src` alongside `'nonce-…'` + `'strict-dynamic'`. A nonce-less inline script is admitted on CSP1/CSP2 via `'unsafe-inline'` and on CSP3 via the nonce — so a plain nonce-miss does NOT block the script. The one residual CSP path is **edge/CDN caching serving a stale HTML document whose baked-in nonce diverges from a fresh `Content-Security-Policy` header nonce** (strict-dynamic then blocks on CSP3); normal page responses carry no `Cache-Control: no-store`. This is a real-but-narrow contributor to the "sometimes" intermittency, not the primary cause.
3. **Files-to-Edit scoped down.** `middleware.ts` / `lib/csp.ts` are NOT on the critical path for the primary fix (the line-239 seed is the load-bearing change). They remain optional hardening only if Phase 0 confirms the edge-cache nonce-divergence path is material in production.

### New Considerations Discovered
- The architecture-strategist initially flagged the fix as "already implemented" because `resolveClientInitialTheme()` (line 65-72) reads `readStoredTheme()` as its fallback. That fallback is **only reached on a client-only render** — on the SSR-hydration path React reuses the server's `"system"` snapshot and the initializer's `readStoredTheme()` branch never runs on the client. The line-239 else-branch is therefore genuinely writing `"system"`, and the fix has a real diff. The regression test MUST simulate the SSR-hydration path (initial `theme` state = `"system"`, `dataset.theme` absent, localStorage = `"light"`) — not a client-only mount, which would mask the bug.
- Prior-art learning `2026-06-12-likec4-mantine-color-scheme-seam-and-vendored-theme-preservation.md` documents a structurally identical defect (provider `"auto"`/`"system"` default firing before the persisted value, letting OS `prefers-color-scheme` win) — same seam-analysis fix pattern: force the resolved value before the OS fallback can win.
- Prior-art learning `2026-04-27-critical-css-fouc-prevention-via-static-and-playwright-gates.md` gives the canonical QA gate: block external stylesheets at the network layer (`page.route('**/*.css', abort)` + `waitUntil:'domcontentloaded'`) and assert the `data-theme` attribute — directly applicable to the Phase 3 Playwright re-verification.

## Overview

A user who explicitly picks **Dark** (or Light) sometimes finds that after a
reload the **palette follows the OS `prefers-color-scheme` instead of their
stored choice**. This is *not* the #3318 symptom (toggle button stuck on the
"System" segment while the palette was correct). Here the **palette itself**
reverts to the OS preference — the visual theme, not just the indicator.

The persistence contract is layered:

1. `localStorage["soleur:theme"]` — durable store of the user's choice (`dark` | `light` | `system`).
2. Inline `NoFoucScript` (`components/theme/no-fouc-script.tsx`) runs synchronously in `<head>`, reads localStorage, writes `<html data-theme=...>` + pre-paint inline-style hints **before first paint**.
3. `globals.css` cascade: `:root[data-theme="dark"]` / `[data-theme="light"]` win unconditionally; the `@media (prefers-color-scheme: …)` block applies **only** to `[data-theme="system"]` or `:root:not([data-theme])`.
4. `ThemeProvider` (`components/theme/theme-provider.tsx`) hydrates React state from `documentElement.dataset.theme`.

The CSS cascade (layer 3) is **correct by inspection** — an explicit
`data-theme="light"`/`"dark"` is never reachable by the `prefers-color-scheme`
media block. Therefore the reported symptom ("OS overrides explicit choice")
can only occur when **`data-theme` ends up unset or `"system"` on the document
at first paint despite a non-`system` value in localStorage**, OR when a code
path **writes `"system"`/clears the attribute after the user's explicit choice
was stored**. The fix is to find which of those reachable states produces the
symptom and close it; the cascade itself needs no change.

This plan investigates first (the symptom is intermittent — "sometimes" —
which points to a timing/environment-dependent path, not an always-on logic
error) and lands a targeted fix plus a regression test that asserts the
**resolved palette token**, not a proxy.

## Premise Validation

- Cited PRs **#3312 / #3315 / #3318** all confirmed `MERGED` via `gh pr view` (they are PRs, not issues — the argument said "issues" but `gh issue view` resolved them as PRs). #3318 ("persist toggle position across reload") added `resolveClientInitialTheme()` reading `dataset.theme` first; #3312 added the first-mount sync effect; #3315 relocated the toggle. The current bug is a **distinct symptom** (palette reverts, not button position) — these prior fixes are correctly out of scope and not regressed by this plan.
- Stale worktree `feat-one-shot-theme-selector-reload-bug` (closed PR #3320) per instructions: **ignored**; this branch `feat-one-shot-theme-persist-system-override` is fresh and avoids the name collision. Verified current branch = `feat-one-shot-theme-persist-system-override`.
- Proposed *mechanism* (keep explicit `data-theme` from being clobbered to `system`/unset) checked against the ADR corpus and the existing theme architecture: no ADR prescribes a different persistence mechanism; the `data-theme` + inline-bootstrap + localStorage triad is the established pattern (no rejected-alternative collision).
- No external premises beyond the above.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (`single-domain` lane, defaulted from absence
of a spec — recorded here, not a fail-closed cross-domain default because the
change is confined to `components/theme/`). The argument's claims were validated
directly against code:

| Claim (from argument) | Reality (codebase) | Plan response |
|---|---|---|
| "OS prefers-color-scheme overrides my explicit choice on reload" | CSS cascade gives explicit `data-theme` precedence; only `system`/unset follows OS. So the bug is upstream: `data-theme` is wrong at paint, or gets reset to `system`/unset. | Investigation Phase 0 reproduces and pins the exact reachable state before any code edit. |
| "prior fixes #3312/#3315/#3318 already shipped" | All three MERGED; they fixed toggle-position/hydration, not palette reversion. | Treated as shipped; not modified; regression-protected. |

## User-Brand Impact

**If this lands broken, the user experiences:** the app paints in the OS theme
instead of the theme they explicitly selected after every reload — a visibly
"forgetful" product that doesn't respect a basic preference.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — the
theme preference is a non-sensitive UI setting stored in `localStorage`; no PII,
no network transmission, no cross-user exposure.

**Brand-survival threshold:** none.

threshold: none, reason: the change touches only client-side theme rendering in `components/theme/`; no sensitive path (schema, auth, API route, migration, secret) is modified — confirmed by Files-to-Edit scope below.

## Hypotheses (to confirm/eliminate in Phase 0)

The symptom requires `data-theme` to be unset or `"system"` at first paint, or
reset afterward, despite localStorage holding `dark`/`light`. Re-ranked after the
deepen pass traced the code paths (see Enhancement Summary):

- **H2 (CONFIRMED — PRIMARY) — `ThemeProvider` first-mount effect writes `"system"` to `dataset.theme` on the SSR-hydration path when the bootstrap did not run.** Traced precisely: the lazy `useState` initializer at `theme-provider.tsx:179-180` returns `"system"` on the server (`typeof window === "undefined"`); React 18 reuses the server snapshot on the client and does NOT re-run the initializer, so `theme === "system"` at first mount. When `dataset.theme` is absent/invalid (bootstrap didn't run), the first-mount effect's else-branch at **line 239 writes `theme` (= `"system"`)** to `dataset.theme` — the `globals.css` `@media (prefers-color-scheme)` block then drives the palette to the OS preference. The `readStoredTheme()` fallback inside `resolveClientInitialTheme()` (line 71) does NOT save this case, because that function is only reached on a *client-only* render, never on the SSR-hydration path React actually uses in production. **This is the bug; the fix is the line-239 seed.**
- **H1 (DEMOTED — low probability) — CSP edge-cache nonce divergence.** A plain nonce-miss does NOT block the inline script: `lib/csp.ts:84-90` always includes `'unsafe-inline'` in `script-src` (admits on CSP1/CSP2) alongside `'nonce-…'` + `'strict-dynamic'` (admits on CSP3). The only residual block path is an **edge/CDN cache serving a stale HTML document whose baked-in nonce diverges from a freshly-headered CSP nonce** (`'strict-dynamic'` then blocks on CSP3); normal page responses set no `Cache-Control: no-store`. This is a plausible *contributor to the "sometimes"* intermittency (it leaves `dataset.theme` unset → triggers the H2 else-branch), but it is upstream of the same H2 mechanism — fixing line 239 makes the palette correct even when the bootstrap is blocked. Phase 0 confirms whether edge caching of documents actually occurs in prod; if so, add the optional CSP hardening, but the primary fix stands regardless.
- **H3 — localStorage value not durable.** The user's choice never persisted (quota, private mode, clear). `setTheme` already mirrors `setItem` failures to Sentry; Phase 0 queries for `reportSilentFallback op:"setItem"` events. If localStorage is empty on reload, `system` is the correct fallback (not a bug). Likely a minor/secondary contributor at most.
- **H4 — A second writer/clearer of the key.** `git grep` confirmed only `theme-provider.tsx` + `no-fouc-script.tsx` touch `soleur:theme` (the `notification-prompt.tsx` STORAGE_KEY is unrelated). Eliminated.

**Phase 0 reproduces and confirms H2 as primary; the fix and regression test
target the line-239 SSR-hydration mechanism.** Phase 0 is now confirmation +
edge-cache scoping, not open-ended hypothesis selection — the deepen pass already
pinned the cause.

## Implementation Phases

### Phase 0 — Reproduce & pin root cause (investigation, no code change)

1. Read `apps/web-platform/middleware.ts` and `apps/web-platform/lib/csp.ts` end-to-end: confirm whether `x-nonce` is set on **every** document response (including any cached/static/edge path) and whether the CSP `script-src` is `'nonce-…'` strict (which would block a nonce-less inline script) or includes `'unsafe-inline'`/a hash fallback. Determine if any route renders `layout.tsx` without a nonce (the `headerList.get("x-nonce") ?? undefined` path at `layout.tsx:46` silently degrades to a nonce-less `<script>`).
2. Check Sentry for `reportSilentFallback` events with `feature:"theme-provider"` and `op:"setItem"` or `op:"storage-event"` (eliminates/confirms H3) via the observability layer — query, do not eyeball a dashboard (`hr-no-dashboard-eyeball-pull-data-yourself`).
3. Reproduce in a real browser with the Playwright MCP: set OS to dark, set `localStorage["soleur:theme"]="light"`, hard-reload, and read `document.documentElement.dataset.theme` + the computed `--soleur-bg-base` on first paint. Repeat with a simulated nonce-less/CSP-blocked inline script (block the inline script via route or CSP) to confirm the unset-`data-theme`→OS-palette mechanism. Capture a screenshot.
4. Write the confirmed root cause as a one-paragraph note at the top of Phase 1, and adjust Phase 1's fix target if Phase 0 confirms H2/H3 over H1.

### Phase 1 — Fix the confirmed cause (PRIMARY: H2 — seed the first-mount fallback from the durable store, not React's `"system"`)

Primary path (H2, confirmed by the deepen pass):

1. In `ThemeProvider`'s first-mount effect (`theme-provider.tsx` else-branch around lines 236-241): when `dataset.theme` is absent/invalid, **read `localStorage` directly** (`readStoredTheme()`) and write *that* to `dataset.theme`, AND sync React state to it — mirroring the bootstrap-ran branch at lines 230-232 (`setThemeState(fromDom); setResolvedTheme(resolveInitial(fromDom))`). Concretely, replace `document.documentElement.dataset.theme = theme` (line 239, which writes the SSR-fallback `"system"`) with:
   - `const stored = readStoredTheme();`
   - `document.documentElement.dataset.theme = stored;`
   - `if (stored !== theme) { setThemeState(stored); setResolvedTheme(resolveInitial(stored)); }`
   - `prevThemeRef.current = stored;`

   This closes the unset-`data-theme`→OS-palette window on the SSR-hydration path without depending on the inline script. **State-sync is load-bearing:** writing `dataset.theme` alone fixes the palette but leaves the React `theme` state on `"system"`, so the `ThemeToggle` indicator would show the wrong segment (the #3318 symptom) — sync both, as the bootstrap branch already does.

**Research Insight (verified):** the bootstrap-ran branch (lines 219-234) is
unaffected — `isTheme(fromDom)` returns early at line 234 before reaching the
else-branch, so no regression for the normal path. The genuine `system` case
(localStorage = `"system"`/empty) is unaffected: `readStoredTheme()` returns
`"system"`, identical to current behavior. (Source: H2-reachability deepen agent,
`theme-provider.tsx:219-247`.)

Optional hardening (only if Phase 0 confirms edge/CDN caching of HTML documents
in prod — the H1 residual path):

2. Add a CSP **hash** for the static `NoFoucScript` body in `lib/csp.ts` (the body is a static literal → stable sha256, no `'unsafe-inline'` reliance), and/or set `Cache-Control: no-store` on document responses so a stale baked-in nonce never diverges from the CSP-header nonce. This is belt-and-suspenders — the primary line-239 fix already makes the palette correct even when the bootstrap is fully blocked.

If Phase 0 finds H3 (write failure) is also occurring, note it; the read-side
fix above already handles a present-but-not-applied value, and the existing
Sentry mirror surfaces write failures — no additional write-path code needed.

### Phase 2 — Regression test (assert the resolved palette, not a proxy)

Add a regression test that asserts the **invariant itself** (palette token /
`data-theme` resolution) rather than a proxy (attribute presence, button state).
Per the runner config, jsdom/happy-dom component tests MUST live under
`apps/web-platform/test/**/*.test.tsx` (`vitest.config.ts:60` `include:
["test/**/*.test.tsx"]`) — a co-located `components/**/*.test.tsx` is silently
never collected.

1. New `apps/web-platform/test/theme-explicit-choice-survives-reload.test.tsx`:
   - **MUST simulate the SSR-hydration path, not a client-only mount.** The bug only manifests when the first-mount `theme` state is `"system"` (the server snapshot React reuses) AND `dataset.theme` is absent. A naive client-only mount would let the lazy initializer reach `readStoredTheme()` (line 71) and mask the bug — the test would pass green before any fix and prove nothing. To force the buggy state: scrub `document.documentElement.dataset.theme` (unset), set `localStorage["soleur:theme"]="light"`, stub `matchMedia` to report OS dark, and ensure the provider's initial `theme` state resolves to `"system"` (e.g., by mounting with `dataset.theme` absent at initializer time so `resolveClientInitialTheme()`→`readStoredTheme()` is the only seed — OR explicitly assert the post-effect DOM state which is the real invariant regardless of init path). Assert the first-mount effect resolves `document.documentElement.dataset.theme === "light"` (NOT `"system"`/unset) AND the `useTheme()` context `theme === "light"` (state-sync invariant).
   - Symmetric case: stored `"dark"` + OS light → resolves dark, context `theme === "dark"`.
   - Control: stored `"system"` + OS light → resolves to follow OS (light), context `theme === "system"` — proves we did not break the genuine system-follow behavior.
2. If Phase 1 includes a CSP hash/nonce change, extend `theme-csp-regression.test.tsx` (or add a sibling) to assert the admit mechanism Phase 1 chose (hash present in CSP, or nonce always non-undefined for document responses) — assert the mechanism, not "specialist reported done".

### Phase 3 — Verify

1. Typecheck (in-package — root has **no** `workspaces` field, so `npm run -w` aborts): `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
2. Run affected tests via the package's actual runner (vitest, per `vitest.config.ts`): `cd apps/web-platform && ./node_modules/.bin/vitest run test/theme-explicit-choice-survives-reload.test.tsx test/theme-provider.test.tsx test/theme-csp-regression.test.tsx test/components/theme-no-fouc-script.test.tsx test/components/theme-toggle.test.tsx test/theme-toggle-ssr-hydration.test.tsx`.
3. Playwright MCP re-verification of the Phase 0 repro: explicit Light on dark-OS survives reload (palette + token), explicit Dark on light-OS survives reload, `system` still follows OS. Screenshot before/after.

## Files to Edit

- `apps/web-platform/components/theme/theme-provider.tsx` — **the primary fix (always edited).** First-mount effect else-branch (~lines 236-241): seed `dataset.theme` from `readStoredTheme()` (durable store) and sync React state, instead of writing React's SSR-fallback `"system"` (current line 239). This is the load-bearing H2 fix.
- `apps/web-platform/lib/csp.ts` — *optional hardening, conditional on Phase 0 confirming HTML edge/CDN caching in prod*: add a sha256 CSP hash for the static `NoFoucScript` body and/or `Cache-Control: no-store` on document responses. NOT required for the primary fix (a plain nonce-miss is already admitted by `'unsafe-inline'`; the line-239 fix corrects the palette even if the bootstrap is fully blocked).
- ~~`apps/web-platform/middleware.ts`~~ — **removed from scope.** The deepen pass confirmed `x-nonce` is set on every non-excluded document route (`middleware.ts:93,125`) and that `'unsafe-inline'` covers any nonce-less render; there is no nonce-emission bug to fix here.

## Files to Create

- `apps/web-platform/test/theme-explicit-choice-survives-reload.test.tsx` — regression test asserting explicit stored choice wins over OS `prefers-color-scheme` on the no-bootstrap path (palette-token / `data-theme` invariant, plus a `system`-follows-OS control).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` was queried for bodies
containing `theme-provider.tsx`, `no-fouc-script.tsx`, `theme-toggle.tsx`; zero
matches.

## Acceptance Criteria

### Pre-merge (PR)
- [x] Phase 0 produces a written, reproduced root-cause note naming the confirmed hypothesis (H1/H2/H3) and the exact reachable state (`data-theme` value at first paint) that produced the OS-override symptom.
- [x] With `localStorage["soleur:theme"]="light"`, OS = dark, and the inline bootstrap **not** run, mounting `<ThemeProvider>` resolves `document.documentElement.dataset.theme === "light"` (NOT `"system"`/unset) — asserted in `test/theme-explicit-choice-survives-reload.test.tsx`.
- [x] Symmetric: stored `"dark"` + OS light → resolves dark; control: stored `"system"` + OS light → follows OS (light). All in the new test.
- [~] (N/A — no CSP/nonce change shipped) If a CSP/nonce change ships: the new/extended test asserts the chosen admit mechanism (CSP hash present, or `x-nonce` always non-undefined for document responses).
- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] All listed theme tests pass via `./node_modules/.bin/vitest run …` (new test + 5 pre-existing affected suites).
- [x] No change to `--soleur-*` token values in `globals.css` or to the `globals.css` cascade (the cascade is correct; this is a bootstrap/persistence fix). The `theme-no-fouc-script.tsx` drift-guard test still passes.

### Post-merge (operator)
- [ ] Playwright MCP (automatable — no operator-only step): load `/dashboard` on a dark-OS profile, select Light, reload, confirm Light palette persists; repeat Dark on light-OS; confirm `system` follows OS. `Automation: feasible via Playwright MCP` — fold into Phase 3, not a manual checklist item.

## Domain Review

**Domains relevant:** Product (ADVISORY)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — N/A (no new UI surface; modifies existing theme-rendering behavior only, no new `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` file is created)
**Pencil available:** N/A (no UI surface)

#### Findings

This is a behavioral correctness fix to existing theme rendering — it restores
the user's explicit choice surviving reload. No new pages, components, modals,
or flows. The UI-surface mechanical override did not fire (Files-to-Create
contains only a test file; Files-to-Edit are provider/middleware/csp logic, no
`components/**/*.tsx` *new* file, no `page.tsx`/`layout.tsx` creation). ADVISORY
tier auto-accepts on the pipeline path.

## Observability

```yaml
liveness_signal:
  what: existing reportSilentFallback mirror in theme-provider.tsx (op:"setItem", op:"storage-event")
  cadence: on-event (client-side, fires when localStorage write fails or a bad storage event arrives)
  alert_target: Sentry (client-observability layer, lib/client-observability.ts)
  configured_in: apps/web-platform/components/theme/theme-provider.tsx (setTheme catch + onStorage handler)
error_reporting:
  destination: Sentry via reportSilentFallback (already wired)
  fail_loud: true (silent fallback is mirrored, not swallowed)
failure_modes:
  - mode: localStorage write fails (quota/private mode) → choice not persisted
    detection: reportSilentFallback op:"setItem" event in Sentry
    alert_route: Sentry client error stream
  - mode: inline bootstrap blocked by CSP → data-theme unset at paint
    detection: Phase 1 fallback now seeds from localStorage, so palette stays correct; if CSP blocks recur, the H1 fix (nonce/hash) is the guard. No new dark monitor introduced.
    alert_route: existing CSP report-uri if configured (verify in Phase 0); otherwise the fallback makes this non-user-visible
logs:
  where: client-side Sentry breadcrumbs/events (no server log surface added)
  retention: Sentry default project retention
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/theme-explicit-choice-survives-reload.test.tsx
  expected_output: all assertions pass — explicit stored choice resolves to the chosen palette, not the OS preference
```

## Infrastructure (IaC)

No new infrastructure. The conditional `lib/csp.ts` edit (if H1 confirmed) adds
a CSP source hash within the existing application code path — it is not a new
server, secret, vendor, DNS record, or persistent runtime process. Skipped per
Phase 2.8 (pure code change against already-provisioned surface).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled (threshold: none, with a sensitive-path scope-out reason).
- The CSS cascade in `globals.css` is **correct** — do NOT "fix" it by reordering or adding `!important`. An explicit `data-theme` already beats `prefers-color-scheme`. The bug is upstream (the attribute's value at paint), so any cascade edit is a wrong-layer change that will fail the `theme-no-fouc-script.tsx` drift-guard and the token-parity tests.
- Component/jsdom tests MUST live under `apps/web-platform/test/**/*.test.tsx` — `vitest.config.ts` only collects that glob for the happy-dom project; a co-located `components/**/*.test.tsx` is silently never run.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; `npm run -w apps/web-platform typecheck` aborts (root `package.json` has no `workspaces` field).
- The regression test must assert the **resolved palette / `data-theme` value**, not a proxy like "the toggle button shows Light" (that proxy was the #3318 symptom and can pass while the palette is wrong) or "the inline `<script>` rendered with a nonce" (passes while production CSP still blocks it).
- This is NOT a re-do of #3318/#3312 — those fixed the toggle-indicator position and hydration; this fixes the palette reverting to OS. Do not touch `theme-toggle.tsx` styling.
