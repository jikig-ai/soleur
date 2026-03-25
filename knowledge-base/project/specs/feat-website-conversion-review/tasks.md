# Tasks: Website Conversion Flow Review

**Plan:** [2026-03-25-feat-website-conversion-flow-review-plan.md](../../plans/2026-03-25-feat-website-conversion-flow-review-plan.md)
**Spec:** [spec.md](./spec.md)
**Issue:** #1142

## Phase 0: UX Gate (BLOCKING)

- [ ] 0.1 Run ux-design-lead: wireframes for homepage hero (resolve 3-CTA hierarchy for desktop + mobile) + Getting Started two-path layout
- [ ] 0.2 Run copywriter: hero headline/subheadline, CTA copy, **homepage FAQ (all 6 Q&A)**, Getting Started copy, form success messages, `site.json` description (must read brand-guide.md first)
- [ ] 0.3 CMO reviews wireframes + copy artifacts. No code until approved.

## Phase 1: Base Layout and Metadata

- [ ] ~~1.1~~ Pricing already in nav (PR #1136)
- [ ] 1.1b Update `site.json` `description` field (line 6) — says "A Claude Code plugin" (CPO: HIGH)
  - `plugins/soleur/docs/_data/site.json`
- [ ] 1.2 Update `<meta name="description">` — remove "Claude Code plugin"
  - `plugins/soleur/docs/_includes/base.njk:6`
- [ ] 1.3 Update OG tags (`og:description`, `twitter:description`)
  - `plugins/soleur/docs/_includes/base.njk:8-23`
- [ ] 1.4 Update JSON-LD `SoftwareApplication` — remove `"price": "0"`, `"softwareRequirements": "Claude Code CLI"`, change `applicationCategory`
  - `plugins/soleur/docs/_includes/base.njk:24-63`
- [ ] 1.5 Verify `<title>` pattern (line 66) has no "plugin" language
- [ ] 1.6 Eleventy dry-run build

## Phase 2: Homepage Reframe

- [ ] 2.1 Rewrite hero section (lines 8-16) from approved copy
  - `plugins/soleur/docs/index.njk`
- [ ] 2.1b Update homepage frontmatter description (line 3) — says "a Claude Code plugin" (CPO: HIGH)
  - `plugins/soleur/docs/index.njk`
- [ ] 2.2 Add inline waitlist form — Buttondown endpoint, `homepage-waitlist` tag, honeypot, Plausible "Waitlist Signup" event
  - `plugins/soleur/docs/index.njk`
- [ ] 2.3 Primary CTA: "See Pricing & Join Waitlist" → `/pages/pricing.html`
- [ ] 2.4 Secondary CTA: "Or try the open-source version" → `/pages/getting-started.html`
- [ ] 2.5 Rewrite FAQ section (lines 127-159) + FAQ JSON-LD (lines 161-216) from approved copy
  - `plugins/soleur/docs/index.njk`
- [ ] 2.5b Remove "plugin" from body copy (department cards, features, quote)
- [ ] 2.5c Update mid-page CTA (lines 73-75) + final CTA (lines 218-223) → pricing page
- [ ] 2.6 Add CSS for hero waitlist form in `@layer components`
  - `plugins/soleur/docs/css/style.css`
- [ ] 2.7 Test at mobile (≤768px), tablet (769-1024px), desktop (>1024px)

## Phase 3: Getting Started Split

- [ ] 3.1 Convert `getting-started.md` → `getting-started.njk`
- [ ] 3.2 Two-path layout from wireframe. Cloud CTA → `pricing.html#waitlist`. Update FAQ.
  - `plugins/soleur/docs/pages/getting-started.njk`
- [ ] 3.3 Add CSS for two-path layout in `@layer components`
- [ ] 3.4 Test responsive at all three breakpoints

## Phase 4: Vision Page and Site-Wide Cleanup

- [ ] 4.1 Remove "Success Tax" section (lines 151-181) from vision page
  - `plugins/soleur/docs/pages/vision.njk`
- [ ] 4.2 Remove "terminal-first" language from vision page
- [ ] 4.3 Update `llms.txt.njk` — remove plugin framing
- [ ] 4.4 Audit remaining pages for "plugin": community, agents, skills
- [ ] 4.5 Update newsletter form: add `tag="newsletter"` hidden field, review copy
  - `plugins/soleur/docs/_includes/newsletter-form.njk`
- [ ] 4.5b Update form JS handler: per-form success messages (`data-success-message`), unified Plausible events (`data-plausible-event`)
  - `plugins/soleur/docs/_includes/base.njk:119-148`
- [ ] 4.6 Verify legal docs — grep for contradictions

## Phase 5: Verify and Test

- [ ] 5.1 Full Eleventy build from repo root
- [ ] 5.2 Check all internal links
- [ ] 5.3 Verify OG tags render in production HTML (#1121)
- [ ] 5.4 Test homepage waitlist form — Buttondown receives with `homepage-waitlist` tag
- [ ] 5.5 Verify Plausible "Waitlist Signup" events fire
- [ ] 5.6 Screenshot all modified pages at 3 breakpoints
- [ ] 5.7 Configure Plausible goals for conversion tracking

## Post-Merge

- [ ] Assign #1142 to milestone (Pre-Phase 4 or "Marketing Positioning")
- [ ] Update `roadmap.md` — mark M2, M5 as pulled forward from Pre-Phase 4
- [ ] Reconcile #1129 milestone (meta descriptions) after merge
