---
date: 2026-04-27
status: not-committed
decision: deferred-pending-validation
related:
  - knowledge-base/product/roadmap.md
  - knowledge-base/product/business-validation.md
  - knowledge-base/product/pricing-strategy.md
  - knowledge-base/finance/cost-model.md
  - knowledge-base/legal/compliance-posture.md
  - knowledge-base/marketing/brand-guide.md
---

# Small-Team Expansion Brainstorm

## What We're Considering

Whether to expand Soleur's ICP from solo founders to include small startup teams (5-15 people), as a parallel ICP — not a pivot. Triggered by an inbound prospect: a 10-person company (CPO, designer, 3 SWEs, 2 SREs + others) who said they want Soleur but need to "keep some expertise where it's needed."

## Decision Status: NOT COMMITTED

Direction is deferred pending validation data. This brainstorm captures the cross-domain assessment and the data-gathering plan that precedes commitment. No engineering work is unlocked by this brainstorm — only validation and cheap unblocks.

## Why Not Commit Now

- N=1 prospect signal — not yet a segment
- Two material unknowns about the prospect's intent (login model and pricing tolerance) shift the engineering surface by ~1-2 weeks each
- Phase 4 of the roadmap has not yet recruited paying solo founders; committing engineering capacity to a parallel ICP before the validated wedge has traction is a focus risk

## Key Reframe (and what corrected it)

The CPO's initial assessment proposed reframing the prospect as a solo founder describing how they buy expertise (lawyer/designer on retainer), arguing that this was a solo-ICP feature, not a second segment. **This reframe was invalidated** by the founder's clarification: the prospect has a real cross-functional team (CPO, designer, 3 SWEs, 2 SREs as named employees). This is a genuine team buyer, not a solo signal.

The CPO's other recommendations (validation-gating, kill criteria, the cheapest-validation-path discipline) remain load-bearing.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Initial reframe (solo ICP feature only) invalidated by clarification that the prospect has a real employed cross-functional team. Validation-gate discipline still applies: don't commit team-tier engineering until inbound team-shaped requests confirm this isn't N=1, and existing solo wedge has traction. ICP fragmentation risk is real — "5-15 person team" is the cleanest segment line; below that overlaps solo, above it requires admin/SSO/MSA work that is out of scope.

### Marketing (CMO)

**Summary:** Keep one brand. Recommended hook: *"Keep your experts. Multiply their output."* Site architecture: hold homepage on solo until 5+ paying team logos exist; add a single `/teams` parallel landing page only when team product is real. No parallel SEO/AEO track yet. Channel additions: LinkedIn long-form, founder-led outbound to YC/Pioneer/SPC cohorts. Risk firewall: every team-segment asset must include the phrase "the same AI organization" so positioning reads as audience extension, not new product.

### Sales (CRO)

**Summary:** Hybrid PLG-led, founder-led for first 5-10 deals. Self-serve signup + team upgrade path; team-tier conversions route to a human (founder initially). **Inbound only** until product is multi-user-ready — outbound now creates expectations the product can't meet → churn poison. Capture team interest via waitlist. Pricing motion: flat team tier with stated seat band, not per-seat. Collateral gaps: ROI one-pager (agent cost vs. fractional specialist payroll), security one-pager, sample DPA, design partner program (3 free teams for case study).

### Finance (CFO)

**Summary:** Recommended pricing model: rename existing $499 Scale tier → "Team," 10 seats included + $29/seat overage. ARPU shift: solo $49 → team $499-849 (10-17x). Cost shape ~flat under BYOK; binding constraint is founder support hours, not COGS. Single pricing page with tier toggle (no dual page). **Kill criterion: <2 paying Team accounts in 2 quarters after gate fires → revert.** Defer SSO to Enterprise tier only. Carve from existing budget; no new line items pre-revenue.

### Engineering (CTO)

