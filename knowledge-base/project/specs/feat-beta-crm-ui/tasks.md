---
feature: beta-crm-ui
issue: 6172
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-08-feat-beta-crm-ui-read-only-board-plan.md
---

# Tasks: in-Soleur read-only beta-CRM UI (board + funnel)

Derived from the finalized plan (post advisor-consult + plan-review). Read-only v1; editing stays
conversational via the agent. Brand threshold: single-user incident → PII-safe errors + atomic
read-audit are non-negotiable.

## Phase 0 — Preconditions (verify before coding)

- [ ] 0.1 Re-verify next-free migration number vs `origin/main` (`git ls-tree origin/main --name-only apps/web-platform/supabase/migrations/ | grep -E '^12[7-9]_'`). 127 is provisional.
- [ ] 0.2 Read `crm-tools.ts:66–73` (column constants) + `crm-tools.test.ts` (drift-guard) to confirm the constant-move is behavior-preserving.
- [ ] 0.3 Confirm CRM icon source (`@/components/icons`) + `swrKeys` location (`lib/swr-config.ts`).

## Phase 1 — Shared read layer (behavior-preserving; land + verify FIRST)

- [ ] 1.1 Create `server/crm/crm-reads.ts` exporting ONLY `CONTACT_COLUMNS`/`NOTE_COLUMNS`/`TRANSITION_COLUMNS` constants.
- [ ] 1.2 Write `test/server/crm-reads.test.ts` — assert the exact column sets (PII-column-drift guard; the stage-enum drift-guard does NOT cover columns — arch P2-4).
- [ ] 1.3 Edit `crm-tools.ts` to import the constants from `crm-reads.ts` (ONLY agent-path touch; write-error mapper untouched).
- [ ] 1.4 Run `crm-tools.test.ts` + agent-path tests + `tsc` — all green before any UI code.

## Phase 2 — Migration 127 (atomic detail-read + read-audit)

- [ ] 2.1 Write `apps/web-platform/supabase/migrations/127_beta_crm_access_log.sql`: `beta_contact_access_log` table (append-only, owner-private — SELECT-owner-only RLS, NO INSERT/UPDATE/DELETE policy, table-level writes REVOKEd, `<table>_jti_not_denied` RESTRICTIVE policy per mig-126 shape).
- [ ] 2.2 Add `crm_get_contact_detail(p_contact_id uuid) RETURNS jsonb` SECURITY DEFINER **VOLATILE** RPC: `SET search_path = public, pg_temp`; `auth.uid() IS NULL -> 42501`; owner-check with uniform 42501 (no oracle); INSERT access-log row + SELECT/return `{contact,notes,transitions}` jsonb in one transaction (fail-closed).
- [ ] 2.3 Write `127_beta_crm_access_log.down.sql`.
- [ ] 2.4 Write `test/server/crm-access-log-rls.test.ts`: SELECT-owner-only; no owner-INSERT; RPC-only write; foreign/missing contact → uniform 42501 (no oracle); a returned contact ⇒ an audit row exists; audit failure rolls back (no data-without-audit).

## Phase 3 — API routes (SSR cookie client: `createClient()` + `getUser()`, 401 on unauth)

- [ ] 3.1 `app/api/crm/contacts/route.ts` — GET list; RLS SELECT inlined using `CONTACT_COLUMNS`; shape `{ contacts: [...] }`. (AC1)
- [ ] 3.2 `app/api/crm/contacts/[id]/route.ts` — GET detail via `supabase.rpc('crm_get_contact_detail', {...})`; map missing/foreign → byte-identical `404 { error: "not_found" }`; RPC error → PII-free 5xx (NOT 200-with-data). Inline rationale comment (atomic audit, no-CSRF, VOLATILE). (AC2/AC3)
- [ ] 3.3 `app/api/crm/funnel/route.ts` — GET funnel aggregation (cumulative reach + stage-to-stage % + avg time-in-stage + per-transition velocity — velocity kept per operator); `conversionPct: null` when prior stage `reached < LOW_N_THRESHOLD`. (AC4)
- [ ] 3.4 All routes: generic PII-free error body + `Sentry.captureException(e, { tags: { surface: "crm-<x>" } })`; never echo raw PG `message`/`details`.
- [ ] 3.5 Route tests in `test/api/crm/{contacts,contact-detail,funnel}.test.ts` (node project): incl. negative PII-safe-error test + no-oracle test + audit-atomic (RPC throw → no data) test.

