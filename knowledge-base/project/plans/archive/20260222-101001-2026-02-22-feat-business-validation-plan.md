---
title: "feat: Add CPO domain leader and business-validator workshop agent"
type: feat
date: 2026-02-22
---

# feat: Add CPO domain leader and business-validator workshop agent

## Overview

Add two agents to the Product domain to fill the pre-build validation gap: a CPO domain leader that orchestrates product agents and participates in brainstorm Phase 0.5, and a business-validator workshop agent that guides users through a 6-gate validation funnel with kill criteria. Addresses issues #141 and #183.

## Problem Statement / Motivation

Soleur users who have a business idea lack a structured way to validate it before committing to build. Existing agents (CMO, brand-architect, pricing-strategist) all assume a product already exists. Additionally, the Product domain has no domain leader -- Marketing has CMO, Engineering has CTO, but Product has no equivalent orchestrator.

## Proposed Solution

### Phase 1: Business Validator Agent

Create `agents/product/business-validator.md` following the brand-architect workshop pattern.

**6-Gate Validation Funnel:**

| Gate | Heading | Questions | Kill Criterion |
|------|---------|-----------|---------------|
| 1 | `## Problem` | 2-3 questions about the problem (separate from solution) | Cannot state problem without mentioning solution |
| 2 | `## Customer` | 2-3 questions about target customer (role, context, pain frequency) | "Everyone" or cannot name 5 real people |
| 3 | `## Competitive Landscape` | Web search + 2-3 questions about alternatives and differentiation | Many competitors + no structural advantage |
| 4 | `## Demand Evidence` | 2-3 questions about customer conversations | No customer conversations at all |
| 5 | `## Business Model` | 2-3 questions about revenue model and willingness to pay | Interest but no commitment of time or money |
| 6 | `## Minimum Viable Scope` | 2-3 questions about smallest testable version | MVP requires 6+ months of engineering |

Framework knowledge (JTBD, Blue Ocean, Mom Test, Van Westendorp) is baked into question phrasing rather than offered as separate opt-in branches. Opt-in deep-dives can be added in v2 if users request them.

**Gate Failure Override Flow:**
When a kill criterion triggers:
1. Agent explains why this is a red flag (specific, not generic)
2. AskUserQuestion with options:
   - **Revise answer** -- Re-attempt the gate with more specific information
   - **Override and continue** -- Proceed with a warning recorded in the document
   - **End workshop** -- Stop with a STOP verdict
3. If override: record `> WARNING: Kill criterion triggered at Gate N -- user chose to proceed` under the gate's heading

**Detect-and-Resume (Step 0):**
- Check if `knowledge-base/overview/business-validation.md` exists
- If exists: read document, present summary table of completed gates with verdicts
- AskUserQuestion: "Which gate would you like to revisit?" with options for each completed gate + "Full refresh" + "Done"
- If not exists: proceed to full workshop

**Web Search (Gate 3):**
Gate 3 uses web search to find real competitors and pricing data. User validates results before they enter the document. Falls back to manual input if search is empty or irrelevant. "No search results" does not mean "no competitors."

**Atomic Write:**
- Collect all answers through the workshop
- Write document atomically at the end (after all gates or after STOP)
- Document includes YAML frontmatter: `last_updated`

**Output Document Contract:**

```yaml
---
last_updated: YYYY-MM-DD
---
```

| Heading | Required |
|---------|----------|
| `## Problem` | Yes |
| `## Customer` | Yes |
| `## Competitive Landscape` | Yes |
| `## Demand Evidence` | Yes |
| `## Business Model` | Yes |
| `## Minimum Viable Scope` | Yes |
| `## Validation Verdict` | Yes |

If verdict is STOP at an early gate, subsequent headings are absent (not empty). The `## Validation Verdict` section includes a gate-by-gate summary showing which gates passed, which triggered kills, and which were not reached.

### Phase 2: CPO Domain Leader

Create `agents/product/cpo.md` following the CMO 4-phase pattern (since CPO delegates to specialist agents).

