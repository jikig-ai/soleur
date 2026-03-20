# Business Idea Validation -- Brainstorm

**Date:** 2026-02-22
**Issues:** #141 (Validate Business Idea), #183 (CPO Domain Leader)
**Status:** Complete

## What We're Building

Two complementary agents in the Product domain:

1. **CPO (Chief Product Officer)** -- Domain leader following the CTO/CMO pattern. Participates in brainstorm Phase 0.5 to assess product implications. Orchestrates product agents (spec-flow-analyzer, ux-design-lead, business-validator). Follows the 4-phase contract: Assess, Recommend, Delegate, Review.

2. **Business Validator** -- Interactive workshop agent following the brand-architect pattern. Guides users through 7 validation gates with go/no-go kill criteria. Opinionated -- will recommend stopping if evidence is weak. Produces a structured validation report to `knowledge-base/overview/business-validation.md`.

## Why This Approach

- **Two agents, not one:** The domain leader pattern (advisory, routing) and workshop pattern (interactive, extended dialogue) serve different purposes. Combining them would mix interaction patterns. The CMO/brand-architect relationship is the proven precedent.
- **Opinionated with kill gates:** The differentiator vs. asking ChatGPT is enforced sequence and honest assessment. A "guided but supportive" agent would just be a fancy checklist.
- **Named-but-optional frameworks:** Plain-language questions by default, with opt-in deep dives into JTBD, TAM/SAM/SOM, Blue Ocean, Mom Test, Van Westendorp. Accessible to all users, rigorous for those who want it.
- **Web search for competitive landscape:** Scoped to competitor discovery and pricing pages (factual lookup), not market sizing claims (where AI hallucinates).
- **LLM semantic routing in brainstorm Phase 0.5:** CPO auto-detected when feature descriptions involve product validation, market viability, or business model assessment. Consistent with CMO/CTO routing.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Target user | Soleur users broadly | Any user thinking about building something -- side project, internal tool, startup |
| Rigor level | Opinionated with kill gates | Must be willing to say "this looks weak" -- the core differentiator |
| Structure | CPO domain leader + business-validator workshop agent | Clean separation of advisory (CPO) and workshop (validator) concerns |
| Methodology | Named-but-optional frameworks | Framework-agnostic defaults, opt-in deep dives. Accessible yet rigorous |
| Output location | knowledge-base/overview/business-validation.md | Living reference doc consumed by downstream agents (CMO, brand-architect, pricing-strategist) |
| Web research | Yes, for competitive landscape | Scoped to competitor/pricing lookup, not market sizing estimates |
| Brainstorm integration | LLM semantic routing via CPO in Phase 0.5 | Consistent with CTO/CMO pattern |

## Validation Gates (Business Validator)

The CMO designed a 7-step funnel. Each gate has a kill criterion -- if the answer is weak, the agent recommends stopping.

| Gate | Question Answered | Kill Criterion | Optional Framework |
|------|------------------|---------------|-------------------|
| 1. Problem articulation | Can you state the problem without mentioning your solution? | Cannot separate problem from solution = building a feature, not solving a problem | JTBD job statement |
| 2. Customer identification | Who has this problem badly enough to pay? | "Everyone" or cannot name 5 real people = problem not acute | -- |
| 3. Existing alternatives | What do people do today? | Many well-funded competitors + no clear difference = reconsider | Blue Ocean value curve |
| 4. Differentiation | What is specifically different? Why now? | "Better UX" or "AI-powered" with no structural advantage = zero moat | -- |
| 5. Demand evidence | Have you talked to 5+ potential customers? | No customer conversations = everything above is hypothesis, not validation | Mom Test |
| 6. Willingness to pay | Would they pay? How much? | "That's cool" but no commitment of time or money = no market | Van Westendorp |
| 7. Minimum viable scope | What's the smallest thing to test the core value prop? | MVP requires 6+ months of engineering = haven't found the core yet | -- |

Web search runs at Gate 3 (competitive landscape) to find real competitors and pricing data.

## CPO Domain Leader Design

Following the CTO pattern:

| Phase | CPO Responsibility |
|-------|-------------------|
| Assess | Evaluate product implications -- market fit, user impact, validation status |
| Recommend | Suggest product direction with trade-offs (2-3 options when ambiguous) |
| Delegate | Route to business-validator, spec-flow-analyzer, or ux-design-lead as appropriate |
| Sharp Edges | Don't prescribe engineering details. Flag cross-domain concerns but defer to CMO/CTO. |

**Brainstorm Phase 0.5 assessment question:**
> "Product validation implications -- Does this feature involve validating a business idea, assessing market viability, analyzing product-market fit, or deciding whether to build something?"

## Output Document Contract

The validation report heading contract (for downstream agent consumption):

| Heading | Required | Purpose |
|---------|----------|---------|
| `## Problem` | Yes | Problem statement without solution |
| `## Customer` | Yes | Target customer profile |
| `## Competitive Landscape` | Yes | Alternatives and differentiation |
| `## Demand Evidence` | Yes | Customer conversation findings |
| `## Business Model` | Yes | Revenue model and willingness to pay |
| `## Minimum Viable Scope` | Yes | Smallest testable version |
| `## Validation Verdict` | Yes | Go/no-go/pivot recommendation with confidence level |

## Resolved Questions

| Question | Decision |
|----------|----------|
| CPO standalone skill entry point? | Not now -- brainstorm routing is sufficient. Add `/soleur:product` later if needed. |
| Detect and resume existing validation docs? | Yes -- follow brand-architect pattern. Show summary, ask which section to update. |
| Dogfood on Soleur after implementation? | Yes -- run the validator on Soleur as part of this PR. Produces a real case study. |

## Dogfooding

Issue #141 explicitly asks to "apply it to Soleur itself" after implementation. This produces:
1. A real validation report for Soleur as a product
2. A case study proving the tool works
3. Feedback on the agent's usability from actual use
