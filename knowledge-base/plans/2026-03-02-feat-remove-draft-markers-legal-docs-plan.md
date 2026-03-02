---
title: "feat: Remove DRAFT markers from legal documents"
type: feat
date: 2026-03-02
---

# Remove DRAFT markers from legal documents after legal review

## Enhancement Summary

**Deepened on:** 2026-03-02
**Sections enhanced:** 4 (Acceptance Criteria, Context, Test Scenarios, Non-goals)

### Key Improvements
1. Identified two additional files with "draft" references that must NOT be changed (legal-generate skill, CLO agent) -- added to explicit preserve list
2. Corrected acceptance criteria: the legal-document-generator agent does NOT need changes (its description and DRAFT template are about newly generated docs, not the project's own reviewed docs)
3. Added verification commands from institutional learnings (sed-silent-failure pattern, dual-location sync pattern)

### Applicable Learnings
- `2026-03-02-governing-law-jurisdiction-change-pattern.md`: Dual-location sync is mechanical but critical; grep verification after editing catches missed references
- `2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md`: Use `grep -rL` after batch operations to verify changes landed
- `2026-02-20-dogfood-legal-agents-cross-document-consistency.md`: The DPA-to-DPD rename is a known historical event; the filename discrepancy is documented

## Overview

All 7 legal documents (excluding the two CLAs) and the legal landing page carry "DRAFT -- requires professional legal review" banners. With professional legal review complete, these markers must be removed from both source docs and rendered site pages. The Terms & Conditions body text referencing "drafts" also needs updating.

Closes #189.

## Acceptance Criteria

- [x] DRAFT blockquote banners removed from top and bottom of 7 source docs in `docs/legal/`
- [x] DRAFT blockquote banners removed from top and bottom of 7 rendered pages in `plugins/soleur/docs/pages/legal/`
- [x] Landing page (`plugins/soleur/docs/pages/legal.njk` line 22) no longer mentions "drafts" or "professional legal review"
- [x] Terms & Conditions section 6.2 body text -- no change needed (describes generator output, not project docs)
- [x] Plugin version bumped (PATCH) in `plugin.json`, `CHANGELOG.md`, `README.md`, `marketplace.json`
- [x] Site builds successfully (`npx @11ty/eleventy`)
- [x] No remaining unintended "DRAFT" references in legal files (verified by grep)
- [x] Explicit preserve list verified unchanged (see "Files to preserve unchanged" below)

## Test Scenarios

- Given the 7 legal source docs, when grepping for "DRAFT", then zero matches are returned
- Given the 7 legal rendered pages, when grepping for "DRAFT", then zero matches are returned
- Given `legal.njk`, when reading line 22, then the text does not mention "drafts" or "professional legal review"
- Given the CLA files (`individual-cla.md`, `corporate-cla.md`), when grepping for "DRAFT", then zero matches (unchanged -- they already lack markers)
- Given the `legal-document-generator.md` agent, when reading its instructions, then the DRAFT blockquote template is unchanged (the generator produces drafts by design)
- Given the `legal-generate/SKILL.md` skill, when reading its content, then all three "draft" references are unchanged
- Given the `clo.md` agent, when reading its sharp edges, then the "draft material requiring professional legal review" line is unchanged
- Given a fresh site build, when running `npx @11ty/eleventy`, then it exits 0 with no warnings
- Given the full codebase, when running the verification commands below, then all checks pass

### Verification Commands

After all edits, run these in sequence:

```bash
# 1. Verify DRAFT markers removed from source docs (expect 0 matches)
grep -r "DRAFT" docs/legal/ | grep -v corporate-cla | grep -v individual-cla

# 2. Verify DRAFT markers removed from rendered pages (expect 0 matches)
grep -r "DRAFT" plugins/soleur/docs/pages/legal/ | grep -v corporate-cla | grep -v individual-cla

# 3. Verify landing page updated (expect 0 matches)
grep -i "draft" plugins/soleur/docs/pages/legal.njk

# 4. Verify preserve list unchanged -- these should STILL contain "draft" references
grep -c "draft" plugins/soleur/agents/legal/legal-document-generator.md  # expect 2+
grep -c "draft" plugins/soleur/skills/legal-generate/SKILL.md            # expect 3
grep -c "draft" plugins/soleur/agents/legal/clo.md                       # expect 1
grep -c "draft" plugins/soleur/CHANGELOG.md                              # expect 1+
grep -c "draft" plugins/soleur/README.md                                 # expect 2

# 5. Build site (expect exit 0)
npx @11ty/eleventy
```

## Context

### File inventory

**Source docs with DRAFT markers (7 files, 2 markers each = 14 removals):**

| File | Line (top) | Line (bottom) |
|------|-----------|---------------|
| `docs/legal/acceptable-use-policy.md` | 8 | 222 |
| `docs/legal/cookie-policy.md` | 8 | 160 |
| `docs/legal/data-processing-agreement.md` | 8 | 267 |
| `docs/legal/disclaimer.md` | 8 | 206 |
| `docs/legal/gdpr-policy.md` | 8 | 268 |
| `docs/legal/privacy-policy.md` | 8 | 196 |
| `docs/legal/terms-and-conditions.md` | 8 | 264 |

**Rendered pages with DRAFT markers (7 files, 2 markers each = 14 removals):**

| File | Line (top) | Line (bottom) |
|------|-----------|---------------|
| `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` | 19 | 232 |
| `plugins/soleur/docs/pages/legal/cookie-policy.md` | 19 | 170 |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 19 | 277 |
| `plugins/soleur/docs/pages/legal/disclaimer.md` | 19 | 216 |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 19 | 278 |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | 19 | 206 |
| `plugins/soleur/docs/pages/legal/terms-and-conditions.md` | 19 | 274 |

**Landing page (1 text change):**

- `plugins/soleur/docs/pages/legal.njk` line 22: Replace draft-referencing text with reviewed status

**Terms & Conditions section 6.2 (2 text changes):**

- `docs/legal/terms-and-conditions.md` line 104
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md` line 114

### Files to preserve unchanged

These files reference "draft" in the context of the legal-document-generator's output behavior, NOT the project's own reviewed documents. They must remain unchanged:

| File | Draft reference context | Why preserve |
|------|----------------------|--------------|
| `plugins/soleur/agents/legal/legal-document-generator.md` | DRAFT blockquote template for newly generated docs | Generator should still produce draft-marked output |
| `plugins/soleur/skills/legal-generate/SKILL.md` | "Generate draft legal documents", "Draft written to", "mandatory DRAFT disclaimers" | Skill description of generator capability |
| `plugins/soleur/agents/legal/clo.md` | "draft material requiring professional legal review" | CLO sharp edge about agent output |
| `plugins/soleur/CHANGELOG.md` | "drafting legal documents" | Historical changelog entry |
| `plugins/soleur/README.md` | "Generate draft legal documents" (2 occurrences) | Agent/skill capability descriptions |

### Filename discrepancy

The source directory has `data-processing-agreement.md` while the rendered pages directory has `data-protection-disclosure.md`. This is a known historical rename documented in `2026-02-20-dogfood-legal-agents-cross-document-consistency.md` (the DPA was renamed to "Data Protection Disclosure" to resolve a structural contradiction). Not introduced by this feature; do not fix in this PR.

### Version bump

This changes plugin files (`plugins/soleur/docs/pages/legal/` and `plugins/soleur/docs/pages/legal.njk`), so a PATCH version bump is required per AGENTS.md. Intent: PATCH.

### Implementation approach

Use the Edit tool for each file rather than batch sed -- the sed-silent-failure learning (`2026-02-14`) warns that sed's append/insert commands fail silently when patterns do not match. The Edit tool provides exact string matching with failure feedback. Process source docs first, then rendered pages (same blockquote text in both), then the landing page and T&C body text.

## Non-goals

- Rewriting or restructuring legal document content
- Fixing the `data-processing-agreement` / `data-protection-disclosure` filename mismatch
- Changing the legal-document-generator agent's DRAFT template for newly generated documents
- Changing the legal-generate skill's draft-related descriptions
- Changing the CLO agent's sharp edges about draft output
- Updating archived specs, plans, or brainstorms that reference the old DRAFT status

## References

- Issue: #189
- Constitution learning on dual-location legal docs: `knowledge-base/overview/constitution.md` line 168
- Governing law change pattern (dual-location sync precedent): `knowledge-base/learnings/2026-03-02-governing-law-jurisdiction-change-pattern.md`
- Sed silent failure pattern: `knowledge-base/learnings/2026-02-14-sed-insertion-fails-silently-on-missing-pattern.md`
- DPA rename history: `knowledge-base/learnings/2026-02-20-dogfood-legal-agents-cross-document-consistency.md`
- Legal document generator agent: `plugins/soleur/agents/legal/legal-document-generator.md`
