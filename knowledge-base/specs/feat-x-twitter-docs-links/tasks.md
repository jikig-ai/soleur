# Tasks: feat-x-twitter-docs-links

## Phase 1: Data Layer

- [ ] 1.1 Add `"x": "https://x.com/soleur_ai"` to `plugins/soleur/docs/_data/site.json`

## Phase 2: Core Implementation

- [ ] 2.1 Add X/Twitter card to Connect section in `plugins/soleur/docs/pages/community.njk`
  - [ ] 2.1.1 Use card dot color `#E7E9EA` for visibility on dark surface
  - [ ] 2.1.2 Category label: "Social", title: "X / Twitter"
  - [ ] 2.1.3 Link to `{{ site.x }}` with `target="_blank" rel="noopener"`
- [ ] 2.2 Add `<meta name="twitter:site" content="@soleur_ai">` to `plugins/soleur/docs/_includes/base.njk`
- [ ] 2.3 Add `**Handle:** [@soleur_ai](https://x.com/soleur_ai)` to X/Twitter section in `knowledge-base/overview/brand-guide.md`
- [ ] 2.4 Add footer social links to `plugins/soleur/docs/_includes/base.njk`
  - [ ] 2.4.1 Add `footer-social` div with Discord, GitHub, X links
  - [ ] 2.4.2 Add `.footer-social` CSS to `plugins/soleur/docs/css/style.css` under `@layer components`

## Phase 3: Validation

- [ ] 3.1 Run `npx @11ty/eleventy` -- build must succeed with zero errors
- [ ] 3.2 Verify community page renders three cards at desktop, tablet, and mobile breakpoints
- [ ] 3.3 Verify footer social links appear and point to correct URLs
- [ ] 3.4 Verify `twitter:site` meta tag in page source
