---
title: "Fix: LikeC4 code-editor Save is a no-op — diagram never re-renders after edit"
type: fix
date: 2026-06-05
lane: cross-domain
brand_survival_threshold: none
---

# Fix: LikeC4 code-editor Save is a no-op — diagram never re-renders after edit

## Enhancement Summary

**Deepened on:** 2026-06-05

### Key Improvements

1. Verified the load-bearing negative claim ("no runtime re-layout possible")
   against installed deps — confirmed `@likec4/core`/`@likec4/diagram` ship no
   parser and no layout engine, so Layer 2 must be out-of-process.
2. De-risked Layer 2 B1 by confirming the Inngest child-process-spawn precedent
   (ADR-033) + `inngest.tf` root + event-triggered function exemplars exist.
3. Verified both write surfaces (UI Save + Concierge `edit_c4_diagram`) carry the
   same false "re-renders" claim, and confirmed the exact source-string literals
   the ACs grep for (`c4-shared.tsx:224`, `c4-concierge-tools.ts:54`).

### New Considerations Discovered

- The wireframe gate (Phase 4.9) fires on `components/kb/*.tsx` but resolves via
  the Excluded "pure copy tweak" carve-out by **reusing the existing
  `C4Diagnostics` banner** — no new visual surface. This shaped the design to
  avoid inventing a new banner component.
- Added the required `threshold: none, reason: …` scope-out bullet because two
  touched files live under `apps/web-platform/server/` (sensitive-path regex).

## Overview

In the new LikeC4 C4-model visualizer (`/dashboard/kb/...` C4 workspace + inline
markdown embed), the **Code** tab exposes an editable `.c4` source panel with a
**Save** button. After editing the source and clicking Save, the user observes
"nothing changed — it just reloads but nothing is modified." The diagram on the
left is visually identical to before the edit.

The root cause is a **two-artifact split** baked into the architecture: the
diagram renders from a *precomputed, layouted* `model.likec4.json`, while Save
writes only the raw `.c4` *source*. The layouted JSON is regenerated
**exclusively out-of-band** via `/soleur:architecture render` (which runs the
heavy `likec4 export json` CLI) — never at runtime, by deliberate design (the
`likec4` toolchain pulls vite/esbuild into prod deps and breaks the
npm10/npm11 lockfile parity that prod `npm ci` + `lockfile-sync` require). So
Save → reload re-reads the edited source into the editor, but the rendered
diagram reads the **stale** `model.likec4.json` and is unchanged.

This is a genuine behavioral gap, not a never-built feature: the UI, PUT route,
writer, GitHub commit, and workspace-sync all exist and work — the `.c4` source
*is* committed and *does* land on disk. The only thing that does not happen is
re-layout of the rendered model.

## Problem Statement / Motivation

The current behavior is actively misleading on **two** write surfaces:

1. **UI Save button** (`C4CodePanel`, used by both `c4-workspace.tsx` and the
   inline `c4-diagram.tsx`): shows `"Saved — re-rendering…"` then reloads to an
   unchanged diagram. The "re-rendering…" copy is a lie — nothing re-renders.
2. **Concierge `edit_c4_diagram` MCP tool** (`c4-concierge-tools.ts`): its tool
   description tells the model *"Commits directly to the repo and the diagram
   re-renders — do not paste DSL into chat for the user to apply."* This is the
   same false claim, so the Concierge confidently tells users their diagram
   updated when it did not.

A save action that silently fails to produce its advertised visible effect is a
trust-eroding UX bug. The fix must make the system **honest** at minimum, and
ideally make the diagram actually update.

## Confirmed Root Cause (code-level)

| Step | File / behavior | Effect |
|------|-----------------|--------|
| User edits source, clicks Save | `c4-shared.tsx` `C4CodePanel.save()` → `PUT /api/kb/c4/<dir>/<file>` | sends edited `.c4` text |
| Server persists | `app/api/kb/c4/[...path]/route.ts` → `server/c4-writer.ts` `writeC4Diagram()` | commits `.c4` to GitHub Contents API, then `syncWorkspace()` pulls the clone → **source updated on disk** ✅ |
| Client reloads | `onSaved` → `useC4Project.reload()` → `GET /api/kb/c4/project?dir=…` | re-fetches `{ sources, dump }` |
| Server returns project | `app/api/kb/c4/project/route.ts` | returns updated `sources` ✅ **but stale `dump` = `model.likec4.json`** ❌ |
| Diagram re-renders | `c4-shared.tsx` `C4Canvas` `useMemo([dump])` → `LikeC4Model.create(dump)` | dump unchanged → **diagram identical** ❌ |

