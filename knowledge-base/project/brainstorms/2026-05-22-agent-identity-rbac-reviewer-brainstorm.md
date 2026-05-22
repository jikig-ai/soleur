---
title: Identity/RBAC Reviewer Agent
date: 2026-05-22
issue: 4233
parent_issue: 4229
branch: feat-agent-identity-rbac-reviewer-4233
pr: 4288
status: brainstormed
---

# Brainstorm: Identity/RBAC Reviewer Agent

## What We're Building

A new narrow-scope review agent at `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` whose mandate is the multi-org / workspace boundary surface introduced by #4229 (team-workspace). The agent checks RLS predicates, JWT claim mapping, workspace-scoped write boundaries, session invalidation on member-state change, and SECURITY DEFINER `search_path` pinning — concerns that no existing reviewer agent owns.

Scope is **Day-1 RLS + JWT coverage only**. SSO / SAML / SCIM coverage is explicitly deferred to a `## Future: Enterprise SSO/SAML/SCIM` placeholder section until re-eval trigger (a) — Enterprise tier scoping begins — fires.

## Why This Approach

#4229 closed yesterday (2026-05-22, commit `7a922264`) and explicitly named "identity/RBAC reviewer agent" as a deferred follow-up. The team-workspace code surface is now live: `organizations`, `workspaces`, `workspace_members`, `is_workspace_member()`, `runtime_cost_state.workspace_id`. The `TEAM_WORKSPACE_INVITE_ENABLED` flag is default OFF in prd but the substrate is a single Doppler flip away. Without a dedicated reviewer, the load-bearing checks for this surface (RLS predicate uses `is_workspace_member()`, write sentinel passes, JWT `org_id` claim consumed) rely on operator vigilance per PR.

**Why a new agent (Approach A) over extending security-sentinel (Approach B):** the plugin convention is narrow agents per cross-cutting concern (`data-integrity-guardian`, `observability-coverage-reviewer`, `agent-native-reviewer`, `user-impact-reviewer`). `security-sentinel` is the OWASP-generalist; auth/sessions are one of its ten chapters. Multi-org boundary integrity is a distinct review surface — it's about *who can read what across organizations*, not *is this auth implementation OWASP-compliant*. Splitting now is cheaper than splitting later when re-eval trigger (b) — a multi-org permission bug ships — forces the split under incident pressure.

**Why narrow scope (Day-1, not Enterprise upfront):** Enterprise tier isn't scoped yet. Building SSO/SAML/SCIM coverage today produces checklist items that sit unused for unknown weeks/months. YAGNI applies.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | New agent file, not security-sentinel extension | Plugin convention (narrow agents); avoids security-sentinel description-budget growth; splits cleanly when multi-org bug eventually shows |
| 2 | Day-1 RLS/JWT scope only | Enterprise tier not scoped; YAGNI; placeholder section preserves growth path |
| 3 | No pointer stub in security-sentinel (Approach C rejected) | Two files to keep in sync for marginal habit-correction; `/review` SKILL.md dispatch handles routing |
| 4 | `/review` skill wires identity-rbac-reviewer on diffs touching: `apps/web-platform/supabase/migrations/`, `lib/supabase/tenant.ts`, `app/api/.*/workspace`, RLS policy files | Targeted dispatch; avoids agent spam on unrelated PRs |
| 5 | Boundary text in agent description: "multi-org/workspace boundary integrity; see security-sentinel for OWASP-generic auth/sessions" | Mirrors `data-integrity-guardian` ↔ `gdpr-gate` boundary pattern in `plugins/soleur/skills/review/SKILL.md` |

## Day-1 Checklist (carry into spec FRs)

1. Every RLS policy on a `workspace_id`-bearing table (`conversations`, `messages`, `kb_files`, `kb_chunks`, `runtime_cost_state`, `scope_grants`, `attachments`) references `is_workspace_member()` — or documents why not.
2. Every `INSERT` / `UPDATE` to a workspace-scoped table passes the write-boundary sentinel (per `hr-write-boundary-sentinel-sweep-all-write-sites`).
3. JWT `org_id` claim is set on org-switch and consumed in every middleware / route that filters by workspace.
4. Session invalidation fires on `workspace_member` row delete or role change.
5. SECURITY DEFINER functions touching org/workspace data have `search_path = pg_temp` pinned (per `cq-pg-security-definer-search-path-pin-pg-temp`).
6. `workspace_member_attestations` writes verify the attester actually has owner-or-admin role at write time (not just attestation time).

