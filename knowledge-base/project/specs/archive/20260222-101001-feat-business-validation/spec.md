# Business Idea Validation -- Spec

**Issues:** #141, #183
**Branch:** feat-business-validation
**Date:** 2026-02-22

## Problem Statement

Soleur users who have a business idea lack a structured way to validate it before committing to build. There is no agent that operates at the "should I build this at all?" level -- existing agents (CMO, brand-architect, pricing-strategist) all assume a product already exists. Additionally, the Product domain has no domain leader (CPO) to orchestrate product-level concerns, unlike Marketing (CMO) and Engineering (CTO).

## Goals

- G1: Provide a structured validation workflow that guides users through business idea assessment
- G2: Enforce a disciplined sequence with go/no-go gates -- the agent must be willing to say "this looks weak"
- G3: Produce a living reference document consumed by downstream agents (CMO, brand-architect, pricing-strategist)
- G4: Establish a CPO domain leader that participates in brainstorm Phase 0.5 and orchestrates product agents
- G5: Follow existing patterns (brand-architect for workshop, CTO for domain leader) to maintain architectural consistency

## Non-Goals

- NG1: Automating market research -- AI hallucinates market sizing data. The agent structures thinking, not generates analysis
- NG2: Replacing customer interviews -- the agent enforces that users talk to real people, not simulate conversations
- NG3: Creating a standalone /soleur:product skill entry point (can be added later if needed)
- NG4: Full business plan generation -- this is validation (go/no-go), not planning

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | Business validator agent runs a 7-gate validation funnel: problem articulation, customer identification, existing alternatives, differentiation, demand evidence, willingness to pay, minimum viable scope |
| FR2 | Each gate has a kill criterion; the agent recommends stopping if evidence is weak |
| FR3 | Agent uses web search at Gate 3 (competitive landscape) to find real competitors and pricing data |
| FR4 | Agent offers named framework deep-dives at relevant gates (JTBD, Blue Ocean, Mom Test, Van Westendorp) |
| FR5 | Agent detects and resumes existing business-validation.md files for iterative refinement |
| FR6 | Agent outputs to knowledge-base/overview/business-validation.md with a defined heading contract |
| FR7 | CPO domain leader follows 4-phase contract: Assess, Recommend, Delegate, Review |
| FR8 | CPO participates in brainstorm Phase 0.5 via LLM semantic assessment question |
| FR9 | CPO routes to business-validator when validation is needed |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | Business validator at agents/product/business-validator.md following brand-architect workshop pattern |
| TR2 | CPO at agents/product/cpo.md following CTO domain leader pattern |
| TR3 | Brainstorm command Phase 0.5 updated with product validation assessment question |
| TR4 | Agent descriptions stay within token budget (~2500 words cumulative) |
| TR5 | All sibling agent descriptions updated for disambiguation (spec-flow-analyzer, ux-design-lead) |
| TR6 | Version bump: MINOR (new agents) across plugin.json, CHANGELOG.md, README.md |

## Output Document Contract

The validation report at `knowledge-base/overview/business-validation.md` uses these exact headings:

| Heading | Required | Downstream Consumers |
|---------|----------|---------------------|
| `## Problem` | Yes | CMO (positioning context) |
| `## Customer` | Yes | CMO (ICP), brand-architect (target audience) |
| `## Competitive Landscape` | Yes | CMO (differentiation matrix), pricing-strategist (competitive pricing) |
| `## Demand Evidence` | Yes | -- |
| `## Business Model` | Yes | pricing-strategist (value metrics) |
| `## Minimum Viable Scope` | Yes | spec-flow-analyzer (user flows) |
| `## Validation Verdict` | Yes | All (go/no-go decision) |

## Validation Gates Detail

| Gate | Kill Criterion | Optional Framework |
|------|---------------|-------------------|
| 1. Problem articulation | Cannot separate problem from solution | JTBD |
| 2. Customer identification | "Everyone" or cannot name 5 real people | -- |
| 3. Existing alternatives | Many competitors + no clear difference | Blue Ocean value curve |
| 4. Differentiation | No structural advantage | -- |
| 5. Demand evidence | No customer conversations | Mom Test |
| 6. Willingness to pay | Interest but no commitment | Van Westendorp |
| 7. Minimum viable scope | MVP requires 6+ months | -- |

## Acceptance Criteria

- [ ] Business validator agent guides through all 7 gates sequentially
- [ ] Agent pushes back on vague answers and recommends stopping when evidence is weak
- [ ] Web search runs at Gate 3 for competitive landscape
- [ ] Framework deep-dives offered as optional at relevant gates
- [ ] Output document follows heading contract
- [ ] Detect-and-resume works for existing validation documents
- [ ] CPO participates in brainstorm Phase 0.5
- [ ] CPO routes to business-validator for validation tasks
- [ ] All sibling descriptions updated for disambiguation
- [ ] Version bumped, CHANGELOG updated, README counts updated
- [ ] Dogfooding: run validator on Soleur itself after implementation (as part of this PR)
