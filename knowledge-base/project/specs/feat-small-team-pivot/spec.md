# Feature: Small-Team Expansion — Validation Phase

## Problem Statement

A 10-person prospect (CPO, designer, 3 SWEs, 2 SREs + others) has signaled demand for a Soleur-shaped product for their team. Soleur's validated ICP today is solo founders. We need to determine whether this is N=1 noise or a real second segment, and gather the data needed to commit (or kill) a parallel team-tier track — *before* spending engineering capacity on the foundational work (workspace-keyed RLS, customer DPA, team tier rename, `/teams` page).

## Goals

- Convert N=1 prospect signal into a structured commit-or-kill decision
- Ship the cheap unblocks that help both ICPs regardless of decision (sub-processor page, Trust Center stub)
- Capture and surface the cross-domain assessments so the next planning cycle has full context
- Avoid premature engineering investment in workspace-keyed RLS / DPA / tier rename until validation gate fires

## Non-Goals

- Building any team-tier feature (multi-user workspaces, RBAC, audit log) in this phase
- Renaming the Scale tier to Team
- Drafting a customer-facing DPA or MSA in this phase
- Launching `/teams` landing page or any team-segment marketing
- Outbound to YC/Pioneer cohorts or any team-segment lead generation
- Any homepage change
- SOC 2 work
- SSO / SAML / SCIM at any tier
- Per-domain RBAC ACLs

## Functional Requirements

### FR1: Prospect product-shape question

Send the active prospect a short message asking whether each of their 10 people would have their own Soleur login, or whether the founder/CPO would drive Soleur with the team looped in for review on specific tasks. The answer determines whether the foundational engineering surface is ~1-2 weeks (workspace-keyed RLS) or ~2-3 days (review-gate fanout extension).

### FR2: Inbound demand audit

Audit the last 90 days of inbound across Discord, GitHub issues, support email, and waitlist signups for team-shaped requests (any inquiry where the asker references "we," "our team," "my team," or names other team members). Output: count, summary table of requests with role of asker, dates.

### FR3: Solo-prospect coordination interview

Re-interview 3-5 existing solo prospects with one question: "do you have a lawyer / designer / accountant / advisor that you'd want Soleur to coordinate with on specific tasks?" Capture answers verbatim. Output: structured note in `knowledge-base/product/business-validation.md`.

### FR4: Sub-processor list page

Public markdown page at `/legal/sub-processors` listing Anthropic, Supabase (eu-west-1), Hetzner (hel1), Cloudflare, Stripe, Resend, Sentry, Vercel — with purpose, region, transfer mechanism. Add a 30-day notification commitment statement. Cross-link from Privacy Policy and from a future Trust Center page.

### FR5: Trust Center stub

Single-page `/trust` listing: security overview (encryption at rest/in transit), sub-processor list link, EU data residency statement, "no incidents to date" attestation, contact for security questions. No SOC 2 claim, no fabricated certifications.

### FR6: Decision gate document

Update `knowledge-base/product/business-validation.md` with the validation results. Apply the decision gate from the brainstorm (multi-user prospect commit OR ≥3 inbound team requests OR 3+ paying solos + 1 paying team). Output: explicit "commit" / "kill" / "wait, re-evaluate in 30 days" recommendation with rationale.

## Technical Requirements

### TR1: Sub-processor page in existing legal docs surface

Place under `docs/legal/` (or wherever `legal/` docs are routed) following the existing legal page pattern. Render via the existing Eleventy / Next.js docs pipeline — no new infrastructure.

### TR2: Trust Center page placement

Single page, no new section nav. Link from footer "Trust" link. Mobile-responsive.

### TR3: No engineering work on workspace-keyed RLS, BYOK rotation, audit log, RBAC, or `/workspaces/` filesystem layout in this phase

These are explicitly deferred. Spec gate is the validation outcome, not implementation readiness.

### TR4: No customer-facing DPA / MSA drafting in this phase

Sub-processor page only; full DPA waits for the validation outcome.

## Acceptance Criteria

- Prospect responded to the product-shape question (or 7-day timeout reached and answer is "unknown")
- Inbound audit complete with count and summary
- 3-5 solo prospects re-interviewed with verbatim answers captured
- Sub-processor page live in production
- Trust Center stub live in production
- Decision gate evaluated and recorded in `business-validation.md` with explicit commit / kill / wait recommendation

## Decision Gate Inputs (for the planning phase that follows)

If gate fires "commit":

- `/soleur:plan` for: workspace-keyed RLS migration + BYOK key rotation + customer DPA + Scale → Team rename + `/teams` waitlist page + ROI one-pager
- Estimated 4-8 weeks engineering + 1-2 weeks legal in parallel

If gate fires "kill":

- Park `/teams` ambition; the sub-processor + Trust Center work still ships (they help solo deals too)
- Brainstorm + spec archived to `knowledge-base/project/brainstorms/archive/` and `knowledge-base/project/specs/archive/`

If gate fires "wait":

- Re-evaluate in 30 days with fresh inbound audit
- No additional engineering work scheduled

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-04-27-small-team-expansion-brainstorm.md`
- Roadmap: `knowledge-base/product/roadmap.md`
- Business validation: `knowledge-base/product/business-validation.md`
- Pricing strategy: `knowledge-base/product/pricing-strategy.md`
- Compliance posture: `knowledge-base/legal/compliance-posture.md`
- Cost model: `knowledge-base/finance/cost-model.md`
