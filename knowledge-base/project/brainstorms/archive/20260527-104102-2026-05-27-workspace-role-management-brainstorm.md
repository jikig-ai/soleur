---
date: 2026-05-27
status: committed
decision: single-owner-strict-with-dedicated-transfer-rpc
brand_survival_threshold: single-user incident
lane: cross-domain
parent: knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md
related:
  - knowledge-base/project/brainstorms/2026-05-22-workspace-member-actions-audit-brainstorm.md
  - apps/web-platform/supabase/migrations/053_organizations_and_workspace_members.sql
  - apps/web-platform/supabase/migrations/063_workspace_member_actions.sql
  - apps/web-platform/supabase/migrations/067_workspace_member_revocation_lookup.sql
closes_issues:
  - 4520
depends_on:
  - 4518
---

# Workspace Role Management + Ownership Transfer Brainstorm

## What We're Building

Role management UI and ownership transfer flow for the team workspace Members tab. Two capabilities:

1. **Role change** — workspace owner can change a member's role (owner ↔ member) via the existing `update_workspace_member_role` RPC (migration 067, already built on `feat-team-workspace-members-tab` branch).
2. **Ownership transfer** — atomic transfer of workspace ownership from current owner to a target member, via a new `transfer_workspace_ownership` SECURITY DEFINER RPC that dual-writes `workspace_members.role` AND `organizations.owner_user_id` in a single transaction.

Enforces **single-owner strict** model: exactly one owner per workspace at all times. Transfer is an atomic swap, not a promote-then-demote sequence.

## Why This Approach

The parent brainstorm (2026-05-21) established a two-role model (`owner` + `member`) and deferred role management to the first workspace with 3+ members. #4516 builds the Members tab UI and invite/remove flows. This issue (#4520) adds the remaining role mutation capabilities.

**Single-owner strict** was chosen over multi-owner because:
- Simpler invariant — exactly one owner, no ambiguity about "who is THE owner"
- Clean GDPR controller designation — one owner = one controller per workspace
- `organizations.owner_user_id` stays trivially in sync (updated atomically in transfer RPC)
- Multi-owner would require additional legal scaffolding (CLO: "who bears controller obligations?")

**Dedicated transfer RPC** was chosen over extending the existing `update_workspace_member_role` because:
- Clear intent and single responsibility — matches the invite/remove separation pattern
- The dual-write (`workspace_members.role` + `organizations.owner_user_id`) is explicit
- Avoids boolean-flag anti-pattern on the existing RPC
- Easier to audit (security-sentinel sees one RPC with one purpose)

## User-Brand Impact

`USER_BRAND_CRITICAL=true` — operator selected all three failure vectors.

**Artifact at risk:** workspace membership roles, audit log access, GDPR controller designation, BYOK delegation grants.

**Vectors:**

1. **Trust breach / role escalation.** A member could escalate to owner without authorization if the transfer RPC's caller-is-owner check fails or if the workspace_members table allows direct client writes to the role column.
2. **Cross-tenant write.** A role change applied to the wrong workspace via a forged `workspaceId` in the API request.
3. **Data loss / ownerless workspace.** A failed transfer leaves zero owners — every owner-gated RPC returns 42501, locking the workspace. The single-owner-strict model with atomic swap prevents this structurally.

