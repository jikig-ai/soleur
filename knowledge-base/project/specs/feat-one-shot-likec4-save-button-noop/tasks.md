---
title: "Tasks — Fix: LikeC4 code-editor Save no-op"
plan: knowledge-base/project/plans/2026-06-05-fix-likec4-code-editor-save-noop-plan.md
lane: cross-domain
date: 2026-06-05
---

# Tasks — Fix: LikeC4 code-editor Save no-op

Derived from `2026-06-05-fix-likec4-code-editor-save-noop-plan.md`. Layer 1 is
mandatory; Layer 2 is recommended-or-defer.

## Phase 1 — Setup & RED (failing tests first)

- [x] 1.1 Read `c4-shared.tsx`, `c4-workspace.tsx`, `c4-diagram.tsx`,
      `c4-concierge-tools.ts` to confirm current behavior before editing.
- [x] 1.2 Write failing test in `test/c4-workspace.test.tsx`: after a successful
      Save, the diagram pane surfaces the "rendered diagram may be out of date"
      message via the existing `C4Diagnostics` banner, AND no "re-rendering…"
      false-success copy is present.
- [x] 1.3 Write failing test: on a fresh load (no edit), the staleness indicator
      is ABSENT (both-toggle-states — guards the false-positive regression).
- [x] 1.4 Update `test/c4-concierge-tools.test.ts` to assert the corrected
      `edit_c4_diagram` description no longer claims "the diagram re-renders".

## Phase 2 — Layer 1 GREEN (mandatory honest fix)

- [x] 2.1 In `c4-shared.tsx` `C4CodePanel.save()`, replace the
      `"Saved — re-rendering…"` literal (currently `c4-shared.tsx:224`) with copy
      that does NOT claim the diagram re-renders (e.g. "Source saved. Diagram
      refreshes after re-render.").
- [x] 2.2 Add a staleness signal: after a successful save, surface a persistent
      "Source edited — rendered diagram may be out of date" message by feeding an
      extra diagnostic into the EXISTING `C4Diagnostics` banner. NO new
      banner/overlay/modal/toast component (preserves the pure-copy-tweak status —
      no new visual surface; wireframe gate stays satisfied).
- [x] 2.3 Wire the staleness signal through `c4-workspace.tsx` (full workspace)
      AND `c4-diagram.tsx` (inline embed) — both share `C4CodePanel`.
- [x] 2.4 In `c4-concierge-tools.ts` (the `EDIT_C4_DIAGRAM_TOOL` description,
      currently line ~54), remove the "the diagram re-renders" clause; replace
      with the accurate contract (commits source; diagram updates after
      out-of-band re-render).
- [x] 2.5 Confirm `reload()` still re-fetches and the saved source shows in the
      Code tab (existing behavior preserved — no regression).

## Phase 3 — Layer 2 decision (implement B1 OR defer B2)

- [x] 3.1 DECISION GATE: choose B1 (Inngest re-render function) or B2 (defer to
      `/soleur:architecture render`). Confirm with operator/plan author.
- [x] 3.2 If B2 (defer): file a tracking issue (deferred re-render capability,
      rationale, re-evaluation criteria, roadmap milestone) per
      `wg-when-deferring-a-capability-create-a`. Skip 3.3–3.6.
      **DECISION: B2 (defer). Tracking issue filed: #4964** (label
      `deferred-automation,type/feature`, milestone Post-MVP / Later).
- [ ] 3.3 If B1: add an event-triggered Inngest function under
      `apps/web-platform/server/inngest/functions/` (mirror
      `agent-on-spawn-requested.ts`) that runs `npx -y likec4@latest export json`
      in a child process and commits the regenerated `model.likec4.json` via the
      existing GitHub Contents API path + `syncWorkspace`.
- [ ] 3.4 If B1: emit the re-render event from `c4-writer.ts` after a successful
      commit+sync (covers BOTH the UI Save and the Concierge tool, single funnel).
- [ ] 3.5 If B1: fill the plan's `## Infrastructure (IaC)` Terraform subsections
      against `apps/web-platform/infra/inngest.tf`.
- [ ] 3.6 If B1: verify `package.json` prod deps are UNCHANGED for the `likec4`
      CLI (lockfile parity preserved — CLI runs via `npx`, not a prod import).

## Phase 4 — Verify & ship-prep

- [x] 4.1 `cd apps/web-platform && npx tsc --noEmit` clean.
- [x] 4.2 Run the package's test runner (per `package.json scripts.test` —
      confirm runner before assuming) on `c4-workspace.test.tsx` and
      `c4-concierge-tools.test.ts`; all green.
- [x] 4.3 Discoverability check (no ssh): `grep -n 'Saved\|re-rendering\|out of
      date\|re-render' components/kb/c4-shared.tsx components/kb/c4-workspace.tsx
      server/c4-concierge-tools.ts` — confirm the false-success string is gone and
      the honest copy/description is present.
- [ ] 4.4 Browser QA (per plan Test Scenarios): edit a `.c4` label → Save → verify
      editor reflects edit, staleness indicator appears, no "re-rendering…" copy.
      (B1: wait for re-render, reload, confirm diagram updates.)
- [ ] 4.5 Re-run /work Check-9 (wireframe gate): if implementation deviated to a
      NEW visual component, produce a `.pen` wireframe before shipping.
