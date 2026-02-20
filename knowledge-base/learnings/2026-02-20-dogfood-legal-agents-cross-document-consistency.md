# Learning: Legal Agent Dogfooding -- Cross-Document Consistency

## Problem

Generated 7 legal documents using `legal-document-generator` and the initial compliance audit found 51 findings (8 Critical, 20 High). The most impactful issues were cross-document inconsistencies: no legal entity disclosed, no contact email, jurisdiction mismatches, placeholder dates, and a structural contradiction where a "Data Processing Agreement" existed for a tool with no processor relationship.

## Solution

1. **Systematic cross-document fixes**: Standardized jurisdiction ("EU, US"), contact info (legal@soleur.ai), legal entity ("Jikig AI"), and dates across all 7 documents
2. **Renamed DPA to "Data Protection Disclosure"**: Resolved the structural contradiction of having a binding DPA when no processor relationship exists
3. **Reconciled controller/processor status**: GDPR Policy now acknowledges limited controller status for Docs Site/GitHub repo; DPD explains local-only architecture
4. **Two audit cycles**: Initial audit (51 findings), fix, re-audit (4 remaining), fix again to zero

## Key Insight

The legal-document-generator creates each document independently, so cross-document consistency must be verified post-generation. The compliance auditor catches these issues well. Budget for a generate-audit-fix-reaudit cycle, not one-shot generation.

Three agent improvements to make:
- **Pre-generation context**: Collect entity name, email, jurisdiction, architecture type upfront
- **Template selection guard**: For local-only tools, suggest "Data Protection Disclosure" instead of "Data Processing Agreement"
- **Post-generation consistency pass**: Align contact info, jurisdiction, entity references across all docs

## Tags
category: integration-issues
module: legal-agents
tags: [legal-document-generator, legal-compliance-auditor, dogfooding, cross-document-consistency, GDPR]
