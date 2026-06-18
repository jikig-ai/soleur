---
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5512
follow_up_issue: 5527
branch: feat-dashboard-inbox
pr: 5524
spec: knowledge-base/project/specs/feat-dashboard-inbox/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-18-dashboard-inbox-surface-brainstorm.md
wireframes: knowledge-base/product/design/inbox/dashboard-inbox.pen
---

# ✨ Plan: Dedicated Inbox Surface (`/dashboard/inbox` list page + nav entry)

## Overview

Add a browsable Inbox surface to the dashboard: a new `/dashboard/inbox` client page
(Active + Archived views) reachable from a top-level "Inbox" nav entry and a "View all →"
link in the Command Center. Pure presentation/navigation — reuses `GET /api/inbox/emails`
and the `EmailTriageRow` component. No backend, schema, or RLS change (settled by #5494 /
ADR-066, migration 111). Effort: **XS**.

The email-connection capability ("connect Gmail/Proton") is **decoupled** to #5527 — the
inbox is single-tenant today (one `ops@soleur.ai` address, one `EMAIL_TRIAGE_OWNER_USER_ID`).

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "Add `/api/inbox/emails` to `setupNavMocks`" (e2e) | Mock already exists: `e2e/nav-states-shell.e2e.ts:228` routes `**/api/inbox/emails*` (the `*` covers `?status=archived`). | TR4 narrows to: exercise the **new `/dashboard/inbox` route** under the existing nav-state harness; no mock added from scratch. |
| Command Center "add View all → link to the section" | `dashboard/page.tsx:796` renders email rows as bare siblings — **no section header exists** today. | FR4 = *add* a small section header wrapping the `emailItems` block, with the link (matches wireframe 12). |
| Nav icon from "the icon module" | Nav icons are defined **inline in `layout.tsx`** (`GridIcon:607`, `BookIcon:625`, `RepeatIcon:746`). | Add `InboxIcon` as a same-file inline component in `layout.tsx`. |
| Detail route is the row's link target | Detail route `email/[emailId]/page.tsx` has **no back affordance**; rows navigate via `router.push` (not an `<a>`). | Fold in a "← Inbox" link on the detail page (spec-flow P0; the list page is now the return target). |
| Existing dashboard fetch handles errors | `dashboard/page.tsx` fetch **silently returns** on `!res.ok` (intentional — rest of page renders). | The dedicated page must NOT silently swallow — visible error+retry (the inbox IS the page). TR2. |
| "client page using `useSearchParams`" (initial draft) | `/dashboard/inbox` is a **static** route; a `"use client"` page calling `useSearchParams` fails `next build` (`missing-suspense-with-csr-bailout`) — `tsc` does NOT catch it. Static-client precedent: `(auth)/signup/page.tsx:15`, `setup-key/page.tsx:19` wrap in `<Suspense>`. The chat page is exempt only because it has a dynamic `[conversationId]` segment. | **[Kieran P0]** Use the Routines pattern: **Server page** (`force-dynamic`, auth gate) → `<Suspense>`-wrapped **client surface** `components/inbox/inbox-surface.tsx`. Add a `next build` gate AC. |
| Reuse: error UI + tabs + skeleton | `ErrorCard` (`components/ui/error-card.tsx`, already imported by `dashboard/page.tsx:12`); `TabButton`/`role="tab"` pattern in `routines-surface.tsx:111-159`; no generic row Skeleton (KB-only). | Reuse `ErrorCard` + the Routines `TabButton` pattern; drop the skeleton for a plain "Loading…" line (routines-surface.tsx:694). |

## User-Brand Impact

**If this lands broken, the user experiences:** a top-level "Inbox" that opens to a blank or
errored page, or an Archived view that strands them — or worse, a statutory item (DSAR /
Art. 33 72h) that silently falls out of view.

**If this leaks, the user's data is exposed via:** over-exposing statutory/PII triage items
(probe rows, archived items) to a workspace Owner, OR mislabeling "archived" as erased.
(Reads are already authorized for every workspace Owner by #5494 RLS — no new exposure path;
the risk is presentation, not authorization.)

**Brand-survival threshold:** single-user incident.

