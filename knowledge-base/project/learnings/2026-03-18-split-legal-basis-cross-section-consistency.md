# Learning: Split legal basis requires cross-section consistency in all legal docs

## Problem

When splitting a legal basis for a single processing activity (e.g., consent for email + legitimate interest for HTTP metadata), the initial plan only updated the primary disclosure section (Section 4.6) and the GDPR basis section (Section 3.6). Plan review caught three additional sections that also needed updating:

1. **Section 5.3** (third-party processor description) — still said "your email address" only
2. **Section 7** (data retention) — had a single retention policy for the entire processing activity, not split retention
3. **6th file** (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`) — a rendered copy of the DPA that was missed in the initial file inventory

## Solution

A legal basis split for one processing activity propagates to every section that references that activity's data types, legal basis, or retention. The complete list for Buttondown newsletter data:

**Privacy Policy:** Section 4.6 (data + basis), Section 5.3 (processor description), Section 6 (legal basis summary), Section 7 (retention)
**GDPR Policy:** Section 3.6 (basis + balancing test), Section 4.2 table (data categories), Section 10 (processing register)
**DPD:** Section 2.3(e) (processing activity description)

Each exists in 2 locations (docs/legal/ + plugins/soleur/docs/pages/legal/) except the DPA source which has 1 copy.

## Key Insight

When a plan review catches missing sections, the issue is usually that the planner enumerated only the sections that directly mention "lawful basis" and missed secondary sections (retention, processor descriptions, rights) that reference the same data types. A legal basis split is a cross-cutting change — grep for the processing activity name (e.g., "Buttondown", "newsletter") across all legal docs to find every reference, not just the ones with "legal basis" or "consent" in them.

## Tags
category: legal-compliance
module: legal-docs
