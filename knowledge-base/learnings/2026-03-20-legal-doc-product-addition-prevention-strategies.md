---
title: "Legal document product addition: section ordering and scoping prevention strategies"
date: 2026-03-20
category: legal-compliance
tags: [legal-documents, prevention, cross-document-consistency, section-ordering, product-addition]
module: legal-docs
---

# Learning: Legal Document Product Addition -- Section Ordering and Scoping Prevention Strategies

## Problem

When adding "Web Platform" as a new product/service to the Terms & Conditions (branch `legal-web-platform-703-736`), two classes of errors occurred:

1. **Section ordering bug:** Section 4.3 (Web Platform Service) was inserted *before* Section 4.2 (Third-Party API Interactions) instead of after it. The plan correctly specified "Add new section between 4.2 and the current Section 5" but the implementation placed the new content at the wrong insertion point within Section 4.

2. **Incomplete scoping:** The initial implementation updated Sections 1, 2, 4.1, 4.3 (new), 7.1, 7.1b (new), 7.4, 9.1, 9.2, 10.1, 10.2, 12, 13.1b (new), 13.3, and 15.1 -- but missed adding "Web Platform" references to Sections 3 (Eligibility), 5.3 (User Content Ownership), 8 (Acceptable Use), 9.2 (SLA disclaimer), 11 (Indemnification), and 13.2 (Termination by Us). These required three additional fix commits after review agents caught the gaps.

Both errors were caught by review agents (legal-compliance-auditor, architecture-strategist, security-sentinel) -- not by the implementer. The fixes were clean but the cycle cost time and commits.

## Root Cause Analysis

### Section Ordering

The plan described insertion points in prose ("Add new section between 4.2 and the current Section 5") but the implementer worked with the Edit tool, which matches text strings rather than structural positions. When the target insertion point is described structurally but executed textually, the mapping is error-prone -- especially in long legal documents where section headers look similar.

### Incomplete Scoping

The plan enumerated specific sections to modify but did not provide a systematic method for discovering *all* sections that reference "the Plugin" as a standalone product term. The plan focused on the sections with false "local-only" statements (the primary legal risk) and missed sections where "the Plugin" appeared as the sole subject but the statement was not factually wrong -- just incomplete after adding the Web Platform.

The distinction: Sections 4.1 and 7.1 said "Soleur does not collect data" (factually wrong after adding a cloud service). Sections 3, 8, 11, and 13.2 said "use the Plugin" (factually incomplete but not contradictory). The plan optimized for fixing false statements and under-prioritized completeness.

## Prevention Strategies

### Strategy 1: Anchor-Based Insertion for Section Ordering

When inserting a new section into a legal document, never rely on prose descriptions of position. Instead:

1. Read the file and identify the *exact text of the heading that should immediately precede the new section*.
2. Use that heading + the first line of its content as the Edit tool's `old_string` anchor.
3. Include the new section in the `new_string`, appended after the anchor content.

Alternatively, identify the *heading of the section that should follow* the new one, and insert the new section text immediately before that heading.

**Verification step:** After every section insertion, read the file and confirm the section numbering sequence is monotonically increasing. A 30-second read is cheaper than an audit-fix-reverify cycle.

```
Checklist:
- [ ] Identified exact preceding section heading as anchor text
- [ ] new_string preserves the anchor and appends the new section
- [ ] Post-edit read confirms section numbers are in order (4.1, 4.2, 4.3 -- not 4.1, 4.3, 4.2)
```

### Strategy 2: Exhaustive Grep Before Implementation

Before making any edits, run a grep for every term that will gain a new qualifier. For adding a new product:

```bash
# Find every standalone "the Plugin" reference that may need "or the Web Platform"
grep -n "the Plugin" docs/legal/terms-and-conditions.md

# Find every "Plugin" as sole subject (not already paired with Web Platform)
grep -n "Plugin" docs/legal/terms-and-conditions.md | grep -v "Web Platform"
```

Classify each match into three buckets:

| Bucket | Action | Example |
|--------|--------|---------|
| **False statement** | Must fix (P1) | "Soleur does not operate cloud servers" |
| **Incomplete scope** | Should fix (P2) | "You agree to use the Plugin only for lawful purposes" |
| **Correctly scoped** | No action | "The Plugin is licensed under BSL 1.1" (license applies to Plugin only) |

The plan should enumerate *all three buckets* with explicit justification for "no action" items. This forces the planner to consider every reference rather than listing only the ones that need changes.

### Strategy 3: Section-by-Section Product Substitution Checklist

When adding a new product/service to legal documents, every section must be evaluated -- not just the ones with obvious problems. Use this classification for each section:

