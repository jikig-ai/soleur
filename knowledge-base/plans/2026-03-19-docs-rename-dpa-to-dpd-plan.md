---
title: "docs: rename data-processing-agreement.md to data-protection-disclosure.md"
type: fix
date: 2026-03-19
---

# docs: rename data-processing-agreement.md to data-protection-disclosure.md

## Enhancement Summary

**Deepened on:** 2026-03-19
**Sections enhanced:** 3 (Phase 1 sharpened, Non-Goals validated, edge cases added)
**Research sources:** 3 institutional learnings, full-repo grep audit, agent/skill/docs-data file inventory

### Key Improvements
1. Added `git add` pre-step for Phase 1 (from learning `git-add-before-git-mv-for-untracked-files`) -- prevents `fatal: not under version control` if the file was modified in the current session
2. Confirmed no GitHub Actions workflows, `docs/_data/*.js`, or `.github/` files reference the old filename -- no CI breakage risk
3. Validated Non-Goals exhaustively: all `data-processing-agreement` matches in `plugins/soleur/docs/pages/legal/` are Buttondown's external URL, not internal references

### Applicable Learnings
- **`git-add-before-git-mv-for-untracked-files`**: Always `git add` before `git mv` -- already in the tasks.md, confirmed as critical
- **`legal-doc-bulk-consistency-fix-pattern`**: When fixing dual-location legal docs, edit source first, mirror to Eleventy -- not applicable here (Eleventy copy already correct, only source needs renaming)
- **`dpd-processor-table-dual-file-sync`**: The dual-file naming mismatch is the exact problem this PR fixes -- after this PR lands, the sync trap documented in this learning is eliminated

## Overview

The source legal document at `docs/legal/data-processing-agreement.md` has the wrong filename. Its title, frontmatter, and content all say "Data Protection Disclosure" -- the document explicitly states it is NOT a Data Processing Agreement (see introduction paragraph). The Eleventy copy at `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` already uses the correct filename. This mismatch has been a known sync trap since February 2026, documented in multiple learnings (`dpd-processor-table-dual-file-sync`, `dpa-vendor-response-verification-lifecycle`), and was formally filed as issue #741 during the Buttondown DPA review.

## Problem Statement

The filename `data-processing-agreement.md` contradicts the document's own content:
- **Frontmatter title:** "Data Protection Disclosure"
- **H1 heading:** "Data Protection Disclosure"
- **Introduction paragraph:** "Because Soleur is not a data processor (see Section 2), this is not a Data Processing Agreement under Article 28. It is a disclosure document that clarifies data handling responsibilities."

This creates:
1. **Confusion for contributors** who see two different filenames for the same document across locations
2. **Sync errors** when editors update one file but grep for the wrong filename to find the other
3. **Misleading legal semantics** -- "Data Processing Agreement" implies an Article 28 controller-processor DPA, which this document explicitly disclaims

## Proposed Solution

Rename the file using `git mv` and update all internal references.

### Files to Modify

#### Phase 1: File Rename

| Action | File |
|--------|------|
| `git mv` | `docs/legal/data-processing-agreement.md` -> `docs/legal/data-protection-disclosure.md` |

### Research Insights -- Phase 1

**Institutional learning applied:** The `git add` before `git mv` pattern (learning `2026-02-24-git-add-before-git-mv-for-untracked-files`) is already in the tasks.md. This is a known gotcha in this codebase -- `git mv` fails if the file was created or modified in the current session without being staged.

**Edge case -- parallel branches:** If another branch modifies `docs/legal/data-processing-agreement.md` concurrently, merging that branch after this PR lands will fail with a conflict on the deleted file. This is unlikely given the file's stability, but the `pre-merge-rebase.sh` hook enforces `git merge origin/main` before PR merge, which would surface this conflict early.

