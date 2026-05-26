# Feature: GDPR Art. 15 + Art. 20 DSAR Self-Serve Export Endpoint

**Parent finding:** D-DSAR-art15 (plan rev-3 of #3603 transcript-hardening, line 200, surfaced 2026-05-12)
**Brand-survival threshold:** single-user incident (Art. 33/34 notifiable)
**GDPR-gate required:** yes (sub-gates: Art-15, Art-20, Art-5-1-c, Art-5-2, Art-6, Art-12-3, Art-32, Art-33-34)
**Brainstorm:** `knowledge-base/project/brainstorms/2026-05-12-dsar-art15-export-endpoint-brainstorm.md`
**Draft PR:** #3634
**Branch:** `feat-dsar-art15-export-endpoint`

## Problem Statement

Privacy Policy §8.1, GDPR Policy §6.1.b, and DPD §5.3 promise users a right of access (Art. 15) and right of data portability (Art. 20). PR-A1 of #3603's Phase 0 verification on 2026-05-12 grep'd `apps/web-platform/server/` for `art 15 | dsar | data-export | export.*personal | portability | gdpr` and confirmed **no code path exists**. The promise is currently fulfilled by manual operator action (DB dump via support ticket to `legal@jikigai.com`), an unverifiable-at-scale fallback for an Art. 12(3) one-month SLA. The Art. 17 sibling endpoint (`apps/web-platform/server/account-delete.ts`) is wired and works; only the export side is missing.

A bad implementation is asymmetrically worse than no implementation: a botched endpoint that returns user A's ZIP to user B is an Art. 33 (CNIL, 72h) + Art. 34 (data-subject, undue delay) notifiable breach in the very surface designed to fulfill a data-subject right — irrecoverable brand damage for a privacy-positioned product.

## Goals

- **G1.** User self-serve export of all personal-data categories enumerated in Privacy Policy §4.7 + §4.8 + §4.9, retrievable via a `/settings/privacy` UI button without operator involvement.
- **G2.** Cross-tenant isolation guaranteed *by construction* (RLS-via-user-JWT for queries + path-prefix isolation for Storage + per-row `user_id` assertion in serializer) rather than by audit.
- **G3.** Article 15 *and* Article 20 satisfied in one bundle via per-file `{article: "15"|"15+20"}` manifest tags (per EDPB WP242).
- **G4.** Column-introspection-driven enumeration (`information_schema.columns` + `SELECT *`) so that PR-A2's `messages.usage` flip and any future column addition auto-appears in subsequent exports without code change.
- **G5.** Audit log that is itself privacy-protective: separate schema, append-only WORM trigger, owner-SELECT denied, service-role-RPC writes only, 24-month retention with scheduled hard-delete.
- **G6.** Same-PR amendment of Privacy Policy §4.7+§8.1, GDPR Policy §6.1.b, DPD §2.3, and `knowledge-base/legal/compliance-posture.md` (cross-document consistency gate).
- **G7.** Step-up reauthentication within last 5 minutes before export job enqueue, binding job to reauth'd session_id, so stolen-session attackers are blocked.
- **G8.** Signed-URL delivery model that is non-bearer: session+IP-bound, single-use, hard-delete on first download, 7d TTL.

## Non-Goals

- **NG1.** Programmatic API for repeated/scheduled exports (Art. 15 is point-in-time, not subscription).
- **NG2.** Incremental "since date X" exports.
- **NG3.** Redaction tooling for third-party-mentioned content (do not mutilate the record per EDPB Guidelines 01/2022 §6).
- **NG4.** Agent-native MCP tool for **initiating** an export. The read-only `dsar_export_status` MCP tool *is* in scope (status/poll/list).
- **NG5.** In-browser preview of export contents.
- **NG6.** Supabase Edge Functions as runtime (house-rejected per `2026-04-02-feat-phase2-security-gdpr-onboarding-beta-gate-plan.md:489`).
- **NG7.** Replacing the existing `legal@jikigai.com` manual fallback — retain as documented fallback in §8.1 update for locked-out / disabled-account users.
- **NG8.** Exporting plaintext BYOK API keys (Art. 5(1)(f) excluded; export fingerprints + scope only, document exclusion in manifest).
- **NG9.** Retrofitting `account-delete.test.ts` (file decision for plan — separate work to land alongside via cross-tenant test family if cheap; otherwise file as follow-up).

## Functional Requirements

### FR1: Settings UI surface

`/settings/privacy` page gains a **"Download my data"** button alongside the existing "Delete my account" CTA. Two-stage flow:
- Click → modal showing **"What's included"** preview card listing categories the export will contain, counts, and approximate size. Includes confirmation copy and "Continue" button.
- Confirm → redirect to `/settings/privacy/reauth` (step-up flow).
- After successful reauth → `POST /api/account/export` issued from server; user sees "We'll email you when your export is ready, usually within 48h" + in-app job-tracker entry.

### FR2: Step-up reauthentication gate

`/settings/privacy/reauth` requires:
- Password accounts: re-entry of primary password.
- OAuth accounts: re-authentication via provider with `prompt=login` and `max_age=300`.
- MFA: fresh challenge if user has MFA enrolled (forward-compatible — MFA not in v1 product surface but the code must not need rework when MFA ships).

Reauth issues a server-tracked `reauth_event_id` valid for 5 minutes, single-use against the export-creation endpoint. The export job binds to the **session_id** that performed reauth; subsequent session revocation invalidates the export's signed URL.

### FR3: `POST /api/account/export`

- Auth: `supabase.auth.getUser()` + `validateOrigin` + `rejectCsrf` (mirror `app/api/account/delete/route.ts`).
- Body: `{ reauth_event_id }`.
- Validates reauth_event_id is fresh (≤5min), unconsumed, belongs to the same user.
- Idempotency: partial unique index on `dsar_export_jobs(user_id) WHERE status IN ('pending','running','completed') AND requested_at > now() - interval '24 hours'`. Second POST within 24h returns existing `job_id` (200), not 429.
- Inserts `dsar_export_jobs` row: `user_id`, `requested_at`, `acknowledged_at`, `status='pending'`, `owner_session_id`, `requester_ip` (in sibling `dsar_export_audit_pii`), `requester_user_agent` (in sibling table).
- Response: `202 Accepted` with `{ job_id, acknowledged_at, estimated_completion_p95: '48h' }`.

### FR4: Async export worker

Substrate TBD at plan time among three candidates (no recommendation locked at brainstorm — see brainstorm Open Q1):
- (a) `pg_cron` + `pg_net` posting to an internal claim endpoint.
- (b) In-process `setInterval` reaper in Next.js server (matches `agent-runner.ts:522`).
- (c) Bolt-on Vercel cron.

Worker per job:
1. Mark row `status='running'`, `started_at=now()`.
2. Construct Supabase client with the requester's stored JWT (NOT service-role) — RLS-enforced queries from this point.
3. For each table that cascade-FKs from `auth.users`: enumerate columns via `information_schema.columns`, `SELECT *`, serialize to JSON file with article tag (Art. 15 vs 15+20 per CLO assessment table).
4. For Storage: list `chat-attachments/<userId>/...` via service-role + path-prefix guard (`startsWith(\`${user.id}/\`) && !.includes('..')` per IDOR learning). Stream each binary into ZIP archive.
5. For KB workspace: read the per-user workspace filesystem (path from `users.workspace_path`), bundle as `workspace/` subdirectory in ZIP.
6. Stream ZIP via `archiver` → Supabase Storage **resumable upload** (`tus-js-client` or native multipart) to `dsar-exports/<userId>/<jobId>.zip`.
7. Generate `manifest.json` last, including SHA-256 of each file; ZIP-final.
8. Mark row `status='completed'`, `completed_at=now()`, `storage_path`, `signed_url_issued_at`, `signed_url_expires_at=now()+7d`.
9. Send Resend email with `/api/account/export/:id/download` link.

### FR5: `GET /api/account/export/:id/download`

- Auth: `supabase.auth.getUser()`.
- Lookup `dsar_export_jobs` row by `:id`, RLS-scoped (`user_id = auth.uid()`).
- Reject if:
  - `status != 'completed'`
  - `downloaded_at IS NOT NULL` (single-use)
  - `session_id != owner_session_id` (session-bound)
  - `request_ip /24 != owner_ip /24` (IP-bound; for IPv6, /48 subnet) — on mismatch, return guidance to re-request a fresh URL from `/settings/privacy`
  - `signed_url_expires_at < now()` (TTL)
- On success: stream Storage object to client; on stream completion, `UPDATE … SET downloaded_at = now(), status='delivered'` AND issue Storage object DELETE in the same transaction-equivalent (Storage delete is best-effort + retry; row state is the source of truth).

### FR6: Job-tracker UI at `/settings/privacy`

Lists user's `dsar_export_jobs` (RLS-scoped, no PII columns from sibling table):
- columns: requested_at, status (pending/running/completed/delivered/expired/failed), completed_at, signed_url_expires_at
- "Re-issue URL" button (only if status=completed AND signed_url not yet consumed): re-binds to current session+IP and resets TTL to now+remaining-window-up-to-7d-from-completed_at. Does NOT re-run worker. Logged in audit log as `reissue` event.

### FR7: Audit-log schema (`dsar_export_audit` + `dsar_export_audit_pii`)

Two tables. **`dsar_export_jobs`** (user-visible via RLS):
- `id uuid pk`, `user_id uuid fk auth.users ON DELETE CASCADE`, `requested_at`, `acknowledged_at`, `started_at`, `completed_at`, `delivered_at`, `status` (check enum), `storage_path text`, `signed_url_issued_at`, `signed_url_expires_at`, `downloaded_at`, `object_deleted_at`, `failure_reason text`.

**`dsar_export_audit_pii`** (admin-only — separate schema `dsar_audit` if Postgres permits; minimum: RLS-deny-all to app role + service-role-only access via RPC):
- `id`, `job_id fk dsar_export_jobs`, `requester_ip inet`, `requester_user_agent text`, `owner_session_id text`, `bundle_sha256 text`, `bundle_size_bytes bigint`, `created_at`.
- WORM enforced via trigger (mirror `audit_byok_use_no_mutate` from migration 037).
- `SECURITY DEFINER` RPC writes only (`write_dsar_export_audit_pii`), `search_path = public, pg_temp`.
- Retention 24 months via `pg_cron` sweep.

### FR8: Cross-document legal-artifact amendments (same PR)

- `docs/legal/privacy-policy.md` §4.7: add `message_attachments` and KB workspace files as enumerated categories; §8.1: add reference to `/settings/privacy` self-serve endpoint, retain `legal@jikigai.com` fallback.
- `docs/legal/gdpr-policy.md` §6.1.b: same-PR pointer to in-product endpoint + format declaration.
- `docs/legal/data-protection-disclosure.md` §2.3: new processing activity "Data Subject Access Request fulfilment" with legal basis 6(1)(b)+6(1)(c) and retention (audit 24mo, bundle 7d).
- `knowledge-base/legal/compliance-posture.md` Active Items: row "DSAR Art. 15/20 self-serve endpoint" referencing this issue.

CI gate: PR cannot merge if all four files are not modified.

### FR9: Cross-tenant safety primitives

- `assertReadScope(rows, expectedUserId)` helper (lift from `cc-dispatcher.ts:43` `assertWriteScope`); rows whose `user_id`/derived owner ≠ expected raise; P0 Sentry mirror dedup keyed `(offendingUserId, expectedUserId, table_name)`.
- Two-user-two-conversation synthesized golden fixture in CI: create users A+B with overlapping content, run export as A, assert zero bytes/rows/path-prefixes attributable to B appear in bundle.
- Unit test: silent-RLS-failure detection — assert that a query returning 0 rows when 0-policies-and-anon raises rather than serializing empty.

### FR10: Read-only MCP surface

`mcp_dsar_export_status` tool (read-only): list user's export jobs, get job status by id. NOT `mcp_dsar_export_create` — explicit human-confirmation gating per DEC13.

## Technical Requirements

### TR1: New migration adds `dsar_export_jobs` + `dsar_export_audit_pii`

Mirrors `037_audit_byok_use.sql` patterns. Includes RLS policies, indexes (`(user_id, requested_at DESC)`, partial unique on idempotency window), WORM trigger on `dsar_export_audit_pii`, `SECURITY DEFINER` RPC.

### TR2: New Supabase Storage bucket `dsar-exports`

Private bucket. RLS: `auth.uid()::text = (storage.foldername(name))[1]`. Path: `dsar-exports/<userId>/<jobId>.zip`.

### TR3: Streaming ZIP via `archiver` to resumable upload

`archiver` (npm) for ZIP construction. `tus-js-client` or Supabase native resumable for the upload primitive. **Spike required before plan-time encodes size cap.** If streaming fails, v1 caps total bundle at ~500MB with operator-fallback for larger accounts.

### TR4: v1 size cap

1GB default; on exceed, mark job `failed` with `failure_reason='exceeds_v1_size_cap'`; email user with operator-fallback instructions; audit row captures cap-hit for visibility.

### TR5: Worker function timeout

`maxDuration: 300` in route config (Vercel Pro plan ceiling). Default 10s on Hobby = unworkable.

### TR6: Email template via Resend

Template name `dsar-export-ready`. Variables: user display name, download URL, expiry timestamp. No PII in subject/preview text. Plain `<a>` link, not auto-tracked.

### TR7: Rate-limit substrate

DB-resident: the partial unique index on `dsar_export_jobs` IS the rate-limit (1/24h). Do not bolt on `SlidingWindowCounter` for this — single source of truth.

### TR8: Step-up reauth route

`/settings/privacy/reauth/route.ts` handles password reentry; OAuth re-prompt is handled by Supabase auth API (`signInWithOAuth({ provider, options: { queryParams: { prompt: 'login', max_age: '300' } } })`).

## Acceptance Criteria

- **AC1 (CLO AC-1):** Export bundle reconciles 1:1 with Privacy Policy §4.7 + §4.8 + §4.9 enumerated categories. CI test asserts every category present or explicitly marked N/A with reason in manifest.
- **AC2 (CLO AC-2):** Bundle = ZIP containing `manifest.json` + JSON-per-table + markdown originals (user-authored) + binaries in original mime. Each file tagged `{article: "15"|"15+20"}` with SHA-256, source table, row count.
- **AC3 (CLO AC-3):** Step-up reauth within 5min required before enqueue. OAuth uses `max_age=300`. Job bound to reauth'd `session_id`; session revocation invalidates URL.
- **AC4 (CLO AC-4):** `acknowledged_at` returned synchronously (≤500ms response). Async job p95 ≤48h, hard ceiling ≤7d. Art. 12(3) extension flow exists with email notification within 30d window.
- **AC5 (CLO AC-5):** Signed URL TTL = 7d; bound to authenticated session + source IP /24 (IPv6 /48); single-use; storage object hard-deleted on first download or at TTL (whichever first).
- **AC6 (CLO AC-6):** `assertReadScope` invocation on every result set + RLS on every query in export pipeline + cross-tenant golden-fixture CI test (two synthesized users, zero cross-bytes).
- **AC7 (CLO AC-7):** Audit log: separate schema, RLS-denied to app role, append-only via trigger, PII-minimal payload, 24-month hard-delete schedule; user's own prior audit rows included in subsequent exports.
- **AC8 (CLO AC-8):** Privacy Policy §4.7/§8.1, GDPR Policy §6.1.b, DPD §2.3, and `compliance-posture.md` updated in the same PR. CI gate: no merge if any of the four files is unmodified.
- **AC9 (own):** Streaming-upload spike (TR3) lands BEFORE spec-encoded size cap is finalized. Spike result either confirms streaming or moves v1 to in-memory-with-cap fallback.
- **AC10 (own):** Read-only `mcp_dsar_export_status` tool present; `mcp_dsar_export_create` is NOT present (DEC13).
- **AC11 (own):** 5-agent plan-review panel (DHH + Kieran + Code-Simplicity + Architecture-Strategist + SpecFlow re-validation) sign-off captured in plan rev-2 before implementation.

## Out of Scope (defer to v2 / follow-ups)

- Programmatic API; incremental since-date; redaction tooling; agent-native MCP for initiation; in-browser preview; Sentry/Cloudflare-processor logs as exportable content.
- Account-delete test retrofit (NG9) — file as follow-up if not bundled.

## Brand-Survival Threshold

**single-user incident** — a single instance of user A's data appearing in user B's bundle is Art. 33 (CNIL, 72h) + Art. 34 notifiable. The 5-agent plan-review panel + `assertReadScope` + two-user cross-tenant golden-fixture CI test together form the load-bearing defense.

## Domain Review (carry-forward)

- **CPO (sign-off pending plan):** ship per DEC1–DEC15; biggest risk is cross-tenant signed-URL keying — must reuse two-user invariant pattern from PR-A1 #3286.
- **CLO (sign-off pending plan):** GDPR-gate triple-invocation declared (Art-15, 20, 5-1-c, 5-2, 6, 12-3, 32, 33-34); 8-item acceptance criteria carried forward as AC1–AC8.
- **CTO (sign-off pending plan):** column-introspection dissolves PR-A2 dependency; streaming-upload spike required (TR3 + AC9); reject Edge Functions (NG6); recommend `pg_cron + pg_net` substrate but defer final choice to plan Open Q1.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-dsar-art15-export-endpoint-brainstorm.md`
- Parent finding: `knowledge-base/project/plans/2026-05-11-feat-cc-soleur-go-transcript-hardening-pra-plan.md:200`
- Adjacent Art. 17 code: `apps/web-platform/server/account-delete.ts`
- WORM-audit reference: `apps/web-platform/supabase/migrations/037_audit_byok_use.sql`
- Existing signed-URL pattern: `apps/web-platform/app/api/attachments/url/route.ts:31`
- DPD-rights plan precedent: `knowledge-base/project/plans/2026-03-20-legal-dpd-web-platform-data-subject-rights-plan.md`
