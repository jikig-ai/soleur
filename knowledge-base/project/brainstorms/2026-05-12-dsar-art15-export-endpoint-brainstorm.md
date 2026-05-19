---
title: DSAR Art. 15 Export Endpoint — Brainstorm
date: 2026-05-12
status: brainstorm-complete
brand_survival_threshold: single-user incident
gdpr_gate_required: true
sub_gates_fired: [Art-15, Art-20, Art-5-1-c, Art-5-2, Art-6, Art-12-3, Art-32, Art-33-34]
parent_finding: D-DSAR-art15 (plan rev-3, 2026-05-11)
parent_session_state: knowledge-base/project/specs/feat-cc-assistant-turn-persistence-3258/session-state.md
not_part_of: "#3603 umbrella — broader compliance workstream"
draft_pr: "#3634"
branch: feat-dsar-art15-export-endpoint
---

# DSAR Art. 15 Export Endpoint — Brainstorm

## What We're Building

A self-serve, user-initiated, async **GDPR Article 15 (right of access) + Article 20 (right of portability) data export endpoint** in the web-platform. Today the §8.1 Privacy Policy and §6.1.b GDPR Policy promises are fulfilled by manual operator action (DB dump via support ticket). This brainstorm replaces the manual flow with a code path that (a) returns a complete, machine-readable ZIP of every personal-data category the user holds with us, (b) provides cross-tenant safety by construction (not by audit), and (c) leaves an evidentiary trail satisfying Art. 5(2) accountability.

**Surface shape:**

```
/settings/privacy → [Download my data]
   ↓
/settings/privacy/reauth   (step-up: password / OAuth max_age=300 / MFA)
   ↓  ok within last 5 min
POST /api/account/export
   • supabase.auth.getUser() + per-user rate limit 1/24h via dsar_export_jobs
     partial-unique index (idempotent within window)
   • insert dsar_export_jobs row, status='pending', bind owner_session_id
   • return 202 + job_id + acknowledged_at (Art. 12(3) clock-starter)
   ↓
Background worker  (substrate TBD — see Open Q1)
   • SELECT user's JWT-scoped data from every table that cascade-FKs from
     auth.users; column enumeration via information_schema (PR-A2-proof)
   • Stream via `archiver` (Node ZIP) → Supabase Storage resumable upload
     to dsar-exports/<userId>/<jobId>.zip
   • Path-prefix RLS: `auth.uid()::text = (storage.foldername(name))[1]`
   • Email user via Resend with /api/account/export/:id/download link
   ↓
GET /api/account/export/:id/download
   • session cookie matches dsar_export_jobs.owner_session_id
   • source IP /24 matches issuance (CGNAT/IPv6 fallback: see Open Q5)
   • single-use: first successful download flips downloaded_at + invalidates
   • on success: hard-delete Storage object, mark dsar_export_jobs.deleted_at
```

**Bundle contents (`manifest.json` + JSON-per-table + markdown originals + binaries in original mime, ZIP-wrapped):**

```
export-<userId>-<jobId>.zip
├── manifest.json           ← Art. 15(1)(a-h) metadata + schema snapshot
│                              + per-file {article: "15" | "15+20"} tag
│                              + SHA-256 per file + source table + row count
├── account/
│   ├── users.json          ← 15+20: email, OAuth provider IDs, display name
│   └── api_keys.json       ← 15+20: BYOK fingerprints + scope ONLY (no plaintext)
├── workspace/
│   └── <files>             ← 15+20: per-user filesystem (markdown originals)
├── conversations/
│   ├── conversations.json  ← 15+20: metadata (domain leader, status, ts, cost)
│   └── messages.json       ← split by Art tag (user=15+20, assistant=15-only)
│                              includes messages.status + messages.usage
│                              (auto-included via information_schema)
├── attachments/
│   ├── attachments.json    ← 15+20: message_attachments rows
│   └── files/              ← original binaries by storage_path
├── share-links.json        ← 15+20: §4.8 records
├── push-subscriptions.json ← 15-only: §4.9 records
├── subscription.json       ← 15-only: Stripe IDs + plan (no card data — Stripe is controller)
└── audit/
    └── prior-exports.json  ← 15-only: user's own past DSAR-export audit rows
                              (recursive transparency)
```

