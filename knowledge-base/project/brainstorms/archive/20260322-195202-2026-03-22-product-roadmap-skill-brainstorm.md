---
topic: product-roadmap-skill
date: 2026-03-22
status: complete
issue: "#675"
---

# Product Roadmap Skill Brainstorm

## What We're Building

A `/soleur:product-roadmap` skill — a CPO-grade interactive workshop for defining and operationalizing product roadmaps. The skill guides founders through a structured dialogue to create a strategic roadmap, then operationalizes it by creating GitHub milestones and assigning issues.

This is a **product feature for all Soleur users**, not internal tooling. After validating an idea (via business-validator), founders need to define what to build and in what order. This capability is completely missing from the product domain and is likely the most-needed capability post-validation.

### Workflow

1. **Discover**: Read knowledge-base (brand guide, business validation, competitive intel, specs, existing issues/milestones)
2. **Fill gaps**: Ask targeted questions about missing context (company stage, users, goals, constraints)
3. **Research**: Optionally spawn competitive-intelligence or market research agents for context
4. **Workshop**: Multi-turn dialogue with founder — strategic themes, phase definitions, feature prioritization, success criteria
5. **Generate**: Write `knowledge-base/product/roadmap.md` (strategic roadmap with phases, objectives, rationale)
6. **Operationalize**: Create GitHub milestones for each phase, assign issues to milestones

## Why This Approach

### Reframe from original issue

Issue #675 originally proposed a shell script that reads GitHub milestones and generates status tables. During brainstorming, two things surfaced:

1. **CPO assessment**: The PIVOT verdict (2026-03-12) says "stop building features." A status-report script is internal tooling for a single-person audience — it doesn't serve users.
2. **CTO assessment**: Zero milestones exist. Zero Projects exist. The skill would generate empty tables from nonexistent data.
3. **Founder input**: User research shows nobody wants a Claude Code plugin — users want a native cross-platform experience. The product-roadmap capability should be something ALL Soleur users need, not just Soleur itself.

The reframe: instead of reading roadmap data (which doesn't exist), the skill **creates** it. Instead of a shell script doing data transformation, it's an agent-backed workshop doing strategic thinking with the founder.

### Why interactive workshop

A real CPO doesn't just track milestones — they research, prioritize, and define the strategy. The skill mirrors this:

- **Like brainstorm but for product strategy**: The brainstorm skill explores WHAT to build (one feature). This skill defines the PORTFOLIO across time (meta-level).
- **Full knowledge-base synthesis**: The CPO reads everything available (validation, competitive intel, brand guide, specs, issues) before asking questions. This is the advantage over a generic AI chat.
- **Discover + fill gaps**: Works for any company. If the knowledge-base is populated, the CPO has rich context. If sparse, it asks targeted questions to fill gaps. Gracefully degrades.

### Why no new agent

The CPO agent already handles "cross-cutting product questions (strategy, roadmap, prioritization)" — but currently as advisory-only with no structured workflow. This skill gives the CPO a structured process. The skill IS the workflow; the CPO and specialist agents are spawned as needed within it.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Implementation type | Agent-backed interactive workshop | Strategic thinking requires LLM, not deterministic script |
| Interaction model | Multi-turn dialogue (like brainstorm) | Real CPOs work through discovery and prioritization with founders |
| Input sources | Full knowledge-base synthesis + gap-filling questions | Maximum context; works for any company |
| Output: document | `knowledge-base/product/roadmap.md` | Strategic roadmap with phases, objectives, rationale |
| Output: operational | GitHub milestones + issue assignment | Bridges strategy to execution tracking |
| Output location | New `knowledge-base/product/` directory | Product-domain artifacts get dedicated home |
| Generality | Discover from KB + fill gaps for any user | Not hardcoded for Soleur's milestones |
| New agent needed | No — CPO exists, skill provides the workflow | Specialists (competitive-intelligence, business-validator) spawned as needed |
| Ongoing issue assignment | Handled by triage, not this skill | Clean separation of concerns |
| Issue #675 | Update with new scope | Same feature number, different (larger) spec |

## Open Questions

1. **Roadmap review cadence**: Should the skill support a "review" sub-command for periodic roadmap revisits? Or is that just re-running the skill?
2. **Automated status tracking**: The original #675 proposed weekly status reports from milestones. Should that be a future enhancement (Phase 2) layered on top of this workshop capability?
3. **Milestone naming convention**: Should the skill enforce a naming pattern (e.g., "Phase N: Title") or let founders name freely?
4. **Cross-repo support**: Should the roadmap span multiple repos (future Soleur users may have monorepos or multi-repo setups)?

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|------------|
| No product-roadmap skill exists | Product | Founders have no structured way to define a roadmap post-validation |
| CPO has no workflow for roadmapping | Product | Agent is advisory-only for roadmap questions — no structured process |
| No `knowledge-base/product/` directory | Product | Product-domain artifacts lack a dedicated home |

## Research Context

### Domain Leader Assessments

**CPO (2026-03-22)**:

- Flagged PIVOT verdict contradiction (building features vs. validating)
- Flagged zero data sources (no milestones, no projects)
- Recommended deferral or building campaign-calendar first
- These concerns were addressed by the reframe: the skill IS the product (serves all users), not internal tooling

**CTO (2026-03-22)**:

- Confirmed architecture fit is low risk (6 scheduled workflows as template)
- Flagged token lacks `read:project` scope (irrelevant now — milestones-only via REST)
- Recommended starting from data that exists (issues, labels) rather than data that doesn't (milestones)
- Recommended issue-label or milestone-driven approach
- These inputs informed the "operationalize" step: the skill creates milestones, not just reads them

### Learnings Applied

- Skills cannot invoke other skills — use shared scripts or agent delegation (learnings/2026-02-18)
- New skills need registration in 5 places: plugin.json (description only), README.md, root README.md, brand-guide.md, skills.js (learnings/2026-02-22)
- Agent prompts should contain ONLY sharp edges the LLM would get wrong without them (learnings/2026-02-19)
- `gh --jq` doesn't support `--arg` — use `$ENV` for dynamic values (learnings/2026-03-04)

### Repo Patterns

- Brainstorm skill is the closest structural analog (interactive workshop, multi-turn dialogue, document output)
- CPO agent handles roadmap advisory-only today — this skill fills the workflow gap
- No existing milestone or Projects API usage anywhere in codebase
- Skill categories in docs: "Review & Planning" is the best fit

### New User Research Finding (2026-03-22)

Talking to users: nobody wants a Claude Code plugin — they want a native cross-platform experience (web, desktop, mobile). This finding will be captured in a separate business validation update session. It reinforces that this skill must be designed as a general-purpose capability, not Soleur-specific internal tooling.
