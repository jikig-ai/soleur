---
title: "feat(kb-sync): add workspace_id discriminator to kb_sync_history rows"
issue: 4728
parent: 4717
branch: feat-one-shot-4728-kb-sync-workspace-id
date: 2026-06-01
type: feat
lane: single-domain
requires_cpo_signoff: false
brand_survival_threshold: none
---

# feat(kb-sync): add `workspace_id` discriminator to `kb_sync_history` rows

✨ **Type:** enhancement (additive schema-flexible field) · **Issue:** #4728 · **Parent:** #4717 (closed by #4726)

## Enhancement Summary

**Deepened on:** 2026-06-01 · **Sections enhanced:** Research Reconciliation, User-Brand Impact, Type-Widening Sweep, Risks (precedent), Observability
**Gates run inline (no subagent tooling in this environment):** 4.6 User-Brand Impact halt (PASS), 4.7 Observability schema (PASS — 5 fields, no ssh), 4.8 PAT-shaped variable scan (PASS — none), 4.45 verify-the-negative pass, 4.4 precedent-diff gate, live PR/issue/attribution checks.

### Key Improvements
1. **Sensitive-path scope-out added (gate fix).** 3 edited files match the preflight Check 6 sensitive-path regex (`server/`, `app/api/`); at `threshold: none` the plan now carries the required `threshold: none, reason:` scope-out bullet — without it, preflight would FAIL at ship time.
2. **Premise reconciliation hardened.** Verified via grep that #4717 shipped users-centric with NO `skippedMultiWorkspace` counter; #4728's re-eval criterion (b) references a non-existent counter. Plan reframed as orthogonal foundations, matching the brainstorm's 2026-06-01 plan-review pivot note.
3. **Negative claims verified.** "reader-inert" / "consumer never reads workspace_id" confirmed by grep (`cron-workspace-sync-health.ts` has 0 `workspace_id` refs; `kb-sync-status.tsx` has no field enumeration).

### New Considerations Discovered
- The **manual `/api/kb/sync` route has no `workspace_id` in scope** — it is users-centric (resolves by `users.workspace_path`). Leaving its rows `workspace_id`-free is correct and backfill-tolerant; fabricating one would need an extra `workspace_members` query for zero present-day benefit.
- **No migration needed.** `kb_sync_history` is JSONB; the field rides inside the existing `append_kb_sync_row` RPC `p_row jsonb` argument unchanged.

## Overview

`kb_sync_history` is a JSONB array column on `public.users` (migration 017). Each rich
row (`KbSyncRow`, defined in `apps/web-platform/server/session-sync.ts:327`) is appended
via the `append_kb_sync_row` SECURITY DEFINER RPC (migration 053) through the
`appendKbSyncRow(userId, row)` helper. Today a row carries
`{ at, trigger, sha_before?, sha_after?, ok, error_class?, push_received_at?, sync_completed_at }`
— **no workspace discriminator**. When one owner has ≥2 ready+installed workspaces, their
single `kb_sync_history` array interleaves rows from all of them with no way to tell which
workspace produced which row, and `sha_after` is not a reliable discriminator (two
workspaces on the same repo see identical SHAs).

This change adds an **optional `workspace_id?: string`** field to `KbSyncRow` and populates
it at the **webhook-push reconcile producer** (`workspace-reconcile-on-push.ts`), where the
iterated workspace's id (`ws.id`) is already in scope. The change is **additive and
backfill-tolerant**: `kb_sync_history` is JSONB, so **no DDL migration is required**; old
rows simply lack the field, and any future per-workspace consumer treats a missing
`workspace_id` as legacy-single-workspace.

This is a foundations-only change. It **writes** the discriminator so a future per-workspace
went-quiet scan can attribute rows; it does **not** add a reader. The consumer
(`cron-workspace-sync-health.ts` arm 3) is intentionally left untouched (see Non-Goals).

## Research Reconciliation — Spec vs. Codebase