> CPO sign-off: carried forward from the 2026-06-18 brainstorm `## Domain Assessments` (CPO
> assessed this exact surface). `user-impact-reviewer` runs at PR-review time.

## Implementation Phases

### Phase 1 — Tests first (RED) — `cq-write-failing-tests-before`
1.1 New `test/inbox-surface.test.tsx` (happy-dom `component` project — `test/**/*.test.tsx`;
vitest — both `bunfig.toml` block `bun test`). Test the client surface `<InboxSurface />`. Cover:
Active fetch renders rows; Archived tab fetches `?status=archived`; query-param-derived tab
state (deep-link to `?status=archived` highlights Archived); Active-empty vs Archived-empty
copy; "Loading…" then content (no empty→populated flash); error+retry refetches the current tab;
tabs stay rendered in the error state. Mock `fetch` per case.
1.2 Extend `e2e/nav-states-shell.e2e.ts`: assert the "Inbox" nav entry renders and routing to
`/dashboard/inbox` shows the list (reusing the existing `**/api/inbox/emails*` mock at :228).

### Phase 2 — Server page + client surface (GREEN)
**[Kieran P0 — Suspense]** Mirror the Routines pattern (Server page → client surface) so the
static route does not hit `missing-suspense-with-csr-bailout`.
2.1 `app/(dashboard)/dashboard/inbox/page.tsx` (new, **Server** component): `export const dynamic
= "force-dynamic"`; cookie-session auth gate (`supabase.auth.getUser()` → `redirect("/login")`,
mirroring routines/page.tsx); render the Routines shell (`<main className="mx-auto max-w-5xl px-6
py-8">` + h1 "Inbox" + one-line description) wrapping `<Suspense fallback={…"Loading…"}>
<InboxSurface /></Suspense>`.
2.2 `components/inbox/inbox-surface.tsx` (new, `"use client"`): fetch `/api/inbox/emails
[?status=archived]` (non-silent error). Active/Archived tabs **mirroring `routines-surface.tsx`
`TabButton`/`role="tab"`**; selection sets `?status=archived` via `useSearchParams` (deep
-linkable; tab-active derives from the query param, not a local default).
2.3 Map items to `EmailTriageRow` (`{item, onChanged: refetch}`); **import** `EmailTriageItem`
from `components/inbox/email-triage-row.tsx` (do not redeclare). Probes hidden (no
`?include_probes`). Render in API order (statutory pinned first) — **no `useMemo(sort)`/re-sort**.
2.4 States: plain "Loading…" line (not a skeleton component); **reuse `ErrorCard`**
(`components/ui/error-card.tsx`, `{title, message, onRetry}`) with `onRetry` → refetch current
tab; distinct empty copy — Active "No items needing attention", Archived "Nothing archived yet".
Empty-state gated on `!loading && !error`.

### Phase 3 — Wire-up (nav + Command Center link + detail back-link)
3.1 `layout.tsx`: add `{ href: "/dashboard/inbox", label: "Inbox", icon: InboxIcon }` to
`NAV_ITEMS` (`:95`) + inline `InboxIcon` (icons are inline in this file). Single `navItems`
array (`:162`) feeds drawer + collapsed rail — no separate mobile edit. `segmentToDrillLevel
("/dashboard/inbox")` returns `null` (allowlist is kb|settings|chat) — no secondary rail.
3.2 `dashboard/page.tsx:796`: wrap the `emailItems` block in a section header carrying a
"View all →" link → `/dashboard/inbox` (wireframe 12).
3.3 `email/[emailId]/page.tsx`: add a "← Inbox" link → `/dashboard/inbox` (spec-flow P0 — the
email-notification deep-link is the inbox's primary entry; a cold land otherwise strands the
operator since browser-back returns to their mail client). Additive — does not touch the
deep-link auth/RLS/notFound path.

## Files to Create
- `apps/web-platform/app/(dashboard)/dashboard/inbox/page.tsx` — Server page (auth gate + Suspense).
- `apps/web-platform/components/inbox/inbox-surface.tsx` — client surface (fetch, tabs, rows, states).
- `apps/web-platform/test/inbox-surface.test.tsx` — vitest happy-dom suite.

