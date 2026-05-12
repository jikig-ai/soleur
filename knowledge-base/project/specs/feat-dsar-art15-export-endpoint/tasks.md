---
title: "Tasks: GDPR Art. 15 + Art. 20 DSAR self-serve export endpoint"
type: feat
date: 2026-05-12
plan: knowledge-base/project/plans/2026-05-12-feat-dsar-art15-export-endpoint-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — feat-dsar-art15-export-endpoint

Derived from plan rev-2 (post 5-agent panel sign-off). Phase ordering is load-bearing per Kieran P0 fix; tests land WITH the module they cover, not at the end. Execute via `skill: soleur:work`.

## Pre-flight

- 0.1 Confirm CPO sign-off captured in conversation (per `requires_cpo_signoff: true` frontmatter — plan-time gate before `/work` proceeds).
- 0.2 Confirm worktree at `.worktrees/feat-dsar-art15-export-endpoint/` and PR #3634 exist; `pwd` shows worktree path.
- 0.3 Re-grep all citations from plan's Research Reconciliation table to confirm no further drift since rev-2.

## Phase 0 — Streaming-archive spike (gating per AC9)

- 0.4 Create `apps/web-platform/scripts/spike-dsar-streaming-upload.ts`:
  - Generate synthetic 100 MB / 500 MB / 1 GB / 2 GB tarballs (PRNG-seeded — `cq-test-fixtures-synthesized-only`)
  - Stream via `archiver` → Bun `Readable.toWeb()` → Supabase Storage `upload()`
  - Measure peak RSS via `process.memoryUsage().rss` polled every 250 ms; wall-clock; SHA-256 round-trip
- 0.5 Run spike against dev Supabase project; capture results
- 0.6 Write `apps/web-platform/scripts/spike-dsar-streaming-upload-report.md` with the measurement table; declare TR4 cap based on largest tier where peak RSS stays under 2 GB; record Bun runtime invariant per S8
- 0.7 If spike fails entirely → pivot to disk-then-upload fallback (Hetzner local disk + `fstat` ino verify + stream-from-file `upload()`); document in spike report
- **GATE**: Phase 1 cannot start until spike report exists and TR4 cap is declared

## Phase 1 — Migrations + ADR

- 1.1 Write ADR `knowledge-base/engineering/architecture/decisions/0NN-dsar-export-substrate-and-audit-retention.md` capturing: Q1 substrate decision; Q-extra Art. 17 vs 24-mo conflict; Q-credential C1 worker-auth decision; Bun runtime invariant
- 1.2 Write `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql`:
  - `dsar_export_jobs` table (user-visible RLS) — NO `owner_jwt_encrypted` column per C1
  - `dsar_export_audit_pii` table (admin-only)
  - 3 SECURITY DEFINER RPCs: `write_dsar_export_audit_pii`, `anonymise_dsar_export_audit_pii`, `claim_next_dsar_export_job`
  - All RPCs: `SET search_path = public, pg_temp` + `public.`-qualified relations + `REVOKE ALL ... FROM PUBLIC, anon, authenticated; GRANT EXECUTE TO service_role;`
  - WORM trigger `dsar_export_audit_pii_no_mutate` with three gates per AC29: GUC + `current_user='service_role'` + function-OID allowlist
  - Restrictive RLS policy on `owner_session_id`
  - Partial unique index for 1/24h compliance idempotency
  - pg_cron retention sweep (TR13)
  - pg_cron TTL-expiry sweep (TR14)
- 1.3 Write `apps/web-platform/supabase/migrations/042_dsar_exports_storage_bucket.sql`: private bucket + folder-prefix RLS
- 1.4 Write `apps/web-platform/test/migration-rpc-grants.test.ts` (generalised file-parse migration test per Kieran P1) — verifies AC13 + AC14 across ALL migrations
- 1.5 Write `apps/web-platform/test/dsar-worm-guc-sites.test.ts` per AC29 + S1 (asserts `SET app.dsar_audit_anonymise_in_progress` appears exactly once)
- 1.6 Run both file-parse tests; iterate until passing
- 1.7 Apply migrations to **dev** Supabase first per `hr-dev-prd-distinct-supabase-projects`; verify via REST API