The issue body (#4728) was written against the **brainstorm-era** design of #4717
(workspace-centric scan, `workspace_members` join, single-workspace-owner MVP with a
skip-and-count counter). That design was **revised at plan-review** before #4717 shipped
(see `2026-06-01-kb-sync-went-quiet-detection-brainstorm.md` line 123 — *"[Updated
2026-06-01 — plan-review pivot]"*). Two premise claims in #4728 are stale; the underlying
need is still valid. The plan must not inherit the stale framing.

| #4728 premise claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| "#4717 scopes its MVP to single-workspace owners only, skipping-and-counting multi-workspace owners" | **No skip-and-count exists.** `git grep 'skippedMultiWorkspace\|multiWorkspace\|workspace_members' cron-workspace-sync-health.ts` → empty. #4717 shipped **users-centric** (scans `users.repo_url` + `users.kb_sync_history`, one row per user); the single-workspace concern "dissolved." | Drop the "unblocks the skip-and-count" framing. This change is **orthogonal future-work foundations**, exactly as the brainstorm's updated note states ("#4728 … remains valid orthogonal future work"). |
| Re-eval criterion (b): "the went-quiet `skippedMultiWorkspace` count in the cron heartbeat becomes non-trivial" | That counter was never built (consequence of the pivot above). | Note in plan: this re-eval trigger references a non-existent counter. The live trigger is criterion (a) — "multiple users own ≥2 ready+installed workspaces." This plan is the foundations layer that makes (a) addressable. |
| "written by `appendKbSyncRow` in `workspace-reconcile-on-push.ts` (where the workspace id is already in scope)" | **Confirmed.** `ws.id` is in scope inside `for (const ws of rows)` at the 3 `appendKbSyncRow(ownerId, …)` call sites (lines 262, 292, 307). | Set `workspace_id: ws.id` on all 3 reconcile rows. |
| (implicit) all `appendKbSyncRow` call sites can supply `workspace_id` | **False for the manual route.** `appendKbSyncRow` is also called from `app/api/kb/sync/route.ts:130,148`. That route is users-centric: it resolves the workspace by `users.workspace_path` (legacy single-workspace-per-user FS path), and has **no `workspace_id` in scope**. | Leave manual-sync rows **without** `workspace_id` (field is optional). This is correct and backfill-tolerant: the manual route is the single-workspace `users` path; a missing `workspace_id` reads as legacy-single-workspace — the exact semantics #4728 prescribes. Documented as a deliberate decision, not a gap. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing. `kb_sync_history` rows
feed (a) the `KbSyncStatus` chip (reads `at`/`ok`/`error_class` — ignores unknown fields)
and (b) the admin analytics sparkline (reads legacy `{date,count}` rows only). An extra
optional `workspace_id` field is inert to both readers. Worst realistic failure is a
malformed JSONB write, but the RPC append path is unchanged (the field rides inside the
existing `p_row jsonb` argument).

**If this leaks, the user's data is exposed via:** N/A. `workspace_id` is a UUID the owner
already owns; it is never surfaced in a user-facing string and never leaves the tenant row.
No PII, no new cross-controller data movement.

**Brand-survival threshold:** none. (Additive, reader-inert, ops-internal field on a JSONB
column. No schema DDL, no auth flow, no API route behavior change, no `.sql` migration.)

- **threshold: none, reason:** the edited files `apps/web-platform/server/session-sync.ts`,
  `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`, and
  `apps/web-platform/app/api/kb/sync/route.ts` match the preflight Check 6 sensitive-path
  regex (`server/`, `app/api/`), but the change is a strict additive optional field on an
  ops-internal JSONB telemetry column — no credential, auth, billing, secret, or
  user-data-exposure surface is touched; readers ignore the field; the manual route is a
  documented no-op. This scope-out is required because the threshold is `none` AND
  sensitive-path files are touched (preflight Check 6 / deepen-plan Phase 4.6).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Type widened (optional).** `KbSyncRow` in `apps/web-platform/server/session-sync.ts`
  gains `workspace_id?: string` (optional, NOT required — required would break the 2
  manual-route call sites and every legacy row).
  Verify: `grep -n 'workspace_id?: string' apps/web-platform/server/session-sync.ts` returns 1.
- [ ] **AC2 — Reconcile producer writes the field at all 3 sites.** All three
  `appendKbSyncRow(ownerId, {…})` calls in
  `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts`
  (skip-not-ready, sync-failed, ok:true) include `workspace_id: ws.id`.
  Verify: `grep -c 'workspace_id: ws.id' apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` returns `3`.
- [ ] **AC3 — Manual route deliberately omits the field.** The 2 `appendKbSyncRow(userId, {…})`
  calls in `apps/web-platform/app/api/kb/sync/route.ts` do **not** set `workspace_id`
  (no `workspace_id` in scope; documented decision per Research Reconciliation row 4).
  Verify: `grep -c 'workspace_id' apps/web-platform/app/api/kb/sync/route.ts` returns `0`.
- [ ] **AC4 — Reconcile test asserts the discriminator.** The existing
  `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` is extended so
  at least one `appendKbSyncRowSpy` assertion uses
  `expect.objectContaining({ workspace_id: <wsId> })` for the relevant workspace id, on the
  ok:true path and at least one failure path.
- [ ] **AC5 — No consumer regression.** `tsc --noEmit` passes (the `lib/analytics.ts`,
  `components/kb/kb-sync-status.tsx`, and `cron-workspace-sync-health.ts` readers compile
  unchanged against the widened-but-optional type). The route test
  (`kb-sync-route.test.ts`) still passes — its `expect.objectContaining({ trigger: "manual",
  ok: true })` partial matchers are unaffected by AC3.
- [ ] **AC6 — Targeted suite green.** `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/server/inngest/workspace-reconcile-on-push.test.ts test/server/kb-sync-route.test.ts`
  passes. (Runner is vitest per `apps/web-platform/package.json` `"test": "vitest"`; files
  match the `test/**/*.test.ts` include glob in `vitest.config.ts:44`.)

## Implementation Phases

### Phase 1 — Widen the type (contract change — lands FIRST)

`apps/web-platform/server/session-sync.ts` — add optional field to `KbSyncRow` (after
`sync_completed_at`, with a one-line comment):

```ts
export type KbSyncRow = {
  at: string;
  trigger: "webhook_push" | "manual" | "session";
  sha_before?: string;
  sha_after?: string;
  ok: boolean;
  error_class?: KbSyncErrorClass;
  push_received_at?: number;
  sync_completed_at: number;
  // #4728 — workspace discriminator. Set by the webhook-push reconcile
  // producer (workspace-reconcile-on-push.ts), where the iterated
  // workspace id is in scope. Absent on manual-route rows and on all
  // legacy rows; a missing value reads as legacy-single-workspace.
  workspace_id?: string;
};
```

Rationale for **optional, contract-first ordering**: the producer edits (Phase 2) read the
widened type; widening must land before they reference the field, and an optional field
keeps every existing call site (manual route + legacy rows) type-valid. This is single-PR
atomic but phase order is load-bearing for sequential `/work` reads.

### Phase 2 — Populate at the reconcile producer (3 sites)

`apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — add
`workspace_id: ws.id` to each `appendKbSyncRow(ownerId, {…})` object literal inside the
`for (const ws of rows)` loop:

- Line ~262 — `skip-not-ready` row (`ok: false`, `error_class: ERROR_CLASS_WORKSPACE_NOT_READY`).
- Line ~292 — `sync-failed` row (`ok: false`, `error_class: ERROR_CLASS_SYNC_FAILED`).
- Line ~307 — `ok: true` row.

`ws.id` is the workspace id from the fan-out loop (the same id used in
`workspacePathForWorkspaceId(ws.id)` and the `reconcile-${ws.id}` step name). No new query,
no new variable.

### Phase 3 — Leave the manual route AS-IS (documented decision)

`apps/web-platform/app/api/kb/sync/route.ts` — **no code change.** Add NOTHING. The route's
two `appendKbSyncRow(userId, {…})` rows stay `workspace_id`-free. The omission is intentional:
the route resolves the workspace by `users.workspace_path` and never holds a `workspace_id`.
A one-line comment near the call site MAY note this for the next reader, but no `workspace_id`
value is fabricated (fabricating one would require an extra `workspace_members` query for zero
present-day benefit — the consumer doesn't read the field yet).

### Phase 4 — Extend the reconcile test

`apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` — the test
already mocks `appendKbSyncRow` via `appendKbSyncRowSpy` and maps `workspace_id → owner
user_id` (line 29, 55). Extend the existing ok:true assertion (and one failure-path
assertion) to assert `expect.objectContaining({ workspace_id: <the iterated ws id> })`. Use
the workspace id already present in the test fixture — do NOT invent a new fixture row.

## Files to Edit

- `apps/web-platform/server/session-sync.ts` — Phase 1, add optional `workspace_id?: string` to `KbSyncRow`.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — Phase 2, add `workspace_id: ws.id` at 3 call sites.
- `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` — Phase 4, assert the discriminator.

## Files to Create

- None. No migration (JSONB column already exists; additive optional field rides inside the existing `p_row jsonb` RPC argument). No new test file (extend the existing reconcile test). No new component.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open --json number,title,body` cross-checked
against the 3 edited paths — no open scope-out names `session-sync.ts`,
`workspace-reconcile-on-push.ts`, or the reconcile test. The `/work` phase should re-run the
check after the file list is final per plan Phase 1.7.5.)

