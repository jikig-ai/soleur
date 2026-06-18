---
date: 2026-06-18
topic: dashboard-inbox-surface
issue: 5512
branch: feat-dashboard-inbox
pr: 5524
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Dedicated Inbox Surface (`/dashboard/inbox` list page + nav entry)

## What We're Building

A first-class **Inbox surface** for the dashboard so a workspace Owner can browse the
operator email-triage inbox like a mailbox, instead of only seeing it inline on the
Dashboard "Command Center" or via a single-item notification deep-link.

In scope (this PR — XS, presentation/navigation only):
- New `/dashboard/inbox` **list page** (client component) that fetches the existing
  `GET /api/inbox/emails` and renders rows with the existing `EmailTriageRow` component.
- **Active / Archived tabs** that drive the `?status=archived` URL query param (default = Active).
- A **top-level "Inbox" nav entry** in `NAV_ITEMS` (`app/(dashboard)/layout.tsx:95`) **and**
  a **"View all →" link** from the existing Command Center `EmailTriageRow` section
  (`dashboard/page.tsx:799`). [Option 3]
- A reassuring **empty-state** ("No items needing attention") — mandatory because a
  permanent top-level entry to a usually-empty page otherwise reads as a "dead mailbox."
- Rows link to the existing detail route `/dashboard/inbox/email/[emailId]`.

Explicitly **out of scope** (decoupled to a follow-up — see Non-Goals): any "connect /
set up email" capability (per-workspace inbound addresses, Gmail OAuth, Proton).

## Why This Approach

The active inbox view is *already* fully visible inline on the Dashboard (uncapped, no
"view all" today). The genuinely missing capabilities are (a) the **archived view**
(reachable only via `?status=archived`, never surfaced in UI) and (b) a **stable
destination** to return to. Reusing `GET /api/inbox/emails` (already supports
`?status=archived`, `?include_probes`) and the self-contained `EmailTriageRow`
(`{item, onChanged?}`) keeps this additive and XS — no backend, schema, or RLS change.
A client page (CTO option A) avoids re-implementing the route's non-trivial filter logic
(unfinalized-stub / probe / statutory-pin exclusion, `route.ts:18-44`).

Tabs (CPO) backed by a query param (CTO) gives both a clear mental model and a shareable
deep-link.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Nav placement | **Top-level "Inbox" entry + Command Center "View all →" link** (Option 3) | Operator's explicit call; max discoverability from both surfaces. |
| Default vs archived | **Active / Archived tabs driving `?status=archived`** | Reconciles CPO (tabs) + CTO (shareable query param); default = Active. |
| Empty-state | **Reassuring "No items needing attention"** (no connect CTA) | Top-level entry to a usually-empty page must not read as broken (CPO; single-user-incident threshold). |
| Unread badge | **Deferred (v1 has no count)** | No read/unread state model exists; YAGNI. Row status pills already convey statutory urgency. |
| Probe rows | **Default-hidden** (no `?include_probes`) | CLO: synthetic items beside real DSAR/Art.33 rows could mislead a non-technical Owner. |
| "Archived" wording | **Must NOT imply erasure** (use "Done" / "Archived — still retained") | CLO: an Owner may read "archived" as Art. 17 deletion; do not misrepresent retention. |
| Statutory visibility | **Never paginated/filtered out of sight** | CLO + API contract: statutory pinned rows are uncapped (`route.ts:31-44`); a list view must preserve that. |
| Architecture | **Client page fetching `/api/inbox/emails`** (CTO option A) | Reuses bounded API + lockstep filter logic; refetch-on-action for free. |
| Observability | **Visible error+retry state, Sentry-mirrored on client fetch failure** | `cq-silent-fallback-must-mirror-to-sentry`; mirror dashboard `ErrorCard` pattern. |
| Email connection CTA | **Decoupled to follow-up issue** | Capability does not exist; needs CLO+Ops+CTO (see Non-Goals + Capability Gaps). |
| Visual design | `knowledge-base/product/design/inbox/dashboard-inbox.pen` (screenshots 09–12) | `wg-ui-feature-requires-pen-wireframe`. |

