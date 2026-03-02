# Learning: Legal Document Bulk Consistency Fix Pattern

## Problem

During the governing law change (feat-french-governing-law, #360), a compliance audit identified 14 pre-existing inconsistencies across 9 legal documents. Issues fell into 4 categories:

1. **Entity attribution** (10 items): Documents used "Soleur" as the legal entity instead of "Jikigai" in introductions, indemnification clauses, and liability sections
2. **Frontmatter jurisdiction** (7 files): `jurisdiction: EU, US` should be `jurisdiction: FR, EU` since Jikigai is incorporated in France
3. **Missing governing law sections** (2 files): AUP and GDPR Policy lacked governing law clauses present in T&Cs, Disclaimer, and CLAs
4. **Stale cross-references** (1 file): Cookie Policy didn't reference T&Cs for governing law

## Solution

Systematic bulk editing with dual-location sync:

1. **Scope all edits first** -- Used an explore agent to map every edit across all 16 files (9 in `docs/legal/` + 7 in `plugins/soleur/docs/pages/legal/`) before touching any file
2. **Edit source files first** (`docs/legal/`) -- Applied all entity, frontmatter, governing law, and cross-reference fixes
3. **Mirror to docs-site copies** (`plugins/soleur/docs/pages/legal/`) -- Applied identical body content changes (no jurisdiction frontmatter in docs-site copies)
4. **Grep verification** -- Ran targeted greps for every pattern that should have been eliminated:
   - `Soleur ("we` -- zero matches
   - `the Soleur project ("we` -- zero matches
   - `hold harmless Soleur` -- zero matches
   - `SHALL SOLEUR` -- zero matches
   - `Soleur-operated` -- only DPA technical architecture references remain (correct)

Key differences between the two file locations:
- `docs/legal/`: Has `type`, `jurisdiction`, `generated-date` frontmatter; uses `.md` relative links
- `plugins/soleur/docs/pages/legal/`: Has `layout`, `permalink`, `description` frontmatter; uses `/pages/legal/*.html` absolute links; wrapped in `<section>` HTML tags

## Session Errors

1. **Edit tool "File has not been read yet"** -- After context compaction in a continued session, the Edit tool requires files to be re-read. Solution: batch-read all target files before applying edits.

## Key Insight

Legal compliance audits always surface pre-existing issues beyond the original scope. The pattern: file a GitHub issue immediately (#363) to track them, then fix in a dedicated follow-up PR. Don't try to fix them inline in the original feature PR -- that creates scope creep. Don't just note them in conversation -- conversation context is ephemeral; GitHub issues persist.

When fixing entity attribution, the distinction matters: "Soleur" is the product name, "Jikigai" is the legal entity. Use "Jikigai" in legal contexts (controller/processor identification, indemnification, liability caps, governing law). Use "Soleur" for product descriptions (features, architecture, behavior).

## Tags
category: integration-issues
module: legal-documents
