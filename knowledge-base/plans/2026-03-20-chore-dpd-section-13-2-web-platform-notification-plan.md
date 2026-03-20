---
title: "chore(legal): add Web Platform email notification to DPD Section 13.2"
type: chore
date: 2026-03-20
---

# Add Web Platform Email Notification to DPD Section 13.2

DPD Section 13.2 (Amendments) lists notification channels as "the Soleur GitHub repository and Docs Site" but omits the Web Platform and email notification. This is the same consistency gap that Sections 7.2 and 8.2(b) had before PR #919 and PR #928 fixed them. Issue #935 tracks this final gap, identified during the cross-document audit for #926.

## Acceptance Criteria

- [ ] Section 13.2 includes "Web Platform (app.soleur.ai)" and "(including email notification for Web Platform users with an account on file)" in both DPD copies
- [ ] "Last Updated" header reflects the new change description prepended to existing entries in both DPD copies (root markdown and Eleventy HTML hero)
- [ ] `diff` between root and Eleventy DPD copies shows only expected differences (frontmatter, HTML wrapper, link paths)
- [ ] No other sections are modified beyond 13.2 and the Last Updated header
- [ ] Parenthetical wording matches the pattern from PR #928 / PR #919: "Web Platform users with an account on file"

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

## Context

- **GitHub issue:** #935
- **Priority:** P3 (minor consistency gap)
- **Labels:** legal, priority/p3-low, type/chore
- **Precedent:** PR #928 (Section 8.2(b) fix for #926), PR #919 (Section 7.2 fix for #907)
- **Related:** #926, #907 (analogous gaps in Sections 8.2(b) and 7.2, now closed)

## References

- `docs/legal/data-protection-disclosure.md` -- root DPD copy
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` -- Eleventy DPD copy
- PR #928 -- Section 8.2(b) fix, exact wording pattern to follow
- PR #919 -- Section 7.2 fix, original pattern
- Issue #935 -- this issue
- GDPR Article 5(1)(a) -- transparency principle supporting explicit channel enumeration
- GDPR Article 12(1) -- intelligibility requirement supporting harmonized notification lists
