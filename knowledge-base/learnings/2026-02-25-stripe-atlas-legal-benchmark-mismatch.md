# Learning: Stripe Atlas is corporate formation docs, not SaaS legal policies

## Problem

User asked to compare their legal documents (ToS, Privacy Policy, Cookie Policy, etc.) against "Stripe Atlas legal documents." This sounds reasonable -- Stripe Atlas is well-regarded and associated with high-quality legal templates.

## Solution

The CLO assessment revealed the premise was wrong. Stripe Atlas provides **corporate formation documents** (bylaws, stock purchase agreements, IP assignments via Orrick templates), not customer-facing SaaS legal policies. Comparing a pre-revenue SaaS plugin's ToS against Stripe's own policies would be comparing against a publicly traded financial services company under PCI-DSS and money transmission regulations -- an apples-to-oranges mismatch that could lead to over-committing to obligations the company cannot fulfill.

The valuable kernel: audit documents against **regulatory checklists** (GDPR Art 13/14 enumerated disclosures) and **similar-stage peer SaaS policies** (Basecamp, GitHub, GitLab). Regulatory benchmarking requires zero external dependencies and delivers the highest legal value. Peer comparison is best-effort due to WebFetch unreliability.

## Key Insight

When users ask to "benchmark against $FAMOUS_COMPANY," challenge the premise before building. The brand association may not match the actual document type or scope. Stripe Atlas = corporate formation. Stripe's own policies = financial services compliance at massive scale. Neither is the right benchmark for a SaaS plugin's customer-facing legal docs. The right benchmarks are: (1) the regulation itself (GDPR Art 13/14 has 13 enumerated disclosure requirements), and (2) peer companies at a similar stage and product category.

## Tags
category: integration-issues
module: legal-agents
