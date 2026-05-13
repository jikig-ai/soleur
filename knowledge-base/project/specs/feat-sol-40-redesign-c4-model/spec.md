---
title: C4 Architecture Diagram Visual Redesign
status: draft
date: 2026-05-13
linear_issue: SOL-40
related_pr: https://github.com/jikig-ai/soleur/pull/3713
brainstorm: knowledge-base/project/brainstorms/2026-05-13-c4-diagram-visual-redesign-brainstorm.md
worktree: .worktrees/feat-sol-40-redesign-c4-model/
branch: feat-sol-40-redesign-c4-model
lane: cross-domain
brand_survival_threshold: none (internal architecture documentation)
---

# Feature: C4 Architecture Diagram Visual Redesign

## Problem Statement

The three existing C4 architecture diagrams in `knowledge-base/engineering/architecture/diagrams/` (`system-context.md`, `container.md`, `component-plugin.md`) render unreadable on GitHub markdown preview: arrows overlap, labels collide, boundaries do not group their contained components, and the L3 Component diagram is functionally illegible. Cause: Mermaid's experimental `C4Context` / `C4Container` / `C4Component` renderer hits its auto-layout ceiling on diagrams above ~10 nodes. The information is structurally correct in source; only the visual output fails.

## Goals

- G1 — `system-context.md`, `container.md`, and `component-plugin.md` render with zero overlapping arrows and zero label collisions on GitHub markdown preview.
- G2 — Each rendered Mermaid block stays within the node-count budget: L1 ≤ 8, L2 ≤ 10, L3 ≤ 8.
- G3 — All semantic content currently represented in the three diagrams remains discoverable in the same file (either inside the Mermaid block or in a new `## Details` prose section).
- G4 — Filenames `system-context.md`, `container.md`, `component-plugin.md` remain unchanged so the 19+ ADR / plan / spec cross-references stay valid.
- G5 — No new tooling, no new runtime dependency, no new CI step. Source format stays Mermaid.

## Non-Goals

- NG1 — Refreshing diagram content to reflect today's counts (71 skills, 66 agents) is **out of scope**. The diagrams stay structurally faithful to their 2026-03-27 stamp; content drift is tracked as a separate deferred issue.
- NG2 — Adding new C4 views (Deployment, additional L3s for Web App / Agent Runtime / Hook Engine) is **out of scope** and tracked as a separate deferred issue.
- NG3 — Code-introspected diagram generation (replacing the LLM scaffold in the `architecture` skill) is **out of scope** and tracked as a separate deferred issue.
- NG4 — Renderer evaluation (Likec4 / D2 / Structurizr DSL) is **out of scope** and tracked as a separate deferred issue.
- NG5 — Editing or amending any existing ADR. The redesign carries no architectural decision warranting an ADR.

## Functional Requirements

### FR1: System Context (L1) restructure

Apply relation bundling to `system-context.md`:

