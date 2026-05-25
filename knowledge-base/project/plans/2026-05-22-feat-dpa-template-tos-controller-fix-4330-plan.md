---
title: Customer-facing DPA template (pre-draft) + ToS/DPD controllership clarification (#4330)
status: planned
issue: 4330
branch: feat-one-shot-4330-dpa-template-tos-controller-fix
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
requires_clo_signoff: true
requires_cpo_signoff: true
requires_cto_signoff: false
requires_adr: false
type: legal-scaffolding
classification: deferred-automation-artifact
deepened: 2026-05-22
---

# Plan — DPA Template Pre-Draft + Controllership Clarification (#4330)

## Enhancement Summary

**Deepened on:** 2026-05-22
**Sections enhanced:** Research Reconciliation (5 drifts → 5 corrections), Phase 4 (DPA §6/§9/§10 grounded in Vercel + Linear precedents), Phase 6 (TC_VERSION justification corrected — Tier 2 DOES require PATCH bump but only when ToS edited), AC8 (justification rewrite), AC14 (vitest invocation per `bunfig.toml` block), AC17 (broken learning cite replaced).

**Research agents used:** WebFetch (Vercel DPA, Linear DPA); WebSearch (GDPR Art. 28 best practices 2026, sub-processor notice windows, EDPB SCCs Module 2); live `gh` PR/issue verification (6 PRs); live file path + AGENTS rule-ID + learning-citation Glob verification; live `gh label list` verification (5 labels); `bunfig.toml` test-runner check.

### Key Improvements

1. **ToS cross-references corrected** — Plan §12 (Liability) now cites ToS §11.2 (Aggregate Liability Cap = EUR 100 or 12-month fees, whichever greater), not the imagined §13. Plan §14 (Governing Law) cites ToS §15.1+§15.2 (France + Paris courts), not §17.
2. **Sub-processor notice window grounded** — Vercel uses 5 days, Linear 15+10 days, EDPB best practice 30 days. Template adopts **30-day notice + 30-day objection window** (conservative, matches enterprise-procurement-team expectations; rationale documented in Phase 3.1).
3. **Schedule 2 (TOMs)** — Vercel ships 18 TOM categories as a discrete Annex II / SCCs annex. Plan now prescribes a **17-section TOM annex** as Schedule 4 (separate from Schedule 2 sub-processor list).
4. **Conflict-precedence ordering added** — Per Linear DPA §9: (1) SCCs > (2) DPA > (3) ToS > (4) other agreements. Codified as new DPA §14.7.
5. **AC8 justification corrected** — Tier 2 DOES require a PATCH bump per `tc-version-bump-policy.md:73-77`. The bump does NOT fire here because the SHA guardrail at `check-tc-document-sha.sh:112,187` is scoped to `docs/legal/terms-and-conditions.md` only; DPD has no version-bump coupling. AC8 now states this distinction explicitly.
6. **AC14 test invocation corrected** — `apps/web-platform/bunfig.toml` `[test] pathIgnorePatterns = ["**"]` blocks `bun test` entirely; AC14 now prescribes `./node_modules/.bin/vitest run apps/web-platform/test/legal-doc-consistency.test.ts`.
7. **Broken learning citation removed** — `2026-04-24-ops-remediation-pr-body-uses-ref-not-closes.md` does NOT exist on disk. Sharp Edge inline rationale now cites AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to` (the canonical source) plus the real existing learning `2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md`.

### New Considerations Discovered

- **Sub-processor list externalization** — Vercel hosts the list at `security.vercel.com`. Soleur has no such page. The DPA template's Schedule 2 is INLINE (snapshot at publish time) AND cross-references `knowledge-base/legal/compliance-posture.md` (Vendor DPA Status table) for the always-current state. Tracking issue stub recorded in Risks.
- **Linear's "essential sub-processor" carve-out** allows continued use even on customer objection. Adopting this clause protects the substrate sub-processors (Supabase, Hetzner, Cloudflare) which cannot be swapped on short notice. Codified as new DPA §6.4.
- **Vercel's "audit via SOC 2 report"** pattern — third-party audit reports satisfy Art. 28(3)(h) without granting in-office access. Soleur has no SOC 2 today; the template's §10 (Audit Rights) prescribes "operator-attested compliance posture in lieu of SOC 2 until obtained" with the explicit commitment to obtain SOC 2 within 24 months of first executed DPA.
- **EDPB Sub-Module attribution** — Schedule 3 SCCs MUST identify Module 2 (Controller-to-Processor) AND Module 3 (Processor-to-Sub-processor) for the customer's sub-processor flow-down. Both modules incorporated by reference.
- **DSAR assistance SLA** — Linear leaves it as "reasonable cooperation" with no timeline. Plan prescribes a **10-business-day operator SLA** consistent with the existing `/dashboard/settings/privacy` self-serve operator commitment; documented in Phase 4 step 1 + DPA §7.

Sources:
- [Vercel Data Processing Addendum](https://vercel.com/legal/dpa)
- [Linear DPA](https://linear.app/dpa)
- [GDPR Article 28 — gdpr-info.eu](https://gdpr-info.eu/art-28-gdpr/)
- [ICO Article 28 contract guidance](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/accountability-and-governance/contracts-and-liabilities-between-controllers-and-processors-multi/what-needs-to-be-included-in-the-contract/)
- [Buttondown DPA (in-vendor-stack precedent)](https://buttondown.com/legal/dpa)


## Overview

Issue #4330 asks for two things:

1. **Pre-draft a customer-facing Data Processing Agreement (DPA) template** at
   `knowledge-base/legal/data-processing-agreement-template.md` so it is ready
   to publish (move to `docs/legal/data-processing-agreement.md` + Eleventy
   mirror) when the first of three B2B trigger events fires:
   (a) first B2B prospect asks "Do you have a DPA?";
   (b) first paying customer organization invites their employees as
   Workspace Co-Members under `FLAG_TEAM_WORKSPACE_INVITE`;
   (c) first EU customer requests Standard Contractual Clauses for non-EU
   sub-processors.
2. **Fix the alleged ToS §3b vs DPD §2.1b "controller" contradiction.**

This plan ships **artifact only** — no production code changes, no ToS
version bump, no compliance-posture flip from "deferred" to "active." Per the
issue body: "This is a deferred-automation backlog item per
`wg-block-pr-ready-on-undeferred-operator-steps`. Re-evaluate when: any of
the three trigger events fires."

The plan REQUIRES a directional confirmation gate at /work time before
touching ToS §3b language (see Research Reconciliation below — the issue's
proposed fix would regress the deliberate controller-shift architecture
shipped in PR #4225/#4289/#4328).

## User-Brand Impact

`USER_BRAND_CRITICAL=true`. Threshold inherited from related #4289:
`single-user incident`.

**If this lands broken, the user experiences:** a prospective B2B customer
sees an incoherent legal posture — either (a) we say "Workspace Owner is
the controller" in ToS §3b but the DPA template says "Jikigai is processor
of the customer-controller's data" with no carve-out for the team-workspace
sub-case, producing contra-proferentem ambiguity an EU regulator can exploit;
or (b) we ship a DPA template that lists Anthropic as a Jikigai sub-processor
when the runtime is BYOK (Anthropic is the user's bilateral relationship),
misrepresenting the engagement at the very moment a prospect is scrutinizing
the document. Either failure costs the deal AND seeds a compliance audit
hook.

**If this leaks, the user's data/workflow/money is exposed via:** N/A —
this PR ships markdown only (no DB schema, no env vars, no runtime
surface). The leak vector is the inverse: an under-specified DPA
template that gets published in haste under a prospect deadline (the
exact scenario the pre-draft is designed to prevent) could create
contractual exposure for Jikigai (e.g., committing to sub-processor change
notification timelines, audit rights, or liability caps Jikigai cannot
actually honor).

**Brand-survival threshold:** `single-user incident` — one B2B prospect
who finds the DPA template internally contradictory with the ToS or
publicly contradictory with the DPD is one prospect lost AND one
compliance-question seed that can spread (procurement teams share
red-flag DPAs across networks).

`requires_cpo_signoff: true` — CPO sign-off required at plan time before
`/work` begins (carry-forward from related #4289 brainstorm + counsel-review
audit precedent). `user-impact-reviewer` will be invoked at review-time per
the conditional-agent block in `plugins/soleur/skills/review/SKILL.md`.

## Research Reconciliation — Spec vs. Codebase

The issue body asserts a contradiction between ToS §3b ("Workspace Owner =
controller") and DPD §2.1b ("Jikigai = controller") and proposes the fix
"replace 'Workspace Owner is the controller' with 'Workspace Owner
administers the workspace; Jikigai remains the platform-level Article 4(7)
controller'". Reading the canonical files against the deliberate architecture
shipped in PR #4225 / PR #4289 / PR #4328 surfaces five drifts:

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| ToS §3b.1 "Workspace Owner is controller" contradicts DPD §2.1b(a) "Jikigai is controller" | DPD §2.1b(a) covers "User account data, workspace data, and subscription data" — the default, platform-level posture for individual users. DPD §2.3(u) (added by PR #4289) AND DPD §4.2 footer carve-out (`data-protection-disclosure.md:183`) BOTH explicitly designate the Workspace Owner as the Art. 4(7) controller and Jikigai as the Art. 4(8) processor when `FLAG_TEAM_WORKSPACE_INVITE` is enabled. The two sections describe DIFFERENT processing activities (default-user vs team-workspace) — not a contradiction | **Directional ambiguity gate fires.** Plan defaults to **Direction B (preserve architecture)**: do NOT flip ToS §3b.1. Instead, add a clarifying clause to DPD §2.1b(a) that explicitly carves out the team-workspace sub-case (referencing §2.3(u) + §4.2 footer). CPO + CLO sign-off required at /work Phase 0 before any controller-language edit lands. See "Directional Ambiguity Gate" section below |
| Issue proposes "Jikigai remains the platform-level Article 4(7) controller" for team-workspace data | Counsel-review audit at `knowledge-base/legal/audits/2026-05-counsel-review-4289.md:38` operator-attested under CJEU C-210/16 *Wirtschaftsakademie* that the Workspace Owner "determines purposes (workspace use case), means (which Co-Members to invite, which scope grants to authorize), and timing (when to flip the flag, when to revoke)" — the load-bearing Art. 4(7) determinants. The Anthropic Commercial Terms §C "authorized users" framing requires Workspace Owner = controller for team workspaces | Issue's proposed fix would regress AC-LEGAL-FLIP, regress the operator-attested counsel review, and break the Anthropic Commercial Terms §C alignment. Direction B (DPD-side clarification) preserves all three |
| DPA sub-processor table enumerates: Supabase, Stripe, Anthropic, Hetzner, Cloudflare | Actual DPD §4.2 Web Platform processor table (`data-protection-disclosure.md:170-181`) contains: Supabase, Stripe, Hetzner, Cloudflare (CDN), Sentry (DE), Resend, Cloudflare R2, plus joint-controller rows for LinkedIn Ireland + Microsoft Ireland. **Anthropic is NOT in the §4.2 processor table** because the operator runtime is BYOK — Anthropic is the USER's bilateral relationship via Anthropic Commercial Terms §C, not Jikigai's sub-processor (see DPD §2.3(o) Sub-processors line: "Anthropic receives BYOK API calls under the user's own API key, governed by the user's bilateral Anthropic relationship via BYOK") | DPA template sub-processor table mirrors actual §4.2 (Supabase + Stripe + Hetzner + Cloudflare CDN + Sentry + Resend + Cloudflare R2; LinkedIn + Microsoft as joint controllers). **Anthropic listed in a separate "Customer-provisioned sub-processors" section** with the BYOK framing — when team-workspace ships with Soleur-managed Anthropic (not BYOK), this row promotes to the main sub-processor table via DPA Schedule 2 amendment, triggering Art. 28(2) customer notification |
| Issue body says "Adapted from public DPAs (Vercel, Linear, Notion all publish theirs at `/legal/dpa`)" | Verified at plan time: Vercel publishes at `vercel.com/legal/dpa`; Linear at `linear.app/dpa`; Notion at `notion.so/notion/Customer-Data-Processing-Addendum`. Existing in-repo DPA pattern at `knowledge-base/legal/tos-research/` references the Buttondown DPA shape (Art. 28-compliant) and the Stripe Atlas legal benchmark | Plan uses Vercel + Linear shape (concise, schedules at the end) as primary precedent; cross-checks against Buttondown DPA shape (already-in-our-vendor-stack precedent) |
| Issue body says "Compliance posture entry: 'DPA template drafted (knowledge-base only); publish + counsel-review when first B2B prospect requests'" | `knowledge-base/legal/compliance-posture.md` has an `## Active Compliance Items` section but the deferred-vs-active distinction matters: this is a TEMPLATE pre-draft, not an active compliance gap | Add to compliance-posture Active Items with explicit status `DEFERRED-ARTIFACT-ONLY` and the three trigger conditions verbatim from the issue body. **Status is NOT "in-progress" or "active"** — the template sits in `knowledge-base/legal/` and never enters `docs/legal/` until a trigger fires |

### Directional Ambiguity Gate

Per AGENTS.md hard rule and per Sharp Edges learning
`2026-03-17-planning-direction-confirmation-required`, this plan
explicitly enumerates the two directions and defaults to Direction B with a
plan-time CPO sign-off + /work Phase 0 reconfirmation gate.

**Direction A (issue body, NOT recommended):** Flip ToS §3b.1 to say
"Workspace Owner administers the workspace; Jikigai remains the platform-
level Article 4(7) controller." This reverts the Workspace-Owner-as-
controller framing shipped in PR #4289.

- **Cost:** Regresses AC-LEGAL-FLIP. Regresses the operator-attested
  counsel review (`2026-05-counsel-review-4289.md`). Breaks the Anthropic
  Commercial Terms §C "authorized users" alignment. Re-opens the
  audit-log scope-bleed indemnification (#4231 carve-out at ToS §3b.3(b))
  because if Jikigai is the controller, Jikigai owns the cross-member
  audit-log liability — the brand-survival risk #4231 was designed to
  shift to the Workspace Owner. Requires a TC_VERSION bump
  (`2.2.1 → 2.3.0`, MAJOR per `tc-version-bump-policy.md` because the
  framing of WHO determines purposes/means is a material change to user
  rights).
- **Benefit:** Eliminates the perceived DPD §2.1b vs ToS §3b
  contradiction by making Jikigai the controller across the board. But
  this benefit is illusory because the contradiction doesn't exist
  (see Direction B).

**Direction B (recommended, default):** Keep ToS §3b.1 unchanged. Add a
clarifying clause to DPD §2.1b(a) that explicitly carves out the team-
workspace sub-case. The full DPD §2.1b(a) becomes:

> **(a)** Jikigai acts as the **data controller** for User account
> data, workspace data, and subscription data processed through the
> Web Platform — EXCEPT for the team-workspace sub-case under
> `FLAG_TEAM_WORKSPACE_INVITE`, where the Workspace Owner is the
> controller per Section 2.3(u) and Section 4.2 footer carve-out, and
> Jikigai acts as the processor for the Workspace Owner. The DPA
> template at `docs/legal/data-processing-agreement.md` (or its
> knowledge-base pre-draft pending B2B trigger) governs the Jikigai-as-
> processor relationship with the Workspace Owner.

- **Cost:** One DPD §2.1b(a) sentence extension. Triggers a
  TC_VERSION bump for the ToS via the DPA cross-reference IF the DPA
  template moves to `docs/legal/`; for the deferred-artifact-only path
  in this PR, NO TC_VERSION bump is required because the DPA template
  stays in `knowledge-base/legal/`. **The DPD §2.1b(a) clarifying-clause
  edit DOES require an Eleventy mirror update + DPD `**Last Updated:**`
  line refresh + Article 30 register cross-reference confirmation.**
  Whether the DPD §2.1b(a) edit itself triggers a TC_VERSION bump
  depends on the Tier classification (`tc-version-bump-policy.md`) —
  see Phase 6 below for the classification gate.
- **Benefit:** Preserves the deliberate Workspace-Owner-as-controller
  architecture, preserves AC-LEGAL-FLIP, preserves the counsel-review
  posture, preserves Anthropic Commercial Terms §C alignment, and
  resolves the perceived contradiction by surfacing the carve-out in
  the section that the issue author actually read.

**Gate at /work Phase 0:** Before any controller-language edit lands,
/work MUST display Direction A vs B with this plan body's full
reasoning and require explicit operator ACK. If operator selects
Direction A, /work MUST halt and re-spawn a CLO + CPO domain-review
panel — Direction A is a material reversal of the #4289 framing and
cannot proceed on plan-time CPO sign-off alone.

## Description

Three artifact deliverables in this PR, all canonical-only (no Eleventy
mirror updates EXCEPT for DPD §2.1b(a) clarifying-clause edit):

1. **DPA template at `knowledge-base/legal/data-processing-agreement-template.md`** — Customer-facing template
   adapted from Vercel/Linear/Notion shape; sub-processor schedule mirrors
   actual DPD §4.2 (NOT the issue body's enumeration which lists Anthropic
   as a Jikigai sub-processor — wrong under BYOK). The template is
   parameterized for the three trigger events: (a) procurement DPA
   request (template ready to send unchanged); (b) team-workspace customer
   onboarding (template plus Side Letter framing carry-over from PR #4289);
   (c) EU SCCs request (template's Schedule 3 covers non-EU sub-processor
   SCCs).
2. **DPD §2.1b(a) clarifying clause** — Single sentence extension naming
   the team-workspace carve-out (Direction B above). Canonical edit at
   `docs/legal/data-protection-disclosure.md:69` + Eleventy mirror at
   `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` + DPD
   `**Last Updated:**` line refresh + dual-date update in Eleventy hero
   `<p>` + body `**Last Updated:**` per learnings
   `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`.
3. **Compliance-posture Active Items entry** — Status `DEFERRED-ARTIFACT-ONLY`
   with three verbatim trigger conditions; cross-references issue #4330,
   the DPA template, and the DPD §2.1b(a) edit.

**Explicitly out of scope (deferred to a future PR when a trigger fires):**

- Publishing the DPA template to `docs/legal/` + Eleventy mirror.
- TC_VERSION bump for a customer-DPA cross-reference in ToS.
- ToS §3b.4 "Side Letter and customer-DPA roadmap" supersession trigger.
- Counsel-review audit at `2026-05-counsel-review-dpa-template.md` —
  operator-attestation is sufficient for the knowledge-base draft per the
  Soleur-as-tenant-zero posture; external counsel review fires only at
  publish time (one of the three trigger events).
- Tenant-DPA register (`knowledge-base/legal/tenant-dpa-register.md`) first
  row write — fires only when first B2B customer counter-signs.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** File `knowledge-base/legal/data-processing-agreement-template.md`
  exists with sections: Preamble, Definitions (Art. 4 alignment),
  Subject Matter & Duration (§1), Nature & Purpose (§2), Categories of
  Data Subjects + Personal Data (§3), Controller Obligations (§4),
  Processor Obligations under Art. 28(3) (§5), Sub-processors under
  Art. 28(2) + (4) (§6), Data Subject Rights Assistance under Art. 28(3)(e) (§7),
  Personal Data Breach Notification under Art. 33+34 (§8),
  Security TOMs under Art. 32 (§9), Audit Rights under Art. 28(3)(h) (§10),
  International Transfers under Art. 44-49 + SCCs Module 2+3 (§11),
  Liability & Indemnification (§12), Term & Termination (§13),
  General Provisions (§14, including §14.7 Conflict-precedence per
  Linear DPA §9 precedent), Schedule 1 (Processing Details),
  Schedule 2 (Sub-processors), Schedule 3 (SCCs — Module 2 + Module 3),
  Schedule 4 (Technical & Organizational Measures — 17 sections per
  Vercel-precedent 18-category Annex II shape). Verified by
  `grep -cE '^## (Definitions|Subject Matter|Nature|Categories|Controller|Processor|Sub-processors|Data Subject Rights|Personal Data Breach|Security|Audit|International|Liability|Term|General|Schedule)' knowledge-base/legal/data-processing-agreement-template.md` returns ≥18 (14 main sections + 4 schedules).

- [ ] **AC2.** Schedule 2 (Sub-processors) of the DPA template enumerates
  EXACTLY the rows from DPD §4.2 Web Platform processor table:
  Supabase, Stripe, Hetzner, Cloudflare (CDN), Sentry (Functional
  Software GmbH), Resend, Cloudflare R2. **Anthropic is NOT listed as a
  Jikigai sub-processor** but appears in a separate "Customer-provisioned
  sub-processors (BYOK)" subsection with the Anthropic Commercial Terms §C
  cross-reference. Verified by `grep -E '\| (Supabase|Stripe|Hetzner|Cloudflare|Sentry|Resend) ' knowledge-base/legal/data-processing-agreement-template.md | wc -l` returns ≥7 AND
  `awk '/^### Schedule 2/,/^### Schedule 3|^---$/' knowledge-base/legal/data-processing-agreement-template.md | grep -c 'Anthropic' returns 0` AND
  `awk '/^#### Customer-provisioned/,/^### |^---$/' knowledge-base/legal/data-processing-agreement-template.md | grep -c 'Anthropic'` returns ≥1.

- [ ] **AC3.** Schedule 3 (SCCs) of the DPA template identifies non-EU
  transfer rows requiring Standard Contractual Clauses (SCCs) Module 2
  (Controller-to-Processor): Stripe (US, with DPF coverage), Resend
  (US), Sentry's underlying cloud (DE per data-protection-disclosure.md
  but Sentry corporate SCCs apply to onward US transfers). EU-only rows
  (Hetzner Helsinki, Cloudflare R2 region `weur`, Supabase EU project) are
  NOT in Schedule 3. Verified by manual review at /work Phase 6.

- [ ] **AC4.** DPA template carries the standard Soleur draft disclaimer
  block (mirrors `tenant-dpa-register.md:15`):

  > **DRAFT — This document was generated by AI and requires professional
  > legal review before use. It does not constitute legal advice.**

  At top AND bottom of the file. Verified by
  `head -20 knowledge-base/legal/data-processing-agreement-template.md | grep -c 'requires professional legal review'` returns 1 AND
  `tail -20 knowledge-base/legal/data-processing-agreement-template.md | grep -c 'requires professional legal review'` returns 1.

- [ ] **AC5.** DPA template YAML frontmatter contains:
  `status: draft-pending-trigger`, `custodian: clo`, `trigger_events: [b2b-prospect-request, team-workspace-customer-onboard, eu-scc-request]`,
  `not_yet_executed: true`, `publish_target: docs/legal/data-processing-agreement.md`,
  `related_issue: 4330`. Verified by
  `awk '/^---$/{c++} c==1' knowledge-base/legal/data-processing-agreement-template.md | grep -E '^(status|custodian|trigger_events|not_yet_executed|publish_target|related_issue):'` returns ≥6 lines.

- [ ] **AC6.** DPD §2.1b(a) carries the team-workspace carve-out
  clarifying sentence (Direction B from Research Reconciliation). The
  edit lands in BOTH the canonical
  `docs/legal/data-protection-disclosure.md` AND the Eleventy mirror
  `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`.
  Verified by `grep -c 'EXCEPT for the team-workspace sub-case under' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns 2.
  **Direction A (issue body's proposed ToS §3b flip) is NOT applied** —
  ToS §3b.1 wording is byte-identical to its current state at HEAD.
  Verified by `git diff main -- docs/legal/terms-and-conditions.md plugins/soleur/docs/pages/legal/terms-and-conditions.md` returns empty.

- [ ] **AC7.** DPD `**Last Updated:**` line carries today's date (`May 22, 2026`)
  AND a brief amendment note referencing issue #4330 + the §2.1b(a)
  carve-out. Both Eleventy mirror sites (hero `<p>` + body
  `**Last Updated:**`) carry the same date. Verified by
  `grep -cE '\*\*Last Updated:\*\* May 22, 2026' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns 2 AND
  `grep -c 'Last Updated May 22, 2026' plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns ≥1 (hero form per learning
  `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`).

- [ ] **AC8.** TC_VERSION classification gate verified at Phase 6.
  `tc-version-bump-policy.md` (`:65-77`) classifies clarifying-cross-
  reference edits as Tier 2 — which DOES require a PATCH bump
  (`tc-version-bump-policy.md:75-77`: "Use a `PATCH` bump under the
  semver-for-legal-docs scheme"). HOWEVER, the SHA guardrail at
  `apps/web-platform/scripts/check-tc-document-sha.sh:112,187` is
  scoped to `docs/legal/terms-and-conditions.md` ONLY (the script's
  `CANONICAL` variable points at the ToS file; DPD is not a
  TC_VERSION-coupled file). Therefore: (i) editing the DPD does NOT
  trigger the SHA guardrail, (ii) editing the DPD does NOT require a
  TC_VERSION bump because the TC_VERSION literal at
  `apps/web-platform/lib/legal/tc-version.ts:14` is the version OF
  THE ToS, not the version of the DPD. AC6 confirms ToS is byte-
  identical to HEAD; therefore no bump fires. Verified by
  `git diff main -- apps/web-platform/lib/legal/tc-version.ts apps/web-platform/scripts/seed-dev-user.sh apps/web-platform/scripts/seed-qa-user.sh` returns empty
  AND `git diff main -- docs/legal/terms-and-conditions.md plugins/soleur/docs/pages/legal/terms-and-conditions.md` returns empty (re-asserts AC6 dependency).

- [ ] **AC9.** `knowledge-base/legal/compliance-posture.md` gains an
  `## Active Compliance Items` row with status
  `DEFERRED-ARTIFACT-ONLY` and the three verbatim trigger conditions from
  the issue body. The row cites issue #4330, the DPA template path, and
  the DPD §2.1b(a) edit. Verified by
  `grep -c 'DPA template drafted (knowledge-base only); publish + counsel-review when first B2B prospect requests' knowledge-base/legal/compliance-posture.md` returns 1 AND
  `awk '/4330/,/^\|/' knowledge-base/legal/compliance-posture.md | grep -c 'DEFERRED-ARTIFACT-ONLY'` returns 1.

- [ ] **AC10.** Directional ambiguity gate ACK recorded in PR body. PR
  body MUST include the line:
  `Direction confirmation: B (preserve Workspace-Owner-as-controller from #4289). ToS §3b unchanged.`
  Verified by `gh pr view --json body --jq .body | grep -c 'Direction confirmation: B'` returns 1 at PR-ready time.

- [ ] **AC11.** Counsel-review skipped at this PR per the Soleur-as-
  tenant-zero posture. No counsel-audit file is created in
  `knowledge-base/legal/audits/` at this PR. Verified by
  `git diff --name-only main..HEAD | grep -c 'knowledge-base/legal/audits/.*dpa'` returns 0. The DPA template carries an inline note (Phase 4) recording the external counsel re-review trigger = "first publish to `docs/legal/` (any of the three trigger events fires)".

- [ ] **AC12.** Article 30 register cross-reference: confirm DPD §2.1b(a)
  carve-out does NOT introduce a new processing activity. The existing
  PA-2 (`workspace co-member`, amended by PR #4225) already covers the
  team-workspace processing; PA-19 (`workspace_member_removals`, #4294)
  and PA-20 (`workspace_member_actions`, #4287) are sibling audit
  surfaces. **No PA-21 needed.** Verified by `grep -c 'PA-21\|Processing Activity 21' knowledge-base/legal/article-30-register.md` returns 0.

- [ ] **AC13.** Eleventy build succeeds with the DPD mirror update.
  Verified by `cd plugins/soleur/docs && bun run build && test -f _site/legal/data-protection-disclosure/index.html`.

- [ ] **AC14.** `legal-doc-consistency.test.ts` passes (hero + body
  Last-Updated dual-regex per learning
  `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`).
  The package's `package.json scripts.test` resolves to `vitest`; AND
  `apps/web-platform/bunfig.toml [test] pathIgnorePatterns = ["**"]`
  blocks `bun test` entirely (defense-in-depth per #1469). Verified by
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts`. The test asserts the hero pattern `Last Updated\s+(<date>)` AND the body pattern `\*\*Last Updated:\*\*\s+(<date>)` against the canonical source's `**Last Updated:**\s+(<date>)` — all three dates must match (verified at the test's lines 122-134; live-read at /work Phase 0).

- [ ] **AC15.** GDPR-gate Phase 2.7 invocation logged with PASS or
  documented Critical fold-in. Verified by Phase 7 below.

- [ ] **AC16.** `## User-Brand Impact` section present in the plan with
  threshold = `single-user incident`. Verified by
  `grep -c '## User-Brand Impact' knowledge-base/project/plans/2026-05-22-feat-dpa-template-tos-controller-fix-4330-plan.md` returns 1.

- [ ] **AC17.** PR body uses `Closes #4330` on its own line in the
  body (AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`: "Use
  `Closes #N` ONLY on its own body line for intentional closure;
  `Ref #N` everywhere else"). `Closes` (not `Ref`) is correct here
  because the deliverable IS the PR's diff (the artifact + DPD edit)
  — there is no post-merge operator step required to satisfy the
  issue's "definition of done." The `Ref #N` convention applies to
  ops-remediation classes where the issue resolution happens
  post-merge (e.g., a `terraform apply` runbook PR), which is the
  opposite of this PR's classification (`classification: deferred-
  automation-artifact`, no apply path). Cross-reference learning
  `2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md` for
  the post-apply deferral pattern (not applicable here). Verified by
  `gh pr view --json body --jq .body | grep -cE '^Closes #4330$'` returns 1 at PR-ready.

### Post-merge (operator)

- [ ] **AC18 (POST).** None. This PR is artifact-only. No prod write,
  no migration, no Doppler secret, no Terraform apply, no service
  restart. Per the automation-feasibility gate in plan SKILL §6, all
  artifact-only operations are inline in /work phases below; no
  operator-only step deferred.

## Domain Review

**Domains relevant:** Legal (CLO), Product (CPO), Engineering (CTO advisory)

### Legal (CLO)

**Status:** reviewed (plan-time, operator-attested per
Soleur-as-tenant-zero precedent #4081/#4066/#4213/#4289)

**Assessment:** The issue body's claim of a ToS §3b vs DPD §2.1b
contradiction is materially incorrect — the two sections describe
different processing activities (default-user platform-level vs
team-workspace sub-case under `FLAG_TEAM_WORKSPACE_INVITE`). The DPD
§4.2 footer carve-out (`data-protection-disclosure.md:183`) explicitly
designates Workspace Owner = controller and Jikigai = processor for
team workspaces, consistent with ToS §3b.1 + the counsel-review audit
under CJEU C-210/16 *Wirtschaftsakademie*. **Direction B (DPD-side
clarification) is the correct fix.** Direction A would regress
AC-LEGAL-FLIP + the counsel-review posture + the Anthropic Commercial
Terms §C alignment.

DPA template structure mirrors Vercel/Linear/Notion shape with the
Buttondown DPA shape as in-our-vendor-stack precedent. Sub-processor
table mirrors actual DPD §4.2 (Anthropic excluded — BYOK posture).
Customer-provisioned sub-processor framing for Anthropic is novel within
the Soleur DPA corpus; carries the same load-bearing argument as the
ToS §3b.1 "authorized users" framing under Anthropic Commercial Terms
§C.

External counsel re-review trigger: any of the three trigger events
from the issue body (B2B prospect request, team-workspace customer
onboard, EU SCC request). NOT triggered by this PR (template stays in
`knowledge-base/legal/` and is never sent to a counter-party).

### Product (CPO)

**Status:** reviewed (plan-time required per
`brand_survival_threshold: single-user incident`)

**Assessment:** Pre-drafting under deadline-relaxed conditions is the
correct go-to-market posture — "DPA not yet available" is a deal-
losing answer at any company larger than a freelancer. The template
being ready for immediate operator review-and-send (or for counsel
review under an actual deadline) preserves negotiating posture vs the
worst case where a prospect's procurement team waits 2-4 weeks for a
DPA draft and re-evaluates competitors in the gap.

The directional ambiguity gate (Direction A vs B) MUST be resolved
plan-time, not work-time, because Direction A is a material reversal
that would require re-spawning the entire #4289 counsel-review panel
+ re-running the CLO Wirtschaftsakademie analysis + bumping
`TC_VERSION 2.2.1 → 2.3.0` (MAJOR) — none of which fit the
"deferred-artifact-only" framing. CPO sign-off is on Direction B.

### Engineering (CTO advisory)

**Status:** reviewed (plan-time, advisory only — no code surface)

**Assessment:** No code surface touched. DPD §2.1b(a) edit is text-only;
TC_VERSION is NOT coupled to DPD (only to ToS via
`check-tc-document-sha.sh:112,187`). Eleventy build is the only CI
gate that runs against the changed file set — Phase 5 includes the
`bun run build` smoke. No migration, no Doppler secret, no Terraform.

### Product/UX Gate

**Tier:** none (no user-facing UI changes — text-only DPD edit; DPA
template lives in `knowledge-base/legal/` and is not Eleventy-served).

**Decision:** auto-accepted (pipeline) — no UI flows, no new
components, no copy-emotion concerns. The DPD §2.1b(a) edit appears on
`/legal/data-protection-disclosure` but the change is a single
clarifying clause inside an existing section the user already
encountered at TC acceptance — no Art. 13(3) "what changed" banner
required because the change is Tier 2 clarifying, not Tier 1 material
(see AC8).

## Implementation Phases

### Phase 0 — Direction Confirmation + Preconditions (5 min)

1. Display Research Reconciliation Direction A vs B with full reasoning.
2. Require operator ACK: "Direction confirmation: B (preserve
   Workspace-Owner-as-controller from #4289). Proceed? [Y/n]".
3. If operator selects A, HALT — re-spawn CLO + CPO domain-review panel
   inline before continuing.
4. Verify `apps/web-platform/package.json` test runner: read
   `cat apps/web-platform/package.json | jq -r '.scripts.test'` to
   determine vitest vs bun-test vs jest. Record the actual runner; AC14
   uses this exact command (per Sharp Edge:
   `2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md` SE#3
   re: `bunfig.toml [test] pathIgnorePatterns`).
5. Read the current DPD §4.2 processor table verbatim (lines 170-181) to
   pin Schedule 2 of the DPA template against ground-truth (paraphrase-
   without-verification Sharp Edge).
6. Read counsel-review audit `2026-05-counsel-review-4289.md` §1
   (Controllership framing) — quote the operator-position rationale in
   Phase 4 of the DPA template Recitals to surface the architecture
   alignment.

### Phase 1 — DPA Template Skeleton (30 min)

1. Create `knowledge-base/legal/data-processing-agreement-template.md`
   with YAML frontmatter per AC5.
2. Write top-of-file DRAFT disclaimer per AC4 (verbatim from
   `tenant-dpa-register.md:15`).
3. Write Recitals (3 paragraphs): (a) Customer-Jikigai engagement
   context — references ToS §3b.4 supersession trigger; (b)
   Wirtschaftsakademie-aligned controllership framing — Customer is
   controller for Customer Data (team-workspace data) per
   ToS §3b.1; Jikigai is processor per DPD §4.2 footer carve-out;
   (c) BYOK posture — Anthropic API calls under Customer's own
   Anthropic Commercial Terms §C "authorized users" relationship.
4. Write §1 Subject Matter & Duration — duration matches the Customer
   Web Platform subscription lifecycle; survival of confidentiality +
   audit-trail obligations per Art. 28(3)(g)+(h).
5. Write §2 Nature & Purpose — single sentence per processing activity
   (drafts, send-audit ledger, scope-grants ledger, account data —
   five sentences total mirroring DPD §2.3 sub-bullets the customer is
   authorized to use).

### Phase 2 — DPA §3-§5 Body (45 min)

1. **§3 Categories of Data Subjects + Personal Data:** Two
   sub-tables.
   - Data subjects: (a) Workspace Owner (the Customer's primary user
     of record); (b) Co-Members (the Customer's invitees);
     (c) Customer Contacts processed in conversation content (if
     Customer's use case includes external-correspondent flows).
   - Personal data categories: mirror DPD §2.3(u) data category +
     the cross-table list (`messages`, `conversations`, `kb_files`,
     `kb_chunks`, `scope_grants`, `action_sends`,
     `template_authorizations`, `workspace_member_attestations`,
     `workspace_member_actions`) — each row cites the DPD §2.3
     sub-bullet for the read-through.
2. **§4 Controller Obligations:** Customer warrants (a) lawful basis
   for upstream collection of Co-Member + Customer Contact data;
   (b) Art. 13/14 transparency notice to data subjects; (c) DSR
   intake routing; (d) AUP §5.5 attestation framework or
   equivalent.
3. **§5 Processor Obligations (Art. 28(3) (a)-(h)):** Eight
   sub-sections numbered (a) through (h) verbatim per Art. 28(3):
   (a) Documented instructions; (b) Confidentiality;
   (c) Art. 32 TOMs (cross-reference DPA §9);
   (d) Sub-processor engagement (cross-reference DPA §6);
   (e) Art. 12-22 DSR assistance (10-business-day SLA;
   cross-reference DSAR worker + `/dashboard/settings/privacy` self-
   serve); (f) Art. 32-36 assistance + DPIA assistance;
   (g) Deletion-or-return at end of engagement (point to DPD §10.3
   LinkedIn carve-out for non-erasable surfaces);
   (h) Audit cooperation + information-provision.

### Phase 3 — DPA §6 Sub-processors (30 min)

1. **§6.1 Standing authorization** for the sub-processors in
   Schedule 2 with a **30-day prior-written-notice** mechanism for
   new sub-processor engagement + a **30-day customer objection
   window** (conservative midpoint between Vercel's 5-day window and
   Linear's 15+10-day window; matches enterprise-procurement
   expectations per EDPB Art. 28 best-practice survey). Notification
   channel: `legal@jikigai.com` outbound; customer subscription
   opt-in at DPA execution.
2. **§6.2 Flow-down** — Jikigai warrants Art. 28(4) flow-down via the
   sub-processor DPAs cited in DPD §4.2 (verbatim links from the
   processor table). Each sub-processor agreement carries
   substantially-similar data protection obligations regarding
   notification, deletion, authorization, location, and instruction
   compliance.
3. **§6.3 Customer-provisioned sub-processors (BYOK)** — Anthropic
   carve-out per Anthropic Commercial Terms §C "authorized users";
   Customer is responsible for its own Anthropic DPA execution and
   sub-processor list. When team-workspace ships with Soleur-managed
   (non-BYOK) Anthropic access, this row promotes to Schedule 2 via
   DPA Schedule 2 amendment, triggering the §6.1 30-day notification.
4. **§6.4 Essential sub-processor carve-out** (per Linear DPA precedent
   §3.3) — Customer objection to an Essential Sub-processor (those
   substrate-level: Supabase, Hetzner, Cloudflare for CDN+R2) cannot
   block continued use; resolution path is Customer right to
   terminate with pro-rata refund. This protects Jikigai from a
   single objection collapsing the entire substrate.
5. Schedule 2 table — VERBATIM from DPD §4.2 Web Platform processor
   table at the publish-PR's HEAD SHA (per AC2). Column shape:
   Sub-processor | Activity | Data processed | Location | DPA URL.
   Inline note: "For the always-current list, see
   `knowledge-base/legal/compliance-posture.md` Vendor DPA Status
   table at the URL printed in the DPA's hero." Cross-reference
   recorded because Soleur does NOT host a public
   `security.soleur.ai`-style sub-processor page today (deferred per
   tracking issue stub in Risks).

### Research Insights — §6 Sub-processors

**Best practices (grounded in Vercel + Linear precedents):**

- **Notification window:** Vercel ships 5-day customer objection.
  Linear ships 15-day prior notice + 10-day objection. EDPB Art. 28
  best-practice survey ([gdpr-info.eu/art-28](https://gdpr-info.eu/art-28-gdpr/))
  recommends ~30 days. The 30-day window in §6.1 is procurement-
  team-friendly and gives Jikigai legal cushion for the operator-
  attested compliance posture (no SOC 2 yet → procurement team
  needs more time for diligence).
- **Sub-processor list externalization:** Vercel maintains the list
  at `security.vercel.com` as a separate addressable page. Soleur's
  closest analogue is `knowledge-base/legal/compliance-posture.md`
  (Vendor DPA Status table) which is NOT publicly addressable today.
  Until that gap is closed (tracking issue per Risks), Schedule 2 is
  an inline snapshot updated at DPA-publish time.
- **Essential sub-processor:** Linear's "block-the-objection" clause
  for sub-processors that cannot be swapped (e.g., Snowflake for a
  data-warehouse customer) maps to Soleur's substrate (Supabase as
  primary auth+DB; Hetzner as primary infra; Cloudflare as
  primary CDN). The customer's recourse for objection on these is
  termination + pro-rata refund, not service continuation under
  protest. Codified as §6.4.

**Edge cases:**

- A customer-DPA executed BEFORE a new sub-processor is engaged
  retroactively binds the 30-day notification — track the customer's
  DPA signing date in `tenant-dpa-register.md` so notification
  ordering is auditable.
- A customer objecting to a sub-processor change that has ALREADY
  been deployed (e.g., a vendor add executed silently before the
  DPA-bound customer signed) creates a retroactive-consent gap. The
  template's §6.1 prescribes 30-day NOTICE — Jikigai's commitment is
  that no new sub-processor engages without notification, even
  pre-DPA-execution customers receive notification at the same time.
- BYOK migration: if a customer flips from BYOK Anthropic to Soleur-
  managed Anthropic, the Schedule 2 amendment + 30-day notification
  fire. Template §6.3 names this path explicitly.

**References:**

- [Vercel Subprocessing terms](https://vercel.com/legal/dpa) §7
- [Linear Authorized Sub-Processors](https://linear.app/dpa) §3
- [GDPR Art. 28(2) + (4)](https://gdpr-info.eu/art-28-gdpr/) — sub-processor authorization + flow-down

### Phase 4 — DPA §7-§14 + Schedules (45 min)

1. **§7 DSR assistance** — point to `/dashboard/settings/privacy`
   self-serve + 10-business-day operator SLA + Resend transactional
   email notification surface.
2. **§8 Personal Data Breach Notification** — 72-hour Art. 33
   notification timing; Resend-based notification channel; PIR
   template precedent at
   `knowledge-base/engineering/ops/post-mortems/`.
3. **§9 Security TOMs** — bulleted list cribbed from DPD §2.3(u)
   load-bearing measures + cross-reference to `compliance-posture.md`
   for the always-current list.
4. **§10 Audit Rights** — annual audit right under Art. 28(3)(h);
   information-provision via SOC2 report (when Jikigai obtains one)
   or operator-attested compliance posture + counsel-review audits
   in the interim; 30-day prior notice; reasonable scope; Customer
   bears costs unless material non-compliance found.
5. **§11 International Transfers** — SCCs Module 2 (Controller-to-
   Processor) AND Module 3 (Processor-to-Sub-processor) incorporated
   by reference for non-EU sub-processors (Stripe US, Resend US,
   Sentry onward US transfers); DPF coverage where available
   (LinkedIn + Microsoft per DPD §6.4 Web Platform international
   transfer table). UK IDTA reserved as a "promote on request" annex
   (not in v1 template — Soleur has no UK customer yet; tracking note
   in Risks).
6. **§12 Liability** — cap matches Customer's contracted Web Platform
   ToS liability cap. Cross-reference to **ToS §11 (Limitation of
   Liability)** and specifically §11.2 (Aggregate Liability Cap =
   greater of EUR 100 or 12-month subscription fees) — VERIFIED
   verbatim against `docs/legal/terms-and-conditions.md:287-300` at
   plan-deepen time. Carve-outs: Art. 82 statutory damages, gross
   negligence + willful misconduct, breach of confidentiality, breach
   of sub-processor flow-down. Super-cap for sub-processor breach
   limited to the actual sub-processor's liability-cap-of-record (so
   Jikigai's exposure on a Supabase breach is bounded by Supabase's
   DPA cap, not amplified).
7. **§13 Term & Termination** — co-terminus with Customer subscription
   (Web Platform ToS §14); survival of Art. 28(3)(g) deletion-or-
   return + Art. 28(3)(h) audit + §10 audit rights + §12 liability
   carve-outs for **12 months post-termination** (mirrors Vercel DPA
   §12; commercially reasonable timeframe).
8. **§14 General Provisions** — governing law (France) and exclusive
   jurisdiction (courts of Paris). Cross-reference to **ToS §15
   (Governing Law and Dispute Resolution)** specifically §15.1
   (France law) + §15.2 (Paris courts), VERIFIED against
   `docs/legal/terms-and-conditions.md:353-365` at plan-deepen time.
   Consistent with Side Letter template §6 (RCS Paris 927 585 729
   jurisdiction; Jikigai SARL gérant signatory format). Severability,
   force majeure, and entire-agreement clauses. **§14.7
   Conflict-precedence** (Linear DPA §9 precedent): (1) SCCs >
   (2) this DPA > (3) Web Platform ToS > (4) any upstream
   procurement-supplied DPA unless bilaterally re-executed by both
   parties' authorized signatories.
9. **Schedule 1 Processing Details** — single-page summary table
   referenced from §1+§2. Cross-reference to DPD §2.3 sub-bullets
   for each row (single source of truth for processing-activity
   definitions). Columns: Activity | Nature | Purpose | Categories of
   Data Subjects | Categories of Personal Data | Duration | Sensitive
   data (none, by warranty in §4).
10. **Schedule 3 SCCs** — per AC3. EU SCCs (Commission Implementing
    Decision (EU) 2021/914) incorporated by reference; Module 2 +
    Module 3 specified. Annex I.A (Parties) cross-references the
    parties named in the DPA cover page. Annex I.B (Description of
    Transfer) references Schedule 1. Annex II (TOMs) references
    Schedule 4. Annex III (Sub-processors) references Schedule 2.
11. **Schedule 4 Technical & Organizational Measures (TOMs)** — new
    schedule (Vercel precedent: 18 sections). Soleur's v1: 17
    sections covering (1) Encryption (TLS 1.3 in transit; AES-256 at
    rest via Supabase), (2) Pseudonymisation (`userIdHash` per
    DPD §2.3(m)), (3) Access control (RLS owner-only + named-role
    REVOKE matrix), (4) Authentication (Supabase Auth + Stripe SCA),
    (5) Confidentiality (operator-attested), (6) Integrity (WORM
    triggers per DPD §2.3 + Recital 75), (7) Availability + DR
    (Hetzner Helsinki + Cloudflare R2 multi-region), (8) Restoration
    (Supabase point-in-time recovery), (9) Testing (CI + multi-agent
    review), (10) Monitoring (Sentry + Better Stack), (11) Logging
    (pino + Vector + VRL PII redaction per DPD §2.3(m)),
    (12) Sub-processor due diligence (`compliance-posture.md` Vendor
    DPA Status table), (13) Data minimisation (DSAR allowlist;
    Article 17 erasure cascade), (14) Article 32 TOMs by category
    (organisational + technical), (15) Article 33 breach response
    (72-hour timeline; Resend + Sentry telemetry), (16) DSAR
    response (10-business-day operator SLA), (17) Data deletion at
    termination (12-month retention floor per Art. 5(1)(e)).
12. Write bottom-of-file DRAFT disclaimer (mirrors top per AC4).
13. Add inline note recording the external counsel re-review trigger:
    "External counsel review fires at the first publish event (any
    of the three trigger events in `compliance-posture.md`); until
    then this template is operator-attested under the Soleur-as-
    tenant-zero posture per #4081/#4066/#4213/#4289 precedent."

### Research Insights — §10 Audit Rights + §11 International Transfers

**Best practices:**

- **Audit via SOC 2 substitute (Vercel pattern):** Vercel offers
  third-party audit reports (SOC 2 Type 2) as Customer audit
  fulfillment without granting on-site access. Soleur has no SOC 2
  TODAY; the template ships with "operator-attested compliance
  posture in lieu of SOC 2 until obtained" with a binding commitment
  to obtain SOC 2 within 24 months of the first executed DPA. This
  commitment is a load-bearing claim — track in `compliance-posture.md`
  as a SOC 2 roadmap item gated on the first DPA execution.
- **30-day audit notice + 1× per year cap** (Linear precedent §7.4) —
  prevents customer-side audit-fatigue attacks; Customer bears costs
  unless material non-compliance. Codified.
- **SCC Module attribution explicit** — EDPB recommends Module 2
  (C2P) AND Module 3 (P2P) for sub-processor flow-down. Both named
  in Schedule 3 to satisfy Art. 28(4) end-to-end.
- **UK IDTA reserved** — Vercel ships UK IDTA as Schedule 5. Soleur
  has no UK customer; deferring UK IDTA to a v2 amendment keeps the
  template lean.

**Edge cases:**

- SCC sub-processor onward transfer to a country with no adequacy
  decision (e.g., a Stripe sub-processor in India) triggers
  Module 3 + supplementary measures (encryption-in-transit + access
  controls). Template's §11 names supplementary-measures requirement
  generically; specific measures live in Schedule 4 TOM categories
  6-7.
- Customer in Switzerland — Swiss FADP applies in parallel to GDPR.
  Schedule 5 Jurisdiction-Specific Terms (Vercel pattern) reserved
  for v2; template's §11 generic SCC reference covers Switzerland
  via the Module 4 (C2C from a non-EEA controller) corollary in
  Schedule 3.

**References:**

- [Vercel Audits and Reviews of Compliance](https://vercel.com/legal/dpa) §9
- [Linear Actions and Access Requests; Audits](https://linear.app/dpa) §7
- [Commission Implementing Decision (EU) 2021/914 — SCCs](https://eur-lex.europa.eu/eli/dec_impl/2021/914/oj)
- [GDPR Art. 44-49 international transfers](https://gdpr-info.eu/chapter-5/)

### Phase 5 — DPD §2.1b(a) Clarifying Clause (15 min)

1. Read `docs/legal/data-protection-disclosure.md:69` (the current
   §2.1b(a) line) verbatim.
2. Apply the Direction B clarifying-clause replacement per the
   Research Reconciliation table — bold "**EXCEPT for the team-
   workspace sub-case**" so it visually announces the carve-out.
3. Update `docs/legal/data-protection-disclosure.md:12` `**Last
   Updated:**` line with a brief amendment note prepending to the
   existing chain:
   `**Last Updated:** May 22, 2026 (#4330 — Section 2.1b(a) clarifying carve-out for the team-workspace sub-case under FLAG_TEAM_WORKSPACE_INVITE; cross-references Section 2.3(u) and Section 4.2 footer carve-out shipped by PR #4289; no new sub-processor, no new processing activity, no TC_VERSION coupling because DPD has no SHA guardrail; DPA template at knowledge-base/legal/data-processing-agreement-template.md pre-drafted pending the three B2B trigger events from issue #4330; previous: May 22, 2026 ...)`.
4. Apply the same edit to the Eleventy mirror
   `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` at
   both hero `<p>` (no colon form per learning #2) and body
   `**Last Updated:**`.

### Phase 6 — TC_VERSION Classification Gate (5 min)

1. Open `apps/web-platform/lib/legal/tc-version.ts`. Confirm current
   `TC_VERSION = "2.2.1"` and `TC_DOCUMENT_SHA = "e87c..."`.
2. Confirm THIS PR does NOT touch
   `docs/legal/terms-and-conditions.md` (Direction B preserves ToS
   §3b verbatim). Verify by
   `git diff main -- docs/legal/terms-and-conditions.md plugins/soleur/docs/pages/legal/terms-and-conditions.md`
   returns empty.
3. Confirm DPD has no SHA guardrail by reading
   `apps/web-platform/scripts/check-tc-document-sha.sh:112,187` —
   both lines reference `docs/legal/terms-and-conditions.md` only.
4. Conclusion: no TC_VERSION bump, no SHA refresh, no
   `apps/web-platform/lib/legal/tc-version.ts` edit, no
   `apps/web-platform/scripts/seed-*-user.sh` edit. AC8 verified.

### Phase 7 — GDPR-gate Phase 2.7 + Compliance-posture Entry (15 min)

1. Run `/soleur:gdpr-gate` against the plan + the DPA template + the
   DPD §2.1b(a) edit. Expected PASS — no new processing activity, no
   Art. 9 special-category data, no new lawful basis. Critical fold-ins
   surfaced by the gate land inline per the gate's normal flow
   (operator-acknowledged write to `compliance-posture.md` Active
   Items + GitHub issue `compliance/critical`).
2. File tracking issue stub for the public sub-processor list page
   (per Risks): `gh issue create --title "feat(legal): public sub-processor list page (security.soleur.ai)" --label domain/legal --label deferred-automation --body "Deferred from PR closing #4330. Vercel precedent: security.vercel.com. Trigger to act: first DPA execution requires a publicly addressable sub-processor list per Art. 28(2). Today the closest analogue is knowledge-base/legal/compliance-posture.md Vendor DPA Status table which is not public. Re-evaluate at first DPA publish trigger event."`. Record the issue number in this plan body's References section + the DPA template Schedule 2 inline note.
3. Add `compliance-posture.md` Active Items row per AC9. Use this
   exact wording in the Notes column:
   `Single-user-incident threshold (carry-forward from #4289). DPA template pre-draft at knowledge-base/legal/data-processing-agreement-template.md. Status: DEFERRED-ARTIFACT-ONLY. Three trigger conditions: (a) first B2B prospect asks "Do you have a DPA?"; (b) first paying customer organization invites employees as Workspace Co-Members under FLAG_TEAM_WORKSPACE_INVITE (the team-workspace dogfood expands beyond Jikigai-internal Jean+Harry); (c) first EU customer requests SCCs for non-EU sub-processors (Stripe US, Resend US, Sentry onward US). On trigger fire: (i) publish DPA template by copying to docs/legal/data-processing-agreement.md + Eleventy mirror; (ii) invoke external counsel review; (iii) bump TC_VERSION if a customer-DPA cross-reference is added to ToS §3b.4 supersession trigger; (iv) write tenant-DPA register first row on counter-signature. DPD §2.1b(a) carve-out clarification shipped in this PR (canonical + mirror); no contradiction with ToS §3b.1 (the two sections describe different processing activities — default-user platform-level vs team-workspace sub-case). Closes #4330.`

### Phase 8 — Verification Sweep (15 min)

1. Run all AC1-AC17 verification commands per the AC list above.
   Record output in the PR body's "## Verification" section.
2. Run `bun run build` (or the equivalent Eleventy build command per
   the docs site's `package.json`) on the Eleventy site to confirm
   the DPD mirror update lands (AC13).
3. Run the legal-doc-consistency test per AC14 using the actual
   test runner from Phase 0 step 4.
4. Verify all `knowledge-base/` and `docs/legal/` cross-references in
   the DPA template resolve by running
   `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md|docs/legal/[A-Za-z0-9/_.-]+\.md' knowledge-base/legal/data-processing-agreement-template.md | grep -v -F 'docs/legal/data-processing-agreement.md' | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'` — empty output expected (per Sharp Edge:
   `2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md` SE#6). The single excluded path
   `docs/legal/data-processing-agreement.md` is the publish-target
   referenced in the template's `publish_target:` frontmatter; it does
   NOT exist at this PR by design (publish is deferred to first
   trigger event).
5. Open PR with body that includes:
   - `Closes #4330` (per AC17).
   - `Direction confirmation: B (preserve Workspace-Owner-as-controller from #4289). ToS §3b unchanged.` (per AC10).
   - Verification output for each AC.
   - Cross-references to #4289 (parent legal scaffolding), #4225 (parent schema), #4328 (parent softening).
   - `## User-Brand Impact` section mirror.

## Files to Edit

- `docs/legal/data-protection-disclosure.md` — §2.1b(a) clarifying
  clause (Phase 5 step 2); `**Last Updated:**` line refresh (Phase 5
  step 3).
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` —
  mirror of canonical DPD edit (Phase 5 step 4); hero `<p>` +
  body `**Last Updated:**` dual-date update.
- `knowledge-base/legal/compliance-posture.md` — Active Items row
  per AC9 + Phase 7 step 2.

**Explicitly NOT in Files to Edit (Direction B preserves these):**

- `docs/legal/terms-and-conditions.md` — ToS §3b.1 unchanged.
- `plugins/soleur/docs/pages/legal/terms-and-conditions.md` — mirror
  unchanged.
- `apps/web-platform/lib/legal/tc-version.ts` — no TC_VERSION bump.
- `apps/web-platform/scripts/seed-dev-user.sh` /
  `apps/web-platform/scripts/seed-qa-user.sh` — no seed-literal sync.
- `knowledge-base/legal/article-30-register.md` — no PA-21 (per AC12).
- `knowledge-base/legal/tenant-dpa-register.md` — no first-row write
  (deferred to first counter-signed B2B customer).

## Files to Create

- `knowledge-base/legal/data-processing-agreement-template.md` — the
  DPA template per Phases 1-4 + AC1-AC5.

## Open Code-Review Overlap

Two-stage `gh issue list --label code-review --state open` + per-file
`jq` search against the three Files to Edit and one File to Create.
Expected to be run at /work Phase 0 step 7. Result will be recorded
inline in this section at plan-execution time.

Anticipated: None (DPA template is net-new; DPD §2.1b(a) carve-out is
a single clarifying sentence on a non-controversial section the
#4289 chain already validated; compliance-posture Active Items is an
append-only audit row).

If matches surface at /work Phase 0, the planner default disposition
is **Fold in** — code-review-labeled overlap on these files
strongly suggests a missed disclosure-cycle item that this DPA-
template PR should sweep in the same merge.

## Infrastructure (IaC)

Not applicable. No servers, no systemd, no Doppler secrets, no
Terraform, no DNS, no vendor accounts. Skip silently per
Phase 2.8 of the plan SKILL.

## Observability

Not applicable. No code-class files under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`. Pure-docs
PR. Skip silently per Phase 2.9 of the plan SKILL.

## Test Strategy

- **Unit:** none. No code surface.
- **Integration:** none. No DB, no API, no auth.
- **Lint / consistency:**
  - Eleventy build (AC13).
  - `legal-doc-consistency.test.ts` for dual-date Last-Updated
    regex (AC14) using the package's declared test runner per
    Phase 0 step 4.
  - `grep`-based ACs per AC1, AC2, AC4, AC5, AC6, AC7, AC9, AC10,
    AC11, AC12 (Phase 8 step 1).
- **Manual review:**
  - AC3 (Schedule 3 SCCs row enumeration) — single-page manual
    cross-check against DPD §6.4.
  - AC8 (TC_VERSION classification) — operator confirms Tier 2
    classification per `tc-version-bump-policy.md`.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Operator selects Direction A at Phase 0 ACK, regressing #4289 architecture | LOW (Direction B reasoning in Research Reconciliation is load-bearing) | Phase 0 HALT-and-respawn-CLO-CPO-panel gate prevents silent execution of Direction A |
| DPA template Schedule 2 sub-processor list drifts from DPD §4.2 over time as new sub-processors are added | MEDIUM (DPD has been amended ~12 times in 2026 per the Last-Updated chain) | Add an inline note in the DPA template recommending Schedule 2 be regenerated from DPD §4.2 at publish time (one of the three trigger events); flag for the "publish-to-`docs/legal/`" PR's checklist |
| Anthropic carve-out framing ("customer-provisioned sub-processor" under BYOK) is novel and may not survive an EU regulator's `is the Co-Member acting independently for the Owner?` test | LOW-MEDIUM | The carve-out mirrors the Anthropic Commercial Terms §C "authorized users" framing operator-attested in PR #4289 counsel review. External counsel re-review at first publish trigger will revisit. Documented as the most important operator-attestation in the DPA template's Recitals |
| DPD §2.1b(a) edit triggers an Art. 13(3) "what changed" disclosure obligation | LOW (Tier 2 clarifying, not Tier 1 material) | The carve-out clarifies an existing carve-out (DPD §4.2 footer) — it does not introduce a new processing purpose, lawful basis, or material narrowing of rights. Tier 2 classification per AC8 |
| Pre-drafted DPA goes stale (new sub-processors added, security TOMs evolve, retention windows change) before a trigger fires | HIGH if trigger waits >6 months | Compliance-posture Active Items entry explicitly says "re-draft at publish time, do NOT publish stale knowledge-base draft." Inline note in template recommends a fresh §4.2 ↔ Schedule 2 reconciliation at publish time |
| Soleur has no public `security.soleur.ai`-style sub-processor page (Vercel's `security.vercel.com` precedent). Inline Schedule 2 snapshot risks drift between DPA and reality. | MEDIUM | At Phase 7, file a tracking issue stub titled `feat(legal): public sub-processor list page (security.soleur.ai)` labeled `domain/legal` + `deferred-automation`. Cross-reference from DPA template Schedule 2 inline note + from compliance-posture entry. Re-evaluate at first DPA publish trigger |
| No SOC 2 audit report → Vercel's "audit-via-SOC-2" substitute pattern is unavailable. DPA §10 ships with operator-attested compliance posture + 24-month SOC 2 commitment. | MEDIUM | Track SOC 2 roadmap item in `compliance-posture.md` Active Items gated on first DPA execution. Commitment is binding once a DPA executes — operator must initiate SOC 2 engagement within 90 days of first DPA |
| UK IDTA not in v1 template (Vercel ships it as Schedule 5). First UK customer triggers UK IDTA amendment. | LOW (no UK customer yet) | Template's Schedule 3 §5 ("UK customers") explicitly says "UK IDTA amendment available on request — contact legal@jikigai.com." First UK trigger files an amendment PR |

## Sharp Edges

- DPA template MUST NOT list Anthropic in the main sub-processor
  schedule (Schedule 2). The operator runtime is BYOK; Anthropic is
  the user's bilateral relationship via Anthropic Commercial Terms
  §C "authorized users." Listing Anthropic as a Jikigai sub-processor
  would misrepresent the engagement at the exact moment a prospect
  is reading the document. The "Customer-provisioned sub-processors"
  subsection (Phase 3 step 3) is the load-bearing carve-out. Per the
  issue-body-paraphrase Sharp Edge: the issue body lists Anthropic
  in the enumeration; verify against DPD §4.2 ground-truth before
  copying.
- Direction confirmation gate at Phase 0 is non-negotiable. Plans
  that involve "merging, moving, or restructuring (A into B vs B
  into A)" require explicit operator ACK before proceeding. The
  issue body's proposed fix (Direction A) is a material reversal of
  the #4289 framing; Direction B is the recommended interpretation
  but Direction A is the issue-author's stated intent. CPO
  sign-off on Direction B at plan-time is sufficient for ACK-by-
  default; operator may override at Phase 0.
- Eleventy mirror MUST be updated in lockstep with the canonical DPD
  edit (Phase 5 step 4). The hero `<p>` form (`Last Updated May 22,
  2026` — no colon) AND the body `**Last Updated:**` form are both
  asserted by `legal-doc-consistency.test.ts:122-134` via separate
  regexes. Per learning
  `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`,
  the AC verifier must use a tolerant regex (`Last Updated[: *]+May 22, 2026`)
  or two separate count assertions, not a literal `Last Updated May 22, 2026`
  regex that misses the body form.
- DPD has no TC_VERSION coupling. The TC_VERSION SHA guardrail at
  `check-tc-document-sha.sh:112,187` operates ONLY on
  `docs/legal/terms-and-conditions.md`. Editing DPD does NOT require
  a TC_VERSION bump or SHA refresh — confirm by reading the
  guardrail script at Phase 6 step 3 before assuming a bump is
  needed.
- `Closes #4330` is correct here (not `Ref #4330`) because the issue's
  "definition of done" IS the artifact set this PR ships — no
  post-merge operator step. The canonical source for this distinction
  is AGENTS.md rule `wg-use-closes-n-in-pr-body-not-title-to`:
  "Use `Closes #N` ONLY on its own body line for intentional closure;
  `Ref #N` everywhere else." The `Ref` pattern applies to ops-
  remediation classes where the issue resolution happens post-merge —
  see learning `2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md`
  for the post-apply deferral case. This PR's
  `classification: deferred-automation-artifact` (not
  `ops-only-prod-write`) means `Closes` is correct.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Filled per plan SKILL §2.6.
- `tc-version-bump-policy.md` Tier 2 (clarifying) does require a SHA
  refresh when ToS is edited, but DOES NOT require a TC_VERSION bump.
  AC8 verifies that ToS is NOT edited in this PR — so the Tier 2 SHA
  refresh requirement does not apply (no SHA to refresh against an
  unchanged file).
- DPA template must carry the DRAFT disclaimer at TOP AND BOTTOM per
  `tenant-dpa-register.md:15` precedent (AC4). Single-position
  disclaimer (only top, only bottom) reads as careless.

## Definition of Done

Per issue #4330's "Definition of done" checklist, mapped to ACs:

| Issue checkbox | Plan AC | Mapped to |
|---|---|---|
| DPA template at `knowledge-base/legal/data-processing-agreement-template.md` | AC1 + AC4 + AC5 | Phases 1-4 |
| Sub-processor table enumerates Supabase + Stripe + Anthropic + Hetzner + Cloudflare; SCCs for non-EU | AC2 + AC3 | Phase 3 — **deviates from issue body**: Anthropic in customer-provisioned subsection, NOT main Schedule 2; rationale recorded in Direction B + Sharp Edges |
| ToS §3b language fix | AC6 (NOT edited) — **deviates from issue body**: Direction B keeps ToS §3b unchanged, instead clarifies DPD §2.1b(a) | Phase 5 |
| TC_VERSION bump | AC8 (NOT bumped) — **deviates from issue body**: Tier 2 clarifying classification, DPD has no TC_VERSION coupling | Phase 6 |
| Compliance-posture entry | AC9 | Phase 7 step 2 |
| Counsel-review audit at `knowledge-base/legal/audits/<YYYY-MM>-counsel-review-dpa-template-<PR>.md` | AC11 (skipped) — **deviates from issue body**: per Soleur-as-tenant-zero precedent, external counsel review fires at first publish trigger, not at knowledge-base-pre-draft time | Inline note in DPA template (Phase 4 step 12) |

## References

- Issue #4330 — `feat(legal): pre-draft customer-facing DPA template + fix ToS §3b controller-language contradiction`.
- PR #4289 — team-workspace legal scaffolding (parent — establishes
  Workspace Owner = controller framing).
- PR #4225 — team-workspace schema (parent — substrate).
- PR #4328 — AUP §5.5 softening (parent — Side Letter as optional).
- PR #4287 — workspace_member_actions audit log (sibling — PA-20).
- PR #4294 — workspace_member_removals (sibling — PA-19).
- `knowledge-base/legal/audits/2026-05-counsel-review-4289.md` — operator-
  attested counsel review for the Workspace-Owner-as-controller framing
  (load-bearing for Direction B).
- `knowledge-base/legal/tc-version-bump-policy.md` — Tier 1/2/3 classification.
- `knowledge-base/legal/tenant-dpa-register.md` — DRAFT disclaimer + first-row trigger precedent.
- `knowledge-base/legal/side-letter-template.md` — bilateral-instrument precedent + RCS Paris governing-law literal.
- `docs/legal/data-protection-disclosure.md` — §2.1b(a) edit target; §4.2 processor table = Schedule 2 ground-truth.
- `docs/legal/terms-and-conditions.md` — §3b NOT edited (Direction B).
- Learning `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md` — Eleventy hero+body Last-Updated dual-form.
- Learning `2026-05-20-github-app-installation-grant-vs-manifest-three-plane-drift.md` SE#3 + SE#6 — package.json test-runner check + knowledge-base/ link Glob-verify.
- Learning `2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` — paraphrase-without-verification gate (informed Phase 0 step 5 verbatim-DPD-read).
- Learning `2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md` — the `Ref #N` post-apply deferral pattern (not applicable to this PR; cited for completeness).
- Learning `2026-03-02-legal-doc-bulk-consistency-fix-pattern.md` — bulk legal-doc edit precedent.
- Learning `2026-03-11-third-party-dpa-gap-analysis-pattern.md` — sub-processor DPA gap-audit precedent for §6 / Schedule 2.
- Learning `2026-03-18-legal-cross-document-audit-review-cycle.md` — cross-doc consistency audit pattern; informs Phase 8 step 1 grep sweep.
- AGENTS.md hard rule `hr-weigh-every-decision-against-target-user-impact` — drove the `## User-Brand Impact` section.
- AGENTS.md workflow gate `wg-block-pr-ready-on-undeferred-operator-steps` — confirms artifact-only + AC18 = none.
- AGENTS.md workflow gate `wg-use-closes-n-in-pr-body-not-title-to` — canonical source for AC17 `Closes #4330` use.
- External: [Vercel DPA](https://vercel.com/legal/dpa) — primary template-structure precedent (13 sections + 5 schedules); informed Phases 1-4 and §6 sub-processor + §9 audit + §11 international-transfers patterns.
- External: [Linear DPA](https://linear.app/dpa) — secondary template-structure precedent (9 sections + 3 exhibits); informed §6.4 essential-sub-processor carve-out, §14.7 conflict-precedence, §7 DSR-cooperation language.
- External: [Buttondown DPA](https://buttondown.com/legal/dpa) — in-vendor-stack precedent (already cited in DPD §6.3 + Article 30 register PA-6).
- External: [GDPR Art. 28 — gdpr-info.eu](https://gdpr-info.eu/art-28-gdpr/) — canonical source for the (a)-(h) processor obligations enumeration in §5.
- External: [Commission Implementing Decision (EU) 2021/914 — SCCs](https://eur-lex.europa.eu/eli/dec_impl/2021/914/oj) — Module 2 + Module 3 incorporated by reference in Schedule 3.
- External: [ICO Article 28 contract guidance](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/accountability-and-governance/contracts-and-liabilities-between-controllers-and-processors-multi/what-needs-to-be-included-in-the-contract/) — UK-perspective reasonableness anchor.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-22-feat-dpa-template-tos-controller-fix-4330-plan.md. Branch: feat-one-shot-4330-dpa-template-tos-controller-fix. Worktree: .worktrees/feat-one-shot-4330-dpa-template-tos-controller-fix/. Issue: #4330. PR: (not yet opened). Plan reviewed (Direction B confirmed), implementation next. Phase 0 ACK gate must run before any controller-language edit.
```
