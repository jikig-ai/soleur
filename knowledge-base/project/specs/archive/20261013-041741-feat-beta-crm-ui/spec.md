---
feature: beta-crm-ui
issue: 6172
epic: 6177
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-07-08
brainstorm: knowledge-base/project/brainstorms/2026-07-08-beta-crm-ui-brainstorm.md
adr: ADR-102
depends_on_shipped: [6160]
---

# Spec: in-Soleur UI surface for the beta-CRM (read-only pipeline board)

## Problem Statement

The beta-CRM store (migration 126, ADR-102, shipped PR #6160) is agent-only: 7 in-process MCP
tools expose read/write over three owner-private Supabase tables. The operator can manage
contacts conversationally but has **no at-a-glance view** of the pipeline — the one job
conversation is structurally bad at (pipeline shape, bulk scanning, spatial recall). The browser
cannot call in-process MCP tools, so surfacing this data visually requires a dedicated
`app/api/crm/*` route layer plus a dashboard board.

## Goals

- G1. Render the beta-CRM pipeline as a **read-only board** at `/dashboard/crm`, grouped by stage.
- G2. Let the operator drill into a contact via a **read-only drawer** showing the dual-lens note
  timeline and stage-transition (velocity) history.
- G2a. Offer a **read-only funnel/analytics view** (Board | Funnel toggle) showing count-based
  stage conversion + drop-off + velocity.
- G3. Emit an **operator-read audit** event for GDPR Art. 5(2) accountability.
- G4. Reuse the existing authz boundary (ADR-102 RPCs / RLS) — introduce **no new authz surface**.
- G5. Reuse the existing Workstream kanban UI machinery — introduce no new design language.

## Non-Goals

- NG1. No create/edit/drag-to-stage or any contact-content write path in v1 (editing stays
  conversational via the agent).
- NG2. No self-serve erase; `crm_erase_contact` stays service-role-only.
- NG3. No workspace-shared / tester-visible views (deferred siblings #6173 / #6171).
- NG4. No weighted-forecasting TS consumer (deferred; CFO: forecasting is theater at 0 deals).

## Functional Requirements

- **FR1.** `GET /api/crm/contacts` returns the owner's contacts (RLS-owner-scoped SELECT via
  `getFreshTenantClient(user.id)`), shaped for board grouping (id, company, person, stage, value).
  Default-authed (not in `PUBLIC_PATHS`); wrapped in `withUserRateLimit`. → wireframe: board.
- **FR2.** `/dashboard/crm` renders a pipeline board: one column per stage (imported from
  `stage-probability.ts`), contact cards with company/person/value, count pill per column.
  Reuses `WorkstreamBoard`/`IssueColumn`/card patterns. → wireframe: board.
- **FR3.** Clicking a card opens a **read-only** right-side drawer (`?contact=<id>` deep-link,
  `IssueDetailSheet` pattern) showing: contact head, `interview_notes` dual-lens timeline,
  `beta_contact_stage_transitions` velocity history. → wireframe: detail drawer.
- **FR4.** Empty state: a board with zero contacts explains contacts are captured via agent
  conversations. → wireframe: empty state.
- **FR4a.** A `Board | Funnel` segmented toggle on `/dashboard/crm`. The **Funnel** view renders a
  count-based conversion funnel (one bar per stage in `stage-probability.ts` order, count +
  stage-to-stage conversion %), Closed Lost as a separate terminal branch, and an average
  time-in-stage velocity stat. **No weighted-dollar forecasting** (deferred, NG4). No note bodies.
  → wireframe: funnel.
- **FR4b.** `GET /api/crm/funnel` returns the aggregation (per-stage counts + conversion + avg
  time-in-stage from `beta_contact_stage_transitions`). Aggregates server-side — returns
  counts/timings only, never note bodies or contact PII beyond what the funnel renders.
  Default-authed; `withUserRateLimit`.
- **FR5.** A **read-audit** event `{ op:'view', userId, contactId, ts }` is emitted on the
  higher-signal view event (drawer open — see TR4). Append-only, owner-private.
- **FR6.** Nav: a "CRM" item in `components/command-palette/nav-items.ts` + icon in
  `(dashboard)/layout.tsx`.

## Technical Requirements

- **TR1. One authz boundary.** Any future write reuses the mig-126 SECURITY DEFINER RPCs
  (`crm_contact_upsert` / `crm_note_append` / `crm_contact_set_stage`) via the tenant client.
  No route-level authz path; no owner-write RLS policy (that is itself a bypass).
- **TR2. PII-safe errors (merge-blocking).** Routes never forward raw Postgres `details`/`message`
  to Sentry or the HTTP response body. Read SQLSTATE only → map to a stable semantic code → return
  a PII-free body → mirror only `{ op, userId, code }` to Sentry. **Factor the agent's mapper
  (`crm-tools.ts` + `lib/postgres-errors.ts` + `reportSilentFallback`) into a shared `server/crm/`
  module both surfaces import** (no divergent scrubbers).
- **TR3. Route hygiene.** `route.ts` exports only HTTP handlers (`cq-nextjs-route-files-http-only-exports`);
  column lists / validators live in sibling modules. Add a route test (note: the http-only-exports
  validator runs only in `next build`, not vitest/tsc).
- **TR4. Read-audit sink (OPEN — plan decision).** Reuse an existing audit sink vs a new minimal
  `beta_contact_access_log` table + SECURITY DEFINER insert RPC. Recommendation: new minimal table
  + insert RPC (append-only, owner-private, RPC-only-write — same posture as the store). Emit on
  drawer-open (single-contact note-body exposure), not board-load. If emitted as a POST rather than
  a GET side-effect, the CSRF three-layer defense + `csrf-coverage.test.ts` gate applies.
- **TR5. Stage enum.** Board imports `STAGES` from `server/crm/stage-probability.ts`; never re-declares.
- **TR6. RLS-policy re-sweep.** Re-run the RLS/RPC-access enumeration against HEAD at PR-author time.
- **TR7. C4 edge.** Add the `webapp -> crmStore` edge (ADR-102 §C4 reserved it for this phase). No new ADR.

## Acceptance Criteria

- Board renders all owner contacts grouped by stage; empty state shows when none.
- Drawer shows note timeline + stage history, read-only, deep-linkable via `?contact=<id>`.
- No raw Postgres error text reaches the browser or Sentry (verified by a negative test).
- Read-audit row written on drawer open.
- Agent-native parity: a contact the agent manages appears identically on the board.
- Wireframes (`.pen`) committed and referenced.

## Wireframes

See brainstorm Visual Design section — `.pen` under `knowledge-base/product/design/`.
