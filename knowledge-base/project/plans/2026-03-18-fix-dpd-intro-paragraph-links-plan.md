---
title: "fix: DPD intro paragraph links use wrong path format"
type: fix
date: 2026-03-18
semver: patch
---

# fix: DPD intro paragraph links use wrong path format

## Enhancement Summary

**Deepened on:** 2026-03-18
**Sections enhanced:** 4 (Problem Statement, Proposed Solution, Test Scenarios, Context)
**Research performed:** Local codebase analysis -- link pattern verification across all 9 Eleventy legal docs and 10 root legal docs

### Key Improvements

1. Verified the `/docs/legal/` broken pattern is isolated to the DPD intro paragraph only -- no other legal documents are affected
2. Confirmed correct link patterns via Eleventy `permalink:` frontmatter (all 9 docs use `pages/legal/*.html`)
3. Confirmed root copy pattern via footer cross-references (all root docs use relative `*.md` paths)
4. Applied institutional learning from `2026-03-18-dpd-processor-table-dual-file-sync` -- dual-file drift verification step added

### New Considerations Discovered

- The `/docs/legal/` path prefix was likely a copy-paste artifact from when the DPD was first generated -- the root directory is `docs/legal/` but that is not a valid link prefix in either rendering context
- No broader codebase-wide audit is needed; this pattern is unique to the DPD intro paragraph

## Overview

Both DPD files (Eleventy source and root source copy) contain links in the intro paragraph that use `/docs/legal/terms-and-conditions.md` and `/docs/legal/privacy-policy.md` absolute paths. These paths are wrong for both file contexts and produce 404 errors on both the live Eleventy site and GitHub rendering.

The correct link patterns already exist in the "Related Documents" footer at the bottom of each file.

## Problem Statement

