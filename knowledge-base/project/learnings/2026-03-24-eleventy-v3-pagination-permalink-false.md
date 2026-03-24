# Learning: Eleventy v3 pagination does not support `permalink: false` per item

## Problem

When using Eleventy v3 pagination with conditional permalink expressions, setting `permalink` to `false` for items that should not generate output fails. Nunjucks string `"false"` becomes a literal path (`_site/false`). Boolean `false` from `.11tydata.js` throws TypeError.

## Solution

Use a `_data/*.js` global data file to pre-filter items so every pagination item produces output. No conditional permalink needed.

## Key Insight

When Eleventy pagination needs to conditionally generate output, pre-filter the data source rather than conditionally set the permalink. Also: templates placed in directories with data cascade files (e.g., `blog.json`) inherit properties like `layout` — always override them explicitly.

## Tags

category: build-errors
module: blog, eleventy
