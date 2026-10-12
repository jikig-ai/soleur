# Brainstorm: Dashboard Agent Identity and Team Customization

**Date:** 2026-04-13
**Branch:** `feat-dashboard-agent-identity`
**Status:** Complete
**Related:** #1871 (named domain leaders — naming implemented, avatar deferred)

## What We're Building

Three improvements to the Command Center dashboard that give domain leaders distinct visual identities and let users personalize their AI team:

1. **Domain-specific badges** — Replace the generic "Soleur" badge on conversations and messages with per-leader badges (domain icons as defaults). Soleur badge reserved for system notifications and unrouted messages only.
2. **Remove dead profile icon** — The profile icon in the top-right corner does nothing. Remove it.
3. **Configurable team member icons** — Extend the existing team settings page (where users already rename leaders) to also support icon customization: a curated icon library plus custom image upload. Icons stored git-committed in `knowledge-base/`.
4. **Per-message leader attribution** — Each message in a conversation shows which domain leader sent it via badge, preparing for multi-leader threads (tag-and-route, roadmap item 1.11).

### Scope

- Extend `domain-leaders.ts` type with `icon`, `color`, and `defaultIcon` fields
- Add `leader_id` field to message data model for per-message attribution
- Render domain-specific badges on: conversation list items, chat message bubbles, leader cards
- Restrict Soleur "S" badge to system/platform messages and unrouted messages
- Remove non-functional profile icon from top-right corner
- Curated icon library (domain-appropriate defaults per leader)
- Custom image upload on existing team settings page
- Git-committed icon storage in `knowledge-base/`

### Out of Scope

- Personalities (deferred to Post-MVP, tracked in #1879)
- Custom specialist agent icons (only domain leaders)
- Custom titles (users can rename but not retitle — "CTO" title stays fixed)

## Why This Approach

### Approach A: Two PRs on single feature branch (Selected)

- **PR 1:** Data model + default badges — extend leader types, add per-message attribution, render domain icons everywhere, remove dead profile icon, restrict Soleur badge
- **PR 2:** Customization UI — curated library + upload on existing team settings page, git-committed storage

**Why selected over alternatives:**

- **vs. Single PR (B):** Large PR is harder to review. PR 1 delivers immediate visual identity fix. PR 2 adds customization without blocking the badge fix.
- **vs. Three incremental PRs (C):** Too granular — badge rendering is useless without the data model change. Two PRs is the right split.

### Rejected Approaches

| Approach | Why Rejected |
|----------|-------------|
| B: Single PR, everything at once | Large scope in one review. Badge fix blocked on customization UI completion. |
| C: Three incremental PRs | Over-split. Data model PR alone delivers nothing visible. |
| Defaults first, customization later | User wants the full "your team" vision shipped now. |

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Full customization now, not defaults-first | User wants the complete team personalization experience. Zero external users means no risk of half-shipped perception. |
| 2 | Name + icon customization per leader | Names already exist (#1871). Adding icons. Titles stay fixed to preserve domain routing clarity. |
| 3 | Both curated library + upload | Library ensures brand-consistent defaults. Upload enables maximum personalization. |
| 4 | Git-committed icon storage | Icons in `knowledge-base/` — users get everything with `git clone`. Consistent with data portability principle. Binary assets have different characteristics from the Supabase-stored names (#1871). |
| 5 | Per-message badges, not per-conversation | Future-proofs for multi-leader threads (tag-and-route 1.11). Each message shows which leader responded. Requires `leader_id` on message model. |
| 6 | Domain icons as defaults (not initials) | Abstract icons per domain (megaphone for CMO, gear for CTO, shield for CLO, chart for CFO). More distinctive than colored initials. |
| 7 | Soleur badge = system + unrouted only | Platform messages (onboarding, errors, status updates) and unrouted messages during triage show Soleur "S". Once routed to a leader, leader badge takes over. |
| 8 | Remove dead profile icon | Non-functional UI erodes trust. Remove until it has purpose. |
| 9 | Extend existing team settings page | Settings page already has leader rename UI (#1871). Add icon picker to the same surface. No new routes needed. |

## Open Questions

| # | Question | Context |
|---|----------|---------|
| 1 | Icon sizing and format constraints | What dimensions? Max file size? Accepted formats (PNG, SVG, WebP)? Need to prevent oversized uploads from bloating the git repo. |
| 2 | Dark mode rendering | Brand uses dark surfaces (neutral-900). Icons need to look good on dark backgrounds. Should we enforce transparency or provide a circular mask? |
| 3 | Curated library contents | How many default icons per domain? Just one per leader, or a selection to choose from? Who designs them — ux-design-lead or gemini-imagegen? |
| 4 | Storage path within knowledge-base | `knowledge-base/config/team-icons/`? `knowledge-base/project/team/icons/`? Needs to align with existing KB structure. |
| 5 | Supabase names + git icons: sync mechanism | Names are in Supabase (#1871), icons in git. How does the web platform read git-committed icons? At build time? Via KB API? |

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Items 1+2 are low-risk quick fixes. Item 3 (configurable icons) is medium scope — requires design decisions on upload flow, storage, sizing, and dark mode rendering. Recommended shipping defaults first (overridden by user preference for full customization). Key concern: multi-leader thread data model must be per-message, not per-conversation, to avoid rebuild when tag-and-route ships. Storage should prefer git-committed for data portability. Roadmap staleness flagged (#1878).

### Marketing (CMO)

**Summary:** Domain badges reinforce the CaaS value prop in every conversation — "free marketing" through screenshot-ready social proof. Configurable icons trigger the endowment effect (psychological ownership), increasing switching costs. Risk: user-uploaded icons could clash with Solar Forge aesthetic without constraints. Recommended delegating layout/badge design to ux-design-lead or conversion-optimizer. Per-domain colors in mockups (green for CM, purple for CC) are not documented in brand guide — may need brand-architect formalization.

## Capability Gaps

None identified. All needed specialists are available (ux-design-lead for badge design, gemini-imagegen for default icon generation, brand-architect for color palette formalization).
