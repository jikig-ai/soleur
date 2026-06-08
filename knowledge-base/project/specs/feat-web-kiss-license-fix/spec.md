---
feature: web-kiss-license-fix
date: 2026-06-08
status: spec
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
brainstorm: knowledge-base/project/brainstorms/2026-06-08-web-kiss-license-fix-brainstorm.md
wireframe: knowledge-base/product/design/website/homepage-kiss-declutter.pen
---

# Spec — soleur.ai License Correction + KISS Homepage Declutter

## Problem Statement

The public marketing site (Eleventy, `plugins/soleur/docs/`, served at soleur.ai)
states present-tense that Soleur is "Apache-2.0 open source." This is inaccurate: the
current license is **BSL 1.1** (root `LICENSE`, README badge, `docs/legal/*`), which
only converts to Apache-2.0 four years after each release. Because BSL 1.1 is not
OSI-approved, even "open source" is a misrepresentation. The false claim is rendered
site-wide — meta summary, JSON-LD structured data, comparison tables, and FAQ rich
snippets — so it also propagates into search and AI answers. Separately, the homepage
has accumulated clutter (duplicate CTAs, a repeated final headline, overlapping prose)
that the UX lead's KISS principle would cut.

## Goals

- G1: Replace every present-tense "Apache-2.0" / "open source" license claim across
  the marketing site with the accurate "source-available (BSL 1.1, converts to
  Apache-2.0 after 4 years)" descriptor.
- G2: Make the correction exhaustive and regression-proof — a CI guard fails if
  "Apache-2.0"/"open source" reappears in marketing surfaces.
- G3: Declutter `index.njk` (moderate) per KISS without harming AEO/SEO or the
  waitlist conversion path, matching the committed wireframe.

## Non-Goals

- NG1: Editing the canonical legal documents (`docs/legal/*.md`) — already correct.
- NG2: Aggressive re-sequencing of homepage sections (explicitly deferred; moderate scope chosen).
- NG3: Changing the actual license, LICENSE file, or T&C conversion terms.
- NG4: Rewriting dated blog *content* beyond the license-claim corrections.

## Functional Requirements

- **FR1 (license sweep, P0):** Correct the site-wide meta summary
  `_includes/page-freshness.njk:20,22` and JSON-LD `_includes/base.njk:104,109`.
- **FR2 (license sweep, P1 — required for full cure):** Correct the remaining 12
  marketing files — `index.njk:197,253`, `pages/pricing.njk`, `pages/about.njk`,
  `pages/getting-started.njk`, `pages/community.njk`,
  `pages/compare-soleur-vs-cursor.njk`, `pages/compare-soleur-vs-devin.njk`, and blog
  posts `2026-03-16-soleur-vs-anthropic-cowork.md`,
  `2026-03-17-soleur-vs-notion-custom-agents.md`, `2026-03-26-soleur-vs-polsia.md`.
  Each FAQ/prose change must also update its mirrored JSON-LD `"text"` twin.
- **FR3 (phrasing):** Hero badge/footer = "Source-available — BSL 1.1"; the
  "converts to Apache-2.0 four years after each release" clause appears in
  meta/FAQ context, not the terse badge.
- **FR4 (regression guard):** Add a CI guard that fails on "Apache-2.0" or
  "open source" present-tense license claims under `plugins/soleur/docs/` marketing
  surfaces (excluding the legal `.md` and dated historical-fact contexts as needed).
- **FR5 (declutter, moderate):** Per wireframe `homepage-kiss-declutter.pen`:
  cut the duplicate mid-page CTA (`landing-cta-mid`); collapse hero to inline waitlist
  form + one "try open-source" link (drop the See-Pricing button + compare anchor);
  replace the repeated final-CTA headline with a distinct closing line; compress
  "This Is the Way" prose overlap; fold the standalone newsletter into the closing CTA.
- **FR6 (preserve AEO/SEO):** Keep the FAQ block + its FAQPage JSON-LD, the Compare
  section (promoted from FAQ per #3996), and the stats/departments strips unchanged.

## Technical Requirements

- **TR1 (packaging):** Two commits on branch `feat-web-kiss-license-fix` — commit 1 =
  license sweep + guard (shippable alone); commit 2 = KISS declutter. License fix must
  not be blocked by any declutter gate failure.
- **TR2 (JSON-LD integrity):** All edited JSON-LD blocks must remain valid JSON (no
  lint/test parses them — manual care required) to preserve rich-result eligibility.
- **TR3 (screenshot gate):** The `index.njk` declutter must clear the critical-CSS
  screenshot gate (`cq-eleventy-critical-css-screenshot-gate`); re-inline any
  newly-above-fold selectors into `base.njk`.
- **TR4 (no T&C contradiction):** Phrasing must not flatten to "not open source" or a
  blanket "Apache-2.0 → BSL" replace that contradicts the T&C conversion language.
- **TR5 (CI):** A docs change triggers `critical-css-gate`, the legal-doc SHA-pin
  guard, and vitest shards — all must pass.

## Acceptance Criteria

- No present-tense "Apache-2.0" or "open source" license claim remains in
  `plugins/soleur/docs/` marketing surfaces (grep-clean); FR4 guard passes.
- Homepage matches the committed wireframe; FAQ/Compare/stats unchanged.
- Critical-CSS screenshot gate + legal-doc guard + vitest all green.
