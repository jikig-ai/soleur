---
title: "Postmortem: LikeC4 Code-tab Save committed an empty model + suppressed the staleness banner (exit-0-isn't-proof)"
date: 2026-06-05
incident_pr: 4967
incident_window: "2026-06-05 ~11:42Z (PR #4965 Layer-2 re-render deployed) → 2026-06-05 (PR #4967 hardening merged same day)"
recovery_at: "2026-06-05"
suspected_change: "PR #4965 (Layer 2) — renderC4Model/runLikeC4 in server/c4-render.ts keyed render success on `child.exitCode === 0`. `likec4 export json` exits 0 even on unresolved-reference validation errors (empty-elements model), so an invalid export was treated as success, committed over the prior model, and reported rerendered:true."
brand_survival_threshold: aggregate pattern
status: resolved
triggers:
  - c4 diagram blank after save
  - staleness banner missing
  - empty model committed
  - likec4 exit 0 unresolved reference
  - render success keyed on exit code only
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — correctness/availability defect in a dev-cohort-gated feature; the affected artifact is a generated diagram-model JSON file (architecture diagram), not personal data. No exposure or breach."
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `human` — Operator did this directly.

# Incident Overview

The LikeC4 visualizer's Code-tab Save (shipped ~2 hours earlier in PR #4965, Layer 2) re-rendered the diagram by spawning `likec4 export json` and keying success on the CLI's exit code. `likec4` **exits 0 even when the source has unresolved references**, emitting an empty-elements model. So an empty/invalid export was (1) reported as `rerendered:true`, suppressing the honest Layer-1 staleness banner, and (2) committed over the previously-good `model.likec4.json` — a latent silent-data-loss path. The founder, dogfooding the deployed feature, saw a blank diagram with no banner and reported it. Root-caused and fixed the same day (PR #4967). Feature is gated behind the `c4-visualizer` dev-cohort flag — no GA users affected.

## Status

resolved — PR #4967 (render-to-temp + validate ≥1 element + atomic publish + honest diagnostic) merged the same day.

## Symptom

After editing `model.c4` and clicking Save, the rendered diagram did not update AND the "diagram may be out of date" banner (present since Layer 1) was gone — strictly worse than before the Layer-2 ship. The save reported success.

## Incident Timeline

- **Start time (detected):** 2026-06-05 (shortly after the ~11:42Z Layer-2 deploy)
- **End time (recovered):** 2026-06-05 (PR #4967 merged same day)
- **Duration (MTTR):** ~hours (same-day)

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-06-05 ~11:42Z | PR #4965 (Layer 2 re-render) deployed; renderC4Model keys success on exit code 0. |
| human | 2026-06-05 | Founder dogfoods: edits a `.c4`, Saves, sees blank diagram + no banner. Reports it. |
| agent | 2026-06-05 | Reproduced against real `likec4@1.50.0`: unresolved-ref source → exit 0 + `elements:{}`. Confirmed the founder's repo was also missing `spec.c4`/`views.c4` (separate data fix, applied to their repo). |
| agent | 2026-06-05 | PR #4967: render-to-temp + element-count validation + atomic publish + `io_error`/`empty_model` split + sanitized diagnostic surfaced to UI + Concierge tool. Merged same day. |

## Detection (+ MTTD)

- **How detected:** external/manual — founder dogfooding the deployed feature (not an automated monitor). The `reportSilentFallback` telemetry that WOULD have caught a render failure never fired, because the empty export was (incorrectly) treated as success — the defect masked its own signal.
- **MTTD:** ~hours (same-day, on first dogfood).

## Triggered by

system — a third-party CLI (`likec4 export json`) whose exit code does not reflect validation success.

## Root cause (5 Whys)

1. **Why did the diagram go blank?** The committed `model.likec4.json` had zero elements.
2. **Why was an empty model committed?** `rerenderAndCommit` committed whatever `renderC4Model` returned as success.
3. **Why did renderC4Model report success on an empty model?** It keyed success on `child.exitCode === 0`.
4. **Why was exit 0 insufficient?** `likec4 export json` exits 0 even on unresolved-reference validation errors (it prints them to stderr and writes an empty-elements model).
5. **Why wasn't this caught before ship?** The Layer-2 tests mocked `renderC4Model` / asserted exit-code behavior; none exercised the real CLI's exit-0-on-empty behavior, and the planning feasibility check ran the CLI against a VALID model only (which exits 0 with a full model), so the exit-0-on-INVALID case was never observed.

## Resolution

Render to a `mkdtemp` temp path, parse it, and treat exit-0 as success only when the model has ≥1 element (after confirming `elements` is a non-empty plain object). Publish atomically (copy-to-same-dir-stage + `rename`) so an invalid render never clobbers the good model. Split `io_error` (our mkdtemp/parse/copy) from `empty_model` (the user's source). Surface a sanitized, capped diagnostic to the save message and the Concierge tool.

## Follow-ups

- None requiring a separate issue. The generalizable lesson is captured as a learning: `knowledge-base/project/learnings/best-practices/2026-06-05-external-cli-exit-0-is-not-proof-validate-the-artifact.md` (an external CLI's exit code is a claim, not a proof — validate the artifact). The test-timing gotcha discovered while fixing is routed to the work skill's spawn-mock guidance.

## Prevention

- The new `c4-render.test.ts` empty-elements test (exit 0 + `elements:{}` → `empty_model` + no copy) is the regression gate; it would have failed against the Layer-2 code.
- Broader pattern (in the learning): when shelling out to a tool whose output you trust/commit, validate the produced artifact against a structural invariant and capture stderr on success too.