## User-Brand Impact

`USER_BRAND_CRITICAL=true`. Threshold: `single-user incident`. Vectors the agent's quality directly governs:

1. **Cross-tenant data read.** Mis-written RLS predicate (e.g., uses `auth.uid()` directly instead of `is_workspace_member()`) → org A reads org B's KB/conversations/messages.
2. **Cross-tenant data write.** Write site bypasses the sentinel (per `hr-write-boundary-sentinel-sweep-all-write-sites`) → row inserted under wrong `workspace_id`.
3. **Stale session privilege.** Member is removed from a workspace but their existing JWT still passes `is_workspace_member()` until expiry → unauthorized reads/writes during the window.
4. **JWT claim impersonation.** Org-switch endpoint accepts client-supplied `org_id` without verifying membership → privilege escalation to any org the user names.

The agent at `/review` dispatch is the load-bearing gate for these vectors. Plan inherits this section verbatim.

## Open Questions

| # | Question | Resolution path |
|---|----------|-----------------|
| Q1 | Should the agent also flag `auth.uid()` direct usage in RLS as an anti-pattern (force `is_workspace_member()`)? | Resolve at plan time — depends on whether ANY legitimate `auth.uid()`-direct RLS use case remains post-#4229. Default: flag with `info` severity. |
| Q2 | Does the agent need its own `--dry-run` mode separate from `/review`? | No. The agent is dispatched by `/review`; running it standalone is rare. Skip until requested. |
| Q3 | Should the placeholder `## Future: Enterprise SSO/SAML/SCIM` section be empty or carry a stub checklist? | Empty placeholder + 1-line note pointing to re-eval trigger (a). A stub checklist invites premature work. |

## Non-Goals

- SSO / SAML / SCIM coverage (deferred until Enterprise tier scoping begins).
- Modifying security-sentinel.md (Approach B/C rejected).
- A standalone CLI / skill — the agent runs only via `/review` dispatch.
- BYOK key-isolation review (`byok_delegations` is a separate deferred issue; the reviewer flags workspace-keyed access patterns only, not cryptographic isolation).
- Static analysis tooling (semgrep-sast already covers rule-based pattern matching; this agent is LLM-based review).

## Domain Assessments

**Assessed:** Engineering (CTO scope, self-assessed by orchestrator)

### Engineering (CTO)

**Summary:** Narrow review agent matching the existing single-concern reviewer pattern (`data-integrity-guardian`, `agent-native-reviewer`, `observability-coverage-reviewer`). Day-1 scope is bounded; description-line boundary against security-sentinel is straightforward. Build cost: ~1 agent file + 1 `/review` SKILL.md dispatch entry + 1 plugin manifest description-line. ~30-60 min effort. No new infrastructure, no new tests beyond agent-file smoke (existing convention).

### Product (CPO)

**Summary:** No direct user-facing surface — internal tooling for engineering quality. CPO sign-off not required. Agent's failure mode (false-negative review missing a multi-org bug) is the user-impact concern, already captured under `## User-Brand Impact`.

### Legal (CLO)

**Summary:** GDPR Art. 32 (security of processing) treats RBAC review as a documented technical safeguard. Existence of a dedicated reviewer is itself defensible evidence; absence is not load-bearing for compliance because security-sentinel + manual review cover the OWASP-generic surface. No CLO sign-off required for the agent itself; CLO sign-off will be required when reviewer's first finding type involves data-subject rights (DSAR routing, deletion) — already a separate deferred issue.

## Capability Gaps

None. All required infrastructure exists:
- `is_workspace_member()` SECURITY DEFINER helper (migration 053)
- Write-boundary sentinel pattern (`hr-write-boundary-sentinel-sweep-all-write-sites`)
- `/review` skill dispatch mechanism
- Plugin agent-registration convention
