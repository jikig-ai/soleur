---
feature: expand-gated-skill-catalog
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
issue: 5704
date: 2026-06-29
branch: feat-expand-gated-skill-catalog
pr: 5719
brainstorm: knowledge-base/project/brainstorms/2026-06-29-expand-gated-skill-catalog-brainstorm.md
parent_brainstorm: knowledge-base/project/brainstorms/2026-06-29-skill-eval-gate-brainstorm.md
related:
  - plugins/soleur/skills/eval-harness/gated-skills.json
  - plugins/soleur/skills/eval-harness/README.md
---

# Spec — Expand gated-skill catalog with golden sets for more classifier surfaces

## Problem Statement

The eval-harness validation gate (#5701/#5702, merged 2026-06-29) is proven on exactly two
classifier surfaces: `soleur:go` intent routing and ticket-triage P-level. The harness was
deliberately built so adding a third surface is cheap and additive (README §"Adding a new
target"). #5704 is the deferred follow-on: bring additional verifiable single-token classifier
surfaces under the gate so edits to their rule prose are regression-checked.

The method only works on classifiers with a **closed enum + a prose rubric the LLM applies**;
subjective/open-ended surfaces are out of scope by construction (parent Decision 4).

## Goals

- Bring **brainstorm lane-inference** (`procedural | single-domain | cross-domain`) under the gate.
- Bring **incident brand_survival_threshold** (`none | single-user incident | aggregate pattern`)
  under the gate. (Originally skill-security-scan; replaced at plan-review — that scanner is
  deterministic `jq` aggregation over YAML rule files, not an LLM-applied prose rubric, so projecting
  its prose is a dishonest gate target. incident Phase 1 criteria IS the LLM-applied rule.)
- Each surface uses the existing additive recipe with **no new assert script**, but DOES edit three
  hardcoded per-target maps (`gen-skill-prompt.cjs TARGET_CONFIG`, `eval-gate.cjs TARGET_RESOURCES`,
  and the `extract-block.test.sh` round-trip loop) — see the plan's Research Reconciliation.
- Deliver as **one PR, two commits** (lane-inference, then incident-threshold).

## Non-Goals

- **pdr-* passive-domain-routing as a multi-label gate.** Deferred (genuinely multi-label;
  needs a set-membership assert). Its single-token output slice is covered by lane-inference.
  Tracked in a separate issue.
- **Wiring any new surface into per-PR CI.** The opt-in validation run stays manual, as for the
  v1 surfaces (the CI-backstop decision is a separate deferred item from the parent brainstorm).
- Any classifier surface beyond the two named (skill-security-scan, gdpr-gate, ux-design-lead, etc.).
- Any change to the shared asserts, `verdict.cjs`, `parse-label.cjs`, or `models.generated.json`.

## Functional Requirements

- **FR1 — lane-inference enum.** Add `enums/lane.json` with the frozen 3-value set
  `["procedural", "single-domain", "cross-domain"]`.
- **FR2 — lane-inference golden set.** Add `tasks/lane-inference.jsonl`, ~6-8 synthesized tasks
  covering each lane at least once **plus adversarial keyword-overlap cases** (a description
  carrying both a `cross-domain` trigger and a `procedural` trigger, to assert the documented
  precedence — `procedural` requires "no `cross-domain` trigger"). Synthesized fixtures only.
- **FR3 — lane-inference arm prompts.** Add `prompts/lane-inference-baseline.txt` (label set
  only) and `prompts/lane-inference-skill.txt` (generated projection of the §Lane Inference
  block via `gen-skill-prompt.cjs`, not hand-copied).
- **FR4 — lane-inference source sentinels.** Wrap the §Lane Inference rule block in
  `brainstorm-domain-config.md` with `<!-- eval-gate:block:lane-inference:start -->` /
  `:end` markers; the projection must round-trip byte-for-byte (AC4 test).
- **FR5 — lane-inference config + registry.** Add `promptfooconfig.lane-inference.yaml`
  mirroring the existing configs, and a `gated-skills.json` row
  (`source_file`, `block_id`, markers, `target`, `projected_prompt_path`).
- **FR6 — incident-threshold enum.** Add `enums/incident-threshold.json` with
  `["none", "single-user incident", "aggregate pattern"]`. (Multi-word labels are
  `parse-label.cjs`-safe — verified.)
- **FR7 — incident-threshold golden set.** Add `tasks/incident-threshold.jsonl`, ~6-8
  synthesized tasks: a no-user-surface internal incident (→ `none`), a single credential/data
  exposure (→ `single-user incident`), a systemic multi-tenant breach (→ `aggregate pattern`),
  **plus a borderline single-vs-aggregate case**. Synthesized fixtures only.
- **FR8 — incident-threshold arm prompts.** Add baseline + generated skill projection of the
  Phase 1 criteria block.
- **FR9 — incident-threshold source sentinels.** Wrap the §Phase 1 — Classification criteria
  block (the 3-tier bullets + intro; exclude the advisory-output example and confirm prompt) in
  `incident/SKILL.md` with `eval-gate:block:incident-threshold` markers; projection round-trips
  byte-for-byte.
- **FR10 — incident-threshold config + registry.** Add
  `promptfooconfig.incident-threshold.yaml` and a `gated-skills.json` row.
- **FR-MAPS — three hardcoded maps per surface.** For BOTH surfaces, add the target to
  `gen-skill-prompt.cjs TARGET_CONFIG` (render + enumPath), `eval-gate.cjs TARGET_RESOURCES`
  (tasks + enumPath — without this the gate path dies fail-closed), and data-drive the
  `extract-block.test.sh` round-trip loop from the registry. Add a registry-coverage consistency
  test asserting every target ∈ both maps.
- **FR11 — opt-in validation run per surface.** Run the harness manually per surface
  (`npx promptfoo eval -c promptfooconfig.<target>.yaml --repeat 3`); record both
  baseline-vs-skill deltas in the single PR body. Disclose the API spend
  (`hr-autonomous-loop-skill-api-budget-disclosure`). Also run the gate path
  (`node scripts/eval-gate.cjs --dry-run --target <t>`, no API) to prove the gate is wired.

## Technical Requirements

- **TR1 — no new assert script, but three per-target maps.** Reuse `measure-classification.cjs`,
  `gate-classification.cjs`, `parse-label.cjs`, `verdict.cjs`, `models.generated.json` unchanged.
  Edit `gen-skill-prompt.cjs TARGET_CONFIG`, `eval-gate.cjs TARGET_RESOURCES`, and the
  `extract-block.test.sh` round-trip loop (data-drive the last from the registry).
- **TR2 — projection round-trip + registry-coverage.** The round-trip test
  (`test/extract-block.test.sh`, data-driven from the registry) must pass for each new
  sentinel-wrapped block; regenerate with `node scripts/gen-skill-prompt.cjs --all` on any
  source-block edit. A consistency test asserts every registry target ∈ both per-target maps.
- **TR3 — sentinel placement must not break the source file's own consumers.** For
  lane-inference, the §Lane Inference block is referenced by downstream skills "by heading" —
  the HTML-comment sentinels must sit inside the section without altering the heading or the
  table that `plan`/`work`/`brainstorm` read.
- **TR4 — synthesized-fixtures gate.** All golden tasks are synthesized; no real skill source
  or real user input copied in (`cq-test-fixtures-synthesized-only`).
- **TR5 — single-source model IDs.** Configs reference `file://models.generated.json`; no model
  literal hardcoded (run `gen-models.sh` before the opt-in run).
- **TR6 — golden sets include cross-label adversarial cases** per
  `2026-05-15-classifier-prose-table-row-ordering-collision` — the gate's value on routing
  classifiers is catching cross-row/cross-label collisions, which only surface if the golden
  set contains overlapping-signal tasks.

## Acceptance Criteria

- AC1: `gated-skills.json` has 4 rows (go-routing, ticket-triage, lane-inference,
  incident-threshold), each pointing at a real source file with present sentinel markers.
- AC2: `node scripts/eval-gate.cjs --check <source-file>` reports `{gated:true}` for both new
  source files.
- AC3 (gate path): `node scripts/eval-gate.cjs --dry-run --target <t>` prints a valid estimate
  (no API) for both — proves `TARGET_RESOURCES` is wired (else the gate ships dormant).
- AC4: registry-coverage consistency test green (every target ∈ TARGET_CONFIG ∩ TARGET_RESOURCES).
- AC5: `bash scripts/test-all.sh` passes (data-driven round-trip green for both new projections).
- AC6: the single PR body records both opt-in deltas + API spend; uses `Ref #5704` (not `Closes`).
- AC7: `gh issue close 5704` runs automatically after merge (both commits landed); #5722 stays open.

## Sequencing

One PR, two commits, `Ref #5704`:
1. **Commit 1 — lane-inference** (FR1-FR5 + FR-MAPS).
2. **Commit 2 — incident-threshold** (FR6-FR10 + FR-MAPS).
3. Auto-close #5704 after merge (both commits landed); #5722 (deferred pdr) stays open.
