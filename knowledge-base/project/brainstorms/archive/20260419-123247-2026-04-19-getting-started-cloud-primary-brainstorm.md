---
title: Getting Started Page — Cloud-Primary Rewrite
date: 2026-04-19
topic: getting-started-cloud-primary
issue: "#1446"
milestone: Pre-Phase 4 Marketing Gate (M5)
status: brainstorm-complete
---

# Getting Started — Cloud-Primary Rewrite

## What We're Building

A rewrite of `plugins/soleur/docs/pages/getting-started.njk` and sitewide nav/footer so the cloud platform is the primary path and the CLI (open source) is a secondary path on the same page. Final Pre-Phase 4 Marketing Gate item (M5 of M1-M15) before founder recruitment opens.

**Scope:**

1. Replace the "Choose your path" two-equal-cards hero with a cloud-primary hero carrying a dual CTA: **"Reserve access"** (primary, → `pricing/#waitlist`) + **"Install CLI (open source)"** (secondary, anchor to CLI section below).
2. Add a **"Founding cohort closing at 10 — book intro"** link (mailto or Cal.com) as a scarcity + sales-motion signal for non-Claude-Code founders. Inline near the hero CTAs.
3. Demote the current self-hosted section to a single condensed **"Run it yourself"** section (heading + "Open source. Install in Claude Code." subhead) below the fold: install commands, `/soleur:go` one-liner, link to deeper docs. No "plugin" in headings — only in literal `claude plugin install` commands (brand-guide exception).
4. Rewrite the FAQ: lead with cloud-path answers, add a "Why a waitlist?" entry that converts friction into a trust signal, regenerate the FAQ JSON-LD.
5. Add a right-aligned **"Reserve access"** accent button to the sitewide nav (`plugins/soleur/docs/_data/site.json` + `_includes/base.njk`).
6. Add a **"Hosted version (coming soon)"** link under the Product column in the footer. CLI keeps an equal footer entry (per CPO: don't signal CLI as deprecated).
7. Add a proof-of-momentum signal near the hero — dated "Shipping weekly" line with a link to the public roadmap or changelog.

**Out of scope:**

- No changes to `pricing/` waitlist form markup/action — that's the canonical waitlist and stays as-is.
- No changes to homepage (`index.njk`) — M2 was done separately (#1129).
- No changes to the cloud signup flow itself (`app.soleur.ai/signup`). Signup stays live but is not promoted here — Phase 4 will flip when Stripe live mode and multi-user readiness gates pass.
- No `/vision/` page changes. The hero secondary link references it but does not modify it.

## Why This Approach

- **Brand guide (2026-03-22 validation review)** requires delivery-agnostic positioning. The current two-equal-cards layout frames "plugin vs cloud" as a choice; the new hero frames Soleur as one memory-first platform with two access modes. Leading subtitle copy draws from the "memory-first" variant the brand guide flagged as strongest across 4 personas.
- **M1 (#1004 brand guide) and M2 (#1129 homepage)** already flipped upstream positioning to cloud-primary. The Getting Started page is currently the loudest contradiction on the site ("AVAILABLE NOW" on CLI, "COMING SOON" on cloud, both equal weight). This PR closes the gap.
- **Phase 4 target is 10 founders (≥3 non-CC users)** — a sales motion, not a marketing funnel. Waitlist-only loses the non-CC target because the form is a black box with no human escape hatch. Adding the "book intro with founder" link gives the sales motion a surface without opening self-serve signup.
- **CC-native devs** — the CPO pushback was that burying CLI below the fold signals vaporware. The secondary "Install CLI (open source)" hero pill keeps the working path visible from the first screen while the primary CTA still steers visitors into the waitlist.
- **CMO pushback on "Join Waitlist"** — "Reserve access" centers the user (action verb, ownership), not the queue. "Run it yourself" frames the CLI as agency, not fallback. Both land in the brand voice (bold, forward-looking) without "simply/just/assistant" pitfalls.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Cloud is primary; CLI is secondary on the same page (no separate `/self-hosted/`). | Single source-of-truth page; avoids redirect/anchor churn; keeps OSS differentiator visible per M11. |
| D2 | Waitlist stays as the primary CTA destination — link to existing `pricing/#waitlist` form. Do not open self-serve cloud signup. | Stripe live mode and multi-user readiness gates not yet passed. Single waitlist form avoids analytics split and drift. |
| D3 | Primary CTA label: **"Reserve access"**. CLI heading: **"Run it yourself"** with subhead "Open source. Install in Claude Code." | CMO recommendation — user-centered verb, preserves OSS signal, avoids "plugin"/"Self-Hosted" cold framing. |
| D4 | Hero carries a **dual CTA** — primary "Reserve access" + secondary "Install CLI (open source)" pill anchored to the CLI section. | CPO recommendation — prevents CC-dev bounce that assumes the product is gated vaporware. |
| D5 | Add a **"Founding cohort closing at 10 — book intro"** link near the waitlist CTA. Destination: mailto `ops@jikigai.com` for v1 (founder-gated), swappable to a Cal.com link when set up. | CPO recommendation — non-CC founders need a human escape hatch. Mailto ships today with zero new services. |
| D6 | Proof-of-momentum line near hero: "Shipping weekly" with a link to `/changelog/` (dated) or `/vision/`. No testimonials (0 beta users). | Replaces absent social proof with roadmap transparency; makes the waitlist feel like a launch countdown. |
| D7 | Nav gets a right-aligned **"Reserve access"** accent button. Label matches hero CTA to avoid voice divergence. | User-chosen scope includes nav CTA alignment; single label across surfaces keeps the funnel coherent. |
| D8 | Footer label for the hosted entry: **"Hosted version (coming soon)"** — not "Cloud Platform (Waitlist)". CLI keeps an equal footer entry. | CPO flagged that "Waitlist" in footer signals CLI-deprecated; "Hosted (coming soon)" keeps hierarchy without demoting CLI. |
| D9 | FAQ rewrite: first FAQ leads with cloud path; existing CLI-specific answers move down; add a "Why a waitlist?" item. Regenerate FAQ JSON-LD. | FAQ JSON-LD must match visible copy (Google validates). Cloud-first framing consistent across visible and structured data. |
| D10 | "plugin" as a word stays only in literal CLI commands (`claude plugin install`) and in technical wording on the CLI section. No "plugin" in hero, nav, footer, or FAQ answers. | Brand-guide exception is narrow; everywhere else must use "platform" / "Soleur". |
| D11 | No new `/waitlist/` page, no inline email form on Getting Started. Single canonical form on `pricing/`. | Analytics coherence, maintenance simplicity. |
| D12 | Page keeps permalink `getting-started/` and the `#self-hosted` anchor. The CLI section is renamed "Run it yourself" but keeps `id="self-hosted"` to avoid breaking external links. | Anchor preservation — other pages/docs/community posts may link to `getting-started/#self-hosted`. |

## Open Questions

None blocking implementation. Two flag-raises for follow-up (tracked as deferred items below):

- Should we replace the mailto with a real Cal.com link before Phase 4 recruitment opens? Deferrable — v1 ships with mailto, upgrade when the Cal.com account is provisioned.
- Copywriter could produce 2-variant hero copy (CC-native vs tool-agnostic register) to A/B against the 3+ non-CC founder persona. Deferrable — v1 uses the tool-agnostic register (brand guide general-audience profile) as default.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Marketing (CMO)

**Summary:** Cloud-primary aligns with M1 brand guide and M2 homepage. Key corrections: lead with memory-first (outcome) rather than "cloud" (delivery), rename CTA to "Reserve access", rename CLI heading to "Run it yourself" with open-source subhead to preserve the M11 differentiator. Add a proof-of-momentum line so the waitlist reads as a launch countdown, not a parking lot. Waitlist-as-primary risk is real but mitigatable with momentum signals.

### Product (CPO)

**Summary:** Flagged the biggest structural risk — 10 founders is a sales motion, not a marketing funnel. Adopted: add a "book intro with founder" CTA alongside the waitlist to serve the ≥3 non-CC founder target; add a secondary "Install CLI (open source)" hero pill so CC-native devs don't bounce thinking the product is gated vaporware; keep CLI as an equal footer entry with "Hosted version (coming soon)" label to avoid signalling CLI deprecation. Recommended copywriter-authored persona-split hero variants — deferred to a follow-up issue.

## Capability Gaps

None. All recommended surfaces already exist (pricing waitlist form, changelog, vision page, site nav/footer data). The only external dependency is an optional Cal.com account for the founder-intro upgrade path, which mailto covers in v1.
