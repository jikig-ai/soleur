# Learning: append-only WORM trigger forbids in-place token/expiry rotation — grep for `*_no_mutate` before accepting an "edit the row" framing

## Problem

Brainstorm of #4636 (resend a pending workspace invite) started from the operator's
literal framing — "mint a new token, reset the 7-day expiry" — which reads as an
in-place `UPDATE workspace_invitations SET token_hash=…, expires_at=…`. That mutation
is **rejected by the database every time**: the `workspace_invitations_no_mutate()`
trigger (migration `075:93`, re-issued verbatim in `085`) marks `token_hash`,
`expires_at`, PII, and audit-lineage columns immutable once a row exists. Designing the
RPC around in-place rotation would have produced a spec that fails at the first migration
test.

## Solution

Two domain leaders (CTO, CLO) independently surfaced the immutability trigger from the
migrations. Verified directly with `git grep -nE "no_mutate|immutable" -- '*075*' '*085*'`
before letting it shape the plan. The architecturally aligned path for "rotate token on
an append-only table" is **revoke-old-row + insert-new-row in one SECURITY DEFINER
transaction**:

- `UPDATE old SET revoked_at=now()` then `INSERT` a fresh row with the new token_hash and
  `now()+7d`, same email/role/inviter, original `attestation_id` carried forward.
- The old link dies for free — `lookup_invitation_by_token` and
  `accept_workspace_invitation` already reject `revoked_at IS NOT NULL` rows.
- Atomic by construction; zero trigger change; the pending list (filters `revoked_at IS
  NULL`) auto-surfaces the new row with no consumer change.

The rejected alternative (relax the WORM trigger to allow mutation on pending rows) widens
a security invariant that three migrations and the unique token index depend on — HIGH risk.

## Key Insight

When a brainstormed feature proposes **mutating an audit/append-only table** (anything with
a `*_no_mutate` trigger, WORM comment, or "immutable once set" guard), grep for that trigger
**before** accepting an in-place-edit framing. The operator's natural mental model is "edit
the record"; the schema's reality is "records are immutable, supersede them." Catching the
mismatch at Phase 1.1 turns a doomed in-place RPC into the correct revoke-and-reinsert
pattern — and it generalizes to any token rotation, expiry reset, or value swap on an
append-only table.

## Session Errors

Session error inventory: none detected. No failed commands, path confusion, or
skill-not-found errors. The premise probe, worktree creation, leader spawns, and
verification greps all succeeded on first attempt.

## Tags
category: logic-errors
module: workspace-invitations / brainstorm
issue: 4636