**Domain Leader Interface:**

| Phase | CPO Responsibility |
|-------|-------------------|
| **1. Assess** | Evaluate product implications: does a validated business exist? Is there a spec? What is the product maturity stage? Read `knowledge-base/overview/business-validation.md` and `brand-guide.md` if they exist. |
| **2. Recommend** | Suggest product direction with trade-offs (2-3 options when ambiguous). Structured output with risk ratings, not prose. |
| **3. Delegate** | Route to appropriate product agent based on product maturity. See routing table below. |

**Sharp Edges:**
- Do not prescribe engineering details -- recommend product direction and constraints.
- Flag cross-domain concerns but defer marketing/legal/ops to their domain leaders.
- Do not duplicate spec-flow-analyzer's gap analysis or ux-design-lead's visual design.

**CPO Routing Decision Tree:**

| Signal | Route To | Rationale |
|--------|----------|-----------|
| No product exists yet / "I have an idea" / pre-build validation | business-validator | Validate before building |
| Product exists, spec/plan needs analysis | spec-flow-analyzer | Analyze user flows and gaps |
| Product exists, visual design needed | ux-design-lead | Design screens and components |
| Cross-cutting product question (strategy, roadmap, prioritization) | CPO handles directly | Advisory assessment, no delegation needed |

**Description (following CMO pattern):**
```
"Orchestrates the product domain -- assesses product strategy, validates business models, and delegates to specialist agents (spec-flow-analyzer, ux-design-lead, business-validator). Use individual product agents for focused tasks; use this agent for cross-cutting product strategy and multi-agent coordination."
```

### Phase 3: Brainstorm Integration

Update `commands/soleur/brainstorm.md` Phase 0.5 with:

1. **Assessment question (item 4):**
   ```
   4. **Product strategy implications** -- Does this feature involve validating a new business idea, assessing product-market fit, evaluating customer demand, competitive positioning, or determining whether to build something?
   ```

2. **Routing block:** AskUserQuestion offering "Include product perspective" or "Brainstorm normally"

3. **Participation block:** Task CPO with assessment prompt, weave into brainstorm dialogue

4. **Business-validator workshop route:** When CPO routes to business-validator during brainstorm, follow the brand-architect pattern: create worktree (if not already in one), handle issue, navigate to worktree, hand off to business-validator via Task tool, display completion message and STOP. Do NOT proceed to brainstorm Phase 1.

### Phase 4: Disambiguation and Sibling Updates

Update ALL product domain agent descriptions for cross-referencing:

- **spec-flow-analyzer**: Add disambiguation against business-validator and CPO
- **ux-design-lead**: Add disambiguation against business-validator and CPO
- **business-validator**: Include disambiguation against spec-flow-analyzer and ux-design-lead
- **cpo**: Include disambiguation against all three product agents

### Phase 5: Plugin Infrastructure

- **AGENTS.md**: Add CPO to domain leaders table (Leader: `cpo`, Domain: Product, Agents Orchestrated: spec-flow-analyzer, ux-design-lead, business-validator, Entry Point: Auto-consulted via brainstorm domain detection)
- **plugin.json**: MINOR version bump from main, update agent count (+2)
- **CHANGELOG.md**: Add new version entry
- **README.md**: Update Product count (+2), add both agents to table, update total count, reconcile any count discrepancies between README and plugin.json
- **Root README.md**: Update version badge
- **bug_report.yml**: Update version placeholder

### Phase 6: Dogfooding

- Run business-validator on Soleur itself after implementation
- Review and commit the validation output

## Technical Considerations

- **Token budget**: Current cumulative description word count is ~850 words (ceiling: 2,500). Two new agents with ~30-50 word descriptions each stays well within budget.
- **Agent prompt length**: Follow "sharp edges only" principle -- embed non-obvious gotchas, not general workshop knowledge. Target under 150 lines.
- **No docs site changes needed for agents.js**: Product domain already exists in `DOMAIN_LABELS`. No new CSS variables needed.
- **No skills added**: Both are agents only. No skills.js registration needed.
- **Agent count baseline**: Verify actual count from both README and plugin.json before bumping. There is a known discrepancy (45 vs 46) that must be reconciled.

