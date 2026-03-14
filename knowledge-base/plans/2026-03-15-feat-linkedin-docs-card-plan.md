---
title: "feat: Docs site LinkedIn card"
type: feat
date: 2026-03-15
semver: patch
---

# feat: Docs site LinkedIn card (site.json, community.njk)

## Overview

Add a LinkedIn card to the docs site community page, following the existing Discord/X/GitHub card pattern. This is a follow-up from the LinkedIn presence work (#138), deferred as #591 because the LinkedIn company page URL did not exist at the time of the initial PR.

## Problem Statement

The community page (`plugins/soleur/docs/pages/community.njk`) lists three social platforms (Discord, X/Twitter, GitHub) but omits LinkedIn, which is the primary B2B channel for reaching engineering managers and technical decision-makers. The `site.json` data file also lacks a LinkedIn URL entry.

## Proposed Solution

Two file changes, following the exact pattern established by the existing cards:

### 1. `plugins/soleur/docs/_data/site.json`

Add `"linkedin"` key with the company page URL:

```json
"x": "https://x.com/soleur_ai",
"linkedin": "https://linkedin.com/company/soleur",
"newsletter": {
```

### 2. `plugins/soleur/docs/pages/community.njk`

Add a 4th card to the Connect section's `.catalog-grid`, after the GitHub card and before the closing `</div>`:

```html
<a href="{{ site.linkedin }}" target="_blank" rel="noopener" class="component-card community-card-link">
  <div class="card-header">
    <span class="card-dot" style="background: #0A66C2"></span>
    <span class="card-category">Professional</span>
  </div>
  <h3 class="card-title">LinkedIn</h3>
  <p class="card-description">Connect with the team, follow company updates, and join the conversation about building with AI.</p>
</a>
```

**Card dot color:** `#0A66C2` (LinkedIn brand blue, per issue spec).
**Category label:** "Professional" (per issue spec).

## Technical Considerations

- **Grid layout compatibility:** The `.catalog-grid` uses `repeat(auto-fill, minmax(300px, 1fr))`, which handles 4 cards without layout issues -- auto-fill wraps naturally at all breakpoints.
- **No CSS changes needed:** All required classes (`component-card`, `community-card-link`, `card-dot`, `card-header`, `card-category`, `card-title`, `card-description`) already exist in `style.css`.
- **No build changes:** Eleventy template uses `{{ site.linkedin }}` which resolves from `site.json` -- no data file schema changes needed.

## Gate

Blocked on LinkedIn company page creation at `https://linkedin.com/company/soleur` (manual browser action requiring LinkedIn admin account). The card can be merged with the URL in place, but the link will 404 until the page is created.

## Acceptance Criteria

- [ ] `site.json` contains `"linkedin": "https://linkedin.com/company/soleur"` after the `"x"` entry
- [ ] `community.njk` Connect section has 4 cards: Discord, X/Twitter, GitHub, LinkedIn
- [ ] LinkedIn card uses `#0A66C2` dot color and "Professional" category label
- [ ] LinkedIn card links to `{{ site.linkedin }}` with `target="_blank" rel="noopener"`
- [ ] Card renders correctly at desktop, tablet, and mobile breakpoints (visual check)

## Test Scenarios

- Given the community page is loaded, when the user views the Connect section, then 4 cards are visible (Discord, X/Twitter, GitHub, LinkedIn)
- Given the LinkedIn card is clicked, when the company page exists, then it opens `https://linkedin.com/company/soleur` in a new tab
- Given a mobile viewport (< 600px), when the community page loads, then the LinkedIn card stacks vertically with the other cards without overflow

## Non-goals

- LinkedIn API integration (tracked in #589)
- LinkedIn analytics/monitoring in community-manager (tracked in #590)
- Content generation for LinkedIn posting (shipped in feat/linkedin-presence)
- CSS changes or new component styles

## References

- Parent issue: #138 (LinkedIn Presence)
- This issue: #591
- Pattern: existing Discord/X/GitHub cards in `community.njk`
- Learning: [Platform Integration Scope Calibration](../learnings/2026-03-13-platform-integration-scope-calibration.md) -- this card was deferred from the original LinkedIn presence PR to keep scope tight
- Related deferred issues: #589 (API scripts), #590 (monitoring), #592 (content publisher), #593 (company page creation)
