---
title: "chore: add Web Platform to DPD Section 7.2 breach notification scope"
type: fix
date: 2026-03-20
---

# chore: add Web Platform to DPD Section 7.2 breach notification scope

## Overview

DPD Section 7.2 (Platform Breaches) lists "the Soleur GitHub repository, Docs Site, or distribution channels" as covered platforms but omits the Web Platform (app.soleur.ai). The Web Platform processes the highest-sensitivity user data (email addresses, hashed passwords, auth tokens, encrypted API keys, subscription metadata) and would be the highest-impact breach scenario. Explicit mention removes ambiguity about whether "distribution channels" covers it.

Found during cross-document audit for #888.

## Problem Statement

Section 7.2 was written before the Web Platform existed. When cloud features were added (Sections 2.1b, 4.2, 5.3, 6.4, 8, 9.2, 10.3), the breach notification section was not updated to include the new platform. While "distribution channels" arguably covers the Web Platform, GDPR Article 34 transparency obligations favor explicit enumeration over implicit inclusion.

Additionally, Section 7.2(b) specifies notification via "the Soleur GitHub repository and, where possible, through direct communication" but does not mention email notification to Web Platform users -- despite the Web Platform collecting email addresses for exactly this kind of communication.

## Proposed Solution

Two targeted text edits to Section 7.2, applied to both the root copy and the Eleventy copy:

### Edit 1: Section 7.2 platform list (line 237 in root, line 246 in Eleventy)

**Current:**
> In the unlikely event that a breach affects the Soleur GitHub repository, Docs Site, or distribution channels:

**Proposed:**
> In the unlikely event that a breach affects the Soleur GitHub repository, Docs Site, Web Platform (app.soleur.ai), or distribution channels:

### Edit 2: Section 7.2(b) notification channels (line 240 in root, line 249 in Eleventy)

**Current:**
> **(b)** Notification will be provided via the [Soleur GitHub repository](https://github.com/jikig-ai/soleur) and, where possible, through direct communication.

**Proposed:**
> **(b)** Notification will be provided via the [Soleur GitHub repository](https://github.com/jikig-ai/soleur) and, for Web Platform users, via the email address associated with their account. Where possible, additional direct communication channels may also be used.

**Rationale for Edit 2:** The Web Platform collects user email addresses (Section 2.3(f)). For a breach affecting user PII, email notification is a concrete obligation under GDPR Article 34, not merely "where possible." Specifying the email channel makes the commitment measurable and gives Web Platform users confidence that they will be individually notified.

## Files to Modify

| File | Role |
|------|------|
| `docs/legal/data-protection-disclosure.md` | Root copy (GitHub rendering) |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | Eleventy copy (docs site build) |

Both files must receive identical content changes. The Eleventy copy has different frontmatter and link formats but the Section 7.2 body text is identical.

## SpecFlow Analysis

**Edge cases considered:**

1. **Breach affecting only one platform:** The "or" conjunction in the platform list correctly handles partial breaches. No structural change needed.
2. **User without email (deleted account):** Section 10.3 covers account deletion and data removal. Post-deletion breach notification falls to the GitHub repository channel. No additional text needed.
3. **"Last Updated" date:** Must be updated in both files to reflect this change.

**No gaps identified.** This is a pure text substitution with no conditional logic or cross-reference changes.

## Acceptance Criteria

- [ ] Section 7.2 platform list includes "Web Platform (app.soleur.ai)" in `docs/legal/data-protection-disclosure.md`
- [ ] Section 7.2(b) specifies email notification for Web Platform users in `docs/legal/data-protection-disclosure.md`
- [ ] Identical changes applied to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] "Last Updated" date updated in both files
- [ ] `diff` between root and Eleventy copies shows only expected frontmatter/link differences (no content drift)

## Test Scenarios

- Given a reader of DPD Section 7.2, when they check which platforms are covered by breach notification, then "Web Platform (app.soleur.ai)" is explicitly listed
- Given a Web Platform user reading Section 7.2(b), when they check how they will be notified of a breach, then email notification is explicitly mentioned
- Given both DPD copies, when comparing Section 7 content, then the text is identical

## Context

**Institutional learnings applied:**
- `2026-03-18-dpd-processor-table-dual-file-sync.md`: Every structural change must touch both files in the same PR
- `2026-03-20-legal-doc-product-addition-prevention-strategies.md`: Exhaustive grep before implementation (Strategy 2) -- confirmed Section 7.2 is the only breach-related section that omits Web Platform

**Semver label:** `semver:patch` (documentation fix, no code changes)

## References

- Issue: #907
- Cross-document audit: #888
- DPD dual-file learning: `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md`
