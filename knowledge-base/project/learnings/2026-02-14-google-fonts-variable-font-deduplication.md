---
title: Google Fonts variable font deduplication
date: 2026-02-14
category: build-errors
tags: [fonts, woff2, google-fonts, variable-fonts, self-hosting]
module: docs
symptoms: ["Two downloaded font files have identical md5 hash", "Same Google Fonts URL returned for different weights"]
---

# Learning: Google Fonts variable font deduplication

## Problem

When self-hosting Google Fonts, downloading Inter weight 400 and weight 700 separately produced two identical 48KB woff2 files (same md5 hash). The Google Fonts CSS API returned the same URL for both weights because Inter v20+ is a variable font -- one file covers the entire weight range.

## Solution

Use a single woff2 file with a weight range in the `@font-face` declaration:

```css
@font-face {
  font-family: 'Inter';
  src: url('../fonts/inter.woff2') format('woff2');
  font-weight: 400 700;
  font-style: normal;
  font-display: swap;
}
```

Instead of two separate `@font-face` rules pointing to identical files.

## Key Insight

Before downloading multiple weight variants of a Google Font, check if the CSS API returns the same URL for different weights. If so, it's a variable font -- use one file with `font-weight: <min> <max>` range syntax. This saves repo space and avoids redundant HTTP requests.

## Detection

```bash
# Query Google Fonts CSS API for the font
curl -s "https://fonts.googleapis.com/css2?family=Inter:wght@400;700&display=swap" \
  -H "User-Agent: Mozilla/5.0"

# If the same URL appears for multiple weight ranges, it's a variable font
# After download, verify with:
md5sum fonts/inter-400.woff2 fonts/inter-700.woff2
```

## Tags
category: build-errors
module: docs
