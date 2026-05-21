---
title: Rollback runbook — feat-team-workspace-multi-user
spec: knowledge-base/project/specs/feat-team-workspace-multi-user/spec.md
plan: knowledge-base/project/plans/2026-05-21-feat-team-workspace-multi-user-plan.md
adr: knowledge-base/engineering/architecture/decisions/ADR-038-team-workspace-multi-user-organizations-and-workspace-members.md
issue: 4229
pr: 4225
date: 2026-05-21
brand_survival_threshold: single-user incident
---

# Rollback runbook — `feat-team-workspace-multi-user`

This runbook covers the incident-response path if the team-workspace migrations (053–056), the workspace-keyed RLS sweep, the bwrap-mount rewrite, or the feature-flagged invite UI causes a `single-user incident` (defined: any cross-user `messages` / `kb_share_links` / filesystem read; any BYOK key-mis-routing; any cross-workspace attestation visibility).

Land BEFORE migration 053 commits, per AC-G.

## Trigger conditions

Open this runbook when any of the following fires in production:

1. **RLS predicate over-returns TRUE.** A user authenticated as `auth.uid() = A` retrieves a row whose owner is `auth.uid() = B` and they are NOT co-members of any workspace. Detection: Sentry alert wired in Phase 8.3 (`scheduled-membership-health.yml` RLS-probe + cross-workspace fixture); user-reported observation of unfamiliar workspace data.
2. **BYOK cost mis-routing.** `audit_byok_use` row with `user_id = A` AND `workspace_id = W` where A is not a member of W. Detection: scheduled liveness probe diffs `audit_byok_use.workspace_id` against `workspace_members(user_id, workspace_id)`.
3. **Filesystem read across workspaces.** A sandboxed agent run reads a file in `/workspaces/<other_workspace_id>/`. Detection: bwrap audit log + `sandbox.ts:isPathInWorkspace` denial counter; Sentry breadcrumb on every denial.
4. **WS session not aborted on member removal.** A removed member's WebSocket continues receiving messages from the workspace they were removed from. Detection: Sentry breadcrumb on `MEMBERSHIP_REVOKED` close-code emission count vs expected count from `remove_workspace_member` RPC invocations.
5. **Backfill non-idempotency.** Re-running migration 053 on a populated DB produces non-zero `RAISE NOTICE` row-count for organizations / workspaces / workspace_members. Detection: re-apply on dev → inspect log.

## 6-step incident response

### Step 1 — Disable the feature flag (immediate, < 60 seconds)

```bash
doppler secrets set FLAG_TEAM_WORKSPACE_INVITE=0 -p soleur -c prd
# Cloud deploy reads from Doppler on container restart; bounce the web pod:
kubectl rollout restart deployment/web-platform -n soleur-prd
# OR for fly.io / single-host substrate:
fly machine restart --app soleur-prd
```

The 2-key gate evaluates `FLAG_TEAM_WORKSPACE_INVITE AND TEAM_WORKSPACE_ALLOWLIST_ORG_IDS.includes(orgId)`. Setting the env to `0` instantly returns `false` for all orgs, route 404s the `/dashboard/settings/team` page, and `isOrgFlagEnabled()` returns false everywhere. **Data is NOT migrated by this step** — the migrations stay applied; new invites are blocked.

Verify: `curl -I https://soleur.ai/dashboard/settings/team` returns `404`.

If the incident is feature-flag-scoped (UI-only) and the data layer is unaffected, **stop here**. Skip to Step 5 (notification) and Step 6 (post-mortem). The RLS sweep + filesystem rewrite remain in place because they were applied BEFORE the flag flipped on (the data shape is correct for solo users post-backfill; rolling back the data layer is only required if the data layer itself is corrupted).

### Step 2 — Down-migrate 056 → 053 (data-layer rollback)

Required only when the migration itself is the failure source (RLS predicate, helper SECURITY DEFINER boundary, backfill correctness, or symlink/filesystem path).

```bash
# From the worktree root, with Doppler-injected DATABASE_URL_POOLER
# (session-mode :5432, NOT :6543 — transaction mode rejects multi-statement DDL).

# Order matters: 056 → 055 → 054 → 053. Each down-migration restores the
# pre-N state including any policies dropped in N.

cd apps/web-platform
doppler run -p soleur -c prd -- bun run scripts/apply-migration.ts \
  --file supabase/migrations/056_current_organization_jwt_hook.down.sql

doppler run -p soleur -c prd -- bun run scripts/apply-migration.ts \
  --file supabase/migrations/055_workspace_keyed_rls_sweep.down.sql

doppler run -p soleur -c prd -- bun run scripts/apply-migration.ts \
  --file supabase/migrations/054_workspace_member_attestations.down.sql

doppler run -p soleur -c prd -- bun run scripts/apply-migration.ts \
  --file supabase/migrations/053_organizations_and_workspace_members.down.sql
```

