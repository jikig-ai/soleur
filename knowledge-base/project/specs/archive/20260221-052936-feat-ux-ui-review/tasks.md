# Tasks: UX/UI Review -- Content Readability & Header Logo

**Branch:** feat-ux-ui-review
**Issue:** #201

## Phase 1: CSS

- [ ] 1.1 Add `.prose` class to `@layer components` in `style.css` (max-width: 75ch, heading/paragraph/list margins)
- [ ] 1.2 Add `#changelog-content` overrides (mono font h2, border-bottom, first-child margin, h3 font-size)
- [ ] 1.3 Add `.community-text + .community-text { margin-top }` rule for vision page paragraph spacing

## Phase 2: Templates

- [ ] 2.1 Add `<img>` logo mark to header in `base.njk` (width=24, height=24, alt="", no CSS class needed)
- [ ] 2.2 Add `class="prose"` to `#changelog-content` div in `changelog.njk`
- [ ] 2.3 Add `<div class="prose">` wrapper to all 7 legal pages (privacy-policy, terms-and-conditions, cookie-policy, acceptable-use-policy, data-protection-disclosure, disclaimer, gdpr-policy)
- [ ] 2.4 Wrap prose sections in getting-started.md with `<div class="prose">` pairs (leave grid components unwrapped)

## Phase 3: Verify

- [ ] 3.1 Build docs and check each modified page visually
- [ ] 3.2 Verify mobile responsiveness at 375px viewport
- [ ] 3.3 Verify card grids, hero sections, and nav are unchanged