**Edge case -- `git log --follow` similarity threshold:** `git mv` with no content changes guarantees `--follow` detection. The Phase 2 frontmatter edit should be in a separate commit or the same commit as the `git mv` -- either way, the similarity will be high enough (only 1 line changes in a 270+ line file, well above git's 50% default threshold).

#### Phase 2: Frontmatter Update

| File | Change |
|------|--------|
| `docs/legal/data-protection-disclosure.md` | Change `type: data-processing-agreement` to `type: data-protection-disclosure` |

#### Phase 3: Agent and Skill Updates

These files contain the `data-processing-agreement` type value or list the document type by the old name:

| File | Line(s) | Change |
|------|---------|--------|
| `plugins/soleur/agents/legal/legal-document-generator.md` | 11, 39, 50 | Update "Data Processing Agreement" to "Data Protection Disclosure" in supported types list, kebab-case type value, and cross-reference hint |
| `plugins/soleur/skills/legal-generate/SKILL.md` | 17 | Update "Data Processing Agreement" to "Data Protection Disclosure" in supported types list |
| `docs/legal/acceptable-use-policy.md` | 232 | Update "Data Processing Agreement" to "Data Protection Disclosure" in cross-reference hint (project self-reference) |
| `docs/legal/disclaimer.md` | 202 | Update "Data Processing Agreement" to "Data Protection Disclosure" in cross-reference hint (project self-reference) |
| `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` | 241 | Mirror the AUP cross-reference update to the Eleventy copy |
| `plugins/soleur/docs/pages/legal/disclaimer.md` | 211 | Mirror the Disclaimer cross-reference update to the Eleventy copy |

#### Phase 4: Knowledge-Base and Historical References

These are **historical plan/spec/learning files** that reference the old filename path. They should be updated to use the new path for accuracy, but they are not user-facing and the old path context is still valid history.

**Active references (non-archived, should update):**

| File | Change |
|------|--------|
| `knowledge-base/learnings/2026-03-19-dpa-vendor-response-verification-lifecycle.md` | Lines 16, 25: update path and filename references |
| `knowledge-base/plans/2026-03-18-fix-dpd-section-6-3-plausible-eu-hosting-plan.md` | Lines 57, 70, 111: update path references |
| `knowledge-base/plans/2026-03-18-fix-buttondown-legal-basis-plan.md` | Lines 43, 88, 97, 106, 109: update path references |
| `knowledge-base/plans/2026-03-18-chore-vendor-ops-legal-web-platform-services-plan.md` | Lines 24, 189, 232, 407: update path references |
| `knowledge-base/plans/2026-03-18-fix-dpd-intro-paragraph-links-plan.md` | Lines 40, 79, 102, 122: update path references |
| `knowledge-base/specs/feat-gdpr-buttondown-legal-basis-666/spec.md` | Line 51: update path |
| `knowledge-base/specs/feat-gdpr-buttondown-legal-basis-666/tasks.md` | Line 27: update path |
| `knowledge-base/specs/feat-dpd-plausible-700/tasks.md` | Lines 5-6: update path |
| `knowledge-base/specs/feat-vendor-ops-legal/tasks.md` | Line 43: update path |
| `knowledge-base/specs/feat-dpd-links-701/tasks.md` | Line 11: update path |

**Archived references (leave as-is):** Files under `knowledge-base/*/archive/` and `knowledge-base/project/plans/archive/` are historical records. Updating them adds churn without value.

**Project-scoped references (should update):**

| File | Change |
|------|--------|
| `knowledge-base/project/plans/2026-03-18-legal-dpd-section-4-missing-processors-plan.md` | Lines 30, 45, 78, 103-104, 156: update path |
| `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md` | Line 5: update path |
| `knowledge-base/project/plans/2026-03-10-feat-newsletter-email-capture-plan.md` | Line 135: update path and note |
| `knowledge-base/project/specs/feat-newsletter/tasks.md` | Line 21: update path and note |

## Non-Goals

- Changing the Eleventy copy filename (already correct at `data-protection-disclosure.md`)
- Changing the docs site permalink (already correct at `pages/legal/data-protection-disclosure.html`)
- Changing the docs site navigation card (already correct, links to `data-protection-disclosure.html`)
- Updating archived knowledge-base files under `archive/` directories
- Modifying references to Buttondown's external DPA URL (`https://buttondown.com/legal/data-processing-agreement`) -- that is Buttondown's filename, not ours
- Modifying references in `docs/legal/privacy-policy.md` or `docs/legal/gdpr-policy.md` that mention "Data Processing Agreement" in the context of third-party vendor DPAs (Buttondown, Supabase, Stripe, Hetzner, Cloudflare) -- those are correct references to external vendor agreements

### Research Insights -- Non-Goals Validation

**Exhaustive grep audit confirmed these exclusions are correct:**
- `plugins/soleur/docs/pages/legal/privacy-policy.md:252` -- Buttondown's external DPA URL
- `plugins/soleur/docs/pages/legal/gdpr-policy.md:195, 274` -- Buttondown's DPA references
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md:207` -- generic "data processing agreements" (lowercase, plural, referring to third-party vendor agreements)
- `docs/legal/privacy-policy.md:135, 149, 158, 168, 177, 243` -- all reference external vendor DPAs (Buttondown, Supabase, Stripe, Hetzner, Cloudflare)
- `docs/legal/gdpr-policy.md:186, 227, 265` -- external vendor DPA references
- `docs/legal/acceptable-use-policy.md:232` -- generic "Data Processing Agreement" in a cross-reference hint (this should arguably update to "Data Protection Disclosure" since it describes the companion document for this project, not external vendor DPAs)
- `docs/legal/disclaimer.md:202` -- same pattern as AUP above

**New finding:** The cross-reference hints in `acceptable-use-policy.md` (line 232) and `disclaimer.md` (line 202) say "Data Processing Agreement" when referring to this project's own companion document. These should be updated to "Data Protection Disclosure" since they describe the Soleur document, not an external vendor's DPA. Adding these to Phase 3.

## Acceptance Criteria

- [ ] `docs/legal/data-processing-agreement.md` no longer exists
- [ ] `docs/legal/data-protection-disclosure.md` exists with identical content
- [ ] `type` frontmatter in renamed file is `data-protection-disclosure`
- [ ] `legal-document-generator.md` references `data-protection-disclosure` type
- [ ] `legal-generate/SKILL.md` lists "Data Protection Disclosure" not "Data Processing Agreement"
- [ ] `git log --follow docs/legal/data-protection-disclosure.md` shows full history
- [ ] No stale references to `docs/legal/data-processing-agreement.md` in active (non-archived) knowledge-base files
- [ ] All references to external vendor DPAs remain unchanged
- [ ] Cross-reference hints in `acceptable-use-policy.md` and `disclaimer.md` (both locations) say "Data Protection Disclosure" not "Data Processing Agreement"

## Test Scenarios

- Given the file `docs/legal/data-processing-agreement.md` exists, when `git mv` renames it to `docs/legal/data-protection-disclosure.md`, then `git log --follow` shows the complete commit history
- Given the renamed file, when checking its frontmatter `type` field, then the value is `data-protection-disclosure`
- Given the rename is complete, when running `grep -r "docs/legal/data-processing-agreement" --include="*.md"` excluding `archive/` directories, then zero matches are returned
- Given the rename is complete, when running `grep -r "data-processing-agreement" plugins/soleur/agents/ plugins/soleur/skills/`, then the only matches are references to external vendor DPA URLs (e.g., `buttondown.com/legal/data-processing-agreement`)

## Semver

`semver:patch` -- documentation-only change, no functional impact on the plugin.

## References

- Issue: #741
- Learning: `knowledge-base/learnings/2026-03-19-dpa-vendor-response-verification-lifecycle.md`
- Learning: `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md`
- Historical plan noting the mismatch: `knowledge-base/project/plans/archive/20260302-132003-2026-03-02-feat-remove-draft-markers-legal-docs-plan.md` (line 129)
- Original issue discovery: PR #528 (Buttondown DPA review)