## Type-Widening Cross-Consumer Sweep (hr-type-widening-cross-consumer-grep)

`KbSyncRow` is widened. Every consumer of the type or the `kb_sync_history` array was grepped
and classified (all inert to an added **optional** field):

| Consumer | Reads | Effect of new optional field |
| --- | --- | --- |
| `components/kb/kb-sync-status.tsx` | `"ok" in row`, `row.at`, `row.ok`, `error_class` | inert — discriminates on `ok`; ignores unknown keys |
| `lib/analytics.ts` | filters for legacy `.count` rows | inert — `workspace_id` rows lack `.count`, already excluded |
| `cron-workspace-sync-health.ts` (arm 2 + arm 3) | `history.at(-1)`, `"ok" in latest`, `latest.at` | inert — does not read `workspace_id` (future per-workspace reader is out of scope) |
| `app/api/kb/sync/route.ts` | writes rows (Phase 3, no read) | inert — optional field, omitted by design |
| `test/server/kb-sync-route.test.ts` | `objectContaining({ trigger, ok })` partial | inert — partial matcher |

Because the field is **optional**, no consumer requires an exhaustiveness update; this is a
strict additive widening, not a discriminated-union member addition.

## Non-Goals / Out of Scope

- **NG1 — No consumer read of `workspace_id`.** This is foundations only. A per-workspace
  went-quiet scan (which would `history.filter(r => r.workspace_id === targetWsId)` and probe
  each workspace's own repo rather than the single `users.repo_url`) is **future work**, not
  this PR. Writing the field now unblocks that future work without shipping a half-wired
  reader. → Tracked: see Deferral Tracking below.
- **NG2 — No backfill of historical rows.** Old rows stay `workspace_id`-free by design;
  "missing → legacy-single-workspace" is the contract. No backfill migration.
- **NG3 — No DDL migration.** `kb_sync_history` is JSONB; an optional field needs no schema
  change. The `append_kb_sync_row` RPC is unchanged (the field rides inside `p_row`).
- **NG4 — Manual route gets no `workspace_id`.** Resolving one would require an extra
  `workspace_members` query for zero current consumer benefit (NG1). Deliberate per Research
  Reconciliation row 4.

## Deferral Tracking

The per-workspace went-quiet **reader** (NG1) is deferred. It is the natural successor to
this foundations PR and to #4717's re-eval criterion (a) ("multiple users own ≥2
ready+installed workspaces"). At `/work` time, file a tracking issue: *"feat(kb-sync):
per-workspace went-quiet reader — filter kb_sync_history by workspace_id and probe each
workspace's repo"*, with re-evaluation criterion = "≥1 owner has ≥2 ready+installed
workspaces" (the live trigger; the brainstorm's `skippedMultiWorkspace` counter does not
exist). Milestone: per `knowledge-base/product/roadmap.md` (Post-MVP / Later unless a KB
phase fits). Note: #4728 itself is closed by THIS PR — the reader is a NEW deferral, not a
re-open of #4728.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal data-shape change on an ops-internal JSONB
column, no user-facing surface, no infra, no regulated-data surface. (Engineering domain is
the implementing domain, not a cross-domain reviewer.)

