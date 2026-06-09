---
title: Activation funnel instrumentation (Supabase)
type: feat
issue: 5049
branch: feat-funnel-instrumentation
date: 2026-06-08
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-08-waitlist-activation-funnel-brainstorm.md
spec: knowledge-base/project/specs/feat-funnel-instrumentation/spec.md
wireframe: knowledge-base/product/design/analytics/activation-funnel.pen
---

# ✨ Plan: Activation funnel instrumentation (Supabase)

## Overview

Surface an **activation funnel** on the existing admin analytics dashboard so
the PIVOT decision (`business-validation.md`, re-validated 2026-06-08) rests on
real adoption numbers. Success metric: **10 founders using 2+ domains for 2+
weeks.**

**Scope decision (post plan-review, 2026-06-08):** ship the **Supabase-derived
funnel only**. The top-of-funnel Buttondown waitlist count is **deferred to a
follow-up issue** — four plan-review agents converged that it is ~50% of the
surface for a number that does not gate the success metric, was premised on a
factual error (the `BUTTONDOWN_API_KEY` provider already exists), and carries
three real PII-leak vectors. See `## Deferred`.

Net-new work, all from existing Supabase columns:
1. A pure `computeFunnel(users, conversations, now?)` aggregate in `lib/analytics.ts`.
2. A funnel section rendered in `components/analytics/analytics-dashboard.tsx`.

No Plausible-goals funnel, no per-user join, no new Plausible props, no new
secret, no new vendor credential, no Terraform.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality (verified 2026-06-08) | Plan response |
|---|---|---|
| Count waitlist via "Buttondown API" | `BUTTONDOWN_API_KEY` already exists as a provider (`server/providers.ts:23`) with an `api.buttondown.com` validator (`token-validators.ts:57`); may be per-workspace BYOK (wrong scope for a global admin funnel). The read also transits email PII server-side. | **Deferred** to follow-up issue (see `## Deferred`). Not in this PR. |
| `workspace_status` has an error state | enum is **only** `('provisioning','ready')` (001_initial_schema.sql:11). | "Workspace ready" stage = `workspace_status = 'ready'`. |
| Activation via `onboarding_completed_at` | Column exists (012) but is client-set fire-and-forget (low fidelity). | Activation = server-derived behavior only. `onboarding_completed_at` **not read/rendered** this PR (deferred with the diagnostic). |
| `domainCount` is activation-ready | `computeMetrics.domainCount` counts domains over **all** conversations incl. `status='failed'` (`analytics.ts`). | **P0-2 fix:** `computeFunnel` computes domain count over **non-failed** conversations only. |
| Admin gate needs provisioning | `ADMIN_USER_IDS` already consumed by 6+ shipped surfaces. | Reuse; no new secret. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly (admin-only
internal dashboard) — but the founder makes the PIVOT decision on a
silently-wrong activation number (e.g., an inflated "activated" count from
counting failed-conversation domains, or an ambiguous span definition).

**If this leaks, the user's data is exposed via:** no new exposure surface — the
funnel renders aggregate counts only; no email/per-user identifier crosses to the
client or to Plausible (the existing per-user table already shows `users.email`
to admins; this PR adds aggregates only and does not widen that boundary).

**Brand-survival threshold:** single-user incident. CPO sign-off carried from
brainstorm (`USER_BRAND_CRITICAL=true`). `user-impact-reviewer` runs at PR review.

## Files to Create

- `apps/web-platform/test/analytics-funnel.test.ts` — RED-first unit tests for
  `computeFunnel`: stage counts, activation predicate, drop-off render, and the
  edge fixtures below (per `cq-test-fixtures-synthesized-only`).

## Files to Edit

- `apps/web-platform/lib/analytics.ts` — add `computeFunnel(users, conversations, now?)`
  returning `{ stages: {key,label,count,dropoffLabel}[], activatedCount, signupCount, activationDef: string }`;
  extend `UserRow` with `workspace_status`.
- `apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx` — add
  `workspace_status` to the `users` SELECT; call `computeFunnel`; pass to the dashboard.
- `apps/web-platform/components/analytics/analytics-dashboard.tsx` — render the
  funnel section above the per-user table per the wireframe (4 stage bars,
  drop-off labels, activated highlight + definition tooltip, 0-users empty state).

## Implementation Phases

