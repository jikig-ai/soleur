# Learning: DPD sub-processor section contradiction fix

## Problem

The Data Protection Disclosure contained an internal contradiction: Section 4.1 ("No Sub-processors") stated there were no sub-processors to disclose, while Section 2.3(e) named Buttondown as a data processor and Section 4.2's table listed Buttondown as "data processor on behalf of Jikigai." The contradiction arose because Section 4.1 was written for the Plugin's local-only architecture and was not updated when Buttondown was added as a newsletter processor in the March 10 update.

## Solution

Restructured Section 4 into three distinct subsections:

1. **4.1 Plugin Sub-processors** — Scoped the "no sub-processors" statement to the Plugin only, with cross-reference to Section 2.1
2. **4.2 Docs Site Processors** — New section disclosing Buttondown as a processor with a structured table (processor, processing activity, data processed, legal basis, sub-processor list link) and explicit cross-reference to Section 2.3(e)
3. **4.3 Third-Party Services Used by Users** — Renumbered from old 4.2, with Buttondown removed (it now belongs in 4.2)

Also filed #690 for a pre-existing Privacy Policy cross-reference bug (Section 4.6 references wrong section for Buttondown).

## Key Insight

When adding a new data processing relationship to a legal document, audit ALL sections — not just the one being updated. The Buttondown addition correctly updated Section 2.3(e) but missed the blanket "no sub-processors" statement in Section 4.1. Legal documents have interdependent sections where a change in one creates contradictions in others. The legal-compliance-auditor agent caught this, validating its value as a post-change verification step.

GDPR terminology precision matters: Buttondown is a **processor** (not sub-processor) because Jikigai acts as Controller, not Processor. Article 28 defines sub-processors as processors engaged by other processors. Getting this wrong in legal documents undermines credibility with supervisory authorities.

## Session Errors

1. Merge conflict when merging origin/main — `knowledge-base/project/plans/` was renamed to `knowledge-base/project/plans/` on main, causing a file location conflict for the plan file created in a prior session. Resolved by staging at the new path.
2. Eleventy docs build failure — pre-existing issue where `agents.js` resolves paths relative to docs dir. Unrelated to this change.

## Tags
category: legal-compliance
module: data-protection-disclosure