## Infrastructure (IaC)

Skipped — pure code change against an already-provisioned surface. No new server, service,
secret, vendor, cron, or persistent runtime process. Edits are confined to
`apps/web-platform/server/`, `apps/web-platform/app/api/`, and `apps/web-platform/test/`.

## Observability

```yaml
liveness_signal:
  what: existing cron-workspace-sync-health Sentry heartbeat (unchanged)
  cadence: daily (cron "23 6 * * *")
  alert_target: Sentry monitor slug cron-workspace-sync-health
  configured_in: apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts
error_reporting:
  destination: Sentry via reportSilentFallback (existing appendKbSyncRow try/catch — unchanged path)
  fail_loud: best-effort by design (kb_sync_history is non-critical telemetry); RPC errors already mirror to Sentry (op="appendKbSyncRow")
failure_modes:
  - mode: malformed workspace_id in JSONB row
    detection: tsc --noEmit (compile-time) + reconcile test objectContaining assertion (AC4)
    alert_route: CI (pre-merge); no runtime alert needed (reader-inert field)
  - mode: workspace_id absent on a reconcile row (regression)
    detection: AC2 grep (=3) + reconcile test assertion
    alert_route: CI (pre-merge)
logs:
  where: existing Inngest function logs (logger.info in cron) + Sentry breadcrumbs; no new log line
  retention: unchanged (Sentry/Inngest defaults)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/workspace-reconcile-on-push.test.ts"
  expected_output: "test asserting workspace_id: <wsId> on reconcile rows passes (no ssh)"
```