```
For each section in the document:
  1. Does this section mention "the Plugin" or "the Service" as a standalone term?
     - YES: Does the statement also apply to the new product?
       - YES: Add "or the [New Product]" → go to step 2
       - NO: Add scoping language ("This section applies to the Plugin only. For [New Product], see Section X.") → go to step 2
       - PARTIALLY: Split into product-specific subsections → go to step 2
     - NO: Skip (document in the checklist that this section was reviewed and found clean)
  2. Does this section need a new subsection for the new product?
     - YES: Draft and insert at correct position (see Strategy 1)
     - NO: Proceed to next section
```

The critical discipline: *every section gets a line in the checklist, even sections that need no changes.* This forces exhaustive review and makes omissions visible.

### Strategy 4: Dual-Pass Implementation

Split the implementation into two passes:

**Pass 1 -- Structural changes:** Add new definitions, new sections, new subsections. Do not modify existing text. Commit or checkpoint.

**Pass 2 -- Scoping changes:** Using the exhaustive grep from Strategy 2, update every existing reference. This pass is mechanical -- for each grep match, either add "or the [New Product]" or add scoping language.

Separating structure from scoping prevents the cognitive overload of doing both simultaneously, which is where the incomplete scoping error originated. The implementer context-switched between "write new Section 4.3 content" and "update all existing Plugin references" and lost track of the scoping pass.

### Strategy 5: Post-Edit Structural Verification

After all edits are complete and before running the compliance auditor, run these automated checks:

```bash
# 1. Section ordering -- extract all section numbers and verify monotonic order
grep -E '^#{2,3} [0-9]+' docs/legal/terms-and-conditions.md

# 2. Product completeness -- find any remaining Plugin-only references
grep -n "the Plugin" docs/legal/terms-and-conditions.md | grep -v "Web Platform" | grep -v "Plugin only"

# 3. Cross-reference integrity -- verify all "see Section X" references point to existing sections
grep -oE 'Section [0-9]+(\.[0-9]+[a-z]?)?' docs/legal/terms-and-conditions.md | sort -u

# 4. Blanket statement scan -- catch any unscoped absolute claims
grep -n "does not collect\|does not operate\|does not store\|does not transmit" docs/legal/terms-and-conditions.md
```

These four checks take under 10 seconds and would have caught both the ordering bug (check 1) and incomplete scoping (check 2) before the auditor ran.

## Checklist: Adding a New Product/Service to Legal Documents

This is the consolidated checklist for future product additions. Each step references the strategy that motivates it.

### Pre-Implementation

- [ ] **Grep inventory** (Strategy 2): Run `grep -n "the Plugin\|the Service" <file>` and classify every match into false-statement / incomplete-scope / correctly-scoped buckets
- [ ] **Section inventory** (Strategy 3): Create a line-by-line checklist of every section, marking each as needs-change / needs-new-subsection / no-change-needed (with justification)
- [ ] **File inventory**: Enumerate ALL file locations (source + Eleventy + any other rendered copies) that need identical content changes
- [ ] **Insertion point anchors** (Strategy 1): For each new section, identify the exact preceding heading text to use as an Edit anchor

### Implementation

- [ ] **Pass 1 -- Structural** (Strategy 4): Add all new definitions, sections, and subsections without modifying existing text
- [ ] **Pass 1 verification**: Read the file and confirm section numbering is correct
- [ ] **Pass 2 -- Scoping** (Strategy 4): Walk the grep inventory and update every reference that needs "or the [New Product]" or scoping language
- [ ] **Pass 2 verification**: Re-run the grep and confirm zero unaddressed matches remain
- [ ] **Sync to all locations**: Apply identical content to Eleventy copies (converting link formats)

### Post-Implementation

- [ ] **Structural verification** (Strategy 5): Run all four automated checks (ordering, completeness, cross-references, blanket statements)
- [ ] **Compliance auditor**: Run legal-compliance-auditor on all source documents
- [ ] **Fix-reverify cycle**: Fix any P1/P2 findings and re-run the auditor (budget for one cycle -- per learning `2026-03-18-legal-cross-document-audit-review-cycle.md`)
- [ ] **Cross-document grep**: Run blanket statement grep across ALL legal documents, not just the one being edited

## Key Insight

Legal document updates that add a new product have two orthogonal dimensions of completeness: *structural* (new sections in the right order) and *referential* (existing text updated everywhere). Plans naturally focus on the structural dimension because new sections are the visible deliverable. The referential dimension is invisible until grep makes it visible. Running the exhaustive grep BEFORE implementation -- and classifying every match with an explicit action or justification -- is the single highest-leverage prevention step. It converts an unbounded "did I miss anything?" question into a bounded checklist.

## Tags
category: legal-compliance
module: legal-docs