**Threshold:** `single-user incident` (inherited from parent brainstorm).

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | Owner model | Single-owner strict | One owner per workspace at all times. Simpler invariant, clearer GDPR controller designation. Schema has no UNIQUE constraint, so enforcement is RPC-level (all writes go through SECURITY DEFINER RPCs). |
| 2 | Transfer implementation | Dedicated `transfer_workspace_ownership` RPC (new migration) | Atomic dual-write: (1) promote target to owner, (2) demote caller to member, (3) update `organizations.owner_user_id`. Separate from role-change RPC for clarity. |
| 3 | Existing RPC modification | Block promotions to owner in `update_workspace_member_role` | The existing RPC allows promoting members to owner, which breaks single-owner. Modify to only allow demotions (or restrict to transfer-RPC-only path). |
| 4 | Transfer confirmation UX | Type workspace name to confirm | GitHub-style destructive confirmation. Owner loses: audit-log read access, invite/remove ability, controller designation. Strongest signal of intent. |
| 5 | Fresh attestation on promotion | Required | CLO requirement. Member-to-owner promotion needs a new WORM attestation row in `workspace_member_attestations` (AUP §5.5 obligation, Art. 5(2) accountability chain). The `attestation_id` FK on `workspace_member_actions` is already wired. |
| 6 | Retroactive audit visibility | Full history | New owner sees all historical `workspace_member_actions` events. Matches "owner is controller" principle — controller needs full accountability chain. Art. 5(1)(c) data minimisation deferred (insufficient justification for filtering at this scale). |
| 7 | BYOK delegation handling | Deferred | CTO flagged: `byok_delegations` trigger (mig 064) fires on DELETE but NOT on role UPDATE. Demoting a grantor-owner to member does not auto-revoke delegations. Accepted as deferred scope — single-owner transfer atomically swaps ownership, so the delegation grantor is always the current owner. |
| 8 | Dual ownership source of truth | Resolved via atomic dual-write | `organizations.owner_user_id` and `workspace_members.role = 'owner'` both updated in the transfer RPC. Call sites reading `organizations.owner_user_id`: `account-delete.ts:670`, `dsar-export-allowlist.ts:190`, `dsar-export.ts:874`, `063:256` (audit log reader). Write-boundary sentinel sweep required at implementation. |
| 9 | Feature flag gating | Behind existing `team-workspace-invite` flag | No new flag needed. Role management is part of the team workspace surface, already gated by `isTeamWorkspaceInviteEnabled`. |
| 10 | Timing | Brainstorm + spec now, plan when #4518 merges | #4518 (Members tab PR) must merge first — it carries migration 067 (role-change RPC) and the Members tab UI (insertion point for role controls). |

## Open Questions

| # | Question | Notes |
|---|----------|-------|
| 1 | Should `update_workspace_member_role` be removed entirely or restricted to demotions? | If single-owner strict, the only valid role change is owner→member (via transfer) or member→owner (via transfer). The existing RPC's promote path becomes dead code. |
| 2 | Should a partial unique index (`WHERE role = 'owner'`) be added for DB-level enforcement? | PostgreSQL partial unique indexes are not deferrable, so the transfer RPC must update in promote-first order (momentary two-owner state within the transaction). The RPC-level guard is sufficient since all writes go through SECURITY DEFINER RPCs. |
| 3 | Session invalidation gap (#4307) | Demoted owner retains JWT privileges until natural expiry. The `user_session_state.current_organization_id = NULL` clear (F6 pattern) forces re-auth, but the window between demotion and JWT refresh is a privilege-retention gap. |

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Deferral is well-reasoned — 2 seed members, single-owner sufficient for dogfood. Dependency chain is clear (#4518 → #4520). Critical risk: dual ownership source of truth (`organizations.owner_user_id` vs `workspace_members.role`). Transfer RPC must update both atomically. Recommends single-owner strict with atomic swap. Leave in Post-MVP/Later; promote when #4518 merges AND 3rd member added.

### Legal (CLO)

**Summary:** Ownership transfer changes GDPR controller designation (Art. 24). Fresh attestation required on member-to-owner promotion (AUP §5.5 obligation). New owner gains retroactive audit-log visibility (PII exposure vector — disclose in DPD). Five legal documents need coordinated updates: ToS §"Workspace Members", AUP §5.5, Privacy Policy, GDPR Policy, DPD §2.3. Recommends `/soleur:gdpr-gate` at plan Phase 2.7. No external-specialist threshold triggered.

### Engineering (CTO)

**Summary:** `update_workspace_member_role` RPC + TS wrapper already exist in migration 067 (on feature branch, not main). Net-new: `update-role` API route (mechanical lift), frontend role toggle, `transfer_workspace_ownership` RPC (new migration — medium complexity). Critical risk confirmed: dual ownership source of truth. Transfer RPC must atomically update `workspace_members.role` + `organizations.owner_user_id` + fresh attestation. BYOK delegation orphaning on demotion deferred. Total estimate: days (not weeks).

## Capability Gaps

None identified. All components (migration authoring, API route creation, React UI, WORM audit) are within the current engineering domain. Legal doc updates use the existing `legal-document-generator` + `legal-compliance-auditor` pipeline.

## Learnings Applied

- WORM trigger bypass must use GUC-only pattern, not `current_user = 'service_role'` (2026-05-18 learning)
- Column-level REVOKE is silently ineffective with table-level grants — revoke table-level first (2026-03-20 learning)
- Supabase `ALTER DEFAULT PRIVILEGES` defeats `REVOKE ALL FROM PUBLIC` — must name all roles explicitly (2026-05-06 learning)
- RLS `FOR ALL USING` applies to writes too — do not add `WITH CHECK (true)` (2026-04-18 learning)
- Session invalidation gap (#4307): demoted owner retains JWT until expiry; F6 pattern (clear `user_session_state`) mitigates but doesn't eliminate window