## Phase 2 — Cross-tenant + audit primitives

- 2.1 Add `mirrorCrossTenantViolation(offendingUserId, expectedUserId, tableName, err, ctx)` to `apps/web-platform/server/observability.ts` (sibling to `mirrorWithDebounce` — does NOT widen existing signature per C3)
- 2.2 Hash both userIds via SHA-256 + `SOLEUR_SENTRY_PII_SALT` env before logging to Sentry payload
- 2.3 Sentry routing: `level: 'fatal'`, `tags: { sec: true, dsar: true, cross_tenant: true }`
- 2.4 Skeleton of `apps/web-platform/server/dsar-export.ts` with `assertReadScope(rows, expectedUserId, tableName)` + `CrossTenantViolation` error type
- 2.5 Unit test in `apps/web-platform/test/dsar-export.test.ts` covering `assertReadScope` raises on empty-when-RLS-denied AND on cross-tenant rows

## Phase 3 — Reauth helpers

- 3.1 Write `apps/web-platform/server/dsar-reauth.ts`: `issueReauthEvent`, `consumeReauthEvent` (validates `auth_time` claim ≤300s for OAuth per AC27), `requireFreshReauth(req)`
- 3.2 Extend `apps/web-platform/test/auth-gate.test.ts` to enumerate `requireFreshReauth(req)` per AC21
- 3.3 Write `apps/web-platform/test/dsar-reauth.test.ts` (or fold into `dsar-export.test.ts` if small enough — keep file count tight per C2)

## Phase 4 — Email

- 4.1 Extend `apps/web-platform/server/notifications.ts` with `sendDsarExportReadyEmail(userId, jobId, expiresAt)` and `sendDsarExportFailedEmail(userId, jobId, reason)` per C2 fold
- 4.2 Subject + preview-text PII-free per TR6 (e.g., "Your Soleur data export is ready" + "Your data export is ready to download. The link expires in 7 days.")
- 4.3 Plain `<a>` link, not auto-tracked; no Resend `tags` for individual link tracking

## Phase 5 — Orchestrator + worker (worker logic in single module per C2)

- 5.1 Complete `apps/web-platform/server/dsar-export.ts`:
  - `enqueueExport(userId, reauthEventId, sessionId, ip, ua)` — INSERT row, return 202 payload
  - `runExport(jobId)` — service-role + per-row WHERE per C1
  - `startDsarExportReaper()` — `setInterval` poller mirroring `agent-runner.ts:698-714`
  - On-startup orphan-reset per S3: `UPDATE dsar_export_jobs SET status='pending', started_at=NULL WHERE status='running'` runs ONCE before first tick
  - Per-job hard timeout 30 min via manual `AbortController + setTimeout(controller.abort, ms)` per `cq-abort-signal-timeout-vs-fake-timers`
  - Allowlist enumerator (`information_schema.columns` + table allowlist + article-tag map)
  - Archiver pipe per spike outcome (in-memory or disk-then-upload)
  - Manifest writer with serialization conventions per AC23: ISO 8601 + UTC offset, base64 for `bytea`, JSON `null` for SQL NULL, sorted keys, `schema_version: "1.0.0"`, `excluded_files[]`
  - Per-file SHA-256 in single fd-pass per AC18
  - `O_NOFOLLOW` + `fstat` ino verify on workspace reads per AC17
  - Per-file error policy per AC26: skip-with-manifest-entry for symlink/ino-mismatch; fail-job-loud for path-traversal
  - Every Supabase call destructures `{ error }` per AC20
  - Defense-relaxation comment at URL-issuance call site per AC19
