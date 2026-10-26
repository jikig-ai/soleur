---
title: Egress audit rollup — preconditions for enabling collection
status: active
issue: 9545
related_adrs: [ADR-288]
---

# Egress audit rollup — preconditions for enabling collection

PR1 of #9545 ships the pipeline dark. Enabling collection (the Flagsmith flag `egress-audit-collection`, evaluated per organisation) is an
operator authorization and a separate act from merging. Nothing below is done by the PR. Do not enable collection for any workspace until
every box for that scope is checked.

## Any workspace, including a Jikigai-owned canary

- [ ] The Flagsmith feature `egress-audit-collection` exists (`bash plugins/soleur/skills/flag-create/scripts/create.sh egress-audit-collection --flagsmith-only --description "..."`, a typed-`yes` TTY step) and is OFF by default.
- [ ] The global env mirror `FLAG_EGRESS_AUDIT_COLLECTION` is `0` (or unset) in Doppler `prd`. The route refuses to run in production while it is `1`.
- [ ] The app container was restarted after the `EGRESS_AUDIT_INGEST_TOKEN` secret was created (it is read at container start). A POST without the secret answers 202 and drops the batch.
- [ ] Nothing in PR1 pages anyone when ingest is wrong: the route's reject and error events are queryable in Sentry (debounced warns and errors), the Vector markers in Better Stack, and the probe is manual. Treat this as "queryable, not paged" until the probe below is scheduled and alerts.
- [ ] `scripts/egress-audit-retention-check.sh` runs on a schedule (for example the existing supabase watchdog or a follow-through) with `EGRESS_AUDIT_EXPECT_COLLECTION=1`, `EGRESS_AUDIT_CANARY_WORKSPACES=<ids>` and the Better Stack query credential, and its failure alerts someone. It is not scheduled anywhere in PR1.
- [ ] `workspace_egress_audit_rollup` is moved from `DSAR_TABLE_EXCLUSIONS` to `DSAR_TABLE_ALLOWLIST` in `apps/web-platform/server/dsar-export-allowlist.ts` (or the exclusion is re-justified in writing by the CLO) before collection is enabled for an external workspace; the Art. 15 export must cover a solo workspace's rows without the runbook.
- [ ] `erase_egress_audit_rollup_for_requester` is applied (migration 162) so an explicit erasure request has a single audited path.

## Any external workspace (in addition)

- [ ] PR2 of #9545 has merged (member read function and audit view, card, wireframe, DPIA trigger t6 re-screen at addendum section 12; there is no member read policy and no read route).
- [ ] The owner notice (email and in-app) has been out for at least 7 days.
- [ ] The CLO-reviewed public wording is merged and the counsel items recorded on the PR are resolved or accepted.
- [ ] The operator has explicitly authorized the production flip.

## After enabling the canary

- [ ] Read `pg_stat_statements.wal_bytes` for `ingest_egress_audit_rollup` and replace the WAL estimate in ADR-288 with the measurement.
- [ ] Read the newest `bucket_start` and the Better Stack `SOLEUR_EGRESS_AUDIT_THROTTLED*` markers for the canary workspace.

## egress-audit-read-failure alert triage

The Sentry issue-alert `egress-audit-read-failure` pages when the member audit view or the Scope Grants card fails to read the rollup. Everything below runs from Sentry and the Supabase SQL console; there is no SSH, `docker exec` or server-side shell step.

1. **First step: search Sentry for `feature:egress-audit-read op:<x>`** (for example `feature:egress-audit-read op:rpc_error`). Open the newest event and read its `pg_code` tag (SQLSTATE only, never message text). To read the issue inline: `doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event <issue-id>` (see `sentry-issue-read.md`).
2. **Paged ops** (these trigger the alert):
   - `rpc_error`: `get_egress_audit_summary` returned an error. Read `pg_code`. `42501` here means the engine refused the call ("permission denied for function"), not the member check (the in-body denial renders the "no longer have access" state and is not mirrored).
   - `rpc_timeout`: the page's RPC did not answer within its bound; the `authenticated` role's `statement_timeout` is 8 s. Check whether one workspace has an unusually large window (see the accepted residuals in ADR-288).
   - `workspace_read_error`: reading the member's workspace pointer threw.
3. **Searchable but unpaged ops** (decorative or secondary reads; the page or card degrades but stays up): `hint_timeout`, `hint_rpc_error`, `hint_workspace_read`, `org_read`, `flag_eval`, `web_access_read`. A burst of `flag_eval` means the page showed the "unknown" recording state while Flagsmith was unreachable.
4. **Sudden fleet-wide `forbidden`-looking failures: check for a lost EXECUTE grant first.** A migration or a Supabase default-privileges change can drop `GRANT EXECUTE ... TO authenticated` on `get_egress_audit_summary`. That surfaces as a paged `rpc_error` with `pg_code=42501` for every member at once. In the Supabase SQL console, run `SELECT has_function_privilege('authenticated', 'public.get_egress_audit_summary(uuid, integer, text)', 'EXECUTE');` (read-only); `false` confirms it. The fix is a new migration restoring the grant (never an edit of an applied one); `apps/web-platform/supabase/verify/177_egress_audit_summary_rpc.sql` lists the expected grant set.
5. **Unexpected `pg_code` values** (`57014` query cancelled by the timeout, `53xxx` resource limits, `08xxx` connection) point at the database, not the feature: check the Supabase status and the `supabase` watchdog before touching code.
