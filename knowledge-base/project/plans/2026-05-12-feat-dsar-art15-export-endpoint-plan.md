---
title: "feat: GDPR Art. 15 + Art. 20 DSAR self-serve export endpoint (D-DSAR-art15)"
type: feat
date: 2026-05-12
revision: 2
issue: 3637
draft_pr: 3634
branch: feat-dsar-art15-export-endpoint
worktree: .worktrees/feat-dsar-art15-export-endpoint/
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
gdpr_gate_required: true
sub_gates_fired: [Art-15, Art-20, Art-5-1-c, Art-5-2, Art-6, Art-12-3, Art-32, Art-33-34]
semver_label: semver:minor
brainstorm: knowledge-base/project/brainstorms/2026-05-12-dsar-art15-export-endpoint-brainstorm.md
spec: knowledge-base/project/specs/feat-dsar-art15-export-endpoint/spec.md
plan_review_panel:
  - dhh-rails-reviewer
  - kieran-rails-reviewer
  - code-simplicity-reviewer
  - architecture-strategist
  - spec-flow-analyzer
plan_review_findings_applied:
  must_fix: [C1, C2, C3, C4, C5, C6, C7, C8]
  high_value_p1: [S1, S2, S3, S4, S5, S6, S7, S8, S9]
v1_1_deferrals:
  - "FR10/AC10 — read-only MCP tool `mcp__soleur_platform__dsar_export_status` (defer until a named agent workflow asks for it)"
  - "Synchronous fast-path for accounts < 10 MB (DHH suggestion; defer until production telemetry shows median user is bothered)"
---

# GDPR Art. 15 + Art. 20 DSAR Self-Serve Export Endpoint — Implementation Plan (rev-2)

Implements the Privacy Policy §8.1 / GDPR Policy §6.1.b promise of a self-serve right of access (Art. 15) + portability (Art. 20). Today the promise is fulfilled by manual operator action (`legal@jikigai.com` ticket → DB dump). PR-A1 of #3603 Phase 0 grep'd `apps/web-platform/server/` on 2026-05-12 and confirmed no code path exists. This plan replaces the manual flow.

**Rev-2 changes vs rev-1** (per AC11 5-agent panel):
- **C1**: dropped `owner_jwt_encrypted bytea` column. Worker uses `service_role` + mandatory per-row `WHERE owner_id = $1` + `assertReadScope` on every row, enforced by file-parse lint.
- **C2**: collapsed 7 server modules → **2** (`dsar-export.ts`, `dsar-reauth.ts`); folded `dsar-email.ts` into existing `notifications.ts`. Tests: 5 → 3.
- **C3**: unfolded #3638. New sibling `mirrorCrossTenantViolation` in `observability.ts` instead of widening `mirrorWithDebounce`'s 2-tuple key. #3638 lands separately.
- **C4**: dropped `Art17ErasureHook` registry — premature pluggability for 1 producer + 1 consumer.
- **C5**: phase ordering fixed; reauth helpers ship before consuming routes; tests land WITH the module they cover, not at the end.
- **C6**: `account-delete.ts` cascade: abort in-flight DSAR jobs FIRST, then anonymise, then auth-delete; existing `:115-117` invariant comment updated in same edit; AC25 covers the failure-mode handling.
- **C7**: state-machine completeness — `expired` status added, TTL sweep cron added, 410-Gone response on expired downloads (AC24).
- **C8**: `legal-doc-cross-document-gate.yml` added to Files-to-Create.
- **S1**: WORM-bypass GUC hardened (function-OID allowlist + single-call-site lint).
- **S2**: OAuth `auth_time` claim validation added (AC27).
- **S3**: TR12 stuck-job pg_cron sweep replaced with on-startup `UPDATE … SET status='pending' WHERE status='running'` in poller init.
- **S4**: manifest serialization conventions codified (AC23).
- **S5**: per-file error policy codified (AC26).
- **S6**: allowlist-completeness CI gate added (AC28).
- **S7**: AC9 + AC11 demoted from pre-merge ACs to phase-exit gates.
- **S8**: Bun runtime invariant captured in spike report + ADR.
- **S9**: reissue inlined into `[jobId]/route.ts` (saves a route file); two-stage UI collapsed to a single confirmation dialog with `<details>` disclosure (saves a state).
- **D1 (panel divergent)**: MCP tool `mcp__soleur_platform__dsar_export_status` deferred to v1.1.
- **D2 (panel divergent)**: synchronous fast-path for small accounts deferred to v1.1.

## Overview

A botched implementation is asymmetrically worse than no implementation: a single instance of user A's bundle returned to user B is Art. 33 (CNIL, 72h) + Art. 34 (data subject) notifiable in the very surface designed to fulfil a data-subject right. Brand-survival threshold is `single-user incident`. Failure-mode artifact: `dsar-exports/<userId>/<jobId>.zip` — a single file containing the entirety of one user's personal data.

The shape:

```
/settings/privacy → [Download my data] → confirmation dialog (with <details> "What's included")
   ↓ Continue
/settings/privacy/reauth (password re-entry OR OAuth signInWithOAuth({prompt:'login', max_age:'300'}))
   ↓ ok within 5 min + auth_time claim ≤ 300s old (per AC27)
POST /api/account/export
   • supabase.auth.getUser() + reauth_event_id consumption (single-use, ≤5min)
   • partial unique index on (user_id) WHERE status IN ('pending','running','completed')
     AND requested_at > now() - 24h gives 1/24h compliance idempotency
   • SlidingWindowCounter abuse rate-limit (1 req / 60s)
   • INSERT dsar_export_jobs row, bind owner_session_id; record requester_ip + ua in
     dsar_export_audit_pii via SECURITY DEFINER RPC
   • return 202 + job_id + acknowledged_at
   ↓
In-process setInterval poller in dsar-export.ts (mirror agent-runner.ts:698-714)
   • on Node startup: UPDATE dsar_export_jobs SET status='pending' WHERE status='running'
     (per S3 — orphaned-on-restart recovery)
   • atomic claim: UPDATE … SET status='running', started_at=now()
     WHERE id = (SELECT id FROM dsar_export_jobs WHERE status='pending'
                  ORDER BY requested_at LIMIT 1 FOR UPDATE SKIP LOCKED)
     RETURNING *
   • construct service-role Supabase client; for each table in allowlist:
       SELECT * FROM <table> WHERE owner_id = $jobs.user_id   (per-row WHERE
         enforced by file-parse lint per AC30; service-role required because
         worker is not authenticated as the user — per C1 redesign)
       assertReadScope(rows, jobs.user_id, table_name)         (defense-in-depth
         against any drift in the per-row WHERE; raises CrossTenantViolation
         + mirrorCrossTenantViolation Sentry P0 with hashed userId)
       serialize → JSON file with article tag per FR4 step 5
   • Storage: list chat-attachments/<userId>/... via service-role + path-prefix
     guard (per 2026-04-11 IDOR learning); stream binaries
   • workspace: read /workspaces/<userId>/* via O_NOFOLLOW + fstat ino verify
     (per 2026-04-15 + 2026-04-17 learnings); SHA-256 in same fd-pass (no re-open)
   • stream archiver → Supabase Storage upload to dsar-exports/<userId>/<jobId>.zip
   • write manifest.json LAST: schema_version + per-file {article, sha256, source_table,
     row_count} + excluded_files[] (per AC26 per-file error policy)
   • mark row status='completed', signed_url_expires_at=now()+7d
   • notifications.ts:sendExportReadyEmail (per C2 — folded into existing module)
   ↓
GET /api/account/export/<jobId>?download=1
   • session_id matches owner_session_id; source IP /24 (IPv6 /48) matches issuance
   • single-use atomic UPDATE; on success: stream Storage object, hard-delete
   • response: Content-Type: application/zip + X-Content-Type-Options: nosniff
     + RFC 6266 Content-Disposition + sanitized fixed filename (per AC16)
   • on TTL expiry without download: pg_cron dsar-export-bundle-ttl-sweep flips
     status='expired' + deletes Storage object (per AC24)
   • GET on expired/unknown jobId returns 410 Gone with re-request copy
```

## Research Reconciliation — Spec vs. Codebase

The brainstorm + spec contained several claims that did not survive verification against the worktree. Each is reconciled here so phase estimates and FR/AC numbering align with reality. Rev-2: R-extra1 documents the C1 substitution.

