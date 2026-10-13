# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-02-fix-member-removal-and-byok-cap-update-plan.md
- Status: complete (amended post-plan with Problem 3 — Members table column alignment — per operator follow-up)

### Errors
None. (Live-DB SQLSTATE repro deferred to /work Phase 0 — requires interactive Supabase OAuth; static evidence + mig-092 precedent conclusive on mechanism.)

### Decisions
- Problem 1 root cause is NOT PR #4779: `remove_workspace_member` resolves owner-gate via bare `auth.uid()` (always NULL under `createServiceClient()`), raising 28000 → rpc_failed → 500 toast. Fix mirrors migration 092's `transfer_workspace_ownership` COALESCE(p_caller_user_id, auth.uid()) + service_role-only grant.
- Problem 2 (BYOK cap update post-join): DB already supports WORM Shape-3 cap-update flip (064:332-353); needs new `update_byok_delegation_cap` RPC (mig 094, impersonation-guarded grant/revoke pattern — GRANT to authenticated+service_role) + PATCH /api/workspace/delegations + inline editable cap in DelegationToggle.
- Problem 3 (added post-plan): ROLE/FUNDED data cells in team-membership-list.tsx don't match their `text-center` header cells; fix is to center the badge/control cells under their headers without changing shared grid templates. Pure presentation; QA-screenshot verified (AC-ALIGN).
- Member RPCs → service_role-only (forgeable override, no internal guard); BYOK cap RPC → authenticated+service_role (internal impersonation guard). Phase order load-bearing: migration → TS callers → feature → alignment → tests.
- Threshold = single-user incident; requires_cpo_signoff: true.

### Components Invoked
- soleur:plan, soleur:gdpr-gate, soleur:deepen-plan (via planning subagent)
- Post-plan operator amendment: added Problem 3 (Members table alignment) — AC-ALIGN, Phase 4.5, files/test-scenarios updated
