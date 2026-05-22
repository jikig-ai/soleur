---
name: user-set-role
description: "This skill should be used to promote a Soleur user into the `dev` flag-targeting cohort (or demote back to `prd`). Updates `public.users.role` via service-role Supabase + writes the `role` trait to the Flagsmith identity so segment overrides take effect."
---

# user-set-role

The only approved path for mutating `public.users.role`. Migration 054's
trigger blocks non-service-role connections from updating that column, so
direct PostgREST writes from authenticated users always fail — this skill
runs the service-role write + the Flagsmith identity trait write together
to keep the two sides aligned.

## When to use

- Promoting yourself or a teammate to the `dev` cohort so you receive
  per-role flag previews before flags promote to `prd`.
- Demoting a user back to `prd` when they no longer need preview access.

## When NOT to use

- Bulk role changes (>5 users at once) — script doesn't batch; run
  individually for now.
- Trying to promote a Supabase user that doesn't exist — skill fails
  early with a clear error.

## Arguments

<arguments> #$ARGUMENTS </arguments>

Required positional args: `<email-or-userId> <prd|dev>`.
- `<email-or-userId>`: email address (resolved to UUID via Supabase) OR
  a Supabase auth UUID directly.
- `<prd|dev>`: target role.

Flag `--dry-run` runs lookup + diff (no writes).

## Prerequisites

- `doppler` CLI authenticated; access to `soleur/prd` config (for
  `SUPABASE_SERVICE_ROLE_KEY` + `NEXT_PUBLIC_SUPABASE_URL`).
- `doppler` access to `soleur/cli_ops` (for
  `FLAGSMITH_MANAGEMENT_API_KEY`).
- `curl` + `python3` on PATH.

## Procedure

```bash
bash plugins/soleur/skills/user-set-role/scripts/set-role.sh <email|uuid> <prd|dev> [--dry-run]
```

The script (full procedure in [scripts/set-role.sh](./scripts/set-role.sh)):

1. **Validate args** — role in `{prd, dev}`; identifier looks like
   email-or-UUID.
2. **Resolve userId** — if input is an email, look up via service-role
   Supabase REST: `GET /rest/v1/users?email=eq.<email>&select=id,role`.
   If input is UUID, use directly + read current role for the diff.
3. **Diff** — if `current_role == target_role`, exit 0 ("no change").
4. **Print pre/post** — user UUID + email + current role + target role.
5. **Operator ack** — literal `yes` per
   `hr-menu-option-ack-not-prod-write-auth`.
6. **Update Supabase** — `PATCH /rest/v1/users?id=eq.<uuid>` with
   `{ "role": "<target>" }`. Service-role JWT bypasses the trigger.
7. **Update Flagsmith identity trait** — POST to
   `/api/v1/environments/{env_id}/identities/{userId}/traits/` with
   `trait_key=role`, `trait_value=<target>`. Done for BOTH dev (env 90722)
   and prd (env 90721) so the user's flag resolution matches in either
   environment.
8. **Re-verify** — re-read `users.role` AND the Flagsmith identity trait
   in each env. Assert matches `<target>`.

## Exit codes

- `0` — success / no-op / dry-run clean.
- `1` — validation failure (bad role, malformed identifier).
- `2` — prerequisite missing (Doppler, env vars).
- `3` — user not found in Supabase.
- `4` — Supabase write failed.
- `5` — Flagsmith trait write failed (Supabase already updated;
  re-run is idempotent on Supabase side and will re-apply the trait).

## Sharp edges

- **30s flag-cache TTL.** The user's resolved flag values won't pick up
  the new role until the per-replica per-role cache TTL elapses (max 30s).
  Skill prints this hint after success.
- **Trait write is fire-and-forget on the identity side.** Flagsmith
  upserts traits; calling with the same value twice is a no-op.
- **Email collision.** If two users somehow share an email (shouldn't
  happen — `public.users(email)` is unique), the skill aborts with
  exit 3 + the conflicting UUIDs.

## Cross-references

- Migration: `apps/web-platform/supabase/migrations/054_users_role_column.sql`
- ADR: `knowledge-base/engineering/architecture/decisions/ADR-038-feature-flags-flagsmith.md`
- Sibling skills: `soleur:flag-set-role`, `soleur:flag-create`