The client wiring is correct (`reload()` does re-fetch and `C4Canvas` does
re-memo on `dump`). The gap is **entirely server-side**: `model.likec4.json` is
never regenerated from the edited source at request time.

## Research Insights (deepen-plan 2026-06-05)

**Verify-the-negative pass (Phase 4.45):** The plan's load-bearing negative claim
— "runtime re-layout is NOT achievable with current prod deps" — was re-verified
against `apps/web-platform/package.json`: only `@likec4/core@1.50.0` and
`@likec4/diagram@1.50.0` (+ `@likec4/styles`) are present; **no** `@likec4/layouts`
(layout engine) and **no** `@likec4/language-services` (DSL parser). Claim HOLDS.
`@likec4/core` exports (`./builder`, `./compute-view`, `./geometry`, `./model`)
confirm no text-parser and no auto-layout. Layer 2 out-of-process is the only path.

**Precedent-diff gate (Phase 4.4):** Layer 2 B1 (Inngest function shelling out to
`npx -y likec4@latest`) has a direct repo precedent —
`ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn` plus
the event-triggered functions `agent-on-spawn-requested.ts` and
`cfo-on-payment-failed.ts`. The CLI-in-child-process pattern is canonical, so
Layer 2 B1 introduces no novel mechanism. `apps/web-platform/infra/inngest.tf`
exists as the Terraform root. (Note: three files share the `ADR-033-` prefix in
`decisions/` — a known mis-numbering quirk; the child-process-spawn one is the
relevant precedent.)

**Both write surfaces share the bug (Phase 1 discovery, carried forward):** the UI
`C4CodePanel` AND the Concierge `edit_c4_diagram` tool both funnel through
`writeC4Diagram` and both falsely imply the diagram re-renders. Fixing only the UI
would leave the Concierge tool lying to the model. Layer 1 covers both surfaces.

**Premise Validation:** All cited artifacts verified live — `c4-shared.tsx`,
`c4-workspace.tsx`, `c4-diagram.tsx`, `c4-writer.ts`, `c4-concierge-tools.ts`,
both API routes, `c4-constants.ts`, `inngest.tf`, and the ADR all exist on the
branch. PRs #4883/#4925/#4926 confirmed via `git log` as the "new implementation."
No external premises were stale.

## Constraint that bounds the fix (verified against installed deps)

Runtime re-layout is **not** achievable with the current production
dependencies — this is a hard constraint, not an oversight:

- `apps/web-platform/package.json` ships only `@likec4/core@1.50.0`,
  `@likec4/diagram@1.50.0`, `@likec4/styles` — **no DSL parser** (lives in
  `@likec4/language-services`) and **no layout engine** (lives in
  `@likec4/layouts`).
- `@likec4/core` exposes `./builder`, `./compute-view`, `./geometry`, `./model`
  — a *programmatic* model builder and view-computation, but **no `.c4` text
  parser** and **no auto-layout**. `LikeC4Diagram` renders a pre-layouted view
  (`vm.$view` carries x/y/width/height); it does not lay out.
- `lib/c4-constants.ts` and `app/api/kb/c4/project/route.ts` both document the
  deliberate exclusion of the heavy toolchain "DELIBERATELY does NOT compute
  layout at runtime" to preserve lockfile parity.

So "just re-run the layout in the route handler" is off the table. The plan must
either (a) make the UX honest, or (b) regenerate the layouted JSON
**out-of-process** (not in the Next prod bundle).

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report) | Reality (code-verified) | Plan response |
|---|---|---|
| "new implementation of likec4" | Confirmed: #4883 replaced Mermaid; #4925 added workspace/Code split; #4926 added Concierge edit tool | Correct premise; fix targets this implementation |
| "Save … nothing change, just reloads" | Save **does** persist the `.c4` source to GitHub + disk; the *diagram* (`model.likec4.json`) is stale | Behavioral fix, not a build-from-scratch |
| Implied: "Save should update the diagram" | Runtime re-layout impossible with installed deps (no parser, no layout engine) | Fix space constrained to honest-UX or out-of-process re-render |

## Proposed Solution

