# Learning: DPD processor table dual-file sync gap

## Problem

DPD Section 4.2 (Docs Site Processors) listed only Buttondown; GitHub Pages and Plausible Analytics were missing despite both being active data processors for the docs site. Additionally, the root source copy (`docs/legal/data-processing-agreement.md`) was entirely out of sync with the Eleventy source (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`) — PR #686 had restructured Section 4 in the Eleventy source but never propagated the structural changes to the root copy.

## Solution

Added GitHub Pages and Plausible Analytics rows to the Section 4.2 processor table in both file copies, based on verified DPA research (GitHub's data protection agreement for Pages, Plausible's DPA for cookie-free analytics). Restructured the root copy's Section 4 to match the Eleventy source's three-subsection layout (4.1 Plugin Sub-processors, 4.2 Docs Site Processors, 4.3 Third-Party Services Used by Users). Moved Buttondown from the user-initiated services table to the processor table in the root copy to match. During review, trimmed the Plausible "Data Processed" column — it had reproduced salt-rotation implementation details that belong in Section 2.3(a), replaced with a cross-reference. Filed three pre-existing issues (#699, #700, #701) discovered during the audit.

## Key Insight

The DPD's dual-file pattern (Eleventy source for the docs site build, root copy for GitHub rendering) means every structural change must touch both files in the same PR. When PR #686 restructured the Eleventy source's Section 4 without updating the root copy, the drift was invisible until #693 audited both files side by side. Mitigation: any PR that modifies a dual-sourced legal document should include a diff comparison of both copies as a verification step, or file a follow-up issue immediately if the second copy is deferred.

A secondary review insight: summary tables in legal documents should cross-reference detailed sections rather than reproducing implementation specifics. The Plausible row's original "Data Processed" text included salt-rotation mechanics that made the column overlong and duplicated content already covered in Section 2.3(a). Cross-references keep tables scannable and avoid stale-detail risk.

## Tags
category: legal-compliance
module: data-protection-disclosure
