---
title: Feature flags via Flagsmith SaaS with per-role targeting (Claude-operated)
status: accepted
date: 2026-05-22
related: [2408, 2409]
related_adrs: [ADR-022]
related_plans:
  - knowledge-base/project/plans/2026-05-22-feat-flagsmith-adoption-plan-v2.md
related_specs:
  - knowledge-base/project/specs/feat-feature-flag-provider/spec.md
brand_survival_threshold: single-user incident
---

# ADR-038: Feature flags via Flagsmith SaaS with per-role targeting (Claude-operated)

## Status

**Accepted** (2026-05-22). Landed as a two-PR sequence:
- **PR #4331** (merged 2026-05-22): identity-aware resolution path, `users.role` column, ADR, provider+hook, tests.
- **PR #2** (this commit's PR): three Soleur skills (`soleur:flag-create`, `soleur:flag-set-role`, `soleur:user-set-role`) + one-time Flagsmith setup runbook at `plugins/soleur/skills/flag-bootstrap/SETUP.md`. Segments `role-prd` (id 1129195) and `role-dev` (id 1129194) created in Flagsmith project `web-platform` (id 39082); dead `command-center-soleur-go` feature archived. Operational interface is live.

Closes the Phase 4 follow-on deliberately deferred by PR #2408 (issue #2409, closed): the original env-var-only system left "adopt a third-party provider" as an explicit future-phase action item.

## Context

PR #2408 shipped a minimal runtime feature-flag system — `getFlag(name)` / `getFeatureFlags()` resolving booleans from `process.env.FLAG_*` at request time, toggled via Doppler + container restart. Adequate for binary on/off, inadequate for **progressive rollout** to a reduced group of testers.

Two operational profiles emerged for flags in this codebase:

1. **Build/deploy-time flags** like `dev-signin` — gates a dev-only auth bypass. Layered defense relies on `process.env.NODE_ENV !== "development"` literals at call sites so SWC/Terser can dead-code-eliminate the panel body in production bundles. The runtime check is belt-and-suspenders inside dev builds. A network round-trip for a value that can't change without a redeploy is wasteful and weakens the DCE story.

2. **Runtime product flags** like `kb-chat-sidebar` — the kind of flag that should flip per-user-group without a deploy. Needs an identity model, audit trail, per-environment scoping (dev vs prd), graceful degradation when the provider is down, and crucially: the ability to enable a feature for a small test group (`role=dev`) before broadening to the prd cohort.

The operator's stated requirement (2026-05-22): "I want to test features with a reduced group of users defined by roles before shipping to everyone, and Claude should be the only thing operating Flagsmith — no human dashboard."

## Decision

Adopt **Flagsmith SaaS** (edge endpoint) for runtime flag evaluation with **per-role segmentation**. Keep `FLAG_*` env vars as a graceful fallback whose value mirrors the prd-segment state (see "Fallback semantics" below).

### API partition by flag kind

- `getFlag(name: EnvFlagName): boolean` — **sync**, reads `process.env[FLAG_*]` only. For build/deploy-time flags. Used by `dev-signin` consumers.
- `getRuntimeFlag(name: RuntimeFlagName, identity: Identity): Promise<boolean>` — **async**, identity-aware. Queries Flagsmith via the server-side SDK with the user's role passed as a trait. Cache key = role (2 entries max). 30s TTL. Falls back to env var on SDK error/timeout/missing key.
- `getFeatureFlags(identity: Identity): Promise<Record<FlagName, boolean>>` — combined snapshot. Hydrated by `/api/flags` and the server-rendered `FeatureFlagProvider` in `app/layout.tsx`.
- `useFeatureFlag(name): boolean` — client hook reading provider context. No client-side Flagsmith SDK.

### Identity model

```
Identity = { userId: string | null, role: "prd" | "dev" }
```

Resolved at every request edge by `resolveIdentity(supabase)`:
- Anonymous (logged-out) → `{ null, "prd" }`. Anonymous = "prd everyone" matches the role semantics; logged-out visitors see the same flag state as any prd-role authenticated user.
- Authenticated → `auth.uid()` + `select role from users where id = ...`.
- Auth probe failures, missing rows, or unrecognised role values → safe default `role="prd"`. Fail-safe (no dark-launch on the resolve path).

### Role storage

`public.users.role text not null default 'prd' check (role in ('prd','dev'))`. Migration 054. Default `'prd'` backfills every existing row with zero data motion (column-add is metadata-only under Postgres 15). Trigger `users_prevent_role_self_mutation` blocks updates to `role` for non-service-role connections — only Soleur skills (running with service-role) can promote a user to `dev`.

### Flagsmith segment model

