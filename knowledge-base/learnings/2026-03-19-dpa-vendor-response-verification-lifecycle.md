# Learning: DPA vendor response verification lifecycle

## Problem

When a third-party vendor (Buttondown) responds to DPA gap analysis with document updates, the verification and legal doc update process touches many files across dual locations. In this session, updating 8 files across source (`docs/legal/`) and Eleventy (`plugins/soleur/docs/pages/legal/`) resulted in one source file (`docs/legal/data-processing-agreement.md`) being missed entirely — it was 9 days behind the Eleventy copy. The legal-compliance-auditor caught this, but only because we ran it before committing.

## Solution

The full DPA vendor response lifecycle:

1. **Fetch and verify** the vendor's updated documents directly (don't trust the email summary alone — fetch the actual DPA URL and extract specific clause text)
2. **Update knowledge artifacts first** (verification memo, brainstorm, plan) with the vendor's response and re-assessment
3. **Update ALL legal doc locations** — enumerate every file that references the vendor before editing:
   - `docs/legal/privacy-policy.md` (source)
   - `docs/legal/gdpr-policy.md` (source)
   - `docs/legal/data-processing-agreement.md` (source DPD)
   - `plugins/soleur/docs/pages/legal/privacy-policy.md` (Eleventy)
   - `plugins/soleur/docs/pages/legal/gdpr-policy.md` (Eleventy)
   - `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Eleventy)
4. **Run legal-compliance-auditor BEFORE committing** — it catches cross-document inconsistencies, stale dates, missing data types, and divergent source/Eleventy copies
5. **File GitHub issues for pre-existing findings** — don't fix everything in the current PR

## Key Insight

The dual-location legal doc architecture (source in `docs/legal/` + Eleventy copy in `plugins/soleur/docs/pages/legal/`) with different filenames (`data-processing-agreement.md` vs `data-protection-disclosure.md`) is a sync trap. Always enumerate ALL files referencing a vendor before starting edits, and always run the compliance auditor as a gate before commit. The auditor is not optional — it's the only reliable way to catch missed locations when files have inconsistent names.

## Session Errors

None detected.

## Cross-References

- Related learning: `2026-03-11-third-party-dpa-gap-analysis-pattern.md` (the gap analysis pattern this lifecycle extends)
- Related learning: `2026-03-02-legal-doc-bulk-consistency-fix-pattern.md` (dual-location sync pattern)
- Related learning: `2026-02-21-github-dpa-free-plan-scope-limitation.md` (plan tier precedent — Buttondown is opposite: covers all tiers)
- PR: #528
- Issue filed: #741 (filename mismatch)
- Issue: #529 (original DPA verification tracking)

## Tags
category: integration-issues
module: legal-docs
