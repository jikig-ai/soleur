# Feature: Getting Started Page — Cloud-Primary Rewrite

Brainstorm: [2026-04-19-getting-started-cloud-primary-brainstorm.md](../../brainstorms/2026-04-19-getting-started-cloud-primary-brainstorm.md)
Issue: [#1446](https://github.com/jikig-ai/soleur/issues/1446)
Milestone: Pre-Phase 4 Marketing Gate (M5)

## Problem Statement

`plugins/soleur/docs/pages/getting-started.njk` currently presents a "Choose your path" hero with two equal-weight cards: cloud platform ("COMING SOON" / waitlist) and self-hosted ("AVAILABLE NOW" / install instructions). The CLI card carries all substantive content while the cloud card is a shell.

This contradicts the M1 brand-guide update (#1004) and M2 homepage update (#1129) which both positioned the cloud platform as the primary path. With Phase 4 founder recruitment gated on the marketing positioning fix, this page is the loudest remaining inconsistency on the site and blocks M5.

## Goals

- Flip visual hierarchy so the cloud platform is the primary path on the Getting Started page.
- Preserve the open-source CLI path as a fully documented secondary surface on the same page (not hidden, not demoted to a separate page).
- Provide a sales-motion escape hatch for non-Claude-Code founders in the recruitment target (≥3 of 10 per Phase 4 plan) — waitlist is a black box for them.
- Keep CC-native developers engaged — the CLI install path must remain visible from the first screen so CC users don't bounce assuming the product is gated.
- Align sitewide nav and footer with the new primary CTA so the funnel is coherent across all surfaces.
- Honor brand-guide constraints — no "plugin" framing in marketing copy; memory-first positioning; delivery-agnostic voice.

## Non-Goals

- Opening self-serve cloud signup (`app.soleur.ai/signup`). Stripe live mode and multi-user readiness gates are not passed yet; waitlist remains the canonical acquisition path for this release.
- Changes to the `pricing/` waitlist form markup, action URL, or Buttondown integration. `pricing/#waitlist` remains the single canonical form.
- Homepage (`index.njk`) edits. M2 (#1129) is the homepage change, already shipped.
- A standalone `/waitlist/` page or an inline email form on Getting Started. Single form on `pricing/`.
- A standalone `/self-hosted/` page. The CLI section stays on Getting Started.
- Copywriter-authored A/B persona-split hero variants. Deferred — v1 uses the brand-guide general-audience register as default.
- Cal.com integration for the "book intro with founder" link. v1 uses a mailto; Cal.com upgrade is tracked as a follow-up.
- Opening or modifying the `/vision/` page. Hero may link to it; it is not edited.

## Functional Requirements

### FR1: Cloud-primary hero

The Getting Started hero replaces the current "Choose your path" two-card layout with a single cloud-primary hero that carries:

- An H1 rewritten in delivery-agnostic brand voice (tool-agnostic register). Candidate: "Your AI company. Always on, always remembering."
- A subtitle leading with the memory-first outcome, not "cloud" as a delivery mode. Candidate subtitle draws from brand-guide memory-first variant.
- A **primary CTA** labelled **"Reserve access"** linking to `pricing/#waitlist`.
- A **secondary CTA** labelled **"Install CLI (open source)"** as a pill/anchor link to `#self-hosted` on the same page.
- A **proof-of-momentum line** — "Shipping weekly" — linking to `/changelog/` (or `/vision/` if changelog is not the right signal).
- A **founder-intro link** reading approximately "Founding cohort closing at 10 — book intro →" pointing to `mailto:ops@jikigai.com?subject=Soleur%20founding%20cohort%20intro`.

### FR2: "Run it yourself" section (condensed CLI)

The current self-hosted section is renamed and condensed:

- H2: **"Run it yourself"** with a subhead **"Open source. Install in Claude Code."**
- The section keeps its existing `id="self-hosted"` anchor so external links do not break.
- Install commands remain (`claude plugin marketplace add jikig-ai/soleur` and `claude plugin install soleur`).
- The "Existing project / Starting fresh" callout remains.
- The full workflow walkthrough (brainstorm → plan → work → review → compound) stays but may be visually compressed — keep the commands list, remove redundant prose.
- "Commands" and "Example Workflows" and "Learn More" subsections remain.

### FR3: FAQ rewrite

- First FAQ item leads with cloud path ("How do I get started?" or equivalent) answering the waitlist flow first, CLI flow second.
- Add a new FAQ item: "Why a waitlist?" explaining the Pre-Phase 4 posture (founding cohort, shipping weekly, access opens as infrastructure matures). Converts waitlist friction into a trust signal.
- Existing CLI-specific FAQs (Windows/Linux/macOS, `/soleur:go` vs individual skills, `/soleur:sync`) move below cloud-path FAQs.
- The "How much does Soleur cost?" FAQ stays but leads with cloud pricing reference to `pricing/`, CLI cost second.
- FAQ JSON-LD at the bottom of the file regenerated so structured data matches visible copy exactly.

### FR4: Sitewide nav "Reserve access" CTA

- `plugins/soleur/docs/_data/site.json` gains a new field (e.g., `"primaryCta": { "label": "Reserve access", "url": "pricing/#waitlist" }`) or the nav array grows a flagged primary item.
- `plugins/soleur/docs/_includes/base.njk` renders that field as a right-aligned accent-color button visible on every page.
- Button is hidden / inlined appropriately at mobile breakpoints so it does not crash the hamburger menu.
- Existing "Get Started" nav item stays.

### FR5: Footer alignment

- Footer Product column gains an entry labelled **"Hosted version (coming soon)"** pointing to `pricing/#waitlist`.
- The existing "Get Started" / CLI-related footer entries are retained — do not demote or remove them (CLI remains an equal footer citizen).

### FR6: Brand-voice compliance

- No use of the word "plugin" in hero copy, nav, footer, FAQ question wording, or FAQ answers — except inside literal CLI commands (``claude plugin install``) and inline technical install instructions in the "Run it yourself" section, per brand-guide exception.
- No "simply" or "just" in any new copy.
- No "assistant" or "copilot".
- No "terminal-first" or "CLI-native" as positioning advantages (delivery-agnostic voice per brand-guide 2026-03-22 revision).

## Technical Requirements

### TR1: Permalink and anchor preservation

- Page permalink stays `getting-started/`.
- The `id="self-hosted"` anchor on the CLI section must be preserved — external docs, community posts, and blog references may link to `getting-started/#self-hosted`.

### TR2: FAQ JSON-LD fidelity

- The `<script type="application/ld+json">` FAQ block at the bottom of `getting-started.njk` must mirror the visible `<details>` FAQ copy verbatim (Google validates the match and flags mismatches in Search Console).
- Question count and ordering in the JSON-LD must match the visible ordering.

### TR3: Accessibility

- The primary "Reserve access" button in the nav must have a discernible accessible name, a focus-visible state, and meet WCAG AA contrast against the nav background.
- Hero CTAs (primary + secondary + founder-intro link) must be keyboard-reachable in a logical tab order: primary → secondary → founder-intro → momentum link.
- The mailto link must include a pre-filled subject to preserve intent signal.

### TR4: Metadata

- Update page `description` frontmatter to remove any "plugin"-framed wording and lead with the memory-first positioning. Keep length within ~155 chars for SERP display.
- Do not change `title` field format — keep "Getting Started with Soleur" for stable SEO.

### TR5: Build and lint

- Run `npx markdownlint-cli2 --fix` on any changed `.md` files (brainstorm, spec).
- Run the Eleventy docs build locally and verify the page renders, the FAQ JSON-LD validates, and the nav button appears on every page.
- Run the SEO/AEO audit skill on the updated page if the copy changes materially.

### TR6: Open-source signal preservation (M11)

- The "Run it yourself" section must explicitly contain the words "open source" in either the heading/subhead or the first paragraph, so the M11 differentiator (#1134) does not regress on this page.
- Confirm the CLI footer entries still surface the OSS path.

## Acceptance Criteria

1. Visiting `/getting-started/` shows a single cloud-primary hero with "Reserve access" as the primary CTA and "Install CLI (open source)" as the secondary CTA.
2. A "Founding cohort closing at 10 — book intro" link is present near the hero CTAs and opens a mail client with a pre-filled subject.
3. A "Shipping weekly" proof-of-momentum line is present near the hero and links to `/changelog/` (or `/vision/`).
4. The CLI section titled "Run it yourself" is present on the same page with `id="self-hosted"`, contains the two install commands, and explicitly uses the words "open source".
5. The FAQ JSON-LD structured data matches the visible FAQ copy and passes Google's Rich Results validation.
6. A right-aligned "Reserve access" button appears in the sitewide nav on every page and is keyboard-accessible.
7. Footer Product column contains "Hosted version (coming soon)" linking to `pricing/#waitlist`; existing CLI entries still present.
8. The page source contains no marketing-voice occurrences of the word "plugin" — only inside literal `claude plugin install …` CLI commands.
9. External links to `getting-started/#self-hosted` still resolve.
10. Eleventy build succeeds and all existing site pages still render.

## Deferred / Follow-up

| Item | Why deferred | Re-evaluation |
|------|--------------|---------------|
| Replace founder-intro mailto with a Cal.com link | Cal.com account not provisioned; mailto ships today | When Cal.com is set up for founder scheduling |
| Copywriter-authored 2-variant hero copy (CC-native vs tool-agnostic register) | Brainstorm captures general-register defaults; A/B requires analytics plumbing | Before Phase 4 recruitment scales past 10 founders |
