---
title: C4 Architecture Diagram Visual Redesign
date: 2026-05-13
linear_issue: SOL-40
related_pr: https://github.com/jikig-ai/soleur/pull/3713
worktree: .worktrees/feat-sol-40-redesign-c4-model/
spec: knowledge-base/project/specs/feat-sol-40-redesign-c4-model/spec.md
lane: cross-domain
brand_survival_threshold: none (internal architecture documentation)
status: complete
---

# C4 Architecture Diagram Visual Redesign — Brainstorm

## What We're Building

A visual redesign of the three existing C4 architecture diagrams so they render legibly on GitHub markdown preview. Source format stays Mermaid. Filenames stay unchanged. Each file keeps one rendered diagram, restructured to fit within Mermaid's auto-layout ceiling.

Files in scope:

- `knowledge-base/engineering/architecture/diagrams/system-context.md` (C4 Level 1)
- `knowledge-base/engineering/architecture/diagrams/container.md` (C4 Level 2)
- `knowledge-base/engineering/architecture/diagrams/component-plugin.md` (C4 Level 3)

## Why This Approach

Mermaid's `C4Context` / `C4Container` / `C4Component` renderer is the layout ceiling — it does not honor `Container_Boundary` grouping reliably, and arrows are routed point-to-point with no avoidance heuristic. The CTO assessment confirms this is a renderer ceiling, not a source defect. Restructuring the source helps only by reducing the load (fewer nodes, fewer edges, controlled boundary ordering).

The CTO also confirms switching renderers is technically low-risk (the Eleventy docs site does not render these files — `knowledge-base/**` is excluded from `deploy-docs.yml`; only GitHub markdown preview and IDE consume them). However, the operator preferred to **stay on Mermaid** to preserve GitHub-native inline rendering without committing parallel SVG artifacts. The COO recommendation (Likec4) and the prior deferred decision from `2026-03-27-architecture-as-code-brainstorm.md` (open question #5 — "Start with Mermaid-only and add Structurizr later?") remain available as a follow-up.

A deferred-issue path captures the architectural debt the agents surfaced — staleness, missing views, hand-authored drift — so SOL-40 stays tight.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Scope = visual fix only.** Out of scope: content staleness updates, new C4 views (Deployment, additional L3s), and auto-generation from code manifests. | Keeps SOL-40 shippable. Each deferred concern becomes its own GitHub issue (see Deferred Items below). |
| D2 | **Stay on Mermaid.** No renderer swap. | GitHub markdown preview must keep working without committing parallel SVGs. The 19+ ADRs referencing existing filenames stay intact. Operator preference. |
| D3 | **Same 3 files, same filenames, one Mermaid block per file.** No splitting into per-subsystem files. | Preserves ~12 cross-references from ADRs, plans, specs (see Cross-references in repo research). |
| D4 | **Slim-down tactic = Approach C** — relation bundling on L1, aggressive node trim on L2/L3, with a `## Details` prose section below each diagram listing what was folded. | L1 (8 nodes) is small enough that bundling alone fixes it. L2/L3 are above Mermaid's auto-layout ceiling and need node count reduction. The Details section keeps the folded information grep-able without polluting the diagram. |
| D5 | **Node-count budget per diagram: L1 ≤ 8, L2 ≤ 10, L3 ≤ 8.** Anything beyond moves into the `## Details` section. | Empirically the threshold where Mermaid's C4 renderer keeps arrows un-crossed. |
| D6 | **Bundle related `Rel()` edges into single labeled edges.** | Three separate "Reads / Writes / Discovers" rels become one "Loads plugin [File I/O]" rel. Cuts edge count without losing the semantic story. |
| D7 | **Reorder boundary declaration top-to-bottom by data flow** (Founder → Web → CLI → Plugin → Infra). Set `UpdateLayoutConfig($c4ShapeInRow=3, $c4BoundaryInRow=2)`. | Aligns Mermaid's row-wrap with the architectural flow direction, reducing arrow crossings. |
| D8 | **Mermaid retained as the standard diagram format.** Likec4 / D2 / Structurizr DSL remain deferred per `2026-03-27-architecture-as-code-brainstorm.md` open question #5. | No ADR formally locks Mermaid (the locking is in the as-code plan / spec, not an ADR). No new ADR required for D2; renderer swap, if revisited, will need one. |

## Open Questions

- After restructure renders, does L3 still have residual arrow overlap? If yes, the deferred renderer-swap follow-up gets prioritized rather than waiting indefinitely.
- Should the `architecture` skill's `c4-reference.md` reference be updated to teach the slim-down conventions (node budget, edge bundling, boundary order)? Tracked as a possible follow-up.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** Root cause is Mermaid's experimental C4 renderer hitting its auto-layout ceiling on medium-to-large diagrams, not a source defect. Source restructure reduces density but cannot fully fix L3 (14 components). Renderer-swap is technically low-risk (zero docs-site coupling) but adds a second toolchain. Diagrams are LLM-hand-authored and will drift from code regardless of renderer — flagged as a separate concern.

### Operations

**Summary:** Likec4 is the lowest-friction renderer alternative (Node devDep, zero spend, free auto-layout). IcePanel rejected at $40/editor/mo and loss of diff-friendly source. Stay-on-Mermaid is the zero-cost zero-procurement baseline. Recommendation respected operator's stay-on-Mermaid choice; full Likec4 evaluation captured as a deferred follow-up rather than discarded.

## Capability Gaps

No new capability gaps. The `architecture` skill already exists and handles ADR lifecycle and C4 diagram scaffolding (LLM-authored). No new skills, agents, or commands are required. Auto-generation from a plugin manifest is a *latent* gap but explicitly out-of-scope for SOL-40.

## Deferred Items

Tracked as separate GitHub issues at Phase 3.6:

1. **Content refresh** — `container.md` reports "61 skills, 65 agents" but actual count is 71/66; missing skills include ship, qa, merge-pr, linear-fetch, agent-native-audit; missing domain leaders include CLO, COO, CFO, CRO, CCO. Re-evaluation criterion: at any point the diagrams' counts mismatch the live `find` count by more than 10%.
2. **Add L3 views for non-plugin containers** — Web App (Dashboard / API / Auth), Agent Runtime internals, Hook Engine. Re-evaluation criterion: when a contributor cannot answer "how does the web app spawn an agent session?" from existing diagrams.
3. **Add a C4Deployment view** — given ADR-006 (Terraform/R2), ADR-007 (Doppler), ADR-008 (Cloudflare Tunnel), ADR-019 (infra layout), a deployment view would carry real signal. Re-evaluation criterion: when next onboarding a contractor or audit team to the infra.
4. **Code-introspected diagram generation** — replace the LLM-authored scaffold in `plugins/soleur/skills/architecture/SKILL.md` with a manifest scanner that emits Mermaid (or whichever renderer is chosen) from `plugins/soleur/{commands,skills,agents}/` discovery. Re-evaluation criterion: when manual content refreshes (item 1) happen more than once per quarter.
5. **Renderer evaluation (Likec4 / D2 / Structurizr DSL)** — revisits open question #5 of `2026-03-27-architecture-as-code-brainstorm.md`. Re-evaluation criterion: when item 1's content refresh or this brainstorm's L3 restructure leaves residual layout problems that source restructuring cannot fix.