## Open Questions

- Icon choice for the nav entry (existing icon module — inbox/mail glyph). Build-time detail.
- Max-width convention for the list page (Routines uses `max-w-5xl`; detail uses `max-w-3xl`). Spec-time.
- Tab vs sub-route for archived: decided as **tabs on one route** updating the query param (not a separate route).

## Non-Goals (this PR)

- **No "connect / set up email" capability.** The inbox is single-tenant today: one fixed
  inbound address (operator `ops@`) → `inbound.soleur.ai` (Resend Inbound / AWS SES eu-west-1,
  provisioned in `infra/dns.tf` + `infra/resend.tf`), attributed to one hardcoded owner via
  `EMAIL_TRIAGE_OWNER_USER_ID` (`email-on-received.ts:310`). There is no per-founder signup,
  no recipient-based routing, and no Gmail/Proton OAuth ingestion. Building that is a separate
  feature (see deferred issue). Gmail OAuth = major privacy/sub-processor/GDPR surface; Proton
  has no public API (Bridge/IMAP only).
- No backend / schema / RLS change (settled by #5494 / ADR-066, migration 111).
- No unread/read-state data model.
- No pagination beyond the existing `LIST_LIMIT=100` (statutory rows intentionally uncapped).

## User-Brand Impact

- **Artifact:** the `/dashboard/inbox` list page + "Inbox" nav entry (operator email-triage browse surface).
- **Vector:** the archived/full inbox view could over-expose statutory/PII triage items, or
  silently fail to render / hide a statutory item (Art. 33 72h) an Owner is responsible for acting on.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Presentation/navigation polish on an already-merged data layer (Phase 4, 0 beta
users). Recommended a sub-entry, but operator chose top-level (Option 3); the binding
consequence is a **mandatory reassuring empty-state** so a usually-empty top-level mailbox
doesn't read as broken. Naming it "Inbox" raises an unread-badge expectation — deferred v1.

### Engineering (CTO)

**Summary:** LOW risk, **XS** effort, pure additive frontend. `EmailTriageRow` reusable as-is;
use a **client page fetching `/api/inbox/emails`** (option A) to avoid duplicating the route's
filter logic. Specify view-toggle via `?status=archived`, visible error+retry with Sentry
mirror, and `segmentToDrillLevel` behavior for `/dashboard/inbox`. Files: `layout.tsx` (nav),
new `dashboard/inbox/page.tsx`, new test.

### Legal (CLO)

**Summary:** **No new compliance gate beyond #5494** — RLS already authorizes every workspace
Owner to read these rows; a browse UI changes discoverability, not authorization. Three UI
correctness guardrails (not blockers): default-hide probes, "Archived" must not imply erasure,
and statutory-clock items must never be hidden by pagination/filtering. No external-counsel trigger.

## Capability Gaps

- **Founder email onboarding / provider connection** — *Operations + Engineering + Legal.*
  Missing: any per-workspace inbound email routing or external-provider (Gmail/Proton) ingestion.
  Evidence: inbound is a single Terraform-provisioned address (`infra/dns.tf:86-126`,
  `infra/resend.tf`), attributed to one owner via `EMAIL_TRIAGE_OWNER_USER_ID`
  (`git grep -n EMAIL_TRIAGE_OWNER_USER_ID apps/web-platform/server/inngest/functions/email-on-received.ts`
  → `:310`); no OAuth email-connection code (`git grep -liE "gmail|google.*oauth.*mail|imap|proton.*bridge"`
  → none in app code). Why needed: the requested "connect/set up email" CTA has nothing real to
  link to until this exists. **Deferred to its own brainstorm.**

## Session Errors

None. Premises verified before leader spawn: PR #5494 MERGED 2026-06-17; `NAV_ITEMS`,
`EmailTriageRow`, the detail route, and `GET /api/inbox/emails` all confirmed on `main`;
no `/dashboard/inbox` list route exists (gap confirmed).
