# Tasks: LinkedIn Docs Card

## Phase 1: Setup

- [ ] 1.1 Read `plugins/soleur/docs/_data/site.json` to confirm current structure
- [ ] 1.2 Read `plugins/soleur/docs/pages/community.njk` to confirm card pattern
- [ ] 1.3 Read `plugins/soleur/docs/_includes/base.njk` footer social links section

## Phase 2: Core Implementation

- [ ] 2.1 Add `"linkedin": "https://linkedin.com/company/soleur"` to `site.json` after the `"x"` entry
- [ ] 2.2 Add LinkedIn card to `community.njk` Connect section after the GitHub card
  - [ ] 2.2.1 Use `{{ site.linkedin }}` href with `target="_blank" rel="noopener"`
  - [ ] 2.2.2 Use `#0A66C2` card dot color (LinkedIn brand blue)
  - [ ] 2.2.3 Use "Professional" category label
  - [ ] 2.2.4 Use `community-card-link` class for link styling
- [ ] 2.3 Add LinkedIn link to `base.njk` footer `.footer-social` section after the X link
  - [ ] 2.3.1 Use `{{ site.linkedin }}` href with `target="_blank" rel="noopener" aria-label="LinkedIn"`

## Phase 3: Testing

- [ ] 3.1 Build docs site locally (`npx @11ty/eleventy`) to verify no template errors
- [ ] 3.2 Visual check: verify 4 cards render in Connect section at desktop width
- [ ] 3.3 Visual check: verify cards stack correctly at mobile width (< 600px)
- [ ] 3.4 Visual check: verify LinkedIn appears in footer social links on any page
