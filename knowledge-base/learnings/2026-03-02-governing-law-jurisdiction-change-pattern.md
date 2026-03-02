# Learning: Governing Law Jurisdiction Change Pattern

## Problem

Soleur's T&Cs and Disclaimer referenced Delaware as governing law, but the company is incorporated in France. The CLAs already used French law / Paris courts, creating an internal inconsistency. The initial plan proposed a 5-subsection structure (Governing Law, Amicable Resolution, Jurisdiction, EU/EEA Consumers, Mandatory Law Savings) — nearly doubling the document surface area for what should have been a simplification.

## Solution

1. **Use existing documents as structural templates.** The CLAs' governing law clause (Section 8a) is two sentences: French law + Paris courts. That's the right structural weight.
2. **Plan review catches scope creep.** Two reviewers independently flagged the amicable resolution clause and savings clause as new substantive legal obligations smuggled under a "change governing law" task. Cutting from 5 to 3 subsections (Law, Jurisdiction, EU/EEA Consumers) kept the change focused.
3. **Compliance audit separates pre-existing from introduced issues.** The post-change audit found 14 issues across 9 documents — all pre-existing (e.g., AUP entity attribution, missing governing law in Privacy Policy). None were introduced by this change. Tracking them as deferred follow-ups prevents scope explosion.
4. **Dual-location sync is mechanical but critical.** Legal docs exist in `docs/legal/` (source) and `plugins/soleur/docs/pages/legal/` (Eleventy site) with different frontmatter. Both must be updated in lockstep. Grep verification after editing catches missed references.

## Key Insight

When changing a legal parameter across documents, the existing document suite IS the template. Match the structural weight of what's already there (CLAs = 2 sentences), don't over-engineer the new clause. Plan review is the gate that prevents a "replace jurisdiction" task from becoming a "redesign dispute resolution framework" task.

## Tags
category: legal-agents
module: legal, docs-site
