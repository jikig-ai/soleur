---
title: "fix: Privacy Policy Section 4.6 cross-references wrong section for Buttondown"
type: fix
date: 2026-03-18
semver: patch
---

# fix: Privacy Policy Section 4.6 cross-references wrong section for Buttondown

## Overview

Section 4.6 (Newsletter Subscription Data) of the Privacy Policy references "Section 5.4" for Buttondown processor details, but the actual Buttondown section is **5.3**, not 5.4. Section 5.4 is "Other Third-Party Integrations."

The source file (`docs/legal/privacy-policy.md`) has already been corrected to reference Section 5.3. However, the docs site template (`plugins/soleur/docs/pages/legal/privacy-policy.md`) still contains the stale "Section 5.4" reference.

## Acceptance Criteria

- [ ] `plugins/soleur/docs/pages/legal/privacy-policy.md` Section 4.6 references Section 5.3, not 5.4
- [ ] Both copies of the Privacy Policy (`docs/legal/` and `plugins/soleur/docs/pages/legal/`) have identical cross-references
- [ ] No other stale cross-references exist between Sections 4 and 5 in either file

## Test Scenarios

- Given the docs site Privacy Policy, when reading Section 4.6 (Newsletter Subscription Data), then the "Third-party processor" line references Section 5.3 (Buttondown)
- Given both copies of the Privacy Policy, when comparing Section 4.6 content, then the cross-references match
- Given both copies of the Privacy Policy, when comparing all internal section cross-references, then no other mismatches exist

## Context

- **Source file (correct):** `docs/legal/privacy-policy.md` line 92 -- `See Section 5.3 for details.`
- **Docs site template (incorrect):** `plugins/soleur/docs/pages/legal/privacy-policy.md` line 101 -- `See Section 5.4 for details.`
- **Root cause:** The source file was updated but the docs site template copy was not synced.
- **Constitution note:** "Legal documents exist in two locations (`docs/legal/` for source markdown and `plugins/soleur/docs/pages/legal/` for docs site Eleventy templates) -- both must be updated in sync when legal content changes."

## Non-goals

- Restructuring the dual-location legal document system
- Adding automated sync tooling between the two copies
- Updating the "Last Updated" date (this is a cross-reference correction, not a substantive content change)

## MVP

### `plugins/soleur/docs/pages/legal/privacy-policy.md`

Change line 101 from:

```markdown
- **Third-party processor:** Buttondown acts as a data processor. See Section 5.4 for details.
```

To:

```markdown
- **Third-party processor:** Buttondown acts as a data processor. See Section 5.3 for details.
```

## References

- Closes #690
- Found during cross-document consistency check for PR #686 / issue #664
