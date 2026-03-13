# Tasks: feat-x-twitter-docs-links

## Phase 1: Data Layer

- [ ] 1.1 Add `"x": "https://x.com/soleur_ai"` to `plugins/soleur/docs/_data/site.json`

## Phase 2: Core Implementation

- [ ] 2.1 Add X/Twitter card to Connect section in `plugins/soleur/docs/pages/community.njk`
  - [ ] 2.1.1 Use card dot color `#E7E9EA` for visibility on dark surface
  - [ ] 2.1.2 Category label: "Social", title: "X / Twitter"
  - [ ] 2.1.3 Link to `{{ site.x }}` with `target="_blank" rel="noopener"`
- [ ] 2.2 Add Twitter Card meta tags to `plugins/soleur/docs/_includes/base.njk`
  - [ ] 2.2.1 Add `<meta name="twitter:site" content="@soleur_ai">`
  - [ ] 2.2.2 Add `<meta name="twitter:creator" content="@soleur_ai">`
- [ ] 2.3 Add `**Handle:** [@soleur_ai](https://x.com/soleur_ai)` to X/Twitter section in `knowledge-base/overview/brand-guide.md`
- [ ] 2.4 Add footer social links to `plugins/soleur/docs/_includes/base.njk`
  - [ ] 2.4.1 Add `footer-social` div with Discord, GitHub, X links between `footer-links` and `footer-tagline`
  - [ ] 2.4.2 Add `.footer-social` CSS to `plugins/soleur/docs/css/style.css` under `@layer components` (after `.community-text a` rule)
  - [ ] 2.4.3 Use `--color-text-secondary` token (not shorthand `--accent`)

## Phase 3: Validation

- [ ] 3.1 Run `npm install` in worktree (worktrees do not share node_modules)
- [ ] 3.2 Run `npx @11ty/eleventy --input=plugins/soleur/docs --output=_site` from repo root -- build must succeed with zero errors
- [ ] 3.3 Verify community page renders three cards at desktop, tablet, and mobile breakpoints
- [ ] 3.4 Verify footer social links appear and point to correct URLs on all pages
- [ ] 3.5 Verify `twitter:site` and `twitter:creator` meta tags in page source
- [ ] 3.6 Verify card dot colors are visible on dark background (X: `#E7E9EA`)