Each `.down.sql` is the exact inverse of its forward migration, ordered to drop dependents before dependencies (policies → triggers → tables; RLS predicate restoration is the LAST step of each 055 reversal so that the table doesn't briefly become unprotected).

**Verify after each down-migration:**

```sql
-- After 056 down:
SELECT current_database(), proname FROM pg_proc WHERE proname = 'set_current_organization_id';  -- expect 0 rows
-- After 055 down: spot-check that old policies are back
SELECT polname FROM pg_policy WHERE polname LIKE '%workspace_member%';  -- expect 0 rows
SELECT polname FROM pg_policy WHERE polname IN ('Users can view their own conversations', ...);  -- expect prior set
-- After 054 down:
SELECT 1 FROM information_schema.tables WHERE table_name = 'workspace_member_attestations';  -- expect 0 rows
-- After 053 down:
SELECT 1 FROM information_schema.tables WHERE table_name IN ('organizations', 'workspaces', 'workspace_members');  -- expect 0 rows
SELECT proname FROM pg_proc WHERE proname = 'is_workspace_member';  -- expect 0 rows
```

### Step 3 — Restore old RLS policies

Migration 055 dropped `auth.uid() = user_id` predicates on 9 tables and replaced them with `is_workspace_member(workspace_id, auth.uid())`. The 055 down-migration restores the original predicates verbatim, sourced from the migration files where the original policies were defined:

| Migration | Table | Original policies to restore |
|---|---|---|
| 001 | conversations, messages | `Users can view/insert/update/delete own conversations`, same for messages |
| 017 | kb_share_links | `Users can manage their own share links` |
| 020 | push_subscriptions | 5 policies (SELECT + INSERT WITH CHECK + UPDATE + DELETE) |
| 029 | concurrency_slots | `Users can SELECT own concurrency slots` |
| 037 | audit_byok_use | founder_id-keyed SELECT policy |
| 041 | dsar_export_jobs | `Users can view their own DSAR jobs` |
| 048 | scope_grants | `Users can SELECT own scope grants` |
| 052 | multi_source_dedup | founder_id-keyed SELECT policy |

The `.down.sql` for 055 contains the verbatim CREATE POLICY statements copy-pasted from the original migrations.

### Step 4 — Drop filesystem symlinks (workspace_id → userId reverse)

If migration 053 + Phase 2 filesystem migration landed before the incident, the symlink `/workspaces/<userId>/` → `/workspaces/<workspace_id>/` was created on every deploy. The reverse:

```bash
# On EACH application host (or in a Kubernetes Job batching them):
for ws_dir in /workspaces/*; do
  if [[ -L "$ws_dir" ]]; then
    target=$(realpath "$ws_dir")
    # If the target is a workspace_id-keyed dir AND the symlink name is a userId,
    # this is a backfilled-solo-workspace self-link (workspaces.id = owner_user_id);
    # the symlink is a no-op and can be left in place OR replaced with a real dir.
    if [[ "$(basename "$ws_dir")" == "$(basename "$target")" ]]; then
      continue  # self-link; no action needed
    fi
    # Real divergent symlink: post-invite workspace. Materialize the directory
    # at the userId-keyed path to preserve agent run access during incident.
    rm "$ws_dir"
    cp -r "$target" "$ws_dir"
  fi
done
```

For backfilled solo workspaces, `workspaces.id = owner_user_id` (ADR-038 N2), so the symlink is a self-link and the down-migration is a no-op. Only multi-member workspaces have symlinks pointing at a different target — those are the ones to materialize.

### Step 5 — Notify affected members

Required if Step 1 alone did not contain the incident (i.e., data leaked or RLS over-returned).

1. Query the impact set: `SELECT DISTINCT user_id FROM <affected_table> WHERE <leak_predicate>` (the specific query depends on the failure mode; e.g., for an over-permissive RLS read, query the audit log for cross-tenant SELECT events).
2. Email each affected user via the standard incident-comms template at `knowledge-base/legal/templates/data-incident-notification.md` (TODO: create if not present).
3. Internal: post a P1 incident summary in `#sev1` Discord channel.
4. Legal: notify CLO of the data category exposed (Art. 33 / GDPR 72-hour clock if a Personal Data breach). Wait for CLO sign-off on the regulator-notification decision.

### Step 6 — Post-mortem via /soleur:compound

```bash
# From the soleur worktree:
/soleur:compound
```

Capture:
- Failure mode (which trigger condition fired)
- Root cause (predicate over-return / backfill non-idempotency / etc.)
- Why the pre-merge gates (sentinel sweep AC4, RLS probe, multi-agent review) failed to catch it
- New gate or test to prevent recurrence
- Reference IDs: PR #4225, ADR-038, this rollback.md

File the post-mortem as a learning under `knowledge-base/project/learnings/security-issues/` or `knowledge-base/project/learnings/bug-fixes/` per category.

## Rolling-deploy safety notes

- **RPC signature changes use overloading, not DROP+CREATE.** Per ADR-038 + `2026-05-12-stub-handlers-as-silent-undercount-vectors`. Old pods continue resolving v1 signatures during the rolling deploy window.
- **Symlinks for legacy `/workspaces/<userId>/` stay in place for one release cycle.** Read-only call sites in `dsar-export.ts`, `sandbox.ts`, `tool-labels.ts`, `agent-runner.ts` keep their existing paths during the transition.
- **`workspace_id NOT NULL` is the LAST step of migration 055.** Backfill completes BEFORE the constraint adds. A failed backfill leaves the column NULLABLE and the old policies still in place (drop-policies is sequenced after backfill succeeds).
- **Backfill is idempotent.** `IS DISTINCT FROM` discriminator + `WHERE NOT EXISTS` guards. Re-running 053 against a populated DB logs `0 rows`.

## What this runbook does NOT cover

- **Total Postgres failure / Supabase availability incident.** That is a substrate incident; refer to Supabase status + Doppler config rollback procedures.
- **BYOK key compromise.** Per-user keys; rotate via the BYOK rotation flow. Workspace boundary is unrelated.
- **Pre-existing tenant-isolation incidents.** PR-A / PR-B / PR-C / PR-D tenant-isolation regressions are unrelated to this PR; refer to the closeout notes in `.service-role-allowlist`.
