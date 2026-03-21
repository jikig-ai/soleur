---
title: "fix: DPD Section 10.3 cross-reference error to T&C"
type: fix
date: 2026-03-20
deepened: 2026-03-20
---

# fix: DPD Section 10.3 cross-reference error to T&C

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 1 (cross-reference audit)
**Research agents used:** None (two-line typo fix -- full agent battery not warranted)

### Key Improvements

1. Verified all internal DPD cross-references are correct (Sections 2.1, 2.1b, 2.3(a-h), 4.2, 6.4, 8.1(a) all match actual headings)
2. Confirmed the only broken reference is the external T&C cross-reference at line 308/317 ("Section 13.1b" should be "Section 14.1b")
3. Verified T&C internal references at Sections 5.2, 14.3 already correctly reference 14.1b, confirming the DPD reference is the outlier

### New Considerations Discovered

- No other cross-reference errors found in either DPD copy
- The "Last Updated" header in both files already correctly mentions "added Section 10.3 Web Platform account deletion" -- no header update needed

## Overview

GitHub issue #906 requests adding DPD Section 10.3 for Web Platform account deletion. However, **Section 10.3 already exists** in both DPD files -- it was added by PR #899 (`chore(legal): resolve pre-existing cross-document audit findings`).

The issue can be closed as already resolved, but a cross-reference bug was introduced: DPD Section 10.3 references "Terms and Conditions Section 13.1b" when the correct section is **14.1b** (T&C Section 13 is "Modifications to the Terms", Section 14.1b is "Termination of Web Platform Account").

## Problem Statement

DPD Section 10.3 in both files contains:

> See the Terms and Conditions Section 13.1b for the full account termination procedure.

The T&C has:

- Section 13 = "Modifications to the Terms"
- Section 14.1b = "Termination of Web Platform Account"

Internal T&C cross-references at Sections 5.2, 14.3 correctly reference 14.1b. The DPD reference to 13.1b is a typo introduced in PR #899.

## Required Changes

### Phase 1: Fix cross-reference (2 files)

- [x] `docs/legal/data-protection-disclosure.md` line 308: Change "Section 13.1b" to "Section 14.1b"
- [x] `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` line 317: Change "Section 13.1b" to "Section 14.1b"

### Phase 2: Close issue #906

- [ ] Close GitHub issue #906 with a comment noting the section was already added by PR #899, and this PR fixes the cross-reference error

## Acceptance Criteria

- [ ] Both DPD files reference T&C Section 14.1b (not 13.1b) in Section 10.3
- [ ] Cross-reference matches actual T&C heading (14.1b = "Termination of Web Platform Account")
- [ ] GitHub issue #906 is closed with `Closes #906` in PR body

## Test Scenarios

- Given the DPD Section 10.3 references T&C for account termination, when a reader follows the reference to Section 14.1b, then they find the correct "Termination of Web Platform Account" subsection
- Given both DPD copies exist (docs/ and plugins/soleur/docs/), when the fix is applied, then both files contain identical Section 10.3 content

## Context

- Section 10.3 added by: PR #899 (commit `2f695d5`)
- Issue opened: #906 (still OPEN despite being resolved)
- Cross-reference target: T&C Section 14.1b "Termination of Web Platform Account"
- Incorrect reference: T&C Section 13.1b (does not exist; Section 13 = "Modifications to the Terms")

## References

- GitHub issue: #906
- PR that added Section 10.3: #899
- Related cross-document audit: #890
- Files to modify:
  - `docs/legal/data-protection-disclosure.md`
  - `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- Cross-reference target: `docs/legal/terms-and-conditions.md` Section 14.1b
