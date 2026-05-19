---
title: Regex over-match fix-inline trap — substring-match alternatives can repeat the same over-match
date: 2026-05-19
category: code-quality
module: scripts/content-publisher.sh
related:
  - "PR #4047 (feat-linkedin-api-reapply-4046)"
  - "Issue #4046"
tags:
  - regex
  - bash
  - review-fix-inline
  - over-match
  - false-positive-traps
---

# Learning: regex over-match fix-inline trap

## Problem

PR #4047 introduced a `classify_linkedin_error` matrix in `scripts/content-publisher.sh`. The original implementation matched HTTP codes via:

```bash
[[ "$err" =~ HTTP\ (401|403) ]]
```

A `code-quality-analyst` review flagged the **regex over-match**: input strings like `"Error code HTTP 4012ab in metadata"` or `"HTTP 4031"` would falsely match the `401` / `403` alternation because the regex has no terminator after the code.

The agent recommended switching to literal substring matches "consistent with sibling branches". I applied the recommendation as:

```bash
[[ "$err" == *"HTTP 401"* ]] || [[ "$err" == *"HTTP 403"* ]]
```

This **is also vulnerable to the same over-match**: `"HTTP 4012ab"` contains the substring `HTTP 401`, so the `*"HTTP 401"*` glob matches it. The fix re-introduced the exact over-match it was meant to prevent.

The recursive trap surfaced only because I ran the 8-input classifier bench against the post-fix version:

```text
classify_linkedin_error (post-fix): 6/8 passed
FAIL: "Error code HTTP 4012ab in metadata" expected=content-rejected got=vendor-blocked
FAIL: "Error code HTTP 4031 in metadata" expected=content-rejected got=vendor-blocked
```

Had the bench not been part of the fix workflow, the over-match would have shipped under a "fix-inline" commit titled "anchor regex over-match", silently keeping the same defect.

## Solution

Switch to a regex with an explicit non-digit boundary so `4012` cannot match `(401)`:

```bash
[[ "$err" =~ HTTP\ (401|403)([^0-9]|$) ]]
```

The `([^0-9]|$)` alternation enforces that the captured code is followed by either a non-digit character (space, colon, end-of-token) or end-of-string. The 11-case bench (4 vendor-blocked positives, 4 content-rejected negatives including the two `HTTP 4012`/`HTTP 4031` traps, 3 transient codes) now passes 11/11.

The agent's "use literal substring like siblings" recommendation was applicable only to the **string-keyword** branches (`LINKEDIN_ORG_ACCESS_TOKEN`, `w_organization_social`) where the keyword has its own natural boundary. For numeric codes, a boundary anchor is mandatory.

## Key Insight

**When fixing an over-match flagged in review, the fix MUST be unit-tested against the SAME inputs that triggered the original concern.**

Substring-match alternatives to a flagged regex are NOT automatically safe. If the original regex captured `401` from `4012`, then a substring match for `"HTTP 401"` will also capture `"HTTP 4012ab"` for the same reason — both miss the trailing-boundary check. The transformation from regex to substring does not introduce a boundary; it just changes the syntax of the unbounded capture.

The single-line generalization: **boundary defects are about what comes AFTER the captured token, not about regex-vs-substring**. Any fix has to anchor the boundary explicitly, regardless of which matching primitive carries it.

Operational corollary: any "fix inline" commit that resolves an over-match SHOULD include a regression bench against the exact trigger inputs the reviewer named. The cost is ≤10 lines of shell; the savings is "did not re-ship the same defect with a different name".

## Session Errors

- **Agent namespace error** — Recovery: re-spawned `pattern-recognition-specialist` as `soleur:engineering:review:pattern-recognition-specialist`. Prevention: review skill could note the available-agent list IS the namespace catalogue.
- **Plan AC literal-grep brittleness** — three plan ACs (`grep 'alias = ...'` single-space, `! grep 'lifecycle'`, `grep -F "...** ..."`) failed after correct implementation because they didn't survive `terraform fmt` column alignment, legitimate comment wording, or markdown bolding. Recovery: blank-line workaround for fmt, reword comment, strip `**` from issue body. Prevention: when authoring plan ACs that grep canonical-tool output, prefer whitespace-tolerant regex (`grep -qE 'alias[[:space:]]*=[[:space:]]*"...'`) or document expected fixup-commit overhead.
- **Stale tests on old env-var contract** — `test/content-publisher.test.ts` had 4 assertions on `LINKEDIN_ACCESS_TOKEN not set` that broke when `post_linkedin_company` migrated to `LINKEDIN_ORG_ACCESS_TOKEN`. tasks.md didn't include a "grep existing tests for the old contract" step. Recovery: updated 4 test assertions + added a `gh` stub for the routing-to-tracker path. Prevention: /work Phase 2 (or the relevant plan template) should grep `test/` for the old env-var name before changing the production contract.
- **Regex over-match fix-inline trap (the topic of this learning)** — Recovery: switched to `=~ HTTP (401|403)([^0-9]|$)`. Prevention: every over-match fix commit must run the trigger-input bench against the post-fix version, not just smoke-test the happy path.

## Tags

category: code-quality
module: scripts/content-publisher.sh
