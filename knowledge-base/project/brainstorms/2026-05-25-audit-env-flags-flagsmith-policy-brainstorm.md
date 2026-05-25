---
date: 2026-05-25
topic: audit-env-flags-flagsmith-policy
status: complete
worktree: .worktrees/feat-audit-env-flags-flagsmith-policy
branch: feat-audit-env-flags-flagsmith-policy
pr: 4455
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
related_adr: ADR-038
follow_on_adr: ADR-039
related_issues: [4229, 4232, 4284, 4365, 4444]
---

# Audit ENV-vs-RUNTIME flag policy + migrate per-org flags to Flagsmith

## What We're Building

A multi-PR sequence that:

1. Closes the legal disclosure gap for Flagsmith (sub-processor, DPA, Article 30, Privacy Policy, DPD) so any code PR that increases data egress is preceded by the corresponding disclosure.
2. Extends ADR-038's Flagsmith integration with **per-org targeting** (ADR-039) — either `org-<id>` segments or a single segment with an `orgId in [...]` rule keyed on a new identity trait.
3. Adds a Supabase WORM audit shim for flag-flip operations on tenant-boundary flags.
4. Migrates `team-workspace-invite` to RUNTIME (Flagsmith) under a **dual-control architecture**: Flagsmith carries the boolean, `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` env-allowlist is **retained as defense-in-depth** (two independent failure domains).
5. Migrates `byok-delegations` to RUNTIME under the same dual-control architecture, with explicit attention to the sync-fast-path optimization in `byok-resolver.ts`.
6. Reaffirms `dev-signin` stays ENV (DCE tripwire + no per-cohort rollout need) and amends ADR-038 with a "Why these stay ENV" rule for future flags of similar shape.

## User-Brand Impact

- **Artifact:** `team-workspace-invite` + `byok-delegations` feature flags (each gates a multi-tenant capability that, if misfired, exposes cross-tenant reads/writes or yanks paying-user access mid-billing-cycle).
- **Vector:** Flagsmith segment misconfiguration, `orgId` trait misrouting, sub-processor disclosure absence, mid-billing-cycle flip without WORM audit trail.
- **Threshold:** `single-user incident`. One paying tenant seeing another tenant's invite surface, BYOK delegation misrouted to wrong grantor key, or losing delegation mid-cycle is a brand-survival event.

## Why This Approach (operator override)

All three domain leaders (CTO, CPO, CLO) independently recommended **not migrating today**, citing:
- Per-role Flagsmith segments are strictly weaker than per-org env-allowlist.
- DCE tripwire for `dev-signin`.
- Hot-path sync optimization for `byok-delegations`.
- CI workflow dependency on `vars.FLAG_TEAM_WORKSPACE_INVITE`.
- Flagsmith sub-processor undisclosed.

**Operator overrode to "full migration with new capability"** (2026-05-25). Override rationale captured here for plan-time carry-forward: the operator wants Claude-operable rollout for these flags via skill invocation rather than Doppler edits + container restarts, and is willing to fund the per-org segment work + legal disclosure work to make the migration meaningful instead of a no-op. The override resolves the leader objections by **building the missing capability** (per-org targeting, sub-processor disclosure, WORM audit shim) rather than ignoring them.

`dev-signin` is **explicitly excluded** from migration — operator override does not extend to a flag where the leader objection is "moving it actively regresses security posture" (DCE).

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Multi-PR sequence, not a single PR | Six independent failure domains (legal, capability, audit, two-flag migrations, docs); each PR has its own reviewability story. |
| 2 | PR-1 (Legal disclosure) MUST land before any PR that adds `orgId` egress to Flagsmith | GDPR Art. 4(1) + CLO findings: `orgId` is personal data; Flagsmith currently undisclosed. Disclosure cannot follow code. |
| 3 | Retain dual-control on migrated flags (Flagsmith boolean + env-allowlist) | CLO §3: two independent failure domains. Flagsmith carries skill-operable on/off; env-allowlist carries which orgs are eligible. Mis-flip on one side fails closed. |
| 4 | Per-org targeting via Flagsmith identity trait `orgId` + segment rule `orgId in [...]` (preferred) — not per-org segments | Segments-per-org would explode to N segments and require Flagsmith API segment creation per new org. Trait + single rule scales linearly with orgs at zero new segments. Architecture decision deferred to ADR-039 draft phase; both options remain open at brainstorm close. |
| 5 | WORM audit shim writes to a new Supabase ledger table for flag-flips on tenant-boundary flags | Skill conversation history is not a SOC2 CC8.1 / GDPR Art. 32(1)(d) audit log. Operator-workstation transcript can be cleared/lost. |
| 6 | `byok-delegations` migration must preserve the existing sync hot-path optimization | `byok-resolver.ts` uses a local `envOnly()` helper to skip async chains on the money path. Migration must introduce the async-aware boundary at `resolveKeyOwnerThenLease` and propagate carefully through agent-runner (2 sites), cc-dispatcher (1), and 2 Inngest functions. Naive `await getRuntimeFlag()` in the hot loop is rejected up-front. |
| 7 | `scheduled-membership-health.yml` CI workflow gets an HTTP probe to `/api/flags?role=prd` (NOT `gh variable` dual-write) | CTO §4 enumerated three options; HTTP probe is the least-bad: dual-write to GH vars would add a third sync target operator must remember; Doppler service-token reads add infra complexity. HTTP probe accepts that "Flagsmith down → workflow false-alarm" trade in exchange for a single source of truth. |
| 8 | `dev-signin` excluded from migration; reaffirm-stay PR adds explanatory comment in `server.ts` + amends ADR-038 with the partition rule | DCE story is load-bearing; future readers should not re-litigate. |
| 9 | Operator override is captured here AND in spec frontmatter (`brand_survival_threshold: single-user incident`) | Plan skill Phase 2.6 carries this forward; user-impact-reviewer agent runs at PR review per the threshold. |