## Why This Approach

**Async, not sync.** Largest plausible account: ~500 conversations × ~200 messages × ~5k attachments avg 500KB ≈ 2.5GB blob + 100k DB rows + workspace directory hundreds-of-MB. Vercel function default 10s, max 300s (Pro). Cloudflare idle-timeout. Sync streaming JSONL inline times out at p95 and leaves the user with a corrupt partial download with no resume primitive. Async (`POST` returns `202` + job_id; user polls or receives email) is the only shape that survives both the timeout reality and Art. 12(3) "without undue delay."

**Column-introspection-driven, not hand-curated.** The export query enumerates columns via `information_schema.columns` at run-time per table, then `SELECT *`. When PR-A2 lands and `CC_PERSIST_USAGE` flips, `messages.usage` automatically appears in subsequent exports — no code change. This (a) decouples this work from the PR-A2 deployment sequencing entirely (chosen Q1 = CTO synthesis), (b) eliminates the entire bug class of "forgot to add column X to export = silent Art. 15 incompleteness," and (c) makes the manifest itself a compliance artifact ("schema-snapshot at date X").

**RLS-via-user-JWT for queries; service-role only for Storage path enumeration.** The biggest brand-survival risk is a cross-tenant leak: user A's data exfiltrated in user B's ZIP. The Supabase JWT-scoped client makes that impossible by construction — Postgres planner physically cannot return another user's rows because RLS filters before the query reaches userspace. Service-role + hand-written `WHERE user_id = $1` is one typo from a notifiable breach. Service-role is only used in one place: Storage object enumeration for `chat-attachments/<userId>/...`, where the `<userId>/` path-prefix is the isolation guarantee (mirrors the existing `account-delete.ts:94-108` pattern). That prefix is load-bearing — every construction site of it is a P0 review block.

**Step-up reauth (chosen Q3).** EDPB Guidelines 01/2022 §3: high-risk surfaces require reauthentication baseline. A stolen session today reads the user's data piecemeal via the app UI; but the export endpoint creates a single artifact containing *all of it*, bypassing the rate-limit-by-UI-step that piecemeal exfiltration would hit. Step-up closes the stolen-session attack. Friction is one extra click — acceptable for an endpoint exercised maybe once a year per user.

**7d signed URL, session+IP-bound, single-use, hard-delete on download (chosen Q2).** Pure-bearer signed URLs are an asymmetric leakage risk if email is forwarded/intercepted. Coupling the URL to an authenticated session + source IP /24 + single-use makes interception non-fatal. 7d window respects timezone/weekend reality (rejected 1h-precedent because Friday-evening-request-Monday-check is plausible and friction-of-re-request is high). Hard-delete on first download satisfies Art. 5(1)(c) minimization.

**Audit log internal-only, mirrors `audit_byok_use`.** Reuses the existing canonical WORM pattern (migration 037): owner-SELECT denied at table level, append-only via trigger, `SECURITY DEFINER` + `search_path = public, pg_temp`, service-role-only writes via RPC. 24-month retention per CLO (CNIL guidance) with scheduled hard-delete. DEC10 of the parent #3603 brainstorm pre-decided "DSAR audit log is internal-only with supplementary disclosure only on confirmed Art. 15 export in affected cohort." User can see *their own* prior exports as a list (status, timestamps) via a separate `dsar_export_jobs` RLS-scoped read — the forensic columns (IP, UA, session_id) live in a sibling `dsar_export_audit_pii` table that the user role cannot read.

**Same-PR Privacy Policy + GDPR Policy + DPD + compliance-posture amendments (cross-document consistency gate).** CLO surfaced two enumeration gaps in §4.7: `message_attachments` and KB workspace files are not listed even though they're in scope for export. A PR that ships the code without closing these is itself an Art. 13/14 violation. The plan-skill MUST emit acceptance criteria covering all four artifacts (privacy-policy.md, gdpr-policy.md, data-protection-disclosure.md, knowledge-base/legal/compliance-posture.md).

## Key Decisions