Two segments (PR #2 bootstraps via management API):
- `role-prd` — trait `role == "prd"` OR identity unknown.
- `role-dev` — trait `role == "dev"`.

Each flag's per-segment enable state is what skills mutate. No identity-level overrides in V1 — every flag decision flows through the segment.

### Fallback semantics (load-bearing)

The `FLAG_*` env var **mirrors the flag's prd-segment Flagsmith state**. When Flagsmith is unreachable (network, SDK timeout, missing key), every user — regardless of role — resolves through `envFallback()` which reads the env var directly.

Consequences:
- **Dev-only feature mid-test** (Flagsmith: prd=off, dev=on / Doppler: `FLAG_X=0`) → outage → dev role temporarily loses preview, prd never sees it. Acceptable: no dark-launch.
- **Promoted feature** (Flagsmith: prd=on, dev=on / Doppler: `FLAG_X=1`) → outage → everyone sees it. Matches steady state.
- **Disabled feature** (Flagsmith: prd=off, dev=off / Doppler: `FLAG_X=0`) → outage → off everywhere. Matches.

The case Flagsmith allows but fallback can't represent (prd=on, dev=off — i.e. "remove a feature from dev cohort while leaving it on for prd") is **explicitly disallowed by the skill contract**. `soleur:flag-set-role <x> dev off` rejects when prd is currently on. Operator must turn prd off first. This is a deliberate constraint — preserving fallback fidelity is worth more than the rare reverse-rollout case.

The skill contract also requires: any change to prd-segment state runs `doppler secrets set FLAG_X=<0|1>` in dev + prd configs so the env var stays in sync with Flagsmith. This is the load-bearing rule that makes the fallback safety story hold.

### Why Claude is the only operator

- Single audit trail (skill invocations land in conversation history).
- No "click the wrong toggle in the wrong env" class of error — skill arguments are checked, role enums validated, Doppler sync forced.
- Forces a written record of every flag flip (the chat is the audit log).
- No human gets a Flagsmith dashboard URL that becomes a foot-gun.

The Flagsmith UI remains accessible for operator inspection ("what's the current state?") but never for mutation.

## Tradeoffs

**Vendor lock-in.** Flagsmith is open-source with a self-hostable backend. Self-host migration is code-free — `FLAGSMITH_API_URL` env var swap. Total switching cost to a different provider entirely is bounded to the four functions in `lib/feature-flags/server.ts` plus the three skills.

**Two-PR rollout adds an interim period.** Between PR #1 merge and PR #2 merge, segments don't exist; every runtime flag resolves identically for every role (whatever Flagsmith env-level default is). Mitigation: the only runtime flag today (`kb-chat-sidebar`) has zero code consumers, so the interim state is invisible to users.

**Cache TTL = 30s per role.** A flag flip via skill takes up to 30s to propagate per process replica. Matches operator tolerance for env-var flag flips (Doppler restart, 1-2 min). The skill output reminds the operator.

**Two APIs, not one.** Explicit partition by sync/async forces callers to choose intentionally. Alternative (single always-async API) would convert `DevSignInPanel` and `isDevSignInEnabled` to async, propagate through their consumers, and weaken the DCE story for the dev-signin layered defense.

**Per-role cache, not per-identity.** Two cache entries instead of N (number of active users). Tradeoff: a per-user override (Flagsmith identity-level override) wouldn't be honored without bypassing the cache. Acceptable in V1 because identity-level overrides are not part of the operational model (everything flows through segments).

**Trigger-based role mutation guard.** `users_prevent_role_self_mutation` blocks the update path for non-service-role connections. Tradeoff: any future use of supabase RPC that runs as `authenticated` and tries to modify `role` will trip the trigger. This is the intended behavior, but worth surfacing in the skill error messages so operators know which path is rejecting them.

## Operational notes

- **`FLAGSMITH_ENVIRONMENT_KEY`** (server-side SDK key) → Doppler `dev` + `prd` configs. Read by the app at request time.
- **`FLAGSMITH_MANAGEMENT_API_KEY`** (organisation token, prefixed `Api-Key`) → operator-only Doppler config `cli` under the `soleur` project. Skills resolve it via `doppler secrets get FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli --plain`. NEVER read by the app, only by Soleur skills.
- **Doppler scope = `dev` + `prd` only** for the SDK key. Other configs (`ci`, `dev_scheduled`, `prd_scheduled`, etc.) silently fall through to env-var resolution. Not needed until one of those configs runs the web-platform request path against real users.
- **Outage behavior is identical to PR #2408's env-var-only system.** When Flagsmith is unreachable, every flag resolves from `process.env.FLAG_*`. A Flagsmith outage cannot dark-launch features.

## Findings & follow-on action items

- **ADR-022 amendment needed (separate PR).** ADR-022 documents `FLAG_CC_SOLEUR_GO=false` in Doppler prd; PR #3270 retired that flag entirely. ADR-022 still references it. Should be amended with the retirement reference and current state.
- **Flagsmith UI cleanup (separate operator action).** The Flagsmith project was provisioned during pre-plan setup with `command-center-soleur-go` as a feature. That flag has no code consumer. Should be archived in the Flagsmith UI (or via skill once `flag-archive` is added — not in V1 scope).
- **PR #2 — Soleur skills + segment bootstrap.** Carries the operational interface. Until it merges, flag mutations require manual curl invocations (documented in PR #2's plan file).

## Alternatives considered

- **LaunchDarkly.** Best-in-class. Disproportionate cost for current flag count and feature needs. Revisit if we adopt experimentation/A/B framework.
- **Self-hosted Flagsmith from day one.** Adds an operational service (Postgres + Flagsmith API + dashboard) for two flags. SaaS lets us defer that until we need data residency control or hit a cost cliff.
- **Statsig / Unleash / GrowthBook.** Considered. Flagsmith won on (1) open-source backend hedge, (2) simple pricing for small flag counts, (3) clean Node SDK with `defaultFlagHandler` and explicit identity API.
- **Stay env-var-only.** PR #2408's choice. Doesn't support the per-role progressive rollout requirement.
- **Per-user overrides instead of role-based segments.** Would require operator to list every dev user as an identity override per flag. Scales poorly past 2-3 testers; segments make role membership the single point of truth.
- **Custom role table separate from `users`.** Considered. `users.role` is simpler and the trigger-based mutation guard provides the same defense as a separate `user_roles` table with restrictive RLS would.