**Summary:** Workspace-keyed RLS migration is foundational and **not feature-flag-able** (Postgres evaluates RLS regardless of flags). Estimate: 1-2 weeks including dual-write/backfill. Top 3 single-tenant decisions blocking teams: user-keyed RLS policies (`001_initial_schema.sql`), user-keyed BYOK key derivation (`server/byok.ts`), `/workspaces/<userId>` filesystem layout (`server/workspace.ts`, `agent-runner.ts`). The "humans-in-the-loop expertise" mechanic is ~2-3 days extending the existing `review-gate.ts`. Audit log: ~3 days as a new append-only table fed from `canUseTool` hook. RBAC MVP: 4 roles (owner/admin/member/viewer) at workspace grain only — defer per-domain ACLs to Enterprise.

### Legal (CLO)

**Summary:** Top deal-blocker is the missing customer-facing DPA (vendor DPAs are in place; nothing to offer customers). Cheapest unblock: public sub-processor page (hours of work). Trust Center over SOC 2 — days vs. 9-12 months and unblocks 80% of small-team buyers. EU data residency (Hetzner hel1 + Supabase eu-west-1) is a real differentiator already shipped. Sequencing: legal track ships parallel and slightly ahead of engineering. Document gaps in priority order: DPA → sub-processor list → Trust Center → T&C/Privacy/AUP team-account revisions → MSA template → SIG-Lite/CAIQ-Lite responses. Fold open issue #736 (T&C contradictions) into the team T&C pass.

## Capability Gaps

- **Identity / RBAC ownership**: no current domain agent owns "auth, sessions, SSO, RBAC" cross-cutting concerns. Currently distributed between CTO and engineering. Recommend either expanding CTO scope or designating a security/identity reviewer for team-tier work. (Flagged by CTO.)

## Open Data Questions (drives commit decision)

1. **Prospect product shape**: does each of the 10 get a Soleur login, or does the founder/CPO drive Soleur with the team looped in for review on specific tasks? — *decision-shaping; differs by ~1-2 weeks of engineering*
2. **Prospect pricing tolerance**: would they pay $499/mo flat? Higher? What's their reference price (their current tooling stack)?
3. **Procurement timing**: does the prospect's team require DPA at signup, or is "we'll send one within 30 days" acceptable? Does data residency matter to them?
4. **Inbound demand scale**: how many team-shaped requests have come in via existing channels in the last 30/60/90 days? — *audits whether N=1 generalizes*
5. **Solo-prospect coordination signal**: of existing solo prospects, how many have a "team" they'd want Soleur to coordinate with? — *cheapest possible test of the boundary between solo-feature and team-tier framing*

## Validation Plan

The cheapest path to a commit-or-kill decision before any team-tier engineering is started:

| # | Action | Owner | Effort | Decision input |
|---|---|---|---|---|
| 1 | Send prospect 3 questions (product shape, pricing tolerance, DPA timing) | Founder | 1 message | Shape & cost |
| 2 | Audit existing inbound (Discord, GitHub issues, email) for team-shaped signals — last 90 days | Founder | ~1 hour | Demand scale |
| 3 | Re-interview 3-5 solo prospects: "do you have a lawyer/designer/accountant you'd want Soleur to coordinate with?" | Founder | ~3 hours | Boundary clarity |
| 4 | Ship sub-processor page + Trust Center stub (cheap; unblocks future regardless of team-tier decision; helps solo deals too) | legal-document-generator | ~hours | Removes a deal-blocker for both ICPs |

Step 4 is the only engineering/content work this brainstorm authorizes. Steps 1-3 are pure data gathering.

## Decision Gate (commit criteria)

Direction = **Full team-tier expansion** (foundational RLS migration + DPA + tier rename + `/teams` page) iff:

- Prospect product shape is "multi-user" AND prospect commits to a paid pilot or signs an LOI, OR
- Inbound team-shaped requests ≥3 in the last 90 days from non-solo askers, OR
- 3+ paying solo founders are live AND ≥1 paying team prospect exists

Until then: only the cheap solo-friendly unblocks (sub-processor page, Trust Center, optional review-gate extension framed as a solo feature) ship.