## Acceptance Criteria

- [x] Business-validator agent guides through all 6 gates sequentially with AskUserQuestion
- [x] Agent pushes back on vague answers and offers override/revise/end when kill criterion triggers
- [x] Web search runs at Gate 3 with fallback to user-provided data
- [x] Output document follows heading contract with `last_updated` frontmatter
- [x] Detect-and-resume works for existing validation documents
- [x] CPO follows domain leader interface with product-specific guidance
- [x] CPO routes correctly based on product maturity signals
- [x] CPO participates in brainstorm Phase 0.5 via LLM semantic assessment
- [x] Brainstorm STOP pattern works when CPO routes to business-validator (including worktree creation)
- [x] All 4 product domain agent descriptions include disambiguation sentences
- [x] AGENTS.md domain leaders table updated
- [ ] Version bumped (MINOR) across plugin.json, CHANGELOG.md, README.md
- [ ] Root README badge and bug_report.yml placeholder updated
- [x] Agent count discrepancy between README and plugin.json reconciled
- [x] Dogfooding: run validator on Soleur itself after implementation

## Test Scenarios

- Given a user brainstorms "I have an idea for a SaaS that does X", when Phase 0.5 fires, then CPO assessment question detects product validation and offers routing
- Given a user invokes business-validator with no existing document, when they complete all 6 gates with passing answers, then a GO verdict document is written to knowledge-base/overview/business-validation.md
- Given a user reaches Gate 2 and says their target customer is "everyone", when the agent pushes back, then the user gets options to revise, override, or end
- Given a user overrides a kill criterion, when the document is written, then a WARNING is recorded under the gate's heading
- Given an existing business-validation.md exists, when the user invokes the agent, then they see a summary and can choose which gate to revisit
- Given web search at Gate 3 returns no relevant results, when the agent falls back, then it asks the user to provide competitors manually
- Given the CPO detects a validated business exists and a spec needs analysis, when it routes, then it delegates to spec-flow-analyzer (not business-validator)

## Dependencies & Risks

- **Risk: Business-validator prompt too long.** Mitigation: Follow "sharp edges only" principle. The 6-gate structure with kill criteria and override flow is ~80-100 lines. Target under 150 lines total.
- **Risk: CPO/CMO overlap on positioning.** Mitigation: CPO focuses on "should we build this?" (pre-build). CMO focuses on "how do we market this?" (post-build). Disambiguation sentence makes this explicit.
- **Risk: Web search quality at Gate 3.** Mitigation: User validates search results before they enter the document. Fallback to user-provided data.

## References & Research

### Internal References

- Brand-architect workshop pattern: `plugins/soleur/agents/marketing/brand-architect.md`
- CTO domain leader: `plugins/soleur/agents/engineering/cto.md`
- CMO domain leader: `plugins/soleur/agents/marketing/cmo.md`
- Brainstorm Phase 0.5: `plugins/soleur/commands/soleur/brainstorm.md`
- Spec: `knowledge-base/specs/feat-business-validation/spec.md`
- Brainstorm: `knowledge-base/brainstorms/2026-02-22-business-validation-brainstorm.md`

### Learnings Applied

- Agent description token budget optimization: `knowledge-base/learnings/performance-issues/2026-02-20-agent-description-token-budget-optimization.md`
- Three-way agent disambiguation: `knowledge-base/learnings/2026-02-22-three-way-agent-disambiguation.md`
- Domain leader pattern and LLM detection: `knowledge-base/learnings/2026-02-21-domain-leader-pattern-and-llm-detection.md`
- Adding new agent domain checklist: `knowledge-base/learnings/integration-issues/adding-new-agent-domain-checklist.md`
- Agent prompt sharp edges only: `knowledge-base/learnings/agent-prompt-sharp-edges-only.md`

### Issues

- #141: Validate Business Idea before building or launching
- #183: CPO domain leader for product
