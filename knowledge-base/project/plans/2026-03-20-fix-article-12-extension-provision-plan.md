---
title: "fix: add Article 12(3) two-month extension provision to response timeline language"
type: fix
date: 2026-03-20
semver: patch
deepened: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 4 (Proposed Fix, Implementation, "Last Updated" headers, Acceptance Criteria)
**Research sources:** GDPR Article 12(3) full text (gdpr-info.eu), institutional learning (`eleventy-mirror-dual-date-locations`)

### Key Improvements

1. **Corrected proposed text** to include both statutory extension grounds ("complexity or volume of requests") instead of only "complexity" -- the regulation says "taking into account the complexity and number of the requests"
2. **Added dual date location warning** for Eleventy mirror files -- each mirror file has TWO "Last Updated" locations (hero HTML `<p>` tag + body markdown line) that must both be updated (from learning: `2026-03-20-eleventy-mirror-dual-date-locations`)
3. **Verified proposed language** against the verbatim GDPR Article 12(3) text from EUR-Lex -- confirmed the notification obligation requires informing "within one month of receipt of the request, together with the reasons for the delay"

### New Considerations Discovered

- The DPD plugin mirror file uses Eleventy HTML link format (`/pages/legal/gdpr-policy.html`) -- verified this difference is already noted in the plan
- Article 12(4) (refusal notification) is out of scope and does not need the extension language

---

# Add Article 12(3) Two-Month Extension Provision

## Overview

All legal documents that reference the one-month GDPR Article 12(3) response timeline omit the statutory right to extend by two further months for complex or numerous requests (second sentence of Article 12(3)). The current wording could be read as a commitment to always respond within one month without exception, creating a self-imposed obligation stricter than GDPR requires.

## Problem Statement

GDPR Article 12(3) provides two guarantees:

1. The controller shall respond "without undue delay and in any event within one month of receipt"
2. "That period may be extended by two further months where necessary, taking into account the complexity and number of the requests"

All four existing response timeline sentences quote only the first guarantee. If Jikigai ever needs the extension (e.g., high volume of simultaneous requests, complex erasure spanning multiple processors), the published policies do not acknowledge the right to use it.

## Proposed Fix

Append the following sentence immediately after each existing response timeline statement:

> This period may be extended by two further months where necessary, taking into account the complexity or volume of requests, in which case we will inform you of the extension and reasons within the initial one-month period.

### Research Insight: Statutory Fidelity

The original issue proposed text mentioning only "request complexity." The actual GDPR Article 12(3) reads: "That period may be extended by two further months where necessary, **taking into account the complexity and number of the requests.**" Both grounds must be included. The proposed text above uses "complexity or volume of requests" as a plain-language paraphrase that preserves both statutory grounds while remaining readable for non-legal audiences. Using "or" rather than "and" avoids implying both conditions must be met simultaneously (the regulation uses "and" in the sense of listing two independent considerations, not requiring both).

## Affected Files (8 total -- 4 source, 4 mirror)

### Source files (`docs/legal/`)

| File | Section | Line | Current text |
|------|---------|------|-------------|
| `docs/legal/gdpr-policy.md` | 14. Contact Information | 313 | "...within one month of receipt, as required by GDPR Article 12(3)." |
| `docs/legal/data-protection-disclosure.md` | 5.3 Web Platform Data | 194 | "...within one month of receipt, as required by GDPR Article 12(3). For full details..." |
| `docs/legal/terms-and-conditions.md` | 17. Legal Entity and Contact Information | 328 | "...within one month of receipt, as required by GDPR Article 12(3)." |
| `docs/legal/privacy-policy.md` | 14. Legal Entity and Contact Us | 289 | "...within one month of receipt, as required by GDPR Article 12(3)." |

### Mirror files (`plugins/soleur/docs/pages/legal/`)

| File | Section | Line | Current text |
|------|---------|------|-------------|
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | 14. Contact Information | 322 | Same as source |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 5.3 Web Platform Data | 203 | Same as source (with Eleventy link format) |
| `plugins/soleur/docs/pages/legal/terms-and-conditions.md` | 17. Legal Entity and Contact Information | 337 | Same as source |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | 14. Legal Entity and Contact Us | 298 | Same as source |

### Dependency: GDPR Policy Section 5.3 (PR #916)

