---
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 9284
branch: feat-inbox-bulk-archive
pr: 9283
brainstorm: knowledge-base/project/brainstorms/2026-09-30-inbox-bulk-archive-brainstorm.md
wireframes: knowledge-base/product/design/app-ui/inbox-bulk-archive.pen
---

# Feature: Bulk archive for `/dashboard/inbox`

## Problem Statement

`/dashboard/inbox` renders the operator's merged inbox — `inbox_item` rows plus
`email_triage_items` rows — partitioned into NEEDS YOU (`action_required`) and
GOOD TO KNOW (informational). Archive exists **per-row only**
(`inbox-item-row.tsx` › Archive button → `POST /api/inbox/[id]/state`;
`email-triage-row.tsx` › Archive button → `POST /api/inbox/emails/[id]/archive`).
Informational items accumulate (Sentry alerts, completion notices) and can only
be cleared one click at a time.

## Goals

- Checkbox multi-select on inbox rows + per-section "Select all" + a bulk
  "Archive selected" action bar on the Active tab.
- One thin bulk endpoint that reuses the existing single-id RPCs server-side,
  returning per-item outcomes (best-effort, never all-or-nothing).
- Unarchivable rows visibly excluded (disabled checkbox with reason), never
  silently skipped.
- Confirmation copy that satisfies the CLO "archived ≠ erased" posture and
  never promises undo.

## Non-Goals

- Unarchive/restore lifecycle — deferred to follow-up issue #9285; archive remains
  one-way terminal in this PR.
- Bulk controls on the Archived tab.
- A new array-param RPC (`set_inbox_item_state(uuid[], …)` / bulk variant of
  `set_email_triage_status`) — re-implements per-row authz for no benefit; the
  DB stays the per-row authority via the existing RPCs.
- Changes to the NEEDS YOU act flow, the email detail page, or retention.
- Changes to the `new → acknowledged|archived` transition matrix of
  `set_email_triage_status`. (Note: the plan resolved the brainstorm's open
  question — the DB-level statutory guard DOES ship in this PR as migration
  145, folding in what was candidate-deferred; see plan §Technical
  Considerations.)

## Functional Requirements

### FR1: Row selection checkboxes

Each rendered row on the Active tab shows a checkbox (left of the row). Rows
that cannot be archived get a **disabled** checkbox with a reason label/tooltip:

- statutory email rows (`MergedInboxItem.kind === 'email'` with `pinned`)
- un-acted `action_required` inbox items (`severity==='action_required' && acted_at === null`)
- acknowledged email rows (the `new → acknowledged|archived` matrix has no
  `acknowledged → archived` transition)
- Archived tab: no selection UI at all in this PR.