| # | Decision | Why | Source |
|---|----------|-----|--------|
| DEC1 | Async job, not sync streaming | Sync times out at p95 account size; ZIP corruption with no resume primitive | CTO + CPO |
| DEC2 | One endpoint serves both Art. 15 and Art. 20; manifest tags each file with `{article: "15"\|"15+20"}` | Art. 20 scope strictly narrower (subject-provided, automated, 6(1)(a/b) only); EDPB WP242 endorses single bundle with metadata | CLO |
| DEC3 | Column-introspection-driven (`information_schema` enumeration + `SELECT *`) | Dissolves PR-A2 sequencing dependency; eliminates "forgot the new column" bug class; manifest doubles as schema-snapshot compliance artifact | CTO; user Q1 |
| DEC4 | RLS-via-user-JWT for queries; service-role only for Storage path enumeration | Cross-tenant leak is impossible by construction, not by audit; matches existing IDOR-defense pattern | CTO + learnings security-issues/2026-04-11 |
| DEC5 | Format: ZIP wrapping `manifest.json` + JSON per relational table + markdown originals + binaries in original mime | Art. 20 "structured, commonly used, machine-readable" satisfied by JSON; markdown preserves user-authored originals for genuine portability; binaries in original mime serve byte-for-byte fidelity | CLO + EDPB WP242 |
| DEC6 | Signed URL: 7d, session+IP/24-bound, single-use, hard-delete on first download. Storage object lives 7d max (or until first download). | Brand-survival defense-in-depth; 1h is friction-heavy without proportional risk reduction once URL is non-bearer | User Q2 (CLO recommendation) |
| DEC7 | Step-up reauth required within 5 min before enqueue; binds export job to reauth session_id; session revoke invalidates URL | EDPB Guidelines 01/2022 §3 high-risk surface; closes stolen-session attack; one-click friction acceptable for annual-use endpoint | User Q3 (CLO recommendation) |
| DEC8 | Audit log internal-only; separate schema; RLS-denied to app role; append-only WORM trigger; 24-month retention | DEC10 from parent #3603 brainstorm + CLO retention recommendation; reuses `audit_byok_use` (migration 037) canonical WORM pattern | CLO + brainstorm 2026-05-11-cc-soleur-go-transcript-hardening:54 |
| DEC9 | Rate-limit: 1 export per user per 24h, idempotent within window via partial unique index | Bounds attack throughput + storage/cost amplification; matches in-spirit account-delete's `1 req / 60s` strict gate but adapted to read-class endpoint | CTO + learnings 2026-04-02 plan:328 |
| DEC10 | v1 scope INCLUDES KB workspace files + `chat-attachments/<userId>/...` Storage blobs; EXCLUDES BYOK plaintext (fingerprints only) | Omitting personal-data categories from Art. 15 is non-compliant (not "minimal"). BYOK plaintext is Art. 5(1)(f) excluded; document exclusion in manifest. | CPO + CLO consensus |
| DEC11 | Privacy Policy §4.7 + GDPR Policy §6.1.b + DPD §2.3 + compliance-posture.md amendments in SAME PR as code | Privacy-policy gap (message_attachments, KB-workspace) makes the code PR itself non-compliant if shipped without the amendment | CLO cross-document consistency gate |
| DEC12 | Reuse `assertWriteScope` from PR-A1 as `assertReadScope` with P0 Sentry mirror (dedup key: `(offendingUserId, targetUserId)`); two-user-two-conversation synthesized fixture per `cq-test-fixtures-synthesized-only` is CI gate | Pattern proven in PR-A1; same threat model; lift not copy | Learnings + plan rev-3:43 |
| DEC13 | No MCP/agent-native surface for *initiating* an export in v1 — only read-only `dsar_export_status` for listing/polling | Agent-native principle has a brand-survival carve-out: regulatory rights exercise must be user-initiated for forensic auditability + misuse-surface bound | CPO §5 |
| DEC14 | 5-agent plan-review panel at plan time (DHH + Kieran + Code-Simplicity + Architecture-Strategist + SpecFlow re-validation) | Required under `brand_survival_threshold: single-user incident` per learnings 2026-05-11-five-agent-plan-review-panel | Learnings precedent |
| DEC15 | Reject Edge Functions as runtime; Next.js API route + service-role pattern used elsewhere is sufficient | Explicit house decision Phase 2 plan §489 | Learnings 2026-04-02 plan:489 |

