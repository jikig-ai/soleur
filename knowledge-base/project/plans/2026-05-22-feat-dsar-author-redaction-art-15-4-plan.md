---
title: DSAR author-only message redaction (Art. 15(4))
issue: 4319
parent_issue: 4230
brainstorm: knowledge-base/project/brainstorms/2026-05-22-dsar-author-redaction-brainstorm.md
spec: knowledge-base/project/specs/feat-dsar-author-redaction-4319/spec.md
branch: feat-dsar-author-redaction-4319
worktree: .worktrees/feat-dsar-author-redaction-4319/
draft_pr: 4351
status: plan
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
requires_cpo_signoff: true
date: 2026-05-22
related_pr_merged: 4289
related_pr_merged_at: 2026-05-22T08:07:37Z
related_pr_merge_commit: 8877c198f791a27260bfb5695b513041e74f0366
deferred_followups:
  - 4358  # Art. 15 completeness — subject-authored messages in foreign-owned conversations
  - 4359  # Art. 5(2) accountability — dsar_export_audit_pii WORM extension for redaction events
---

# Plan — DSAR Author-Only Message Redaction (Art. 15(4))

## Overview

Add a per-row redaction transform to the DSAR export pipeline at
`apps/web-platform/server/dsar-export.ts` so that messages authored by a
non-subject within a subject-owned conversation are returned as structural
shells (content nulled, thread-position preserved). The same rule cascades
to `message_attachments` via an **allowlist semantic** keyed on
subject-authored message IDs (not a denylist — orphan attachments fail
closed). A new top-level `redactions: { path, reason, count }[]` field on
the bundle manifest surfaces the redaction explicitly to the subject;
schema bumps from `1.0.0` to `1.1.0` at both producer sites
(`dsar-export.ts:133` + `scripts/dsar-export-oversize.sh:130`).

Disclosure copy delta rides this PR through the legal-doc cross-document
gate: PR #4289 merged today at 08:07Z but did not add Art. 15(4) /
Recital 63 "rights of others" language to `privacy-policy.md`,
`gdpr-policy.md`, DPD §2.3, or `article-30-register.md`. Without this
delta, runtime behavior outpaces documented processing under Art. 13(2)(b).

Two adjacent gaps surfaced at plan-review and are explicitly **scope-out
with deferred follow-up issues**:
- **#4358** — Art. 15 completeness: subject-authored messages in
  foreign-owned workspace conversations are silently omitted from the
  bundle. Orthogonal to Art. 15(4) under-redaction.
- **#4359** — Art. 5(2) accountability: extend `dsar_export_audit_pii`
  WORM ledger to record per-job redaction counts past Better Stack's
  30-day pino retention.

## Research Reconciliation — Spec vs. Codebase