- 5.2 Write `apps/web-platform/test/dsar-export.test.ts` — happy path + silent-RLS detection (per C2 fold) + `assertReadScope` raises + per-file error policy + serialization-conventions golden fixture
- 5.3 Write `apps/web-platform/test/dsar-allowlist-completeness.test.ts` per AC28 + S6 (discover all `auth.users`-FK tables; assert each is in allowlist or documented exclusions)
- 5.4 Write `apps/web-platform/test/dsar-worker-per-row-where.test.ts` per AC30 + C1 (file-parse lint over `dsar-export.ts` asserting every `service.from('<allowlisted-table>').select(...)` has `.eq('owner_id', expectedUserId)`)

## Phase 6 — API routes

- 6.1 Write `apps/web-platform/app/api/account/export/route.ts` (POST: validateOrigin + rejectCsrf + auth + abuse rate-limit + consume reauth event + insert job + 202)
- 6.2 Write `apps/web-platform/app/api/account/export/[jobId]/route.ts` (GET: status RLS-scoped; POST: reissue per S9 inline)
- 6.3 Write `apps/web-platform/app/api/account/export/[jobId]/download/route.ts` (stream Storage with session+IP-bind; nosniff + RFC 6266 + sanitised filename per AC16; on completion hard-delete + UPDATE; on `expired`/unknown returns 410 per AC24)
- 6.4 Write `apps/web-platform/test/dsar-export-route.test.ts` — CSRF + auth + abuse rate-limit + reauth-event consumption + idempotency + IP-bind + 410 expired (AC24) + concurrent-click (AC31)

## Phase 7 — Reauth route

- 7.1 Write `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/reauth/route.ts` (password re-entry; OAuth → `signInWithOAuth({prompt:'login', max_age:'300'})`)

## Phase 8 — UI

- 8.1 Write `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/page.tsx`
- 8.2 Write `apps/web-platform/components/settings/dsar-export-dialog.tsx` — single dialog with `<details>` "What's included" disclosure per S9 collapse; "Continue" → reauth redirect → "we'll email you" confirmation
- 8.3 Write `apps/web-platform/components/settings/dsar-export-job-list.tsx` — RLS-scoped list; renders `expired` rows with re-request CTA per AC24; disables "Download my data" button when active job exists per AC31
- 8.4 Edit `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` and `apps/web-platform/components/settings/settings-content.tsx` to surface the new privacy sub-route
- 8.5 Run Playwright MCP E2E: discover → confirm → reauth (password) → POST → "we'll email you" → in-app status updates → email link click → download → status `delivered`. Test failure modes: wrong password, OAuth canceled, reauth event expired between confirm and POST, IdP ignores `prompt=login` (per RK4 + AC27), concurrent-click (AC31).

## Phase 9 — account-delete cascade extension

- 9.1 Edit `apps/web-platform/server/account-delete.ts`:
  - Insert step at top of cascade: `UPDATE public.dsar_export_jobs SET status='failed', failure_reason='account_deleted_during_export' WHERE status IN ('pending','running') AND user_id=$1` (per AC25)
  - Insert step before `auth.admin.deleteUser()`: call `anonymise_dsar_export_audit_pii(p_user_id)` RPC
  - Extend storage-purge to include `dsar-exports/<userId>/`
  - **Update the existing `:115-117` invariant comment** in the same edit to reflect new ordering and recoverability of the failure-mode (anonymise idempotent → re-runs safe)
- 9.2 Extend `apps/web-platform/test/account-delete.test.ts` cascade-order test to assert new order: `["abort-dsar-jobs", "abort", "workspace", "storage-purge", "anonymise-dsar-audit", "auth"]`
- 9.3 Add test: "anonymise succeeds, auth-delete fails" recovery (job tombstone reversible)

## Phase 10 — Cross-tenant integration test

- 10.1 Write `apps/web-platform/test/dsar-export-cross-tenant.integration.test.ts` (gated by `SUPABASE_DEV_INTEGRATION=1`):
  - Two synthesised users (A, B) per `cq-test-fixtures-synthesized-only`
  - Seed overlapping content via service-role (overlapping conversation titles, attachments, KB workspace files)
  - Export as A
  - Assert via **service-role re-check** (NEVER HTTP status, per `2026-05-06-rls-zero-policies-anon-delete-204-semantic.md`) that zero rows / bytes / path-prefixes attributable to B appear in A's bundle
  - Add content-level scan: extract A's exported markdown files; assert no string fragment matching B's distinguishing content

