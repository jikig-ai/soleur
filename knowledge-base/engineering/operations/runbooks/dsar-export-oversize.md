---
category: compliance
tags: [dsar, gdpr, art-15, art-20, oversize, fallback, manual-export]
date: 2026-05-12
---

# DSAR Export — Oversize Account Fallback

**Issue:** #3637
**Plan:** `knowledge-base/project/plans/2026-05-12-feat-dsar-art15-export-endpoint-plan.md`
**Related:** `dsar-export-failed-job.md`, `dsar-export-oversize.sh`
**Compliance:** GDPR Art. 12(3) — 30-day response window with one possible 60-day extension

## Symptom

A user's automated DSAR export at `/dashboard/settings/privacy` produced
a `failed` job with `failure_reason = 'archive_error'` (or `job_timeout`)
because the bundle exceeded the `DSAR_EXPORT_SIZE_CAP_MB` configured cap
(default 1024 MB per plan TR4, validated by the Phase 0 spike).

Symptoms in monitoring:

- `mirrorWithDebounce(*, "dsar-export-failed")` Sentry alert fires.
- The user's `dsar_export_jobs` row for this attempt has `status='failed'`
  with `failure_reason` set to `archive_error` (size cap exceeded inside
  `buildArchiveToDisk`) or `job_timeout` (the worker hit the 30-min
  `AbortController` cap before finishing).
- The `dsar_export_failed_email` Resend log shows the user has been
  notified with the standard "we weren't able to package your data within
  the time limit" copy.

## Why this happens

The TR4 cap is conservative: 1 GiB sits at the ~40 % headroom margin
under the 2 GB Hetzner allocation ceiling, derived from the spike's
measured Δ-RSS ≈ 1.1 × payload coefficient. Accounts that exceed it are
typically heavy-attachment power users (image-rich conversations, large
KB workspace files). The cap is honest: shipping a bundle that OOM-kills
the Node process mid-stream is worse than asking the user to use the
operator fallback.

## Operator response (within 24h of alert)

1. **Acknowledge the user.** Reply to the user's email (their account
   address from `auth.users.email`) within 24 hours per CNIL guidance.
   Template:

   ```
   Subject: Your Soleur data export — we're packaging it manually

   Hi <name>,

   Your data export request from <date> exceeded our automated bundle
   size limit (your account has more data than the self-serve flow
   currently supports). We're packaging your bundle manually and will
   email you the download link within <X> business days.

   Per GDPR Article 12(3), we have 30 days to fulfil your request; we
   typically deliver within 7 days for oversize accounts. If you need
   it faster, let us know.

   — The Soleur team
   ```

2. **Run the helper script.** From `apps/web-platform/`:

   ```bash
   doppler run -p soleur -c prd -- \
     ./scripts/dsar-export-oversize.sh <user-id> <out-dir>
   ```

   The script:
   - Reads every allowlisted SQL table for the user with the same
     per-row WHERE + assertReadScope-equivalent invariant the
     automated worker uses.
   - Downloads `chat-attachments/<userId>/` blobs via service-role.
   - rsyncs `/workspaces/<userId>/` from the Hetzner host via SSH
     (skipping symlinks with `--no-links`).
   - Emits a `manifest.json` with the same AC23 conventions as the
     automated flow.
   - Bundles into a multi-volume ZIP (split at 4 GB so the user can
     download each part separately).

3. **Verify the bundle.** Spot-check three things before delivering:

   ```bash
   # (a) Every JSON file's first row is owned by the requested user.
   jq -r '.rows[0].user_id // .rows[0].id // .rows[0].founder_id' \
     <out-dir>/tables/*.json
   # All values MUST equal <user-id>.

   # (b) No path under attachments/ contains '..' or starts with a
   # different user id segment.
   find <out-dir>/attachments -type f -name "*" | \
     awk -F/ '{ if ($0 ~ /\.\./ || $4 != "'<user-id>'") print "LEAK: " $0 }'

   # (c) Manifest declares the same SHA-256 we compute now.
   sha256sum -c <out-dir>/manifest.sha256
   ```

4. **Deliver.** Upload each volume to a one-time Cloudflare R2 bucket
   with a 7-day TTL pre-signed URL. Email the user with the link(s).
   Record an audit row in `dsar_export_audit_pii` via the manual
   service-role console with `event_type='enqueue'` and a note in
   `user_agent`: `"operator-fallback: dsar-export-oversize.sh"`.

5. **Close the loop.** Update the corresponding `dsar_export_jobs` row
   to `status='delivered'` with a `failure_reason` of `null` and
   `bundle_size_bytes` set to the actual size; this is the source of
   truth for AC-PM-4 verification.

## When NOT to use this runbook

- If the failure reason is anything other than `archive_error` /
  `job_timeout` (size-related), use `dsar-export-failed-job.md` instead.
- If the user is asking to receive the bundle in any non-ZIP format
  (CSV, PDF), reply that we deliver structured ZIPs only per the
  Privacy Policy §4.7 enumeration and DPD §5.3(e). Custom-format
  requests are out of scope for Art. 15 / Art. 20.

## Post-mortem expectations

If the same user hits this twice within a quarter, raise an issue
tagged `dsar-cap-revisit` so the v1.1 plan can re-evaluate the cap
against fresh real-world telemetry per plan rev-2 TR4 caveat.