Issue #929 lists "GDPR Policy Section 5.3" as a fifth location. This section is being added by PR #916 (issue #909), which is currently OPEN. The new Section 5.3 will contain Web Platform-specific data subject rights with its own response timeline sentence. Once PR #916 merges, that section will also need the extension language. Two approaches:

- **If PR #916 merges first:** This PR should merge origin/main (required by pre-merge-rebase hook) and update the new GDPR Policy Section 5.3 along with the other 8 files.
- **If this PR merges first:** PR #916 should include the extension language when it adds the new section. File an advisory comment on PR #916 noting the requirement.

## Implementation

For each of the 8 files listed above, append the extension sentence to the existing response timeline paragraph. The DPD version requires care because the sentence continues with "For full details..." -- insert the extension language before that continuation.

### Pattern for 7 of 8 files (gdpr-policy, terms-and-conditions, privacy-policy in both locations + DPD plugin mirror if identical)

**Before:**

```text
...within one month of receipt, as required by GDPR Article 12(3).
```

**After:**

```text
...within one month of receipt, as required by GDPR Article 12(3). This period may be extended by two further months where necessary, taking into account the complexity or volume of requests, in which case we will inform you of the extension and reasons within the initial one-month period.
```

### Pattern for DPD (`data-protection-disclosure.md`, both locations)

**Before:**

```text
Jikigai will acknowledge requests within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3). For full details on how each right applies, see the companion [GDPR Policy](gdpr-policy.md) Section 5.
```

**After:**

```text
Jikigai will acknowledge requests within 5 business days and respond substantively within one month of receipt, as required by GDPR Article 12(3). This period may be extended by two further months where necessary, taking into account the complexity or volume of requests, in which case we will inform you of the extension and reasons within the initial one-month period. For full details on how each right applies, see the companion [GDPR Policy](gdpr-policy.md) Section 5.
```

(Note: the plugin mirror copy uses Eleventy link format `/pages/legal/gdpr-policy.html` instead of `gdpr-policy.md`.)

### "Last Updated" headers

Update the "Last Updated" line in each of the 8 files to include today's date and a brief description of the change (e.g., "added Article 12(3) two-month extension provision").

**Institutional Learning (from `2026-03-20-eleventy-mirror-dual-date-locations`):** The 4 Eleventy mirror files in `plugins/soleur/docs/pages/legal/` each contain TWO "Last Updated" locations that must both be updated:

1. A **hero `<p>` tag** in the HTML wrapper near the top of the file (inside `<section class="page-hero">`):

   ```html
   <p>Effective February 20, 2026 | Last Updated March 20, 2026 (...)</p>
   ```

2. A **body markdown line** further down in the document content:

   ```markdown
   **Last Updated:** March 20, 2026 (...)
   ```

The source files in `docs/legal/` have only one "Last Updated" location (the body markdown line). Before editing each mirror file, grep for all date occurrences:

```bash
grep -n "Last Updated" plugins/soleur/docs/pages/legal/<file>.md
```

## Section Number Discrepancy

Issue #929 references "Privacy Policy Section 12" but the response timeline text is in Section 14 (Legal Entity and Contact Us). Section 12 is "Cookies." The plan targets Section 14 where the text actually lives.

## Acceptance Criteria

- [ ] All 8 files contain the extension language after the existing one-month response timeline sentence
- [ ] DPD copies preserve the "For full details..." continuation after the extension sentence
- [ ] Plugin mirror copies match source copies (accounting for Eleventy link format differences)
- [ ] "Last Updated" dates reflect the change
- [ ] No other content is altered
- [ ] markdownlint passes on all modified files

## Test Scenarios

- Given the GDPR Policy Section 14, when reading the response timeline paragraph, then both the one-month commitment and the two-month extension provision are present.
- Given the DPD Section 5.3, when reading the response timeline paragraph, then the extension sentence appears between the Article 12(3) reference and the "For full details" cross-reference.
- Given all 8 files, when comparing source and mirror copies, then the response timeline paragraphs are identical (except for link format differences in DPD).
- Given PR #916 merges before this PR, when merging origin/main, then the new GDPR Policy Section 5.3 is also updated with extension language.

## References

- GitHub Issue: #929
- GDPR Article 12(3): [EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32016R0679#d1e2182-1-1)
- Related open PR: #916 (adds GDPR Policy Section 5.3)
- Constitution: legal documents exist in two locations and must be updated in sync
