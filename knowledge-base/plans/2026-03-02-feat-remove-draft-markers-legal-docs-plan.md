---
title: "feat: Remove DRAFT markers from legal documents"
type: feat
date: 2026-03-02
---

# Remove DRAFT markers from legal documents after legal review

## Overview

All 7 legal documents (excluding the two CLAs) and the legal landing page carry "DRAFT -- requires professional legal review" banners. With professional legal review complete, these markers must be removed from both source docs and rendered site pages. The legal-document-generator agent instructions and the Terms & Conditions body text referencing "drafts" also need updates.

Closes #189.

## Acceptance Criteria

- [ ] DRAFT blockquote banners removed from top and bottom of 7 source docs in `docs/legal/`
- [ ] DRAFT blockquote banners removed from top and bottom of 7 rendered pages in `plugins/soleur/docs/pages/legal/`
- [ ] Landing page (`plugins/soleur/docs/pages/legal.njk` line 22) no longer mentions "drafts" or "professional legal review"
- [ ] Terms & Conditions section 6.2 body text updated in both locations to reflect reviewed status
- [ ] `legal-document-generator` agent updated: generated docs should still carry disclaimers, but wording reflects that the _project's own_ legal docs have been reviewed
- [ ] Plugin version bumped (PATCH) in `plugin.json`, `CHANGELOG.md`, `README.md`, `marketplace.json`
- [ ] Site builds successfully (`npx @11ty/eleventy`)
- [ ] No remaining unintended "DRAFT" references in legal files (verified by grep)

## Test Scenarios

- Given the 7 legal source docs, when grepping for "DRAFT", then zero matches are returned
- Given the 7 legal rendered pages, when grepping for "DRAFT", then zero matches are returned
- Given `legal.njk`, when reading line 22, then the text does not mention "drafts" or "professional legal review"
- Given the CLA files (`individual-cla.md`, `corporate-cla.md`), when grepping for "DRAFT", then zero matches (unchanged -- they already lack markers)
- Given the `legal-document-generator.md` agent, when reading its instructions, then the DRAFT blockquote template for _newly generated_ documents is preserved (only the project's own docs lose the marker, not the generator's output template)
- Given a fresh site build, when running `npx @11ty/eleventy`, then it exits 0 with no warnings

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

**Agent file (review, do not break generator):**

- `plugins/soleur/agents/legal/legal-document-generator.md` -- The agent's template for _newly generated_ docs should keep the DRAFT banner. No change needed unless the agent description references the project's own docs as drafts.

### Filename discrepancy

The source directory has `data-processing-agreement.md` while the rendered pages directory has `data-protection-disclosure.md`. This is a pre-existing naming mismatch, not introduced by this feature. Note it but do not fix in this PR.

### Version bump

This changes plugin files (`plugins/soleur/docs/pages/legal/` and `plugins/soleur/docs/pages/legal.njk`), so a PATCH version bump is required per AGENTS.md.

## Non-goals

- Rewriting or restructuring legal document content
- Fixing the `data-processing-agreement` / `data-protection-disclosure` filename mismatch
- Changing the legal-document-generator agent's DRAFT template for newly generated documents
- Updating archived specs or plans that reference the old DRAFT status

## References

- Issue: #189
- Constitution learning on dual-location legal docs: `knowledge-base/overview/constitution.md` line 168
- Legal document generator agent: `plugins/soleur/agents/legal/legal-document-generator.md`
