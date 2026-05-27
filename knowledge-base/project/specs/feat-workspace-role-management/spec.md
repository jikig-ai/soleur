---
name: feat-workspace-role-management
status: brainstormed
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 4520
depends_on:
  - 4518
brainstorm: knowledge-base/project/brainstorms/2026-05-27-workspace-role-management-brainstorm.md
---

# Workspace Role Management + Ownership Transfer

## Problem Statement

The workspace Members tab (#4516) provides invite and remove flows but no mechanism to change a member's role or transfer workspace ownership. With a single-owner strict model, the workspace owner needs the ability to atomically transfer ownership to another member.

## Goals

- G1: Owner can transfer ownership to a member via an atomic swap (single-owner strict)
- G2: Transfer updates both `workspace_members.role` AND `organizations.owner_user_id` in one transaction
- G3: Transfer requires GitHub-style destructive confirmation (type workspace name)
- G4: Transfer writes a fresh attestation row to `workspace_member_attestations` (CLO Art. 5(2) requirement)
- G5: Audit trigger automatically captures `role_changed` events (already wired in mig 063)
- G6: New owner gains full historical audit-log visibility

## Non-Goals

- NG1: Multi-owner model (explicitly rejected — single-owner strict)
- NG2: BYOK delegation auto-revocation on transfer (deferred — delegation grantor is always the current owner)
- NG3: Role change UI without transfer (the existing `update_workspace_member_role` RPC's promote path contradicts single-owner; restrict or remove)
- NG4: Two-phase transfer with target acceptance (overkill for 2-member dogfood)
- NG5: Retroactive audit-log filtering for new owner (full history, per GDPR controller principle)

## Functional Requirements

| ID | Requirement |
|----|-------------|
| FR1 | New `transfer_workspace_ownership` SECURITY DEFINER RPC: atomically (1) promote target to owner, (2) demote caller to member, (3) update `organizations.owner_user_id`, (4) write fresh attestation row, (5) set `workspace_audit.actor_user_id` GUC |
| FR2 | New `app/api/workspace/transfer-ownership/route.ts` API route following the invite-member pattern (CSRF, auth, flag gate, workspace mismatch defense, caller ownership check) |
| FR3 | "Transfer ownership" option in Members tab kebab menu (owner-only, non-self members only) |
| FR4 | Confirmation dialog: user must type workspace name to confirm. Displays consequences (lose audit access, lose invite/remove ability, lose controller designation) |
| FR5 | Post-transfer cascades: SIGTERM in-flight agent sessions for both parties, WS close with preamble, clear `user_session_state` for both |
| FR6 | Modify `update_workspace_member_role` to reject promotions to owner (single-owner enforcement) |

## Technical Requirements

| ID | Requirement |
|----|-------------|
| TR1 | RPC pins `SET search_path = public, pg_temp` (per `cq-pg-security-definer-search-path-pin-pg-temp`) |
| TR2 | REVOKE/GRANT matrix: `REVOKE ALL FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO authenticated` |
| TR3 | Actor GUC: `set_config('workspace_audit.actor_user_id', ...)` before any workspace_members mutation |
| TR4 | Write-site sentinel: new migration must pass `check-workspace-members-write-sites.sh` CI gate |
| TR5 | `organizations.owner_user_id` call-site sweep: verify `account-delete.ts:670`, `dsar-export-allowlist.ts:190`, `dsar-export.ts:874`, `063:256` all behave correctly post-transfer |
| TR6 | `/soleur:gdpr-gate` at plan Phase 2.7 against migration + API route diffs |

## Legal Requirements

| ID | Requirement |
|----|-------------|
| LR1 | ToS §"Workspace Members" defining owner as controller, ownership transfer clause |
| LR2 | AUP §5.5 owner attestation obligation + re-attestation on promotion |
| LR3 | Privacy Policy: workspace membership data category, role-change audit log |
| LR4 | GDPR Policy: PA-20 cross-reference, balancing test for audit-log access on transfer |
| LR5 | DPD §2.3: ownership-transfer disclosure, audit-log access scope expansion |

## Dependencies

- **#4518** (Members tab PR) must merge first — carries migration 067 (`update_workspace_member_role` RPC) and the Members tab UI (insertion point for transfer controls)
- Migration 067 establishes the `update_workspace_member_role` RPC, `workspace_member_removals` revocation-lookup, and F6 session-clear pattern that this feature extends

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Ownerless workspace (transfer fails mid-transaction) | HIGH | Single SECURITY DEFINER RPC — all changes in one transaction, promote-before-demote ordering |
| `organizations.owner_user_id` desync | HIGH | Atomic dual-write in transfer RPC; write-boundary sentinel sweep at implementation |
| Cross-workspace role mutation | HIGH | `workspace_mismatch` check in API route (invite-member pattern) |
| Privilege retention post-demotion (#4307) | MEDIUM | F6 pattern (clear `user_session_state`) forces JWT refresh; residual window accepted |
| BYOK delegation orphaning | LOW | Deferred — delegation grantor is always the current owner post-transfer |