- Combine related `Rel()` edges that share source and target into a single labeled bundle (e.g., today's separate "Auth and data" + "Sessions and encrypted keys" become bundled per source-target pair).
- Reorder boundary and system_ext declaration top-to-bottom by data flow direction: Founder → Web App → Cloud CLI Engine → Supabase → External systems.
- Apply `UpdateLayoutConfig($c4ShapeInRow=3, $c4BoundaryInRow=2)`.
- Maintain the existing 8 systems (founder, webapp, engine, supabase, anthropic, github, cloudflare, doppler, discord, stripe, plausible) **subject to G2** — if node count exceeds 8, fold the lowest-signal external systems (e.g., plausible, discord) into a single `Analytics & Notifications` system_ext with the folded detail in the `## Details` section.

### FR2: Container (L2) restructure

Apply aggressive node trim to `container.md`:

- Inside the `Soleur Plugin` boundary, collapse `Skills` + `Agents` + `Knowledge Base` into a single `Plugin Resources` container (their detail belongs at L3 anyway).
- Reorder boundary declarations top-to-bottom by data flow: Web Application → Cloud CLI Engine → Soleur Plugin → Infrastructure.
- Bundle redundant cross-boundary `Rel()` edges where source-target pairs share semantics.
- Apply `UpdateLayoutConfig($c4ShapeInRow=2, $c4BoundaryInRow=2)`.
- Add a `## Details` prose section listing every folded element and its origin (e.g., "`Plugin Resources` contains: Skills (markdown SKILL.md), Agents (markdown Agent Defs), Knowledge Base (Markdown + YAML)").

### FR3: Component plugin (L3) restructure

Apply aggressive node trim to `component-plugin.md`:

- Collapse entry-point commands (`go`, `sync`, `help`) into one `Entry Points` component.
- Collapse workflow skills (`brainstorm`, `plan`, `work`, `review`, `compound`, `ship`, `one-shot`, `architecture`) into one `Workflow Skills` component.
- Keep `CTO agent`, `CMO agent`, `CPO agent`, `architecture-strategist` visible only if total node count remains ≤ 8 — otherwise fold the four domain leaders + architecture-strategist into a single `Domain Leaders & Reviewers` component.
- Bundle the seven `Rel(oneshot, *)` edges into one labeled bundle (`one-shot → Workflow Skills [orchestrates steps 1-5]`).
- Apply `UpdateLayoutConfig($c4ShapeInRow=2, $c4BoundaryInRow=1)`.
- Add a `## Details` prose section listing every folded element (component name + role) so the information stays grep-able and reviewable.

### FR4: Visual acceptance check

After implementation, the three diagrams MUST render on GitHub (open the PR, view each file's rendered Mermaid) with:

- Zero arrows crossing other arrows.
- Zero arrow labels overlapping other arrow labels or component boxes.
- Every Container_Boundary visually contains its declared components.

Acceptance is verified by viewing the three files at the PR commit (link from the PR description) — not by local Mermaid CLI render. GitHub's renderer is the only consumer surface that matters here.

## Technical Requirements

### TR1: No new dependencies or CI changes

No new runtime dependencies. No new CI jobs. No edits to `eleventy.config.js` or `.github/workflows/*`. The change set is markdown-only edits to three files plus the optional `architecture/SKILL.md` reference update from TR3.

### TR2: Preserve cross-references

The filenames `system-context.md`, `container.md`, `component-plugin.md` MUST NOT change. The 12+ files cross-referencing them (`knowledge-base/INDEX.md`, `2026-03-27-feat-architecture-as-code-plan.md`, `feat-architecture-decision-records/tasks.md`, and others — see brainstorm "Cross-references" section) stay valid without sweep.

### TR3: Optional — update `c4-reference.md`

`plugins/soleur/skills/architecture/references/c4-reference.md` MAY be updated to teach the slim-down conventions used here: node-count budget, edge bundling pattern, boundary-order convention, `UpdateLayoutConfig` defaults. If included in this PR, the change is documentation-only and adds no execution semantics. If deferred, file as a follow-up so the next `/soleur:architecture diagram` invocation produces a similarly slim scaffold.

### TR4: No ADR amendment

No ADR amendment is required. No ADR formally locks Mermaid as the diagram renderer — the locking lives in `2026-03-27-feat-architecture-as-code-plan.md` and `feat-architecture-decision-records/spec.md`. Neither needs amendment for this redesign (FR4 visual fix is consistent with both).

### TR5: Generated-stamp update

Each redesigned file's "Generated: 2026-03-27" line MUST be updated to "Generated: 2026-05-13 (visual redesign per SOL-40)" so reviewers can distinguish a redesign pass from a content refresh. This sets a precedent for future content refreshes (deferred-item #1) to update the stamp similarly.

## Deferred Items

The following are explicitly out of scope for this spec and MUST be filed as separate GitHub issues at brainstorm Phase 3.6 step 7:

1. **Content refresh** — sync diagrams to 71 skills / 66 agents / current domain leaders. Re-eval: when count drift > 10%.
2. **Add missing L3 views** — Web App, Agent Runtime, Hook Engine. Re-eval: when contributor cannot answer architectural question from existing diagrams.
3. **Add C4Deployment view** — covers ADR-006/007/008/019 infra surface. Re-eval: next contractor/audit onboarding.
4. **Code-introspected diagram generation** — replace LLM scaffold with manifest scanner. Re-eval: when manual refresh happens > 1×/quarter.
5. **Renderer evaluation** — revisits `2026-03-27-architecture-as-code-brainstorm.md` open question #5 (Likec4 / D2 / Structurizr DSL). Re-eval: when source restructuring leaves residual layout problems FR4 cannot satisfy.
