---
title: DSAR author-only message redaction (Art. 15(4))
issue: 4319
parent_issue: 4230
brainstorm: knowledge-base/project/brainstorms/2026-05-22-dsar-author-redaction-brainstorm.md
branch: feat-dsar-author-redaction-4319
draft_pr: 4351
status: spec
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
related_pr_merged: 4289
date: 2026-05-22
---

# Spec — DSAR Author-Only Message Redaction (Art. 15(4))

## Problem Statement

After migration 059 made conversations workspace-keyed (RLS policy
`conversations_workspace_member_all`), any workspace co-member can post
messages in a conversation owned by another member. The DSAR exporter
at `apps/web-platform/server/dsar-export.ts:328-364` fetches messages
by `.in("conversation_id", conversationIds)` only — no author filter —
so a requester's DSAR bundle includes co-members' verbatim messages
that reside in the requester's conversations.

This violates GDPR Art. 15(4) "rights and freedoms of others" — Recital
63 supports narrowing Art. 15 to exclude content authored by third
parties whose rights would be adversely affected. Brand-survival
threshold: single-user incident (one DSAR exposes one co-member's
content).

Parent issue #4230 originally bundled this FR5 predicate; plan-review
(DHH, Kieran, Code-Simplicity) recommended split because (a) the
predicate affects ALL DSARs not just departed-member, (b) Art. 13(2)(b)
disclosure dependency had to coordinate with PR #4289 (legal
scaffolding) which is now MERGED 2026-05-22T08:07Z.

## Goals

- **G1:** Messages authored by a non-subject within a subject-owned
  conversation are returned with content nulled but thread-position
  metadata preserved (`id`, `conversation_id`, `role`, `created_at`,
  `user_id`).
- **G2:** Message attachments authored by a non-subject within a
  subject-owned conversation are returned with storage URL nulled but
  `id`, `message_id`, `mime_type`, `byte_size`, `created_at` preserved.
- **G3:** The DSAR bundle manifest surfaces redaction occurrences via a
  new top-level `redactions: { path, reason, count }[]` field; schema
  version bumps from `1.0.0` to `1.1.0`.
- **G4:** Integration test fixture asserts the mixed-ownership behavior
  end-to-end (Alice owns conversation, Bob co-authors one message,
  Alice's export bundle redacts Bob's content while preserving
  structural fields and manifest entry).
- **G5:** If merged PR #4289 does NOT already cover Art. 15(4)
  redaction semantics in legal docs, coordinate a docs/legal text
  update through the legal-doc cross-document gate in this PR.

## Non-Goals

- **NG1:** No retroactive sweep of already-issued DSAR bundles. Verify
  at plan time via `dsar_export_jobs` count — if zero historical
  exports contain mixed-ownership conversations, no sweep is required.
- **NG2:** No content-based attachment redaction. Author-keyed only:
  `message_attachments.user_id != requester` triggers redaction; we do
  not inspect blob bodies.
- **NG3:** No declarative redaction-policy extension to `DsarTableSpec`
  in `dsar-export-allowlist.ts`. YAGNI — only one joinVia table
  (`messages` + child `message_attachments`) needs this predicate
  today.
- **NG4:** No new UI surface, endpoint, or operator runbook. Predicate
  ships inside the existing exporter pipeline.
- **NG5:** No changes to the worker concurrency model, retry logic, or
  upload streaming substrate.

## Functional Requirements

- **FR1:** In `dsar-export.ts:328-364`, after the messages
  `.in("conversation_id", …)` fetch, iterate the returned rows and for
  each row where `row.user_id !== expectedUserId`, set `row.content =
  null` (and any other personal-data column added by future
  migrations — gate via a single helper `redactForeignAuthorMessage`).
  Preserve `id`, `conversation_id`, `role`, `created_at`, `user_id`.
- **FR2:** In the `message_attachments` block (joinVia messages),
  apply analogous logic: for each row where `row.user_id !==
  expectedUserId`, null the storage URL field(s). Preserve `id`,
  `message_id`, `mime_type`, `byte_size`, `created_at`, `user_id`.
- **FR3:** Extend the `ManifestRoot` TypeScript type to include
  `redactions: { path: string; reason: string; count: number }[]`.
  Bump the embedded `schema` field from `"1.0.0"` to `"1.1.0"`.
- **FR4:** The exporter appends one entry to `manifest.redactions` per
  table whose export had ≥1 row redacted, with shape
  `{ path: "<table>.jsonl", reason: "art-15-4-rights-of-others",
  count: <N> }`. Zero-count entries are omitted.