## User-Brand Impact

**Brand-survival threshold:** single-user incident.

**Failure-mode artifact (named):** `dsar-exports/<userId>/<jobId>.zip` — a single bundled file containing the entirety of one user's personal data with Soleur.

**Failure vector (primary):** Cross-tenant exfiltration via any of:
- (a) a `WHERE user_id = $1` clause missing on a JOIN, returning rows of users other than the requester
- (b) a Storage signed URL constructed with a `userId` variable shadowed/staled to a different user (the `${userId}/` path-prefix is the isolation guarantee — any non-`auth.uid()` source for it is a P0 review block)
- (c) a worker that processes job N while reading the JWT or `auth.uid()` for job N+1 due to async-context bleed
- (d) silent RLS failure returning `{}` instead of erroring — operator and user both see "successful empty export" while the actual data is suppressed (learnings/2026-04-12-silent-rls-failures-in-team-names.md)

**Failure mode (secondary):** Signed URL leakage via email forwarding/interception — mitigated by session+IP-binding + single-use + hard-delete-on-download (DEC6) but not eliminated. Defense-in-depth needed.

**Failure mode (tertiary):** Audit log of exports leaked, revealing third-party-mentioned content via signed-URL filename or content hashes — mitigated by separating PII columns (IP, UA, session_id) into `dsar_export_audit_pii` table, RLS-denied to app role (DEC8).

**Regulator-shaped event:** Art. 33 notification to the lead supervisory authority (CNIL, given the French/EU establishment per DPD §6.3) within 72h of awareness; Art. 34 notification to affected data subjects "without undue delay" if the breach is "likely to result in a high risk to the rights and freedoms" — the threshold is met if exfiltrated data includes the conversation transcripts (which contain whatever personal information the user discussed with their domain leaders).

**Brand cost (irreversible):** the only event class worse than this for a privacy-positioned product is plaintext-credential leakage. A regulator-notified breach in the *very surface designed to fulfill a data subject right* is reputational damage that does not recover.

## Domain Assessments

**Assessed:** Engineering, Legal, Product. (Marketing, Operations, Sales, Finance, Support — not relevant at brainstorm phase; Support will gain a runbook for the email-fallback case during plan.)

### Engineering (CTO)

**Summary:** Async via existing in-monorepo substrate (NOT Edge Functions — house-rejected per learnings 2026-04-02 plan:489). Column-introspection-driven export decouples from PR-A2. RLS-via-user-JWT for cross-tenant safety; service-role only for Storage path enumeration with `<userId>/` prefix guard. Streaming `archiver` → resumable Supabase Storage upload is a *spike-before-spec* requirement (Node memory cap 3008MB on Vercel; 2.5GB in-memory ZIP buffer = OOM). v1 size cap 1GB with explicit user-facing fallback for larger accounts.

### Legal (CLO)

**Summary:** Single endpoint, two articles, per-file article tags in manifest. 8 explicit acceptance criteria (AC-1 through AC-8) covering category reconciliation, manifest format, step-up auth, SLA (acknowledged ≤5 business days, p95 ≤48h, hard ≤7d), signed-URL TTL+binding+single-use, per-row user_id assertion + RLS + cross-tenant golden fixture, audit log retention/access, cross-document consistency gate. GDPR-gate fires Art-15, Art-20, Art-5-1-c, Art-5-2, Art-6, Art-12-3, Art-32, Art-33-34. Two privacy-policy enumeration gaps surfaced (must be closed same-PR): `message_attachments` and KB workspace files.

### Product (CPO)

**Summary:** Settings-page button alongside "Delete my account" (carries discovery surface for free). Two-stage UX: click → "what's included" preview card → "we'll email you when ready." In-app job tracker for status visibility. Don't email the ZIP itself, email the link. Bundle MUST include KB workspace + Storage attachments — omitting is non-compliant, not minimal. Manifest file inside ZIP is the highest-leverage trust artifact (sophisticated users + regulators open it first). Do NOT expose as agent-native MCP tool for *initiation* in v1; read-only status MCP tool is fine.

## Open Questions

