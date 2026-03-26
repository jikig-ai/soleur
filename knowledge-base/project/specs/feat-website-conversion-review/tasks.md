# Tasks: Website Conversion Flow Review

**Plan:** [2026-03-25-feat-website-conversion-flow-review-plan.md](../../plans/2026-03-25-feat-website-conversion-flow-review-plan.md)
**Spec:** [spec.md](./spec.md)
**Issue:** #1142

## Phase 0: UX Gate (BLOCKING)

- [x] 0.1 ux-design-lead wireframes — DONE (`knowledge-base/product/design/website/homepage-getting-started-wireframes.pen`)
- [ ] 0.2 Run copywriter: hero, CTAs, FAQ (6 Q&A), Getting Started copy, site.json description
- [ ] 0.3 CMO review. No code until approved.

## Phase 1: All Content and Template Changes

- [ ] 1.1 `site.json` — Update description (line 5), remove "plugin"
- [ ] 1.2 `base.njk` — Meta description, OG tags, JSON-LD (one session)
- [ ] 1.3 `index.njk` — Hero rewrite, inline waitlist form (`homepage-waitlist` tag), CTAs, FAQ + JSON-LD, mid/final CTAs, body copy cleanup
- [ ] 1.4 `getting-started.md` → `.njk` — Two-path layout, FAQ + JSON-LD update
- [ ] 1.5 `vision.njk` — Remove Success Tax, fix `var(--accent)` → `var(--color-accent)`
- [ ] 1.6 `newsletter-form.njk` — Add `newsletter` Buttondown tag
- [ ] 1.7 `llms.txt.njk` — Remove plugin framing (3 instances)
- [ ] 1.8 `style.css` — Hero form + two-path layout in `@layer components`
- [ ] 1.9 `pricing.njk` — Minor CTA alignment if needed

## Phase 2: Build, Test, Ship

- [ ] 2.1 Full Eleventy build
- [ ] 2.2 Internal link verification
- [ ] 2.3 OG tag verification (#1121)
- [ ] 2.4 Homepage form test (Buttondown + `homepage-waitlist` tag)
- [ ] 2.5 Responsive screenshots (3 breakpoints, all modified pages)

## Post-Merge

- [ ] Assign #1142 to milestone
- [ ] Update `roadmap.md` (M2, M5 pulled forward)
- [ ] File issue for legal docs "plugin" cleanup
