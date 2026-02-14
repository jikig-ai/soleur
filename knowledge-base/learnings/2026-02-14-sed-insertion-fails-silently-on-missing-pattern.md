---
title: Sed insertion fails silently when target pattern is missing
date: 2026-02-14
category: build-errors
tags: [sed, html, automation, mechanical-changes, code-review]
module: docs
symptoms: ["og:image meta tag missing on some pages after batch sed update", "sed /a command produces no output when pattern not found"]
---

# Learning: Sed insertion fails silently when target pattern is missing

## Problem

When batch-updating 7 HTML pages to add `og:image` meta tags, the sed command inserted the new tag "after the og:type meta tag line." Three pages (changelog, getting-started, mcp-servers) had a simpler `<head>` structure that lacked `og:type` entirely. Sed's `/pattern/a` command silently does nothing when the pattern isn't found -- no error, no warning. The og:image tag was missing on those 3 pages until code review caught it.

## Solution

After any batch sed operation across multiple files, verify the change actually landed:

```bash
# After adding og:image to all pages:
grep -rL "og:image" plugins/soleur/docs/**/*.html plugins/soleur/docs/*.html
# Returns files MISSING the pattern -- should be empty
```

Or use a more defensive sed approach that doesn't depend on a specific anchor line:

```bash
# Instead of: sed -i '/<meta property="og:type"/a\  <meta ...'
# Use: check if pattern already exists, if not insert after a reliable anchor
grep -q "og:image" "$file" || sed -i '/<\/head>/i\  <meta property="og:image" ...' "$file"
```

## Key Insight

Sed's append/insert commands (`a`, `i`) fail silently when the address pattern doesn't match. When making mechanical changes across multiple files with different structures, always verify with `grep -rL` (list files NOT matching) after the batch operation. Code review agents catch this reliably -- never skip the review step for "mechanical" changes.

## Tags
category: build-errors
module: docs