## Files to Edit
- `apps/web-platform/app/(dashboard)/layout.tsx` — `NAV_ITEMS` entry + inline `InboxIcon`.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — Command Center section header + "View all →".
- `apps/web-platform/app/(dashboard)/dashboard/inbox/email/[emailId]/page.tsx` — "← Inbox" back link.
- `apps/web-platform/e2e/nav-states-shell.e2e.ts` — exercise the new route (mock already present).

## Observability

```yaml
liveness_signal:
  what: GET /api/inbox/emails 200 rate (existing route; now also driven by the list page)
  cadence: on page load / tab switch (user-driven)
  alert_target: existing Sentry project (no new alert rule — same route as Command Center)
  configured_in: apps/web-platform/app/api/inbox/emails/route.ts (reportSilentFallback → Sentry)
error_reporting:
  destination: Sentry — server route via reportSilentFallback (route.ts:71-78, PII-safe {userId})
  fail_loud: client page surfaces a visible error + retry (NOT the dashboard's silent return);
    any client-side catch that degrades silently mirrors to Sentry (cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - mode: API 500 (query error)
    detection: reportSilentFallback → Sentry (existing)
    alert_route: existing inbox-emails Sentry signal
  - mode: client fetch network failure
    detection: page error state + Sentry mirror on catch
    alert_route: Sentry (client)
  - mode: statutory item hidden by filter/pagination
    detection: covered by API contract (pinned statutory rows uncapped, route.ts:31-44) + AC
    alert_route: n/a (structural — verified by test, not runtime alert)
logs:
  where: Sentry (route + client); no new log sink
  retention: existing Sentry retention
discoverability_test:
  command: "curl -fsS -H 'Cookie: <owner-session>' https://<host>/api/inbox/emails | jq '.items | length'"
  expected_output: a JSON array length (0+); 500 → Sentry event (no ssh)
```

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carried forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward). LOW risk, XS, pure additive frontend. Client page (option A)
reusing the bounded API; `EmailTriageRow` reusable as-is; specify error+retry + `segmentToDrillLevel`.

