---
title: "Plan: detect vendored schemas before proposing edits; check for blocking validation gates"
date: 2026-05-12
category: workflow-patterns
tags: [plan, schema, vendored-upstream, compound-capture, validation-gate, review-catch]
issue: 2723
severity: medium
status: open
---

# Learning: Vendored-schema P1 detection at plan-review time

## Problem

The plan for Spec A of #2723 (tech-debt ledger lifecycle) prescribed editing three files under `plugins/soleur/skills/compound-capture/`:

1. `schema.yaml` — add `status` enum field with `required: true` + `default: open`, plus `technical_debt` to the `problem_type` enum
2. `references/yaml-schema.md` — mirror the schema change in human-readable form
3. `assets/resolution-template.md` — add `status: open` to the template

The repo-research-analyst agent had returned these three anchors as the compound-integration touch points. The plan was drafted accordingly.

At plan-review time:

- **Kieran-agent P1:** opened `schema.yaml` and read its first line: `# CORA Documentation Schema`. The `component` enum contained `rails_model`, `rails_controller`, `email_processing`, `brief_system`, `assistant` — CORA-domain, not Soleur-domain. The schema was vendored from an upstream project and never adapted. Editing it would (a) break the upstream-sync contract, and (b) propagate Soleur-specific values into a schema that's structurally CORA's.
- **architecture-strategist P1:** the `compound-capture/SKILL.md` declares `<validation_gate name="yaml-schema" blocking="true">` at step 5 that loads `schema.yaml`. Adding `status` as `required` would BLOCK every `/soleur:compound` invocation across all 13 problem_types (build_error, test_failure, runtime_error, performance_issue, …) — not just `technical_debt`. The plan's R5 risk row had asserted "schema additions only … no breaking changes" — false. A `required` field IS a breaking change to a blocking gate.

The cheap fix: collapse compound integration to **template-only** (`assets/resolution-template.md`). When `/soleur:compound` writes a new entry from the template verbatim, the new `status: open` line lands without touching the blocking schema. Plan Phase 5 dropped from 4 files to 1 file.

## Solution

Two complementary checks to fold into `soleur:plan` at draft time so plan-review catches drift, not premise:

### 1. Vendored-schema header check

Before adding any file under `**/schema.yaml`, `**/*_schema.yaml`, `**/*_schema.md`, `**/*.config.{yaml,json}` to `## Files to Edit`, **read the file's first 10 lines** and look for:

- A header comment naming a foreign project: `# <ProjectName> Documentation Schema`, `# Vendored from X`, `# Adapted from X — MIT`, `# SPDX-License-Identifier: ...` (with non-Soleur copyright).
- Enum values from a foreign domain (Rails-specific tokens in a non-Rails project, etc.).
- A sibling `NOTICE` file with `upstream:` frontmatter (precedent: `plugins/soleur/skills/gdpr-gate/NOTICE`).

If any of these fire, treat the file as **vendored-read-only** — edits are out of scope without an explicit vendoring decision. The right plan response is "this is CORA-vendored; out of scope" not "this is in the path so we'll edit it."

### 2. Blocking-validation-gate audit

Before proposing a `required: true` field on a schema (anywhere), grep the schema's consumers for `<validation_gate ... blocking="true">` or equivalent (`validate_required`, `require: true`, `enforce: hard`). If any consumer treats the schema as a hard gate, adding a new `required` field is a breaking change to the gate contract — every existing producer must be updated in the same PR or the gate fails for all categories, not just the one being targeted.

**Detection grep at plan time:**

```bash
git grep -n 'blocking="true"\|validate_required\|enforce: hard' -- '**/*.md' '**/*.yaml' | head -20
```

If hits exist on a file referenced in `## Files to Edit`, the plan MUST include either:
- An audit step proving the new `required` field is back-compatible with all existing schema-producers, OR
- A scope reduction (optional-with-default, or template-only, or conditional-required by some discriminator field).

## Key Insight

Plan-review's 5-agent panel caught both P1s at the gate where catching them is cheap (~minutes of plan rewrite). At /work time, the same finding would have caused either (a) a runtime regression breaking 13 problem_types if the agent was less careful, or (b) a mid-build pivot rewriting Phase 5 with the half-built skill in flight. The vendored-schema header check + blocking-gate grep are TWO LINES OF SHELL EACH. Putting them in the plan-skill's Phase 2 file-list construction step closes both gaps at the cheapest possible point.

Generalizes: **before treating a file as in-scope-to-edit, check whether its first 10 lines or its consumers declare it as read-only.** The path-pattern grep (which is what repo-research-analyst did here) reveals the file exists; it does not reveal whether the file is the consumer's source-of-truth or a vendored mirror.

## Session Errors

- **Plan v1 prescribed editing CORA-vendored `compound-capture/schema.yaml`.** Caught at plan-review by Kieran-agent (P1, read the file header) + architecture-strategist (P1, traced the blocking-validation-gate consumer). Recovery: Phase 5 narrowed to template-only (1 file, 2 lines). **Prevention:** the two checks proposed above, folded into plan-skill Phase 2.
- **Plan v1 was ~30% over-spec'd** (flock + 20 tests + regex theater + shared module + separate committed backfill script). Caught by simplification panel (DHH + code-simplicity, fire on same scope). Recovery: convergent cuts applied en bloc; plan body 330→240 lines. **Prevention:** plan-skill Phase 4 detail-level selection should default to MORE (not A LOT) for single-day-scope features; the rubric "delete-over-fix when both panels fire on the same scope" is already documented in plan-review SKILL.md and worked here as designed.

## Tags
category: workflow-patterns
module: plugins/soleur/skills/plan
