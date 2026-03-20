---
title: "Eleventy legal mirror files have two Last Updated locations"
date: 2026-03-20
category: legal
tags:
  - legal-documents
  - eleventy
  - dual-location-sync
module: docs-site
---

# Learning: Eleventy legal mirror files have two "Last Updated" locations

## Problem

When updating "Last Updated" dates on legal documents, the Eleventy mirror files in `plugins/soleur/docs/pages/legal/` contain TWO date locations that must both be changed:

1. A **hero `<p>` tag** in the HTML wrapper near the top of the file (inside `<section class="page-hero">`), e.g.:
   ```html
   <p>Last Updated: March 20, 2026</p>
   ```
2. A **body markdown line** further down in the document content, e.g.:
   ```markdown
   **Last Updated:** March 20, 2026
   ```

The source files in `docs/legal/` have only one "Last Updated" location (the body markdown line), so agents applying the established "update both file locations" pattern correctly update the source file and the mirror's body line, but miss the mirror's hero `<p>` tag.

This has been caught by review agents in at least two sessions (legal-audit-890 task 4.3, and issue #912's harmonize-cloudflare session) before commit.

## Solution

When updating "Last Updated" on any legal document, grep the Eleventy mirror file for all date occurrences before editing:

```bash
grep -n "Last Updated\|Effective\|March.*2026\|202[0-9]" plugins/soleur/docs/pages/legal/<file>.md
```

This surfaces every date location in the file. Update all of them.

## Key Insight

The dual-location legal doc pattern (source + Eleventy mirror) is well-documented, but a file having multiple date locations *within itself* is a separate trap. The existing learnings teach "update both files" — this learning teaches "within the mirror file, update both the hero HTML and the body markdown."

## Session Errors

None

## Tags
category: legal
module: docs-site