## Hard Kill Criterion (post-commit)

If team-tier expansion is committed and <2 paying Team accounts close in 2 quarters from gate firing, revert: park `/teams` page, leave RLS migration in place (it's also useful for future Enterprise), do not maintain team-segment marketing.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| ICP move | Expansion (parallel solo + team), not pivot | Solo wedge is the validated bet; teams as add-on de-risks |
| Direction commit timing | Deferred pending validation | N=1 signal; 5 cheap data points first |
| Branding | Single brand, single domain, single mission line update | Sub-brand fractures SEO and brand recall for no upside |
| Pricing model | Flat team tier with seat band + overage (rename Scale→Team) | Matches BYOK cost shape; predictable forecasting; soft expansion lever |
| Pricing page | Single page with tier toggle | Dual pages confuse buyers and split SEO |
| Sales motion | Hybrid PLG-led, inbound-only until multi-user product | Outbound now creates expectations the product can't meet |
| Tenancy migration | Workspace-keyed RLS — coordinated single change, not feature-flagged | RLS evaluates regardless of flags; flag-gating is unsafe |
| Humans-in-the-loop primitive | Extend existing `review-gate.ts` + workspace-level domain-expert assignments | ~2-3 days vs. weeks for a generalized framework |
| RBAC scope (team tier) | 4 roles at workspace grain (owner/admin/member/viewer) | Per-domain ACLs deferred to Enterprise |
| SSO scope | Deferred to Enterprise tier (25+ seats trigger) | 4-6 week build that doesn't matter at this segment |
| Legal sequencing | Ship sub-processor page + Trust Center now; DPA before first team deal | DPA is the deal-blocker; sub-processor page is hours |
| Outbound for team segment | Deferred until product is multi-user-ready | Expectation/product mismatch = churn poison |
| SOC 2 | Out of scope | 9-12 months, premature; Trust Center is 80% of buyer signal at <20% effort |

## Non-Goals

- Mid-market (15-50) or enterprise (50+) ICP — out of scope for this expansion track
- SSO/SAML/SCIM at the Team tier — Enterprise-only
- Per-domain RBAC ACLs (folder-level write permissions, etc.) — Enterprise-only
- Paid outbound for team segment — premature
- A second domain or sub-brand — single brand only
- SOC 2 audit — replaced by Trust Center for now
- New homepage for team audience — homepage stays solo until 5+ paying team logos
- Dual pricing pages

## Open Questions (post-validation, if commit fires)

- What's the expansion narrative from team-tier ($499) → Enterprise (custom)? Triggers? Anchor?
- How does the workspace-knowledge-base merge with the team's existing institutional knowledge (Notion/Confluence imports)? Out of scope for v1 but inevitable.
- Member-departure data handling: stays with workspace, but what about agent activity tied to that user (their conversations, their BYOK keys)? Need DPA + product flow.
- When does the first AE/SE hire become the right move? CFO's note: defer until 10+ Team accounts.

## Cross-Domain Dependencies (if direction commits)

| From | To | Dependency |
|---|---|---|
| CLO | CPO | Admin-acceptance UX at workspace creation (T&C version capture, entity name) |
| CLO | CTO | Admin export endpoint, member-departure data routing, deletion-propagation, audit log — required for DPA promises to be truthful |
| CLO | CMO | Trust Center placement on marketing site; positioning of EU data residency |
| CRO | CMO | Team-tier landing page copy and positioning |
| CRO | CFO | Deal-weighted pipeline forecast for Team tier |
| CRO | CPO | Multi-user product readiness gating outbound |
| CFO | COO | Add Supabase Team + CX43 triggers to expense ledger when Team tier ships |

## Out of Scope for This Brainstorm

- Specific RLS migration design — `/soleur:plan` work after gate fires
- Exact DPA wording — `legal-document-generator` after gate fires (or in step 4 if we ship sub-processor page now)
- Team tier price-point research — `pricing-strategist` after gate fires
- ROI one-pager content — `copywriter` after gate fires
