---
title: "How We Generated 9 Legal Documents in Days, Not Months"
date: 2026-03-10
description: "AI agents produced 9 legal documents -- Terms, Privacy Policy, GDPR, CLAs -- totaling 17,761 words with dual-jurisdiction coverage in days, not months."
tags:
  - case-study
  - legal
  - company-as-a-service
---

Soleur needed a full legal compliance suite for its documentation site (soleur.ai) and platform distribution. The requirements: Terms & Conditions, Privacy Policy, Cookie Policy, GDPR Policy, Acceptable Use Policy, Data Protection Disclosure, Disclaimer, and two Contributor License Agreements (Individual and Corporate). These documents needed to address dual-jurisdiction concerns (French incorporation under Jikigai at 25 rue de Ponthieu, 75008 Paris, plus global distribution including EU/GDPR and US users), reference the correct data controller/processor distinctions for a local-first architecture, and maintain cross-document consistency across all 9 documents.

A solo founder building a software platform does not know how to write GDPR-compliant data protection disclosures or draft CLA patent grant clauses that account for French moral rights law. These are domains where getting it wrong creates real legal exposure.

## The AI Approach

The legal domain was built as a first-class organizational function: two agents (`legal-document-generator` and `legal-compliance-auditor`) plus a domain leader (`CLO`) that orchestrates them. The workflow proceeded in phases:

1. **Brainstorm** (2026-02-19): Defined scope -- 7 initial document types, jurisdiction requirements, dogfooding model.
2. **Generation**: The `legal-document-generator` agent produced first drafts from company context (entity name, address, product architecture, data practices).
3. **Audit**: The `legal-compliance-auditor` ran regulatory benchmarking against GDPR Articles 13/14, CCPA requirements, ICO cookie guidance, and CNIL recommendations.
4. **Iteration**: Multiple rounds -- governing law was corrected from Delaware (inherited from US templates) to French law/Paris courts (2026-03-02 brainstorm). CLAs were added in a separate cycle (2026-02-26) after identifying IP risks with BSL 1.1 licensing.
5. **Benchmark**: Peer comparison against Basecamp, GitHub, and GitLab policies for structural gap analysis.

## The Result

9 legal documents totaling 17,761 words across 1,872 lines of structured markdown with HTML templates:

| Document | Words | Effective Date |
|----------|-------|----------------|
| Terms & Conditions | 2,565 | Feb 20, 2026 |
| Privacy Policy | 2,114 | Feb 20, 2026 |
| GDPR Policy | 2,988 | Feb 20, 2026 |
| Data Protection Disclosure | 2,273 | Feb 20, 2026 |
| Disclaimer | 1,975 | Feb 20, 2026 |
| Acceptable Use Policy | 1,833 | Feb 20, 2026 |
| Cookie Policy | 1,473 | Feb 20, 2026 |
| Individual CLA | 1,247 | Feb 26, 2026 |
| Corporate CLA | 1,293 | Feb 26, 2026 |

Each document addresses dual-jurisdiction (French governing law with mandatory-law savings clauses for EU consumers under Rome I Art. 6), references the correct data architecture (local-first, no server-side data collection), and cross-references related documents. All deployed to the live documentation site at soleur.ai.

## The Cost Comparison

According to [Robert Half's 2026 Legal Salary Guide](https://www.roberthalf.com/us/en/insights/salary-guide/legal), senior technology lawyers in France or the US command EUR 300-500/hour for SaaS legal document drafting (as of 2026). A full legal compliance suite covering 9 documents -- with cross-document consistency, dual-jurisdiction coverage, and regulatory benchmarking -- typically runs 30-50 billable hours. That puts the cost at EUR 9,000-25,000 and 3-6 weeks of elapsed time. A legal startup package from a boutique firm starts around EUR 5,000 for a basic set without CLAs or regulatory benchmarking. The AI-generated suite was produced across several sessions over 2 weeks, with multiple audit and revision cycles included.

## The Compound Effect

The legal documents feed forward in three ways. First, the `legal-compliance-auditor` agent now exists as a reusable capability -- any Soleur user can audit their own project's legal documents against the same regulatory checklists. Second, the CLO domain leader participates in brainstorm sessions automatically when legal implications are detected, so future product decisions get legal assessment without a separate workflow. Third, the governing law correction (Delaware to France) was caught by the system's own audit capability and propagated across all 9 documents consistently -- exactly the kind of cross-document coherence that falls apart when using separate tools or templates for each document.

## Frequently Asked Questions

<details>
<summary>Can AI generate legal documents?</summary>

Yes. Soleur's legal domain agents produce Terms & Conditions, Privacy Policies, GDPR Policies, CLAs, and more with dual-jurisdiction coverage. All documents are generated as drafts requiring professional legal review — the platform accelerates production, not replaces counsel.

</details>

<details>
<summary>How long does AI legal document generation take?</summary>

Nine legal documents totaling 17,761 words were produced across several sessions over two weeks, including multiple audit and revision cycles. According to [Robert Half's 2026 Legal Salary Guide](https://www.roberthalf.com/us/en/insights/salary-guide/legal), technology lawyers charge EUR 300-500/hour (as of 2026), putting equivalent scope at EUR 9,000–25,000 over 30–50 billable hours.

</details>

<details>
<summary>Who is AI legal document generation for?</summary>

Solo founders and small teams who need a full legal compliance suite without the upfront cost of a law firm engagement. The generated documents address jurisdiction requirements, cross-document consistency, and regulatory benchmarking — then a lawyer reviews the output.

</details>

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Can AI generate legal documents?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Yes. Soleur's legal domain agents produce Terms & Conditions, Privacy Policies, GDPR Policies, CLAs, and more with dual-jurisdiction coverage. All documents are generated as drafts requiring professional legal review — the platform accelerates production, not replaces counsel."
      }
    },
    {
      "@type": "Question",
      "name": "How long does AI legal document generation take?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Nine legal documents totaling 17,761 words were produced across several sessions over two weeks, including multiple audit and revision cycles. According to Robert Half's 2026 Legal Salary Guide, technology lawyers charge EUR 300-500/hour (as of 2026), putting equivalent scope at EUR 9,000–25,000 over 30–50 billable hours."
      }
    },
    {
      "@type": "Question",
      "name": "Who is AI legal document generation for?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Solo founders and small teams who need a full legal compliance suite without the upfront cost of a law firm engagement. The generated documents address jurisdiction requirements, cross-document consistency, and regulatory benchmarking — then a lawyer reviews the output."
      }
    }
  ]
}
</script>
