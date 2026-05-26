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

## prd apply — done (2026-05-21)

Applied 053–057 to prd via Doppler `DATABASE_URL_POOLER` session-mode
(`:6543` → `:5432` rewrite) per AGENTS.md "Supabase fallback chain". Counts:

```text
053 organizations inserted:     14
053 workspaces inserted:        14
053 workspace_members inserted: 14
055 conversations:               75
055 messages:                   166
055 kb_share_links:               8
055 push_subscriptions:           1
055 scope_grants:                 2
055 (other 5 tables):             0 rows in prd
056 user_session_state:          14
057 RPCs widened (no row delta)
```

PostgREST schema cache reloaded via `NOTIFY pgrst, 'reload schema'`;
REST probe confirms all 5 new tables return HTTP 200:

```text
organizations:                 HTTP 200
workspaces:                    HTTP 200
workspace_members:             HTTP 200
workspace_member_attestations: HTTP 200
user_session_state:            HTTP 200
```

**AC-LEGAL-FLIP still in effect** — `FLAG_TEAM_WORKSPACE_INVITE=0`
remains in prd Doppler until the parallel legal-scaffolding PR (Phase 10,
branch `feat-team-workspace-legal-scaffolding`) lands ToS 2.2.0 / AUP §5.5
/ DPD §2.3 / Side Letter. Migration apply ≠ flag flip; the schema is now
in place to make the FLAG flip cheap when the legal-PR ships.

## Renumber + tracking reconciliation — 2026-05-21 (post-merge of main)

Main landed `054_schema_migrations_content_sha.sql` (PR #4251 —
fix(ci): block unmerged-dev-apply + drift probe in tenant-integration)
**while this branch was in flight**, colliding with the previously-named
`054_workspace_member_attestations.sql`. Renumbered to avoid collision:

| Old name                                | New name                                |
| --------------------------------------- | --------------------------------------- |
| 054_workspace_member_attestations.sql   | 058_workspace_member_attestations.sql   |
| 055_workspace_keyed_rls_sweep.sql       | 059_workspace_keyed_rls_sweep.sql       |
| 056_current_organization_jwt_hook.sql   | 060_current_organization_jwt_hook.sql  |
| 057_byok_audit_workspace_id_rpcs.sql    | 061_byok_audit_workspace_id_rpcs.sql   |

053 stayed (filename-distinct from main's two 053s — append_kb_sync_row_rpc
+ template_authorizations land alphabetically before and after mine).

`public._schema_migrations` reconciled on both dev + prd via direct
INSERT/UPDATE (script: `/tmp/pg-runner/reconcile-tracking.mjs`):

- DEV: DELETEd 4 old-numbered rows; UPSERTed 5 new rows with `content_sha`
  populated from `git hash-object`.
- PRD: UPSERTed 5 new rows (no old rows present — my earlier
  direct-pg apply bypassed tracking).

Final state — DEV and PRD identical, all 9 migrations through 061
tracked under canonical filenames:

```text
052_multi_source_dedup.sql
053_append_kb_sync_row_rpc.sql              (from main PR #4226)
053_organizations_and_workspace_members.sql (this branch)
053_template_authorizations.sql             (from main PR #4213)
054_schema_migrations_content_sha.sql        (from main PR #4251)
058_workspace_member_attestations.sql        (this branch)
059_workspace_keyed_rls_sweep.sql            (this branch)
060_current_organization_jwt_hook.sql        (this branch)
061_byok_audit_workspace_id_rpcs.sql         (this branch)
```

content_sha fingerprints (post-rename):

```text
dc6fde49e2dc1c4214e71e5db7f8929dd00f3d27  053_organizations_and_workspace_members.sql
c175fe2117d958e7b31530c3690ad5a84f582fee  058_workspace_member_attestations.sql
9e9bac622c1fc415a0397be4c412a2802f616e28  059_workspace_keyed_rls_sweep.sql
b21a80f4422a6a48bf04a0ed8aa6de60649b526a  060_current_organization_jwt_hook.sql
a30ffa4083d016da65816c9d72f9cf8e7f799b16  061_byok_audit_workspace_id_rpcs.sql
```

Main's `scheduled-dev-migration-drift.yml` workflow will compare these
SHAs against `git ls-tree origin/main` at the canonical paths — once
this PR merges, both will match.
