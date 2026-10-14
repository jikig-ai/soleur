# Migration checklist — Phase 2 PR A (epic #5274)

Migration: `116_worktree_write_lease.sql` (+ `.down.sql`) + `verify/116_worktree_write_lease.sql`.

## dev apply — done

Applied to DEV Supabase (ref `mlwiodleouzwniehynfz`, NOT prod — `hr-dev-prd`) via
Doppler `DATABASE_URL_POOLER` (session-mode `:5432`), tracked in
`public._schema_migrations` with `content_sha`. Verified live:

- AC1 — up/down round-trip clean (table+3 RPCs created → dropped → re-created).
- AC2 (a–f) / AC4-smoke / AC5 — integration test 8/8 (incl. tombstone gen-climb 1→2→3).
- AC4 — `verify/116` sentinel 18/18 `bad=0` (RLS shape, SECURITY DEFINER + `search_path` pin, REVOKE matrix, service_role grants, proargnames parity).

## prd apply — pending

**Deferred to the post-merge deploy pipeline (canonical mechanism).** The
`migrate` job in `.github/workflows/web-platform-release.yml` runs
`doppler run -c prd -- bash apps/web-platform/scripts/run-migrations.sh` on
merge to `main`, applying `116_worktree_write_lease.sql` to PRD and recording it
in PRD's `public._schema_migrations`. The `verify-migrations` job then runs
`verify/116_worktree_write_lease.sql` against PRD (fails the release on any
`bad>0`). `/ship` Phase 3.6 verifies the PRD apply post-merge.

The migration is **inert at PR A** — no committed code consumes the lease RPCs
(only tests import the client; write-path wiring is PR B), so PRD-apply timing
carries no runtime risk. preflight Check 1 SKIPs on this documented deferral
(`hr-dev-prd` — no manual PRD write pre-merge).