| # | Spec/brainstorm claim | Reality | Plan response |
|---|---|---|---|
| 1 | `messages.user_id` is the author column we filter on | `user_id` is NULLABLE (mig 046:79-101); legacy conversation-bound rows have `user_id IS NULL`. **Plan-review Kieran P0-3:** legacy-NULL writes into a foreign-owned conversation are reachable (any pre-mig-046 path, service-role insert). Treating `user_id IS NULL` as subject-owned **leaks**. | **Fail-closed default:** legacy NULL rows are REDACTED unless Phase 0.3 audit confirms `user_id IS NULL` writes are write-restricted to `auth.uid() = c.user_id` (mig 046 backfill RLS). If audit confirms safe, flip to "legacy NULL = subject-owned"; if ambiguous, ship with REDACT. AC1 fixture covers both interpretations via the Phase 0 audit outcome. |
| 2 | Redact only `content` on foreign-authored messages | `messages` also has `tool_calls` (mig 001:71), `usage` (mig 040:22-27 — embeds `completed_actions[].input_summary/result_summary`), `draft_preview` (mig 046:97), `leader_id` (mig 010:14), `action_class` (mig 051:56, **GDPR-gate Imp-6:** open namespace could leak Art. 9 status) | Redaction nulls **all personal-data + namespace-leakage columns**: `content`, `tool_calls`, `usage`, `draft_preview`, `action_class`. Preserves structural: `id`, `conversation_id`, `role`, `created_at`, `status`, `workspace_id`, `tier`, `source`, `urgency`, `trust_tier`, `cache_*_input_tokens`, `source_ref`. |
| 3 | `message_attachments.user_id != requester` triggers redaction | `message_attachments` has NO `user_id` column (mig 019:20-28). **SpecFlow #4:** denylist `parent in redactedMessageIds` fails-open on orphan attachments (parent deleted mid-export). | **Allowlist semantic** (fail-closed): build `subjectAuthoredMessageIds: Set<string>` of message IDs WHERE the message is owned-by-subject. Attachment is redacted iff `attachment.message_id ∉ subjectAuthoredMessageIds`. Orphan attachments (parent not in fetch) → redacted by default. |
| 4 | Two joinVia tables: `messages`, `message_attachments` | Three: `messages`, `message_attachments`, `workspaces` (joinVia `workspace_members`) at `dsar-export-allowlist.ts:168-175` | `workspaces` is workspace-metadata (no user-authored content) — out of scope. YAGNI argument for inline (vs. declarative `DsarTableSpec` extension) holds. |
| 5 | Preserve raw `user_id` of foreign author for transparency | Raw `user_id` of non-subject is third-party PII per EDPB Guidelines 01/2022 §175. **Plan-review GDPR-gate Crit-5:** the brainstorm claimed "reuse the bundle-hashing salt" but `dsar-export.ts:1270-1281` computes `bundleHash` as a content-derived SHA-256, NOT a random salt. Salt source GAP. **SpecFlow #5:** hex8 = 32-bit collision space, birthday-bound problematic past ~10^4. | Mint `pseudonymSalt = crypto.randomBytes(32)` at function entry (memory-only, never persisted to manifest/audit/log). Redacted rows replace raw `user_id` with `member_<hex12>` where `hex12 = sha256(salt || raw_user_id).slice(0,12)`. AC asserts salt appears only in the predicate closure, zero appearances in manifest emission code. |
| 6 | PR #4289 covers Art. 15(4) disclosure | Verified `gh pr view 4289`: MERGED 2026-05-22T08:07:37Z at `8877c198`. `git show origin/main:docs/legal/{privacy-policy,gdpr-policy,data-processing-description}.md` and `knowledge-base/legal/article-30-register.md` contain ZERO matches for `Art\. 15.4|rights of others|Recital 63`. | **FR6 fires.** Coordinated text update through `.github/workflows/legal-doc-cross-document-gate.yml`. |
| 7 | `MANIFEST_SCHEMA_VERSION` has one consumer (`dsar-export.ts`) | Two: `apps/web-platform/server/dsar-export.ts:133,1234` AND `apps/web-platform/scripts/dsar-export-oversize.sh:130` (operator script). | Bump both sites in lockstep. |
| 8 | Bundle table files are `.jsonl` (newline-delimited) | **Plan-review Kieran P0-1:** verified at `dsar-export.ts:1174` — files are written as `tables/${t.table}.json` (single JSON object `{table, article, row_count, rows}`). | Manifest `redactions[].path` values are `tables/messages.json` and `tables/message_attachments.json`. Disclosure copy text avoids extension-specific phrasing. |
| 9 | DSAR-export has its own Processing Activity row | **GDPR-gate Imp-3:** No standalone DSAR-export PA in `article-30-register.md`. DSAR TOMs are scattered across PA-2 §(g)(3-9). | Phase 8 edits **PA-2 §(g)** specifically, adding numbered TOM item (12) for `redactRow` + Art. 15(4) minimization controls. |
| 10 | Subject-authored messages in foreign-owned conversations are in scope | **Plan-review Kieran P0-2:** After mig 059, Alice can post in Bob's workspace conversation. Current fetch by `c.user_id = Alice` silently omits these from Alice's DSAR (Art. 15 completeness gap, NOT Art. 15(4)). | **Scope-out** to #4358. Spec NG entry added: "Subject's messages in foreign-owned conversations remain out of scope; tracked at #4358." |
| 11 | Internal audit trail via pino log is sufficient | **GDPR-gate Crit-4:** Better Stack 30d retention < Art. 82(2) limitation horizon (DE 3y minimum); pino logs are not WORM. | **Scope-out** to #4359 (`dsar_export_audit_pii` WORM extension). Pino log line ships in this PR as the immediate observability hook; long-horizon WORM extends per #4359. |

## Files to Edit

