---
title: "feat: Linear-style command palette (⌘K) + help overlay (?)"
date: 2026-06-22
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5635
branch: feat-web-app-shortcuts
pr: 5633
brainstorm: knowledge-base/project/brainstorms/2026-06-22-keyboard-shortcuts-brainstorm.md
spec: knowledge-base/project/specs/feat-web-app-shortcuts/spec.md
---

# ✨ feat: Linear-style Command Palette (⌘K) + Help Overlay (?)

## Overview

Add a keyboard-first command layer to the Soleur web app (`apps/web-platform`), inspired by
Linear. v1 ships exactly two surfaces, both backed by **one central command registry** (single
source of truth): a `⌘K`/`Ctrl+K` command palette (via `cmdk`) and a `?` help overlay. The
existing scattered `⌘B` sidebar-toggle migrates into the registry. The registry is *structured*
to expose actions to agents later (#5638), but agents are **not** wired in v1.

Out of scope (deferred, tracked): single-key verbs (#5637), `G`-then-`I` nav sequences (#5636),
agent action surface (#5638), rebinding/scoped-maps/mobile (NG4).

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "No single-character shortcuts in v1 → WCAG 2.1.4 satisfied by construction" (spec TR4) | **`?` is a single-character shortcut** and IS in scope for WCAG SC 2.1.4 (Level A). The suppression-while-typing guard is necessary but not sufficient. | FR9: bind help to `⌘/` (modifier combo — exempt) as canonical + `?` as a guarded alias; honor a `shortcutsEnabled` toggle (the SC 2.1.4 "turn off" mechanism). |
| `cmdk` is the chosen palette lib | **Not installed.** `cmdk@1.1.1` peers `react: ^18 \|\| ^19` → React 19.1 compatible. | `bun add cmdk` in `apps/web-platform` (TR3). Validate `bun install --frozen-lockfile`. |
| Component lives near layout | vitest projects collect component tests ONLY from `apps/web-platform/test/**/*.test.tsx` (happy-dom). Co-located `components/**/*.test.tsx` is silently never run. | All component tests under `apps/web-platform/test/` (TR7). |
| Help overlay wireframe `02` shows `G then I/K/R/D` nav sequences | Those are NG2-deferred (#5636) — shipping them documents shortcuts that do nothing. | FR4: v1 overlay lists ONLY working shortcuts (`⌘K`, `⌘/`, `⌘B`, `?`, `Esc`). The wireframe's Navigation-sequence rows are a post-v1 vision; do NOT render until #5636. |
| FR3 "misfire-resistant" routine rows (design only) | **`POST /api/dashboard/routines/run` already exists** (`{fnId, confirmed?}` → `202 {dispatched}` / `409 {error:"confirmation_required"}` for protected; `400`/`502` carry `body.error`). Auth is **`validateOrigin` (Origin-header check), NOT a CSRF token**. Canonical caller `routines-surface.tsx:268` swallows non-409 errors. | FR3+FR6: palette "Run routine" does a **same-origin fetch** (no token), branches on **`res.status`** (409→confirm, 400/502→inline error), and is **intentionally stricter** than `routines-surface.tsx` (surfaces non-409 + Sentry). |
| `NAV_ITEMS`/`ADMIN_NAV_ITEMS` reused by the registry | **Module-local to `layout.tsx:95,102` — not exported.** | Extract to a shared `nav-items.ts`; re-import in both layout + registry (Phase 1.2). |
| `useFeatureFlag("command-palette")` | `FlagName` is a typed union; `command-palette` must be in `RUNTIME_FLAGS` in `lib/feature-flags/server.ts` or `tsc` fails (AC). | Add to `RUNTIME_FLAGS` as a **Phase 0 step (before any consumer)** — contract before consumer. |
| FR3 rows show "scope + last-run" | `RoutineItem` has **no `scope`** field — exposes `domain`, `ownerRole`, `scheduleLabel`, `manualTrigger`, `lastRun`. | Use `domain` + `scheduleLabel` + `lastRun` for disambiguation. |
| both wireframes committed | Confirmed: `01-command-palette-cmdk.png` + `02-help-overlay-shortcuts.png` both on disk (spec-flow's "01 missing" was a subagent path false-negative). | No action. |

## User-Brand Impact

**If this lands broken, the user experiences:** the `⌘K` palette swallowing keystrokes inside
chat/KB inputs (cannot type), or a "Run routine" row firing the wrong/unconfirmed Inngest
routine.
**If this leaks, the user's workflow is exposed via:** a mis-routed or silently-failed command
on a surface the operator drives constantly (navigation, KB search, workflow trigger).
**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins — covered by brainstorm Phase 0.1
> carry-forward (CPO assessed the idea). `user-impact-reviewer` runs at PR-review time.

## Implementation Phases

### Phase 0 — Flag union (contract before consumer)
0.1 Add `command-palette` to `RUNTIME_FLAGS` in `lib/feature-flags/server.ts` so `useFeatureFlag("command-palette")` typechecks (P0-2). This MUST precede any consumer code.

### Phase 1 — Registry + global listener (foundation)
1.1 In `apps/web-platform`: `bun install` (cold worktree — deps not pre-installed), then `bun add cmdk`, then `bun install --frozen-lockfile` to validate.
1.2 Extract `NAV_ITEMS`/`ADMIN_NAV_ITEMS` from `layout.tsx:95,102` into a shared `components/command-palette/nav-items.ts`; re-import into both layout and the registry (P0-1).
1.3 Create `use-shortcuts.tsx` (`"use client"`) — the provider that OWNS the command registry (flat array; `Command = { id, label, group, keys?, when?(ctx), run() }`) AND the single global `keydown` listener. (Registry + provider are one module in v1 — one consumer; #5638 can split it when it adds a second.) Static commands: Navigation (from `nav-items.ts`), Ask-an-agent, help, sidebar-toggle. Suppression contract via **one shared `isEditable(target)` predicate** (used by both the global listener and the `?` alias): skip when `target` is input/textarea/contenteditable **including the palette's own search input** (FR1/G3). Honor `shortcutsEnabled` (FR9). Never read `navigator.platform` during render (SSR/hydration).
1.4 Migrate the `⌘B` handler (layout.tsx:204–221) and fold the drawer `Escape` (192–201) into the registry/listener so there is no double-fire (FR5).

### Phase 2 — Command palette (⌘K)
2.1 `command-palette.tsx` (`"use client"`) using `cmdk` `Command.Dialog`. `role="dialog"`,
    `aria-modal`, `aria-labelledby`, focus trap, `inert={open || undefined}` on background,
    Esc-close + **focus restoration** to `document.activeElement` captured on open (FR7/G6).
2.2 Static groups render immediately; async groups (KB docs via `/api/kb/tree`, routines via
    `/api/dashboard/routines`) fetched **lazily on first palette open** (not prefetched), with a
    `mountedRef` guard (strict-mode double-mount) and a single "Searching…" affordance while
    in-flight (FR6/G5).
2.3 Error states (FR6/G2): KB `needsReconnect:true` → inline "Reconnect KB to search docs" row;
    `503/500` → "KB search temporarily unavailable". KB/routines failure must NOT break Navigation
    or Ask-an-agent groups.
2.4 Empty state (FR6/G4): "No results for '<q>'" + persistent fallback row "Ask an agent about
    '<q>'" → `/dashboard/chat/new` (pre-seed query). Turns dead-ends into the hero verb.
2.5 Selection: arrow keys + Enter. Navigate/open-chat → `router.push` (`next/navigation`) and close.
2.6 Stacking/Esc policy (FR8/G7): suppress `⌘K` while a blocking/confirm modal is open; allow over
    the mobile drawer (close drawer first); top-most layer consumes Esc (stop propagation).

### Phase 3 — Trigger-routine row (brand-critical) — FR3
3.1 Workflow rows show disambiguating context (`domain` + `scheduleLabel` + `lastRun`) + explicit
    "Run routine" action per wireframe `01`.
3.2 On Enter → `POST /api/dashboard/routines/run` `{fnId}` as a **same-origin fetch** (Origin-header
    check via `validateOrigin`; no CSRF token). Branch on **`res.status`**: `202` → inline success;
    `409` (`body.error === "confirmation_required"`) → surface a confirm modal **layered above the
    palette**, re-POST `{fnId, confirmed:true}`; `400`/`502` (`body.error`) → inline error + Sentry
    (intentionally stricter than `routines-surface.tsx`, which swallows non-409). Palette stays open
    until resolved (FR3/G1/G11). v1 keeps the feedback minimal (fire → await → inline success/error
    + confirm); optimistic "Dispatching…" / "view run" deep-link are deferred polish.

### Phase 4 — Help overlay (?) — FR4 + FR9
4.1 `help-overlay.tsx` (`"use client"`) — searchable cheat-sheet modal (same a11y contract as 2.1).
    Lists ONLY working v1 shortcuts: `⌘K` (palette), `⌘/` (this help), `⌘B` (sidebar), `?` (help),
    `Esc` (close). NO `G`-sequence rows until #5636.
4.2 Help opens via `⌘/` (canonical, WCAG-exempt) and `?` (alias, only when no text input focused).
4.3 WCAG SC 2.1.4 (FR9): global listener honors a `shortcutsEnabled` preference (localStorage,
    default `true`) — the "turn off" mechanism — surfaced as a single Settings toggle.

### Phase 5 — Flag + tests
5.1 Gate both surfaces behind a Flagsmith runtime flag `command-palette` (default OFF, dev-cohort)
    via `useFeatureFlag()` — create with `soleur:flag-create command-palette` (dev+prd OFF). (TR5;
    confirm with operator — recommended for staged rollout.)
5.2 Component tests in `apps/web-platform/test/` (`.test.tsx`, happy-dom): open/close + suppression,
    grouped contents, empty/loading/error states, routine 202/409/error handling, focus restore,
    `?`-in-input types literal, help-overlay shortcut list.
5.3 Registry unit tests in `apps/web-platform/test/` (`.test.ts`).

## Files to Create
- `apps/web-platform/components/command-palette/nav-items.ts` — shared `NAV_ITEMS`/`ADMIN_NAV_ITEMS` (extracted from layout)
- `apps/web-platform/components/command-palette/use-shortcuts.tsx` — provider + flat registry + global listener + `isEditable()` + `shortcutsEnabled`
- `apps/web-platform/components/command-palette/command-palette.tsx` — `cmdk` palette modal
- `apps/web-platform/components/command-palette/help-overlay.tsx` — `?` cheat-sheet (shares the palette's dialog/focus-trap primitive, not a parallel a11y impl)
- `apps/web-platform/test/command-palette.test.tsx`, `help-overlay.test.tsx`, `shortcuts-registry.test.ts`

## Files to Edit
- `apps/web-platform/lib/feature-flags/server.ts` — add `command-palette` to `RUNTIME_FLAGS` (Phase 0)
- `apps/web-platform/app/(dashboard)/layout.tsx` — mount provider; import nav-items; migrate ⌘B (204–221) + drawer Esc (192–201) into registry
- `apps/web-platform/package.json` + `bun.lock` — add `cmdk`
- `apps/web-platform/components/settings/…` — single "Enable keyboard shortcuts" toggle (FR9; localStorage — a deliberate device-local a11y pref, NOT account state, so it diverges from the server-persisted toggle pattern by design)
- `.env.example` / Flagsmith / Doppler — `command-palette` flag (via `soleur:flag-create`)

## Open Code-Review Overlap
1 open scope-out touches a planned file: **#2193** (unify billing past_due/unpaid banners + extract
`useDismissiblePersistent`) references `app/(dashboard)/layout.tsx`. **Acknowledge** — different
concern (billing-banner dedup vs. keyboard registry); the overlap is the shared file, not the code
region. #2193 remains open; this plan touches only the keydown-handler + provider-mount regions.

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carry-forward from brainstorm Phase 0.5)

### Engineering
**Status:** reviewed (carry-forward). Central registry as single source of truth; `cmdk` palette;
client-only (SSR/hydration safe); migrate scattered bindings; registry doubles as the future agent
action surface (do not bypass the action layer). v1 = registry + palette + overlay; defer
rebinding/scoped-maps/mobile.

### Legal
**Status:** reviewed (carry-forward). WCAG SC 2.1.4 is the one compliance item — `?` is in scope;
satisfied via `⌘/` exempt binding + `shortcutsEnabled` turn-off (FR9). IP risk of mimicking
Linear's binding scheme negligible; do not copy Linear help-text/branding.

### Product/UX Gate
**Tier:** blocking (mechanical UI-surface override — new `components/command-palette/*.tsx`)
**Decision:** reviewed
**Agents invoked:** spec-flow-analyzer (this plan), cpo (brainstorm carry-forward), ux-design-lead (brainstorm Phase 3.55 — `.pen` committed)
**Skipped specialists:** none
**Pencil available:** yes (wireframes `01`+`02` committed at `knowledge-base/product/design/command-palette/`)

#### Findings
spec-flow-analyzer surfaced 11 gaps; G1–G8 folded into FRs above (routine feedback/409 confirm,
KB error state, `?`-in-input, empty/loading/focus-restore/stacking, wireframe-vs-NG2 conflict).
G9 (mobile entry) deferred per NG4. G10/G11 folded into FR3.

## Architecture Decision (ADR/C4)

### ADR — deferred to #5638 (no ADR in v1)
**No ADR in v1.** v1 is a UI command list + a library choice (`cmdk`), not a new substrate,
ownership/tenancy boundary, or cross-cutting invariant — a competent engineer reading the existing
ADRs/C4 would not be misled by it (the Phase 2.10 skip test). The architectural decision worth an
ADR is *"the command registry is the unified user **and agent** action surface"* — but that
invariant only becomes real when agents are wired (**#5638**). ADR authoring is therefore an
in-scope deliverable of **#5638**, not this PR (avoids an ADR for an array; per plan-review).
v1 keeps a flat registry array with no agent-surface coupling.

### C4 views
**No `.c4` edit for v1** — verified by reading all three model files
(`diagrams/{model.c4,views.c4,spec.c4}`):
- **External human actors:** none new (`founder` already modeled).
- **External systems/vendors:** none new — `cmdk` is a build-time bundled library, not a runtime
  integration (contrast Resend/Stripe/Anthropic which carry relationship edges).
- **Containers/stores:** palette lives inside the existing `dashboard` container; reads existing
  `/api/kb/tree` + `/api/dashboard/routines` via the already-modeled `dashboard -> api` edge.
- **Access relationships:** unchanged — agents not wired in v1 (no new agent↔registry edge).
- **Views:** no component-level view exists for the webapp/dashboard (only the Soleur Plugin has an
  L3 view); the registry is below the model's webapp granularity.

### Sequencing
No ADR/C4 change in this PR. When **#5638** wires agents to the registry, that PR authors the ADR
(unified user+agent action surface) and adds the agent↔registry C4 access edge.

## Observability

```yaml
liveness_signal:
  what: "command-palette flag-gated render + ⌘K open event (client)"
  cadence: on-demand (user-triggered)
  alert_target: none (UI surface; no liveness alert)
  configured_in: "Flagsmith command-palette flag; component mount"
error_reporting:
  destination: "client Sentry (Sentry.captureException) on command run failure"
  fail_loud: true (inline error row + Sentry; never a silent dead row)
failure_modes:
  - mode: "routine dispatch fails (400/502/dispatch_failed/CSRF)"
    detection: "non-202/409 response from /api/dashboard/routines/run"
    alert_route: "inline error + Sentry.captureException with fnId tag"
  - mode: "/api/kb/tree or /api/dashboard/routines fetch fails"
    detection: "non-200 / needsReconnect:true"
    alert_route: "inline group message; Sentry breadcrumb (non-fatal)"
  - mode: "shortcut fires inside a text input (suppression regression)"
    detection: "component test asserts suppression; no runtime alert"
    alert_route: "test-gate (apps/web-platform/test)"
logs:
  where: "browser console (dev) + client Sentry (prd)"
  retention: "Sentry default"
discoverability_test:
  command: "open palette → run a routine that returns 502 in dev; confirm Sentry receives the event (no ssh)"
  expected_output: "Sentry event with fnId tag and 'routine dispatch failed' message"
```

## Infrastructure (IaC)
None — pure client-side code + one bundled npm dependency (`cmdk`). No new server, secret (the
`command-palette` flag is a Flagsmith/Doppler runtime flag created via the existing `flag-create`
path, not new infra), DNS, or runtime process.

## GDPR / Compliance Gate
Considered, skipped: the palette adds no regulated-data surface — it consumes existing,
already-authorized read endpoints (`/api/kb/tree`, `/api/dashboard/routines`) and navigates; no
new schema/migration/auth/API route, no new processing activity, no new distribution surface. The
`single-user incident` threshold (trigger b) is acknowledged, but the feature moves no data across
a controller boundary. (If `/work` adds any new server route, re-run `/soleur:gdpr-gate`.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1: `cmdk` in `apps/web-platform/package.json`; `bun install --frozen-lockfile` clean.
- [ ] AC2: `⌘K`/`Ctrl+K` opens the palette from a dashboard route; `Esc` closes; focus restores to the prior element.
- [ ] AC3: Shortcuts are suppressed while focus is in input/textarea/contenteditable INCLUDING the palette's own search input (`?` types a literal `?` there).
- [ ] AC4: Palette renders all four groups; Navigation includes admin-gated items only when `isAdmin`.
- [ ] AC5: Empty query shows "Ask an agent about '<q>'" fallback → `/dashboard/chat/new`.
- [ ] AC6: KB `needsReconnect`/`503`/`500` renders an inline KB-group message without breaking other groups; loading skeleton shown during fetch.
- [ ] AC7: "Run routine" does a same-origin POST to `/api/dashboard/routines/run` (no CSRF token); branches on `res.status` — `202` success, `409` → confirm modal then re-POST `confirmed:true`, `400`/`502` → inline error + Sentry.
- [ ] AC8: Existing `⌘B` toggle works via the registry with no double-fire (grep layout.tsx shows the old standalone `handleToggleShortcut` removed/migrated); `NAV_ITEMS` imported from the shared `nav-items.ts`.
- [ ] AC9: Help overlay opens via `⌘/` and guarded `?`; lists ONLY `⌘K`/`⌘/`/`⌘B`/`?`/`Esc` (no `G`-sequence rows).
- [ ] AC10: A "Enable keyboard shortcuts" toggle (default on) disables the global listener when off (WCAG SC 2.1.4 turn-off).
- [ ] AC11: `command-palette` is in `RUNTIME_FLAGS` (`lib/feature-flags/server.ts`); both surfaces are flag-gated.
- [ ] AC12: Component/registry tests live under `apps/web-platform/test/` (`.test.tsx`/`.test.ts`) and pass via the package's vitest runner.
- [ ] AC13: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.

### Post-merge (operator)
- [ ] AC14: `soleur:flag-create command-palette` (dev+prd OFF) if not created pre-merge; flip dev cohort ON to validate. (`Automation: feasible` via flag-create skill.)

## Test Scenarios
1. ⌘K open → type "inbox" → Enter → routes to `/dashboard/inbox`; focus restored on close.
2. Focus chat input → press ⌘K → palette does NOT open (suppressed); press ⌘K from body → opens.
3. Palette open → type "?" in search → literal `?` entered, help does NOT open.
4. KB tree returns `needsReconnect` → KB group shows reconnect row; Navigation still works.
5. "Run routine" on a protected routine → 409 → confirm modal above palette → confirm → 202 success.
6. Toggle "Enable keyboard shortcuts" OFF → ⌘K and ? no longer fire.
7. ⌘B still toggles the sidebar (migrated), no double-fire.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6 — this one is filled (carry-forward).
- `cmdk`'s `Command.Dialog` provides most of the modal a11y contract, but verify focus-trap +
  `inert={open||undefined}` (React 19 boolean inert) against the existing custom-modal patterns;
  do NOT assume cmdk restores focus — capture/restore `document.activeElement` explicitly.
- Component tests MUST be `apps/web-platform/test/**/*.test.tsx` — a co-located test is silently
  skipped by the vitest happy-dom project glob.
- The help-overlay wireframe `02` shows NG2-deferred `G`-sequences; build to FR4 (working shortcuts
  only), not to the aspirational wireframe rows.
