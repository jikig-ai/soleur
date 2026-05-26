# ADR-043: Flagsmith Per-Org Targeting via Identity Trait

**Status:** accepted
**Date:** 2026-05-25
**Deciders:** Jean Deruelle (CTO), Claude (engineering)
**Related:** ADR-038 (feature-flag architecture), umbrella #4456 PR-2

## Context

Umbrella #4456 migrates `team-workspace-invite` and `byok-delegations` from ENV_FLAGS (sync, deploy-time) to RUNTIME_FLAGS (async, identity-aware via Flagsmith). Both flags need per-org rollout capability — the ability to enable a feature for specific organizations without a deploy.

The current Flagsmith integration uses a single `role:<role>` identifier with per-role segments. This does not support per-org granularity.

## Decision

Extend the Flagsmith identity model with an `orgId` trait, resolved from `workspace_members`, and use a single `org-targeted` segment with a rule `orgId IN [...]` to gate per-org features.

### Identity Strategy

- **Identifier:** `org:<orgId>:<role>` when orgId is present; `role:<role>` when absent
- **Traits:** `{ role, orgId }` (both plain values, auto-wrapped by SDK)
- **Transient:** `true` on all `getIdentityFlags()` calls — no server-side identity persistence

### Segment Design

One `org-targeted` segment (not N per-org segments):
- Rule: `orgId IN [org-id-1, org-id-2, ...]`
- Features attached to this segment evaluate to `true` only for identities whose `orgId` trait matches
- Adding/removing an org = updating the segment rule via `/soleur:flag-set-role --target org`

### Cache Key Widening

Replace the `Map<Role, ...>` (max 2 entries) with an LRU cache keyed on `${role}:${orgId}`:
- Max entries: `parseInt(process.env.FLAGSMITH_CACHE_MAX_ENTRIES || '1000')`
- TTL: 30s (unchanged from current)
- Eviction: LRU by last-access timestamp

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| N per-org segments (one segment per org) | Segment explosion; O(orgs) management overhead |
| Per-user identity overrides | Out-of-scope; org-level is the correct boundary for both flags |
| Separate Flagsmith project per org | Massive operational complexity; billing explosion |
| Continue with ENV_FLAGS + deploy-time allowlist only | No runtime flip without deploy; defeats the purpose of ADR-038 |

## Consequences

- **Dual-control preserved:** Flagsmith boolean AND env-allowlist must both hold (defense-in-depth)
- **Data minimization:** `transient: true` prevents Flagsmith from persisting any identity data server-side
- **Cache bounded:** LRU(1000) prevents unbounded memory growth from org diversity
- **WORM audit trail:** Every flag flip (via skill) appends to `flag_flip_audit` table (migration 071)
- **Async propagation:** `isTeamWorkspaceInviteEnabled` and `isByokDelegationsEnabled` become async; all consumers must await
