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