### Phase 1 — Funnel compute (TDD)
- RED: `analytics-funnel.test.ts` with synthesized fixtures (see Test Scenarios).
- GREEN: implement `computeFunnel`. **Pinned definitions (P0 fixes):**
  - **Non-failed population (P0-2):** every per-user derivation uses conversations
    with `status != 'failed'`. "First conversation" stage = users with ≥1 non-failed
    conversation. Activation domain count = distinct `domain_leader` among non-failed
    conversations only.
  - **Activation (P0-1):** `nonFailedDomainCount ≥ 2` AND `(lastNonFailedSession −
    firstNonFailedSession) ≥ 14 days`. Expose this as `activationDef` and render it
    as a tooltip/label on the Activated stage so the number is read with its definition.
  - **Drop-off (P0-3):** label = drop from the **immediately preceding stage**:
    `dropoffLabel = prev === 0 ? "—" : round((prev−curr)/prev*100)+"%"`. Never emit
    `NaN%`/`Infinity%`; the zero-prior case renders `—`.
  - **Stages (P2-1):** four independent counts (signed-up, workspace-ready,
    first-conversation, activated). Document that they are not guaranteed strictly
    nested; render does not imply false nesting.

### Phase 2 — Dashboard render
- Add `workspace_status` to the SELECT; wire `computeFunnel`. Render the funnel per
  wireframe. **Empty state (P1-1):** when `signupCount === 0`, render "No signups
  recorded yet" instead of a wall of `0`/`—`.

### Phase 3 — Verify
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/analytics-funnel.test.ts`
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `computeFunnel` returns 4 stages (signed-up, workspace-ready,
  first-conversation, activated) with counts + drop-off labels.
- [ ] **P0-2:** activation domain count + first-conversation stage use **non-failed**
  conversations; the all-failed fixture asserts `activatedCount === 0` AND the user
  does not clear the first-conversation stage.
- [ ] **P0-1:** activation = `nonFailedDomainCount ≥ 2` AND span ≥ 14 days
  (last − first non-failed session); `activationDef` rendered as a tooltip/label on
  the Activated stage. No dependency on `onboarding_completed_at`.
- [ ] **P0-3:** drop-off label is relative to the previous stage; zero-prior renders
  `—` (a fixture asserts the rendered string, not just the number); no `NaN`/`Infinity`.
- [ ] **P1-1:** 0-users renders "No signups recorded yet".
- [ ] **P2-2:** exact-boundary fixtures (13.99d not activated, 14.0d activated) pass.
- [ ] `page.tsx` SELECT includes `workspace_status`; `UserRow` widened (grep
  `UserRow` consumers per `hr-type-widening-cross-consumer-grep` — only `analytics.ts`
  + `page.tsx`; both updated in lockstep).
- [ ] No Plausible interaction; `ALLOWED_PROP_KEYS` still `["path"]` (regression guard).
- [ ] No `email`/per-subscriber data in the funnel path; aggregates only.
- [ ] `tsc --noEmit` clean; vitest green.

### Post-merge (operator)
- [ ] Verify funnel renders live for an admin user via Playwright MCP against the
  admin analytics route — no ssh. (No infra/secret steps — none introduced.)

## Domain Review

**Domains relevant:** Product, Engineering, Legal (carry-forward from brainstorm).

### Engineering (CTO)
**Status:** reviewed (carry-forward + plan-review)
**Assessment:** Server emission dissolves; query Supabase. Kieran verified the
`computeFunnel` shape, schema columns, test paths, and `reportSilentFallback`
availability are sound. P0-2 (non-failed population) is the one real correctness
fix and is folded into the predicate. No capability gaps. No new infra.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** Supabase aggregate-only stays inside the #1063 internal-operational-data
ruling; no new PII surface, no per-user join. The PII-transit concern was entirely
in the deferred Buttondown read — out of scope for this PR.

### Product/UX Gate
**Tier:** blocking (mechanical UI-surface override — edits `components/analytics/analytics-dashboard.tsx`)
**Decision:** reviewed
**Agents invoked:** ux-design-lead (brainstorm Phase 3.55), spec-flow-analyzer, cpo (carry-forward)
**Skipped specialists:** none
**Pencil available:** yes — wireframe at `knowledge-base/product/design/analytics/activation-funnel.pen`

#### Findings
spec-flow-analyzer surfaced P0-1/P0-2/P0-3/P1-1/P2-1/P2-2 (all folded above). The
Buttondown-specific flow gaps (P0-4 null-conversion, P1-4 tag-write-path, P1-5
unavailable-scoping) are deferred with the Buttondown count. Wireframe is
page-level design → ux-design-lead producer requirement satisfied; the wireframe's
waitlist row + onboarding diagnostic note are deferred (see Deferred).

## Observability

```yaml
liveness_signal:
  what: admin analytics page renders the funnel section
  cadence: on-demand (admin page load)
  alert_target: none (admin-only internal tool, low traffic)
  configured_in: apps/web-platform/app/(dashboard)/dashboard/admin/analytics/page.tsx