- **FR5:** A new integration test at
  `apps/web-platform/test/dsar-author-redaction.integration.test.ts`
  asserts:
  - Fixture: workspace W with members Alice + Bob; conversation C owned
    by Alice in W; message M1 authored by Alice + message M2 authored
    by Bob; attachment A2 on M2 authored by Bob.
  - When Alice exercises DSAR, the resulting bundle's `messages.jsonl`
    contains both M1 and M2.
  - M2's `content` is `null`; M2's `id`, `conversation_id`, `role`,
    `created_at`, `user_id` are present and unchanged.
  - M1's `content` is unchanged.
  - The bundle's `message_attachments.jsonl` contains A2 with its
    storage URL nulled and metadata preserved.
  - The bundle's `manifest.json` contains
    `schema: "1.1.0"` and `redactions` array with entries for
    `messages.jsonl` (count: 1) and `message_attachments.jsonl`
    (count: 1).
- **FR6 (conditional):** If plan-time research determines merged PR
  #4289 did NOT add Art. 15(4) redaction-semantics language to
  privacy-policy.md / gdpr-policy.md / DPD, add the language in this
  PR via the legal-doc cross-document gate.

## Technical Requirements

- **TR1:** The redaction helper(s) live in
  `apps/web-platform/server/dsar-export.ts` adjacent to the messages
  block. No changes to `dsar-export-allowlist.ts` type definitions.
- **TR2:** The manifest schema bump must be coordinated with any
  consumer that reads the manifest — confirm via
  `grep -rn 'manifest\.schema\|"1\.0\.0"' apps/web-platform/` at
  implementation time. If no consumers exist outside the exporter
  itself, the bump is no-cost. If consumers exist, gate the bump on
  consumer readiness.
- **TR3:** Cross-tenant assertion (`CrossTenantViolation` raise on
  rows whose `conversation_id` is not in the owner-scoped set) must
  remain in place — redaction does NOT subsume the existing scope
  check. The redaction predicate runs AFTER the scope check.
- **TR4:** The redaction helper must be deterministic and pure (no
  side effects) so it is unit-testable in isolation from the worker
  pipeline.
- **TR5:** Observability: Sentry breadcrumb / structured log line on
  each export job emitting `redactions: { messages: N, message_attachments: M }`
  counts (per `hr-observability-as-plan-quality-gate`). No PII in the
  log — counts only.

## Acceptance Criteria

- **AC1:** FR1 + FR2 redaction logic implemented and adjacent unit
  tests pass.
- **AC2:** FR3 + FR4 manifest changes implemented and the manifest
  schema version bump is reflected in any existing manifest-schema
  unit tests (search for fixture `"1.0.0"` literal occurrences).
- **AC3:** FR5 integration test passes locally and in CI.
- **AC4:** `dsar-export-cross-tenant.integration.test.ts` still passes
  (regression check on the scope-check ordering).
- **AC5:** `dsar-allowlist-completeness.test.ts` still passes (no
  allowlist type changes expected).
- **AC6 (conditional):** If FR6 fires, the legal-doc cross-document
  gate passes (privacy-policy + gdpr-policy + DPD updates land in the
  same PR).
- **AC7:** TR5 observability — a structured log line confirms redaction
  counts in a manual smoke test of the export endpoint.
- **AC8:** `user-impact-reviewer` agent approves the PR per the
  inherited brand-survival threshold.

## Out of Scope (revisit triggers)

- Retroactive bundle re-export with redaction applied. Re-evaluation
  trigger: any historical `dsar_export_jobs` row pre-dating this PR
  represents a workspace with ≥2 active members at the time of the
  export.
- Content-based attachment scanning (e.g., detecting that Bob's name
  appears inside a PDF Alice uploaded). Re-evaluation trigger: regulator
  guidance or DSAR-vendor convergence on attachment-content redaction.
- Generalizing the redaction predicate to other joinVia tables. Re-
  evaluation trigger: any new joinVia entry added to
  `DSAR_TABLE_ALLOWLIST` whose `parentTable` is workspace-keyed.

## Inherited Context

- Parent brainstorm: `knowledge-base/project/brainstorms/2026-05-22-dsar-workspace-member-extension-brainstorm.md`
- Parent spec: `knowledge-base/project/specs/feat-dsar-workspace-member-4230/spec.md` (FR5 carved out)
- Merged dependency: PR #4289 (legal scaffolding) — 2026-05-22T08:07Z
- Domain triad (CTO/CPO/CLO) assessments carried forward from parent;
  user-impact-reviewer at PR review is the load-bearing gate.
