# Learning: First PII collection requires comprehensive legal doc overhaul

## Problem

Adding the first personal data collection (newsletter email addresses via Buttondown) to a site that previously collected zero PII. Existing legal documents contained blanket statements like "does not collect email addresses" and "Soleur does not collect personal data from any users" that became contradictions once email capture was introduced.

## Solution

### 1. Systematic grep verification catches contradictions

After updating the obvious sections (new data category, processor entry, consent basis, retention policy), grep verification across all legal docs caught two additional contradictions:

- **GDPR Section 12 (Children's Data):** "Soleur does not collect personal data from any users" — required rewording
- **GDPR Section 5 header:** "Because Soleur does not collect or process personal data" — required nuance

The grep patterns that caught these: `"does not collect"`, `"no personal data"`, `"email address"` across all `**/legal/*.md` files.

### 2. Six documents, not three

Legal docs exist in two locations with different frontmatter formats:
- **Published:** `plugins/soleur/docs/pages/legal/` (Eleventy layout frontmatter)
- **Source:** `docs/legal/` (YAML type/jurisdiction frontmatter)

Each policy requires updates in both locations. For newsletter, three policies were affected = 6 file edits.

### 3. Consent vs Legitimate Interest distinction

Previous data processing (analytics, CLA signatures) used legitimate interest (Art. 6(1)(f)). Newsletter email collection requires **consent** (Art. 6(1)(a)) because it involves collecting PII for direct marketing communications. This required a new Section 3.6 in the GDPR Policy rather than extending existing legitimate interest sections.

### 4. Pre-existing numbering issues compound during edits

The GDPR Policy had a pre-existing numbering error (Section 3.5 CLA before Section 3.4 Legal). Fixing this during the newsletter update prevented confusion about the new Section 3.6's placement.

## Key Insight

When a site transitions from zero PII collection to collecting any personal data, every blanket "we don't collect data" statement becomes a potential legal contradiction. Grep verification is not optional — it's the only way to catch statements scattered across 10+ legal document files. Always run the grep verification AFTER all targeted edits, not just on the sections you changed.

## Session Errors

1. **Playwright ref invalidation:** During Buttondown account setup, element references became stale after page auto-navigation. Always take a fresh snapshot before interacting with elements after any page state change.
2. **Edit tool file-not-read rejection:** Attempted to edit `index.njk` after only Grep'ing it. The Edit tool requires a Read call first. Grep results don't satisfy this requirement.

## Tags
category: feature-implementation
module: legal-docs, docs-infrastructure
tags: gdpr, legal-compliance, pii, newsletter, buttondown, grep-verification
