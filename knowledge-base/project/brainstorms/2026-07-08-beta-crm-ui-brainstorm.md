---
date: 2026-07-08
topic: beta-crm-ui
issue: 6172
epic: 6177
depends_on_shipped: [6160]
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: in-Soleur UI surface for the beta-CRM (over the store's API)

## What We're Building

A **read-only pipeline board** inside the Soleur dashboard (`/dashboard/crm`) that renders
the already-live, owner-private beta-CRM store (migration 126, ADR-102, shipped in PR #6160).
The store is agent-only today — 7 in-process MCP tools in `crm-tools.ts`. The browser cannot
call in-process MCP tools, so the UI gets its own thin `app/api/crm/*` route surface.

**v1 scope (decided):**
- `GET /api/crm/contacts` → a **pipeline board** grouping contacts into stage columns
  (reusing the existing Workstream kanban machinery).
- A **read-only contact detail drawer** (`?contact=<id>` deep-link) showing the dual-lens
  `interview_notes` timeline and the `beta_contact_stage_transitions` velocity history.
- A **funnel / analytics view** as a `Board | Funnel` toggle on the same `/dashboard/crm` route:
  count-based stage conversion + drop-off + average time-in-stage (velocity), served by a small
  `GET /api/crm/funnel` aggregation route (counts/timings only — no note bodies). **Count-based,
  NOT weighted-dollar forecasting** (that stays deferred per CFO / NG4).
- An **operator-read audit** event on contact/note view (`{ op:'view', userId, contactId, ts }`)
  for GDPR Art. 5(2) accountability — **included in v1** by operator decision.
- Nav registered as a dashboard sibling of inbox/kb/chat/workstream.

**Explicitly NOT in v1:** no create/edit/drag-to-stage, no write routes for contact content,
no self-serve erase. Editing stays conversational via the agent (which already does it well).

## Why This Approach

All five brainstorm inputs (CPO, CLO, CTO, repo-research, learnings) converged independently
on **read-only first**:

- **The visual surface's real value is the one job conversation is structurally bad at:**
  at-a-glance pipeline shape, bulk scanning across contacts, spatial recall. Editing is *not*
  a differentiator — the agent already edits well conversationally. Building CRUD would spend
  days duplicating agent capability for an audience of one (the operator). (CPO)
- **Read-only = near-zero new attack surface:** one authed `GET` over the existing
  RLS-owner-scoped SELECT. No write route means no write-authz question, no CSRF surface,
  no within-tenant prompt-injection vector to defend. (CTO + learnings)
- **The heavy machinery already exists in-repo:** `WorkstreamBoard` / `IssueColumn` /
  `IssueDetailSheet` are a portable kanban (columns, collapse, accent tints, count pills,
  SWR fetch, drawer, URL-param deep-link). The board is a reskin of a proven surface, not a
  new design language. (repo-research)

## User-Brand Impact

- **Artifact:** the in-Soleur CRM UI surface — `app/api/crm/*` routes + `/dashboard/crm`
  read-only pipeline board — over the owner-private mig-126 store.
- **Vector:** third-party beta-tester PII (names, companies, conversation-note bodies) leaked
  to the browser network tab / a client-side error reporter via a raw Postgres error, or
  exposed to the wrong tenant through a mis-authz'd route.
- **Threshold:** `single-user incident`.

Kept at `single-user incident` (fail-safe) despite the read-only narrowing — the data is
third-party PII. Note the read-only surface has **no Art. 33 notifiable write event**; the
risk is disclosure-via-error-leak and wrong-tenant-read, not data corruption.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Read-only board for v1**; editing stays conversational | Scan/overview is conversation's one weak spot; editing isn't a UI differentiator; CRUD duplicates agent capability (CPO/CTO). |
| 2 | **Reuse the mig-126 SECURITY DEFINER RPCs** for any future writes; do NOT add a route-level authz path | authz lives inside the RPCs (auth.uid()-pinned, FOR UPDATE, uniform 42501). RLS-through-route physically can't write (no INSERT/UPDATE/DELETE policy). (CTO/CLO) |
| 3 | **New `app/api/crm/*` routes are default-authed** — do NOT register in `PUBLIC_PATHS` | Everything not in PUBLIC_PATHS inherits the middleware auth gate; use the existing `withUserRateLimit` wrapper. (CTO/repo) |
| 4 | **PII-safe error discipline is merge-blocking** on the routes | Raw PG errors carry third-party PII in `details`/`message`; a browser route is *more* dangerous than the agent path (error reaches the client). Read SQLSTATE only, map to stable semantic code, return PII-free body, mirror only `{op,userId,code}` to Sentry. Factor the agent's mapper into a shared `server/crm/` module both surfaces import. (CLO/CTO/learnings) |
| 5 | **Detail = right-side drawer** (Workstream `IssueDetailSheet` pattern), `?contact=<id>` deep-link | Instant toggle + deep-linkable; reuses proven component; lighter than a route-based detail page. (repo) |
| 5a | **Funnel view in v1** as a `Board \| Funnel` toggle; count-based conversion + velocity via `GET /api/crm/funnel` | The stage-transition table is already the velocity source; read aggregation with LESS PII than the board (counts/timings, no note bodies). Weighted-$ forecasting stays deferred (NG4) — honest about thin data at beta volume. (operator decision) |
| 6 | **Board imports `STAGES` from `stage-probability.ts`** — never re-declare the enum | Single source of truth, drift-guarded against the migration CHECK. (CTO) |
| 7 | **Operator-read audit included in v1** | GDPR Art. 5(2) accountability from day one — a browser board renders full note bodies at a glance (operator decision). Sink choice is an Open Question. |
| 8 | **No self-serve erase in v1**; `crm_erase_contact` stays service-role-only | Erasure is high-blast-radius (must reconcile mutable head + append-only history redaction). A UI "flag for erasure" request routing to the operator-attested path is the compliant shape when needed. (CLO) |
| 9 | **Nav** = `/dashboard/crm` sibling, one line in `components/command-palette/nav-items.ts` + icon in `(dashboard)/layout.tsx` | Single source of truth; no drift. (repo) |
| 10 | **No new ADR** — reuses ADR-102's authz boundary | A plan note "UI reuses ADR-102 SECURITY DEFINER RPCs" suffices; the `webapp -> crmStore` C4 edge (reserved in ADR-102 §C4) gets added. (CTO) |
| 11 | **Visual design:** `.pen` wireframes committed (read-only board, detail drawer, empty state) | `wg-ui-feature-requires-pen-wireframe` — mandatory before markup. |

## Visual Design

Wireframes (`.pen`, mirroring the shipped Workstream kanban's visual language — sibling surface,
not a new design language):

- **Source:** `knowledge-base/product/design/crm/beta-crm-pipeline.pen`
- **Screenshots:** `knowledge-base/product/design/crm/screenshots/`
  - `01-crm-pipeline-board.png` — pipeline board (7 stage columns in `stage-probability.ts` enum
    order; Closed Lost shown collapsed to demonstrate the column-collapse affordance; cards show
    company/person/value — **no note bodies**, honoring the PII constraint).
  - `02-crm-contact-detail-drawer.png` — 460px right sheet: dual-lens note timeline + stage-history
    velocity timeline + read-only hint pointing edits back to the CRO/CPO agent.
  - `03-crm-empty-state.png` — zero-contact prompt (contacts captured via agent conversations).

Two flagged deviations (both intentional, sibling-fidelity over aspirational tokens): rounded
corners matching the *shipped* Workstream board (not the brand guide's 0px), and a 2160px board
frame so all 7 stages show at once (a true 1440 viewport scrolls the last ~1.5 columns, same as
Workstream).

## Open Questions (for the plan)

1. **Read-audit sink** — reuse an existing audit sink vs a new minimal `beta_contact_access_log`
   table + a SECURITY DEFINER insert RPC (mirroring the mig-126 write-RPC pattern). Probe found
   only domain-specific audit migrations (kb files, WORM, ownership) — no general record-view
   sink exists. **Recommendation:** minimal new table + insert RPC, kept append-only, so the read
   log inherits the same owner-private + RPC-only-write posture as the rest of the store.
2. **Read-audit granularity** — log on board load (list view = many contacts) or only on drawer
   open (single-contact detail view = the actual note-body exposure)? Drawer-open is the higher-signal,
   lower-noise event; board-load reveals only company/name.
3. **CSRF re-engagement trigger** — the read-audit write means v1 is not purely render-only. If the
   audit event is emitted via a GET side-effect it avoids the CSRF-on-POST concern, but if it becomes
   a separate POST, the CSRF three-layer defense + `csrf-coverage.test.ts` gate applies. Decide the
   audit-emit shape so the security posture is intentional.
4. **RLS-policy staleness re-sweep** — re-run the RLS/RPC-access enumeration against HEAD at
   PR-author time (sibling branches can land new authenticated policies mid-flight). (learnings #3)
5. **Agent-native parity check** — before launch, confirm the board surfaces a contact the agent
   already manages (one known-good record), so UI and agent read the same store consistently.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
**Participated (triad, mandatory under USER_BRAND_CRITICAL):** Product, Legal, Engineering.

### Product (CPO)
**Summary:** Keep deferred by its own labels (p3-low, operator-only); when built, ship the
read-only pipeline board only — scan/overview is conversation's one structural weak spot,
editing is not; CRUD is low-value duplication for an audience of one; nav as a dashboard sibling.

### Legal (CLO)
**Summary:** UI over third-party PII adds accountability duties (operator-read audit — mig-126
logs writes only) but no new legal basis; PII-safe-error discipline is a merge-blocking invariant
on `app/api/crm/*`; writes MUST re-call the existing SECURITY DEFINER RPCs (operator edits are
inherently reviewed — no R3 UI analogue needed); keep erasure service-role-only with head +
append-only redaction semantics — no self-serve erase button in v1.

### Engineering (CTO)
**Summary:** Reuse migration-126 RPCs via `getFreshTenantClient` (one authz boundary,
default-authed — no PUBLIC_PATHS), factor the PII-safe SQLSTATE→`reportSilentFallback` mapper
into a shared `server/crm/` module, import `stage-probability.ts`; ship read-only board first
(SMALL/LOW risk), writes as a second slice. No new ADR — reuses ADR-102's boundary.

## Capability Gaps

None blocking. One build-phase flag (not a missing agent/skill): there is **no read-audit
primitive today** (migration 126 logs writes only) — evidence: `git grep -lE "audit_log|read_audit|access_log"`
over `apps/web-platform/supabase/migrations/*.sql` returns only domain-specific sinks
(kb-files RLS audit, WORM bypass, ownership transfer), none a general record-view log. Adding the
read-audit (Decision 7) needs a CTO-owned schema/logging decision (Open Question 1), not a new tool.

## Deferred Siblings (epic #6177, not in this slice)

- **#6171** — tester-visible records / agent-user parity
- **#6173** — workspace-shared visibility
- **#6174** — USD normalization
- **#6175** — field-level mutable-head audit

## Gates a UI plan will trigger

- **Wireframes mandatory** (`wg-ui-feature-requires-pen-wireframe`) — `.pen` from `ux-design-lead`
  (produced in this brainstorm; see Visual Design).
- **`webapp -> crmStore` C4 edge** (ADR-102 §C4 reserved this for the UI phase).
- **Structural-UI QA gate** re-engages on `app/(dashboard)/**` diff.
- **New `app/api/crm/*` route** → middleware auth (default; no PUBLIC_PATHS) + route tests +
  `cq-nextjs-route-files-http-only-exports` compliance.