## Phase 11 — Legal docs

- 11.1 Edit `docs/legal/privacy-policy.md` §4.7 — add 5 missing categories (`message_attachments`, KB workspace files, `team_names`, `audit_byok_use`, Stripe customer/subscription IDs)
- 11.2 Edit `docs/legal/privacy-policy.md` §8.1 — add self-serve endpoint reference; retain `legal@jikigai.com` (Q8)
- 11.3 Edit `docs/legal/gdpr-policy.md` §6.1.b + §5.3
- 11.4 Edit `docs/legal/data-protection-disclosure.md` §2.3 (new processing activity), §5.3 (add Art. 20), §10 (termination clause update per SpecFlow ripple)
- 11.5 Edit `knowledge-base/legal/compliance-posture.md` Active Items
- 11.6 Create `.github/workflows/legal-doc-cross-document-gate.yml` per C8: fails PR if `apps/web-platform/server/dsar-export.ts` (or other declared regulated-data surface) is modified AND any of the 4 legal docs is unmodified
- 11.7 Invoke `legal-compliance-auditor` agent as a phase per `2026-03-18-legal-cross-document-audit-review-cycle.md`; resolve any ripple contradictions in §4 sub-processors / §10 termination

## Phase 12 — Operator runbooks

- 12.1 Write `knowledge-base/engineering/ops/runbooks/dsar-export-oversize.md`
- 12.2 Write `knowledge-base/engineering/ops/runbooks/dsar-export-failed-job.md`
- 12.3 Write `apps/web-platform/scripts/dsar-export-oversize.sh`

## Phase 13 — Pre-merge verification

- 13.1 Run `bun test` (or per `package.json` scripts.test) — all passing
- 13.2 Run preflight Check 6 (User-Brand Impact present + threshold valid)
- 13.3 Confirm migrations applied to **dev** first per `wg-when-a-pr-includes-database-migrations`
- 13.4 Verify `select * from cron.job where jobname like 'dsar-export-%';` returns 2 rows in dev
- 13.5 Verify Storage bucket `dsar-exports` exists in dev, listed `private`, RLS verified
- 13.6 Coordinate with #3603 PR-C ship-time per RK3 (compliance-cohort interplay)
- 13.7 `gh pr ready 3634`
- 13.8 `gh pr merge 3634 --squash --auto`

## Post-merge (operator)

- PM.1 Apply migrations 041 + 042 to prd Supabase project
- PM.2 Verify pg_cron schedules in prd
- PM.3 Verify Storage bucket exists in prd
- PM.4 Run end-to-end exercise as internal synthesised account (on synthetic-allowlist per `cq-destructive-prod-tests-allowlist`); confirm POST/poll/email/download/delete cycle
- PM.5 `gh issue close 3637`
- PM.6 7-day post-deploy monitoring of `mirrorCrossTenantViolation` + `mirrorWithDebounce(*, "dsar-export-failed")` Sentry alerts; on either P0, flip `DSAR_EXPORT_ENABLED=false`
- PM.7 Open v1.1 follow-up issue: read-only MCP tool `mcp__soleur_platform__dsar_export_status` (deferred per D1)
- PM.8 Open v1.1 follow-up issue: synchronous fast-path for accounts <10 MB (deferred per D2; gate on production median-export-size telemetry)

## Definition of Done

- All ACs in plan rev-2 satisfied (AC1-8 compliance + AC12-31 substance; AC9/10/11 demoted/deferred per S7+D1)
- All Test Scenarios TS1-TS16 covered by tests
- 5-agent panel sign-off captured (this plan revision IS the rev-2 sign-off)
- PR #3634 merged
- Issue #3637 closed
- v1.1 follow-up issues filed for D1 + D2 deferrals
