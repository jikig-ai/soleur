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
- Bring **skill-security-scan verdict** (`LOW-RISK | REVIEW | HIGH-RISK`) under the gate.
- Each surface uses the existing additive recipe with **no new assert script** (both are
  single-token).
- Deliver as **one PR per surface**, lane-inference first.

## Non-Goals

- **pdr-* passive-domain-routing as a multi-label gate.** Deferred (genuinely multi-label;
  needs a set-membership assert). Its single-token output slice is covered by lane-inference.
  Tracked in a separate issue.
- **Wiring any new surface into per-PR CI.** The opt-in validation run stays manual, as for the
  v1 surfaces (the CI-backstop decision is a separate deferred item from the parent brainstorm).
- **incident `brand_survival_threshold`** and any other surface beyond the two named (noted as a
  future candidate, not built here).
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
- **FR6 — skill-security-scan enum.** Add `enums/skill-security-scan.json` with
  `["LOW-RISK", "REVIEW", "HIGH-RISK"]`.
- **FR7 — skill-security-scan golden set.** Add `tasks/skill-security-scan.jsonl`, ~6-8
  synthesized tasks: at least one clean LOW-RISK skill, one borderline REVIEW, one
  unambiguous HIGH-RISK (e.g. embeds a curl|bash, exfiltrates env), **plus a
  max-severity-aggregation case** (multiple low signals that must still aggregate to the
  documented verdict). Synthesized fixtures only.
- **FR8 — skill-security-scan arm prompts.** Add baseline + generated skill projection of the
  verdict-rubric block.
- **FR9 — skill-security-scan source sentinels.** Wrap the verdict/aggregation rubric block in
  `skill-security-scan/SKILL.md` with `eval-gate:block:skill-security-scan` markers; projection
  round-trips byte-for-byte.
- **FR10 — skill-security-scan config + registry.** Add
  `promptfooconfig.skill-security-scan.yaml` and a `gated-skills.json` row.
- **FR11 — opt-in validation run per surface.** For each surface, run the harness manually
  (`npx promptfoo eval -c promptfooconfig.<target>.yaml --repeat 3`) and record the
  baseline-vs-skill delta in the PR body as the opt-in evidence. Disclose the API spend
  (`hr-autonomous-loop-skill-api-budget-disclosure`).

## Technical Requirements

- **TR1 — additive only.** Reuse `measure-classification.cjs`, `gate-classification.cjs`,
  `parse-label.cjs`, `verdict.cjs`, and `models.generated.json` unchanged. No new script.
- **TR2 — projection round-trip under existing tests.** The AC4 round-trip test
  (`test/extract-block.test.sh`) must pass for each new sentinel-wrapped block; regenerate
  projections with `node scripts/gen-skill-prompt.cjs --all` on any source-block edit.
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
  skill-security-scan), each pointing at a real source file with present sentinel markers.
- AC2: `node scripts/eval-gate.cjs --check <source-file>` reports `{gated:true}` for both new
  source files.
- AC3: `bash scripts/test-all.sh` passes (AC4 round-trip green for both new projections).
- AC4: Each PR body records the manual opt-in run's baseline-vs-skill delta + API spend.
- AC5: A deferred GitHub issue exists for the pdr-* multi-label set-membership gate.

## Sequencing

1. **PR 1 — lane-inference** (FR1-FR5, proves the additive template). References #5704.
2. **PR 2 — skill-security-scan** (FR6-FR10). References #5704.
3. Close #5704 when both land; file the deferred pdr issue at brainstorm-end (AC5).
