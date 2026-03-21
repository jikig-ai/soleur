# Learning: Legal Cross-Document Audit-Review Cycle

## Problem

When adding new data processors (Supabase, Stripe, Hetzner, Cloudflare) to legal documents, the initial implementation missed several cross-document consistency issues despite following the plan's detailed section-by-section instructions. The legal-compliance-auditor review found 4 critical and 6 high findings after all edits were complete.

Key misses:

- DPD Section 2.1b listed Cloudflare as Article 28 processor but Section 4.2 table omitted it (auditor contradiction)
- Privacy Policy and GDPR Policy rights sections still said "most relevant to GitHub" without mentioning Web Platform
- GDPR Policy data retention section (8) had no Web Platform subsection
- DPD Section 9.2 audit rights still said "if cloud features are introduced" (stale conditional)
- GDPR Policy breach scenarios and DPO assessment didn't mention Web Platform

## Solution

1. Run legal-compliance-auditor agent AFTER all edits are complete (not during -- the agent needs the full picture)
2. The auditor checks 5 dimensions: cross-document consistency, source/Eleventy sync, missing disclosures, section numbering, and remaining blanket statements
3. Fix all P1/P2 findings before committing the review fixes
4. File GitHub issues for out-of-scope contradictions (e.g., Terms & Conditions) rather than expanding scope mid-PR

## Key Insight

Legal documents have a cross-reference graph that is invisible in a section-by-section plan. When a plan says "update Section X with Y," it cannot enumerate all downstream sections that reference the same concept. The legal-compliance-auditor agent is the only reliable way to catch these gaps because it reads all documents holistically. Always run it as a post-edit verification, not a pre-edit check.

The pattern is: edit all documents → run auditor → fix findings → re-verify. Budget for this cycle when planning legal document updates.

## Session Errors

- `worktree-manager.sh feature` failed in bare repo root (not a worktree context). Used `git worktree add` directly.

## Tags

category: integration-issues
module: legal-documents
