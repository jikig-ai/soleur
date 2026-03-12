# Case Study: Business Validation Workshop

## The Problem

A technical founder building a product they use daily faces a specific blind spot: they cannot distinguish between "I need this" and "the market needs this." Soleur had 280+ merged PRs, 65+ agents across 8 domains, and daily dogfooding across every function -- but zero external users validating the multi-domain thesis. The question was not "does the product work?" but "does the problem statement resonate with anyone besides the builder?"

## The AI Approach

The business validation was run through the product domain, orchestrated by the `business-validator` agent following a structured gate framework:

1. **Gate 1 -- Problem**: Define the problem statement in solution-free language. Assess whether the pain is real, structural, and independently articulable.
2. **Gate 2 -- Customer**: Define the target customer profile with specificity. Identify reachable examples. Test whether the segment is tight enough.
3. **Gate 3 -- Competitive Landscape**: Map the full competitive landscape across 6 tiers (platform-native, closest substitutes, no-code agent platforms, CaaS, agent frameworks, DIY stacks). Identify structural advantages and vulnerabilities.
4. **Gate 4 -- Demand Evidence**: Assess direct and indirect demand signals. Apply a kill criterion: if demand evidence is below threshold, flag it.
5. **Gate 5 -- Business Model**: Evaluate revenue model options against the customer profile and competitive landscape.
6. **Gate 6 -- Minimum Viable Scope**: Define what must be tested and why breadth is the minimum scope (not a nice-to-have).

Each gate produces a PASS, CONDITIONAL PASS, FLAG, or FAIL verdict. A FLAG at Gate 4 triggers a kill criterion review.

## The Result

A 3,627-word business validation document (`knowledge-base/overview/business-validation.md`) containing:

- **Problem assessment**: PASS. Twofold framing (capacity gap + expertise gap) validated as real, structural, and solution-independent.
- **Customer assessment**: CONDITIONAL PASS. Specific profile defined (technical solo founders across all stages), but named contacts fell below the 5-person threshold.
- **Competitive landscape**: PASS (later updated to CONDITIONAL PASS after Tier 0 threat materialization). 19 competitors mapped across 6 tiers with structural advantages and vulnerabilities.
- **Demand evidence**: FLAG with OVERRIDE. Kill criterion triggered at Gate 4 -- only 1-2 informal conversations versus the 5+ threshold. User chose to proceed with strong external signals (Naval Ravikant, Amodei predictions, solo founder growth statistics).
- **Business model**: CONDITIONAL PASS. Four revenue model options evaluated with competitor pricing context.
- **Minimum viable scope**: PASS. Breadth validated as minimum scope via coherence check.
- **Final verdict**: PIVOT -- from building features to validating the thesis with real users. A 7-step action plan defined.
- **Vision alignment check**: Validated that the pivot does not contradict the brand guide's positioning.

## The Cost Comparison

A startup strategy consultant or fractional CPO charges $200-400/hour for business validation work. A structured validation workshop covering problem definition, customer profiling, competitive landscaping, demand assessment, business model evaluation, and scope definition typically runs 20-40 hours: $4,000-16,000. A startup accelerator provides similar validation as part of a cohort program (valued at $10,000-25,000 in advisory). The AI-produced validation was generated through the brainstorm workflow with the `business-validator` agent, iterated through multiple sessions, and updated when new competitive data invalidated prior assessments.

## The Compound Effect

The business validation is the strategic anchor for the entire project. The competitive intelligence report references it as the baseline. The pricing strategy is constrained by its business model assessment. The PIVOT verdict directly changed the project's activity from feature development to user validation. The kill criterion at Gate 4 -- demand evidence is thin -- is the most important finding in the entire knowledge base, because it prevents the founder from building in a vacuum. Future validation cycles (after the 10 user interviews prescribed in step 3) will update this document, and every downstream artifact (competitive strategy, pricing, content calendar) will re-derive from the updated verdicts.
