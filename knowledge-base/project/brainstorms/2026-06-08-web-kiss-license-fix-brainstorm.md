---
date: 2026-06-08
topic: soleur.ai license correction + KISS homepage declutter
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
---

# soleur.ai — License Correction + KISS Homepage Declutter

## What We're Building

Two separable changes to the public marketing site (the Eleventy site at
`plugins/soleur/docs/`, served at soleur.ai), shipped as two commits on one branch:

1. **License correction.** The live site claims, present-tense, that Soleur is
   "Apache-2.0 open source." The actual current license is **BSL 1.1** (root
   `LICENSE`, README badge, `docs/legal/terms-and-conditions.md`). BSL 1.1 only
   *converts* to Apache-2.0 four years after each version's publication; only
   v3.0.10-and-earlier are Apache today. Crucially, **BSL 1.1 is not OSI-approved,
   so "open source" is itself the misrepresentation** — not merely the word
   "Apache." Sweep all marketing surfaces to the accurate descriptor and add a CI
   guard so the claim can't silently regress.

2. **KISS homepage declutter.** Apply the UX lead's documented KISS principle
   (`plugins/soleur/agents/product/design/ux-design-lead.md:45` — "fewer elements,
   not more; every element must earn its place; cut duplicate affordances; when two
   layouts satisfy the brief, ship the simpler one") to `index.njk` at moderate
   aggressiveness: cut duplicate CTAs and the repeated final headline, compress
   overlapping prose, while preserving the AEO/SEO structures.

## Why This Approach

- **Two-track, one branch** (CTO recommendation): the license fix is a low-risk
  mechanical text sweep and is the legally-urgent half; the declutter edits
  `index.njk` layout and can shift above-fold selectors that trip the critical-CSS
  screenshot gate. Keeping them as separate commits means a gate failure on the
  declutter never blocks the legal cure.
- **"Source-available (BSL 1.1)" with conversion clause**: matches the canonical
  `LICENSE`/T&C, avoids the OSI-definition misrepresentation, and the "converts to
  Apache-2.0 after 4 years" clause gives honest good-faith context rather than
  flattening to "not open source" (which would itself contradict the T&C).
- **Moderate declutter**: removes the genuinely redundant elements the KISS bar
  flags while keeping the FAQ / Compare / stats blocks that look redundant but earn
  their place for AEO and internal-link equity.

## Key Decisions

| Decision | Choice | Source |
|---|---|---|
| Packaging | Two-track, one branch (license commit shippable alone) | User + CTO |
| License phrasing | "Source-available under BSL 1.1 — converts to Apache-2.0 four years after each release" | User + CLO |
| Declutter aggressiveness | Moderate — leaders' full cut/merge list | User + CMO |
| Correction scope | All 14 marketing files (P0 meta+JSON-LD, P1 blog/compare/FAQ twins); leave 3 legal `.md` untouched | CTO inventory |
| Regression guard | Add CI grep guard failing on "Apache-2.0"/"open source" in `plugins/soleur/docs/` marketing surfaces | CLO + CTO |
| AEO/SEO traps to KEEP | FAQ block (FAQPage JSON-LD), Compare section (promoted from FAQ per #3996), stats strip | CMO |
| Visual design | ux-design-lead `.pen` wireframe for decluttered `index.njk` (Phase 3.55) | Workflow gate |

### Declutter cut/merge list (moderate)

- **CUT** the duplicate mid-page CTA (`index.njk` ~L108, `landing-cta-mid`) — pure repeat of hero/final waitlist button.
- **MERGE** hero's 3 stacked CTAs → inline waitlist form (primary) + one "try open-source" link; drop the standalone "See Pricing" button and the compare anchor (section still reachable by scroll/nav).
- **TRIM** final-CTA headline (~L278) that repeats the hero H1 → replace H2 with a closing/urgency line, keep the CTA itself.
- **COMPRESS** the "This Is the Way" prose where it re-explains memory/compounding-KB already covered by the Compare section.

### License sweep file list (CTO inventory — 14 files)

Includes (load-bearing): `_includes/page-freshness.njk:20,22`, `_includes/base.njk:104,109`.
Pages: `index.njk:197,253`, `pages/pricing.njk:303,355`, `pages/about.njk:82,126`,
`pages/getting-started.njk:36`, `pages/community.njk:47`,
`pages/compare-soleur-vs-cursor.njk:32,83`, `pages/compare-soleur-vs-devin.njk:36,87`.
Blog: `blog/2026-03-16-soleur-vs-anthropic-cowork.md` (incl. comparison table + FAQ JSON-LD twin),
`blog/2026-03-17-soleur-vs-notion-custom-agents.md`, `blog/2026-03-26-soleur-vs-polsia.md`.
**Do NOT touch** the canonical legal `.md` (`docs/legal/*`) — already correct.

## User-Brand Impact

- **Artifact:** the present-tense "Apache-2.0 open source" claim rendered site-wide
  (meta summary, JSON-LD, comparison tables, FAQ rich snippets).
- **Vector:** a single visitor reads the claim, relies on it to fork or self-host
  Soleur under Apache-2.0 freedoms (e.g. standing up a competing hosted service),
  then discovers the actual license is BSL 1.1 — a license-reliance trust breach
  with legal exposure. The misrepresentation also propagates into AI/search answers
  via the JSON-LD, so the reach is larger than the homepage alone.
- **Threshold:** single-user incident. One person acting on the false claim is the
  brand-survival floor; the correction must be exhaustive (a half-corrected site
  that still says "Apache-2.0" in a comparison table or rich snippet is still a live
  misrepresentation).

## Open Questions

- Exact form of the CI grep guard: a new vitest case vs. a shell guard in an
  existing docs CI step. (Deferred to plan/implementation — TR, not a WHAT.)
- Whether the conversion clause appears in the terse hero badge or only in
  meta/FAQ where there's room. (Wireframe will settle placement.)

## Domain Assessments

**Assessed:** Legal, Marketing, Engineering (Product/UX via ux-design-lead at Phase 3.55)

### Legal (CLO)

**Summary:** BSL 1.1 is not OSI-approved, so "open source" — not just "Apache-2.0" —
is the actionable misrepresentation. Correct to "source-available (BSL 1.1, converts
to Apache-2.0 after 4 yrs)." Homepage+meta correction is necessary but not sufficient;
comparison tables and FAQ JSON-LD still mislead and rank in search/AI answers, so full
cure requires the P1 sweep. Canonical `docs/legal/*` is already correct; consider a
regression guard since the consistency test does not cover marketing prose.

### Marketing (CMO)

**Summary:** Moderate declutter — cut the duplicate mid-page CTA (safest), collapse
hero's 3 CTAs to form + 1 link, fix the repeated final headline, compress prose
overlap. Keep FAQ (FAQPage JSON-LD for AEO), the Compare section (promoted from FAQ
for AEO per #3996), and the stats strip (internal-link equity) — these look redundant
but earn their place. Waitlist form is the confirmed primary conversion action.

### Engineering (CTO)

**Summary:** MEDIUM risk, no infra/data impact. License claims live in 14 non-centralized
files — a duplicated sweep, partial edit = self-contradicting site; mind the JSON-LD
`"text"` twins mirroring every FAQ answer. The declutter can move above-fold selectors
and trip the critical-CSS screenshot gate, so keep it as a separable commit and re-inline
any newly-above-fold selectors into `base.njk`. Avoid a blanket find/replace that would
contradict the T&C's "converts to Apache-2.0 after 4 years" language.