**Eleventy source** (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`, line 29):

- Current (broken): `[Terms and Conditions](/docs/legal/terms-and-conditions.md)` and `[Privacy Policy](/docs/legal/privacy-policy.md)`
- Footer (correct): `/pages/legal/terms-and-conditions.html` and `/pages/legal/privacy-policy.html`

**Root source copy** (`docs/legal/data-protection-disclosure.md`, line 20):

- Current (broken): `[Terms and Conditions](/docs/legal/terms-and-conditions.md)` and `[Privacy Policy](/docs/legal/privacy-policy.md)`
- Footer (correct): `terms-and-conditions.md` and `privacy-policy.md` (relative)

The `/docs/legal/` path prefix does not correspond to any deployed route on the Eleventy site (which uses `/pages/legal/*.html`) or any renderable relative path from the `docs/legal/` directory on GitHub.

### Research Insights

**Pattern verification:** Searched all legal documents in both locations for the `/docs/legal/` path prefix. Results:

- **Eleventy source** (`plugins/soleur/docs/pages/legal/*.md`): Only the DPD intro paragraph uses `/docs/legal/`. All 9 legal docs consistently use `/pages/legal/*.html` for cross-references (matching their `permalink:` frontmatter values).
- **Root copies** (`docs/legal/*.md`): Only the DPD intro paragraph uses `/docs/legal/`. Root docs that have linked cross-references use relative `*.md` paths (e.g., `privacy-policy.md`, `cookie-policy.md`).

**Root cause:** The `/docs/legal/` prefix was likely introduced during initial DPD generation by the `legal-document-generator` agent. The generator creates documents independently and uses filesystem paths as link targets -- but filesystem paths (`docs/legal/`) differ from both Eleventy route paths (`/pages/legal/*.html`) and GitHub-relative paths (`*.md`). The footer links were corrected in subsequent PRs but the intro paragraph links were missed.

## Proposed Solution

Update the intro paragraph links in both files to match the correct footer pattern for each context:

1. **Eleventy source** -- change to `/pages/legal/terms-and-conditions.html` and `/pages/legal/privacy-policy.html`
2. **Root source copy** -- change to `terms-and-conditions.md` and `privacy-policy.md` (relative paths)

This is a two-line edit across two files.

### Research Insights

**Link format conventions verified across the codebase:**

| Context | Format | Example | Source |
|---------|--------|---------|--------|
| Eleventy legal docs | `/pages/legal/<name>.html` | `/pages/legal/privacy-policy.html` | All 9 Eleventy legal doc footer sections |
| Root legal docs | `<name>.md` (relative) | `privacy-policy.md` | Root privacy-policy.md, gdpr-policy.md footers |
| Eleventy frontmatter | `pages/legal/<name>.html` | `permalink: pages/legal/terms-and-conditions.html` | All 9 Eleventy legal doc frontmatter |

**Edge case: leading slash.** Eleventy body links use `/pages/legal/*.html` (with leading `/`) while frontmatter uses `pages/legal/*.html` (without). The leading slash is correct for body links as they need to be site-root-relative. The frontmatter value is an Eleventy output path, not a URL.

## Acceptance Criteria

- [x] Eleventy DPD intro links use `/pages/legal/*.html` format matching footer pattern (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`)
- [x] Root DPD intro links use relative `*.md` format matching footer pattern (`docs/legal/data-protection-disclosure.md`)
- [x] No other `/docs/legal/` absolute paths remain in either file
- [x] Footer "Related Documents" links remain unchanged
- [x] Both files remain content-identical except for their link format conventions

## Test Scenarios

- Given the Eleventy DPD source, when rendered on the docs site, then the Terms and Conditions and Privacy Policy links in the intro paragraph resolve to valid pages
- Given the root DPD source, when viewed on GitHub from the `docs/legal/` directory, then the Terms and Conditions and Privacy Policy links in the intro paragraph resolve to the correct sibling files
- Given both files after the fix, when searching for `/docs/legal/` paths across the entire repo, then zero matches are found (excluding plan/task reference files)

### Research Insights

**Verification commands:**

```bash
# Verify no broken /docs/legal/ paths remain in source files
grep -rn '/docs/legal/' plugins/soleur/docs/pages/legal/ docs/legal/ | grep -v knowledge-base

# Verify Eleventy intro links match footer pattern
grep '/pages/legal/' plugins/soleur/docs/pages/legal/data-protection-disclosure.md

# Verify root intro links match footer pattern (relative)
grep -E '\(terms-and-conditions\.md\)|\(privacy-policy\.md\)' docs/legal/data-protection-disclosure.md
```

**Dual-file drift check (institutional learning):** After editing both files, run a structural diff to confirm the intro paragraphs are semantically identical (same text, different link formats). This prevents the dual-file sync gap documented in learning `2026-03-18-dpd-processor-table-dual-file-sync.md`.

## Context

- **Severity:** Low -- cosmetic/UX issue. The correct links exist in the Related Documents footer at the bottom.
- **Source:** Found by pattern-recognition-specialist review agent during PR #697 review.
- **Dual-file pattern:** The DPD exists in two locations with different link conventions (see learning `2026-03-18-dpd-processor-table-dual-file-sync.md`). The Eleventy source uses `.html` absolute paths for the docs site build; the root copy uses relative `.md` paths for GitHub rendering.
- **Scope confirmation:** No other legal documents have this issue. The broken `/docs/legal/` pattern is isolated to the DPD intro paragraph in both file copies.

## MVP

### plugins/soleur/docs/pages/legal/data-protection-disclosure.md (line 29)

```markdown
This DPD supplements our [Terms and Conditions](/pages/legal/terms-and-conditions.html) and [Privacy Policy](/pages/legal/privacy-policy.html) and transparently describes the data processing relationship under the General Data Protection Regulation (EU) 2016/679 ("GDPR"). Because Soleur is not a data processor (see Section 2), this is not a Data Processing Agreement under Article 28. It is a disclosure document that clarifies data handling responsibilities.
```

### docs/legal/data-protection-disclosure.md (line 20)

```markdown
This DPD supplements our [Terms and Conditions](terms-and-conditions.md) and [Privacy Policy](privacy-policy.md) and transparently describes the data processing relationship under the General Data Protection Regulation (EU) 2016/679 ("GDPR"). Because Soleur is not a data processor (see Section 2), this is not a Data Processing Agreement under Article 28. It is a disclosure document that clarifies data handling responsibilities.
```

## References

- GitHub issue: #701
- Related PR: #697 (where the issue was discovered)
- Learning: `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md`
- Learning: `knowledge-base/project/learnings/2026-02-20-dogfood-legal-agents-cross-document-consistency.md`
- Constitution rule: "Legal documents exist in two locations -- both must be updated in sync when legal content changes"
- Constitution rule: "When documentation mandates one strategy but code uses another, canonicalize on what the code does"