Two layers, shippable independently. **Layer 1 is the minimum honest fix and is
mandatory; Layer 2 is the "actually re-render" fix and is the recommended scope
but carries an infra decision** the plan defers to the Alternatives section.

### Layer 1 (mandatory) — make the system honest

1. **UI:** After a successful Save, surface a truthful state. The diagram cannot
   re-render in-browser, so instead of `"Saved — re-rendering…"`:
   - Show `"Source saved. Diagram refreshes after re-render (run /soleur:architecture render)."`
     (or equivalent), and
   - Detect staleness: compare the edited source's identity against the model
     the diagram was built from. A cheap, honest signal: after save, surface a
     persistent "Source edited — rendered diagram may be out of date" message.
     **This MUST reuse the existing `C4Diagnostics` banner** (already shipped,
     already occupying the warning slot above the canvas with the same visual
     treatment) by feeding it an additional diagnostic-style message — NOT a new
     banner/overlay/modal/toast component. No new visual surface, no layout
     change: this keeps Layer 1 a pure copy + content change to existing
     components (per the wireframe-gate Excluded list — "Pure copy or style
     tweaks with no structural/layout change"). The diagram pane geometry is
     unchanged; only the text content of an already-rendered warning region and
     the Save-button message change.
2. **Concierge tool description:** Correct `c4-concierge-tools.ts` —
   remove/replace the false "the diagram re-renders" clause so the model stops
   telling users their diagram updated. Replace with the accurate contract:
   "Commits the source; the rendered diagram updates after the model is
   re-rendered out-of-band."
3. **Keep `reload()`** — the editor SHOULD reflect the saved source (it already
   does), so the user at least sees their edit persisted in the Code tab.

### Layer 2 (recommended, infra-gated) — actually re-render

Regenerate `model.likec4.json` from the edited `.c4` sources **out-of-process**,
then commit it alongside the source so the next `GET /project` returns a fresh
`dump`. This is the only way to make the diagram visibly update. See
**Alternative Approaches** + **Infrastructure (IaC)** for the three candidate
mechanisms and the decision the plan author/operator must make. If Layer 2 is
deferred, file a tracking issue (per `wg-when-deferring-a-capability-create-a`).

## Technical Considerations

- **Both write surfaces share `writeC4Diagram`** — Layer 2's re-render trigger,
  if added server-side, belongs in or adjacent to `writeC4Diagram` so the UI
  Save and the Concierge tool both benefit (single funnel, mirrors the existing
  scope-guard funnel design).
- **`@likec4/diagram` is browser-only** (`ssr: false`); none of the Layer 1 work
  changes that.
- **No new dependencies in the Next prod bundle** — adding the `likec4` CLI to
  prod deps is explicitly rejected by the existing architecture; any Layer 2
  re-render must run the CLI via `npx -y likec4@latest` in a separate process /
  job, not as a prod import.
- **NFR impact:** assess latency (a synchronous in-request re-layout would add
  multi-second blocking — another reason Layer 2 is async/out-of-process) and
  the existing `MAX_C4_BYTES` / `MAX_C4_WRITE_BYTES` caps remain unchanged.

## User-Brand Impact

- **If this lands broken, the user experiences:** the Code-tab Save button on the
  C4 visualizer continues to claim success ("Saved — re-rendering…") while the
  diagram silently stays stale, OR the new banner/copy misfires and shows a
  "stale" warning when the diagram is actually current.
- **If this leaks, the user's data is exposed via:** N/A — no new data surface.
  The write path already commits only to the diagrams dir under the strict
  `isC4DiagramPath` scope guard; this fix does not touch auth, scope, or PII.
- **Brand-survival threshold:** `none`

`threshold: none, reason: the touched server/ files (c4-writer.ts, c4-concierge-tools.ts) only correct a tool-description string and—at Layer 2—trigger an out-of-process re-render; they add no new data exposure, auth, scope, or PII surface beyond the existing isC4DiagramPath-guarded write path.`

*This is a UX-honesty + optional re-render fix on an existing, scope-guarded
write path. No new exposure vector; threshold `none`. The touched paths
(`components/kb/*`, `app/api/kb/c4/*`, `server/c4-writer.ts`,
`server/c4-concierge-tools.ts`) are not PII/auth/billing surfaces.*

## Observability

```yaml
liveness_signal:
  what:            "Sentry breadcrumb/event on c4 save + (if Layer 2) re-render-job completion"
  cadence:         "per-save (user-triggered)"
  alert_target:    "Sentry web-platform issue (operator email on error spike)"
  configured_in:   "apps/web-platform/server/c4-writer.ts (existing Sentry.captureException + logger.info event:c4_write)"

error_reporting:
  destination:     "Sentry web-platform via SENTRY_DSN (existing in c4-writer.ts and project/route.ts)"
  fail_loud:       "PUT returns non-2xx with {error,code}; UI renders saveMsg with the error; SYNC_FAILED/GITHUB_API_ERROR/SHA_MISMATCH already mapped"

failure_modes:
  - mode:          "Layer 1 staleness banner false-positive (warns stale when diagram is current)"
    detection:     "vitest unit test on the staleness predicate + manual QA both toggle states"
    alert_route:   "caught pre-merge by tests; no runtime page"
  - mode:          "Save succeeds (source committed) but re-render (Layer 2) fails or is absent"
    detection:     "logger.info event:c4_write present without a paired re-render event; Sentry on re-render job error (Layer 2)"
    alert_route:   "Sentry issue → operator email"
  - mode:          "workspace sync fails after commit (pre-existing SYNC_FAILED path)"
    detection:     "Sentry.captureException(sync.error) already in c4-writer.ts"
    alert_route:   "Sentry issue → operator email"

logs:
  where:           "pino structured logs (logger.info/error in c4-writer.ts, project/route.ts) → container stdout → existing aggregator"
  retention:       "per existing web-platform log retention"

discoverability_test:
  command:         "cd apps/web-platform && grep -n 'Saved\\|re-rendering\\|out of date\\|re-render' components/kb/c4-shared.tsx components/kb/c4-workspace.tsx server/c4-concierge-tools.ts"
  expected_output: "no remaining 'Saved — re-rendering…' false-success string; staleness/out-of-date copy present; concierge tool description no longer claims 'the diagram re-renders'"
```

## Acceptance Criteria

### Layer 1 (mandatory)

- [ ] The `"Saved — re-rendering…"` string in `C4CodePanel` (`c4-shared.tsx`) is
      replaced with copy that does NOT claim the diagram re-renders; the new copy
      states the source was saved and the diagram updates after re-render.
- [ ] After a successful Save, the diagram pane shows a persistent
      "source edited — rendered diagram may be out of date" indicator that clears
      when a fresh model is loaded. The indicator MUST reuse the existing
      `C4Diagnostics` banner (no new banner/overlay/modal/toast component — no new
      structural/layout surface). Verified in BOTH the full workspace
      (`c4-workspace.tsx`) AND the inline embed (`c4-diagram.tsx`), which share
      `C4CodePanel`.
- [ ] The Concierge `edit_c4_diagram` tool description in
      `server/c4-concierge-tools.ts` no longer asserts "the diagram re-renders";
      it states the source is committed and the rendered diagram updates after
      out-of-band re-render.
- [ ] No regression: the `.c4` source still commits to GitHub and the edited
      source is visible in the Code tab after reload (existing PUT → write →
      sync → reload path unchanged).
- [ ] `tsc --noEmit` clean; vitest suite green (`c4-workspace.test.tsx`,
      `c4-concierge-tools.test.ts` updated for new copy/description).

### Layer 2 (recommended — implement OR defer with a tracking issue)

- [ ] EITHER: editing a `.c4` source and saving causes the rendered diagram to
      reflect the change after the out-of-process re-render completes (mechanism
      chosen per Alternatives), with `model.likec4.json` regenerated and
      committed; OR: a tracking issue is filed capturing the deferred re-render
      capability, the chosen-deferred rationale, and re-evaluation criteria.
- [ ] If implemented: the re-render runs out-of-process (no `likec4`/vite/esbuild
      added to the Next prod bundle; lockfile parity preserved — verify
      `package.json` prod deps unchanged for the `likec4` CLI).

## Test Scenarios

- Given an edited `.c4` source, when the user clicks Save and the PUT succeeds,
  then the Code tab shows the saved source AND the diagram pane shows the
  "may be out of date" indicator AND no "re-rendering…" false-success copy
  appears.
- Given a freshly loaded C4 page (no edit), when it renders, then the staleness
  indicator is absent (no false-positive). Verify in both the workspace split
  and the inline embed.
- Given the Concierge `edit_c4_diagram` tool, when its description is read, then
  it does not promise "the diagram re-renders."
- Regression: Given a save, when `writeC4Diagram` commits + syncs, then the
  `.c4` source on disk and in the reloaded Code tab matches the edit (existing
  behavior preserved).
- **Browser (QA):** Navigate to a C4 KB page → Code tab → edit a label in the
  `.c4` source → Save → verify (a) editor shows the edit, (b) staleness banner
  appears, (c) no "re-rendering…" copy. (Layer 2, if shipped: wait for re-render,
  reload, verify diagram reflects the edit.)

## Dependencies & Risks

- **Risk:** Layer 1 staleness detection must be honest in BOTH toggle states
  (banner present after edit / absent on fresh load) — a false-positive banner is
  itself a UX regression. Mitigate with explicit tests for both states (per the
  "verify both toggle states" learning).
- **Risk (Layer 2):** Any out-of-process re-render that runs the `likec4` CLI
  must not regress lockfile parity — the entire reason layout is out-of-band.
- **Dependency:** Layer 2's "commit regenerated `model.likec4.json`" reuses the
  GitHub Contents API + `syncWorkspace` path already in `c4-writer.ts`.

## Alternative Approaches Considered

| Approach | Mechanism | Verdict |
|---|---|---|
| **A. Honest UX only (Layer 1)** | Truthful copy + staleness banner; no re-render | **Mandatory baseline.** Cheapest, removes the lie. Diagram still won't auto-update. |
| **B. Out-of-process re-render job (Layer 2)** | After commit, enqueue a job that runs `npx -y likec4@latest export json`, commits the regenerated `model.likec4.json`, re-syncs | **Recommended if infra allows.** Makes the diagram actually update. Requires a job runner / worker (see Infrastructure). Async — UI polls or shows "rendering…" honestly. |
| **C. Add layout deps to prod bundle, re-layout in-request** | Import `@likec4/language-services` + `@likec4/layouts` into the route | **Rejected.** Directly violates the documented lockfile-parity constraint; the whole architecture exists to avoid this. |
| **D. Client-side layout via @likec4/core builder** | Build + lay out in-browser from sources | **Rejected.** `@likec4/core` ships no DSL parser and no auto-layout; would require pulling the heavy parser/layout into the client bundle. |

**If Layer 2 (Approach B) is deferred:** file a tracking issue with the deferred
re-render capability, rationale (infra decision pending), and re-evaluation
criteria; reference the milestone from `knowledge-base/product/roadmap.md`.

## Files to Edit

- `apps/web-platform/components/kb/c4-shared.tsx` — `C4CodePanel.save()` success
  copy (remove "re-rendering…" lie); add staleness signal plumbing; possibly
  `C4Diagnostics` host for the banner.
- `apps/web-platform/components/kb/c4-workspace.tsx` — wire staleness banner into
  the diagram pane (full workspace).
- `apps/web-platform/components/kb/c4-diagram.tsx` — wire staleness banner into
  the inline embed (shares `C4CodePanel`).
- `apps/web-platform/server/c4-concierge-tools.ts` — correct the
  `edit_c4_diagram` tool description's false "the diagram re-renders" claim.
- `apps/web-platform/test/c4-workspace.test.tsx` — assert new copy + staleness
  banner in both states.
- `apps/web-platform/test/c4-concierge-tools.test.ts` — assert corrected tool
  description.
- **(Layer 2 only)** `apps/web-platform/server/c4-writer.ts` — enqueue/trigger the
  out-of-process re-render after a successful commit+sync.
- **(Layer 2 only)** re-render job definition (location depends on chosen
  mechanism — see Infrastructure).

## Files to Create

- None for Layer 1.
- (Layer 2, if implemented) a re-render job/worker module — exact path TBD by the
  chosen mechanism in the Infrastructure section.

## Open Code-Review Overlap

None — checked: no open `code-review`-labelled issues touch
`components/kb/c4-*.tsx`, `server/c4-writer.ts`, `server/c4-concierge-tools.ts`,
or `app/api/kb/c4/*` at plan time. (If Layer 2 introduces a worker, re-run the
overlap check at /work time against the new file paths.)

## Domain Review

**Domains relevant:** Product (UI behavior)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — this fix modifies the existing C4 Code-tab Save
behavior. It creates no new page, route, or interactive surface (no new
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` file), so the
mechanical UI-surface override resolves to ADVISORY, not BLOCKING.
**Pencil available:** N/A (no new UI surface)

**Wireframe gate (`wg-ui-feature-requires-pen-wireframe` / deepen-plan Phase
4.9):** The glob superset matches `components/kb/*.tsx`, but the change falls
under the gate's own **Excluded** carve-out — "Pure copy or style tweaks with no
structural/layout change." The two Layer-1 changes are (a) the Save-button
success-message string and (b) feeding an additional diagnostic message into the
**already-shipped** `C4Diagnostics` banner. No new banner/overlay/modal/toast
component, no layout change, no new interactive surface. Therefore no `.pen`
wireframe is required. (If implementation deviates to a NEW visual component,
the gate re-fires and a wireframe must be produced — re-check at /work Check-9.)

#### Findings

The change is a copy correction + reusing the existing diagnostics banner with a
new message on an existing pane. UX risk is confined to the staleness-indicator
false-positive case (warns stale when current), covered by the both-toggle-states
test requirement in Acceptance Criteria.

## Infrastructure (IaC)

**Layer 1: no infrastructure.** Pure code change against the already-provisioned
web-platform — edits `components/kb/*`, `server/c4-concierge-tools.ts`, and tests.
No new server, service, secret, vendor, or persistent process.

**Layer 2 (recommended, if implemented): introduces an out-of-process re-render
runtime — defer the mechanism decision to the operator/plan author.** Candidate
mechanisms and their infra implications:

- **B1 — Inngest function** (per `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn`,
  the repo's sanctioned pattern for an Inngest function shelling out to a CLI via
  child-process spawn — directly de-risks running `npx -y likec4@latest` in the
  function process): `writeC4Diagram` emits an event (mirror the existing
  event-triggered functions, e.g. `agent-on-spawn-requested.ts`,
  `cfo-on-payment-failed.ts` under `apps/web-platform/server/inngest/functions/`);
  the function runs `npx -y likec4@latest export json`, commits the regenerated
  `model.likec4.json` via the existing GitHub Contents API path, re-syncs.
  **Preferred** — reuses existing job infra; no new vendor. The `likec4` CLI runs
  in the function process (child-process spawn), NOT in the Next prod bundle,
  preserving lockfile parity.
- **B2 — defer entirely** to `/soleur:architecture render` as today, and ship
  only Layer 1. No infra. (File the tracking issue.)

**Decision required before Layer 2 implementation:** B1 (Inngest re-render) vs.
B2 (defer). If B1 is chosen, the `### Terraform changes` / `### Apply path` /
`### Distinctness / drift safeguards` subsections must be filled in at deepen-plan
or /work time against `apps/web-platform/infra/inngest.tf`. **Layer 1 ships with
zero infra regardless of this decision.**

## References & Research

### Internal References

- `apps/web-platform/components/kb/c4-shared.tsx` — `C4CodePanel`, `useC4Project`, `C4Canvas`, `C4Diagnostics`
- `apps/web-platform/components/kb/c4-workspace.tsx:184` — `onSaved={reload}`
- `apps/web-platform/components/kb/c4-diagram.tsx:68-73` — inline embed reuses `C4CodePanel`
- `apps/web-platform/app/api/kb/c4/[...path]/route.ts` — PUT route → `writeC4Diagram`
- `apps/web-platform/app/api/kb/c4/project/route.ts` — GET project (returns stale precomputed `dump`)
- `apps/web-platform/server/c4-writer.ts` — single write funnel (GitHub commit + `syncWorkspace`)
- `apps/web-platform/server/c4-concierge-tools.ts` — `edit_c4_diagram` tool (false "re-renders" description)
- `apps/web-platform/lib/c4-constants.ts` — `C4_MODEL_JSON`, documented runtime-layout exclusion
- `plugins/soleur/skills/architecture/SKILL.md:254-265` — `/soleur:architecture render` regenerates `model.likec4.json`

### Related Work

- #4883 — LikeC4 visualizer replaces static Mermaid
- #4925 — full-screen C4 workspace (diagram ‖ Concierge/Code split)
- #4926 — autonomous `edit_c4_diagram` tool
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` — precedent for an Inngest function shelling out to a CLI via child-process spawn (Layer 2 B1)
- `apps/web-platform/infra/inngest.tf` — Terraform root for Layer 2 B1 (if implemented)
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`, `cfo-on-payment-failed.ts` — event-triggered Inngest function precedents to mirror for Layer 2 B1
