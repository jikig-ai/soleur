---
name: feat-flagsmith-adoption-v2
title: Adopt Flagsmith SaaS with per-role targeting (prd/dev) — Claude-operated
date: 2026-05-22
branch: feat-flagsmith-adoption
supersedes: knowledge-base/project/plans/2026-05-21-feat-flagsmith-adoption-plan.md
predecessor: knowledge-base/project/specs/feat-feature-flag-provider/spec.md
status: approved — splitting into two PRs (see "Two-PR split" below)
---

# Plan v2: Adopt Flagsmith SaaS with per-role targeting

## What changed from v1

V1 of this plan (dated 2026-05-21) modelled flags as global booleans — Flagsmith returns one value per flag, same for every user. During implementation the operator clarified the actual requirement: **flags must be testable on a reduced group of users (role=dev) before being enabled for everyone (role=prd).** V1 doesn't support that — it would force a dark-launch to every user the moment a flag flips ON.

V2 keeps the same Flagsmith adoption decision but adds **identity-based resolution** with a two-role segment model (`prd`, `dev`). The v1 work-in-progress in this worktree (provider + hook + sync env-flag carve-out + `flagsmith-nodejs` dep) carries forward; the server resolution module and call sites are rewritten to be identity-aware.

## Two-PR split

After scoping, this plan ships as two PRs:

**PR #1 (this branch, `feat-flagsmith-adoption`)** — core resolution path. Stages 1–4, 7, 8 below.
- Migration 054 (users.role + trigger guard).
- `lib/feature-flags/server.ts` identity-aware rewrite.
- `lib/feature-flags/identity.ts` (resolveIdentity helper).
- `app/layout.tsx` + `app/api/flags/route.ts` identity wiring.
- `FeatureFlagProvider` + `useFeatureFlag` hook (from v1 work).
- Tests (16 unit + 3 component, all green).
- ADR-038 v2.
- `.env.example` + plan + spec cross-link.

**PR #2 (follow-on, fresh branch)** — operational interface. Stages 5, 6 below.
- Three Soleur skills (`flag-create`, `flag-set-role`, `user-set-role`).
- One-time segment-bootstrap script (creates `role-prd` + `role-dev` in Flagsmith).
- Doppler operator config for `FLAGSMITH_MANAGEMENT_API_KEY`.

Interim state between PRs: runtime flags resolve identically for all roles (whatever Flagsmith env-level default is). Only `kb-chat-sidebar` is a runtime flag and it has zero code consumers, so the interim state is invisible to users.

## Context

PR #2408 (issue #2409) shipped env-var-only runtime flags and explicitly deferred third-party provider adoption to a later phase — this is that phase, scoped to enable **per-role progressive rollout**: ship a feature, enable for the dev role first, observe, then promote to the prd role.

The operator never opens flagsmith.com — Soleur skills mutate Flagsmith via its management API. The system has no human-facing dashboard.

## Goals

- **G1**: Flag resolution returns different values per user based on the user's role (`prd` or `dev`).
- **G2**: Anonymous (logged-out) users resolve to the `prd` role.
- **G3**: When Flagsmith is unreachable, every user falls back to the same `process.env.FLAG_*` value — and that value mirrors the prd-segment Flagsmith state, so an outage cannot dark-launch a dev-only feature to prd users.
- **G4**: Soleur skills are the only operational interface for Flagsmith (create flag, flip per-role, assign user→role). No human ever opens flagsmith.com.
- **G5**: Sync env-flag carve-out for build-time flags (`dev-signin`) stays — those never go through Flagsmith.

## Non-goals (V1 scope)

- More than two roles. `prd` + `dev` only. Future roles need a follow-on PR.
- Per-user overrides outside the role model (no targeting individual emails).
- Self-hosted Flagsmith (env-driven `FLAGSMITH_API_URL` left in place for future).
- A/B testing or experiment framework.
- Backfilling Flagsmith key to ci/scheduled/terraform Doppler configs (those continue to fall through to env-var path).

## Architecture

### Identity assembly

```
                  ┌──────────────────────────────────────┐
                  │ Request edge                          │
                  │  (app/layout, /api/flags, ws-handler) │
                  └─────────────────┬────────────────────┘
                                    │ resolveIdentity(supabase)
                                    ▼
                  ┌──────────────────────────────────────┐
                  │ Identity = {                          │
                  │   userId: string | null,              │
                  │   role:   "prd" | "dev"               │
                  │ }                                     │
                  │ Anonymous = { null, "prd" }           │
                  └─────────────────┬────────────────────┘
                                    │
                                    ▼
                  ┌──────────────────────────────────────┐
                  │ getFeatureFlags(identity)            │
                  │   ├─ Map<role, snapshot> cache       │
                  │   │   (2 entries max, TTL 30s)       │
                  │   ├─ flagsmith.getIdentityFlags(     │
                  │   │     userId ?? `anon`,            │
                  │   │     { role })                    │
                  │   └─ on SDK error/timeout/no key →   │
                  │       envFallback() — prd-mirror     │
                  └──────────────────────────────────────┘
```

