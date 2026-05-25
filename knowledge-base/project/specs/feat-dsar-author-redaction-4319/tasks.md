---
title: Tasks — DSAR author-only message redaction (Art. 15(4))
issue: 4319
plan: knowledge-base/project/plans/2026-05-22-feat-dsar-author-redaction-art-15-4-plan.md
spec: knowledge-base/project/specs/feat-dsar-author-redaction-4319/spec.md
branch: feat-dsar-author-redaction-4319
worktree: .worktrees/feat-dsar-author-redaction-4319/
draft_pr: 4351
status: tasks
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-05-22
deferred_followups: [4358, 4359]
---

# Tasks — DSAR Author-Only Message Redaction (Art. 15(4))

## Phase 0 — Preconditions & Audit

- [x] **0.1** Re-verify PR #4289 MERGED: `gh pr view 4289 --json mergedAt,mergeCommit`. Expect `mergedAt: 2026-05-22T08:07:37Z`, `mergeCommit.oid: 8877c198…`.
- [x] **0.2** Re-verify zero Art. 15(4) matches in merged legal docs: `git show origin/main:docs/legal/{privacy-policy,gdpr-policy,data-processing-description}.md` and `knowledge-base/legal/article-30-register.md` — confirm FR6 still fires.
- [x] **0.3** **LEGACY_NULL_IS_SUBJECT audit (load-bearing).** Grep RLS policies on `messages` table from migrations 001-latest; grep INSERT paths in `ws-handler.ts`, `apps/web-platform/server/agent/`, `apps/web-platform/server/dsar-export.ts`, and any service-role insert site. Determine: can a non-subject write `user_id IS NULL` rows into a foreign-owned conversation?
  - [ ] If audit confirms write-restricted to `auth.uid() = c.user_id` at every path → set `LEGACY_NULL_IS_SUBJECT = true` (fail-open).
  - [ ] If any ambiguity remains → set `LEGACY_NULL_IS_SUBJECT = false` (fail-closed, default).
  - [ ] Record audit outcome as a checkbox in PR #4351 body BEFORE marking ready.
- [x] **0.4** Verify `MANIFEST_SCHEMA_VERSION` locations: `grep -nE 'schema_version' apps/web-platform/server/dsar-export.ts apps/web-platform/scripts/dsar-export-oversize.sh` → exactly 2 sites with `"1.0.0"`.
- [x] **0.5** Confirm `messages` is hard-delete (no soft-delete column): `grep -nE 'deleted_at|soft_delete' apps/web-platform/supabase/migrations/{001,046}_*.sql` returns zero.
- [x] **0.6** `dsar_export_jobs` historical count probe. If non-zero completed exports exist, escalate to CLO BEFORE merge to decide retroactive sweep policy. Document outcome in PR body.

## Phase 1 — RED: failing integration test first