1. **Async substrate choice.** Three live candidates given no Vercel cron and no Edge Functions are currently wired:
   - **(a) `pg_cron` + `pg_net`** — cron job inside Postgres pings an internal Next.js endpoint to claim and process the next pending job. Existing extension (`029_plan_tier_and_concurrency_slots.sql`). Lowest new ops surface.
   - **(b) In-process `setInterval` reaper** in the Next.js server — matches existing pattern in `apps/web-platform/server/agent-runner.ts:522` (stuck-conversation sweep). Risk: only one Node instance can run it; "process-local — when infra scales to >1 Node instance, all consumers must migrate" comment from rate-limiter.ts:16 applies double here.
   - **(c) New Vercel cron** — bolts on a new ops surface but is the Vercel-native answer. Configurable per `vercel.json`.
   - Defer this to plan-time decision; CTO leans (a). Spike all three before committing.

2. **Streaming-upload spike.** The recommendation hinges on `archiver` (or `yazl`) streaming through Supabase Storage's resumable upload (`tus-js-client` or native). This MUST be proven in a spike before the spec encodes the size cap. If streaming fails (Supabase's resumable upload has known issues with chunked transfer from Node serverless), v1 falls back to in-memory ZIP with explicit ~500MB cap and operator-handoff for larger accounts.

3. **Email delivery surface.** Resend is the existing transactional-email vendor (DPD §2.3(k)). The export-ready email template needs (a) reauth-required language so user knows the link requires re-login if session expired, (b) clear "expires in 7d" copy, (c) no PII in subject or preview text (rendered in mail-client preview without authentication), (d) plain `<a>` link not auto-tracked.

