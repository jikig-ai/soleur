---
title: "chore(legal): add Web Platform email notification to DPD Section 8.2(b)"
type: chore
date: 2026-03-20
---

# Add Web Platform Email Notification to DPD Section 8.2(b)

## Overview

DPD Section 8.2(b) lists notification channels for future changes to the DPD but does not mention the Web Platform or email notification for users with an account on file. This is the same consistency gap that Section 7.2 had before it was fixed in PR #919. The issue asks to add explicit Web Platform email notification as a channel in Section 8.2(b).

## Problem Statement

Section 8.2(b) currently reads:

> Via the Soleur GitHub repository, Docs Site, and release notes;

While this covers GitHub and the Docs Site, it does not explicitly mention:
1. The Web Platform (app.soleur.ai) as a notification surface
2. Email notification for Web Platform users who have an account on file

This creates an inconsistency with Section 7.2(b) (after PR #919), which explicitly mentions Web Platform and email notification for breach notifications. If Jikigai notifies users about breaches via Web Platform email but does not commit to the same for future DPD changes, that is a gap -- DPD changes are arguably as important as breach notifications for informed consent.

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

### Consistency audit -- other notification sections

Two additional sections mention notification channels:

- **Section 7.2(b)** -- Already fixed by PR #919 to include Web Platform and email. No action needed.
- **Section 13.2** -- Currently reads: "Material changes will be communicated at least 30 days in advance through the Soleur GitHub repository and Docs Site." Consider whether to add Web Platform email here too for full consistency. Section 13 covers general amendments (same topic as Section 8.2 -- future changes), so the same channels should apply. However, Section 13.2 is a general amendment clause while Section 8.2 is specifically about cloud processing expansion. The issue scope is limited to Section 8.2(b). Flag Section 13.2 as a follow-up if desired but do not change it in this PR.

### Files to update

Both copies must be updated identically:

1. `docs/legal/data-protection-disclosure.md` (root copy, line 265)
2. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Eleventy copy, line 273)

### Last Updated header

Update the "Last Updated" date and changelog entry in both files to reflect this change.

## Acceptance Criteria

- [ ] Section 8.2(b) includes "Web Platform (app.soleur.ai)" and "(including email notification for users with an account on file)" in both DPD copies
- [ ] "Last Updated" header reflects the new change description
- [ ] `diff` between root and Eleventy DPD copies shows only expected differences (frontmatter, HTML wrapper, link paths)
- [ ] No other sections are modified beyond 8.2(b) and the Last Updated header

## Test Scenarios

- Given both DPD copies are updated, when running `diff` on the content sections, then only frontmatter/HTML/link differences should appear (no content drift)
- Given Section 8.2(b) is updated, when reading the notification channels list, then Web Platform and email are mentioned alongside GitHub repository, Docs Site, and release notes
- Given the branch was created before PR #919 merged, when preparing to commit, then `git merge origin/main` must be run first to incorporate the Section 7.2 fix

## Context

- **GitHub issue:** #926
- **Priority:** P3 (minor consistency gap)
- **Labels:** legal, priority/p3-low, type/chore
- **Precedent:** PR #919 (Section 7.2 breach notification fix for #907)
- **Related:** #907 (Section 7.2 gap, now closed)
- **Branch note:** This branch was created before PR #919 merged. Must merge `origin/main` before committing to avoid conflicts with Section 7.2 changes.

## References

- `docs/legal/data-protection-disclosure.md` -- root DPD copy
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- Eleventy DPD copy
- PR #919 -- precedent for the same pattern (Section 7.2)
- Issue #907 -- the analogous Section 7.2 gap (now closed)