The checkbox is rendered as a SIBLING of the row at the dispatch site (rows
are `role="button"` whose keydown `preventDefault`s bubbled keys — a nested
checkbox's Space would navigate instead of toggle). No `stopPropagation`
needed: its events never traverse the row.

### FR2: Per-section "Select all"

A "Select all" control on its own thin line directly under each group header
(NEEDS YOU / GOOD TO KNOW — operator-approved wireframe placement), selecting
all **archivable rendered** rows in that group. Indeterminate state when a
subset is selected; disabled when a group has no archivable rows. `+N more
need you` overflow rows are unrendered and unselectable — selection is defined
as visible rows only.

### FR3: Bulk action bar

When ≥1 row is selected, a bar shows "N selected" and a `Button` (gold
variant) "Archive N selected". One `usePendingAction` episode for the whole
batch (`loading={pending}`, double-submit-safe). Error renders via `role="alert"`.

### FR4: Confirmation dialog

"Archive N items? They'll stay in the Archived tab — nothing is deleted." with
Cancel / Archive. No "Delete/Remove/Clear/Dismiss" verbs; no undo promises.

### FR5: Bulk endpoint

`POST /api/inbox/bulk-archive` accepting `{items: [{kind: "inbox"|"email", id: uuid}]}`
(≤200, deduped). Route file exports POST only and stays thin — the handler
lives in `server/` and loops `set_inbox_item_state` /
`set_email_triage_status` per id. Server re-derives eligibility per id —
including `statutory_class IS NULL` for email ids — because the client
selection may be stale and the email RPC has no statutory check (mig 145 in
this PR adds the DB-level pin as belt-and-suspenders).

Response: `{results: [{id, kind, outcome}]}` with
`outcome ∈ archived|guarded|not_found|conflict|error` — predicate-ineligible
ids return `guarded` with a reason code (`statutory|needs_action|
already_acknowledged|already_archived`); per-item 404/409 collapse preserves
the no-existence-oracle property of the single-id handlers.

### FR6: Result reporting

On completion: `mutate()` `swrKeys.inbox("active")` and
`swrKeys.inbox("archived")` (list + nav badge share the key per ADR-067).
Result copy reports skips honestly: "Archived N. M items can't be archived
until handled."

Wireframes: `knowledge-base/product/design/app-ui/inbox-bulk-archive.pen`
(screenshots in the sibling `screenshots/` dir) cover the selected-rows state
and the confirmation dialog for FR1–FR4.

## Technical Requirements

### TR1: Minimal DB surface

No new RPC, no signature change to `set_inbox_item_state`
(`test/migration-122-inbox-item.test.ts` regex-pins it). One migration ships:
`145_email_triage_statutory_archive_guard.sql` re-creates
`set_email_triage_status` adding a statutory pin (`archived` rejected when
`statutory_class IS NOT NULL`, `ERRCODE='P0001'`) — resolved at plan time when
the deferral gate classed it inline-sized. The bulk handler calls the existing
RPCs through the user-context client — `createServiceClient` is banned under
`app/api/inbox/**` (`test/inbox-no-service-client.test.ts`; add any new
`server/` handler module to its `SERVER_MODULES` allowlist).

### TR2: Rate limit

Wrap the route in `withUserRateLimit` (feature key `inbox.bulk-archive`,
60/min) — one request regardless of N. Rationale for the single endpoint over
client fan-out: >60 same-kind ids would self-inflict 429s.

### TR3: Guard parity with single-item archive

The bulk path must produce the same outcomes the per-row UI produces:
`action_required` un-acted → guarded; statutory email → excluded (server-side
re-check, since `set_email_triage_status` lacks a statutory guard);
acknowledged email → 409-equivalent skip.

### TR4: Observability

Bulk-route failure mirrors to Sentry via `reportSilentFallback`
(`cq-silent-fallback-must-mirror-to-sentry`); visible error+retry state in the
UI. Sentry-mirrored silent-fallback applies to the fan-out's failure path too.

### TR5: Tests

- Extend handler tests for the bulk route: mixed-eligibility payloads, per-item
  outcomes, 42501→not_found collapse, statutory exclusion enforced server-side.
- Component tests: checkbox disabled states, Select-all archivable-only, bulk
  bar visibility, confirm dialog, result copy, `mutate` on both SWR keys.
- `setupNavMocks` stub for the new endpoint if it fires during e2e shell nav
  (per `2026-06-11-worm-mutation-matrix-and-e2e-harness-mock-for-new-fetches.md`).

## User-Brand Impact

Artifact: the bulk "Archive selected" action on `/dashboard/inbox`. Vector: a
one-click sweep irreversibly archives compliance-adjacent inbox items; a
silently-skipped statutory or action-required row misrepresents what happened.
Threshold: `single-user incident`.

## Domain Review (carry-forward)

- **Product:** disabled checkboxes (not hidden, not selectable-but-blocked);
  Select-all per-section over archivable rendered rows only; confirm dialog is
  the minimum bar for an irreversible bulk action.
- **Legal:** statutory exclusion is blocking for ship — UI exclusion + per-id
  server-side re-check; mandatory skipped-count result copy; no delete verbs,
  no undo promises; gdpr-gate runs at plan Phase 2.7 / work Phase 2 exit (new
  API route lands under the regulated-surface regex).
- **Engineering:** single endpoint looping existing RPCs; per-item outcomes;
  client-only selection state in `InboxSurface`; checkbox↔row-navigation
  stopPropagation; `mutate()` both SWR keys; complexity ~1–2 days.
