# Migration checklist — feat-severity-ranked-inbox (#6007)

## Migration
- `apps/web-platform/supabase/migrations/122_inbox_item.sql` (+ `.down.sql`) — new `inbox_item` operational-notification table, RLS, `set_inbox_item_state` RPC, 90d retention cron.

## prd apply — deferred
The prd apply is **deferred to the release workflow** — `web-platform-release.yml#migrate` runs `run-migrations.sh` on merge to `main` (ledger-tracked, single-transaction), applying `122_inbox_item.sql` before the prod deploy cuts over. This is the standard deploy-time apply path for a new-table schema-addition migration; it is NOT applied pre-merge (the table cannot exist in prd before deploy, so preflight Check 1's REST probe correctly 400s until then). Post-merge, `/ship` Phase 7 Step 3.6 verifies the columns are live via the Supabase REST API.

Verify post-deploy:
```
SELECT to_regclass('public.inbox_item');
SELECT to_regprocedure('public.set_inbox_item_state(uuid,text)');
SELECT jobname FROM cron.job WHERE jobname='inbox_item_retention';
```
