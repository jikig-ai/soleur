# Learning: FAQ section insertion point must be outside container divs for consistent layout

## Problem

When adding FAQ sections with FAQPage JSON-LD schema to 11 documentation pages (6 NJK templates + 5 blog case studies), the FAQ sections ended up with inconsistent DOM nesting across pages.

Pages like `vision.njk` and `community.njk` wrapped their entire content in a single `<div class="container">`. Pages like `agents.njk`, `skills.njk`, and `changelog.njk` had their catalog grids inside a `<div class="container">` that closed mid-page, leaving the rest of the page at root level.

A subagent using an "append before the last closing tag" heuristic placed FAQ sections inside whatever wrapper existed at the end of each file. This produced two different layouts:

- **Inside container** (vision, community): 6-space indent, constrained to container max-width
- **Outside container** (agents, skills, changelog): 4-space indent, full viewport width via `landing-section` class

The reference implementation (`index.njk`) had its FAQ outside any container div, confirming the outside pattern was correct.

## Solution

Moved FAQ sections in `vision.njk` and `community.njk` outside the `<div class="container">` wrapper to match the pattern established by `agents.njk`, `skills.njk`, `changelog.njk`, and the reference `index.njk`. All FAQ sections now sit at the same DOM depth with consistent `landing-section` styling.

## Key Insight

When adding new full-width sections to template pages with varying DOM structures, never rely on positional heuristics like "append before the last closing tag." The insertion point determines layout behavior -- inside a container div means constrained width; outside means full viewport. Explicitly identify and close the container boundary, then insert the new section after it. For batch operations across multiple templates, verify the DOM structure of each target page individually rather than assuming structural uniformity.

## Tags

category: template-patterns
module: docs-site
issue: 653
related:

- knowledge-base/project/learnings/build-errors/eleventy-seo-aeo-patterns.md