## PR Sequence

| # | Title | Blocking | Scope |
|---|---|---|---|
| PR-1 | legal: Flagsmith sub-processor disclosure (DPA, Art. 30, Privacy, DPD) | Yes — blocks PR-4, PR-5 | DPA execution, `compliance-posture.md` vendor row, Article 30 PA-1 + PA-2 recipient column, Privacy Policy + DPD sub-processor list update, Flagsmith data-region / transfer-mechanism pin, tenant DPA flow-down (Art. 28(4)) update |
| PR-2 | feat(flags): ADR-039 + per-org Flagsmith targeting infrastructure | Yes — blocks PR-4, PR-5 | ADR-039 doc, extend `getRuntimeFlag` to accept `orgId` identity trait, extend `Identity` type, extend Flagsmith bootstrap skill (segments), update `soleur:flag-set-role` → split into `flag-set-role` (per-role) + `flag-set-org` (per-org) or extend with `--org` flag |
| PR-3 | feat(flags): WORM audit shim for tenant-boundary flag-flips | No (parallel with PR-2) | New `flag_audit_log` Supabase table (insert-only RLS), `soleur:flag-set-*` skills append to ledger, retention policy doc |
| PR-4 | feat(flags): migrate team-workspace-invite to RUNTIME with dual-control | Blocked by PR-1, PR-2, PR-3 | Move `team-workspace-invite` from `ENV_FLAGS` to `RUNTIME_FLAGS`, await 5 server call sites, KEEP `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` env-allowlist, update `scheduled-membership-health.yml` to HTTP-probe `/api/flags`, expand e2e to cover Flagsmith outage + misconfig cases |
| PR-5 | feat(flags): migrate byok-delegations to RUNTIME with dual-control | Blocked by PR-1, PR-2, PR-3 | Same shape as PR-4 with hot-path care: introduce async boundary at `resolveKeyOwnerThenLease`, propagate to agent-runner / cc-dispatcher / Inngest call sites, keep `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS` env-allowlist, add latency regression test |
| PR-6 | docs(flags): reaffirm dev-signin ENV-stay + ADR-038 partition rule amendment | No (parallel with PR-1 onward) | Comment in `server.ts:16-20`, ADR-038 §"Why these stay ENV" appendix, learning capture |

## Open Questions

