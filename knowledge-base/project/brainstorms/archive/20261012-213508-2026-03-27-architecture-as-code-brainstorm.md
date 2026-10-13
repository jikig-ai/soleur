# Architecture as Code Brainstorm

**Date:** 2026-03-27
**Status:** Complete
**Participants:** Founder, CTO, CPO, CMO

## What We're Building

A comprehensive architecture documentation capability for the Soleur platform, consisting of:

1. **A new `soleur:architecture` skill** with sub-commands for creating ADRs, generating Mermaid/Structurizr architecture diagrams, listing decisions, and superseding outdated ones
2. **Extended CTO agent** with write capability — when it detects architectural decisions during brainstorm/plan, it prompts to capture them as ADRs
3. **Extended architecture-strategist review agent** that checks whether PRs touching architecture have corresponding ADRs
4. **Workflow hooks** in brainstorm, plan, and work skills that detect architectural decisions and prompt for capture
5. **Architecture as Code (AAC)** — all artifacts stored as Mermaid/Structurizr DSL in markdown files under `knowledge-base/project/architecture/`

This is a **product feature from day one**, designed to be usable by any founder running the Soleur platform — not just internal tooling.

## Why This Approach

### The Gap

Three architecture-adjacent agents exist (`architecture-strategist`, `ddd-architect`, `agent-native-architecture`) but they are all **advisory or review-time only**. None produce persistent artifacts. The CTO agent assesses during brainstorms but writes nothing to disk. The learnings directory has 10+ entries that are effectively proto-ADRs, but they use a problem/solution format, not a decision/rationale format. Architecture decisions are scattered across brainstorms, plans, roadmap.md, and constitution.md — no single queryable location exists.

### Why Approach A (Skill + Extended Agents)

- **Standalone skill** gives users a proper entry point (`/soleur:architecture create`, `/soleur:architecture diagram`)
- **Extending existing agents** (CTO, architecture-strategist) avoids token budget pressure and overlap — no new agent needed
- **Workflow hooks** ensure ADRs don't depend on agents "remembering" to create them
- **Product-ready** since skills are discoverable and invocable in any repo

### Rejected Alternatives

- **New architecture agent (Approach B):** Token budget pressure, overlap with 3 existing agents, agents can't be invoked directly by users
- **Extend existing only (Approach C):** No dedicated entry point, ADR creation depends on agent memory, doesn't feel like a product feature

## Key Decisions

1. **Scope:** Full suite — ADRs + architecture diagrams + proactive architecture thinking + Architecture as Code. Not phased.
2. **Format:** Mermaid/Structurizr DSL embedded in markdown files. Human-readable, version-controlled, renderable in GitHub/docs.
3. **Location:** `knowledge-base/project/architecture/` directory with sequential numbering (ADR-001, ADR-002, etc.)
4. **Lifecycle:** Lightweight — two states: **active** (current truth) and **superseded** (replaced by newer ADR, with forward link).
5. **Audience:** Product feature from day one. Any founder using Soleur gets this capability.
6. **Integration model:** Standalone skill (`soleur:architecture`) + workflow hooks in brainstorm/plan/work that detect and prompt for architectural decisions.
7. **No new agent:** Extend CTO agent (write capability) and architecture-strategist (ADR coverage check) instead of creating a new agent.

## Open Questions

1. **What constitutes an "architectural decision" that triggers a hook?** Infrastructure changes (Terraform) are easy to detect. Library choices, data model decisions, and API patterns are harder. Is human judgment the trigger, or should the workflow detect heuristically?
2. **Diagram scope:** Which C4 levels are worth producing? Level 1 (System Context) and Level 2 (Container) are stable. Level 3+ rots fast.
3. **How does this relate to compound?** Compound captures post-implementation learnings (problem/solution). ADRs capture at-decision-time rationale (context/decision/consequences). They're complementary but the boundary needs to be clear in the skill instructions.
4. **Cross-domain ADRs:** Architecture decisions that span CTO + CFO + CLO (e.g., data residency) need domain routing. The brainstorm domain config handles this during brainstorm, but ADRs written post-brainstorm via the standalone skill bypass that routing.
5. **Structurizr DSL adoption:** Mermaid is already used in the codebase. Structurizr DSL is more powerful for C4 models but adds a dependency. Start with Mermaid-only and add Structurizr later?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Three architecture-adjacent agents exist but none produce persistent artifacts. The CTO agent's assessments are conversational, not durable. Recommends starting with Option A (skill + extended agents) and warns against bundling diagrams, ADRs, and "long-term thinking" into one bloated deliverable. Mermaid is already used in the codebase — the gap is that no workflow step produces or updates diagrams as a side effect of implementation.

### Product (CPO)

**Summary:** The gap is real but partially covered by informal patterns. The product is in a PIVOT state (Phase 1 incomplete), but this is plugin-side engineering infrastructure that doesn't block P1. Recommends formalizing the proto-ADR pattern that already exists in learnings. Warns against building a workflow gate — this should be a capability the agent offers, not a barrier it enforces. Timing is fine: build for internal use now, it naturally becomes CaaS value in Phase 4.

### Marketing (CMO)

**Summary:** Strong differentiation opportunity — no competitor claims architecture-level thinking. Positions Soleur as operating at the systems-design level, a qualitative tier above code-level tools. The "knowledge compounds" thesis gets its most concrete proof point. Risks: "ADR" is insider vocabulary that needs outcome-framing for external audiences. Engineering-only perception must be countered by framing as cross-domain capability. Content opportunity: "Agentic Architecture" article fits existing content strategy pillars.

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|-----------|
| No persistent artifact output from CTO agent assessments | Engineering | CTO produces conversational assessments during brainstorm but writes nothing to disk. Giving it write capability closes the core gap without a new agent. |
| No architecture diagram convention | Engineering | Mermaid is used ad-hoc but there's no standard location, naming convention, or workflow trigger for producing/updating diagrams. |
| No ADR template in spec-templates | Engineering | The spec-templates skill has spec.md and tasks.md but no ADR template. |
| "ADR" naming needs outcome-framing for external audiences | Marketing | Solo founders won't search for "Architecture Decision Records." Need accessible naming like "Architecture Decisions" or "System Design Decisions." |
