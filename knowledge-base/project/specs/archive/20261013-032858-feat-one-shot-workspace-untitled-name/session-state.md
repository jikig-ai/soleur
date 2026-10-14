# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-01-fix-org-name-null-untitled-switcher-plan.md
- Status: complete

### Errors
- IaC-routing PreToolUse hook initially blocked the plan Write (flagged "operator runs"/"manual" prose). Resolved by reviewing Phase 2.8 (pure code change, no new infra) and embedding the documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out. No other errors.

### Decisions
- Reframed lever (a): the invite flow adds a member to the inviter's existing (NULL-name) org via p_workspace_id — it does NOT create an org. So "capture name in invite flow" became "prompt the owner to name their existing org at first-invite," plus a generic non-NULL trigger default. Signup/onboarding name capture made a Non-Goal (no onboarding flow or TS signup fallback exists to hook into).
- No NOT NULL constraint on organizations.name — enforce non-NULL at trigger + backfill + app layers, per migration 053's contract (preserves single-statement backfill invariant).
- RPC-only write path: add rename_organization (migration 091) as SECURITY DEFINER plpgsql with auth.uid() owner-gate, mirroring 075_transfer_workspace_ownership.sql; no new RLS UPDATE policy on organizations.
- Privacy: backfill defaults NULL names to a generic non-PII label ('My Workspace'), NOT owner email — org name is peer-visible via orgs_select_for_members, so email would leak the owner's address.
- Threshold single-user incident → requires_cpo_signoff: true; Product/UX gate is BLOCKING and carried forward to review.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Inline gates: code-review overlap, GDPR (advisory), IaC routing (acked), precedent-diff, verify-the-negative, User-Brand Impact, Observability (5/5), PAT-shaped scan