### Role storage

`public.users.role` (Supabase). Migration: `add column role text not null default 'prd' check (role in ('prd','dev'))`. Default `'prd'` backfills every existing row safely with zero data motion. RLS: existing `auth.uid() = id` policy already covers self-read; service-role-only update policy added.

### Flagsmith setup (one-time via management API)

Two segments:
- `role-prd` — trait `role == "prd"` OR identity unknown (anonymous fallback).
- `role-dev` — trait `role == "dev"`.

Each flag's per-segment enablement is what the skills mutate.

### Env-var fallback semantics (load-bearing)

The `FLAG_*` env var **mirrors the prd-segment Flagsmith state**. Skill enforcement (see Stage 6): any flip that changes prd-segment state must also `doppler secrets set FLAG_X=<0|1>` so fallback agrees. Consequences:
- Dev-only feature mid-test (Flagsmith: prd=off, dev=on / Doppler: FLAG_X=0) → outage → both roles fall back to off → dev temporarily loses preview, prd never sees it. Acceptable.
- Promoted feature (Flagsmith: prd=on, dev=on / Doppler: FLAG_X=1) → outage → everyone falls back to on → matches steady state.
- Disabled feature (Flagsmith: prd=off, dev=off / Doppler: FLAG_X=0) → outage → off everywhere → matches.

The case Flagsmith allows but fallback can't represent (prd=on, dev=off) is **disallowed by the skill contract** — `flag-set-role prd on` is required before any path that takes dev off below prd. Trying to set dev=off while prd=on raises in the skill.

## Implementation plan

### Stage 1 — Restart from clean v1-survivor baseline

In the worktree:
- Keep: `flagsmith-nodejs` dep, `components/feature-flags/{provider.tsx, use-feature-flag.ts}`, the spec cross-link, the v1 sync env-flag carve-out structure.
- Rewrite: `lib/feature-flags/server.ts`, `app/api/flags/route.ts`, `app/layout.tsx`, `lib/feature-flags/server.test.ts`, ADR-038, `.env.example`, `test/feature-flag-provider.test.tsx` (provider test stays correct; only its inputs change).

### Stage 2 — Supabase migration: users.role

- New migration `apps/web-platform/supabase/migrations/NNN_add_users_role.sql`:
  ```sql
  alter table public.users
    add column role text not null default 'prd'
    check (role in ('prd', 'dev'));

  create policy "users_role_service_only_update"
    on public.users for update using (false);
  -- (specific service-role grant is implicit via supabase service key)
  ```
- Run `doppler run -p soleur -c dev -- supabase db push` against dev project; verify via SQL.

### Stage 3 — Identity-aware server.ts

```ts
export type Role = "prd" | "dev";
export type Identity = { userId: string | null; role: Role };
export const ANON_IDENTITY: Identity = { userId: null, role: "prd" };

export function getFlag(name: EnvFlagName): boolean;                  // unchanged
export async function getRuntimeFlag(name: RuntimeFlagName, identity: Identity): Promise<boolean>;
export async function getFeatureFlags(identity: Identity): Promise<Record<FlagName, boolean>>;
```

Cache: `Map<Role, { at: number; flags: Record<RuntimeFlagName, boolean> }>`. Eviction by TTL. Anonymous resolves through the `prd` cache entry — no separate "anon" bucket.

### Stage 4 — Identity wiring at request edges

- `app/layout.tsx`: helper `resolveIdentity()` reads Supabase auth, looks up role; pass into `await getFeatureFlags(identity)`.
- `app/api/flags/route.ts`: same.
- `server/ws-handler.ts`: **deferred** — no current WS-path consumer of runtime flags. When the first such flag lands, add `role: Role` to `ClientSession` and extend `refreshSubscriptionStatus()`'s select to include `role`. Avoiding dead code per YAGNI.

### Stage 5 — Soleur skills (three) — DEFERRED TO PR #2

All three live under `plugins/soleur/skills/`. Auth via `FLAGSMITH_MANAGEMENT_API_KEY` (new Doppler `cli` config — operator-scoped, not in dev/prd app configs).

- **`soleur:flag-create`** — interactive: name, description, initial state per role (default both off). Calls Flagsmith API: create feature → set per-segment enablement. Then edits `RUNTIME_FLAGS` in `server.ts`, adds `FLAG_*` to `.env.example`, and runs `doppler secrets set FLAG_*` for dev + prd to mirror prd-segment initial state.
- **`soleur:flag-set-role <flag> <role> <on|off>`** — flips one segment. If role=prd, also mutates Doppler. Refuses `dev off` when `prd on` (see fallback rule above).
- **`soleur:user-set-role <email|userId> <prd|dev>`** — updates `public.users.role` via service-role Supabase client; writes the trait to the Flagsmith identity. Idempotent.

