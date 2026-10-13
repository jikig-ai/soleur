---
title: "chore(legal): add Web Platform email notification to DPD Section 8.2(b)"
type: chore
date: 2026-03-20
---

# Add Web Platform Email Notification to DPD Section 8.2(b)

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Proposed Solution, Consistency Audit, Acceptance Criteria, Test Scenarios)
**Research performed:** Cross-document notification channel audit, PR #919 diff analysis, GDPR transparency review

### Key Improvements

1. Verified exact wording from PR #919 diff to ensure Section 8.2(b) uses the same parenthetical pattern
2. Expanded cross-document audit from 2 sections to 6 legal documents, identifying additional notification channel references in Privacy Policy and Acceptable Use Policy
3. Identified that the "Last Updated" header on `origin/main` already includes PR #919 changes -- merge must happen first to get the correct baseline header text before appending

### New Considerations Discovered

- After merging `origin/main`, the "Last Updated" header will already reflect PR #919's change ("added Web Platform to Section 7.2 breach notification scope"). The new header update must append to that version, not the pre-merge version.
- Section 13.2 (Amendments) uses the same notification channel pattern without Web Platform -- should be filed as a separate follow-up issue for consistency.
- Privacy Policy Section 13 and Acceptable Use Policy Section 11 also list notification channels without Web Platform -- these are separate documents with their own update cadences, but worth tracking.

## Overview

DPD Section 8.2(b) lists notification channels for future changes to the DPD but does not mention the Web Platform or email notification for users with an account on file. This is the same consistency gap that Section 7.2 had before it was fixed in PR #919. The issue asks to add explicit Web Platform email notification as a channel in Section 8.2(b).

## Problem Statement

Section 8.2(b) currently reads:

> Via the Soleur GitHub repository, Docs Site, and release notes;

While this covers GitHub and the Docs Site, it does not explicitly mention:

1. The Web Platform (app.soleur.ai) as a notification surface
2. Email notification for Web Platform users who have an account on file