1. **`apps/web-platform/server/dsar-export.ts`** (load-bearing change):
   - L133: `MANIFEST_SCHEMA_VERSION = "1.0.0"` → `"1.1.0"`.
   - L154-178: extend `ManifestRoot` type with `redactions: { path: string; reason: string; count: number }[]` (inline shape, no separate `ManifestRedaction` export).
   - Adjacent to `assertReadScope` (L102-123): add **one** pure helper `redactRow<T extends Record<string, unknown>>(row: T, shouldRedact: boolean, fieldsToNull: readonly (keyof T)[], pseudonymCol?: keyof T, pseudonym?: string): boolean` — returns `true` if redacted (so the call site can count). Plus the pseudonymisation helper `pseudonymiseUserId(rawUserId: string, salt: Buffer): string`.
   - At function entry (immediately after `expectedUserId` resolution): mint `const pseudonymSalt = crypto.randomBytes(32)` — memory-only, closure-scoped, NEVER passed to manifest/audit/log emission code.
   - L328-364 (messages block): after fetch, iterate rows; compute `isSubjectAuthored = row.user_id === expectedUserId || (row.user_id === null && LEGACY_NULL_IS_SUBJECT)` (where `LEGACY_NULL_IS_SUBJECT` is a `const` set by Phase 0.3 audit — `true` if confirmed safe, `false` for fail-closed default). Apply `redactRow(row, !isSubjectAuthored, ["content","tool_calls","usage","draft_preview","action_class"], "user_id", pseudonymiseUserId(row.user_id, salt))`. Collect `subjectAuthoredMessageIds: Set<string>` (only when `isSubjectAuthored && row.id`) and `messagesRedactionCount`. **TR3 invariant:** cross-tenant `CrossTenantViolation` assertion runs BEFORE the redaction predicate.
   - L370-… (message_attachments block): after fetch, iterate; compute `shouldRedact = !subjectAuthoredMessageIds.has(row.message_id)`; apply `redactRow(row, shouldRedact, ["storage_path", "filename"])` (no pseudonymisation column on attachments — they have no `user_id`). Collect `attachmentRedactionCount`.
   - L1232-1250 (manifest emission): populate `manifest.redactions` with entries `{path: "tables/messages.json", reason: "art-15-4-rights-of-others", count: messagesRedactionCount}` and `{path: "tables/message_attachments.json", reason: "art-15-4-rights-of-others", count: attachmentRedactionCount}`. Only include entries with `count > 0`.
   - After manifest write, before function return: emit `logger.info({ feature: "dsar-export", op: "redact-foreign-author", userIdHash: hashUserId(expectedUserId), redactions: { messages: messagesRedactionCount, message_attachments: attachmentRedactionCount } }, "redacted foreign-author content")`. Counts only; `renameUserIdToHash` formatter at `server/logger.ts:5` rewrites bare `userId` → `userIdHash`.

2. **`apps/web-platform/scripts/dsar-export-oversize.sh`** (paired manifest bump):
   - L130: `"schema_version": "1.0.0"` → `"schema_version": "1.1.0"`. Add `"redactions": []` to the operator-generated stub.

3. **`apps/web-platform/test/dsar-author-redaction.integration.test.ts`** (new, load-bearing) — see Phase 7.

4. **`docs/legal/privacy-policy.md`** (FR6) — Add Art. 15(4) / Recital 63 disclosure paragraph in Right of Access section. Canonical phrasing (lifted from EDPB Guidelines 01/2022 §172):
   > *"When you exercise your right of access under Article 15, we will provide a copy of personal data concerning you. Where your data resides in shared conversations that include contributions from other workspace members, we will redact content authored by those other members to protect their rights and freedoms under Article 15(4) GDPR. The export will indicate the location and count of such redactions; the redacted users are referred to by a pseudonymous identifier scoped to your export bundle."*

5. **`docs/legal/gdpr-policy.md`** (FR6) — Mirror the disclosure in §6.1.b alongside existing DSAR allowlist text.

6. **`docs/legal/data-processing-description.md`** (FR6) — §2.3 single-sentence addition referencing the manifest field.

7. **`knowledge-base/legal/article-30-register.md`** (FR6) — Extend **PA-2 §(g)** (NOT a new PA row) with new TOM item (12): "**Art. 15(4) author-only redaction** — `redactRow` helper at `apps/web-platform/server/dsar-export.ts` nulls free-text personal-data columns (`content`, `tool_calls`, `usage`, `draft_preview`, `action_class`) on messages authored by a non-subject within a subject-owned conversation; cascades to `message_attachments` via allowlist semantic on `subjectAuthoredMessageIds`. Per-bundle salt-scoped pseudonym replaces raw `user_id` of non-subject author. Manifest `redactions[]` field discloses count + reason + path to the subject (EDPB Guidelines 01/2022 §176). PA-2 sub-purpose: Art. 15 fulfillment minimization under Art. 15(4) rights-of-others narrowing."