### Legal (CLO) — Compliance / GDPR Gate (Phase 2.7)
**Status:** reviewed (carry-forward). The CLO domain leader assessed this exact presentation
surface at brainstorm time. **No new processing activity** (no new Art. 30 PA — same
`email_triage_items` rows, same controller-side access established by #5494/ADR-066), **no new
lawful basis**, **no Art. 9 special-category change**, **no new data-movement/schema/route**.
Three binding UI guardrails carried into TRs/ACs: (1) probes hidden by default; (2) "Archived"
must not imply erasure ("Archived — still retained" / "Done", no action buttons on archived);
(3) statutory items never paginated/filtered out of sight. A separate `/soleur:gdpr-gate` run
was not invoked — the change introduces no regulated-data surface beyond what #5494 shipped, and
the legal authority (CLO) already produced the binding assessment. Trigger (b) (single-user
threshold) is satisfied by the CLO carry-forward.

### Product/UX Gate
**Tier:** blocking (mechanical override — new `app/**/page.tsx`).
**Decision:** reviewed.
**Agents invoked:** spec-flow-analyzer (this plan), cpo (carry-forward), ux-design-lead (brainstorm — wireframes committed).
**Skipped specialists:** none.
**Pencil available:** yes (`.pen` committed: `knowledge-base/product/design/inbox/dashboard-inbox.pen`, screens 09–12; referenced in spec FRs).

#### Findings (spec-flow-analyzer)
- **P0** detail-route has no back affordance → fold in "← Inbox" link (Phase 4).
- **P0** acknowledge keeps statutory row visible (pinned) after `onChanged` — empty-state keys on `items.length`; verified by AC.
- **P1** tab/query preserved on return (browser-back for in-app; explicit link → Active).
- **P1** error retry scoped to current tab; tabs stay rendered in error state.
- **P1** loading skeleton; empty-state gated on `!loading && !error`.
- **P2** distinct Archived-empty copy; tab-active derives from query param.

## Acceptance Criteria (Pre-merge)

- [ ] `/dashboard/inbox` renders Active items from `GET /api/inbox/emails`; Archived tab fetches `?status=archived`.
- [ ] Tab-active state derives from `?status=archived`; deep-linking to `?status=archived` highlights Archived.
- [ ] Top-level "Inbox" nav entry renders and is active on `/dashboard/inbox`; `segmentToDrillLevel` shows no secondary rail.
- [ ] Command Center "View all →" link navigates to `/dashboard/inbox`.
- [ ] Active-empty shows "No items needing attention"; Archived-empty shows "Nothing archived yet"; both gated on `!loading && !error`.
- [ ] Fetch failure shows a visible error + retry (retry refetches the current tab); tabs stay clickable in the error state.
- [ ] Probe rows hidden by default; statutory pinned rows render **in API order** — the surface does **not** `useMemo(sort)`/re-sort the items; an acknowledged statutory row stays visible after `onChanged`.
- [ ] Archived view uses no deletion/erasure wording and shows no action buttons.
- [ ] Detail route shows a "← Inbox" back link → `/dashboard/inbox`.
- [ ] The "Inbox" **nav entry** is the always-available path to the inbox (the Command Center "View all →" link only renders when `emailItems.length > 0`); empty-state reachable via the nav entry.
- [ ] No backend/schema/RLS change (the page does no DB access — it fetches the existing API).
- [ ] `./node_modules/.bin/vitest run test/inbox-surface.test.tsx` passes (happy-dom `component` project); `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; **`next build` succeeds** (catches the `useSearchParams`/Suspense bailout that `tsc` does not).
- [ ] Wireframes 09–12 committed; observability-coverage-reviewer + user-impact-reviewer pass at review.

## Open Code-Review Overlap

2 open `code-review` issues touch planned files, both **Acknowledge** (different concern, own cycle):
- #2193 (billing past_due/unpaid banner unification) touches `layout.tsx` — unrelated to the nav entry. Left open.
- #2590 (extract `useFirstRunAttachments`/`FirstRunComposer`) touches `dashboard/page.tsx` — unrelated to the Command Center "View all" link. Left open.

## Architecture Decision (ADR / C4)

**No ADR.** No architectural decision: no tenancy/ownership move (settled by #5494/ADR-066), no
new substrate/integration, no resolver/trust-boundary change, no ADR reversal.

**No C4 impact** — verified by reading all three `.c4` files. The relevant external actors,
systems, store-writes, and access relationship are **already modeled**:
- `emailSender` external actor (`model.c4:16`) and `resend` system (`model.c4:195`) — the inbound source.
- Owner-shared-inbox access relationship — `model.c4:9` (Owner description: "Owner-shared surfaces
  (e.g. the operator email-triage inbox, ADR-066) are readable by every Owner") + `model.c4:243`.
- `inngest → supabase` triage writes (`model.c4:244`).
This plan adds a UI **page** (below C4 container grain) reading the already-modeled
`webapp → api → supabase` path; it introduces no new actor, system, data store, or access
relationship. No `.c4` edit, no new `view … include`.

## Risks & Sharp Edges

- **`useSearchParams` on a static route is a `next build` breaker (Kieran P0).** A `"use client"` page calling `useSearchParams` at `/dashboard/inbox` (no dynamic segment) fails build with `missing-suspense-with-csr-bailout`; `tsc --noEmit` does NOT catch it. Mitigated by the Server-page + `<Suspense>`-wrapped client-surface structure (Phase 2). The `next build` gate AC is the guard. Do not "simplify" back to a bare client page.
- Reuse, don't rebuild: `ErrorCard` (`components/ui/error-card.tsx`), the `TabButton`/`role="tab"` pattern (`routines-surface.tsx:111-159`), and the `EmailTriageItem` type (`email-triage-row.tsx:28`). Plain "Loading…" line, not a skeleton component.
- A plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan Phase 4.6 — it is filled above.
- Test runner is **vitest** (`component` project = happy-dom), not bun (`bunfig.toml` `pathIgnorePatterns=["**"]`); path must match `test/**/*.test.tsx`; typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no root `workspaces`).
- Do NOT re-implement the route's filter logic (stub/probe/statutory-pin) in the surface — reuse the API (`route.ts:18-44`).
- The Command Center email block is gated on `emailItems.length > 0`; the "View all →" link lives in its header, so it shows only when items exist. The always-available path is the nav entry (acceptable; matches wireframe 12; covered by AC).
