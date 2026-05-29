# ADR-043: Flagsmith Per-Org Targeting via Identity Trait

**Status:** superseded-in-part (see "Per-feature segment scoping (2026-05-29)" below)
**Date:** 2026-05-25
**Deciders:** Jean Deruelle (CTO), Claude (engineering)
**Related:** ADR-038 (feature-flag architecture), umbrella #4456 PR-2, #4581 PR-2 (per-feature segment scoping)

> **Supersession note (2026-05-29):** The "Segment Design" section below — a
> *single* shared `org-targeted` segment gating *all* per-org features — is
> superseded by the per-feature-segment model documented at the end of this ADR
> (#4581 PR-2). The Identity Strategy and Cache Key Widening sections remain in
> force. The shared `org-targeted` segment is retained until `team-workspace-invite`
> is migrated off it (follow-up); new per-org features use `<flag>-orgs`.

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

- **Single-control:** Flagsmith segment rule is the sole per-org gate; env-allowlist removed. FLAG_* env vars remain as Flagsmith outage fallback
- **Data minimization:** `transient: true` prevents Flagsmith from persisting any identity data server-side
- **Cache bounded:** LRU(1000) prevents unbounded memory growth from org diversity
- **WORM audit trail:** Every flag flip (via skill) appends to `flag_flip_audit` table (migration 071)
- **Async propagation:** `isTeamWorkspaceInviteEnabled` and `isByokDelegationsEnabled` become async; all consumers must await

## Per-feature segment scoping (2026-05-29)

**Supersedes:** the "Segment Design" section (single shared `org-targeted` segment).
**Context:** #4581 PR-2 — enabling a legally-sensitive flag (`byok-delegations`) for
**one** org (#4232) without exposing it to the *other* org that happens to share the
`org-targeted` segment. The original "one segment for all per-org features" design
made per-(feature, org) granularity impossible: any feature attached to `org-targeted`
is enabled for **every** org in its membership. `byok-delegations` and
`team-workspace-invite` cannot have different org sets under one shared segment.

**Decision:** Each org-targetable feature `<flag>` gets its **own** project-level
segment `<flag>-orgs`. The feature has an ON feature-state override on its own segment
in both envs; the segment's membership (one `EQUAL orgId <uuid>` condition per org,
inside the `ANY` rule — same rule envelope as `org-targeted`, **not** an `IN` clause)
is the per-org gate **for that feature only**. Adding/removing an org for a feature =
mutating `<flag>-orgs` conditions, via `soleur:flag-set-role <flag> <env> <on|off>
--org <orgId>`. Provisioning (`provision_feature_segment <flag>`) is idempotent:
segment-create-if-absent + override-ON-in-both-envs.

### Why this does not reintroduce the rejected "N per-org segments" explosion

The original ADR rejected "one segment per org" because membership management is
**O(orgs)** — the customer axis is unbounded, so segment count grows with every
customer. The per-feature model is **O(features)**: one segment per *org-targetable
feature*, a small, slow-growing, product-controlled axis (today: 2). Org churn changes
*conditions inside* an existing segment, never the segment *count*. The explosion the
ADR feared lives on the org axis; this design keeps the segment count on the feature
axis, which is exactly where it is bounded.

### Fallback-fidelity property (unchanged invariant, re-stated for per-feature segments)

Per-org segment overrides are **invisible to the Doppler `FLAG_*` env-var mirror**
(the mirror reflects the prd *role-segment* override state, not segment rule
definitions — ADR-038 v2 §"Fallback semantics"). Consequence: on a Flagsmith outage,
a flag whose *only* enablement is a per-org `<flag>-orgs` override **falls back OFF**
(env-var = 0). For `byok-delegations` this is the **safe** direction and a verified
precondition: `FLAG_BYOK_DELEGATIONS` is `0` in prd Doppler (verified 2026-05-29), and
no prd role-segment override pins it ON. A per-org BYOK grant therefore degrades closed
(feature disabled) rather than open (feature enabled for a non-opted-in org) when
Flagsmith is unreachable — consistent with the legitimate-interest assessment for the
flag-flip audit and the single-user-incident brand-survival threshold.

### Re-verification is at the evaluation layer, not segment membership

A correct membership set is **not** sufficient proof a flag is enabled: a missing
feature-state override, or an override present in only one env, leaves the flag OFF
while the org is "in" the segment. The skill therefore re-verifies by **evaluating the
flag** for a transient identity carrying the `orgId` trait (the production
`getIdentityFlags("org:<orgId>:<role>", {role, orgId}, transient=true)` path), asserting
`enabled=true` for the target org **and** `enabled=false` for a control org — an
absolute invariant, not a check against the script's own computed membership.
