---
date: 2026-05-21
status: committed
decision: build-internal-dogfood-plus-flagged-invite-ui
brand_survival_threshold: single-user incident
lane: cross-domain
supersedes:
  - knowledge-base/project/brainstorms/2026-04-27-small-team-expansion-brainstorm.md
related:
  - knowledge-base/project/brainstorms/2026-04-18-verify-workspace-isolation-brainstorm.md
  - knowledge-base/product/roadmap.md
  - knowledge-base/product/business-validation.md
  - knowledge-base/product/pricing-strategy.md
  - knowledge-base/finance/cost-model.md
  - knowledge-base/legal/compliance-posture.md
closes_issues:
  - 2972
---

# Team-Workspace Multi-User Support Brainstorm

## What We're Building

A first-class `organizations` primitive in the Soleur webapp that lets two-or-more authenticated users share one workspace under a common organization, plus a feature-flagged invite UI gated to allowlisted orgs (jikigai initially). Two seed members on day one: Jean (founder) and Harry (intern), collaborating on Soleur itself.

This is an **additive parallel ICP** (solo founders + small teams as named segments), not a pivot. The solo-founder positioning, pricing page, and homepage stay unchanged.

## Why Now (and What Changed Since 2026-04-27)

The 2026-04-27 small-team brainstorm deferred all team-tier engineering to "after validation gate fires." Two things changed:

1. **Internal dogfood need is real.** Harry was onboarded as an intern. Founder + intern collaborating on building Soleur is a concrete, immediate use case — operationally, Soleur cannot dogfood multi-user shape if multi-user shape doesn't exist.
2. **Prospect signal firmed up.** The 10-person prospect from #2972 came back with "most likely needs Soleur for a team of 10 users." This partially fires the #2972 commit-gate (product-shape clause: "Prospect product shape is 'multi-user'"). The LOI clause is not strictly met — operator override based on prospect-shape signal + dogfood urgency.
3. **Tenant-isolation seam now exists.** Migrations 038 (RLS schema), 043 (tenant_deploy_audit), 045 (attachments storage RLS), `lib/supabase/tenant.ts`, and #1450 / MU3 (sandbox isolation) all shipped since 2026-04-27. The 1-2 week RLS-migration estimate from the prior CTO scope shrinks to 7-10 days for the organizations primitive.

## User-Brand Impact

`USER_BRAND_CRITICAL=true` — operator (Jean) selected all three failure modes in Phase 0.1 framing.

**Artifact at risk:** Jean's Soleur workspace KB, chat history, BYOK key material, and Anthropic cost ledger.

**Vectors named:**

1. **Cross-user KB/chat leak** — current RLS predicates are `auth.uid() = user_id`. A naive `is_workspace_member()` helper that's broader than intended exposes every row Jean owns to Harry, and (worse) potentially across orgs if the predicate is mis-written. **Load-bearing risk per CLO + CTO.**
2. **BYOK key exposure / silent cost shift** — Harry running an agent in Jean's workspace must NOT silently debit Jean's Anthropic key with no UI surface. CTO's load-bearing brand risk. Mitigation: per-user BYOK keys, workspace-shared cost ledger; explicit `byok_delegations` opt-in if Jean wants to fund Harry's runs.
3. **Multi-tenant boundary bleed** — every code path that assumes `workspace.owner_id === session.user_id` (`server/workspace.ts`, `server/agent-runner.ts`, audit context, BYOK key derivation) becomes an authorization bug rather than an invariant once a second principal exists. Required: write-boundary sentinel sweep before merge per `hr-write-boundary-sentinel-sweep-all-write-sites`.

**Threshold:** `single-user incident` — one mis-written RLS predicate that leaks Jean's KB to a future workspace member is brand-survival territory.

## Domain Assessments

**Assessed:** Product (CPO), Engineering (CTO), Legal (CLO), Finance (CFO). Marketing, Sales, Operations, Support not spawned (scope is internal/flagged; positioning is unchanged; no public surface ships).

### Product (CPO)

**Summary:** Ship internal-only, hard-gated to `@jikigai.com` domain. NOT visible in UI for external users until #2972's external-validation gate fires. The founder-dogfood need is operationally real and product-coherent ("your founding team from 1 to 2-3"), but shipping a visible "Share workspace" CTA before workspace-keyed RLS + customer DPA + member-departure flows exist will create churn-poison expectations. **Operator overrode to "schema + invite UI behind feature flag"** — accepted on the basis that the feature flag is OFF in prd and only flipped after legal scaffolding (Side Letter + ToS bump) lands.

### Engineering (CTO)

