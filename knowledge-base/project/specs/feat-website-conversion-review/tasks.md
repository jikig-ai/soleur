# Tasks: Website Conversion Flow Review

**Plan:** [2026-03-25-feat-website-conversion-flow-review-plan.md](../../plans/2026-03-25-feat-website-conversion-flow-review-plan.md)
**Spec:** [spec.md](./spec.md)
**Issue:** #1142

## Phase 0: UX Gate (BLOCKING)

- [x] 0.1 ux-design-lead wireframes — DONE (`knowledge-base/product/design/website/homepage-getting-started-wireframes.pen`)
- [x] 0.2 Run copywriter: hero, CTAs, FAQ (6 Q&A), Getting Started copy, site.json description — DONE (`knowledge-base/project/specs/feat-website-conversion-review/copy-deck.md`)
- [x] 0.3 CMO review. No code until approved. — DONE (approved per commit 47362f80)

## Phase 1: All Content and Template Changes

- [x] 1.1 `site.json` — Update description (line 5), remove "plugin"
- [x] 1.2 `base.njk` — Meta description, OG tags, JSON-LD (one session). Also: form-aware success messages (waitlist vs newsletter)
- [x] 1.3 `index.njk` — Hero rewrite, inline waitlist form (`homepage-waitlist` tag), CTAs, FAQ + JSON-LD, mid/final CTAs, body copy cleanup
- [x] 1.4 `getting-started.md` → `.njk` — Two-path layout, FAQ + JSON-LD update
- [x] 1.5 `vision.njk` — Remove Success Tax, fix `var(--accent)` → `var(--color-accent)` (3 instances)
- [x] 1.6 `newsletter-form.njk` — Add `newsletter` Buttondown tag
- [x] 1.7 `llms.txt.njk` — Remove plugin framing (3 instances)
- [x] 1.8 `style.css` — Hero form + two-path layout in `@layer components`
- [x] 1.9 `pricing.njk` — No changes needed, CTAs already aligned

## Phase 2: Build, Test, Ship

- [x] 2.1 Full Eleventy build — 41 files, 0 errors
- [x] 2.2 Internal link verification — all targets exist in build output
- [x] 2.3 OG tag verification (#1121) — no "plugin" in meta/OG/Twitter descriptions
- [x] 2.4 Homepage form test — `homepage-waitlist` tag present, form renders with Buttondown action
- [x] 2.5 Responsive screenshots — homepage + getting-started at desktop/tablet/mobile, vision at desktop

## Post-Merge

- [ ] Assign #1142 to milestone
- [ ] Update `roadmap.md` (M2, M5 pulled forward)
- [ ] File issue for legal docs "plugin" cleanup
