---
title: "feat: in-Soleur read-only beta-CRM UI (pipeline board + funnel)"
date: 2026-07-08
type: feat
issue: 6172
epic: 6177
branch: feat-beta-crm-ui
pr: 6239
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-102 (amend)
brainstorm: knowledge-base/project/brainstorms/2026-07-08-beta-crm-ui-brainstorm.md
spec: knowledge-base/project/specs/feat-beta-crm-ui/spec.md
wireframes: knowledge-base/product/design/crm/beta-crm-pipeline.pen
depends_on_shipped: [6160]
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: in-Soleur read-only beta-CRM UI (pipeline board + funnel) 📊

## Overview

Surface the already-live, owner-private beta-CRM store (migration 126 / ADR-102 / PR #6160) as a
**read-only** dashboard UI at `/dashboard/crm`. Today the store is agent-only (7 in-process MCP
tools in `crm-tools.ts`); the browser cannot call in-process MCP tools, so the UI gets its own thin
`app/api/crm/*` GET routes that **reuse the exact same authz boundary** — RLS-owner-scoped reads on
the authenticated **SSR cookie client** (`createClient()` from `@/lib/supabase/server` + `getUser()` — NOT
the agent-impersonation `getFreshTenantClient`), no new authz path. The detail read runs through a
SECURITY DEFINER RPC (`auth.uid()`-pinned) so its `auth.uid()` resolves from the same cookie session.

v1 delivers three surfaces, all read-only (editing stays conversational via the agent):

1. **Pipeline board** — contacts grouped into stage columns, reusing the `WorkstreamBoard` interaction model.
2. **Board | Funnel toggle** — a count-based conversion funnel (cumulative reach + stage-to-stage %) + stage velocity, mirroring the `FunnelSection` bar style from `analytics-dashboard.tsx`.
3. **Contact detail drawer** — dual-lens note timeline + stage-transition history, reusing the `IssueDetailSheet` pattern; opening it emits a GDPR Art. 5(2) operator-**read** audit event.

**Approach chosen (brainstorm, 5-way convergence CPO/CLO/CTO/repo/learnings):** read-only first. The
visual surface's marginal value over the shipped agent capability is *scan/overview* (conversation's
one structural weak spot); editing is not a differentiator, so CRUD would duplicate agent capability
for an audience of one. Read-only = one authed GET over the existing RLS SELECT ≈ near-zero new
attack surface.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "reuse WorkstreamBoard machinery" | `WorkstreamBoard`/`IssueColumn`/`IssueDetailSheet` exist but are **domain-coupled** to `WorkstreamIssue` — no generic board export | Reuse as **pattern/reference** (column layout, instant drawer, `pushState` deep-link, `popstate` sync), reskin into `components/crm/*`. Not a drop-in. |
| "funnel view" (new) | `FunnelSection` in `components/analytics/analytics-dashboard.tsx` (#5049) is a private count-based conversion-bar component | **Mirror its bar style** for visual consistency; do not import (analytics-coupled). |
| "PII-safe mapper factored into shared module" | Mapper is **inline** in `crm-tools.ts:84–114` and translates **write**-constraint SQLSTATEs (unique/FK/check) | **Do NOT extract** (advisor consult): the read routes' error surface is 404-on-empty / 500 — they don't consume the write mapper. Leave crm-tools.ts's mapper untouched; the routes do their own minimal PII-safe error handling (never echo `error.message`/`details`). |
| "new API routes need PUBLIC_PATHS wiring" (issue body) | `app/api/*` and `app/(dashboard)/*` are **authed-by-default**; only `PUBLIC_PATHS` entries bypass | Do **NOT** register in `PUBLIC_PATHS`. Inherit the default gate. |
| stage enum | `stage-probability.ts` exports `STAGES`, `STAGE_PROBABILITY`, `Stage`, `DEFAULT_STAGE`, `SCHEMA_VERSION`; order `[new, contacted, qualified, evaluating, committed, closed_won, closed_lost]` | Board columns + funnel bars `import { STAGES } from "@/server/crm/stage-probability"` — never re-declare. |
| migration apply workflow | `apply-web-platform-migrations.yml` **does not exist**; migrations apply via `web-platform-release.yml#migrate` | Reference the real workflow. Migration 127 applies on merge-to-main via the release pipeline. |
| C4 `webapp -> crmStore` edge | `crmStore`, `webapp`/`api`/`dashboard` containers, `founder`/`betaContact` actors all exist; `engine -> crmStore` exists; **`webapp -> crmStore` edge does NOT** (ADR-102 §C4 reserved it for the UI phase) | Add `webapp -> crmStore` edge + render it (Phase 5). |

## User-Brand Impact

**If this lands broken, the user experiences:** the CRM board renders blank, wrong-tenant, or
error-spews raw Postgres text — the operator loses trust in the surface that shows real
beta-testers' data.

**If this leaks, the user's data is exposed via:** third-party beta-tester PII (names, companies,
conversation-note bodies) leaked to the browser network tab / a client-side error reporter through
a raw Postgres error `details`/`message`, or a mis-authz'd route returning another owner's rows.

