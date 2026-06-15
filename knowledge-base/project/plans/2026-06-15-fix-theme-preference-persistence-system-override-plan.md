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
reset afterward, despite localStorage holding `dark`/`light`. Candidate
reachable causes, ranked by likelihood given the **intermittent** ("sometimes")
report:

- **H1 — CSP nonce miss blocks the inline `NoFoucScript`.** If the per-request nonce is absent/mismatched (e.g., a cached/edge-served document, a route where `x-nonce` isn't set, a CSP that rejects the inline script), the bootstrap never runs → `data-theme` stays unset → `globals.css` `:root:not([data-theme])` `@media (prefers-color-scheme)` block drives the palette to the OS preference. **Intermittent** fits (only on routes/edge cases where the nonce path fails). `theme-csp-regression.test.tsx` covers the *passthrough*, but only asserts the attribute is rendered — not that production CSP actually admits the script, and not the unset-`data-theme` → OS-palette fallback consequence. *This is the leading hypothesis.*
- **H2 — `ThemeProvider` first-mount effect overwrites a correct `dataset.theme` with `"system"`.** In `theme-provider.tsx` lines 217-247, when `dataset.theme` is *invalid/absent* the effect writes React's current `theme` (which is `"system"` on the SSR-fallback path) to `dataset.theme`. If the inline script ran but the attribute was scrubbed/raced, the effect could pin `"system"`. Need to confirm whether any ordering makes `prevThemeRef.current === null` see an absent attribute while localStorage is `dark`.
- **H3 — localStorage value not durable.** The user's choice never actually persisted (quota, private mode, an unexpected clear). `setTheme` mirrors `setItem` failures to Sentry; check whether `reportSilentFallback`/`op:"setItem"` events exist. If localStorage is empty on reload, `system` is the correct fallback and the "bug" is a persistence-write failure, not a read/cascade failure.
- **H4 — A second writer/clearer of the key.** `git grep` confirmed only `theme-provider.tsx` + `no-fouc-script.tsx` touch `soleur:theme` (the `notification-prompt.tsx` STORAGE_KEY is unrelated). H4 is effectively eliminated but Phase 0 re-confirms no extension/SDK path clears it.

**Phase 0 picks the confirmed hypothesis; later phases implement against it.**
The most probable outcome is H1 (matches the intermittent symptom and the
unset-`data-theme`→OS-palette mechanism exactly); the plan is structured so the
fix and regression test target whichever hypothesis Phase 0 confirms, but the
default implementation path below is written for H1 with H2 as a defense-in-depth
secondary.

## Implementation Phases

### Phase 0 — Reproduce & pin root cause (investigation, no code change)

1. Read `apps/web-platform/middleware.ts` and `apps/web-platform/lib/csp.ts` end-to-end: confirm whether `x-nonce` is set on **every** document response (including any cached/static/edge path) and whether the CSP `script-src` is `'nonce-…'` strict (which would block a nonce-less inline script) or includes `'unsafe-inline'`/a hash fallback. Determine if any route renders `layout.tsx` without a nonce (the `headerList.get("x-nonce") ?? undefined` path at `layout.tsx:46` silently degrades to a nonce-less `<script>`).
2. Check Sentry for `reportSilentFallback` events with `feature:"theme-provider"` and `op:"setItem"` or `op:"storage-event"` (eliminates/confirms H3) via the observability layer — query, do not eyeball a dashboard (`hr-no-dashboard-eyeball-pull-data-yourself`).
3. Reproduce in a real browser with the Playwright MCP: set OS to dark, set `localStorage["soleur:theme"]="light"`, hard-reload, and read `document.documentElement.dataset.theme` + the computed `--soleur-bg-base` on first paint. Repeat with a simulated nonce-less/CSP-blocked inline script (block the inline script via route or CSP) to confirm the unset-`data-theme`→OS-palette mechanism. Capture a screenshot.
4. Write the confirmed root cause as a one-paragraph note at the top of Phase 1, and adjust Phase 1's fix target if Phase 0 confirms H2/H3 over H1.

### Phase 1 — Fix the confirmed cause (default: H1 — guarantee the bootstrap always runs / fails safe to stored theme)

Default path (H1 confirmed):

1. Ensure the inline `NoFoucScript` is admitted by CSP on every document route. Two non-exclusive measures, chosen per Phase 0 findings:
   - If a route can render `layout.tsx` without a nonce, fix the nonce-set path in `middleware.ts`/`lib/csp.ts` so `x-nonce` is always present for document responses (preferred — keeps strict CSP intact).
   - If strict-nonce CSP can race/cache such that the script is occasionally rejected, add a CSP **hash** for the static `SCRIPT` string as a belt-and-suspenders admit path (the script body is a static literal, so a stable sha256 hash is computable at build time — no `'unsafe-inline'`).
2. Harden the fallback so that *even if the inline script does not run*, an explicit stored choice is not silently surrendered to the OS:
   - In `ThemeProvider`'s first-mount effect (`theme-provider.tsx` ~217-247): when `dataset.theme` is absent/invalid, **read `localStorage` directly** (`readStoredTheme()`) and write *that* to `dataset.theme` + React state — instead of writing React's SSR-fallback `theme` (`"system"`). This converts the current "establish baseline from React state" branch (which is `"system"` on the SSR path) into "establish baseline from the durable store", closing the unset-`data-theme`→OS-palette window without depending on the inline script. This is the smallest correctness-restoring edit and is defense-in-depth even if H1's CSP fix fully resolves the symptom.

Secondary path (only if Phase 0 confirms H2): adjust the first-mount effect so an absent attribute never resolves to `"system"` when localStorage holds a concrete choice (same edit as 1.2 above; H2 and H1's fallback converge on the same code change).

Tertiary path (only if Phase 0 confirms H3 — write failure): the read side is
already correct; scope the fix to surfacing the persistence failure (the Sentry
mirror already exists) and confirm no additional write-path bug. If H3 is the
sole cause, document it and close — there is no "OS override" logic bug, and the
plan re-scopes to a write-durability note (flag at review for re-scope).

### Phase 2 — Regression test (assert the resolved palette, not a proxy)

Add a regression test that asserts the **invariant itself** (palette token /
`data-theme` resolution) rather than a proxy (attribute presence, button state).
Per the runner config, jsdom/happy-dom component tests MUST live under
`apps/web-platform/test/**/*.test.tsx` (`vitest.config.ts:60` `include:
["test/**/*.test.tsx"]`) — a co-located `components/**/*.test.tsx` is silently
never collected.

1. New `apps/web-platform/test/theme-explicit-choice-survives-reload.test.tsx`:
   - Simulate `localStorage["soleur:theme"]="light"` + OS dark (`matchMedia` stub returns dark), with the inline bootstrap **not** having run (scrubbed `dataset.theme` — the exact unset-attribute state). Mount `<ThemeProvider>` and assert the first-mount effect writes `data-theme="light"` (NOT `"system"`/unset) — i.e., the explicit stored choice wins over OS even on the no-bootstrap path.
   - Symmetric case: stored `"dark"` + OS light → resolves dark.
   - Control: stored `"system"` + OS light → resolves to follow OS (light) — proves we did not break the genuine system-follow behavior.
2. If Phase 1 includes a CSP hash/nonce change, extend `theme-csp-regression.test.tsx` (or add a sibling) to assert the admit mechanism Phase 1 chose (hash present in CSP, or nonce always non-undefined for document responses) — assert the mechanism, not "specialist reported done".

### Phase 3 — Verify

1. Typecheck (in-package — root has **no** `workspaces` field, so `npm run -w` aborts): `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
2. Run affected tests via the package's actual runner (vitest, per `vitest.config.ts`): `cd apps/web-platform && ./node_modules/.bin/vitest run test/theme-explicit-choice-survives-reload.test.tsx test/theme-provider.test.tsx test/theme-csp-regression.test.tsx test/components/theme-no-fouc-script.test.tsx test/components/theme-toggle.test.tsx test/theme-toggle-ssr-hydration.test.tsx`.
3. Playwright MCP re-verification of the Phase 0 repro: explicit Light on dark-OS survives reload (palette + token), explicit Dark on light-OS survives reload, `system` still follows OS. Screenshot before/after.

## Files to Edit

- `apps/web-platform/components/theme/theme-provider.tsx` — first-mount effect: when `dataset.theme` is absent/invalid, seed from `readStoredTheme()` (durable store) instead of React's SSR-fallback `"system"` state. (Always edited — this is the defense-in-depth correctness fix regardless of confirmed hypothesis.)
- `apps/web-platform/middleware.ts` — *conditional on H1*: ensure `x-nonce` is set on every document response. Read in Phase 0; edit only if a nonce-less document path exists.
- `apps/web-platform/lib/csp.ts` — *conditional on H1*: add a sha256 CSP hash for the static `NoFoucScript` body as a belt-and-suspenders admit path, or fix the nonce emission. Read in Phase 0; edit only if Phase 0 confirms a CSP-block path.

## Files to Create

- `apps/web-platform/test/theme-explicit-choice-survives-reload.test.tsx` — regression test asserting explicit stored choice wins over OS `prefers-color-scheme` on the no-bootstrap path (palette-token / `data-theme` invariant, plus a `system`-follows-OS control).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` was queried for bodies
containing `theme-provider.tsx`, `no-fouc-script.tsx`, `theme-toggle.tsx`; zero
matches.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Phase 0 produces a written, reproduced root-cause note naming the confirmed hypothesis (H1/H2/H3) and the exact reachable state (`data-theme` value at first paint) that produced the OS-override symptom.
- [ ] With `localStorage["soleur:theme"]="light"`, OS = dark, and the inline bootstrap **not** run, mounting `<ThemeProvider>` resolves `document.documentElement.dataset.theme === "light"` (NOT `"system"`/unset) — asserted in `test/theme-explicit-choice-survives-reload.test.tsx`.
- [ ] Symmetric: stored `"dark"` + OS light → resolves dark; control: stored `"system"` + OS light → follows OS (light). All in the new test.
- [ ] If a CSP/nonce change ships: the new/extended test asserts the chosen admit mechanism (CSP hash present, or `x-nonce` always non-undefined for document responses).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] All listed theme tests pass via `./node_modules/.bin/vitest run …` (new test + 5 pre-existing affected suites).
- [ ] No change to `--soleur-*` token values in `globals.css` or to the `globals.css` cascade (the cascade is correct; this is a bootstrap/persistence fix). The `theme-no-fouc-script.tsx` drift-guard test still passes.

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