**Summary:** Workspace == userId today (`server/workspace.ts:67` → `join(getWorkspacesRoot(), userId)`). No `workspace_id`/`tenant_id` primitive exists. Operator chose first-class organizations table (~7-10 days, NOT 1-2 weeks because tenant.ts/RLS work shipped since 2026-04-27). Architecture: `organizations(id, name, owner_user_id, ...)` + `workspaces(id, org_id, ...)` + `workspace_members(workspace_id, user_id, role)` join table with a `SECURITY DEFINER` `is_workspace_member()` helper (pin `search_path = pg_temp`). RLS rewrite on ~8 user-keyed tables (conversations, messages, kb_*, byok_keys, runtime_cost_state, scope_grants, attachments). BYOK stays per-user (HKDF keyed on userId); cost ledger gets a `workspace_id` column. Filesystem: `/workspaces/<workspace_id>`, symlink existing `/workspaces/<userId>` → `/workspaces/<workspace_id>` for backward compat. Sandbox MU3 re-run narrowed: tier 4 (cross-workspace) still load-bearing; tiers 1-3 collapse inside a workspace by design. Audit log deferred to first external workspace. **ADR required** before merge (introduces foundational data-model primitive).

### Legal (CLO)

**Summary:** Internal-use does NOT exempt from GDPR Arts. 12-22; Harry as a data subject retains rights even as an employee/intern. Non-negotiable scaffolding BEFORE flag flips ON, even for jikigai-only:

1. ToS amendment (TC_VERSION 2.1.0 → 2.2.0) adding §"Workspace Members" — workspace owner is controller; members access under owner's account; owner indemnifies.
2. AUP §5.5 — owner attestation that all invitees are under employment/contractor agreement until customer-DPA ships.
3. In-product invite-time checkbox: "I confirm this member is my employee or contractor under written agreement," captured to `workspace_member_attestations` WORM table (scope_grants pattern).
4. Internal Side Letter (Jean→Harry): confidentiality + IP assignment + workspace-activity-logged acknowledgement.
5. DPD §2.3 one-liner disclosing "workspace co-members" as a data category.

Anthropic Commercial Terms §C "authorized users" is satisfied by Side Letter (4). No new sub-processor; Harry's prompts process under Jean's existing Anthropic key under Jean's existing DPA.

Member-departure DSAR: Harry retains Art. 15/17/20 over his identifiable rows post-departure. Existing DSAR endpoint (#3637, in-progress) is keyed to founder_id — will not find Harry's rows after departure unless workspace_member rows carry subject_id. **Filed as Capability Gap.**

### Finance (CFO)

**Summary:** **GO**, with budget caveat. Per-user marginal COGS ≈ $1.50/mo at current architecture; Harry is 1 of 11 CX33 slots; well within Supabase Pro / Hetzner headroom. No vendor seat triggers (Supabase Pro covers, Doppler Developer is free, Anthropic via BYOK has no per-seat). Engineering ceiling is ≤10 days before re-consult; operator's chosen scope (organizations table + invite UI + roles) is ~10-13 days — **breaches ceiling by 0-3 days; flagged for plan-skill confirmation.** Pricing-page leakage risk handled by feature flag OFF in prd + no `/pricing` change. Revised kill criterion (replaces #2972's 2-quarter clock): revisit when (a) first solo-founder paying customer lands AND (b) ≥1 external team prospect requests multi-user during invite-UI beta, whichever later.

## Capability Gaps

1. **DSAR routing across workspace members.** `#3637` DSAR endpoint is keyed on `founder_id`. When Harry leaves, his Art. 15/17/20 requests must be served by querying `workspace_member_id`, not `founder_id`. Evidence: grep `apps/web-platform/server/dsar-reauth.ts` for `founder_id` and `user_id` parameter shape. (CLO.)
2. **Workspace-member-scenario test suite.** Existing `sandbox-isolation.test.ts` covers cross-user, not multi-user-same-workspace. Add one MU3 case: two users same workspace see same files; two users different workspaces see nothing. (CTO.)
3. **`byok_delegations` table primitive.** If Jean funds Harry's runs, need an explicit `byok_delegations(grantor_user_id, grantee_user_id, expires_at, revoked_at)` table. Out of dogfood scope but design must not preclude. (CTO.)
4. **No identity/RBAC reviewer agent.** Carried forward from 2026-04-27: no agent owns auth/sessions/RBAC cross-cutting concerns. Recommend `security-sentinel` extension or new agent before external small-team onboarding.

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Use case framing | Internal dogfood (Jean + Harry) + flagged invite UI as foundation for future external small-team support | Operator override of CPO "no UI" recommendation; prospect signal from #2972's 10-person prospect firmed product-shape clause |
| 2 | Membership model | First-class `organizations` table + `workspaces` + `workspace_members` | Operator chose heaviest option to get the right primitive instead of patching twice. Defensible if validation gate is on 6-month horizon |
| 3 | UI scope this PR | Schema + invite UI behind `TEAM_WORKSPACE_INVITE_ENABLED` feature flag, OFF in prd, ON only for jikigai org | Operator override; flag is the brake against churn-poison; legal scaffolding must land BEFORE flag flips ON |
| 4 | BYOK model | Per-user keys (HKDF keyed on userId, unchanged), workspace-shared cost ledger (add `workspace_id` to `runtime_cost_state`) | CTO recommendation; clean accountability; prevents silent cost-shift to Jean |
| 5 | BYOK delegations | Not in this PR; design must not preclude `byok_delegations` table | Out of dogfood scope; deferred |
| 6 | Roles | Owner + Member (2 roles) | Dogfood minimum; defer Admin/Viewer until external team or revenue. Schema-compatible-later (role is a text column) |
| 7 | Multi-org membership | Many-to-many: one user can belong to N orgs | Cheaper now (~+0.5d); future-friendly for agency/consultant use case; schema-incompatible-later means rebuild |
| 8 | Filesystem | `/workspaces/<workspace_id>`, symlink legacy `/workspaces/<userId>` → workspace_id | Backward-compat without breaking active sandboxes |
| 9 | Sandbox MU3 | Re-run narrowed: tier 4 (cross-workspace) is load-bearing; tiers 1-3 collapse inside a workspace by design | New `sandbox-isolation.test.ts` case |
| 10 | Audit log | Defer for dogfood; required at first external workspace | Jean+Harry trust each other; `tenant_deploy_audit` covers deploy boundary |
| 11 | Legal sequencing | Side Letter + ToS 2.2.0 + AUP §5.5 + attestation checkbox + DPD §2.3 line MUST land before flag flips ON (parallel-tracked) | CLO non-negotiable |
| 12 | #2972 relationship | Close #2972 as superseded by this work | Operator: prospect signal firmed; dogfood + flagged-UI IS the validation step; new kill criterion supersedes the 2-quarter clock |
| 13 | Pricing page | No change. Stays solo-positioned until first external team customer | CFO: avoids "free team tier" signal |
| 14 | Homepage | No change. Single brand, single mission line | Carried from 2026-04-27 |
| 15 | ADR | Required: introduces `workspace_members` foundational primitive. Run `/soleur:architecture create` before migration merges | CTO |
| 16 | Budget override | Operator's chosen scope (~10-13 days) exceeds CFO's ≤10-day ceiling | Acknowledged; plan skill must confirm at Phase 2.6 |

