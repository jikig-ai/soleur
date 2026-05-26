---
title: "ADR-028 — DSAR export substrate, audit retention, worker credential, and runtime"
status: accepted
date: 2026-05-12
plan: knowledge-base/project/plans/2026-05-12-feat-dsar-art15-export-endpoint-plan.md
spec: knowledge-base/project/specs/feat-dsar-art15-export-endpoint/spec.md
issue: 3637
supersedes: none
related: [ADR-023-supabase-environment-isolation, ADR-021-kb-binary-serving-pattern]
---

# ADR-028 — DSAR export substrate, audit retention, worker credential, runtime

## Context

Plan rev-2 for `feat-dsar-art15-export-endpoint` (issue #3637) ships the
GDPR Art. 15 + Art. 20 self-serve export pipeline. Four architectural
questions surfaced during brainstorm / spec / plan-review and must be
decided before the Phase 1 migration lands.

Brand-survival threshold is `single-user incident` (CNIL Art. 33 within
72 h + Art. 34 to data subject). Failure-mode artifact:
`dsar-exports/<userId>/<jobId>.zip` — the entirety of one user's
personal-data footprint. An A → B leak is the worst event class short of
plaintext-credential leakage.

## Decisions

### D1 — Async-job substrate (plan Q1)

**Decision**: in-process `setInterval` reaper inside the Next.js server
process, mirroring `agent-runner.ts:698-714` (`startStuckActiveReaper`).

**Alternatives considered**:
- (a) `pg_cron` + `pg_net` — rejected because `pg_net` is not installed on
  either dev or prd Supabase project (R5 of plan); installing it adds a
  new extension surface for a single use case.
- (b) **In-process setInterval reaper** — chosen. Re-uses the
  single-instance assumption already shared with the rate-limiter
  singleton and stuck-conversation reaper. All three migrate together
  when infrastructure scales beyond one instance (caveat documented at
  `rate-limiter.ts:252-262`).
- (c) Vercel cron / Next.js route-handler `maxDuration` — rejected; prd
  is Hetzner (no `vercel.json` exists per R6); spec's `maxDuration: 300`
  is moot.

**Implications**: per-job hard timeout managed via
`AbortController + setTimeout(controller.abort, JOB_HARD_TIMEOUT_MS)` per
`cq-abort-signal-timeout-vs-fake-timers`. Orphan-on-restart recovery: the
poller's init phase runs
`UPDATE dsar_export_jobs SET status='pending', started_at=NULL WHERE status='running'`
ONCE before the first tick (plan S3 — replaces the originally planned
pg_cron stuck-job sweep).

### D2 — Audit retention vs. Art. 17 erasure (plan Q-extra)

**Decision**: keep audit-PII rows for 24 months (Art. 5(1)(c)
proportionality + Art. 5(2) accountability); on user deletion, **anonymise
the PII columns of `dsar_export_audit_pii`** via a SECURITY DEFINER RPC
called from `account-delete.ts` BEFORE `auth.admin.deleteUser()`. The
audit row itself remains for the 24-month retention window so the
controller can prove fulfilment of past DSARs without retaining
identifying data.

**Constraint that forced this design**: migration 037's reuse pattern
(`founder_id REFERENCES public.users(id) ON DELETE RESTRICT`) blocks
`auth.admin.deleteUser()` while audit rows exist. We therefore use
`ON DELETE NO ACTION` on `dsar_export_audit_pii.user_id` and run an
explicit anonymisation step ordered before `auth.admin.deleteUser()` in
the cascade.

**Cascade order** (account-delete.ts, per AC25):
`abort-dsar-jobs → abort sessions → workspace → storage-purge →
anonymise-dsar-audit → auth`. The `anonymise_dsar_export_audit_pii` RPC
is idempotent (re-runs are safe), so the failure-mode where anonymise
succeeds and `auth.admin.deleteUser()` fails is recoverable: the row
shows `(anonymised, null, null, …)` and the next retry of account
deletion re-runs anonymise as a no-op then re-attempts auth-delete.

### D3 — Worker authentication credential (plan Q-credential, rev-2 C1)

**Decision**: the DSAR worker uses the **`service_role`** Supabase
client + a mandatory per-row `WHERE owner_id = $jobs.user_id` predicate
on every table read + `assertReadScope(rows, expectedUserId, table_name)`
runtime invariant on every result set.

**Alternatives considered (rev-1 design rejected at AC11 panel review)**:
- (a) **`owner_jwt_encrypted bytea` column** — store the requester's JWT
  encrypted-at-rest at enqueue, decrypt at run. **Rejected**: creates a
  new credential vault — reversible session credentials with hours-long
  dwell time; key compromise yields mass impersonation; reuses the
  BYOK-domain HKDF helper which breaks domain separation. This was the
  largest unflagged risk per architecture-strategist + DHH + Kieran in
  the panel review (recorded as plan rev-2 C1).
- (b) Per-user JWT-mint-at-runtime — rejected. Requires Supabase admin
  API capability for impersonation-as-user that is not demonstrated for
  the available primitives (which mint magic-links, not session JWTs).
- (c) **`service_role` + per-row `WHERE` + `assertReadScope`** — chosen.
  Two-layer defense: per-row `WHERE owner_id = $1` is the planner-level
  isolation (enforced by file-parse lint `dsar-worker-per-row-where.test.ts`
  per AC30); `assertReadScope` is the runtime invariant that raises
  `CrossTenantViolation` if any returned row's `owner_id` ≠ expected.
  Mirrors via new sibling `mirrorCrossTenantViolation` on
  `observability.ts` (does NOT widen the existing `mirrorWithDebounce`
  signature — plan C3 unfold of #3638; lands separately).

**Implications**:
- Service-role usage in DSAR worker adds new call sites to
  `.service-role-allowlist` (CI gate, PR-B); these are reviewed for
  tenant isolation impact at PR time.
- Worker never holds user credentials; impersonation surface is zero.
- The `expectedUserId` value is passed explicitly via parameter, never
  via ambient context — eliminates async-context bleed between jobs.

### D4 — Streaming-archive pattern + runtime (plan S8, Phase 0 spike outcome)

**Decision**: production worker uses **disk-then-upload via raw `fetch`
POST** with `Content-Length` + `duplex: 'half'` from
`fs.createReadStream()`, **not** `supabase-js`'s `upload(ReadableStream)`.
Runtime is **Node 22** (the production runtime for the Next.js server
process).

**Evidence** (`scripts/spike/dsar-streaming-upload-report.md`):
| Mode | Δ RSS coefficient | Notes |
|------|-------------------|-------|
| `supabase.storage.upload(WebReadableStream)` | ≈ 1.09 × payload + 12 MB | SDK buffers body before fetch |
| Raw fetch + `duplex: 'half'` from disk | ≈ 1.09 × payload + 22 MB on Node 21 | Buffering attributable to undici v5 in Node 21; **must re-validate on Node 22 prd** |

**Why disk-then-upload regardless of Node 22 outcome**: even if Node 22's
undici streams cleanly, the disk intermediate buys us:
- Per-file `O_NOFOLLOW + fstat` ino verify (AC17) during archive build,
  enforced once at write time rather than during upload.
- SHA-256 of the bundle is computed during archive write (same fd-pass
  as the bytes flowing into the writer), avoiding a second pass.
- Resumable retry on transient upload failures without re-archiving.
- Predictable peak RSS independent of upstream bandwidth fluctuations.

**TR4 v1 size cap**: 1024 MB (1 GiB), env-overrideable via
`DSAR_EXPORT_SIZE_CAP_MB`. Sized for ~40 % safety margin under the 2 GB
Hetzner allocation ceiling using the conservative measured coefficient.
Cap is **provisional** — operator must re-validate on Node 22 prd (post-
deploy task PM.4 in the plan rev-2 tasks).

**Plan rev-2 §FR4 step 6 wording** ("Stream `archiver` → Supabase Storage
`upload()` per spike outcome") is updated in-place to "Build archive to
`${WORKSPACE_BASE}/_dsar-tmp/<jobId>.zip` via `O_NOFOLLOW + fstat` ino
verify; upload via raw `fetch` POST with `Content-Length` +
`duplex: 'half'` from `fs.createReadStream()`."

### D5 — Substrate side-effects: pg_cron schedules

**Decision**: ship **two** pg_cron schedules in migration 041:
- `dsar-export-pii-retention-sweep` — daily 03:00 UTC; deletes
  `dsar_export_audit_pii` rows older than 24 months (TR13).
- `dsar-export-bundle-ttl-sweep` — hourly; updates `dsar_export_jobs`
  rows where `status='completed' AND signed_url_expires_at < now()` to
  `status='expired'` (TR14). The actual Storage object deletion is
  performed by the in-process poller observing `expired` rows (defers
  Storage I/O out of pg_cron since pg_net is not installed — plan R5).

**Plan rev-2's TR12** (pg_cron stuck-job sweep) is replaced by the
on-startup `UPDATE … SET status='pending' WHERE status='running'` in the
poller's init phase (S3 — saves a cron schedule + dev/prd verification
ceremony).

### D6 — WORM-bypass hardening (plan S1, AC29)

**Decision**: the WORM trigger on `dsar_export_audit_pii` raises P0001
on any UPDATE/DELETE EXCEPT when all three of:
1. GUC `app.dsar_audit_anonymise_in_progress` is set (any non-empty value)
2. `current_user = 'service_role'`
3. The SET-site for the GUC appears exactly **once** in the codebase, in
   the body of `anonymise_dsar_export_audit_pii` — enforced by file-parse
   test `dsar-worm-guc-sites.test.ts` (AC29 + S1).

**Function-OID allowlist note**: AC29 references a "hard-coded function
OID allowlist." In practice this is enforced via (a) the GUC + role
gates listed above (cryptographic-strength insufficient to gate alone)
PLUS (b) the file-parse lint that asserts no other code path can SET the
GUC. PostgreSQL exposes no first-class API for "calling function OID"
from a trigger; the lint is the load-bearing enforcement. The trigger's
own OID-equivalent gate is `current_user = 'service_role' AND
current_setting('app.dsar_audit_anonymise_in_progress', true) <> ''`.

## Consequences

- **Add to `.service-role-allowlist`** (PR-B CI gate) for the new call
  sites in `dsar-export.ts`. Reviewed at PR time.
- **Single-instance assumption** widened by one consumer
  (`startDsarExportReaper`). When the deployment scales beyond one
  Hetzner node, all three reapers + the rate-limiter migrate together
  to Redis-backed coordination.
- **Plan rev-2 §FR4 step 6** edited in-place (no revision bump — the
  edit is a sourcing of the Phase 0 spike outcome, anticipated by the
  task list).
- **Operator post-merge checklist** (plan §PM):
  1. Apply migrations 041 + 042 to dev first, then prd.
  2. Verify pg_cron schedules in both envs (2 rows).
  3. Confirm `dsar-exports` bucket fileSizeLimit ≥ 1024 MB on prd.
  4. Re-validate disk-mode Δ RSS coefficient on Node 22 prd; tighten
     `DSAR_EXPORT_SIZE_CAP_MB` env var if Node 22 streams cleanly.

## Status

Accepted. Lands in Phase 1 of feat-dsar-art15-export-endpoint alongside
migrations 041 + 042 per the architecture-strategist's
"ADR-precedes-consumers" guidance.