### Stage 6 — Flagsmith one-time setup — DEFERRED TO PR #2

A `plugins/soleur/skills/flag-bootstrap/` script the operator runs once: creates the two segments (`role-prd`, `role-dev`) with their trait rules. Imports the existing `kb-chat-sidebar` feature into the new segment model (set prd=off, dev=off by default; flip via skill as needed).

### Stage 7 — Tests

- Unit (`lib/feature-flags/server.test.ts`):
  - Per-role cache: two consecutive calls for same role → 1 SDK call. Different roles → 2 SDK calls. Same role, third call after TTL → re-fetch.
  - Identity passed to SDK: `getIdentityFlags(userId, { role })` invoked with correct args.
  - Anonymous: `{ null, "prd" }` resolves through prd cache; SDK called with `"anon"` identifier.
  - Fallback: SDK throws → env-var value returned regardless of role.
  - Env-only flag: sync `getFlag("dev-signin")` unchanged.
- Component (`test/feature-flag-provider.test.tsx`): existing tests stand; add one verifying provider accepts snapshot for arbitrary role.
- Skill tests: dry-run mode + fixture-based assertions on what API calls each skill would make (mock the Flagsmith API).

### Stage 8 — Docs

- Rewrite ADR-038 to v2: per-role decision, anon-as-prd rationale, env-var fallback policy, skills-as-only-interface decision, why not local-evaluation (still: too few flags).
- Update `.env.example`: add `FLAGSMITH_ENVIRONMENT_KEY=` (app), document that `FLAGSMITH_MANAGEMENT_API_KEY` lives only in operator/cli Doppler config (never app configs).
- Update spec cross-link.
- Skill SKILL.md files cover usage + the fallback-sync invariant.

## Acceptance criteria

- [ ] **AC1**: User in role=dev sees `kb-chat-sidebar=true` when Flagsmith has it ON for `role-dev` and OFF for `role-prd`; same flag in same env returns `false` for a prd-role user. Verified by unit test with stubbed SDK + manual curl with dev/prd test users.
- [ ] **AC2**: Anonymous request to `/api/flags` returns the prd-segment values. Verified by integration test against running dev container.
- [ ] **AC3**: With `FLAGSMITH_ENVIRONMENT_KEY` unset, resolution returns env-var values for every role without any network call. Verified by unit test.
- [ ] **AC4**: Killing the Flagsmith SDK (simulated outbound block) returns env-var-derived values matching the prd-segment state. Dev-role users do NOT see a feature whose `FLAG_X` is 0 in Doppler. Verified by integration test.
- [ ] **AC5**: `soleur:flag-set-role <x> prd on` mutates Flagsmith prd-segment AND runs `doppler secrets set FLAG_X=1` in dev + prd. Verified by dry-run + manual smoke.
- [ ] **AC6**: `soleur:flag-set-role <x> dev off` is REJECTED when prd is currently on (skill contract). Verified by skill unit test.
- [ ] **AC7**: `soleur:user-set-role harry@example.com dev` updates Supabase row AND writes Flagsmith trait. Verified by skill unit test + dry-run.
- [ ] **AC8**: Sync `getFlag("dev-signin")` continues to work (env-flag carve-out preserved). Verified by existing unit test.
- [ ] **AC9**: `bun run typecheck` + `bun run test` pass in `apps/web-platform`.

## Rollback strategy

- Code: single revert PR. `users.role` column harmlessly orphaned (drop in a follow-on).
- Operational: `FLAGSMITH_ENVIRONMENT_KEY` cleared from Doppler → every flag falls back to env-var path → behavior identical to PR #2408 baseline.
- Skills: removing from `plugins/soleur/skills/` is a code revert.

## Post-merge verification (PM)

- [ ] PM1: Promote operator (you) to `role=dev` via `soleur:user-set-role`. Verify `/api/flags` returns dev-segment values when logged in.
- [ ] PM2: Flip `kb-chat-sidebar` ON for dev only. Confirm dev-role user sees it, prd-role user does not.
- [ ] PM3: Promote `kb-chat-sidebar` to prd via skill. Confirm Doppler `FLAG_KB_CHAT_SIDEBAR=1` got set in both dev + prd configs (skill side-effect).
- [ ] PM4: In Sentry filter `tag:feature=flagsmith` over the next 24h. Zero unhandled errors expected (SDK failures fall back).

## Out-of-scope (follow-on PRs)

- ADR-022 amendment for retired `FLAG_CC_SOLEUR_GO` (separate small PR).
- Flagsmith UI cleanup: archive the `command-center-soleur-go` feature created during pre-plan setup (it's now imported into segments but has no code consumer).
- More than two roles (e.g. `role-internal-qa`, `role-beta-cohort-1`).
- Per-flag analytics in Sentry (would need a wrapper around `isFeatureEnabled` that emits `feature.evaluated`).
- Auto-cleanup of stale flags (no flag should outlive its feature; deferred until we have >5 flags).