- [x] **1.1** Create file `apps/web-platform/test/dsar-author-redaction.integration.test.ts`.
- [x] **1.2** Import test fixture helpers: `createSharedWorkspaceMembers`, `SharedWorkspaceFixture`, `tearDownSharedWorkspace` from `@/test/helpers/workspace-members-fixtures`; `syntheticEmail`, `distinctivePhrase`, `assertSynthetic` from existing DSAR test helpers.
- [x] **1.3** Build fixture: workspace W, members Alice + Bob + Charlie (all via `syntheticEmail()`); conversation C owned by Alice in W.
- [x] **1.4** Seed messages M1-M5 + attachments A1, A2, A2b per plan AC1.
- [x] **1.5** Write assertions per AC1 (see Phase 9 mapping).
- [x] **1.6** Add `vi.spyOn(logger, 'info')` capture for the redaction-count log line.
- [x] **1.7** Add cross-tenant violation regression case (Phase 7.5 in plan).
- [x] **1.8** Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/dsar-author-redaction.integration.test.ts`. Expect RED.

## Phase 2 — Helper + type widening + salt minting

- [x] **2.1** In `apps/web-platform/server/dsar-export.ts`, adjacent to `assertReadScope` (L102-123), add pure helper `redactRow<T extends Record<string, unknown>>(row: T, shouldRedact: boolean, fieldsToNull: readonly (keyof T)[], pseudonymCol?: keyof T, pseudonym?: string): boolean`. Returns `true` if redaction was applied.
- [x] **2.2** Add `pseudonymiseUserId(rawUserId: string, salt: Buffer): string` — `sha256(salt || rawUserId).slice(0,12)` returned as `member_<hex12>`.
- [x] **2.3** Extend `ManifestRoot` type at L154-178 with inline `redactions: { path: string; reason: string; count: number }[]` (no separate exported type).
- [x] **2.4** Update `MANIFEST_SCHEMA_VERSION = "1.1.0"` at L133.
- [x] **2.5** At function entry, after `expectedUserId` resolution: mint `const pseudonymSalt = crypto.randomBytes(32)`. Memory-only, closure-scoped.
- [x] **2.6** Confirm `crypto` import already at top of file (used by `bundleHash`). If absent, add.
- [x] **2.7** Type-check: `cd apps/web-platform && npx tsc --noEmit`. Must pass with the type extension before Phase 3.

## Phase 3 — Messages block predicate

- [x] **3.1** In `dsar-export.ts:328-364` messages block, after fetch + cross-tenant assertion + scope check:
- [x] **3.2** Declare `const LEGACY_NULL_IS_SUBJECT = <value-from-Phase-0.3>` as a top-of-file `const`.
- [x] **3.3** Iterate fetched rows: compute `isSubjectAuthored = row.user_id === expectedUserId || (row.user_id === null && LEGACY_NULL_IS_SUBJECT)`.
- [x] **3.4** Compute the pseudonym to use: `isSubjectAuthored ? row.user_id : pseudonymiseUserId(String(row.user_id ?? ""), pseudonymSalt)`.
- [x] **3.5** Call `redactRow(row, !isSubjectAuthored, ["content", "tool_calls", "usage", "draft_preview", "action_class"], "user_id", pseudonym)`. Increment `messagesRedactionCount` on `true` return.
- [x] **3.6** Build `subjectAuthoredMessageIds: Set<string>`: add `row.id` only when `isSubjectAuthored && typeof row.id === "string"`.
- [x] **3.7** Verify cross-tenant `CrossTenantViolation` block precedes the predicate — TR3 invariant.

## Phase 4 — Attachments block (allowlist semantic)

- [x] **4.1** In `dsar-export.ts` message_attachments block (~L370+), after fetch + scope check:
- [x] **4.2** Iterate rows: compute `shouldRedact = !subjectAuthoredMessageIds.has(String(row.message_id ?? ""))`. Orphan attachments → redact (allowlist fail-closed).
- [x] **4.3** Call `redactRow(row, shouldRedact, ["storage_path", "filename"])`. No pseudonymisation column on attachments.
- [x] **4.4** Accumulate `attachmentRedactionCount`.

## Phase 5 — Manifest emission

- [x] **5.1** At `dsar-export.ts:1232-1250` manifest construction:
- [x] **5.2** Build `redactions` array entries for `tables/messages.json` (`reason: "art-15-4-rights-of-others"`, count from Phase 3) and `tables/message_attachments.json` (count from Phase 4). Omit entries with `count === 0`.
- [x] **5.3** Assign `manifest.redactions = redactions`.
- [x] **5.4** Confirm `manifest.schema_version === MANIFEST_SCHEMA_VERSION` (now `"1.1.0"`).

## Phase 6 — Observability emission

- [x] **6.1** After manifest write, before function return: emit `logger.info({ feature: "dsar-export", op: "redact-foreign-author", userIdHash: hashUserId(expectedUserId), redactions: { messages: messagesRedactionCount, message_attachments: attachmentRedactionCount } }, "redacted foreign-author content")`.
- [x] **6.2** Verify NO raw `userId`, `content`, `salt`, or row IDs in the log payload.
- [x] **6.3** Confirm log level is `info` (pino-only) — `warn+` would page Sentry per `SENTRY_BREADCRUMB_MIN_LEVEL`.

## Phase 7 — Integration test (GREEN)

- [x] **7.1** Run vitest from Phase 1.8 → GREEN.
- [x] **7.2** Run regression suite: `dsar-export-cross-tenant.integration.test.ts`, `dsar-allowlist-completeness.test.ts`, `dsar-worker-per-row-where.test.ts` → all GREEN.
- [x] **7.3** Run `tsc --noEmit` → no type errors.

## Phase 8 — Paired manifest bump (script)

- [x] **8.1** Edit `apps/web-platform/scripts/dsar-export-oversize.sh:130`: `"schema_version": "1.0.0"` → `"schema_version": "1.1.0"`.
- [x] **8.2** Add `"redactions": []` line to the operator-generated stub immediately after `schema_version` for consistency.

## Phase 9 — Legal-doc disclosure delta (FR6)

- [x] **9.1** Edit `docs/legal/privacy-policy.md`: add the EDPB-aligned Art. 15(4) disclosure paragraph in the Right of Access section (canonical text in plan §Files-to-Edit #4).
- [x] **9.2** Edit `docs/legal/gdpr-policy.md`: mirror the disclosure in §6.1.b alongside existing DSAR allowlist text.
- [x] **9.3** Edit `docs/legal/data-processing-description.md`: §2.3 single-sentence addition referencing `manifest.redactions`.
- [x] **9.4** Edit `knowledge-base/legal/article-30-register.md`: extend **PA-2 §(g)** (NOT a new PA row) with NEW numbered TOM item (12) per plan §Files-to-Edit #7. Name `redactRow` + Art. 15(4) minimization controls explicitly.
- [ ] **9.5** Verify legal-doc cross-document gate passes locally if possible; otherwise CI gate (`.github/workflows/legal-doc-cross-document-gate.yml`) is the gate.

## Phase 10 — Acceptance criteria verification (pre-merge)

- [x] **10.1** AC1: integration test passes (Phase 7.1).
- [x] **10.2** AC2: `grep -nE 'schema_version[^=]*"1\.0\.0"' apps/web-platform/server/dsar-export.ts apps/web-platform/scripts/dsar-export-oversize.sh` → zero matches; `grep -nE 'schema_version[^=]*"1\.1\.0"' …` → 2 matches.
- [x] **10.3** AC3: cross-tenant regression test passes including new ordering-invariant case (Phase 7.5 in plan, Phase 1.7 here).
- [x] **10.4** AC4: `grep -lE 'Art\.\s*15\(4\)' docs/legal/privacy-policy.md docs/legal/gdpr-policy.md docs/legal/data-processing-description.md knowledge-base/legal/article-30-register.md` → 4 paths.
- [x] **10.5** AC5: salt isolation grep — `grep -nE 'pseudonymSalt|crypto\.randomBytes' apps/web-platform/server/dsar-export.ts` shows one mint site + N use sites, zero appearances in manifest emission (L1232-1250) or in any `logger.*` / `Sentry.*` call.
- [ ] **10.6** AC6: record CPO sign-off as a checkbox in PR #4351 body before `gh pr ready`.
- [x] **10.7** AC7: `dsar-allowlist-completeness.test.ts` + `dsar-worker-per-row-where.test.ts` regression tests pass.
- [ ] **10.8** AC8: PR #4351 body cross-references #4358 + #4359 with deferred-scope-out rationale.
- [ ] **10.9** AC9: invoke `user-impact-reviewer` agent (via review skill); paste agent output as PR comment; link comment URL in PR body.

## Phase 11 — Ship

- [ ] **11.1** Mark PR #4351 ready: `gh pr ready 4351` (after AC6, AC9 complete).
- [ ] **11.2** Watch CI: legal-doc cross-document gate + integration test + regression suite must all GREEN.
- [ ] **11.3** Resolve any review comments inline (per `rf-review-finding-default-fix-inline`).
- [ ] **11.4** Merge: `gh pr merge 4351 --squash --auto` after `user-impact-reviewer` APPROVE + CPO sign-off + green CI.

## Phase 12 — Post-merge verification

- [ ] **12.1** `gh issue close 4319` with comment: "Author-only redaction shipped at PR #4351. Long-horizon WORM audit + Art. 15 completeness gap tracked at #4359 / #4358."
- [ ] **12.2** Update #4358 + #4359 with a comment linking the merged PR.
- [ ] **12.3** Trigger one dev-env DSAR export against a synthetic mixed-ownership fixture; tail Better Stack live-tail filter `feature:"dsar-export" op:"redact-foreign-author"` to confirm a single log line emitted (operator may skip if Phase 7 GREEN is considered sufficient).

## Out of Scope (tracked elsewhere)

- **#4358** — Art. 15 completeness for subject-authored messages in foreign-owned conversations.
- **#4359** — Art. 5(2) accountability WORM extension for redaction events on `dsar_export_audit_pii`.
- Retroactive bundle re-export with redaction applied (spec NG1; gated on Phase 0.6 outcome).
- Content-based attachment scanning (spec NG2).
- `DsarTableSpec` declarative redaction-policy extension (spec NG3, plan NG8).