| # | Spec / brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|---|
| R1 | `assertWriteScope` exists at `apps/web-platform/server/cc-dispatcher.ts:43`, lift as `assertReadScope` (FR9) | **Does not exist anywhere in repo.** Line 43 of `cc-dispatcher.ts` is `} from "./soleur-go-runner";` (an unrelated import). | Build `assertReadScope` greenfield in `apps/web-platform/server/dsar-export.ts`. Use a new sibling `mirrorCrossTenantViolation(offendingUserId, expectedUserId, table)` in `apps/web-platform/server/observability.ts` (added without widening the existing `mirrorWithDebounce` signature — per C3). |
| R2 | `apps/web-platform/test/account-delete.test.ts` does NOT exist (Brainstorm Open Q6) | **Exists** (371 lines, vitest mocks). | Brainstorm Open Q6 is moot. The mock test pattern is reused; spec NG9 removed. |
| R3 | Brainstorm cites `agent-runner.ts:522` (stuck-conversation sweep) | Actual `startStuckActiveReaper` is at `apps/web-platform/server/agent-runner.ts:698-714`. | All references use `:698`. |
| R4 | Brainstorm cites `rate-limiter.ts:44` for the single-instance caveat | `SlidingWindowCounter` declaration is `:44`; the single-instance caveat docblock is `:255-262`. | Use `:255-262` for the caveat citation. |
| R5 | Substrate (a) `pg_cron` + `pg_net` is a candidate (Open Q1) | `pg_cron` installed (`migrations/029_plan_tier_and_concurrency_slots.sql:23`). **`pg_net` is NOT installed.** | Substrate (b) chosen — see Q1 resolved. |
| R6 | Substrate (c) Vercel cron is a candidate (Open Q1) | **No `vercel.json`.** Production deployment is **Hetzner** (`rate-limiter.ts:259-261`). | Substrate (c) moot; spec TR5's `maxDuration: 300` is moot — replaced by AbortController hard timeout. |
| R7 | Streaming-archive primitive available in repo | **Greenfield** — zero matches for `archiver`, `tus-js-client`, `tus`, `uploadResumable`. | Phase 0 spike gates downstream work. v1 size cap parameterised by spike outcome. |
| R8 | `/settings/privacy` route exists | **Does not exist.** Settings sub-routes: `services/`, `billing/`, `team/`. | Greenfield route at `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/page.tsx`. |
| R9 | Step-up reauth helper exists | **Greenfield.** | Greenfield in `apps/web-platform/server/dsar-reauth.ts`. Auth-gate smoke test extended (AC21). |
| R10 | Privacy Policy §4.7 enumerates all DSAR-relevant tables | **Five enumeration gaps confirmed**: missing `message_attachments`, KB workspace files, `team_names`, `audit_byok_use`, Stripe customer/subscription IDs. DPD §5.3 missing Art. 20. DPD §10 termination not yet considered. | FR8 widened. `legal-compliance-auditor` agent invoked as a phase. DPD §10 added to amendment list. |
| R11 | WORM-audit table reuses migration 037 pattern verbatim | Migration 037's FK uses `ON DELETE RESTRICT` — blocks `auth.admin.deleteUser()` until audit rows removed. | Plan uses `ON DELETE NO ACTION` + cascade extension that aborts in-flight jobs THEN anonymises THEN auth-deletes (AC25). WORM trigger conditional on a function-OID-allowlisted `SET app.dsar_audit_anonymise_in_progress` GUC (AC29 per S1 hardening). |
| R12 | `mcp__soleur_platform__dsar_export_status` is the read-only MCP tool name (FR10) | Existing house pattern. | **Deferred to v1.1 per D1.** No MCP tool ships in v1. DEC13 carve-out (no `_create` tool) trivially preserved by having no surface at all. |
| R-extra1 | Spec FR4 step 2: "construct Supabase client with the requester's stored JWT (NOT service-role)" | Storing user JWTs encrypted-at-rest creates a new credential vault — reversible session credentials with hours-long dwell time; key compromise yields mass impersonation; reuses BYOK-domain HKDF helper which breaks domain separation. **Largest unflagged risk per architecture-strategist + DHH + Kieran.** | **Per C1**: `owner_jwt_encrypted bytea` column dropped. Worker uses `service_role` Supabase client + mandatory per-row `WHERE owner_id = $jobs.user_id` (file-parse lint enforces this — AC30) + `assertReadScope(rows, expectedUserId, table_name)` on every fetch as defense-in-depth (AC12). The two-layer defense: per-row `WHERE` is the planner-level isolation; `assertReadScope` is the runtime invariant that fires P0 + raises if `WHERE` ever drifts or is bypassed. |
| R-extra2 | `legal-doc-cross-document-gate.yml` exists (AC8 cites it) | **Does not exist** in `.github/workflows/`. | Added to Files-to-Create per C8. |

## User-Brand Impact

Carry-forward verbatim from brainstorm `## User-Brand Impact` (with C1 reframe of vector (a) and (c)):

**If this lands broken, the user experiences:** another user's personal data inside the ZIP they downloaded from `/api/account/export/<jobId>?download=1` — names, conversation transcripts, attachments, KB workspace files belonging to a stranger.

**If this leaks, the user's data is exposed via:** the bundled artifact `dsar-exports/<userId>/<jobId>.zip` contains the entirety of one user's personal-data footprint with Soleur. Concrete vectors:

- (a) a missing `WHERE owner_id = $jobs.user_id` clause in a worker query, returning rows of users other than the requester. **Two-layer mitigation per C1**: (i) file-parse lint asserts every `service.from(<allowlisted-table>).select(...)` in `dsar-export.ts` carries `.eq('owner_id', expectedUserId)` (AC30); (ii) `assertReadScope` runtime invariant on every result raises `CrossTenantViolation` if any row's owner_id ≠ expected.
- (b) a Storage signed URL constructed with a `userId` variable shadowed/staled. Mitigated by the `<userId>/` path-prefix being derived from `auth.uid()` at issuance time, never from a route parameter or request body.
- (c) async-context bleed in the worker (job N's user context applied to job N+1). Per C1, the worker always operates as `service_role` and threads `expectedUserId` explicitly; per-row `WHERE` is the load-bearing isolation, not an ambient context. `assertReadScope` catches drift.
- (d) silent RLS failure returning `[]` instead of erroring per `2026-04-12-silent-rls-failures-in-team-names.md` and `2026-05-06-rls-zero-policies-anon-delete-204-semantic.md`. Mitigated by `assertReadScope` raising on empty-when-RLS-denied AND by cross-tenant golden fixture verifying via service-role re-check, never HTTP status.
- (e) signed URL leakage via email forwarding — mitigated by session+IP-bind + single-use + hard-delete-on-download.
- (f) `dsar_export_audit` PII column leak — mitigated by separating PII columns into `dsar_export_audit_pii` table, RLS-denied to the `authenticated` role, accessible only via `service_role` RPC + WORM trigger gated by function-OID allowlist (AC29).
- (g) **NEW vector eliminated by C1**: long-lived encrypted JWT-at-rest enabling mass impersonation if `BYOK_ENCRYPTION_KEY` leaks. Eliminated by not storing the JWT.

**Brand-survival threshold:** `single-user incident`. A single A→B leak triggers Art. 33 (CNIL, 72h) + Art. 34 (data subject, undue delay).

**Brand cost (irreversible):** the only event class worse than this for a privacy-positioned product is plaintext-credential leakage. A regulator-notified breach in the very surface designed to fulfil a data-subject right is reputational damage that does not recover.

**Sign-off requirements:**

- Plan-time: **CPO sign-off required before `/work` begins.** Brainstorm carries CPO+CLO+CTO framing; CPO must explicitly ack rev-2 of this plan before implementation.
- Review-time: `user-impact-reviewer` agent invoked as a conditional reviewer per `plugins/soleur/skills/review/SKILL.md`.
- Ship-time: preflight Check 6 verifies the section is present and the threshold is `single-user incident`.

## Domain Review (carry-forward)

Per `## Brainstorm carry-forward check`, brainstorm `## Domain Assessments` is imported.

**Domains relevant:** Engineering, Legal, Product. (Marketing, Operations, Sales, Finance, Support — not relevant; Support gains the email-fallback runbook in Phase 11.)

### Engineering (CTO) — carry-forward + rev-2 reframe
**Status:** reviewed (brainstorm); **rev-2 reframe:** worker is `service_role` + per-row `WHERE` + `assertReadScope` (NOT per-user-JWT), per C1.

### Legal (CLO) — carry-forward
**Status:** reviewed (brainstorm). 8 ACs (AC1-AC8) carry forward. GDPR sub-gates: Art-15, Art-20, Art-5-1-c, Art-5-2, Art-6, Art-12-3, Art-32, Art-33-34. Two policy enumeration gaps were two; rev-2 found three more (R10) — FR8 widened.

### Product (CPO) — carry-forward + plan-time sign-off requirement
**Status:** reviewed (brainstorm); **plan-time sign-off REQUIRED** per `single-user incident`. Brainstorm-recommended specialists: none beyond CTO/CLO/CPO. Skipped specialists: none.

## Open Questions Resolved

Brainstorm enumerated 8 questions; one additional (Q-extra) surfaced during research; one more (Q-credential) surfaced during plan-review. All resolved below.

| Q | Decision | Rationale | Long-form |
|---|---|---|---|
| Q1 | Substrate **(b) in-process setInterval reaper** + on-startup orphan-reset (S3) + pg_cron retention sweep (TR13) | (a) requires installing pg_net (R5); (c) requires Vercel (R6 — Hetzner); (b) matches `agent-runner.ts:698` house pattern. Single-instance constraint already shared with rate-limiter and reaper; all three migrate together when infra scales. | ADR `0NN-dsar-export-substrate-and-audit-retention.md` |
| Q2 | Phase 0 spike script + report; v1 cap parameterised by spike outcome | Hetzner Node memory (~4 GB allocation) + 50% safety margin = ~2 GB cap on peak RSS. Largest tier where peak RSS stays under 2 GB sets the cap. | ADR + spike report |
| Q3 | Resend inline HTML via existing `notifications.ts:9-58 getResend()`, no template engine; subject + preview text contain zero PII | TR6 + RK5 | ADR + TR6 |
| Q4 | TR4 v1 size cap = spike outcome (default placeholder removed; spike report is the authority) | Per S7 demote: AC9 → phase-exit gate. The spike report IS the cap declaration. | spike report |
| Q5 | IP /24 (IPv4) and /48 (IPv6) bind; mismatch → 409 with re-issue copy + inline reissue action on `[jobId]` route | FR5 + S9 | inline |
| Q6 | `account-delete.test.ts` exists; spec NG9 removed; lift the structure for `dsar-export.test.ts` | R2 | inline |
| Q7 | Compliance-cohort interplay deferred to ship-time check (#3603 PR-C must merge before this PR or be explicitly deferred with recorded ack) | RK3 | inline |
| Q8 | `legal@jikigai.com` channel **retained** in Privacy Policy §8.1 + GDPR Policy §5.3 — additive, not replacing | FR8 | inline |
| Q-extra | Art. 17 cascade vs 24-mo retention conflict: FK `ON DELETE NO ACTION` + cascade extension that **aborts in-flight DSAR jobs FIRST**, then anonymises PII columns of `dsar_export_audit_pii` via function-OID-allowlisted RPC, then `auth.admin.deleteUser()` | C6 + C7 + S1 + AC25 + AC29 | ADR + AC25 |
| Q-credential | Worker authentication: **`service_role` + per-row `WHERE owner_id = $1` + `assertReadScope`** (NOT per-user-JWT-at-rest, NOT per-user-JWT-mint-at-runtime) | C1 + R-extra1. Per-user-JWT-at-rest is a credential-vault risk class. Per-user-JWT-mint-at-runtime requires Supabase admin API capability that's not demonstrated for impersonation-as-user; available primitives mint magic-links not session JWTs. Service-role + per-row-WHERE + invariant assertion gives planner-level isolation by clause AND runtime invariant by code, with neither requiring a new credential surface. | ADR Q-credential |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/app/(dashboard)/dashboard/settings/page.tsx` | Add link/card surfacing the new `/settings/privacy` sub-route |
| `apps/web-platform/components/settings/settings-content.tsx` | Render the Privacy card alongside existing settings cards |
| `apps/web-platform/server/observability.ts` | **Add** sibling `mirrorCrossTenantViolation(offendingUserId, expectedUserId, tableName, err, ctx)` (does NOT modify existing `mirrorWithDebounce` signature — per C3 unfold of #3638). Internal: hashes both userIds via SHA-256 + existing `SOLEUR_SENTRY_PII_SALT` env before logging to Sentry payload. |
| `apps/web-platform/server/account-delete.ts` | Cascade extension per C6 + AC25: insert step **before** `auth.admin.deleteUser()` that (1) `UPDATE public.dsar_export_jobs SET status='failed', failure_reason='account_deleted_during_export' WHERE status IN ('pending','running') AND user_id=$1` (aborts in-flight jobs to prevent worker-against-tombstone P0 cascade), (2) calls `anonymise_dsar_export_audit_pii(p_user_id)` RPC. **Update the existing invariant comment at `:115-117`** to reflect the new ordering and the failure-mode (anonymise-succeeds-then-auth-delete-fails is recoverable because the job-row tombstone is reversible). Also extend storage-purge to include `dsar-exports/<userId>/`. |
| `apps/web-platform/server/notifications.ts` | **Add** `sendDsarExportReadyEmail(userId, jobId, expiresAt)` and `sendDsarExportFailedEmail(userId, jobId, reason)` (folded from rev-1's separate `dsar-email.ts` per C2). Lifts existing `getResend()`, `escapeHtml()`. Subject + preview-text PII-free per TR6. |
| `apps/web-platform/test/account-delete.test.ts` | Extend cascade-order test to include `["abort-dsar-jobs", "abort", "workspace", "storage-purge", "anonymise-dsar-audit", "auth"]`. Add test for "anonymise succeeds, auth-delete fails" recovery (job tombstone is reversible). |
| `apps/web-platform/test/auth-gate.test.ts` | Extend the auth-primitive enumeration to recognise `requireFreshReauth(req)` per `2026-04-18-auth-gate-smoke-tests-enumerate-patterns.md` (AC21). |
| `docs/legal/privacy-policy.md` §4.7 | Add five missing categories: `message_attachments`, KB workspace files (`/workspaces/<userId>/*`), `team_names`, `audit_byok_use`, Stripe customer/subscription IDs (note Stripe is independent controller for card data) |
| `docs/legal/privacy-policy.md` §8.1 | Add reference to `/settings/privacy` self-serve endpoint AND retain `legal@jikigai.com` fallback (Q8) |
| `docs/legal/gdpr-policy.md` §6.1.b | Same-PR pointer to in-product endpoint + format declaration |
| `docs/legal/gdpr-policy.md` §5.3 | Add self-serve path; retain `legal@jikigai.com` fallback |
| `docs/legal/data-protection-disclosure.md` §2.3 | Add new processing activity row (legal basis 6(1)(b) + 6(1)(c); retention audit 24mo, bundle 7d) |
| `docs/legal/data-protection-disclosure.md` §5.3 | Add Art. 20 enumeration |
| `docs/legal/data-protection-disclosure.md` §10 (per SpecFlow ripple finding) | Update termination clause to reflect DSAR-export retention obligations |
| `knowledge-base/legal/compliance-posture.md` Active Items | Row "DSAR Art. 15/20 self-serve endpoint" referencing this issue |

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/scripts/spike-dsar-streaming-upload.ts` | Phase 0 spike (Q2). Generates synthetic 100MB / 500MB / 1GB / 2GB tarballs (PRNG-seeded, per `cq-test-fixtures-synthesized-only`); streams via `archiver` → Bun `Readable.toWeb()` → Supabase Storage `upload()`; measures peak RSS (every 250ms), wall-clock duration, byte-for-byte SHA-256 round-trip. |
| `apps/web-platform/scripts/spike-dsar-streaming-upload-report.md` | Spike report. Captures the table per Q2; records Bun runtime invariant per S8; declares the v1 cap that Phase 1's migration uses. AC9 phase-exit gate (S7 demote). |
| `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql` | `dsar_export_jobs` (user-visible RLS) + `dsar_export_audit_pii` (admin-only) + 3 SECURITY DEFINER RPCs (`write_dsar_export_audit_pii`, `anonymise_dsar_export_audit_pii`, `claim_next_dsar_export_job`) + WORM trigger conditional on function-OID allowlist (AC29) + restrictive policy on `owner_session_id` + partial unique index on idempotency window + pg_cron retention sweep (TR13) + pg_cron TTL-expiry sweep (TR14). **No `owner_jwt_encrypted` column per C1.** |
| `apps/web-platform/supabase/migrations/042_dsar_exports_storage_bucket.sql` | Private `dsar-exports` bucket + RLS `(storage.foldername(name))[1] = auth.uid()::text` |
| `apps/web-platform/server/dsar-export.ts` | **All worker logic in one module per C2**: orchestrator (`enqueueExport`, `runExport`), enumerator (`information_schema.columns` + table allowlist + article-tag map), archiver (streaming-ZIP-to-Storage per spike outcome), poller (mirror `agent-runner.ts:698-714`; on-startup orphan-reset per S3), `assertReadScope` greenfield (per R1). Exports: `enqueueExport`, `startDsarExportReaper`, `assertReadScope`, `CrossTenantViolation`. |
| `apps/web-platform/server/dsar-reauth.ts` | Step-up reauth helpers: `issueReauthEvent(userId, sessionId)`, `consumeReauthEvent(reauthEventId, expectedUserId, expectedSessionId)` (validates `auth_time` claim ≤300s for OAuth flows per AC27), `requireFreshReauth(req): Promise<{userId, sessionId}>`. |
| `apps/web-platform/app/api/account/export/route.ts` | `POST` handler: validateOrigin + rejectCsrf + auth + abuse rate-limit (1 req/60s via `SlidingWindowCounter`) + consume reauth event + insert export job + return 202 |
| `apps/web-platform/app/api/account/export/[jobId]/route.ts` | `GET` handler: status (RLS-scoped read of `dsar_export_jobs`); `POST` handler: reissue (re-bind session+IP, reset TTL, log audit event) — per S9 inlining of rev-1's separate reissue route |
| `apps/web-platform/app/api/account/export/[jobId]/download/route.ts` | Stream Storage object with session+IP-bind enforcement; `nosniff` + RFC 6266 + sanitised filename (AC16); on completion hard-delete + UPDATE row; on `expired`/unknown jobId return 410 Gone with re-request copy (AC24) |
| `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/page.tsx` | Settings sub-page; surfaces "Download my data" CTA + "Delete my account" link + job-tracker list |
| `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/reauth/route.ts` | Step-up reauth handler (password re-entry; for OAuth, server-action redirects to `signInWithOAuth({prompt:'login', max_age:'300'})`) |
| `apps/web-platform/components/settings/dsar-export-dialog.tsx` | Single confirmation dialog with `<details>`-style "What's included" disclosure (per S9 collapse of rev-1 two-stage flow); "Continue" → reauth redirect → "we'll email you" confirmation |
| `apps/web-platform/components/settings/dsar-export-job-list.tsx` | RLS-scoped list of user's export jobs with reissue button (calls POST `/api/account/export/[jobId]` per S9 inline). Renders `expired` rows with "re-request" CTA per AC24. Disables "Download my data" button when active job exists per AC31. |
| `apps/web-platform/test/dsar-export.test.ts` | Vitest mock unit tests covering: enqueue, run-job happy path, silent-RLS detection (per `2026-04-12-silent-rls-failures-in-team-names.md`), `assertReadScope` raises on empty-when-denied AND on cross-tenant rows, archiver per-file-error policy (skip-with-manifest-entry for symlink/ino-mismatch; fail-job-loud for path-traversal — per AC26). Per C2 fold of rev-1's separate `dsar-export-silent-rls.test.ts`. |
| `apps/web-platform/test/dsar-export-route.test.ts` | Route-level tests: CSRF, auth, abuse rate-limit, reauth-event consumption (with `auth_time` validation per AC27), idempotency-within-window, IP-bind enforcement, expired-bundle 410 (AC24), concurrent-click (AC31). |
| `apps/web-platform/test/dsar-export-cross-tenant.integration.test.ts` | `SUPABASE_DEV_INTEGRATION=1` gated. Two synthesised users (A, B) per `cq-test-fixtures-synthesized-only`; seed overlapping content via service-role; export as A; assert via **service-role re-check** (NEVER HTTP status, per `2026-05-06-rls-zero-policies-anon-delete-204-semantic.md`) that zero rows / zero bytes / zero path-prefixes attributable to B appear in A's bundle. Add a content-level cross-tenant check per SpecFlow finding: scan A's exported markdown files for any string fragment matching B's distinguishing content. |
| `apps/web-platform/test/migration-rpc-grants.test.ts` | **Generalised file-parse migration test** (per Kieran's P1 generalisation): for every `CREATE FUNCTION ... SECURITY DEFINER` in `apps/web-platform/supabase/migrations/*.sql`, regex-require `REVOKE ALL ON FUNCTION public.<name>(...) FROM PUBLIC, anon, authenticated;` AND `SET search_path = public, pg_temp;` AND `public.`-qualified relations within the body. Per `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md` + `cq-pg-security-definer-search-path-pin-pg-temp`. Replaces rev-1's DSAR-specific `dsar-export-rpc-grants.test.ts`. |
| `apps/web-platform/test/dsar-allowlist-completeness.test.ts` | Per AC28 + S6: discover every public table with a column referencing `auth.users` (or `public.users` which cascades from auth.users) via `information_schema.columns` + `key_column_usage` + `referential_constraints`; assert each is either in the DSAR enumerator allowlist OR explicitly in the documented exclusions list (`apps/web-platform/server/dsar-export-exclusions.ts` constant) with a per-table reason. Prevents Art. 15 completeness drift across future migrations. |
| `apps/web-platform/test/dsar-worker-per-row-where.test.ts` | Per AC30 + C1: file-parse lint over `apps/web-platform/server/dsar-export.ts` asserting every `service.from('<allowlisted-table>').select(...)` is followed by `.eq('owner_id', expectedUserId)` or equivalent positive predicate over the owner column. Failure mode: a future refactor that drops the `WHERE` clause. |
| `apps/web-platform/test/dsar-worm-guc-sites.test.ts` | Per AC29 + S1: greps the codebase for `SET app.dsar_audit_anonymise_in_progress` and asserts exactly 1 occurrence (in the `anonymise_dsar_export_audit_pii` migration body). Prevents accidental WORM-bypass surface widening. |
| `knowledge-base/engineering/architecture/decisions/0NN-dsar-export-substrate-and-audit-retention.md` | New ADR. Records: Q1 substrate decision; Q-extra Art. 17 vs 24-mo conflict resolution; Q-credential C1 worker-auth decision (service-role + per-row WHERE + assertReadScope, with the alternatives considered and rejected); Bun runtime invariant per S8. **Lands in Phase 1 alongside the migration per architecture-strategist's ADR-precedes-consumers guidance.** |
| `knowledge-base/engineering/ops/runbooks/dsar-export-oversize.md` | Operator runbook for >v1-cap accounts |
| `knowledge-base/engineering/ops/runbooks/dsar-export-failed-job.md` | Operator runbook for failed-job triage |
| `apps/web-platform/scripts/dsar-export-oversize.sh` | Helper script for the oversize fallback runbook |
| `.github/workflows/legal-doc-cross-document-gate.yml` | **Per C8**: CI gate that fails the PR if the file modification set includes `apps/web-platform/server/dsar-export.ts` (or any other declared "regulated-data surface" file) AND does NOT include all four legal docs (`docs/legal/privacy-policy.md`, `docs/legal/gdpr-policy.md`, `docs/legal/data-protection-disclosure.md`, `knowledge-base/legal/compliance-posture.md`). |

## Functional Requirements

Spec FRs carried forward; rev-2 changes inline. All FRs cite implementation pointers per paper-resolution lint.

### FR1 — Settings UI surface
Single-stage confirmation dialog (per S9 collapse) with `<details>`-style "What's included" disclosure on `/settings/privacy`. Implementation: `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/page.tsx` + `apps/web-platform/components/settings/dsar-export-dialog.tsx`. Job-tracker list renders `expired` rows with re-request CTA (AC24); disables "Download my data" button when active job exists (AC31).

### FR2 — Step-up reauthentication gate
Greenfield per R9. Implementation: `apps/web-platform/server/dsar-reauth.ts`. OAuth flow validates `auth_time` claim ≤300s per AC27. `apps/web-platform/test/auth-gate.test.ts` extended to recognise `requireFreshReauth(req)` per AC21.

### FR3 — `POST /api/account/export`
Unchanged in shape from spec. Implementation pointers:
- `validateOrigin` + `rejectCsrf`: `apps/web-platform/lib/auth/validate-origin.ts:15-46`
- `supabase.auth.getUser()`: same as `apps/web-platform/app/api/account/delete/route.ts:18-21`
- Abuse rate-limit (1 req / 60s): `SlidingWindowCounter` from `apps/web-platform/server/rate-limiter.ts:44-130`
- Compliance idempotency (1/24h): partial unique index in migration 041
- `consumeReauthEvent`: `apps/web-platform/server/dsar-reauth.ts` — validates `auth_time` per AC27
- INSERT job + return 202: `apps/web-platform/server/dsar-export.ts` `enqueueExport`
- Every Supabase call destructures `{ error }` per AC20

### FR4 — Async export worker
Substrate **(b) in-process setInterval reaper** per Q1. Implementation in `apps/web-platform/server/dsar-export.ts` (single module per C2). Worker per job:

1. **On Node startup** (per S3): `UPDATE public.dsar_export_jobs SET status='pending', started_at=NULL WHERE status='running'` to recover any orphaned-on-restart jobs.
2. **Atomic claim** via `claim_next_dsar_export_job` RPC (`SECURITY DEFINER`, search_path pinned, named-role REVOKE per AC13/AC14). Single-row UPDATE … RETURNING with FOR UPDATE SKIP LOCKED.
3. **Construct `service_role` Supabase client** (NOT per-user-JWT per C1). Worker context holds `expectedUserId = jobs.user_id` for the entire run.
4. **For each table in the allowlist**: `service.from(table).select('*').eq('owner_id', expectedUserId)`. The `.eq('owner_id', expectedUserId)` is enforced by the file-parse lint `dsar-worker-per-row-where.test.ts` per AC30. Then `assertReadScope(rows, expectedUserId, table_name)` per AC12 (defense-in-depth — raises `CrossTenantViolation` if any row's `owner_id` ≠ expected; mirrors via `mirrorCrossTenantViolation` Sentry P0 with hashed userId).
5. **Storage**: `service.storage.from('chat-attachments').list(userId, ...)` then nested `${userId}/${folderName}` enumeration + `download()` per blob. Path-prefix guard: `if (!path.startsWith(\`${userId}/\`) || path.includes(".."))` rejects with **fail-job-loud** per AC26 (path-traversal in a service-role-derived path is a security-validation regression — never silently skip).
6. **KB workspace** (`/workspaces/<userId>/*`): `O_NOFOLLOW` on open + `fstat` ino verify across hash→serve gap per AC17. Symlinks (ELOOP) and ino-mismatch result in **skip-with-manifest-entry** per AC26 (data-quality concern, not security regression).
7. **Build archive to `${WORKSPACE_BASE}/_dsar-tmp/<jobId>.zip`** via `O_NOFOLLOW + fstat` ino verify; **upload via raw `fetch` POST** with `Content-Length` + `duplex: 'half'` from `fs.createReadStream()` (disk-then-upload per Phase 0 spike outcome + ADR-028 §D4 — `supabase-js.upload(WebReadableStream)` buffers the body, defeating the streaming hypothesis). Per-file SHA-256 computed during the same fd-pass that writes to the local tmpfile per AC18 (single-fd; no re-open).
8. **Write `manifest.json` LAST** with serialization conventions per AC23: ISO 8601 with UTC offset, base64 for `bytea`, JSON null for SQL NULL, sorted keys, `schema_version: "1.0.0"`, `excluded_files[]` populated from per-file errors per AC26.
9. **Mark row** `status='completed'`, `signed_url_expires_at=now()+7d`, `bundle_sha256`, `bundle_size_bytes`. Send email via `notifications.ts:sendDsarExportReadyEmail`.

**Per-job timeout**: `AbortController` + manual `setTimeout(controller.abort, JOB_HARD_TIMEOUT_MS)` (default 30 min) per `cq-abort-signal-timeout-vs-fake-timers`. On timeout: mark failed, `failure_reason='job_timeout'`, partial Storage object purged, `mirrorWithDebounce` keyed `feature: "dsar-export-job-timeout"`, `sendDsarExportFailedEmail`.

**On any worker error**: `mirrorWithDebounce` keyed `(userId, "dsar-export-failed")` + UPDATE row failed + email user.

**Empty-export user** (zero rows across all tables): produces a valid bundle with manifest + empty per-table files; email distinguishes via "your account contained no exportable data beyond account metadata" copy per AC23 implicit.

### FR5 — `GET /api/account/export/[jobId]/download`
Implementation refinements:
- `Content-Type: application/zip` + `X-Content-Type-Options: nosniff` per AC16
- RFC 6266 Content-Disposition: `attachment; filename="soleur-data-export.zip"; filename*=UTF-8''soleur-data-export.zip` (fixed filename — no user-controlled tokens; no header-injection vector via CR/LF — per AC16)
- Single-use atomic UPDATE with RETURNING; loser of race gets 410
- On expired or unknown jobId: 410 Gone with body `{ error: 'export_expired', remediation: 'Visit /settings/privacy to request a fresh export.' }` per AC24
- On stream completion: hard-delete Storage object + UPDATE `status='delivered'`

### FR6 — Job-tracker UI at `/settings/privacy`
Lists `dsar_export_jobs` (RLS-scoped). Statuses include `expired` per AC24. Reissue is a POST to `/api/account/export/[jobId]` per S9 inline. "Download my data" button disabled when active job exists per AC31.

### FR7 — Audit-log schema (`dsar_export_jobs` + `dsar_export_audit_pii`)
Refined per R11 + Q-extra + S1:
- FK to `auth.users` uses `ON DELETE NO ACTION`.
- WORM trigger `dsar_export_audit_pii_no_mutate` raises `'P0001'` on UPDATE/DELETE EXCEPT when GUC `app.dsar_audit_anonymise_in_progress = on` is set AND `current_user = 'service_role'` AND the calling function OID is in a hard-coded allowlist (per AC29 + S1).
- File-parse lint `dsar-worm-guc-sites.test.ts` asserts the `SET app.dsar_audit_anonymise_in_progress` token appears exactly once in the codebase (in the anonymise RPC body) per AC29.
- `SECURITY DEFINER` RPCs follow the named-role REVOKE shape per AC13 + the search_path pin + `public.`-qualified relations per AC14 — enforced by the generalised `migration-rpc-grants.test.ts`.
- Restrictive RLS on `owner_session_id` per constitution `:88`.

### FR8 — Cross-document legal-artifact amendments (same PR)
Refined per R10 + SpecFlow ripple:
- Privacy Policy §4.7 enumerates the five missing categories
- Privacy Policy §8.1 self-serve + retain `legal@jikigai.com`
- GDPR Policy §6.1.b + §5.3 self-serve + retain
- DPD §2.3 new processing activity row
- DPD §5.3 add Art. 20
- DPD §10 termination clause updated
- `compliance-posture.md` Active Items row

`legal-compliance-auditor` agent invoked as a phase per `2026-03-18-legal-cross-document-audit-review-cycle.md`. CI gate `.github/workflows/legal-doc-cross-document-gate.yml` (per C8) blocks merge if any of the four files is unmodified.

### FR9 — Cross-tenant safety primitives
Refined per R1 + C1:
- `assertReadScope(rows, expectedUserId, tableName)` greenfield in `apps/web-platform/server/dsar-export.ts`. Throws `CrossTenantViolation`. Mirrors via new `mirrorCrossTenantViolation` sibling on `observability.ts` (does NOT widen `mirrorWithDebounce` per C3).
- Per-row `WHERE owner_id = $1` enforced by `dsar-worker-per-row-where.test.ts` per AC30 — the planner-level isolation.
- Two-user golden fixture in `dsar-export-cross-tenant.integration.test.ts`: synthesised users A + B; seeded via service-role; export as A; assert via **service-role re-check** that zero rows / bytes / path-prefixes attributable to B appear in A's bundle. Includes content-level scan per SpecFlow finding.
- Silent-RLS-failure unit test inside `dsar-export.test.ts` (per C2 fold).

### FR10 — Read-only MCP surface (DEFERRED to v1.1)
**Per D1**: deferred. v1 ships no MCP tool. DEC13 carve-out (no `_create` tool) is preserved trivially by having no surface. v1.1 once a named agent workflow asks for it; create issue at ship-time.

## Technical Requirements

| ID | Requirement | Implementation pointer |
|---|---|---|
| TR1 | Migration `041_dsar_export_jobs.sql` adds `dsar_export_jobs` + `dsar_export_audit_pii` (mirrors `037_audit_byok_use.sql` pattern) with named-role REVOKE shape AND function-OID-allowlisted WORM trigger. **No `owner_jwt_encrypted` column** per C1. | `apps/web-platform/supabase/migrations/041_dsar_export_jobs.sql` |
| TR2 | Migration `042_dsar_exports_storage_bucket.sql` adds private bucket + folder-prefix RLS | `apps/web-platform/supabase/migrations/042_dsar_exports_storage_bucket.sql` |
| TR3 | **Disk-then-upload** pattern per Phase 0 spike outcome + ADR-028 §D4: archive built to local tmpfile (`${WORKSPACE_BASE}/_dsar-tmp/<jobId>.zip`, `O_NOFOLLOW + fstat` ino verify), then streamed to Supabase Storage via raw `fetch` POST with `Content-Length` + `duplex: 'half'`. `supabase-js.upload(WebReadableStream)` rejected — measured to buffer the body (Δ RSS ≈ 1.09× payload). | folded into `apps/web-platform/server/dsar-export.ts` per C2; spike at `apps/web-platform/scripts/spike/dsar-streaming-upload.ts` (path corrected from plan literal `scripts/spike-...` to match in-tree convention) |
| TR4 | v1 size cap **1024 MB (1 GiB)**, env-overrideable via `DSAR_EXPORT_SIZE_CAP_MB`. ~40% safety margin under the 2 GB Hetzner allocation ceiling using the measured 1.1× buffering coefficient. **Provisional — re-validate on Node 22 prd** (post-merge PM.4); operator may tighten env var post-deploy. | spec FR4 step 8; spike report `apps/web-platform/scripts/spike/dsar-streaming-upload-report.md` |
| TR5 | Worker per-job hard timeout 30 min via `AbortController` + manual `setTimeout` per `cq-abort-signal-timeout-vs-fake-timers` (spec's `maxDuration: 300` Vercel value moot per R6) | folded into `apps/web-platform/server/dsar-export.ts` |
| TR6 | Email via existing `notifications.ts:9-58 getResend()` (no template engine; PII-free subject + preview text; plain `<a>` link, not auto-tracked); folded `dsar-email.ts` per C2 | `apps/web-platform/server/notifications.ts` (extended) |
| TR7 | Rate-limit substrate: partial unique index = 1/24h compliance; `SlidingWindowCounter` (1 req/60s) = abuse | migration 041 + `apps/web-platform/app/api/account/export/route.ts` |
| TR8 | Step-up reauth route handles password re-entry; OAuth uses `signInWithOAuth({prompt:'login', max_age:'300'})`; `consumeReauthEvent` validates `auth_time` claim per AC27 | `apps/web-platform/server/dsar-reauth.ts` + `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/reauth/route.ts` |
| TR9 | **REMOVED** (was widening `mirrorWithDebounce` to 3-tuple key — per C3 unfold of #3638). Replaced by sibling `mirrorCrossTenantViolation` added without modifying existing signature. | n/a |
| TR10 | **REMOVED** (was `Art17ErasureHook` registry — per C4 cut as premature pluggability). | n/a |
| TR11 | `auth-gate.test.ts` extended to enumerate `requireFreshReauth(req)` per `2026-04-18-auth-gate-smoke-tests-enumerate-patterns.md` | `apps/web-platform/test/auth-gate.test.ts` |
| TR12 | **REPLACED** (was pg_cron stuck-job sweep — per S3 simpler equivalent): on Node startup, the poller runs `UPDATE dsar_export_jobs SET status='pending', started_at=NULL WHERE status='running'` once before the first `setInterval` tick. Saves a cron schedule + dev/prd verification ceremony. | `apps/web-platform/server/dsar-export.ts` `startDsarExportReaper()` init |
| TR13 | pg_cron retention sweep (24-month PII): `SELECT cron.schedule('dsar-export-pii-retention-sweep', '0 3 * * *', $$DELETE FROM public.dsar_export_audit_pii WHERE created_at < now() - interval '24 months'$$);` | migration 041 |
| TR14 | pg_cron TTL-expiry sweep (per AC24 + S/C7): hourly, deletes Storage objects for jobs where `signed_url_expires_at < now() AND status='completed' AND downloaded_at IS NULL`, flips status to `expired`. Uses pg_net? **No** — pg_net not installed (R5). Implementation: cron schedules a SQL function that updates status to `expired`; the in-process poller reads `expired`-status rows and performs Storage deletion via service-role client (deferred from cron to Node so we don't introduce pg_net). | migration 041 + `apps/web-platform/server/dsar-export.ts` |
| TR15 | New `mirrorCrossTenantViolation(offendingUserId, expectedUserId, tableName, err, ctx)` on `observability.ts` (per C3, replaces removed TR9). Hashes both userIds via SHA-256 + `SOLEUR_SENTRY_PII_SALT` before logging. | `apps/web-platform/server/observability.ts` |

## Acceptance Criteria

Spec AC1-AC8 carry forward (compliance baseline). Rev-2 changes per C/S findings. Each AC cites an implementation pointer per paper-resolution lint.

### Pre-merge (PR)

- **AC1** (CLO AC-1 + R10): Bundle reconciles 1:1 with Privacy Policy §4.7 + §4.8 + §4.9 enumerated categories (after FR8 update). CI test in `dsar-export-cross-tenant.integration.test.ts` asserts every category present or marked N/A in `manifest.json`.
- **AC2** (CLO AC-2 + AC23): Bundle = ZIP containing `manifest.json` + JSON-per-table + markdown originals + binaries. Each file tagged `{article: "15"|"15+20"}` with SHA-256, source table, row count. Manifest declares `schema_version: "1.0.0"` + serialization conventions per AC23.
- **AC3** (CLO AC-3 + AC27): Step-up reauth within 5min; OAuth `max_age=300` + `auth_time` claim validation per AC27; job bound to reauth'd `session_id`; revocation invalidates URL. Implementation: `dsar-reauth.ts` + `dsar-export.ts:enqueueExport`.
- **AC4** (CLO AC-4): `acknowledged_at` returned synchronously (route handler median ≤500ms); async job p95 ≤48h, hard ≤7d; Art. 12(3) extension flow exists with email notification within 30d. Implementation: `apps/web-platform/app/api/account/export/route.ts`.
- **AC5** (CLO AC-5): Signed URL TTL = 7d; bound to session + IP /24 (IPv6 /48); single-use; Storage hard-deleted on first download or at TTL (whichever first via TR14). Implementation: `apps/web-platform/app/api/account/export/[jobId]/download/route.ts`.
- **AC6** (CLO AC-6): `assertReadScope` invocation on every result set + per-row `WHERE owner_id = $1` (file-parse lint per AC30) + cross-tenant golden-fixture CI test (synthesised users, service-role re-check assertion per `2026-05-06-rls-zero-policies-anon-delete-204-semantic.md`). Implementation: `apps/web-platform/server/dsar-export.ts` + `dsar-export-cross-tenant.integration.test.ts`.
- **AC7** (CLO AC-7 + Q-extra + AC29): Audit log: separate `dsar_export_audit_pii` table, RLS-denied to app role, append-only via WORM trigger gated by function-OID allowlist + service-role check (AC29), PII-minimal payload, 24-month TR13 retention sweep; Art. 17 cascade per AC25. Implementation: migration 041 + extended `account-delete.ts`.
- **AC8** (CLO AC-8 + R10 + C8): Privacy Policy §4.7/§8.1, GDPR Policy §6.1.b/§5.3, DPD §2.3/§5.3/§10, and `compliance-posture.md` updated in same PR. CI gate `.github/workflows/legal-doc-cross-document-gate.yml` blocks merge if any of the four files is unmodified. `legal-compliance-auditor` agent invoked as a phase during `/work`.
- **AC12** (R1 + C1): `assertReadScope` built greenfield (not lifted). Sibling `mirrorCrossTenantViolation` on `observability.ts` added without modifying `mirrorWithDebounce` (per C3). Cross-tenant test pattern lifted from `apps/web-platform/test/server/agent-runner.tenant-isolation.test.ts`.
- **AC13** (per `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md` + Kieran's generalisation): `migration-rpc-grants.test.ts` is a generalised file-parse test that, for every `CREATE FUNCTION ... SECURITY DEFINER` across `apps/web-platform/supabase/migrations/*.sql`, regex-requires explicit `REVOKE ALL ON FUNCTION public.<name>(...) FROM PUBLIC, anon, authenticated;` then `GRANT EXECUTE TO service_role;`. Replaces rev-1's DSAR-specific test. Implementation: `apps/web-platform/test/migration-rpc-grants.test.ts`.
- **AC14** (per `cq-pg-security-definer-search-path-pin-pg-temp` — generalised by AC13's test): every `SECURITY DEFINER` RPC sets `search_path = public, pg_temp` AND qualifies every relation with `public.`. Asserted by the same `migration-rpc-grants.test.ts` regex set.
- **AC15** (reframed for C1 — per-row WHERE compliance integration test): integration test under service-role connection asserts that every `service.from('<allowlisted-table>').select(...).eq('owner_id', test_user_a)` returns ZERO rows owned by `test_user_b` AND that `assertReadScope` raises if a fixture intentionally returns a misowned row. Implementation: `dsar-export-cross-tenant.integration.test.ts`.
- **AC16** (per `2026-04-12-binary-content-serving-security-headers.md`): download response includes `Content-Type: application/zip`, `X-Content-Type-Options: nosniff`, RFC 6266 `Content-Disposition` with sanitised fixed filename (no user-controlled tokens; no CR/LF). Implementation: `apps/web-platform/app/api/account/export/[jobId]/download/route.ts`.
- **AC17** (per `2026-04-15-kb-share-binary-files-lifecycle.md` + `2026-04-17-stream-response-toctou-across-fd-boundary.md`): workspace file reads use `O_NOFOLLOW` on open + `fstat` ino verify. Implementation: `apps/web-platform/server/dsar-export.ts` workspace-read helper.
- **AC18** (per `2026-04-17-stream-response-toctou-across-fd-boundary.md`): per-file SHA-256 in manifest computed during the same fd-pass that streams bytes into the archiver — never via re-open. Implementation: `apps/web-platform/server/dsar-export.ts` archiver-pipe.
- **AC19** (per `2026-05-05-defense-relaxation-must-name-new-ceiling.md`): the 1h→7d TTL relaxation MUST cite, in `dsar-export.ts` at the URL-issuance call site, all four compensating defences (session-bind, IP-bind, single-use, hard-delete-on-download) and name the new ceiling (7d hard expiry + Storage object lifetime via TR14). The comment is the standing reminder against future refactors that drop one defence.
- **AC20** (per `2026-03-20-supabase-silent-error-return-values.md`): every `supabase.from(...)`, `supabase.rpc(...)`, `supabase.auth.*` call site destructures `{ error }` AND propagates via `Sentry.captureException` + appropriate response. No silent `.data ?? defaultValue`.
- **AC21** (per `2026-04-18-auth-gate-smoke-tests-enumerate-patterns.md`): `auth-gate.test.ts` extended to recognise `requireFreshReauth(req)` so future routes that omit it are caught by CI.
- **AC22** (rev-2 — sibling `mirrorCrossTenantViolation` shape): the new helper is functionally distinct from `mirrorWithDebounce`: it accepts `(offendingUserId, expectedUserId, tableName, err, ctx)`, internally hashes both userIds via SHA-256 + `SOLEUR_SENTRY_PII_SALT`, and routes to Sentry with `level: 'fatal'` + `tags: { sec: true, dsar: true, cross_tenant: true }`. **Does NOT modify** existing 5 callers of `mirrorWithDebounce` (per C3 unfold of #3638).
- **AC23** (per SpecFlow finding — manifest serialization conventions): manifest and per-table JSON files use ISO 8601 timestamps with UTC offset, base64 for `bytea`, JSON `null` for SQL NULL, sorted object keys for deterministic SHA-256. Documented in `dsar-export.ts` JSDoc + verified by golden fixture in `dsar-export.test.ts`.
- **AC24** (per SpecFlow finding — `expired` lifecycle): job status enum is `pending | running | completed | delivered | expired | failed`. TR14 pg_cron sweep flips `completed → expired` after TTL; in-process poller deletes the Storage object on observing `expired`. Job-tracker UI renders `expired` rows with re-request CTA. Download endpoint on `expired` or unknown jobId returns 410 Gone with body `{ error: 'export_expired', remediation: 'Visit /settings/privacy to request a fresh export.' }`. Closes the spec FR6 ↔ plan FR4 drift on `expired` status.
- **AC25** (per Architecture-Strategist + SpecFlow + C6 — account-delete cascade): `account-delete.ts` cascade order is `["abort-dsar-jobs", "abort", "workspace", "storage-purge" (incl. dsar-exports prefix), "anonymise-dsar-audit", "auth"]`. The "abort-dsar-jobs" step `UPDATE`s any `pending`/`running` DSAR jobs for the deleting user to `failed` with `failure_reason='account_deleted_during_export'` BEFORE the audit anonymisation. The existing invariant comment at `apps/web-platform/server/account-delete.ts:115-117` is **updated in the same edit** to reflect the new ordering and the recoverability of the failure-mode (anonymise-succeeds-then-auth-delete-fails: the anonymise RPC is idempotent — re-runs are safe; the failure-mode is recoverable). Test added: "anonymise succeeds, auth-delete fails" recovery.
- **AC26** (per SpecFlow finding — per-file error policy): worker per-file errors:
  - **Symlink (ELOOP) on workspace file**: skip-with-manifest-entry `{path, included: false, reason: 'symlink_rejected'}` in `excluded_files[]`.
  - **fstat ino-mismatch (TOCTOU evidence)**: skip-with-manifest-entry `{path, included: false, reason: 'inode_mismatch'}`.
  - **Path-traversal in `chat-attachments/` (`..`-bearing path)**: fail-job-loud (security-validation regression — never silently skip; raises, mirrorCrossTenantViolation fires).
  - Test fixtures cover each rejection class in `dsar-export.test.ts`.
- **AC27** (per SpecFlow finding — `auth_time` claim validation): `dsar-reauth.ts:consumeReauthEvent` validates the JWT `auth_time` claim is within 300s of `now()` for OAuth flows. Defends against IdPs that silently ignore `prompt=login`. Implementation: `apps/web-platform/server/dsar-reauth.ts`.
- **AC28** (per Architecture-Strategist + S6 — allowlist completeness CI gate): `dsar-allowlist-completeness.test.ts` discovers every public table with a column referencing `auth.users` (or `public.users` which cascades from auth.users) via `information_schema` + `key_column_usage`; asserts each is either in the DSAR enumerator allowlist OR in the documented exclusions list with a reason. Prevents Art. 15 completeness drift.
- **AC29** (per Architecture-Strategist + S1 — WORM-bypass GUC hardening): WORM trigger `dsar_export_audit_pii_no_mutate` raises `'P0001'` on UPDATE/DELETE EXCEPT when ALL of: (a) GUC `app.dsar_audit_anonymise_in_progress = on`, (b) `current_user = 'service_role'`, (c) calling function OID is in a hard-coded allowlist (currently: `anonymise_dsar_export_audit_pii`'s OID). File-parse test `dsar-worm-guc-sites.test.ts` asserts the `SET app.dsar_audit_anonymise_in_progress` token appears exactly once in the codebase (in the anonymise RPC body). Prevents accidental WORM-bypass surface widening.
- **AC30** (per C1 + R-extra1 — per-row WHERE file-parse lint): `dsar-worker-per-row-where.test.ts` parses `apps/web-platform/server/dsar-export.ts` and asserts every `service.from('<allowlisted-table>').select(...)` is followed by `.eq('owner_id', expectedUserId)` or equivalent positive predicate over the owner column. Failure mode: a future refactor that drops the `WHERE` clause silently widens cross-tenant surface.
- **AC31** (per SpecFlow finding — concurrent-click UX): "Download my data" button in `dsar-export-dialog.tsx` is disabled when an active job exists for the user (`status IN ('pending','running','completed')`); shows status + ETA inline. Tested in route-level test `dsar-export-route.test.ts`.

**Demoted from pre-merge ACs to phase-exit gates per S7:**
- ~~AC9~~ (spike report exists at named path) — Phase 0 exit gate; the report itself is the deliverable, not a pre-merge AC.
- ~~AC11~~ (5-agent panel sign-off captured in plan rev-2) — process gate fulfilled by this plan revision; `/work` reads rev-2.
- ~~AC10~~ (read-only MCP tool present) — **deferred to v1.1 per D1**.

### Post-merge (operator)

- **AC-PM-1**: Migrations 041 + 042 applied to **dev** Supabase project FIRST, verified via REST API. Then to **prd**. Per `wg-when-a-pr-includes-database-migrations` and `hr-dev-prd-distinct-supabase-projects`.
- **AC-PM-2**: pg_cron schedules verified live in dev + prd via `select * from cron.job where jobname like 'dsar-export-%';` returns 2 rows (`dsar-export-pii-retention-sweep`, `dsar-export-bundle-ttl-sweep` — TR12's stuck-job sweep is replaced by S3 startup-reset).
- **AC-PM-3**: Storage bucket `dsar-exports` exists in dev + prd, listed `private`, RLS verified via test request as anon role returning 0 rows.
- **AC-PM-4**: First end-to-end exercise as an internal synthesised account (a real Supabase account on the synthetic-allowlist per `cq-destructive-prod-tests-allowlist`) — POST/poll/email/download/delete cycle completes without error, then `gh issue close 3637`.

## Test Scenarios (Given / When / Then)

### TS1 — Happy path: small account export
**Given** user with 5 conversations, 20 messages, 2 attachments (~50 KB total)
**When** they request export from `/settings/privacy` after step-up reauth
**Then** within 60 seconds: job row inserted, worker claims, archiver streams to Storage, email sent, link works once, Storage object hard-deleted on download, row marked `delivered`.

### TS2 — Cross-tenant isolation invariant (load-bearing)
**Given** synthesised users A and B with overlapping content
**When** A exports
**Then** A's bundle contains zero rows / bytes / path-prefixes attributable to B, verified via service-role re-check (NEVER HTTP status). `assertReadScope` raises on first leak. Content-level check additionally scans A's exported markdown for distinguishing fragments of B's content.

### TS3 — Silent RLS failure detection
**Given** a query that would normally return rows but the per-row WHERE silently fails (e.g., bug introduced that drops `.eq('owner_id', ...)`)
**When** worker attempts export
**Then** `dsar-worker-per-row-where.test.ts` (file-parse lint) catches at CI, BEFORE the bug ever ships. If somehow it slips: `assertReadScope` raises on first row whose `owner_id` ≠ expected; `mirrorCrossTenantViolation` fires P0 with hashed userId.

### TS4 — Stolen-session attack mitigation
**Given** attacker holds user's session cookie (no fresh reauth)
**When** attacker calls `POST /api/account/export`
**Then** route returns 403 — reauth_event_id missing or stale.

### TS4b — OAuth `prompt=login` ignored
**Given** OAuth IdP silently ignores `prompt=login` and returns a stale `auth_time` claim
**When** user attempts step-up reauth
**Then** `consumeReauthEvent` rejects with 401 + "your provider did not honour the re-authentication request; please log out and back in" copy. Per AC27.

### TS5 — Signed URL session+IP-bind enforcement
**Given** legitimate export completed; user forwards email to a coworker on a different network
**When** coworker clicks the link
**Then** download endpoint returns 409 with re-issue guidance; Storage object remains intact.

### TS6 — Idempotency within 24h window
**Given** user successfully POSTs export (job_id = X)
**When** user POSTs again within 24h
**Then** route returns 200 with the same `job_id = X` (per partial unique index).

### TS7 — Worker timeout
**Given** worker mid-export hits the 30-min hard timeout
**When** AbortController fires
**Then** job marked `failed`, `failure_reason='job_timeout'`, partial Storage object purged, `mirrorWithDebounce` records P0 event, `sendDsarExportFailedEmail` sent.

### TS7b — Archiver mid-stream failure
**Given** worker mid-stream throws after partial Storage upload
**When** the error propagates
**Then** partial Storage object is purged in the catch block; job marked failed; mirror fires.

### TS8 — Orphaned-on-restart recovery (S3 replaces stuck-job cron)
**Given** Node instance died after claiming a job (`status='running'`)
**When** Node starts up
**Then** poller's startup query `UPDATE … SET status='pending' WHERE status='running'` resets the orphan; first reaper tick re-claims it.

### TS9 — Account-deletion-during-export semantic (AC25)
**Given** user requests Art. 17 deletion while a DSAR export job is `running` for that user
**When** `account-delete.ts` cascade runs
**Then** the cascade aborts in-flight DSAR jobs (`UPDATE status='failed', failure_reason='account_deleted_during_export'`) BEFORE invoking the anonymise RPC — preventing the worker from later observing a tombstoned `user_id` and triggering `assertReadScope` P0 against itself.

### TS10 — Cross-document consistency CI gate
**Given** PR modifies `apps/web-platform/server/dsar-export.ts` but does NOT modify `docs/legal/privacy-policy.md`
**When** CI runs `.github/workflows/legal-doc-cross-document-gate.yml`
**Then** CI fails with explanation pointing to FR8 / AC8.

### TS11 — Live-API verification per `2026-04-22-plan-ac-external-state-must-be-api-verified.md`
**Given** AC8 lists §4.7, §8.1, §6.1.b, §5.3, §2.3, §10 as the sections to amend
**When** plan reviewer greps the docs
**Then** every section number cited exists in the named file (no renumbered drift). Verified at plan time before the AC is frozen.

### TS12 — `expired` bundle lifecycle (AC24)
**Given** export completes; user never downloads; 7 days pass
**When** TR14 pg_cron tick fires
**Then** status flips to `expired`; on next poller tick the Storage object is deleted; `GET …?download=1` returns 410 Gone with re-request copy.

### TS13 — Empty-export user (AC23 implicit)
**Given** brand-new account with zero conversations / messages / attachments
**When** export runs
**Then** bundle contains valid manifest + empty per-table files; email body says "your account contained no exportable data beyond account metadata."

### TS14 — Path-traversal in `chat-attachments/` (AC26 fail-job-loud)
**Given** `chat-attachments/<userId>/` contains a file with `..` in its path (regression from prior validation)
**When** worker enumerates Storage
**Then** worker fails the job loud (`mirrorCrossTenantViolation` fires); does NOT silently skip.

### TS15 — Symlink in workspace (AC26 skip-with-manifest)
**Given** `/workspaces/<userId>/foo` is a symlink
**When** worker reads with `O_NOFOLLOW`
**Then** open() returns ELOOP; manifest's `excluded_files[]` gains `{path: 'foo', included: false, reason: 'symlink_rejected'}`; job continues; no security alert.

### TS16 — Concurrent-click UX (AC31)
**Given** user has an active export job (`status='running'`)
**When** user opens `/settings/privacy`
**Then** "Download my data" button is disabled with status + ETA inline; second-click does not POST.

## Open Code-Review Overlap

Per Phase 1.7.5 grep against open code-review issues:

- **#3638** (`observability.ts`): "hash userId in Sentry mirror payload + Art. 17 erasure hooks for breach-attempt events (#3603 PR-A2 H6/H7)." → **Acknowledged** (rev-2 per C3 unfolds the rev-1 fold-in). The DSAR plan adds a new sibling `mirrorCrossTenantViolation` (TR15) that internally hashes userIds via the same `SOLEUR_SENTRY_PII_SALT` env var, but does NOT modify the existing `mirrorWithDebounce` signature or its 5 callers. #3638's broader work (hashing userIds in `mirrorWithDebounce` itself + the Art. 17 erasure-hook registry) lands separately. PR body MUST NOT contain `Closes #3638`; instead, link as `Ref #3638` with note "DSAR adopts the userId-hashing convention via sibling helper; this PR does not modify the existing primitive."
- **#2197 / #2196** (`rate-limiter.ts`): refactors. → **Acknowledge.** This PR consumes `SlidingWindowCounter` as-is.
- **#3642 / #3639** (`observability.ts`): cc-dispatcher op-slug constant hoist + TurnPersistenceState extraction. → **Acknowledge.** Different concern.
- **#3454 / #3392 / #3343 / #3242** (`agent-runner.ts`): pdf_metadata MCP, PR-B deferrals, document-escape, tool_use WS. → **Acknowledge.** This PR references `agent-runner.ts:698` only as a pattern source.
- **#3221 / #3220** (`supabase/migrations`): nightly cron + postmerge migration verification. → **Acknowledge** with cross-reference. AC-PM-1 covers manual verification if #3220 hasn't landed.

## Sharp Edges

- **Worker is `service_role` per C1.** Every `service.from('<allowlisted-table>').select(...)` call MUST carry `.eq('owner_id', expectedUserId)`. The `dsar-worker-per-row-where.test.ts` file-parse lint is the gate. A reviewer who accepts a refactor that drops the `.eq()` is approving a cross-tenant footgun — and `assertReadScope` is the runtime catch but the lint is the no-runtime-failures-make-it-to-prod first line.
- **The brainstorm + spec contained four stale citations** (R1, R3, R4, R-extra1). Plan reviewers and `/work` agents MUST trust the Research Reconciliation table over any other reference. Re-grep before quoting any line number to a downstream consumer.
- **Phase 0 spike is a phase-exit gate.** Do not start Phase 1 (migrations) until the spike report exists and TR4's size cap is set in the migration based on the spike outcome.
- **`SECURITY DEFINER` RPCs without explicit named-role REVOKE silently grant EXECUTE to anon and authenticated** per Supabase auto-grant default. AC13's generalised `migration-rpc-grants.test.ts` is the gate across all migrations, not just DSAR.
- **Cross-tenant golden-fixture tests asserting via HTTP status alone are insufficient.** Service-role re-check after extracting the bundle is the load-bearing assertion shape.
- **The 1h→7d signed-URL TTL relaxation must explicitly enumerate the new ceiling and compensating defences at the URL-issuance call site** per AC19. A future refactor that drops one of session-bind / IP-bind / single-use / hard-delete-on-download silently widens the attack surface.
- **Art. 17 cascade order is load-bearing** (AC25): abort-dsar-jobs → abort → workspace → storage-purge → anonymise-dsar-audit → auth. Reversing any pair risks (a) the worker continuing against a tombstone (cross-tenant P0 alert against itself), (b) auth row gone before audit PII anonymised (forensic data loss), or (c) account-locked with audit row never anonymised (Art. 17 violation).
- **WORM-bypass GUC has THREE gates** per AC29 + S1: GUC set, `current_user='service_role'`, function-OID in allowlist. Any future migration that ALTERs the trigger to relax these gates regresses the WORM guarantee. The `dsar-worm-guc-sites.test.ts` lint catches accidental new GUC-set sites.
- **The settings UI flow surfaces a high-friction "step-up reauth" path for the first time in this codebase.** UX must be tested end-to-end with Playwright MCP per `wg-when-a-feature-creates-external` before shipping. Specifically: password account flow, OAuth flow (Google), failure modes (wrong password, OAuth canceled, reauth event expired between confirm and POST, IdP ignores `prompt=login`).
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is filled with concrete vectors and the threshold is `single-user incident`.

## Risks

| ID | Risk | Mitigation | Tracking |
|---|---|---|---|
| RK1 | Phase 0 spike fails entirely (archiver + Supabase upload OOMs at smallest tier) | Disk-then-upload fallback; cap v1 at validated tier | Spike report |
| RK2 | `pg_cron + pg_net` substrate forced by reviewer | Plan Q1 + ADR documents the rationale (no pg_net installed; matches house pattern); reviewer dissent triggers ADR amendment, not silent pivot | ADR |
| RK3 | Compliance-cohort interplay (Q7): cohort user runs new endpoint BEFORE supplementary disclosure for #3603 | Ship-time check confirms #3603 PR-C is merged or explicitly deferred with recorded ack | Ship-checklist |
| RK4 | OAuth IdPs that ignore `prompt=login` | AC27 (`auth_time` claim validation) is the server-side detection; E2E Playwright test enumerates Google + GitHub | AC27 + E2E test |
| RK5 | Resend preview-text rendering on some mobile clients leaks first body line | Body's first line is the same neutral text as preview; no PII in first 280 chars regardless of client | TR6 + manual visual test |
| RK6 | `archiver` upstream concurrency race on entry list | Phase 0 spike measures concurrency behaviour; serialise entry-add via queue if confirmed | Spike report |
| RK7 | Bun runtime drift (`Readable.toWeb()` adapter ties worker to Bun semantics) | Spike report records the runtime invariant; `bunfig.toml` engine pin in same PR per S8 | Spike report + ADR |
| RK8 | Future migration adds a `user_id`-FK table that's silently absent from exports | AC28 / `dsar-allowlist-completeness.test.ts` CI gate | AC28 |
| RK9 | Future refactor drops `.eq('owner_id', ...)` from a worker query | AC30 / `dsar-worker-per-row-where.test.ts` file-parse lint + AC12 `assertReadScope` runtime invariant | AC12 + AC30 |
| RK10 | Account deletion mid-export triggers cross-tenant P0 against tombstone | AC25 cascade aborts in-flight jobs FIRST | AC25 |
| RK11 | Storage objects leak in `dsar-exports/` bucket (TTL-expired, never downloaded) | AC24 / TR14 hourly sweep flips `expired` + Node poller deletes | AC24 |

## Rollback Plan

Feature-add, not refactor. Rollback options:

1. **Code rollback (within 24h of merge):** `git revert <merge-sha>` drops new routes, components, server modules. Migrations 041 + 042 remain (additive, no interaction with existing code paths). New pg_cron schedules can be dropped via `select cron.unschedule('dsar-export-pii-retention-sweep'); select cron.unschedule('dsar-export-bundle-ttl-sweep');`.
2. **Migration rollback (worst case):** `DROP TABLE public.dsar_export_audit_pii CASCADE; DROP TABLE public.dsar_export_jobs CASCADE; DROP FUNCTION ... CASCADE;` — destructive; only if no real user has used the endpoint.
3. **Storage bucket cleanup:** `delete from storage.buckets where id = 'dsar-exports';` after objects purged.
4. **Legal-doc rollback:** revert via the same `git revert`. The `legal@jikigai.com` channel is unchanged.
5. **Deployment-time monitoring:** first 7 days, alert via `mirrorCrossTenantViolation` (P0) and `mirrorWithDebounce(*, "dsar-export-failed")` (P1) keys to Sentry. On either alert, immediately disable the endpoint via `process.env.DSAR_EXPORT_ENABLED ?? "true"` flipped to `"false"` returns 503.

## Implementation Phases

Phases ordered by dependency direction (per Kieran's P0 fix). Tests land WITH the module they cover, not at the end.

| # | Phase | Files / actions | Gates |
|---|---|---|---|
| 0 | **Spike: streaming-archive primitive** | `apps/web-platform/scripts/spike-dsar-streaming-upload.ts` + `apps/web-platform/scripts/spike-dsar-streaming-upload-report.md` | Phase-exit gate (S7-demoted AC9): report exists; cap declared. |
| 1 | Migrations + ADR | `041_dsar_export_jobs.sql` + `042_dsar_exports_storage_bucket.sql` + `knowledge-base/engineering/architecture/decisions/0NN-dsar-export-substrate-and-audit-retention.md` | AC7 + AC13 + AC14 + AC29; `migration-rpc-grants.test.ts` passes; `dsar-worm-guc-sites.test.ts` passes |
| 2 | Cross-tenant + audit primitives | Add `mirrorCrossTenantViolation` to `apps/web-platform/server/observability.ts` (does not modify existing exports per C3); add `dsar-export.ts` skeleton with `assertReadScope` + `CrossTenantViolation` type | AC12 + AC22 |
| 3 | Reauth helpers | `apps/web-platform/server/dsar-reauth.ts` + extend `apps/web-platform/test/auth-gate.test.ts` (TR11 + AC21) + reauth tests inside `dsar-reauth.test.ts` | AC3 + AC21 + AC27 |
| 4 | Email | Extend `apps/web-platform/server/notifications.ts` with `sendDsarExportReadyEmail` + `sendDsarExportFailedEmail` (per C2 fold) | TR6 |
| 5 | Orchestrator + worker | Complete `apps/web-platform/server/dsar-export.ts` (`enqueueExport`, `runExport`, `startDsarExportReaper` with on-startup orphan-reset per S3); allowlist enumerator; archiver pipe; manifest writer; tests in `dsar-export.test.ts` (incl. silent-rls per C2 fold + per-file error policy per AC26) + allowlist-completeness test (`dsar-allowlist-completeness.test.ts`) + per-row WHERE lint (`dsar-worker-per-row-where.test.ts`) | AC15 + AC17 + AC18 + AC23 + AC26 + AC28 + AC30; TR12 (replaced by S3) verified |
| 6 | API routes (depends on Phases 3+5) | `apps/web-platform/app/api/account/export/route.ts` + `[jobId]/route.ts` (status + reissue) + `[jobId]/download/route.ts`; tests in `dsar-export-route.test.ts` (incl. AC24 410 + AC31 concurrent-click) | AC4 + AC5 + AC16 + AC19 + AC20 + AC24 + AC31 |
| 7 | Reauth route | `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/reauth/route.ts` | AC3 + AC27 |
| 8 | UI | `apps/web-platform/app/(dashboard)/dashboard/settings/privacy/page.tsx` + `apps/web-platform/components/settings/dsar-export-dialog.tsx` (single dialog with `<details>` per S9) + `apps/web-platform/components/settings/dsar-export-job-list.tsx` (`expired` rendering + active-job button-disable); edits to settings root | FR1 + FR6; Playwright E2E |
| 9 | Account-delete cascade extension | Edit `apps/web-platform/server/account-delete.ts` (insert abort-dsar-jobs + anonymise step BEFORE `auth.admin.deleteUser()`; **update the `:115-117` invariant comment** in the same edit); extend `apps/web-platform/test/account-delete.test.ts` cascade-order test | AC7 + AC25 |
| 10 | Cross-tenant integration test | `apps/web-platform/test/dsar-export-cross-tenant.integration.test.ts` (synthesised users + service-role re-check + content-level scan) | AC6 + AC15 |
| 11 | Legal docs | Edit Privacy Policy §4.7/§8.1, GDPR Policy §6.1.b/§5.3, DPD §2.3/§5.3/§10, `compliance-posture.md`; create `.github/workflows/legal-doc-cross-document-gate.yml`; invoke `legal-compliance-auditor` agent; resolve any ripple contradictions | AC8 + FR8; cross-document gate green |
| 12 | Operator runbooks | `knowledge-base/engineering/ops/runbooks/dsar-export-oversize.md` + `dsar-export-failed-job.md` + `apps/web-platform/scripts/dsar-export-oversize.sh` | Q4 + RK1 |
| 13 | Pre-merge verification | Run preflight Check 6; confirm migrations applied to dev FIRST; `gh pr ready 3634` | All ACs + AC-PM-1/2/3 |

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-dsar-art15-export-endpoint-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-dsar-art15-export-endpoint/spec.md`
- Parent finding (D-DSAR-art15): `knowledge-base/project/plans/2026-05-11-feat-cc-soleur-go-transcript-hardening-pra-plan.md:200`
- Adjacent Art. 17 code: `apps/web-platform/server/account-delete.ts` (esp. `:115-117` invariant comment to update per AC25)
- WORM-audit reference (canonical): `apps/web-platform/supabase/migrations/037_audit_byok_use.sql`
- Existing signed-URL precedent: `apps/web-platform/app/api/attachments/url/route.ts:31` (1h TTL — relaxed to 7d under DEC6 with compensating defences per AC19)
- Stuck-job reaper pattern: `apps/web-platform/server/agent-runner.ts:698-714`
- Rate-limiter single-instance caveat: `apps/web-platform/server/rate-limiter.ts:255-262`
- Sentry mirror-with-debounce primitive (NOT widened per C3): `apps/web-platform/server/observability.ts:183-208`
- Storage path-prefix RLS pattern: `apps/web-platform/supabase/migrations/019_chat_attachments.sql:14`
- Resend transactional surface: `apps/web-platform/server/notifications.ts:9-58`, `:183-209`
- DPD-rights plan precedent: `knowledge-base/project/plans/2026-03-20-legal-dpd-web-platform-data-subject-rights-plan.md`
- Constitution principles applied: `cq-pg-security-definer-search-path-pin-pg-temp`; `cq-test-fixtures-synthesized-only`; `cq-abort-signal-timeout-vs-fake-timers`; line 88 (RLS restrictive policies for auth-relevant columns); line 227 ("design for v2, implement for v1")
- AGENTS.md hard rules applied: `hr-weigh-every-decision-against-target-user-impact`, `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-dev-prd-distinct-supabase-projects`, `hr-menu-option-ack-not-prod-write-auth`
- Acknowledged code-review issue (NOT folded — per C3): #3638
- Draft PR: #3634
- Tracking issue: #3637
