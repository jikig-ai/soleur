---
title: Migration apply checklist for feat-team-workspace-multi-user
plan: knowledge-base/project/plans/2026-05-21-feat-team-workspace-multi-user-plan.md
spec: knowledge-base/project/specs/feat-team-workspace-multi-user/spec.md
---

# Migration apply audit

## Migration 053–056 (dev) — 2026-05-21

See [tasks.md §Phase 1 apply status](./tasks.md) — applied via Doppler
`DATABASE_URL_POOLER` (session-mode `:5432` rewrite). 437 organizations
/ 437 workspaces / 437 workspace_members; 1224 audit_byok_use rows
backfilled with `workspace_id`.

## Migration 057 (dev) — 2026-05-21

Applied via Doppler `DATABASE_URL_POOLER` session-mode (`:6543` →
`:5432` rewrite) per AGENTS.md "Supabase fallback chain" because the
Supabase MCP OAuth flow is intermittently rejecting URLs at the
dashboard `auth_id` handoff.

### Verification (post-apply)

```text
write_byok_audit               | p_invocation_id uuid, p_founder_id uuid, p_workspace_id uuid, p_agent_role text, p_token_count integer, p_unit_cost_cents integer | SECURITY DEFINER | search_path=public, pg_temp
record_byok_use_and_check_cap  | p_invocation_id uuid, p_founder_id uuid, p_workspace_id uuid, p_agent_role text, p_token_count integer, p_unit_cost_cents integer | SECURITY DEFINER | search_path=public, pg_temp
```

- Both RPCs present at the 6-arg signature with `p_workspace_id uuid` in position 3.
- No leftover 5-arg overload (DROP+CREATE was clean).
- `SECURITY DEFINER` preserved on both.
- `search_path = public, pg_temp` pinned per `cq-pg-security-definer-search-path-pin-pg-temp`.
- `service_role`-only `GRANT EXECUTE`; `REVOKE ALL FROM PUBLIC, anon, authenticated`.

### Smoke INSERT

```sql
SELECT public.write_byok_audit(
  gen_random_uuid(),
  '<founder_id>',
  '<workspace_id>',  -- owner_user_id under N2 invariant for solo
  'phase3-smoke',
  0,
  0
);
```

Row insert succeeded; `audit_byok_use.workspace_id NOT NULL` constraint
satisfied. Row deleted after verification (WORM trigger temporarily
disabled to allow cleanup).

## Migration 053 idempotency re-run (dev) — 2026-05-21

Re-applied 053–057 to dev (the previous apply had been rolled back
between runs; dev had no `organizations`/`workspaces`/`workspace_members`
tables at re-entry). Apply path: same Doppler `DATABASE_URL_POOLER`
session-mode (`:6543` → `:5432`) wrapper via `pg` (node-pg) per AGENTS.md
"Supabase fallback chain". Counts:

```text
053 organizations inserted:     1128
053 workspaces inserted:        1128
053 workspace_members inserted: 1128
055 conversations:               186
055 messages:                    176
055 audit_byok_use:              1265
055 scope_grants:                  74
055 (other 5 tables):              0 (no rows in dev)
056 user_session_state:         1128
057 RPCs widened (no row delta)
```

Then re-ran the 053 backfill DO block (Phase 6.1 idempotency check) —
`WHERE NOT EXISTS` discriminator + `name IS NULL` defensive guard hold:

```text
[053-rerun-idempotency] organizations inserted:     0
[053-rerun-idempotency] workspaces inserted:        0
[053-rerun-idempotency] workspace_members inserted: 0
```

AC1 backfill idempotency verified end-to-end. Apply path is replay-safe
under the same pattern documented in
`2026-03-20-gdpr-remediation-migration-discriminator-strategy`.

## prd apply — pending

Deferred to the prd-apply operator window. Sequence:

1. Apply migrations 053, 054, 055, 056, 057 in order (or 057 alongside
   the 055 apply — they cannot land separately; the legacy 5-arg RPC
   would fail under the NOT NULL constraint added by 055).
2. Re-run the verification query above against the prd project ref to
   confirm signatures + grants.
3. Verify post-apply that no in-flight cc-soleur-go / agent-runner
   session is blocked on the legacy RPC signature (the deploy of the
   Phase 3 application code must precede or coincide with the prd
   migration apply, NOT lag — see migration 057 header §Sequencing).