This change adds NO new runtime observability surface (it is a reader-inert field on an
existing JSONB column). The discoverability test is the targeted vitest run that proves the
producer writes the discriminator.

## Test Scenarios

1. **Reconcile ok:true row carries `workspace_id`.** Push webhook fans out to a workspace
   `ws.id = W`; the ok:true `appendKbSyncRow` call includes `workspace_id: W`. (Extend
   existing test.)
2. **Reconcile failure rows carry `workspace_id`.** skip-not-ready and sync-failed rows also
   carry `workspace_id: ws.id`. (Extend existing test — at least one failure path.)
3. **Manual route row omits `workspace_id`.** `kb-sync-route.test.ts` still passes with its
   `objectContaining({ trigger: "manual", ok })` matcher; no `workspace_id` key is required
   or present.
4. **Type compiles.** `tsc --noEmit` green — optional field, all existing call sites valid.

## Risks & Mitigations

- **Risk: making the field required.** Would break the 2 manual-route call sites and imply
  every legacy row is invalid. → Mitigation: field is `workspace_id?:` (optional). Enforced
  by AC1.
- **Risk: fabricating a `workspace_id` for the manual route.** Tempting for "completeness,"
  but the route has no workspace id in scope and the consumer doesn't read the field. →
  Mitigation: explicit Phase 3 no-op + AC3 (grep returns 0). Backfill-tolerant semantics
  ("missing → legacy-single-workspace") make the omission correct, not a gap.
- **Risk: precedent drift on `ws.id`.** → Mitigation: `ws.id` is the exact id already used
  for `workspacePathForWorkspaceId(ws.id)` and `reconcile-${ws.id}` in the same loop body;
  no new resolution.

### Precedent-Diff Gate (deepen-plan Phase 4.4)

**Pattern: adding an optional field to the `KbSyncRow` JSONB row shape.** Not novel — the
`KbSyncRow` type grew `error_class?`, `push_received_at?`, `sha_before?`, and `sha_after?` the
same additive-optional way (all introduced in #4224, `session-sync.ts:327`). The append path
is unchanged: the new field rides inside the `append_kb_sync_row` RPC's `p_row jsonb` argument
(migration 053), which `jsonb`-stores whatever object it receives. No DDL precedent needed
(JSONB column, migration 017). **Conclusion:** strict additive-optional precedent exists in
the same type; the change follows it verbatim. No `SECURITY DEFINER`/atomic-write/lock
precedent applies (the RPC is untouched).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold =
  none with a sensitive-path scope-out reason.)
- **`workspace_id` is in scope ONLY in the reconcile producer.** The feature description's
  phrasing ("the workspace id is already in scope") is true for `workspace-reconcile-on-push.ts`
  but NOT for the manual `/api/kb/sync` route — the manual route is users-centric and resolves
  by `workspace_path`. Do not "fix" the manual route by adding a workspace lookup; that is
  out of scope and reader-unused (see NG4 / Research Reconciliation row 4).
- **`kb_sync_history` is a JSONB array on `public.users`, not a table.** "Add a field to each
  row" means widening the TS type and the producer object literal — there is NO `ALTER TABLE`
  and NO migration. The append goes through the `append_kb_sync_row` RPC unchanged; the new
  field is carried inside the existing `p_row jsonb` argument.
- **The went-quiet consumer reads `history.at(-1)`, not a per-workspace filter.** This PR does
  NOT change that. With this field written, a future reader can switch to
  `history.filter(r => r.workspace_id === targetWsId).at(-1)` — but that reader is NG1
  (deferred). Shipping the field without the reader is the intended foundations split.
