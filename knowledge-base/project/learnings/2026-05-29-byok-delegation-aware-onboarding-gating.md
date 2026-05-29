# Learning: Onboarding/redirect gates must check EFFECTIVE key, not own `api_keys` row

## Problem

Brainstorming a skippable "Connect your API key" onboarding step (issue #4642, PR
#4640), the initial framing assumed the relevant question was "does the user have a
key?" — implemented everywhere as a direct `api_keys` lookup. The operator raised
mid-brainstorm that multi-user workspaces now support **BYOK delegation**: a member can
run on the workspace owner's key without owning one.

Investigation found the auth callback (`app/(auth)/callback/route.ts` ~L233-242) and
`accept-terms` (`getRedirectDestination`, ~L10-23) both decide the `/setup-key`
force-redirect by checking ONLY `api_keys` (provider=anthropic, is_valid=true) for the
user's own row. A user with a valid **inbound delegation but no own key** is therefore
**already, today, wrongly force-redirected to `/setup-key`** — a pre-existing latent
bug, not introduced by the new feature.

## Solution

The correct gate is "does the user have an **effective** key?" = own valid key **OR**
an active, consented, non-withdrawn inbound delegation. The authoritative resolver
already exists as the Postgres RPC `resolve_byok_key_owner(caller, workspace)` (migns
083/084): own-key short-circuit → else the active-delegation predicate (not revoked, not
expired, current-version acceptance in `byok_delegation_acceptances`, no newer row in
`byok_delegation_withdrawals`). There is **no TS boolean helper** for it — so the fix is
a single reusable `userHasEffectiveByokKey(userId, workspaceId, serviceClient):
Promise<boolean>` wrapping that RPC (non-empty ⇒ true), used by every onboarding
redirect AND any degraded-state banner. It must also mirror the runtime's org-level
delegation feature-flag check (see `byok-resolver.ts resolveKeyOwnerThenLease`) so
flag-disabled orgs don't count delegations.

Enforcement stays untouched: the chat-time gate (`agent-runner.ts getUserApiKey` →
`KeyInvalidError` before any Anthropic call) remains authoritative; the skip/redirect
work is routing-only.

## Key Insight

**In a multi-tenant BYOK product, any "has this user got a key?" check that reads
`api_keys` directly is a latent bug once delegation exists.** Whenever delegation is
added to a credential model, sweep every consumer of the raw credential table — auth
redirects, onboarding gates, dashboard banners, feature flags — and re-point them at the
effective-resolution path (`resolve_byok_key_owner`), because the runtime already
resolves "own OR delegated" but the UI/routing gates silently don't. The "granted but
not yet accepted" delegation state has zero effective key (resolver fail-closes), so a
keyless-degraded surface must branch: pending-delegation → "accept the delegation" vs.
truly-keyless → "add your key".

## Session Errors

1. **First research agent (Explore) reported "no Settings page exists" (false
   negative).** It was spawned with bare-repo-absolute paths before the orchestrator was
   operating inside the worktree, so it read stale bare-repo state; a real
   `/dashboard/settings/services` + `KeyRotationForm` exist in the worktree.
   **Recovery:** worktree-grounded CPO/CTO leaders flagged the contradiction; re-verified
   with `find` from the worktree before relying on it. **Prevention:** already covered —
   spawn research agents with worktree-absolute paths and verify file-existence claims
   from the worktree, not the bare repo (see
   [[2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd]],
   [[2026-05-19-bare-repo-grep-and-subagent-infra-claim-verification]]). No new rule
   warranted.

## Tags
category: integration-issues
module: web-platform/byok-onboarding
