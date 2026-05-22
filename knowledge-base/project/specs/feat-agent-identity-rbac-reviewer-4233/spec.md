---
title: Identity/RBAC Reviewer Agent
status: specified
issue: 4233
parent_issue: 4229
brainstorm: knowledge-base/project/brainstorms/2026-05-22-agent-identity-rbac-reviewer-brainstorm.md
branch: feat-agent-identity-rbac-reviewer-4233
pr: 4288
date: 2026-05-22
lane: cross-domain
brand_survival_threshold: single-user incident
requires_clo_signoff: false
requires_cpo_signoff: false
requires_cto_signoff: true
requires_adr: false
---

# Spec: Identity/RBAC Reviewer Agent

## Problem Statement

#4229 (team-workspace multi-user) closed on 2026-05-22 (commit `7a922264`), introducing first-class `organizations`, `workspaces`, `workspace_members` primitives, the `is_workspace_member()` SECURITY DEFINER helper, `runtime_cost_state.workspace_id`, RLS rewrites on seven tables, and a feature-flagged invite UI. The `TEAM_WORKSPACE_INVITE_ENABLED` flag is default OFF in prd but the substrate is live.

No existing review agent in `plugins/soleur/agents/engineering/review/` owns the multi-org boundary surface. `security-sentinel` is the OWASP-generalist; auth/sessions are one of its ten chapters. Multi-org-specific concerns — RLS predicate uses `is_workspace_member()`, write sites pass the workspace-keyed sentinel, JWT `org_id` claim is consumed correctly, session invalidation on member-state change — fall through.