## Phase 4 — UI (reskin WorkstreamBoard patterns into components/crm/)

- [ ] 4.1 `app/(dashboard)/dashboard/crm/page.tsx` — server component, `export const dynamic = "force-dynamic"`, `getUser()` → `redirect("/login")`, `<Suspense>` around `<CrmSurface/>`.
- [ ] 4.2 `components/crm/crm-surface.tsx` — client host; `Board | Funnel` toggle (toggle stays interactive if funnel errors); SWR (`jsonFetcher`, `swrKeys.crmContacts()`); drawer state + `pushState`/`popstate` deep-link; toggling to Funnel with drawer open closes the drawer; loading/error/empty states; "edit via your CRO/CPO agent" hint + `/dashboard/chat` link (board + funnel + drawer). (AC8/9/10/11)
- [ ] 4.3 `components/crm/pipeline-column.tsx` — reskin `IssueColumn`; renders its own read-only cards inline; render ALL `STAGES` columns (empty ones too); Closed Lost terminal rail. Import `STAGES` from `stage-probability.ts` (no re-declared enum). (AC7)
- [ ] 4.4 `components/crm/contact-detail-sheet.tsx` — reskin `IssueDetailSheet`; SWR `swrKeys.crmContactDetail(id)`; `notFound` → byte-identical "This contact isn't available" + "Back to board"; RPC error → ErrorCard + Retry; dual-lens note timeline + stage history; zero-note/zero-transition empty microcopy; read-only hint. (AC2/10)
- [ ] 4.5 `components/crm/funnel-view.tsx` — mirror `FunnelSection` (analytics-dashboard.tsx) bar style; per-stage accent hexes; low-N "insufficient data" suppression; velocity strip + per-transition; honest thin-data footnote. (AC4)
- [ ] 4.6 Nav: add `{ href: "/dashboard/crm", label: "CRM", seq: "g m" }` to `NAV_ITEMS` + `"/dashboard/crm": <icon>` to `NAV_ICONS`. (AC12)
- [ ] 4.7 Add `crmContacts`/`crmContactDetail`/`crmFunnel` keys to `swrKeys` (`lib/swr-config.ts`).
- [ ] 4.8 Component tests in `test/crm/{crm-surface,contact-detail-sheet,funnel-view}.test.tsx` (component project): empty-column render, deep-link cold load, low-N suppression, notFound state.

## Phase 5 — C4 + ADR

- [ ] 5.1 `model.c4`: add `webapp -> crmStore` edge (RLS-owner-scoped GET routes + `crm_get_contact_detail` audit RPC); update `crmStore` technology to include `beta_contact_access_log`; rewrite the stale `model.c4:316–318` "no UI/API surface at MVP" comment.
- [ ] 5.2 `views.c4`: ensure the edge renders (include line).
- [ ] 5.3 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 5.4 Amend `ADR-102`: "UI phase (read-only)" section — realized `webapp -> crmStore` edge; owner-read accountability via `beta_contact_access_log` + `crm_get_contact_detail`; no self-serve erase (unchanged).

## Phase 6 — Full verification

- [ ] 6.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 6.2 `test-all.sh` green (routes, components, migration/RLS, C4, agent-path regression).
- [ ] 6.3 Agent-native parity smoke: a `crm_contact_list` contact appears identically on the board.
- [ ] 6.4 Ship: `Ref #6172` in PR body (not `Closes`); ship verifies migration applied + `crm_get_contact_detail` exists via Supabase MCP read-only probe.

## Non-Goals (do not build)

- CRUD / drag-stage / any contact-content write (editing stays conversational).
- Self-serve erase (`crm_erase_contact` stays service-role-only).
- Workspace-shared / tester-visible views (#6173 / #6171).
- Weighted-$ forecasting (NG4).
- Pre-scoped chat deep-link for the edit-via-agent CTA (v1 links to `/dashboard/chat` generically; file a follow-up).
