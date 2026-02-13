---
title: "Version bumps must cascade to HTML version badges in docs site"
category: workflow-patterns
tags: [versioning, docs, html, version-badge, release]
module: docs
symptom: "HTML pages show old version number after plugin version bump"
root_cause: "Version bump triad (plugin.json + CHANGELOG.md + README.md) doesn't include HTML docs site pages that display version badges"
---

# Version Bump Cascades to HTML Badges

## Problem

The Soleur versioning triad requires updating 3 files: plugin.json, CHANGELOG.md, README.md. But after adding the docs site, 8 HTML files also contain `<span class="version-badge">v2.6.1</span>` in their navigation header. Bumping the version to 2.6.2 left all HTML pages showing v2.6.1.

Additionally, the changelog.html page needs a new entry added when the version is bumped.

## Solution

After bumping the standard triad, also:

1. Search all HTML docs for the old version string: `grep -r "v2.6.1" plugins/soleur/docs/`
2. Update all matches to the new version
3. Add the new version entry to `pages/changelog.html`

## Prevention

When the `release-docs` skill regenerates all pages, it should pull the version from `plugin.json` automatically. Until then, add a manual step to the version bump checklist:

- [ ] Update version in all `plugins/soleur/docs/**/*.html` files

## Key Insight

Any hardcoded version string in the codebase is a maintenance liability. The versioning triad is now a "versioning pentad" with docs: plugin.json + CHANGELOG.md + README.md + root README badge + HTML version badges. Consider generating version badges from plugin.json at build/release time.