## Non-Goals

- SSO/SAML/SCIM (Enterprise tier; deferred per 2026-04-27)
- Per-domain RBAC ACLs (Enterprise; deferred)
- Customer-facing DPA template (parallel CLO track; not gated by this PR's flag-OFF state)
- Audit log table (deferred to first external workspace)
- `/teams` landing page (until 5+ paying team logos)
- Pricing-page tier toggle (until validation evidence justifies)
- Public "share workspace" CTA on solo-positioned surfaces
- SOC 2 (Trust Center stub already covers per 2026-04-27)
- Container-per-workspace isolation (Phase 4.6 / #673; orthogonal)
- Plan-based agent concurrency enforcement (Phase 4.7 / #1162; orthogonal)

## Open Questions

1. **`feat-workspace-reconciliation-4224` collision.** Active worktree may touch the `/workspaces/<userId>` invariant. Sequence after that lands, or coordinate. (Engineering, before plan-skill phase.)
2. **`feat-pr-d-attachments-storage-tenant-rls` collision.** Migration 045's `is_message_owner` predicate must be extended, not replaced. Plan must reference its exact shape.
3. **Org-switcher UI** when a user belongs to multiple orgs. In scope (FR6) but UI shape (header dropdown vs. settings switch) deferred to plan.
4. **`workspace_member_attestations` WORM shape.** CLO referenced scope_grants pattern (PR-G #3984); plan must lift the exact column set.
5. **Member-departure DSAR routing.** Capability Gap #1 — extend `dsar-reauth.ts` to query `workspace_member_id`. Filed as deferred follow-up; not gated by this PR.
6. **Sentinel sweep checklist.** Plan must enumerate every `owner_id === session.user_id` site and convert to `is_workspace_member()`. Pre-merge gate.

## Cross-Domain Dependencies

| From | To | Dependency |
|---|---|---|
| CLO | CTO | `workspace_member_attestations` table + attestation-time enforcement in invite endpoint |
| CLO | CMO | Trust Center note on org/workspace separation if/when public docs ship (not gated by this PR) |
| CLO | legal-document-generator | ToS 2.2.0 + AUP §5.5 + Side Letter template + DPD §2.3 edit (parallel track) |
| CTO | feat-workspace-reconciliation-4224 | Sequence-after coordination |
| CTO | #3815 (multi-tenant Sentry DPA) | The `workspace_id` primitive lands here; Sentry per-tenant project keying becomes possible after |
| CTO | #3723 (multi-tenant deploy substrate) | Same — deploy-substrate work can lift `org_id`/`workspace_id` from this migration |
| CTO | #2778 (projects-table refactor, post-MVP) | Compatible; no merge conflict |
| CFO | COO | Add to expense ledger only if/when external workspace lands (no entry today) |

## Out of Scope for This Brainstorm

- Exact RLS predicate text — plan-skill work
- Exact ToS 2.2.0 wording — legal-document-generator after this brainstorm
- ADR text — `/soleur:architecture create` after plan
- Invite-UI visual design — ux-design-lead after plan, if needed

## Session Errors

None this session. (No mis-routed agents, no false-negative file checks surfaced post-spawn.)

## Productize Candidate

None identified. Multi-tenant primitives are app-domain work, not a reusable skill/agent shape.