4. **v1 size cap.** CTO suggests 1GB. CPO didn't weigh in. Pragma: ship 1GB cap with `if total_size > limit → mark job failed with "contact support" reason → operator falls back to manual today's-process (which still works for Art. 15 — endpoint is automation, not the sole compliance path)`. The audit log captures this case for visibility.

5. **CGNAT / IPv6 prefix rotation breaking IP/24 binding.** Some mobile networks rotate the public IP /24 mid-session, and IPv6 customers may have provider-rotated /64 prefixes. Hardening: if IP-bind check fails, fall back to "re-request a fresh signed URL from `/settings/privacy`" path which re-binds. The Storage object survives until consumed or T+7d. Acknowledge IPv6-bind is /48 (subnet) not /24.

6. **`account-delete.test.ts` does not exist.** The analogue endpoint we are mirroring (Art. 17 deletion) has no test coverage in `apps/web-platform/test/`. Should the DSAR-export PR also add account-delete tests as part of the cross-tenant invariant test family? File as decision-required during plan-time.

7. **Compliance-cohort retroactive disclosure interplay.** Spec §FR10 / AC10 of #3603's spec describes a DSAR audit of the 2026-05-05→AC11 window. If a user in that cohort exercises the NEW endpoint *before* the supplementary disclosure is sent, what does the supplementary disclosure contain that the export doesn't? Coordinate with PR-C of #3603.

8. **Disabled-account / locked-out user fallback.** A user locked out of their account (forgotten password + locked OAuth) cannot exercise this endpoint. The pre-existing manual `legal@jikigai.com` channel must be retained as a documented fallback in the same Privacy Policy §8.1 update (do not remove the email channel — *add* the self-serve path).

## Capability Gaps

- **No streaming-upload primitive validated for Supabase Storage from Vercel serverless.** Evidence: `apps/web-platform/app/api/attachments/presign/route.ts:96` is the only upload site and uses signed-upload-URL pattern (client-side direct upload), not server-side streaming. The export path requires server-side streaming because the client never holds the bytes. This is a spike-before-spec dependency (Open Q2).
- **No long-running async-export queue pattern exists in repo.** Evidence: repo-research grep confirmed no `jobs` table, no Edge Functions directory, no Vercel cron config. Three candidate substrates evaluated (Open Q1) but none yet validated in production for jobs that run on the order of minutes-to-an-hour. Spike candidates: `pg_cron + pg_net`, `setInterval`-reaper, new Vercel cron.
- **No prior decision on signed-URL TTL.** Evidence: learnings searched `security-issues/2026-04-11-service-role-idor-untrusted-ws-attachments.md` and adjacent files — only the 1h precedent in `attachments/url/route.ts:31` exists. This brainstorm establishes the 7d-session-IP-bound precedent (DEC6).
- **No prior decision on step-up auth for sensitive READ endpoints.** Evidence: house style for sensitive WRITES is session-only + rate-limit (account-delete). This brainstorm establishes step-up-reauth as the precedent for sensitive READS (DEC7).
- **No `account-delete.test.ts`** — the Art. 17 analogue has no test coverage at all in `apps/web-platform/test/`. Evidence: repo-research grep returned 0 hits. Decision-required during plan (Open Q6) whether to retrofit account-delete tests as part of this PR's cross-tenant test family.

## Compliance Acceptance Criteria (from CLO assessment, MUST encode in spec)

- **AC-1** Export bundle reconciles 1:1 with Privacy Policy §4.7 + §4.8 + §4.9 enumerated categories; CI test asserts every category present or explicitly marked N/A with reason.
- **AC-2** Bundle contains `manifest.json` tagging each file `{article: "15"|"15+20"}` + SHA-256 + source table + row count; format = ZIP of JSON + markdown + original-mime binaries.
- **AC-3** Step-up reauth within 5 min required before enqueue; OAuth accounts use `max_age=300`; session-bound to the auth event.
- **AC-4** Controller acknowledgement returned synchronously (≤500ms) with `acknowledged_at`; async job p95 ≤48h, hard ceiling ≤7d; Art. 12(3) extension flow exists with email notification within 30d.
- **AC-5** Signed URL TTL = 7d; bound to authenticated session + source IP /24 (IPv6: /48); single-use; storage object hard-deleted at TTL or first successful download (whichever first).
- **AC-6** Per-row `user_id` assertion in serializer + RLS on every query in the export pipeline + cross-tenant golden-fixture test in CI (two synthesized users, zero cross-bytes).
- **AC-7** Audit log: separate schema, RLS-denied to app role, append-only via trigger, PII-minimal payload, 24-month hard-delete schedule; self-export includes own prior audit rows (recursive transparency).
- **AC-8** Privacy Policy §4.7/§8.1, GDPR Policy §6.1.b, DPD §2.3 register, and `compliance-posture.md` updated in the **same PR** as the code (cross-document consistency gate — no merge if one of the four is missing).

## Out of Scope (v1)

- Programmatic API for repeated exports (defer to v2; Art. 15 right is not subscription-of-changes).
- Incremental "since date X" exports (defer to v2).
- Redaction tooling for third-party-mentioned content (CLO assessment §3: do not redact; mutilates the record).
- Agent-native MCP tool for **initiating** an export (DEC13). Read-only `dsar_export_status` MCP tool *is* in scope.
- In-browser preview of export contents (scope creep, attacker-controlled-markdown risk).
- Sentry breadcrumbs and Cloudflare-processor logs as exportable content (mention existence in manifest; defer surface to v2 per CLO §2 table).

## Reference Links

- Parent finding: `knowledge-base/project/plans/2026-05-11-feat-cc-soleur-go-transcript-hardening-pra-plan.md:200` (D-DSAR-art15 deferred-item)
- Phase 0.5 finding source: `knowledge-base/project/specs/feat-cc-assistant-turn-persistence-3258/session-state.md:38-44`
- Adjacent code (Art. 17 analogue): `apps/web-platform/server/account-delete.ts`
- Audit-table WORM pattern to reuse: `apps/web-platform/supabase/migrations/037_audit_byok_use.sql`
- Existing signed-URL precedent: `apps/web-platform/app/api/attachments/url/route.ts:31`
- Existing rate-limiter substrate: `apps/web-platform/server/rate-limiter.ts:44`
- Cross-tenant test pattern (lift): `apps/web-platform/server/cc-dispatcher.ts:43` (`assertWriteScope`)
- Privacy Policy: `docs/legal/privacy-policy.md` §4.7, §4.8, §4.9, §8.1
- GDPR Policy: `docs/legal/gdpr-policy.md` §6.1.b (lines 183-189)
- DPD: `docs/legal/data-protection-disclosure.md` §2.3, §5.3
- DPD plan precedent: `knowledge-base/project/plans/2026-03-20-legal-dpd-web-platform-data-subject-rights-plan.md`
- Draft PR: #3634