This issue (#4233) was carried forward from the 2026-04-27 small-team brainstorm and re-affirmed in #4229's brainstorm (2026-05-21) as a deferred follow-up. Re-eval criteria from the issue body: when Enterprise tier scoping begins OR when a multi-org cross-org permission bug ships. The first hasn't fired; the second hasn't fired either — but the substrate is one Doppler flip away from being load-bearing in prd. Building the reviewer before the flag flips is cheaper than splitting `security-sentinel` under incident pressure later.

## Goals

- G1: New review agent at `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` covering Day-1 RLS + JWT concerns.
- G2: Agent dispatched by `/review` on diffs touching the identity/workspace surface.
- G3: Description-line boundary against `security-sentinel` is unambiguous (operators do not have to guess which agent to invoke).
- G4: Placeholder `## Future: Enterprise SSO/SAML/SCIM` section preserves growth path without inviting premature work.
- G5: Plugin manifest entry added; release-docs counts updated.

## Non-Goals

- SSO / SAML / SCIM coverage (deferred until Enterprise tier scoping begins — re-eval trigger (a)).
- Modifications to `security-sentinel.md` (Approaches B and C from brainstorm rejected).
- Standalone CLI / skill invocation — agent runs only via `/review` dispatch.
- BYOK key cryptographic-isolation review (`byok_delegations` is a separate deferred issue).
- Static analysis tooling (semgrep-sast already covers rule-based pattern matching).

## Functional Requirements

- **FR1.** Agent file frontmatter declares `name: identity-rbac-reviewer`, `model: inherit`, and a `description:` that names the boundary against `security-sentinel`.
- **FR2.** Agent body contains a checklist covering:
  - FR2.1: Every RLS policy on a `workspace_id`-bearing table references `is_workspace_member()` (or documents why not).
  - FR2.2: Every `INSERT` / `UPDATE` to a workspace-scoped table passes the write-boundary sentinel (per `hr-write-boundary-sentinel-sweep-all-write-sites`).
  - FR2.3: JWT `org_id` claim is set on org-switch and consumed in every middleware / route that filters by workspace.
  - FR2.4: Session invalidation fires on `workspace_member` row delete or role change.
  - FR2.5: SECURITY DEFINER functions touching org/workspace data have `search_path = pg_temp` pinned (per `cq-pg-security-definer-search-path-pin-pg-temp`).
  - FR2.6: `workspace_member_attestations` writes verify the attester has owner-or-admin role at write time.
- **FR3.** Agent body contains an empty `## Future: Enterprise SSO/SAML/SCIM` section with a one-line note pointing to re-eval trigger (a).
- **FR4.** `plugins/soleur/skills/review/SKILL.md` dispatch table includes a row routing identity-touching diffs to `identity-rbac-reviewer`. Dispatch pattern matches diffs touching: `apps/web-platform/supabase/migrations/`, `lib/supabase/tenant.ts`, `app/api/**/workspace*`, RLS policy file changes.
- **FR5.** Plugin manifest (`plugins/soleur/plugin.json`) description includes the new agent count.
- **FR6.** `plugins/soleur/README.md` agent table includes the new row.

## Technical Requirements

- **TR1.** Agent file follows the narrow-agent template — model on `plugins/soleur/agents/engineering/review/data-integrity-guardian.md` for shape and length (~80–100 lines).
- **TR2.** Description-line word count obeys `cq-skill-description-budget-headroom` cumulative budget; verify with the standard SKILL.md description-budget one-liner.
- **TR3.** Dispatch glob added to `/review` SKILL.md must coexist with existing dispatch rules (no overlap loss; `security-sentinel` still fires on the same diffs).
- **TR4.** Boundary text in description mirrors the `data-integrity-guardian` ↔ `gdpr-gate` convention documented in `plugins/soleur/skills/review/SKILL.md` §boundaries.

## Acceptance Criteria

- [ ] AC1: `plugins/soleur/agents/engineering/review/identity-rbac-reviewer.md` exists with required frontmatter (name, description, model) and the 6-item Day-1 checklist (FR2.1–FR2.6).
- [ ] AC2: Agent description carves explicit boundary against `security-sentinel`; passes description-budget check.
- [ ] AC3: `plugins/soleur/skills/review/SKILL.md` dispatch wires the new agent on identity-touching globs (FR4).
- [ ] AC4: `## Future: Enterprise SSO/SAML/SCIM` section present, empty body, 1-line re-eval note.
- [ ] AC5: Plugin manifest agent count incremented; README table updated.
- [ ] AC6: `bash scripts/test-all.sh` passes (no regression).
- [ ] AC7: Eleventy docs build succeeds with new agent counted in build output.

## User-Brand Impact

`USER_BRAND_CRITICAL=true`. Threshold: `single-user incident`.

The agent itself is internal tooling, but its quality directly governs whether the following vectors get caught at PR review:

1. **Cross-tenant data read** — mis-written RLS predicate uses `auth.uid()` directly instead of `is_workspace_member()`; org A reads org B's KB/conversations/messages.
2. **Cross-tenant data write** — write site bypasses the workspace-keyed sentinel; row inserted under wrong `workspace_id`.
3. **Stale session privilege** — workspace_member removed but their existing JWT still passes `is_workspace_member()` until expiry; unauthorized reads/writes during the window.
4. **JWT claim impersonation** — org-switch endpoint accepts client-supplied `org_id` without verifying membership; privilege escalation to any org the user names.

False-negative review (the agent passes a PR that ships one of these) IS the brand-survival event. The `user-impact-reviewer` agent at PR review remains the load-bearing gate; this agent adds defense-in-depth at the diff-level review.

## Domain Review

### Engineering (CTO) Gate

- **Decision:** approved (self-assessed; matches existing narrow-agent convention)
- **Agents invoked:** code-architect (self), implicit via brainstorm Phase 0.5 (lean — single-concern internal tooling)
- **Skipped specialists:** legal-compliance-auditor (GDPR Art. 32 review-tooling existence is defensible at agent-level; PR-time CLO review remains via existing gates)
- **Notes:** No new infrastructure; ~30–60 min implementation effort; description-budget headroom must be verified at plan time.

### Product/UX Gate

- **Decision:** N/A — no user-facing surface.

### Legal (CLO) Gate

- **Decision:** N/A — internal review tooling; no DSAR/PII/contractual surface modified.

## Risks

- **R1.** Description-budget overrun: the new agent's description-line plus the boundary text could push cumulative SKILL/AGENT descriptions over the `cq-skill-description-budget-headroom` ceiling. Mitigation: measure at plan time per `cq-skill-description-budget-headroom`; sibling-trim if < 10 words headroom.
- **R2.** Dispatch overlap: if `/review` SKILL.md dispatch globs cause `security-sentinel` AND `identity-rbac-reviewer` to BOTH fire on the same diff, operator gets duplicate/conflicting findings. Mitigation: dispatch table assigns identity-touching diffs to identity-rbac-reviewer first; security-sentinel still fires for OWASP-generic concerns. Document the dispatch order in `review/SKILL.md`.
- **R3.** Premature Enterprise growth: a future contributor sees the `## Future: Enterprise SSO/SAML/SCIM` placeholder and fills it before re-eval trigger (a) fires. Mitigation: the placeholder note explicitly cites the re-eval criterion and asks contributors to file an issue first.

## References

- Issue: #4233
- Parent issue: #4229 (team-workspace multi-user, closed 2026-05-22, commit `7a922264`)
- Prior brainstorm references:
  - 2026-04-27 small-team brainstorm (first deferral)
  - `knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md` (re-affirmation)
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-agent-identity-rbac-reviewer-brainstorm.md`
- Boundary precedent: `data-integrity-guardian` ↔ `gdpr-gate` in `plugins/soleur/skills/review/SKILL.md` §boundaries
- Rule references: `hr-write-boundary-sentinel-sweep-all-write-sites`, `cq-pg-security-definer-search-path-pin-pg-temp`, `cq-skill-description-budget-headroom`, `hr-weigh-every-decision-against-target-user-impact`