error_reporting:
  destination: existing page error boundary (Supabase query failure) — unchanged
  fail_loud: true (existing console.error + Retry link)
failure_modes:
  - mode: Supabase users/conversations query fails
    detection: existing usersResult.error / convsResult.error branch
    alert_route: existing error UI + Retry (unchanged)
  - mode: computeFunnel returns all-zero (no signups)
    detection: signupCount === 0
    alert_route: "No signups recorded yet" empty state (not an error)
logs:
  where: existing console.error on query failure (no new log surface; no PII)
  retention: n/a (no new logging)
discoverability_test:
  command: "admin render verified via Playwright MCP against /dashboard/admin/analytics (anon → redirect to login)"
  expected_output: "funnel section present with 4 stages, or 'No signups recorded yet'"
```

## Open Code-Review Overlap

None — checked the 63 open `code-review` issues against all planned file paths; zero matches.

## Deferred

Filed as a follow-up issue (see Post-Generation): **waitlist→signup top-of-funnel
count via Buttondown**. Re-evaluation criteria + acceptance the follow-up must carry:
- Reconcile the **existing** `BUTTONDOWN_API_KEY` provider (`server/providers.ts:23`):
  is it per-workspace BYOK (encrypted vault) or a global env? A global admin funnel
  count needs a global key — determine the correct source before adding any Terraform.
- **Security mitigations (single-user-incident):** helper throws **status-only**
  errors (mirror `waitlist.ts:78`), never interpolating the response body; `fetch`
  sets `cache: "no-store"` (Next.js Data Cache would persist emails otherwise); add
  `email`/`email_address` to `server/sensitive-keys.ts`; pin the helper return to
  `{count,fetchedAt}|null` and assert the client prop carries no `results`; extend
  `test/server/sentry.beforeSend.test.ts` to assert `event.exception.values[].value`
  carries no email on failure. Note the Buttondown token is account-global/write-capable
  (no read-only scope) — state as residual risk.
- **Flow edges:** conversion % renders only when both operands present AND waitlist>0
  (else "unavailable", never 0%/NaN); verify the production embed write-path actually
  applies the `pricing-waitlist` tag before trusting the tag-filtered denominator.
- **YAGNI gate:** only build when the waitlist→signup conversion ratio is shown to be
  decision-relevant (it does not gate the success metric); at n≈10 the count is
  visible in the Buttondown dashboard.

Also deferred: the `onboarding_completed_at` drop-off diagnostic (low-fidelity
client-set field; revisit if a signup→first-conversation stall needs diagnosis).

## Risks & Mitigations

- **Ambiguous activation count** → span + non-failed population pinned in Phase 1;
  `activationDef` rendered with the number.
- **Admin/internal accounts inflating the funnel** → OPEN (see Open Questions): decide
  whether to exclude `ADMIN_USER_IDS` from funnel counts at /work time.
- **Type widening blast radius** → `UserRow` consumers grepped (only analytics.ts +
  page.tsx); updated in lockstep.

## Open Questions (carry to /work)
- Exclude `ADMIN_USER_IDS` / internal accounts from funnel counts? (P1-2 — avoids a
  signup number that disagrees with intuition.) Default: include all, note in UI.

## Test Scenarios

- `computeFunnel`: 0 users (→ empty state); 1 user no conversations; user with 1
  non-failed domain (not activated); user with 2 non-failed domains but <14-day span
  (not activated); user with 2 domains and ≥14-day span (activated); user whose only
  conversations are `status='failed'` (→ `activatedCount===0` AND not past
  first-conversation stage); exact boundary 13.99d vs 14.0d; drop-off with a
  zero-prior stage (→ rendered `—`).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails
  `deepen-plan` Phase 4.6. (Filled above.)
- `computeMetrics.domainCount` includes failed conversations — do NOT reuse it for the
  activation predicate; `computeFunnel` must scope to non-failed (P0-2).