**Brand-survival threshold:** `single-user incident`.

> CPO sign-off required at plan time before `/work` begins (carried forward from brainstorm Phase 0.1
> `USER_BRAND_CRITICAL=true`; CPO reviewed the brainstorm and recommended read-only-first).
> `user-impact-reviewer` runs at review-time (review skill conditional-agent block).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** `GET /api/crm/contacts` returns the owner's contacts (RLS-owner-scoped SELECT on the SSR cookie client — `createClient()` + `getUser()`), shaped `{ contacts: [{ id, company, name, role, stage, amount, currency, last_contact }] }`. 401 when unauthenticated. Query inlined in the handler using `CONTACT_COLUMNS` from `crm-reads.ts`. Route file exports only HTTP handlers (`cq-nextjs-route-files-http-only-exports`).
- **AC2.** `GET /api/crm/contacts/[id]` returns `{ contact, notes, transitions }` (head + dual-lens `interview_notes` + `beta_contact_stage_transitions`) via the **atomic** `crm_get_contact_detail(p_contact_id)` RPC (AC3). A missing/erased/foreign `id` returns a **byte-identical** `404 { error: "not_found" }` — no existence oracle (mirrors the RPC's uniform-42501 posture). Verified by a test asserting the never-existed, erased, and cross-owner cases return identical status+body.
- **AC3.** The detail read is **atomic with the read-audit** (advisor consult): one SECURITY DEFINER RPC `crm_get_contact_detail(p_contact_id)` inserts the `beta_contact_access_log` row AND returns the contact/notes/transitions **in the same transaction** — fail-closed: no audit row ⇒ no data. This makes "un-bypassable" an invariant (not aspiration), makes SWR-revalidation duplicate log rows *semantically correct* (each = a real PII re-egress), and neutralizes future prefetch phantom-reads. On RPC error the drawer renders the standard **ErrorCard + Retry** (loud, never silent, never data-without-audit — reconciles spec-flow P0-2's "fail loud" with fail-closed accountability); the error mirrors `{ op, userId, code }` to Sentry (no PII). Verified by a test: RPC throw → route 5xx with a PII-free semantic body (NOT a 200 with data).
- **AC4.** `GET /api/crm/funnel` returns `{ stages: [{ stage, reached, conversionPct|null }], closedLost, avgTimeInStageDays, perTransition }` computed from `beta_contact_stage_transitions` (counts/timings only — **no note bodies, no contact PII beyond stage counts**). `conversionPct` is `null` when the prior stage's `reached < LOW_N_THRESHOLD` (funnel renders "insufficient data", not misleading 0/100%).
- **AC5.** No route forwards raw Postgres `error.message`/`details` to the HTTP body or Sentry. Each route returns a generic PII-free body (semantic string, no server text) + `Sentry.captureException(e, { tags: { surface } })`. (Routes do NOT reuse the write mapper — their error surface is 404-on-empty / 500, per the advisor consult.) Verified by a negative test: a route handler fed a PostgrestError carrying a row-value in `details` returns a body containing no server text and the Sentry mock receives no PII.
- **AC6.** `server/crm/crm-reads.ts` exports ONLY the column-list constants `CONTACT_COLUMNS`/`NOTE_COLUMNS`/`TRANSITION_COLUMNS` (single source, prevents PII-column drift; query builders are inlined in their one consuming route). `crm-tools.ts` imports these constants — the **only** touch to the agent path (write-error mapper untouched). A `crm-reads` self-test asserts the exact column sets (the existing `crm-tools.test.ts` drift-guard covers only the stage enum, NOT the PII columns — architecture P2-4). `crm-tools.test.ts` + all agent-path tests + `tsc` stay green (behavior-preserving).
- **AC7.** `/dashboard/crm` renders a board with one column per stage in `STAGES` order (imported from `stage-probability.ts` — grep asserts no re-declared stage literal in `components/crm/`). **Empty stage columns still render** (spatial recall). Closed Lost renders as a terminal branch (collapsed rail per wireframe).
- **AC8.** Clicking a card opens a read-only right-side drawer, `?contact=<id>` deep-link via `pushState`; `popstate` re-syncs; closing uses `replaceState` (no history spam). Cold direct `?contact=<id>` load fetches the board list underneath so closing lands on a populated board. Toggling to Funnel with the drawer open **closes** the drawer (funnel has no card context).
- **AC9.** `Board | Funnel` toggle switches views on the same route. The toggle **stays interactive** when `/api/crm/funnel` errors so the operator can fall back to Board.
- **AC10.** Every fetch surface (board list, detail drawer, funnel) has a **loading** skeleton, an **error** state rendering only the semantic code + generic copy + a **Retry** (SWR `mutate`) — never raw server text (P0-3), and an **empty** state. Zero-note / zero-transition drawers show explicit empty microcopy.
- **AC11.** A "**edit via your CRO/CPO agent**" hint is present on the board, funnel, and drawer (not the drawer alone) — the read-only escape-hatch so the operator is never dead-ended (P1-5). v1 hint links to `/dashboard/chat` (pre-scoped chat deep-link deferred — see Non-Goals).
- **AC12.** Nav: `{ href: "/dashboard/crm", label: "CRM", seq: "g m" }` added to `NAV_ITEMS` (`components/command-palette/nav-items.ts`) + `"/dashboard/crm": <icon>` added to `NAV_ICONS` (`app/(dashboard)/layout.tsx`).
- **AC13.** Migration `127_beta_crm_access_log.sql` creates `beta_contact_access_log` (append-only, owner-private: SELECT-owner-only RLS, NO INSERT/UPDATE/DELETE policy, table-level writes REVOKEd, `<table>_jti_not_denied` RESTRICTIVE policy per mig-126 shape) + the **atomic** `crm_get_contact_detail(p_contact_id uuid) RETURNS jsonb` SECURITY DEFINER RPC (`auth.uid() IS NULL -> 42501` guard; `SET search_path = public, pg_temp` per `cq-pg-security-definer-search-path-pin-pg-temp`; verifies the contact belongs to `auth.uid()` with uniform 42501 on foreign/missing — no oracle; INSERTs the access-log row AND returns `{ contact, notes, transitions }` as jsonb in the same transaction — fail-closed). `.down.sql` provided. Migration number re-verified next-free against `origin/main` at /work time (provisional 127).
- **AC14.** `tsc --noEmit` clean (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`); route tests in `test/api/crm/**/*.test.ts` (unit project) + component tests in `test/crm/**/*.test.tsx` (component project) per `vitest.config.ts` globs; full `test-all.sh` green.
- **AC15.** C4: `webapp -> crmStore` edge added to `model.c4` + rendered (`views.c4` include) + the reserved `model.c4:316–318` comment rewritten (no longer "no UI/API surface") + `crmStore` technology string updated to include `beta_contact_access_log`; `c4-code-syntax.test.ts` + `c4-render.test.ts` green. ADR-102 amended with the UI-phase + read-audit decision.

(CPO sign-off + `user-impact-reviewer`-at-review are tracked in the frontmatter `requires_cpo_signoff: true` + the User-Brand Impact note above — process gates, not merge-gating ACs.)

### Post-merge (pipeline-automated; no manual infra)

- **AC17.** Migration 127 applies via `web-platform-release.yml#migrate` on merge-to-main — pipeline-automated, no SSH, no dashboard step. `/soleur:ship` verifies the migration applied + `crm_get_contact_detail` exists via the Supabase MCP read-only `list_migrations`/`execute_sql` probe. `Ref #6172` in the PR body (not `Closes` — the issue closes when the UI is live-verified). Epic #6177 unaffected.
- **AC18.** Agent-native parity smoke: a contact the agent manages (`crm_contact_list`) appears identically on the board (same store, same RLS) — verified via one MCP `crm_contact_list` call + a board render check.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- Re-verify next-free migration number against `origin/main` (`git ls-tree origin/main --name-only apps/web-platform/supabase/migrations/ | grep -E '^12[7-9]_'`). Use the true next-free; 127 is provisional.
- Read `crm-tools.ts:60–120` (column lists + inline mapper) and `crm-tools.test.ts` (drift-guard) so the extraction is behavior-preserving.
- Confirm the icon source: `@/components/icons` — pick/define a CRM icon (people/contacts glyph).
- Confirm `swrKeys` location (grep `swrKeys` in `lib/`) for `crmContacts`/`crmContactDetail`/`crmFunnel` keys.

### Phase 1 — Shared read layer (no UI yet; behavior-preserving; TDD) — land + verify FIRST
1. **`server/crm/crm-reads.ts`** — export ONLY the column-list constants `CONTACT_COLUMNS`/`NOTE_COLUMNS`/`TRANSITION_COLUMNS` + a self-test asserting the sets (the PII-column-drift guard). The list & funnel query bodies are inlined into their single consuming route handler (Phase 3), not builder wrappers here (simplicity review — one consumer each). The detail read lives in the migration RPC (Phase 2).
2. **`crm-tools.ts`**: replace its inline column-list constants with imports from `crm-reads.ts` (the ONLY agent-path touch; the inline write-error mapper stays). Run `crm-tools.test.ts` drift-guard + agent-path tests — must stay green. This is a **behavior-preserving refactor landed and test-verified before any UI code** (bisectable; a UI revert never rolls back the agent path). Do NOT extract the write-error mapper (advisor consult — the routes don't consume it).

### Phase 2 — Migration 127 (atomic detail-read + read-audit)
- `127_beta_crm_access_log.sql` + `.down.sql` per AC13. `beta_contact_access_log` + the atomic `crm_get_contact_detail(p_contact_id) RETURNS jsonb` SECURITY DEFINER RPC. Mirror the mig-126 guard shape verbatim (`auth.uid() IS NULL -> 42501`, owner-check, uniform 42501, `SET search_path = public, pg_temp`). The RPC INSERTs the access-log row and returns `{contact,notes,transitions}` jsonb in one transaction (fail-closed). RLS/immutability test (SELECT-owner-only; no owner-INSERT; RPC-only write; foreign contact → 42501, no oracle; a returned contact ⇒ an audit row exists).

### Phase 3 — API routes (Model A: direct `createClient()` + `getUser()` + 401)
1. `app/api/crm/contacts/route.ts` — GET list; RLS SELECT inlined in the handler using `CONTACT_COLUMNS` (AC1). Sibling `route.helpers.ts` only if a non-handler export is needed.
2. `app/api/crm/contacts/[id]/route.ts` — GET detail via the **atomic** `crm_get_contact_detail` RPC, called with `supabase.rpc(...)` on the SSR cookie client (AC2, AC3). Rationale documented inline: the read + Art. 5(2) access-log are one transaction (fail-closed = un-bypassable); a GET whose only "write" is the accountability log ⇒ no CSRF surface; SWR-duplicate log rows are correct (each = a real re-egress). The RPC is VOLATILE (default) — an INSERT inside a STABLE function fails.
3. `app/api/crm/funnel/route.ts` — GET funnel aggregation; query inlined (AC4). All three routes: generic PII-free error body + `Sentry.captureException(e, { tags: { surface: "crm-<x>" } })`; never echo raw PG text; SSR cookie client (`createClient()` + `getUser()`, NOT `getFreshTenantClient`).

### Phase 4 — UI (reskin WorkstreamBoard patterns into components/crm/)
1. `app/(dashboard)/dashboard/crm/page.tsx` — server component, `export const dynamic = "force-dynamic"`, `getUser()` → `redirect("/login")`, `<Suspense>` around `<CrmSurface/>`.
2. `components/crm/crm-surface.tsx` — client; `Board | Funnel` toggle; SWR (`jsonFetcher`, `swrKeys.crmContacts()`); drawer state + `pushState`/`popstate` deep-link; loading/error/empty states (AC10); the "edit via agent" hint/CTA (AC11).
3. `components/crm/pipeline-column.tsx` — reskin `IssueColumn`; renders its own read-only contact cards inline (no separate card file); render all `STAGES` columns (empty ones too); Closed Lost terminal rail.
4. `components/crm/contact-detail-sheet.tsx` — reskin `IssueDetailSheet`; SWR `swrKeys.crmContactDetail(id)`; `notFound` prop → neutral byte-identical "This contact isn't available" + "Back to board" (P0-1); dual-lens note timeline + stage-history; read-only hint.
5. `components/crm/funnel-view.tsx` — mirror `FunnelSection` bars; per-stage accent from the same hexes; low-N "insufficient data" suppression (AC4); velocity strip; honest thin-data footnote.
6. Nav: `nav-items.ts` + `layout.tsx` NAV_ICONS (AC12).

### Phase 5 — C4 + ADR (Architecture Decision deliverable)
- `model.c4`: add `webapp -> crmStore` edge ("GET /api/crm/* RLS-owner-scoped read routes + crm_get_contact_detail audit RPC"); update `crmStore` technology to include `beta_contact_access_log`. `views.c4`: ensure the edge renders. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- Amend `ADR-102`: add a "UI phase (read-only)" section — the reserved `webapp -> crmStore` edge is realized; operator-read accountability via `beta_contact_access_log`; no self-serve erase (unchanged).

### Phase 6 — Full verification
- `tsc --noEmit`, `test-all.sh`, C4 tests, migration/RLS test, route tests, component tests, negative PII-safe-error test, agent-parity smoke.

## Domain Review

**Domains relevant:** Product, Legal, Engineering (triad carried forward from brainstorm `## Domain Assessments`).

### Legal (CLO) — carry-forward
**Status:** reviewed. **Assessment:** UI over third-party PII adds accountability duties (operator-read audit — encoded as mig-127) but no new legal basis. PII-safe-error discipline is **merge-blocking** on the routes (AC5). Writes reuse the SECURITY DEFINER RPCs; direct owner edits are inherently reviewed (no R3 UI analogue). Erasure stays service-role-only; no self-serve erase in v1. Art. 15 (access) is served by the owner's own read; Art. 17 (erasure) unchanged (service-role `crm_erase_contact`, head + append-only redaction).

### Engineering (CTO) — carry-forward
**Status:** reviewed. **Assessment:** one authz boundary (reuse mig-126 RPCs via `getFreshTenantClient`); default-authed routes (no `PUBLIC_PATHS`); factor the PII-safe mapper into shared `server/crm/`; import `stage-probability.ts`. Read-only board = near-zero new attack surface. No new ADR — amend ADR-102.

### Product/UX Gate
**Tier:** blocking (UI-surface files under `app/(dashboard)/**` + `components/**/*.tsx`).
**Decision:** reviewed. **Agents invoked:** spec-flow-analyzer (this session), cpo (brainstorm carry-forward), ux-design-lead (brainstorm — wireframes committed + operator-approved). **Skipped specialists:** none.
**Pencil available:** yes (`.pen` committed at `knowledge-base/product/design/crm/beta-crm-pipeline.pen`, 4 screenshots, operator-approved).
#### Findings
spec-flow-analyzer P0/P1/P2 gaps folded into AC2/AC3/AC5/AC8/AC9/AC10/AC11 (deep-link no-oracle, audit non-blocking, PII-safe rendering, funnel error state, edit-via-agent escape, cold deep-link, low-N suppression, empty-column render).

## GDPR / Compliance (Phase 2.7)

Regulated-data surface (third-party PII, new migration, API routes) + `single-user incident` threshold → gate fires. Concerns encoded via CLO carry-forward, not re-litigated:
- **Art. 5(2) accountability:** `beta_contact_access_log` records owner reads of note bodies (drawer-open granularity), written **atomically inside** the detail-read RPC (fail-closed: no PII egress without an audit row) — a stronger evidentiary guarantee than a best-effort side-write.
- **Art. 15 (access):** served by the owner's own read; no new subject-facing surface.
- **Art. 17 (erasure):** unchanged — service-role `crm_erase_contact` (head delete + append-only redaction); the access-log holds only `contactId` (no note body) and its rows are included in the erase set — **noted for the erase path, tracked, not built in v1** (NG2).
- **No raw PG error egress** (AC5) — the load-bearing leak-prevention.

## Observability

```yaml
liveness_signal:
  what: crm route request volume + 5xx rate (owner-only, low volume)
  cadence: per-request
  alert_target: Sentry (surface tag crm-contacts / crm-contact-detail / crm-funnel)
  configured_in: apps/web-platform/infra/sentry/*.tf (issue alert on crm-* surface 5xx)
error_reporting:
  destination: Sentry via Sentry.captureException + mapPgErrorCode (PII-free)
  fail_loud: true (route 500s surface a semantic-code ErrorCard + Retry; never silent)
failure_modes:
  - mode: atomic detail RPC fails (read+audit are one transaction — fail-closed, no data-without-audit)
    detection: Sentry event crm-get-contact-detail:<code>; drawer shows ErrorCard + Retry (never silent, never blank)
    alert_route: Sentry issue alert (a failing detail RPC = both a read outage AND an accountability signal)
  - mode: route returns raw PG error
    detection: negative test (AC5) at CI; never reaches prod
    alert_route: CI gate
  - mode: cross-owner read attempt
    detection: RLS returns empty -> uniform 404 (no oracle); no alert (expected-safe)
    alert_route: n/a
logs:
  where: Sentry (errors) + beta_contact_access_log (owner reads, in-DB)
  retention: Sentry default; access-log rows owner-private, erased with the contact
discoverability_test:
  command: "supabase MCP execute_sql 'select count(*) from beta_contact_access_log' (read-only, NO ssh)"
  expected_output: row count increments after a drawer-open in prod smoke
```

## Infrastructure (IaC)

The plan introduces **no new server, systemd unit, cron, vendor account, secret, DNS record, or
firewall rule**. Two infra-adjacent surfaces, both pipeline/IaC — zero manual provisioning:

### Terraform changes
- **Sentry issue-alert rule** for the `crm-*` surface: fire on 5xx on `crm-contacts`/`crm-contact-detail`/`crm-funnel` AND on the `crm-log-contact-view:<code>` audit-write-failure event (the accountability-gap signal). Declared as a `sentry_*` resource in `apps/web-platform/infra/sentry/*.tf`, extending the existing Sentry root; scoped into the `apply-sentry-infra.yml` `-target=` set the same way sibling alert rules are. No new provider, no new secret (uses the existing `prd_terraform` Sentry token).

### Apply path
- **Migration 127**: a code-class `.sql` file applied by the existing `web-platform-release.yml#migrate` job on merge-to-main. Not new infrastructure provisioning — no `.tf`, no SSH, no dashboard.
- **Sentry alert**: applied by the existing `apply-sentry-infra.yml` auto-apply workflow on merge of the `.tf` change. cloud-init N/A (no host).

### Distinctness / drift safeguards
- No `dev != prd` host config here. The Sentry alert targets the prod Sentry project only (existing convention). No state-storage change.

### Vendor-tier reality check
- Sentry issue alerts are within the existing paid tier already used for sibling `crm-tools` alerts — no tier gate needed.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-102** (do not create new). Add a "UI phase (read-only)" section: the reserved
`webapp -> crmStore` edge is realized by `app/api/crm/*` GET routes; owner-read accountability is added
via `beta_contact_access_log` + `crm_get_contact_detail` (SECURITY DEFINER, RPC-only-write,
owner-private — same posture as mig-126); no self-serve erase (unchanged).

### C4 views
**Container (L2):** add `webapp -> crmStore` edge to `model.c4` and the `view include` in `views.c4` so
it renders; update the `crmStore` technology string to include `beta_contact_access_log`.
**Completeness check (all three `.c4` files read):** external human actors `founder` (views CRM) +
`betaContact` (PII origin) already modeled; no new external system/vendor (Supabase = `crmStore`,
already modeled); the one changed access relationship is `webapp -> crmStore` (NEW); `founder`→`webapp`
path already exists. No other actor/system/relationship changes. Run `c4-code-syntax.test.ts` +
`c4-render.test.ts` after the edit.

### Sequencing
All in this PR — no soak gate, no deferred ADR.

## Open Code-Review Overlap

**None.** Checked all 62 open `code-review` issues against every planned file path
(`server/crm/crm-tools.ts`, `app/api/crm`, `components/crm`, `dashboard/crm`, `nav-items.ts`,
`stage-probability.ts`, `126_beta_crm`) — zero matches.

## Non-Goals

- **NG1.** No create/edit/drag-to-stage or any contact-content write path (editing stays conversational via the agent).
- **NG2.** No self-serve erase; `crm_erase_contact` stays service-role-only. (Adding `beta_contact_access_log` to its delete set is noted for the erase path but not built in v1.)
- **NG3.** No workspace-shared / tester-visible views (deferred siblings #6173 / #6171 under epic #6177).
- **NG4.** No weighted-$ forecasting (CFO: theater at 0 deals — funnel is count-based only).
- **NG5.** No **pre-scoped chat deep-link** for the "edit via agent" CTA — v1 links to `/dashboard/chat` generically; pre-scoping chat to a contact is deferred (file follow-up issue).

## Files to Create

- `apps/web-platform/server/crm/crm-reads.ts` — shared column-list constants + a column-set self-test (no query builders — inlined in routes). (No `crm-errors.ts` — advisor consult dropped the write-mapper extraction.)
- `apps/web-platform/app/api/crm/contacts/route.ts` — GET list.
- `apps/web-platform/app/api/crm/contacts/[id]/route.ts` — GET detail via the atomic `crm_get_contact_detail` RPC (read + audit).
- `apps/web-platform/app/api/crm/funnel/route.ts` — GET funnel aggregation.
- `apps/web-platform/app/(dashboard)/dashboard/crm/page.tsx` — board page (server component).
- `apps/web-platform/components/crm/crm-surface.tsx` — client board+funnel+drawer host.
- `apps/web-platform/components/crm/pipeline-column.tsx` (renders its own read-only cards inline — no separate card file, simplicity review), `contact-detail-sheet.tsx`, `funnel-view.tsx`. (4 components total: surface + column + drawer + funnel.)
- `apps/web-platform/supabase/migrations/127_beta_crm_access_log.sql` + `.down.sql`.
- Tests: `test/api/crm/{contacts,contact-detail,funnel}.test.ts`, `test/server/crm-access-log-rls.test.ts` (RLS + atomic-RPC: returned contact ⇒ audit row; foreign → 42501), `test/crm/{crm-surface,contact-detail-sheet,funnel-view}.test.tsx`.

## Files to Edit

- `apps/web-platform/server/crm/crm-tools.ts` — import column-list constants from `crm-reads.ts` ONLY (inline write-error mapper `:84–114` stays untouched — advisor consult); behavior-preserving.
- `apps/web-platform/components/command-palette/nav-items.ts` — add CRM nav item.
- `apps/web-platform/app/(dashboard)/layout.tsx` — add CRM to `NAV_ICONS`.
- `apps/web-platform/lib/swr-config.ts` (or wherever `swrKeys` lives) — add `crmContacts`/`crmContactDetail`/`crmFunnel` keys.
- `knowledge-base/engineering/architecture/diagrams/model.c4` + `views.c4` — `webapp -> crmStore` edge + crmStore technology.
- `knowledge-base/engineering/architecture/decisions/ADR-102-*.md` — UI-phase amendment.

## Test Scenarios

1. **PII-safe error (negative):** route fed a PostgrestError with a row value in `details` → body has only the semantic code; Sentry mock receives `{ op, code, userIdHash }`, no PII. (AC5)
2. **No existence oracle:** detail route for never-existed / erased / cross-owner id → identical `404 { error: "not_found" }`. (AC2)
3. **Audit atomic / fail-closed:** `crm_get_contact_detail` throws (audit-table down) → detail route 5xx with a PII-free body, NO contact data returned; Sentry gets the mirror; a returned contact always has a matching audit row. (AC3)
4. **Funnel low-N:** prior stage `reached < LOW_N_THRESHOLD` → `conversionPct: null` → view shows "insufficient data". (AC4)
5. **Empty column renders:** board with zero contacts in a stage still renders the column. (AC7)
6. **Deep-link cold load:** direct `?contact=<id>` → board list fetches underneath; close → populated board. (AC8)
7. **Agent-path regression:** `crm-tools.test.ts` + agent tools tests green after the extraction. (AC6)
8. **RLS/immutability:** access-log SELECT-owner-only, no owner-INSERT, RPC-only write, foreign contact → 42501. (AC13)

## Risks & Mitigations

- **R1 — touching the agent write path regresses the "make-or-break" path.** Reduced by the advisor consult: the only agent-path touch is importing column-list constants from `crm-reads.ts` (write-error mapper untouched). Landed as Phase 1 + verified against the `crm-tools.test.ts` drift-guard + agent-path tests before any UI (bisectable).
- **R2 — atomic detail RPC couples drawer availability to audit-table health.** Accepted trade for a single-owner beta CRM at Art. 5(2) stakes: fail-closed accountability > drawer uptime; failure degrades to a loud ErrorCard+Retry (not blank). SWR-revalidation duplicate log rows are now *semantically correct* (each = a real PII re-egress), so no dedup needed; a future hover-prefetch can't create phantom "read" records without actually egressing data.
- **R3 — funnel aggregation cost.** Mitigation: single owner, tiny dataset; `computeFunnel` is a single grouped read. No hot path.
- **R4 — migration number collision with a sibling PR.** Mitigation: re-verify next-free against `origin/main` at /work (Phase 0); ship re-checks.

## Sharp Edges

- `## User-Brand Impact` is filled (not TBD) — required or `deepen-plan` Phase 4.6 halts.
- Typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (root has no `workspaces`; `npm run -w` fails).
- Test paths must match `vitest.config.ts` globs: routes → `test/api/crm/**/*.test.ts` (node), components → `test/crm/**/*.test.tsx` (happy-dom). A co-located test is silently never run.
- Import `STAGES` from `stage-probability.ts`; never re-declare the enum (drift-guarded against the mig CHECK).
- Migration 127 is **provisional** — re-verify next-free against `origin/main` before writing.
- The detail read + audit are **one atomic SECURITY DEFINER RPC** (`crm_get_contact_detail`), fail-closed (no audit row ⇒ no data). It's a GET whose only write is the Art. 5(2) accountability log, so no CSRF surface; document the rationale inline so a reviewer doesn't flag it as a REST-hygiene violation. Do NOT split it back into a pure read + best-effort side-write (that reintroduces the read-succeeds/audit-fails accountability gap the advisor consult closed).

## Scoped Advisor Consult (fable) — applied

Two changes applied before plan-review (both architectural, within operator direction):
1. **Dropped** the `crm-errors.ts` write-mapper extraction — read routes don't consume it; keep only the `crm-reads.ts` column-list share (minimizes the agent-path touch).
2. **Atomic fail-closed audit** — folded read + access-log into one `crm_get_contact_detail` RPC (was: best-effort side-write), making "un-bypassable" an invariant and reducing code.

## Plan Review (architecture-strategist + code-simplicity-reviewer) — applied

Core design affirmed (atomic RPC transaction semantics, RPC-vs-RLS boundary, low agent-path blast radius). Applied all mechanical findings: renamed the stale `crm_log_contact_view` → `crm_get_contact_detail` in AC17/C4/ADR (P1-1); `webapp -> crmStore` not `api ->` per the reserved comment + sibling convention (P1-2); SSR cookie client not `getFreshTenantClient` for routes (P2-3); AC6 column-set self-test since the drift-guard covers only the stage enum (P2-4); VOLATILE RPC via `.rpc()` (P2-5); folded `contact-card` into `pipeline-column` (4 components); narrowed `crm-reads.ts` to column constants only; removed ceremony AC16. One **User-Challenge surfaced to the operator** (funnel velocity/per-transition scope): operator **kept velocity in v1** (matches the approved wireframe + the chosen funnel option). Funnel scope unchanged.

- **VOLATILE RPC (SQL gotcha):** `crm_get_contact_detail` must be `VOLATILE` (the default) — an `INSERT` (the audit row) inside a `STABLE`/`IMMUTABLE` function raises at runtime. Call it via supabase-js `supabase.rpc(...)` (POST under the hood) on the SSR cookie client.