This creates an inconsistency with Section 7.2(b) (after PR #919), which explicitly mentions Web Platform and email notification for breach notifications. If Jikigai notifies users about breaches via Web Platform email but does not commit to the same for future DPD changes, that is a gap -- DPD changes are arguably as important as breach notifications for informed consent.

### Research Insights

**GDPR Transparency Principle (Article 5(1)(a)):** GDPR requires that personal data be processed "in a transparent manner in relation to the data subject." Explicitly enumerating notification channels for policy changes supports this transparency obligation. While "direct communication" could be argued to cover email, explicit enumeration is the stronger position -- it removes ambiguity about what "direct communication" means and creates an enforceable commitment.

**Notification Channel Consistency:** GDPR Article 12(1) requires information to be provided "in a concise, transparent, intelligible and easily accessible form." When different sections of the same document use different notification channel lists for analogous purposes (breach vs. policy changes), this creates confusion about whether the difference is intentional. Harmonizing the lists supports the "intelligible" requirement.

## Proposed Solution

Update DPD Section 8.2(b) to include "Web Platform (app.soleur.ai)" and email notification, mirroring the pattern established in Section 7.2(b) by PR #919.

### Target text for Section 8.2(b)

Update from:

```
- **(b)** Via the Soleur GitHub repository, Docs Site, and release notes;
```

To:

```
- **(b)** Via the Soleur GitHub repository, Docs Site, release notes, and Web Platform (app.soleur.ai) (including email notification for users with an account on file);
```

### Research Insights -- Wording Verification

**PR #919 exact diff (verified from `git show 2ad2db2`):**

Section 7.2(b) was changed from:

```
- **(b)** Notification will be provided via the [Soleur GitHub repository](https://github.com/jikig-ai/soleur) and, where possible, through direct communication.
```

To:

```
- **(b)** Notification will be provided via the [Soleur GitHub repository](https://github.com/jikig-ai/soleur) and, where possible, through direct communication (including email notification for Web Platform users with an account on file).
```

**Note:** The Section 7.2(b) pattern uses "Web Platform users with an account on file" while the proposed Section 8.2(b) text uses "users with an account on file." For maximum consistency, use the same phrasing: "Web Platform users with an account on file."

**Corrected target text:**

```
- **(b)** Via the Soleur GitHub repository, Docs Site, release notes, and Web Platform (app.soleur.ai) (including email notification for Web Platform users with an account on file);
```

### Consistency audit -- full cross-document analysis

**DPD internal notification sections:**

| Section | Current Text | Web Platform Mentioned? | Action |
|---------|-------------|------------------------|--------|
| 7.2(b) | "...direct communication (including email notification for Web Platform users with an account on file)." | Yes (after PR #919) | No action -- already fixed |
| 8.2(b) | "Via the Soleur GitHub repository, Docs Site, and release notes;" | No | **Fix in this PR** |
| 13.2 | "...through the Soleur GitHub repository and Docs Site." | No | Follow-up issue recommended |

**Other legal document notification sections:**

| Document | Section | Current Text | Web Platform Mentioned? |
|----------|---------|-------------|------------------------|
| Privacy Policy | 13 | "...through a repository release note or a notice on the Docs Site" | No |
| Acceptable Use Policy | 11 | "...through the GitHub repository (release notes, changelog, or repository notification)" | No |
| Terms and Conditions | 15.1 | "...through the repository's release notes or changelog" | No |

These other documents have their own update cadences and are out of scope for this issue. However, a follow-up audit issue could harmonize notification channels across all legal documents.

### Files to update

Both copies must be updated identically:

1. `docs/legal/data-protection-disclosure.md` -- root copy
2. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- Eleventy copy

### Last Updated header

**Important merge-order dependency:** After merging `origin/main`, the "Last Updated" header will already contain PR #919's addition: "added Web Platform to Section 7.2 breach notification scope". The update must append to that post-merge text.

Expected post-merge header baseline (from PR #919 + #914):

```
**Last Updated:** March 20, 2026 (added Web Platform to Section 7.2 breach notification scope, harmonized Cloudflare dual legal basis, renamed Section 3.1 heading, removed Buttondown from Section 4.3, updated Cloudflare legal basis to dual basis, added Section 10.3 Web Platform account deletion, added Section 5.3 Web Platform data subject rights)
```

Update to prepend the new change:

```
**Last Updated:** March 20, 2026 (added Web Platform email notification to Section 8.2(b), added Web Platform to Section 7.2 breach notification scope, harmonized Cloudflare dual legal basis, renamed Section 3.1 heading, removed Buttondown from Section 4.3, updated Cloudflare legal basis to dual basis, added Section 10.3 Web Platform account deletion, added Section 5.3 Web Platform data subject rights)
```

## Acceptance Criteria

- [x] Section 8.2(b) includes "Web Platform (app.soleur.ai)" and "(including email notification for Web Platform users with an account on file)" in both DPD copies
- [x] "Last Updated" header reflects the new change description prepended to existing entries
- [x] `diff` between root and Eleventy DPD copies shows only expected differences (frontmatter, HTML wrapper, link paths)
- [x] No other sections are modified beyond 8.2(b) and the Last Updated header
- [x] Parenthetical wording matches PR #919 pattern: "Web Platform users with an account on file" (not just "users with an account on file")

## Test Scenarios

- Given both DPD copies are updated, when running `diff` on the content sections, then only frontmatter/HTML/link differences should appear (no content drift)
- Given Section 8.2(b) is updated, when reading the notification channels list, then Web Platform and email are mentioned alongside GitHub repository, Docs Site, and release notes
- Given the branch was created before PR #919 merged, when preparing to commit, then `git merge origin/main` must be run first to incorporate the Section 7.2 fix and the Cloudflare dual legal basis harmonization (#914)
- Given the "Last Updated" header is modified, when comparing to origin/main's version, then only the new prepended entry differs

### Edge Cases

- **Merge conflict on "Last Updated" header:** The header has been modified by multiple recent PRs (#918, #919, #914). After merging `origin/main`, verify the header text before editing. If a conflict occurs during merge, resolve by taking the `origin/main` version and then prepending the new change.
- **Eleventy copy link format:** The Eleventy copy uses `/pages/legal/terms-and-conditions.html` paths instead of `terms-and-conditions.md`. Ensure any new links added follow the Eleventy copy's link convention. (Not applicable here -- no new links are being added, only text changes.)

## Context

- **GitHub issue:** #926
- **Priority:** P3 (minor consistency gap)
- **Labels:** legal, priority/p3-low, type/chore
- **Precedent:** PR #919 (Section 7.2 breach notification fix for #907)
- **Related:** #907 (Section 7.2 gap, now closed)
- **Branch note:** This branch was created before PRs #919 and #914 merged. Must merge `origin/main` before committing to incorporate both.

## References

- `docs/legal/data-protection-disclosure.md` -- root DPD copy
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- Eleventy DPD copy
- PR #919 (`2ad2db2`) -- precedent for the same pattern (Section 7.2), verified via `git show`
- PR #914 (`6bad1d5`) -- Cloudflare dual legal basis harmonization (also modified "Last Updated" header)
- Issue #907 -- the analogous Section 7.2 gap (now closed)
- Issue #926 -- this issue
- GDPR Article 5(1)(a) -- transparency principle supporting explicit channel enumeration
- GDPR Article 12(1) -- intelligibility requirement supporting harmonized notification lists
