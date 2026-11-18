---
title: Migration checklist — feat-one-shot-12600 (mig 187, 188)
date: 2026-11-18
plan: knowledge-base/project/plans/2026-11-12-fix-syncpush-kb-only-push-plan.md
migration: apps/web-platform/supabase/migrations/187_workspace_kb_sync_held_files.sql, apps/web-platform/supabase/migrations/188_workspace_kb_sync_pull_blocked.sql
---

# Migration checklist — `187_workspace_kb_sync_held_files.sql`, `188_workspace_kb_sync_pull_blocked.sql`

187 adds the held-files count columns on `public.workspaces` and the read RPC; 188 adds the pull-blocked
column and widens the RPC (task 10.1-10.3, rulings D29, D42 restore).

## dev apply — done

CI tenant-integration applied 187 and 188 to the dev Supabase project; the dev-ledger parity check is
clean (`violations=0`). 187 is byte-identical to the blobs dev applied (pinned by a blob-id test).

## prd apply — pending

prd application is deferred to merge time: the `migrate` and `verify-migrations` jobs in
`web-platform-release.yml` apply the migrations and run the `apps/web-platform/supabase/verify/` sentinels
on the prd deploy. Deploy order (D29(2)): the migrations apply before the code that writes the columns;
rollback is the code first, then the down migrations. Post-merge, postmerge confirms the columns via a
read-only REST GET.
