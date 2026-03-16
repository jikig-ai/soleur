---
title: "feat: Docs site LinkedIn card"
type: feat
date: 2026-03-15
semver: patch
deepened: 2026-03-15
---

## Enhancement Summary

**Deepened on:** 2026-03-15
**Sections enhanced:** 3 (Proposed Solution, Acceptance Criteria, Test Scenarios)
**Research sources:** Codebase analysis (base.njk footer), LinkedIn brand guidelines (brand.linkedin.com), platform-integration-scope-calibration learning

### Key Improvements

1. **Footer social link gap discovered** -- `base.njk` footer (lines 108-112) has hardcoded social links for Discord, GitHub, and X but no LinkedIn; adding a footer link keeps the site consistent (3 files total, not 2)
2. **Brand color verified** -- `#0A66C2` confirmed against LinkedIn's official brand assets at brand.linkedin.com
3. **Accessibility consideration added** -- LinkedIn card should include `aria-label="LinkedIn"` on the link for screen reader consistency with footer pattern

### New Considerations Discovered

- The footer social links in `base.njk` are hardcoded (not data-driven from `site.json`), so adding the `site.json` key alone does not propagate to the footer -- a manual addition is required
- All three existing footer social links use `aria-label` attributes; the community page cards do not -- this is an existing inconsistency, not something to fix in this PR

# feat: Docs site LinkedIn card (site.json, community.njk, base.njk)

## Overview

Add a LinkedIn card to the docs site community page, following the existing Discord/X/GitHub card pattern. This is a follow-up from the LinkedIn presence work (#138), deferred as #591 because the LinkedIn company page URL did not exist at the time of the initial PR.

## Problem Statement

The community page (`plugins/soleur/docs/pages/community.njk`) lists three social platforms (Discord, X/Twitter, GitHub) but omits LinkedIn, which is the primary B2B channel for reaching engineering managers and technical decision-makers. The `site.json` data file also lacks a LinkedIn URL entry.

## Proposed Solution

Three file changes, following the exact patterns established by the existing cards and footer:

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

**Card dot color:** `#0A66C2` (LinkedIn brand blue, per issue spec -- verified against brand.linkedin.com).
**Category label:** "Professional" (per issue spec).

### 3. `plugins/soleur/docs/_includes/base.njk`

Add LinkedIn to the footer social links (line 111, after the X link):

```html
<a href="{{ site.linkedin }}" target="_blank" rel="noopener" aria-label="LinkedIn">LinkedIn</a>
```

This follows the existing footer pattern where Discord, GitHub, and X are listed as individual `<a>` tags inside `.footer-social`.

### Research Insights

**Discovered during deepening:** The footer social links in `base.njk` (lines 108-112) are hardcoded per-platform, not data-driven from `site.json`. Adding the `linkedin` key to `site.json` does not automatically populate the footer -- the link must be added manually. Omitting this would create an inconsistency where LinkedIn appears on the community page but not in the site-wide footer.

## Technical Considerations

- **Grid layout compatibility:** The `.catalog-grid` uses `repeat(auto-fill, minmax(300px, 1fr))`, which handles 4 cards without layout issues -- auto-fill wraps naturally at all breakpoints.
- **No CSS changes needed:** All required classes (`component-card`, `community-card-link`, `card-dot`, `card-header`, `card-category`, `card-title`, `card-description`) already exist in `style.css`.
- **No build changes:** Eleventy template uses `{{ site.linkedin }}` which resolves from `site.json` -- no data file schema changes needed.

## Gate

Blocked on LinkedIn company page creation at `https://linkedin.com/company/soleur` (manual browser action requiring LinkedIn admin account). The card can be merged with the URL in place, but the link will 404 until the page is created.

## Acceptance Criteria

- [x] `site.json` contains `"linkedin": "https://linkedin.com/company/soleur"` after the `"x"` entry
- [x] `community.njk` Connect section has 4 cards: Discord, X/Twitter, GitHub, LinkedIn
- [x] LinkedIn card uses `#0A66C2` dot color and "Professional" category label
- [x] LinkedIn card links to `{{ site.linkedin }}` with `target="_blank" rel="noopener"`
- [x] `base.njk` footer `.footer-social` includes LinkedIn link with `aria-label="LinkedIn"`
- [ ] Card renders correctly at desktop, tablet, and mobile breakpoints (visual check)
- [x] Footer LinkedIn link renders alongside Discord, GitHub, and X links

## Test Scenarios

- Given the community page is loaded, when the user views the Connect section, then 4 cards are visible (Discord, X/Twitter, GitHub, LinkedIn)
- Given the LinkedIn card is clicked, when the company page exists, then it opens `https://linkedin.com/company/soleur` in a new tab
- Given a mobile viewport (< 600px), when the community page loads, then the LinkedIn card stacks vertically with the other cards without overflow
- Given any page on the docs site is loaded, when the user scrolls to the footer, then LinkedIn appears in the social links alongside Discord, GitHub, and X

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
