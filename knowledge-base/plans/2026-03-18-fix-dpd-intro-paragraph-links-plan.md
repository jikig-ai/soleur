---
title: "fix: DPD intro paragraph links use wrong path format"
type: fix
date: 2026-03-18
semver: patch
---

# fix: DPD intro paragraph links use wrong path format

## Overview

Both DPD files (Eleventy source and root source copy) contain links in the intro paragraph that use `/docs/legal/terms-and-conditions.md` and `/docs/legal/privacy-policy.md` absolute paths. These paths are wrong for both file contexts and produce 404 errors on both the live Eleventy site and GitHub rendering.

The correct link patterns already exist in the "Related Documents" footer at the bottom of each file.

## Problem Statement

**Eleventy source** (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`, line 29):
- Current (broken): `[Terms and Conditions](/docs/legal/terms-and-conditions.md)` and `[Privacy Policy](/docs/legal/privacy-policy.md)`
- Footer (correct): `/pages/legal/terms-and-conditions.html` and `/pages/legal/privacy-policy.html`

**Root source copy** (`docs/legal/data-processing-agreement.md`, line 20):
- Current (broken): `[Terms and Conditions](/docs/legal/terms-and-conditions.md)` and `[Privacy Policy](/docs/legal/privacy-policy.md)`
- Footer (correct): `terms-and-conditions.md` and `privacy-policy.md` (relative)

The `/docs/legal/` path prefix does not correspond to any deployed route on the Eleventy site (which uses `/pages/legal/*.html`) or any renderable relative path from the `docs/legal/` directory on GitHub.

## Proposed Solution

Update the intro paragraph links in both files to match the correct footer pattern for each context:

1. **Eleventy source** -- change to `/pages/legal/terms-and-conditions.html` and `/pages/legal/privacy-policy.html`
2. **Root source copy** -- change to `terms-and-conditions.md` and `privacy-policy.md` (relative paths)

This is a two-line edit across two files.

## Acceptance Criteria

- [ ] Eleventy DPD intro links use `/pages/legal/*.html` format matching footer pattern (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`)
- [ ] Root DPD intro links use relative `*.md` format matching footer pattern (`docs/legal/data-processing-agreement.md`)
- [ ] No other `/docs/legal/` absolute paths remain in either file
- [ ] Footer "Related Documents" links remain unchanged

## Test Scenarios

- Given the Eleventy DPD source, when rendered on the docs site, then the Terms and Conditions and Privacy Policy links in the intro paragraph resolve to valid pages
- Given the root DPD source, when viewed on GitHub from the `docs/legal/` directory, then the Terms and Conditions and Privacy Policy links in the intro paragraph resolve to the correct sibling files
- Given both files after the fix, when searching for `/docs/legal/` paths, then zero matches are found

## Context

- **Severity:** Low -- cosmetic/UX issue. The correct links exist in the Related Documents footer at the bottom.
- **Source:** Found by pattern-recognition-specialist review agent during PR #697 review.
- **Dual-file pattern:** The DPD exists in two locations with different link conventions (see learning `2026-03-18-dpd-processor-table-dual-file-sync.md`). The Eleventy source uses `.html` absolute paths for the docs site build; the root copy uses relative `.md` paths for GitHub rendering.

## MVP

### plugins/soleur/docs/pages/legal/data-protection-disclosure.md (line 29)

```markdown
This DPD supplements our [Terms and Conditions](/pages/legal/terms-and-conditions.html) and [Privacy Policy](/pages/legal/privacy-policy.html) and transparently describes...
```

### docs/legal/data-processing-agreement.md (line 20)

```markdown
This DPD supplements our [Terms and Conditions](terms-and-conditions.md) and [Privacy Policy](privacy-policy.md) and transparently describes...
```

## References

- GitHub issue: #701
- Related PR: #697 (where the issue was discovered)
- Learning: `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md`
- Constitution rule: "Legal documents exist in two locations -- both must be updated in sync when legal content changes"
