# Legal Benchmark Audit

**Date:** 2026-02-25
**Status:** Decided
**Participants:** User, CLO (legal assessment)

## What We're Building

Extend the existing `legal-compliance-auditor` agent and `legal-audit` skill with a **benchmark mode** that:

1. **Regulatory benchmarking** — checks each legal document against authoritative regulatory checklists (GDPR Article 13/14 required disclosures, CCPA disclosure requirements, ICO guidance, CNIL cookie recommendations) rather than just internal consistency.
2. **Peer comparison** — fetches public legal policies from similar-stage SaaS companies (Basecamp/37signals, GitHub, GitLab, and agent-selected peers) and flags structural gaps, missing clauses, and coverage differences.

Both produce integrated findings in the existing severity-scored format (CRITICAL/HIGH/MEDIUM/LOW), merged into one unified audit report.

## Why This Approach

### Original Idea Correction

The original idea was "compare against Stripe Atlas legal documents." The CLO assessment revealed this is based on a misunderstanding: Stripe Atlas provides **corporate formation documents** (bylaws, stock purchase agreements, IP assignments via Orrick templates), not customer-facing SaaS legal policies. Comparing Soleur's ToS/Privacy Policy against Stripe's own policies would be comparing a pre-revenue Claude Code plugin against a publicly traded financial services company under PCI-DSS and money transmission regulations — an apples-to-oranges mismatch that could lead to over-commitment.

### Why Extend the Existing Auditor

- The regulatory checklist is just more detailed compliance checking — already the auditor's core job.
- Peer comparison is a natural extension of "find gaps in our documents."
- Keeps agent count stable (no new agents, no token budget increase).
- Reuses existing finding severity format — one unified output, no separate reports to reconcile.

### Why Live Fetch for Peer Policies

- Peer policies change over time; cached versions go stale.
- Eliminates maintenance burden of a reference directory.
- WebFetch is sufficient for structural comparison (we're comparing clause coverage, not verbatim text).

## Key Decisions

1. **Extend existing agent, not new agent** — `legal-compliance-auditor` gains benchmark capabilities alongside its existing compliance checks.
2. **New sub-command on `legal-audit` skill** — `legal-audit benchmark` triggers the enhanced mode; plain `legal-audit` runs the standard compliance check.
3. **Live fetch for peer policies** — agent uses WebFetch at audit time to pull current versions of peer SaaS policies.
4. **Agent selects peers** — curated starting list (Basecamp, GitHub, GitLab) but the agent picks the most relevant peer per document type based on similar stage and product category.
5. **Integrated findings** — peer comparison gaps and regulatory benchmark gaps appear alongside compliance findings in the same severity-scored format.
6. **Regulatory checklists** — GDPR Article 13/14 required disclosures, CCPA requirements, ICO cookie guidance, CNIL recommendations.

## Open Questions

1. **Peer selection criteria** — How does the agent decide which peer is "most relevant" for each document type? Need clear heuristics (company stage, product type, licensing model, jurisdiction).
2. **WebFetch limitations** — WebFetch summarizes content through a model. For structural comparison this is acceptable, but it may miss fine-grained clause details. May need fallback to `curl` for specific cases (per BSL migration learning).
3. **Rate of change** — How often should benchmarks be re-run? After every legal document edit? On a schedule? Only on demand?
4. **Professional review gate** — All 7 documents are still DRAFT. Should the benchmark audit block or flag the absence of professional legal review?
