---
date: 2026-09-30
topic: inbox-bulk-archive
branch: feat-inbox-bulk-archive
pr: 9283
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Bulk archive for `/dashboard/inbox`

## What We're Building

Checkbox multi-select + Select-all + a bulk "Archive selected" action bar on the
dashboard inbox (`/dashboard/inbox`), Active tab only. Today archiving is per-row
only; the operator's inbox accumulates GOOD TO KNOW items (Sentry alerts,
completion notices) that can only be cleared one click at a time.

In scope:

- A checkbox on each rendered row. **Unarchivable rows get a disabled checkbox
  with a reason** (mirrors the existing disabled-Archive-button + tooltip
  pattern): statutory email rows (`pinned`), un-acted `action_required` inbox
  items, and acknowledged email rows (the `set_email_triage_status` matrix has
  no `acknowledged → archived` transition).
- A per-section "Select all" covering all **archivable rendered** items in that
  group. The `+N more need you` overflow rows are unrendered and unreachable —
  selection is defined as "visible rows only."
- A bulk action bar (visible when ≥1 selected): `Archive N selected` →
  confirmation dialog → `POST /api/inbox/bulk-archive` → per-item results →
  SWR `mutate()` on `swrKeys.inbox("active")` and `swrKeys.inbox("archived")`
  (list + nav badge reconcile together per ADR-067's shared-key contract).
- Confirmation copy: "Archive N items? They'll stay in the Archived tab —
  nothing is deleted." Result copy reports skips honestly:
  "Archived N. M items can't be archived until handled."

Explicitly out of scope (see Non-Goals): an unarchive/restore lifecycle
(deferred — follow-up issue), bulk controls on the Archived tab, any change to
the NEEDS YOU act flow, the email detail page, and client-side fan-out over the
existing `[id]` routes (rejected — self-inflicted 429 past 60 same-kind items).

## Why This Approach

A single `POST /api/inbox/bulk-archive` route looping the **existing** RPCs
(`set_inbox_item_state`, `set_email_triage_status`) server-side keeps the
archive-guard and per-row authz single-sourced, spends one 60/min rate-limit
budget for any N, and yields per-item outcomes naturally. Best-effort semantics
(`{archived, skipped, failed}` per item) fit the existing 409-as-reconcile
contract — a guarded row under Select-all is an *expected* member of the set,
not a batch failure. A new array-param RPC was rejected: it re-implements the
authz loop, needs rls-fuzz classification + a down migration, and buys
atomicity the per-item model deliberately doesn't want.

## User-Brand Impact

- **Artifact:** the bulk "Archive selected" action on `/dashboard/inbox`.
- **Vector:** a one-click sweep irreversibly archives the operator's
  compliance-adjacent inbox items; a silently-skipped statutory or
  action-required row misrepresents what happened to it.
- **Threshold:** `single-user incident`.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Selection model | **Checkbox per rendered row; disabled-with-reason on unarchivable rows** (CPO) | Disabled state communicates the protection boundary; hidden checkboxes make Select-all math opaque; selectable-but-blocked converts a discoverable rule into an error toast. |
| Select-all scope | **Per-section, archivable rendered items only** | NEEDS YOU select-all would select mostly non-archivable rows and can never reach overflow items — a control promising "all" that delivers "some" is a footgun at single-user-incident threshold. |
| Endpoint shape | **`POST /api/inbox/bulk-archive`, kind-partitioned payload `{inboxIds, emailIds}`, server-side loop over existing RPCs** (CTO) | Reuses pinned authz + archive-guard verbatim; one 60/min budget; per-item results natural. Two tables, two RPCs, two authz models — never merge ids into one array. |
| Partial failure | **Best-effort + per-item outcome** (`archived\|guarded\|not_found\|conflict`), collapse 404/409 per-item to preserve the no-existence-oracle property | 409 is already treated as "transitioned elsewhere → reconcile" by the rows; an expected guard hit must not fail the batch. |
| Statutory protection | **UI exclusion + server-side re-check of eligibility per id** (CLO blocking-for-ship) | `set_email_triage_status` has no statutory check — protection today is UI-only. The bulk route must re-derive `statutory_class === null` per email id, not trust the client selection (state can change between render and click). |
| Confirmation | **Confirm dialog, mandatory** (operator decision) | Archive is irreversible — no unarchive exists. Codebase's own standard confirms single action_required archives; bulk without confirm is a regression from it. |
| Wording | **"Archive N selected"; "They'll stay in the Archived tab — nothing is deleted"; never "Delete/Remove/Clear/Dismiss"; never promise undo/restore** (CLO) | "Archived" must not imply erasure (Art. 17); copy must not promise a reversibility that doesn't exist. |
| Result copy | **"Archived N. M items can't be archived until handled."** (CLO mandatory) | A blanket success after a silent skip misrepresents what happened to a statutory item and hides the residual action-required count. |
| Selection state | **Client-only `Set<kind:id>` in `InboxSurface`**; cleared on tab switch and successful submit (CTO) | Kind-tagged keys needed for payload routing; ephemeral state has no deep-link value. |
| Undo posture | **Confirm-only; unarchive deferred to follow-up issue** (operator decision, CPO option B) | Per CPO, minimum bar for an irreversible bulk action; unarchive is a lifecycle change needing its own CLO retention-semantics review. |
| Checkbox/keyboard | **stopPropagation on checkbox click + keydown** (CTO) | Rows are `role="button"` with Enter/Space → navigate; a nested checkbox's Space would bubble and navigate. |
| Pending/error UX | **One `usePendingAction` episode for the batch; `role="alert"` error line; `Button` primitive** (ADR-255 contract) | Double-submit-safe, 30s Sentry watchdog; no raw `<button>`; checkboxes are `<input>` (outside the sentinel). |
| Observability | **Bulk-route failure mirrored to Sentry** (`reportSilentFallback`); visible error+retry state | `cq-silent-fallback-must-mirror-to-sentry`; mirrors the surface's existing fetch-error posture. |
| Visual design | `.pen` wireframe — see `knowledge-base/product/design/app-ui/` | `wg-ui-feature-requires-pen-wireframe`; Phase 3.55 output. |

## Open Questions

- **DB-level statutory guard on `set_email_triage_status`** (CLO recommended,
  defense-in-depth): mirror mig 122's archive-guard so the RPC rejects
  `archived` when `statutory_class IS NOT NULL`. Deferred to plan-time — it
  pulls a migration + `test/rls-fuzz/rpc-cases.ts` classification into scope.
  If deferred, the UI exclusion + server-side per-id re-check is the minimum
  acceptable posture and the deferral must be recorded.
- `(out of scope)` **Unarchive lifecycle** — tracked in #9285.
  filed as #9285.
- `(out of scope)` Bulk controls on the Archived tab (un-archive semantics,
  statutory re-pinning) — needs its own review.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

Archive is one-way terminal everywhere in the inbox — no unarchive exists for
`inbox_item` or `email_triage_items` (conversations' unarchive is a different
surface). Disabled checkboxes (not hidden, not selectable-but-blocked) are the
correct communication of the protection boundary; Select-all should be
per-section and honest about covering only archivable rendered rows. Bulk
without a confirm would regress below the codebase's own single-item
action_required archive standard. Minimum bar: confirm dialog; recommended
(and deferred by operator decision): ship unarchive in the same PR.

### Legal (CLO)

The statutory non-archive protection is **UI-only** — `set_email_triage_status`
would archive a `new` statutory row today. Bulk raises the stakes: exclusion
from checkbox/Select-all plus a server-side per-id re-check is **blocking for
ship**; a DB-level guard mirror is recommended defense-in-depth (deferral must
be recorded). Copy: retention clause on the confirm; explicit skipped-count on
the result; no delete verbs; no undo promises. GDPR gate applies if a new API
route or migration lands — expected advisory/low (no new data category,
recipient, or retention change; existing operator-inbox PA covers the store).

### Engineering (CTO)

Both write RPCs are single-id; direct table writes are impossible (REVOKE +
WORM trigger + GUC), so a bulk path is net-new either way. Recommended shape:
thin `POST /api/inbox/bulk-archive` → `server/` handler looping the existing
RPCs with per-item outcome mapping. Watch the checkbox↔row-navigation event
collision (stopPropagation), add any new `server/` module to
`inbox-no-service-client.test.ts`'s `SERVER_MODULES` allowlist, and keep the
route file POST-only exports (`cq-nextjs-route-files-http-only-exports`).
WAL is negligible (operator-initiated, ≤~200 rows/click). Complexity:
small-to-medium (~1–2 days).

## Capability Gaps

- **Unarchive lifecycle action** (Engineering + Legal): no `unarchive`/`restore`
  transition exists in `set_inbox_item_state` or `set_email_triage_status`, and
  no Archived-tab restore affordance. Needed if a future brainstorm ships undo;
  the reversal touches retention semantics and needs CLO review. Deferred to a
  follow-up issue per operator decision.

## Session Errors

None.