1. **PR-2 segment model choice:** Per-org segments (N segments) vs single segment with `orgId in [...]` rule + identity trait. Decide in ADR-039 draft. Both have operational tradeoffs (segment-count explosion vs rule-string length limits in Flagsmith). Recommend prototyping in dev-segment first.
2. **PR-1 transfer mechanism for Flagsmith:** EU-US DPF status of Bullet Train Ltd? Region pinning available on current Flagsmith tier? Determines whether PA-1/PA-2 acquire a new Chapter V third-country-transfer entry.
3. **PR-3 WORM ledger schema:** Mirror existing `audit_byok_use` shape or introduce a generic `flag_audit_log` with `(flag_name, env, role_or_org_target, action, actor, before_state, after_state, ts)`?
4. **PR-4 CI probe failure semantics:** When `/api/flags?role=prd` returns 5xx during the `scheduled-membership-health` cron run, should the workflow fail-open (assume OFF, no paging) or fail-closed (assume ON, page even if we don't know)? Default recommendation: fail-closed-to-OFF (no page) because the membership-health probe is itself a diagnostic, not a gate.
5. **#4444 cross-PR coordination:** Issue #4444 (storage-object lifecycle on workspace deletion) is OPEN and "blocks TEAM_WORKSPACE_INVITE_ENABLED flag flip." PR-4 migrates the flag *mechanism* (env → runtime); it does NOT flip the flag ON. Confirm PR-4 does not implicitly resolve #4444 and that the flip-ON step remains gated on #4444 closure.
6. **`flag-set-role` skill rename:** If per-org targeting is added, does `soleur:flag-set-role` get a new sibling skill (`flag-set-org`), an extended `--target role|org` arg, or get renamed entirely? Skill-name churn has operator-memory cost; recommend extension over rename.

## Domain Assessments

**Assessed:** Engineering, Product, Legal

### Engineering (CTO)

**Summary:** Originally recommended STAY ENV for all 3 flags with file-cited rationale: DCE tripwire (`assert-dev-signin-eliminated.sh`), per-org allowlist coupling, CI workflow flag-state read (`scheduled-membership-health.yml:44`), hot-path latency (`byok-resolver.ts envOnly()`), and fallback-fidelity contract. Operator override reframes the work as **build the missing per-org capability + audit shim + legal disclosure, then migrate** rather than migrate-as-no-op. CTO recommendations preserved as binding constraints on the PR sequence (dual-control, async boundary placement, CI HTTP probe strategy, dev-signin exclusion).

### Product (CPO)

**Summary:** Originally recommended DEFER all three migrations because Flagsmith V1 per-role is strictly weaker than per-org allowlist. Per-org targeting is the load-bearing cohort axis for `team-workspace-invite` (jikigai-only friendly-org rollout) and `byok-delegations` (cross-tenant billing blast radius). Operator override accepted on basis that PR-2 builds the missing per-org capability. CPO recommendation that `dev-signin` stays ENV is **adopted unchanged**.

### Legal (CLO)

**Summary:** Flagsmith is absent from every legal artifact (`compliance-posture.md` vendor table, Article 30 register, Privacy Policy, DPD, DPA folder). ADR-038 shipped without disclosure — pre-existing gap. `orgId` is personal data under GDPR Art. 4(1) recital 26; passing it as a Flagsmith trait reclassifies Flagsmith from non-PII to pseudonymous-PII processor under PA-1 + PA-2 recipients. Dual-key gate is genuine defense-in-depth — keep env-allowlist even if boolean moves. Skill conversation history is NOT a SOC2 CC8.1 / GDPR Art. 32(1)(d) audit log; WORM shim required for tenant-boundary flag-flips. Operator override is acceptable provided PR-1 (legal disclosure) precedes any PR that increases Flagsmith data egress.

## Capability Gaps

1. **Per-org targeting in Flagsmith** — ADR-038 §"Flagsmith segment model" defines `role-prd` and `role-dev` only; no `org-<id>` segments, no identity-level overrides. Evidence: `git grep -n "segment" knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md` returns segment-model definition with explicit "No identity-level overrides in V1" language; Flagsmith bootstrap skill (`plugins/soleur/skills/flag-bootstrap/SETUP.md`) creates only the two role segments. **Owner: CTO. Why needed: load-bearing cohort axis for `team-workspace-invite` and `byok-delegations` migrations.**
2. **Flagsmith sub-processor disclosure** — Verified absent: `git grep -nri "flagsmith" knowledge-base/legal/ docs/legal/` returns zero hits across `compliance-posture.md`, `article-30-register.md`, `data-processing-agreements/`, `privacy-policy.md`, `gdpr-policy.md`, `data-protection-disclosure.md`. **Owner: CLO. Why needed: Art. 28 sub-processor disclosure obligation; reclassification trigger when `orgId` traits added.**
3. **WORM audit ledger for flag-flip operations** — No table or skill-side append exists today. Skills currently log only to conversation transcript (operator-workstation, non-retentive). Evidence: `git grep -n "flag.*audit\|audit.*flag" apps/web-platform/server/ apps/web-platform/lib/feature-flags/ plugins/soleur/skills/flag-*/` returns zero. **Owner: CTO. Why needed: GDPR Art. 32(1)(d) effectiveness-of-TOMs evidence; SOC2 CC8.1 change-management for tenant-boundary flags.**

## Session Errors

- None this session. Premise checks (ADR-038 existence, Flagsmith integration state, flag inventory) all verified before leader spawn. Pre-existing-gap finding (Flagsmith sub-processor undisclosed) is correctly attributed to ADR-038 not this brainstorm.

## References

- `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- `apps/web-platform/lib/feature-flags/server.ts:16-24` (ENV vs RUNTIME registries), `:135-156` (team-workspace two-key gate), `:162-183` (byok-delegations two-key gate)
- `apps/web-platform/server/byok-resolver.ts:117-205` (hot-path sync optimization)
- `apps/web-platform/server/team-workspace-boot.ts` (Sentry breadcrumb on gate state)
- `.github/workflows/scheduled-membership-health.yml:44` (CI workflow flag-state read)
- `knowledge-base/project/brainstorms/2026-04-16-runtime-feature-flags-brainstorm.md` (original feature-flags design)
- `knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md` (team-workspace decision #3 establishing per-org allowlist)
- `knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md` (BYOK delegations mirror-shape)
- Issue #4229 (CLOSED) — umbrella; Issue #4232 (OPEN) — BYOK delegations parent; Issue #4444 (OPEN) — storage-object lifecycle blocks flag-flip; Issue #4365 (OPEN) — byok-delegations CI parse-time assertion
