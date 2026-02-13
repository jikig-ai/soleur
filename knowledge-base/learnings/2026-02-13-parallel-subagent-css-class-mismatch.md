---
title: "Parallel subagent HTML generation creates CSS class mismatches"
category: implementation-patterns
tags: [subagents, parallel, css, html, static-site, naming-conventions]
module: docs
symptom: "HTML pages use CSS class names that don't exist in the stylesheet"
root_cause: "Independent subagents generating HTML pages in parallel each invent their own CSS class names instead of referencing the shared stylesheet"
---

# Parallel Subagent CSS Class Mismatch

## Problem

When spawning multiple subagents to generate HTML pages in parallel, each subagent independently chose CSS class names without consulting the shared `style.css`. This resulted in:

- `index.html` using `.hero`, `.workflow-pipeline`, `.workflow-node` classes
- Inner pages using `.hero`, `.subtitle`, `.content` classes
- CSS defining `.page-hero`, `.pipeline`, `.pipeline-node` classes
- None of the HTML class names matching the CSS definitions

## Root Cause

Each subagent received the CSS file content as context but still invented different class names. The CSS was ~500 lines, and subagents prioritized generating valid HTML structure over exact class name matching.

## Solution

After parallel generation, run a CSS class audit: extract all classes used in HTML and cross-reference against the CSS. Two fix strategies:

1. **Add missing CSS rules** (less invasive when many HTML files share the same undefined classes)
2. **Fix HTML class names** (better when only 1-2 files diverge from the CSS)

## Prevention

When spawning parallel HTML subagents:

1. Provide an **explicit class name reference list** (not the full CSS file) — e.g., "Use these exact class names: `.page-hero`, `.pipeline`, `.pipeline-node`..."
2. Or generate a single template HTML first, then have subagents copy its header/nav/footer exactly
3. Always run a post-generation class audit step before committing
