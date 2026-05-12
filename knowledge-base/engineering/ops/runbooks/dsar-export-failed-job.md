---
category: compliance
tags: [dsar, gdpr, art-15, art-20, failed-job, triage]
date: 2026-05-12
---

# DSAR Export — Failed Job Triage

**Issue:** #3637
**Plan:** `knowledge-base/project/plans/2026-05-12-feat-dsar-art15-export-endpoint-plan.md`
**Related:** `dsar-export-oversize.md`

## Symptom

A DSAR export job is in `status = 'failed'` with a `failure_reason` set,
and the user has received the standard failure email but is asking why
their export did not complete.

## Triage steps

1. **Pull the audit trail** (service-role console — Supabase Studio or
   `psql` via Doppler):

   ```sql
   select
     j.id, j.status, j.failure_reason,
     j.requested_at, j.started_at, j.completed_at,
     j.bundle_size_bytes
   from public.dsar_export_jobs j
   where j.user_id = '<user-id>'
   order by j.requested_at desc
   limit 10;
   ```

   ```sql
   select event_type, event_at, requester_ip, user_agent
   from public.dsar_export_audit_pii
   where user_id = '<user-id>'
   order by event_at desc
   limit 20;
   ```

2. **Cross-reference Sentry.** Search for the `mirrorWithDebounce` key
   `dsar-export-failed` filtered to the time window of `started_at`.
   The Sentry payload contains a hashed userId (HMAC-SHA256 with
   `SOLEUR_SENTRY_PII_SALT`) — confirm by hashing the user's id
   with the same salt:

   ```bash
   echo -n "<user-id>" | \
     openssl dgst -sha256 -hmac "$SOLEUR_SENTRY_PII_SALT" | \
     awk '{print $2}'
   ```

3. **Classify by `failure_reason`:**

   | Reason | Class | Next step |
   |--------|-------|-----------|
   | `job_timeout` | Size / performance | `dsar-export-oversize.md` |
   | `archive_error` | Size cap exceeded | `dsar-export-oversize.md` |
   | `account_deleted_during_export` | Expected | Confirm via `auth.users` — user is gone; no action needed |
   | (other / null) | Unknown | Continue below |

4. **For unknown reasons,** read the Sentry stack trace. Common
   non-size failure modes seen during dev:

   - **Storage download stall** — `bucket.download(<path>)` returned
     null body or a slow 5xx. Cause: Supabase Storage outage. Action:
     re-enqueue manually after Supabase recovers.
   - **`CrossTenantViolation`** — a per-row WHERE somehow returned a
     row owned by another user. This is a P0 — `mirrorCrossTenantViolation`
     should already have fired with `level: 'fatal'`. Pause the feature
     by flipping `DSAR_EXPORT_ENABLED=false` (returns 503), open a
     `compliance/critical` issue, and run the Phase 10 cross-tenant
     integration test against prd to confirm the breach scope.
   - **`workspace_path` unreadable** — the user's workspace directory
     was deleted out-of-band. Re-enqueueing will succeed; the bundle
     will contain `excluded_files[]` entries for the missing paths but
     no other data is affected.

5. **Re-enqueue if appropriate.** From the service-role console:

   ```sql
   update public.dsar_export_jobs
     set status = 'pending', started_at = null,
         failure_reason = null, completed_at = null
   where id = '<job-id>';
   ```

   The next reaper tick (≤5s) re-claims the job.

6. **Notify the user** if the re-enqueue is expected to succeed. If
   it does not, fall through to `dsar-export-oversize.md` or the
   manual export channel.

## When this becomes a `compliance/critical`

A single `CrossTenantViolation` event is single-user-incident threshold
and triggers Art. 33 (CNIL, 72h) + Art. 34 (data subject). Do NOT wait
for batch confirmation — open the issue immediately.
