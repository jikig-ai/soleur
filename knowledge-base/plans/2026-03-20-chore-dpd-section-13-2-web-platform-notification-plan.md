---
title: "chore(legal): add Web Platform email notification to DPD Section 13.2"
type: chore
date: 2026-03-20
---

# Add Web Platform Email Notification to DPD Section 13.2

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 3 (Proposed Changes, Test Scenarios, References)
**Research performed:** Cross-document notification channel audit, wording pattern verification against Sections 7.2(b) and 8.2(b), institutional learnings check

### Key Improvements

1. Verified exact wording pattern -- Section 13.2 correctly follows the 8.2(b) pattern (general notification list) rather than the 7.2(b) pattern (breach-specific "direct communication" framing)
2. Applied `eleventy-mirror-dual-date-locations` learning -- plan already correctly accounts for all 3 header update locations (confirmed, no gap)
3. Cross-document audit confirms this is the last DPD-internal notification channel gap; Privacy Policy (Section 13), AUP (Section 11), and T&C (Section 15.1) also lack Web Platform but are separate documents with their own update cadences

### New Considerations Discovered

- The "Last Updated" header wording should say "added Web Platform notification channel to Section 13.2" (not "email notification") to differentiate from the 8.2(b) entry that already says "email notification" -- avoids ambiguity about which section was changed
- After this PR, all three DPD-internal notification channel references (7.2, 8.2, 13.2) will mention Web Platform. The remaining gaps are in other legal documents (Privacy Policy, AUP, T&C) and could be addressed in a single batch follow-up

---

DPD Section 13.2 (Amendments) lists notification channels as "the Soleur GitHub repository and Docs Site" but omits the Web Platform and email notification. This is the same consistency gap that Sections 7.2 and 8.2(b) had before PR #919 and PR #928 fixed them. Issue #935 tracks this final gap, identified during the cross-document audit for #926.

## Acceptance Criteria

- [x] Section 13.2 includes "Web Platform (app.soleur.ai)" and "(including email notification for Web Platform users with an account on file)" in both DPD copies
- [x] "Last Updated" header reflects the new change description prepended to existing entries in both DPD copies (root markdown and Eleventy HTML hero)
- [x] `diff` between root and Eleventy DPD copies shows only expected differences (frontmatter, HTML wrapper, link paths)
- [x] No other sections are modified beyond 13.2 and the Last Updated header
- [x] Parenthetical wording matches the pattern from PR #928 / PR #919: "Web Platform users with an account on file"

## Proposed Changes

### Section 13.2 text change

Update from:

```text
**13.2** Material changes will be communicated at least 30 days in advance through the Soleur GitHub repository and Docs Site.
```

To:

```text
**13.2** Material changes will be communicated at least 30 days in advance through the Soleur GitHub repository, Docs Site, and Web Platform (app.soleur.ai) (including email notification for Web Platform users with an account on file).
```

#### Wording pattern verification

The DPD uses two distinct notification channel patterns depending on context:

| Section | Context | Pattern | Web Platform phrasing |
|---------|---------|---------|----------------------|
| 7.2(b) | Breach notification | "...through direct communication (including email notification for Web Platform users with an account on file)." | Parenthetical on "direct communication" |
| 8.2(b) | Future changes disclosure | "...Docs Site, release notes, and Web Platform (app.soleur.ai) (including email notification for Web Platform users with an account on file);" | Inline in channel list |
| 13.2 | Amendments notification | "...Soleur GitHub repository and Docs Site." | **Missing -- this PR fixes it** |

Section 13.2 is a general notification channel list (like 8.2), not a breach notification (like 7.2). The proposed text correctly follows the 8.2(b) pattern: "Web Platform (app.soleur.ai)" inline in the channel list with the email parenthetical appended.

Note: Section 8.2(b) includes "release notes" as a separate channel; Section 13.2 does not currently list release notes, and adding them would be a scope expansion beyond #935. The proposed change adds only Web Platform and email notification.

### Files to update

Both copies must be updated identically (content-wise):

1. `docs/legal/data-protection-disclosure.md` (line 336) -- root copy
2. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (line 345) -- Eleventy copy

### Last Updated header

Prepend the new change to the existing "Last Updated" parenthetical in all three locations:

1. `docs/legal/data-protection-disclosure.md` line 12 -- markdown "Last Updated" line
2. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` line 11 -- HTML hero `<p>` tag
3. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` line 21 -- markdown "Last Updated" line

Current header starts with:

```text
March 20, 2026 (added Web Platform email notification to Section 8.2(b), ...
```

Update to prepend:

```text
March 20, 2026 (added Web Platform notification channel to Section 13.2, added Web Platform email notification to Section 8.2(b), ...
```

## Test Scenarios

- Given both DPD copies are updated, when running `diff` on the content sections, then only frontmatter/HTML/link differences should appear
- Given Section 13.2 is updated, when reading the amendments section, then Web Platform and email notification are mentioned alongside GitHub repository and Docs Site
- Given the "Last Updated" header is modified, when comparing to origin/main's version, then only the new prepended entry differs

### Edge Cases

- **Eleventy mirror triple-update (from `eleventy-mirror-dual-date-locations` learning):** The Eleventy copy has two "Last Updated" locations (hero `<p>` tag at line 11, markdown body at line 21). Both must be updated. Grep for all date occurrences before editing: `grep -n "Last Updated\|March.*2026" plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- **Merge conflict on "Last Updated" header:** The header has been modified by multiple recent PRs. After merging `origin/main`, verify the header text before editing. If a conflict occurs, take `origin/main` version and prepend the new entry.
- **No new links added:** This change is text-only within Section 13.2. No link format differences between root and Eleventy copies are introduced, so the Eleventy link convention (`/pages/legal/*.html` vs `*.md`) does not apply.

### Cross-document audit (out of scope)

After this PR merges, all three DPD notification channel sections will mention Web Platform:

| Section | Status |
|---------|--------|
| 7.2(b) -- breach notification | Fixed by PR #919 |
| 8.2(b) -- future changes | Fixed by PR #928 |
| 13.2 -- amendments | **Fixed by this PR** |

The following non-DPD legal documents also list notification channels without Web Platform. These are separate documents and out of scope for #935:

| Document | Section | Current channel list |
|----------|---------|---------------------|
| Privacy Policy | 13 | "repository release note or a notice on the Docs Site" |
| Acceptable Use Policy | 11 | "GitHub repository (release notes, changelog, or repository notification)" |
| Terms and Conditions | 15.1 | "repository's release notes or changelog" |

## Context

- **GitHub issue:** #935
- **Priority:** P3 (minor consistency gap)
- **Labels:** legal, priority/p3-low, type/chore
- **Precedent:** PR #928 (Section 8.2(b) fix for #926), PR #919 (Section 7.2 fix for #907)
- **Related:** #926, #907 (analogous gaps in Sections 8.2(b) and 7.2, now closed)

## References

- `docs/legal/data-protection-disclosure.md` -- root DPD copy (Section 13.2 at line 336)
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- Eleventy DPD copy (Section 13.2 at line 345)
- PR #928 -- Section 8.2(b) fix, exact wording pattern to follow
- PR #919 -- Section 7.2 fix, original pattern
- Issue #935 -- this issue
- `knowledge-base/learnings/2026-03-20-eleventy-mirror-dual-date-locations.md` -- institutional learning about Eleventy files having two "Last Updated" locations
- GDPR Article 5(1)(a) -- transparency principle supporting explicit channel enumeration
- GDPR Article 12(1) -- intelligibility requirement supporting harmonized notification lists