## Files to Create

1. **`apps/web-platform/test/dsar-author-redaction.integration.test.ts`** — see Phase 7.

(No new helper file; helpers live in `dsar-export.ts` per TR1.)

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from parent #4230 brainstorm).

### Engineering (CTO) — carry-forward

**Status:** reviewed. **Plan-review delta:** the helper unification to one `redactRow<T>` was operator-approved at plan-review against the original two-helper proposal.

### Product (CPO) — carry-forward; **plan-time sign-off required**

**Status:** reviewed. CPO sign-off required at plan time per `requires_cpo_signoff: true`. Recorded via PR-body checkbox before `gh pr ready`.

### Legal (CLO) — carry-forward + plan-time delta

**Status:** reviewed. **Plan-time delta:** FR6 fires (verified PR #4289 merged copy contains zero Art. 15(4) language). FR6 coordinated through `.github/workflows/legal-doc-cross-document-gate.yml`.

### Product/UX Gate

**Tier:** none — no new user-facing pages, modals, dialogs, or interactive surfaces.

## User-Brand Impact

- **Brand-survival threshold:** `single-user incident` — carry-forward from brainstorm; canonical-bullet form for preflight Check 6 + ship Phase 5.5 gate detection.

Enumerated by **role** (per `2026-05-06-user-impact-section-by-role-not-surface.md`):

**Role 1 — Requesting subject (data subject under Art. 15):**
- **Under-disclosure (Art. 15 incompleteness):** Subject's own legacy `user_id IS NULL` rows over-redacted because Phase 0.3 audit defaulted fail-closed. Mitigated by AC1 fixture covering legacy rows under both audit outcomes; AC1 explicitly asserts the deterministic redaction matches the audited semantic.
- **Artifact:** `tables/messages.json` in the export bundle.
- **Vector:** the legacy NULL handling branch.

**Role 2 — Non-subject co-conversant (the Art. 15(4) "rights of others" cohort):**
- **Under-redaction (Art. 15(4) leak):** Bob's verbatim content in Alice's conversation appears in Alice's bundle. **Brand-survival threshold trigger.**
- **Artifact:** `tables/messages.json` rows where `user_id != requester` and Phase 3 predicate failed.
- **Vector:** absence of the predicate at `dsar-export.ts:328-364` OR predicate skipped on legacy NULL rows OR raw `user_id` of non-subject leaks via the row's `user_id` column (Reconciliation #5) OR orphan attachment leaks via denylist semantic (Reconciliation #3 — now allowlist).

**Role 3 — Workspace admin / Soleur operator (controller accountability under Art. 5(2)):**
- **Silent / unobservable leak:** No alert; controller cannot demonstrate the Art. 15(4) balancing test was applied.
- **Artifact:** pino structured log line + `manifest.redactions` field.
- **Vector:** missing log emission (TR5) OR log fields contain PII (raw `user_id`, content fragments) OR salt leaks to manifest.
- **Long-horizon gap:** pino's 30d retention is insufficient for Art. 82(2) horizon — tracked at #4359 (WORM extension to `dsar_export_audit_pii`).

**Brand-survival escalation:**
- Detection: `user-impact-reviewer` at PR review (per AC9) + integration test (FR5/AC1) covers both over- and under-redaction.
- Containment if shipped broken: operator-mediated bundle revocation via `knowledge-base/legal/runbooks/dsar-accountless-ex-member.md` adaptation. Statutory clock Art. 33 / 34 (72h notification + affected-subject contact); single confirmed leak escalates immediately to CLO.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned zero matches for `dsar-export.ts`, `test/dsar-*`, or `dsar-export-allowlist`.

## Observability

```yaml
liveness_signal:
  what: Per-export-job structured log line emitted after manifest write
  cadence: One emission per DSAR export job (event-driven)
  alert_target: Better Stack Logs (pino) + Sentry breadcrumb (warn+ mirror at server/logger.ts:50-80) — info-level is pino-only by default
  configured_in: apps/web-platform/server/dsar-export.ts post-manifest emission; pino→Sentry mirror configured at server/logger.ts
error_reporting:
  destination: Sentry (existing pino mirror; SENTRY_BREADCRUMB_MIN_LEVEL = warn)
  fail_loud: yes — exporter throws on `service.from(...)` errors; redactRow is pure (no side effects); cross-tenant violation continues to call mirrorCrossTenantViolation
failure_modes:
  - mode: Over-redaction of subject's legacy NULL rows
    detection: AC1 fixture asserts M3 (subject's legacy NULL row) redaction matches Phase 0.3 audit-determined LEGACY_NULL_IS_SUBJECT constant
    alert_route: CI failure
  - mode: Under-redaction (foreign-author rows escape predicate)
    detection: AC1 fixture asserts M2 (Bob-authored row in Alice's conversation) IS redacted
    alert_route: CI failure
  - mode: Manifest schema drift (script consumer still emits 1.0.0)
    detection: AC2 — schema_version-context grep across both producer sites
    alert_route: CI failure
  - mode: PII leak via log payload
    detection: AC1 captures logger.info call; asserts no raw user_id / no row IDs / no content / no salt
    alert_route: CI failure + manual review at PR-time (security-sentinel agent)
  - mode: Foreign-author user_id leaked via redacted row's user_id column
    detection: AC1 asserts redacted row's user_id matches /^member_[0-9a-f]{12}$/ (NOT raw UUID)
    alert_route: CI failure
  - mode: Orphan attachment leaks (parent message deleted mid-export)
    detection: AC1 fixture includes orphan attachment scenario; asserts redaction by allowlist semantic
    alert_route: CI failure
discoverability_test:
  command: curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/api/account/export
  expected_output: "401"
  # Probes that the DSAR export route is reachable and auth-gated (401 without
  # session cookie = correct, route alive + RLS-gated). The redaction-count
  # log shape is verified by the integration test in CI under
  # SUPABASE_DEV_INTEGRATION=1; that test runs at every PR per #4351
  # Phase 7.1. The local-terminal observability probe checks the route is
  # live; CI checks the log shape. Preflight Check 10 invariant satisfied.
logs:
  where: Better Stack Logs (pino) + Sentry breadcrumbs (warn+ mirror)
  retention: Better Stack 30d. **Long-horizon WORM via dsar_export_audit_pii extension tracked at #4359.**
```

## Acceptance Criteria

### Pre-merge (PR) — load-bearing

- **AC1:** `apps/web-platform/test/dsar-author-redaction.integration.test.ts` passes in CI. Fixture: workspace W, members Alice + Bob + Charlie; Alice owns conversation C in W. Messages: M1 authored by Alice (with attachment A1), M2 authored by Bob (with attachment A2 + orphan-shape attachment A2b whose `message_id` is for a deleted message), M3 with `user_id IS NULL` (legacy), M4 authored by Bob (second Bob message), M5 authored by Charlie. Alice exercises DSAR. Bundle assertions:
  - M1 content + tool_calls + usage + draft_preview + action_class present and unchanged; M1.user_id = Alice.id.
  - M2 + M4 content + tool_calls + usage + draft_preview + action_class are ALL `null`; M2.user_id and M4.user_id match `/^member_[0-9a-f]{12}$/` and are IDENTICAL (same Bob → same pseudonym within bundle).
  - M5.user_id matches `/^member_[0-9a-f]{12}$/` and is DIFFERENT from M2/M4 (Charlie ≠ Bob).
  - M3 redaction state matches `LEGACY_NULL_IS_SUBJECT` (per Phase 0.3): if `true`, M3 content preserved + M3.user_id = `null` (not pseudonymised — it's the legacy null itself); if `false`, M3 content nulled + M3.user_id retained as `null`.
  - All redacted rows preserve `id`, `conversation_id`, `role`, `created_at`.
  - A1 (Alice attachment on M1): storage_path + filename PRESERVED and unchanged.
  - A2 (Bob attachment on M2): storage_path + filename `null`; A2.id, message_id, content_type, size_bytes, created_at preserved.
  - A2b (orphan attachment): storage_path + filename `null` (allowlist fail-closed).
  - `manifest.schema_version === "1.1.0"`.
  - `manifest.redactions` contains entries for `tables/messages.json` (count: 2 if `LEGACY_NULL_IS_SUBJECT`, else 3) and `tables/message_attachments.json` (count: 2 — A2 + A2b).
  - Capture `logger.info` call: shape exactly matches `{ feature: "dsar-export", op: "redact-foreign-author", userIdHash: <hex32>, redactions: { messages: N, message_attachments: M } }`. No raw `userId`, no `content`, no `salt`, no row IDs.
- **AC2:** Manifest schema bump verified at both producer sites. Verification: `grep -nE 'schema_version[^=]*"1\.0\.0"' apps/web-platform/server/dsar-export.ts apps/web-platform/scripts/dsar-export-oversize.sh` returns ZERO matches; `grep -nE 'schema_version[^=]*"1\.1\.0"' …` returns 2 matches (one per producer site).
- **AC3:** `apps/web-platform/test/dsar-export-cross-tenant.integration.test.ts` still passes (regression: predicate runs AFTER scope check). Plus a NEW test row inside the fixture: a message with `conversation_id` outside `ownedConvSet` is constructed and `CrossTenantViolation` is asserted to raise BEFORE any redaction — proves ordering invariant.
- **AC4:** Legal-doc cross-document gate passes: `grep -lE 'Art\.\s*15\(4\)' docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-processing-description.md knowledge-base/legal/article-30-register.md` returns 4 paths.
- **AC5:** Salt isolation: `grep -nE 'pseudonymSalt|crypto\.randomBytes' apps/web-platform/server/dsar-export.ts` shows ONE mint site adjacent to `expectedUserId` resolution AND uses ONLY in the predicate closure (within the messages block iteration); ZERO appearances in the manifest emission code path (L1232-1250) or in any `logger.info` / `logger.warn` / `Sentry.*` call.
- **AC6:** CPO sign-off recorded in PR body (checkbox) before `gh pr ready` (per `requires_cpo_signoff: true`).
- **AC7:** `dsar-allowlist-completeness.test.ts` and `dsar-worker-per-row-where.test.ts` still pass (regression check on unrelated lints).
- **AC8:** Issues #4358 and #4359 cross-referenced in PR body as deferred-scope-out with rationale.
- **AC9:** `user-impact-reviewer` agent invoked at PR review; agent output pasted as PR comment (linked in PR body) and returns APPROVE on all three User-Brand Impact roles.

### Post-merge (operator)

- **None.** Predicate ships inert until next DSAR export job is triggered, at which point the existing event-driven exporter applies it automatically. **Automation: not feasible because** there is no operator step.

## Risks

1. **Pseudonymisation salt extraction from process memory.** Mitigation: salt held in closure only; never persisted; AC5 grep-asserts isolation.
2. **Schema bump consumer drift** (Reconciliation #7). Both producer sites bumped in lockstep; AC2 grep-asserts.
3. **Legacy NULL ambiguity** (Reconciliation #1). Fail-closed default (REDACT) is the conservative choice; Phase 0.3 audit can flip to fail-open if write paths are confirmed safe. AC1 fixture covers BOTH outcomes.
4. **Over-trim on unintended columns.** The fields-to-null list is closed (`content`, `tool_calls`, `usage`, `draft_preview`, `action_class`). Future schema additions are not auto-redacted — see Sharp Edges.
5. **Pseudonym hex12 collision.** 48-bit space, birthday-safe past 10^6 distinct authors per bundle. Bundles realistically contain ≤100 distinct authors; collision probability < 4e-11.
6. **Disclosure language drift.** Cross-document gate enforces same-PR coordination; AC4 token grep enforces semantic alignment.
7. **#4358 completeness gap visibility.** First-multi-user-workspace DSAR may surface omissions of subject's own messages in foreign-owned conversations. Documented in #4358 re-evaluation criteria; user-impact-reviewer at PR review of #4358 is the gate for that scope.
8. **#4359 audit-trail gap visibility.** First regulator inquiry or DPO accountability audit referencing the missing internal log would trigger #4359 re-evaluation.

## Implementation Phases

### Phase 0 — Preconditions

- **0.1** Re-verify `gh pr view 4289 --json mergedAt,mergeCommit` → MERGED at `8877c198…`. (Done at plan-write; re-check at /work start.)
- **0.2** Re-verify zero Art. 15(4) matches in `git show origin/main:docs/legal/{privacy-policy,gdpr-policy,data-processing-description}.md` and `article-30-register.md`. (Done at plan-write.)
- **0.3** **LEGACY_NULL_IS_SUBJECT audit (load-bearing for AC1 predicate semantics):** grep RLS policies on `messages` table from migrations 001 through latest. Check INSERT paths in `ws-handler.ts`, `apps/web-platform/server/agent/`, and any service-role insert sites. Determine: can a non-subject write `user_id IS NULL` rows into a foreign-owned conversation? Set `const LEGACY_NULL_IS_SUBJECT = <true|false>` based on audit:
  - `true` (fail-open): only if audit confirms `user_id IS NULL` writes are write-restricted to `auth.uid() = c.user_id` at every insert path.
  - `false` (fail-closed, default): if any ambiguity remains.
  - Record audit outcome in PR body as a checkbox before merge.
- **0.4** Verify `MANIFEST_SCHEMA_VERSION` literal locations: `grep -nE 'schema_version' apps/web-platform/server/dsar-export.ts apps/web-platform/scripts/dsar-export-oversize.sh` returns exactly 2 sites with `"1.0.0"`.
- **0.5** `messages` hard-delete confirmation: `grep -nE 'deleted_at|soft_delete' apps/web-platform/supabase/migrations/{001,046}_*.sql` returns zero matches. (Confirms historical Bob-content doesn't ghost after Bob's delete.)
- **0.6** `dsar_export_jobs` historical count probe: `service.from("dsar_export_jobs").select("id").eq("status", "completed")` count. If non-zero, escalate to CLO BEFORE merge to decide retroactive sweep policy. Document outcome in PR body.

### Phase 1 — RED: write failing tests

Per `cq-write-failing-tests-before`: implement the integration test FIRST.

- Create `apps/web-platform/test/dsar-author-redaction.integration.test.ts` with the AC1 fixture (Alice+Bob+Charlie, M1-M5, A1+A2+A2b).
- Run vitest: expected FAIL on every assertion that depends on Phase 2+ work.

### Phase 2 — Helper + type widening + salt minting

**Precondition (Kieran P1-5):** the `ManifestRoot` type extension MUST land in the same commit as `MANIFEST_SCHEMA_VERSION = "1.1.0"` AND BEFORE Phase 3-5 — otherwise TypeScript will error on the manifest object literal at L1234.

- Adjacent to `assertReadScope`: add `redactRow<T>` and `pseudonymiseUserId`.
- L154-178: extend `ManifestRoot` with inline `redactions: { path: string; reason: string; count: number }[]`.
- L133: `MANIFEST_SCHEMA_VERSION = "1.1.0"`.
- At function entry (after `expectedUserId` resolution): `const pseudonymSalt = crypto.randomBytes(32)`. The `crypto` import already exists at the top of `dsar-export.ts` for `bundleHash`.

### Phase 3 — Messages block predicate

- L328-364: after fetch, iterate. Compute `isSubjectAuthored = row.user_id === expectedUserId || (row.user_id === null && LEGACY_NULL_IS_SUBJECT)`. Call `redactRow(row, !isSubjectAuthored, ["content","tool_calls","usage","draft_preview","action_class"], "user_id", isSubjectAuthored ? row.user_id : pseudonymiseUserId(row.user_id ?? "", pseudonymSalt))`. Accumulate `subjectAuthoredMessageIds: Set<string>` and `messagesRedactionCount`.
- **TR3 invariant:** cross-tenant `CrossTenantViolation` assertion stays exactly where it is — predicate runs AFTER.

### Phase 4 — Attachments block (allowlist semantic)

- L370-…: after fetch, iterate. Compute `shouldRedact = !subjectAuthoredMessageIds.has(row.message_id)`. Call `redactRow(row, shouldRedact, ["storage_path", "filename"])`. Accumulate `attachmentRedactionCount`.

### Phase 5 — Manifest emission

- L1232-1250: populate `manifest.redactions` from counters (only entries with `count > 0`).

### Phase 6 — Observability emission

- After manifest write, before return: `logger.info({ feature: "dsar-export", op: "redact-foreign-author", userIdHash: hashUserId(expectedUserId), redactions: { messages: messagesRedactionCount, message_attachments: attachmentRedactionCount } }, "redacted foreign-author content")`. Info-level → pino-only (no Sentry over-paging).

### Phase 7 — Integration test (GREEN)

- Wire up fixture via `createSharedWorkspaceMembers(supabase, ["alice@example.test", "bob@example.test", "charlie@example.test"])`. (All fixture emails synthetic per `cq-test-fixtures-synthesized-only`.)
- Insert conversations + messages + attachments per AC1 fixture.
- Invoke exporter via the same entry point as `dsar-export-cross-tenant.integration.test.ts`.
- Read bundle's `tables/messages.json`, `tables/message_attachments.json`, `manifest.json`; assert per AC1.
- Add test case "emits redaction counts" — uses `vi.spyOn(logger, 'info')` to capture the log call; asserts shape per Observability discoverability_test.
- Add test case "CrossTenantViolation raised BEFORE redaction" — insert a row whose `conversation_id` is outside the owner-scoped set; assert the violation throws BEFORE the redaction loop executes.

### Phase 8 — Legal-doc disclosure delta (FR6)

- Edit four files per `## Files to Edit` entries 4-7. Use the canonical EDPB-aligned text in Files to Edit #4. Article 30 register edit targets PA-2 §(g) — NEW numbered TOM item (12) — NOT a new PA row.

### Phase 9 — AC verification

- Run integration test → GREEN.
- Run regression suite: cross-tenant + allowlist-completeness + per-row-where tests → GREEN.
- AC2 + AC4 + AC5 greps locally; capture output for PR body.
- Mark draft PR #4351 ready: AC6 CPO sign-off checkbox in PR body, then `gh pr ready 4351`.
- AC9: invoke `user-impact-reviewer` via the review skill conditional-agent block; paste agent output as PR comment; link in PR body.

## Test Strategy

- **Runner:** vitest. Invocation: `cd apps/web-platform && ./node_modules/.bin/vitest run test/dsar-author-redaction.integration.test.ts`. (Sharp Edge: `apps/web-platform/bunfig.toml` blocks bun test discovery.)
- **Fixture isolation:** `createSharedWorkspaceMembers` per `describe`; `tearDownSharedWorkspace` in `afterEach`. Synthetic emails only via `syntheticEmail()` and `*@example.test` domain.
- **Logger capture:** `vi.spyOn(logger, 'info')` (no real Sentry / Better Stack emission in test mode).

## Non-Goals

(From spec + plan-review additions.)
- No retroactive bundle re-export (spec NG1; Phase 0.6 audit gates this).
- No content-based attachment scanning (spec NG2).
- No declarative `DsarTableSpec` redaction extension (spec NG3).
- No new UI / endpoint / runbook (spec NG4).
- No worker concurrency / retry changes (spec NG5).
- **NG6 (new):** Subject-authored messages in foreign-owned workspace conversations remain in the exporter's existing conversation-keyed fetch (omitted from Alice's bundle). Tracked at **#4358**.
- **NG7 (new):** Long-horizon (>30d) internal audit trail of redactions is out of scope; pino log line is the immediate observability. Tracked at **#4359**.
- **NG8 (new):** `dsar-export-allowlist.ts` is NOT modified — no new entries, no schema changes. Predicate lives entirely in `dsar-export.ts` per TR1.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or has placeholder text fails `deepen-plan` Phase 4.6. This plan enumerates by role; do not condense.
- The `pseudonymSalt` MUST stay in closure. Confirm at code review via AC5 grep — salt must NEVER appear in manifest emission code path, log calls, or audit writes.
- Predicate runs AFTER `CrossTenantViolation` assertion (TR3 invariant). Inverting hides the violation.
- The fields-to-null list (`content`, `tool_calls`, `usage`, `draft_preview`, `action_class`) is closed. Per `hr-write-boundary-sentinel-sweep-all-write-sites`: any future migration adding a free-text personal-data column to `messages` MUST sweep `dsar-export.ts` for the predicate's field list and update.
- Phase 0.3 LEGACY_NULL_IS_SUBJECT audit is load-bearing for AC1 fixture's M3 assertion. Default fail-closed; flip to fail-open ONLY if every `messages` INSERT path is verified write-restricted to `auth.uid() = c.user_id`.
- All fixture data uses `syntheticEmail()` / `distinctivePhrase()`. NO copying real production data into the test (`cq-test-fixtures-synthesized-only`).
- `additionalOwnerFields` (PR #4287) is forward-defense; if `messages` ever gains an additional owner column (e.g., `assistant_user_id`), the predicate's single-column check would miss it. Test fixture comment-anchors the place where the check would expand.
- Bundle file extension is `.json` (single JSON object), NOT `.jsonl` (line-delimited). Verified at `dsar-export.ts:1174`. Plan-review Kieran P0-1.
