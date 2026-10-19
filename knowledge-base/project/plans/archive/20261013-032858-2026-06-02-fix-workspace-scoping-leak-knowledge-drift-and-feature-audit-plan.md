---
date: 2026-06-02
type: fix
branch: feat-one-shot-workspace-scoping-leak
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
user_brand_critical: true
status: plan-deepened
---

# fix: Workspace-scoping leak — knowledge-drift notification cross-workspace + feature scoping audit

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Root cause, Decisions, Phases 1-2, Acceptance Criteria, added Risks & Mitigations (precedent-diff).
**Research mode:** direct codebase grep/read (Task subagent fan-out unavailable in this environment; per-section research, precedent-diff gate 4.4, verify-the-negative pass 4.45, and the three halt gates 4.6/4.7/4.8 were executed inline).

### Key Improvements

1. **Corrected a false premise:** `kb-drift-ingest/route.ts:208` `workspace_id: operatorFounderId` is a `logger.info` structured-log field, NOT a second DB write site. The only DB write is via `insertDraftCard` (`:173`). Phase 2 updated.
2. **Refined the mutation-route risk (AC3):** `today/[id]/{send,discard,…}` routes scope card lookups by `.eq("id", messageId).eq("user_id", user.id)` — id-scoped + owner-only, so they are NOT a cross-workspace *list* leak. They do allow acting on a card from the wrong active workspace (lower severity). AC3 downgraded from "must filter" to "audit + add active-workspace guard for consistency, or record rationale".
3. **Pinned the canonical precedent:** `app/api/workspace/active-repo/route.ts:35-65` is the established active-workspace read shape (claim → solo fallback + J5 self-heal via `set_current_workspace_id` RPC). The Today route should mirror it, using `resolveCurrentWorkspaceId` directly (the route already holds a cookie-scoped tenant client).

### New Considerations Discovered

- The Today route uses `createClient()` (cookie-scoped tenant client), so `resolveCurrentWorkspaceId(userId, supabase)` works directly — no service-client read needed (unlike active-repo which uses the service client).
- `conversations.visibility` defaults to `'private'` (mig 075); a shared-team conversation only surfaces cross-member when explicitly set to `'workspace'`. Relevant to the Phase 4 conversations audit — the visibility model is a second scoping axis beyond `workspace_id`.

🐛 **Bug** + ♻️ **Scoping audit**

## Overview

On `jean.deruelle@jikigai.com`, an owner of **two** workspaces ("Soleur Workspace" and
"Chatte Workspace"), a **knowledge-drift notification** that belongs to one workspace
shows up on the other. The Today/notification surface is not cleanly scoped to the active
workspace. This plan (a) fixes the knowledge-drift notification leak end-to-end, and
(b) audits three named features — **conversations**, **conversations rate limiting**, and
**billing** — for user-vs-workspace scoping gaps, fixing or explicitly deferring each with
a tracking issue.

### Root cause (validated against code, 2026-06-02)

The KB-drift notification is a **draft action card** persisted in the `messages` table
(model established by #4579 / PR #4580). Three coupled layers produce the leak:

1. **Write pins to the SOLO workspace.** `apps/web-platform/server/messages/insert-draft-card.ts:66`
   sets `workspace_id = input.founderId` (the solo workspace per ADR-038 N2), with an
   explicit docblock (`:12-20`) stating this is intentional to avoid "cross-posting into a
   team queue". The KB-drift ingest route (`app/api/internal/kb-drift-ingest/route.ts:173`)
   attributes every finding to a single env-configured `KB_DRIFT_OPERATOR_FOUNDER_ID` — the
   payload carries **no workspace context** at all, so the card is written to the founder's
   solo workspace regardless of which workspace's KB the walker actually scanned.

2. **Read is user-scoped, NOT active-workspace-scoped.** The Today loader
   `app/api/dashboard/today/route.ts:121-128` filters by `.eq("user_id", userId)` and
   `.in("tier", …)` + `.eq("status", "draft")` — there is **no `workspace_id` filter and no
   active-workspace gate**. `messages` RLS (migration 059) is
   `is_workspace_member(workspace_id, auth.uid())`, which an owner satisfies for ALL of
   their workspaces, so RLS does not constrain the read either. Result: the same
   solo-pinned drift cards render on every workspace the user switches to.

3. **No active-workspace concept on the notification surface.** The dashboard Today section
   never consults `user_session_state.current_workspace_id` (the active-workspace
   source-of-truth, ADR-044) when loading or mutating cards.

The user's framing ("belongs to Soleur Workspace, showing on Chatte") is the *symptom*; the
*mechanism* is that the card belongs to neither — it belongs to the **solo** workspace, and
the read shows solo-workspace cards on every workspace view. The directional decision (which
workspace the drift card SHOULD belong to, and how the read scopes) is the central design
question below.

## Premise Validation

Checked, 2026-06-02 against `origin/main` and worktree HEAD:

- **`insertDraftCard` solo-pin** — CONFIRMED present and intentional
  (`insert-draft-card.ts:66`, docblock `:12-20`). The leak is a real consequence of the
  documented design, not a regression.
- **Today read user-scoping** — CONFIRMED: `today/route.ts:124` is `.eq("user_id", userId)`
  with no workspace filter. Held.
- **`messages.workspace_id` column + RLS** — CONFIRMED: added in migration 059
  (`059_workspace_keyed_rls_sweep.sql:78-107`), NOT NULL, RLS =
  `is_workspace_member(workspace_id, auth.uid())`. Held.
- **`conversations.workspace_id`** — CONFIRMED: added migration 059
  (`:44-65`), `visibility` added migration 075. Conversations ARE workspace-keyed at schema/RLS.
- **Billing on `users`** — CONFIRMED: `subscription_status` (mig 002), `stripe_subscription_id` /
  `current_period_end` (mig 020), `stripe_customer_id` unique (mig 029), `plan_tier` /
  `concurrency_override` (mig 029) all live on `public.users`. Billing is per-user.
- **Rate limiting key** — CONFIRMED: `sessionThrottle.isAllowed(userId)`
  (`ws-handler.ts:1294`); `invoiceEndpointThrottle` keyed by `user.id`
  (`rate-limiter.ts:255`); connection/pending throttles keyed by IP. None keyed by workspace.
- **`KB_DRIFT_OPERATOR_FOUNDER_ID`** is a single env value — the walker cannot today
  distinguish which of an operator's workspaces a finding belongs to. This is the
  load-bearing fact for the directional decision.
- **No prior brainstorm** for this exact branch (closest: `2026-05-29-kb-drift-messages-schema-brainstorm.md`
  #4579 which established the draft-card model, and `2026-05-29-flag-org-scoping-brainstorm.md`).
  No external premises cited that require GitHub-issue verification.
- Latest migration: **092**; next free number is **093**.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (direct plan entry). The #4579 brainstorm's claim that the
solo-pin is the correct cross-tenant guard is **true for the WRITE in isolation** but is the
*cause* of the leak once a user owns >1 workspace and the READ is unscoped. The reconciliation
the plan must carry: the solo-pin was designed when the only multi-workspace case was a
**member cross-posting into a team queue** (write-side threat); the actual leak is an
**owner of multiple OWNED workspaces seeing one workspace's card on another** (read-side gap).
Fixing the read alone (scope to active workspace) is necessary but, given the write still
pins to solo, would make the drift card visible **only** when the solo workspace is active —
likely never, if neither "Soleur" nor "Chatte" is the solo workspace. So both write and read
must change together. See Decision D1.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **Scope the Today read to the active workspace AND attribute the drift card to the workspace it describes.** Both write and read change in the same PR. | Fixing only the read hides the card (solo-pinned, solo rarely active); fixing only the write still leaks (read unscoped). The leak is the *product* of the two gaps. |
| D2 | **Drift card `workspace_id` = the workspace whose KB was scanned**, threaded from the walker, not `founderId`. The walker scans a specific `<WORKSPACES_ROOT>/<workspace_id>/knowledge-base`; that id must travel in the HMAC-signed payload. | Restores the invariant "a card belongs to the workspace it is about". Without it there is no correct workspace to scope the read to. |
| D3 | **Today read gains an explicit `.eq("workspace_id", activeWorkspaceId)` filter**, where `activeWorkspaceId = resolveCurrentWorkspaceId(userId, tenant)` (existing helper, `workspace-resolver.ts:190`). RLS stays as defense-in-depth. | Mirrors the established active-workspace read pattern (`resolveActiveWorkspaceKbRoot`, conversations-tools `repo_url` scoping). Belt-and-suspenders like the route's own existing `.eq("user_id")` comment. |
| D4 | **Conversations: confirm-and-harden, do not redesign.** Conversations are already workspace-keyed (mig 059) + visibility-gated (mig 075). The list tool scopes by `repo_url`; audit whether `repo_url` is a sound active-workspace proxy or whether an explicit `workspace_id` filter is needed; fix the dashboard "orphaned conversations" count (`dashboard/page.tsx:240`) which is cross-workspace (`.eq("user_id")` only). | Avoids gold-plating a surface that is mostly correct; targets the one cross-workspace count + the proxy question. |
| D5 | **Billing: AUDIT + document, defer redesign.** Billing/subscription is per-user by schema (`users.subscription_status`, one `stripe_customer_id` per user). For a single owner of two workspaces this is arguably correct today (one human, one subscription) — but the billing page's conversation count (`settings/billing/page.tsx:54`) is cross-workspace. Fix the misleading count or label it; file a tracking issue if per-workspace billing is a roadmap goal. | Per-workspace billing is a product/pricing decision (org-level subscription), not a bug fix. Scope this plan to the *display* gap; defer the model change with CPO input. |
| D6 | **Rate limiting: AUDIT + decide.** `sessionThrottle` is per-user (`ws-handler.ts:1294`); concurrency slots (`user_concurrency_slots`, mig 029) are per-user. Decide whether "conversations rate limiting" should be per-workspace (an owner of 2 workspaces shares one 30/hr session budget across both). Likely **keep per-user** (the budget is a per-human anti-abuse + cost ceiling tied to the per-user subscription) — but document the decision explicitly; file a tracking issue if per-workspace caps are wanted. | The session cap is coupled to the per-user plan_tier/concurrency model; making it per-workspace without a per-workspace billing model would let one user multiply their paid capacity by creating workspaces. |
| D7 | **Migration 093 is OPTIONAL.** If D2 backfill is needed (re-attribute existing solo-pinned drift cards to their true workspace), a data migration may be required. If the walker can simply start writing the right `workspace_id` going forward and stale solo cards are acceptable to discard/expire, no migration is needed. Decide during deepen-plan after counting existing drift rows (read-only prod probe). | Avoid a forward-only migration unless backfill is genuinely required. |

## User-Brand Impact

**If this lands broken, the user experiences:** a knowledge-drift notification for one
workspace continues to appear on an unrelated workspace's dashboard (the exact reported bug),
OR — if the active-workspace filter is too tight — the drift notification disappears entirely
(false-negative: operator never sees real KB drift).

**If this leaks, the user's workflow/data is exposed via:** a draft action card describing
one workspace's knowledge-base drift (which can embed file paths, doc structure, and
domain-internal content) surfacing in the dashboard of a *different* workspace the operator
is viewing — cross-workspace context bleed. For a future multi-tenant team workspace this
generalizes to one tenant's draft queue leaking into another tenant's view.

**Brand-survival threshold:** single-user incident. One operator owning two workspaces
already reproduces it; the messages-table read path is the same surface a shared team
workspace would use, so a single leak is a tenant-isolation failure, not a cosmetic glitch.

> **CPO sign-off required at plan time before `/work` begins.** Invoke the CPO domain leader
> (or confirm CPO reviewed this plan) before implementation. `user-impact-reviewer` will be
> invoked at review-time per `review/SKILL.md`.

## Implementation Phases

> NEVER CODE during planning. Phases below are the implementation contract for `/work`.

### Phase 0 — Preconditions (verify before any edit)

- [ ] `grep -n "workspace_id" apps/web-platform/server/messages/insert-draft-card.ts` —
      confirm solo-pin at `:66` unchanged.
- [ ] `grep -n "user_id\|workspace_id" apps/web-platform/app/api/dashboard/today/route.ts` —
      confirm no workspace filter present (the gap this PR closes).
- [ ] `grep -nE "^export (async )?function resolveCurrentWorkspaceId" apps/web-platform/server/workspace-resolver.ts`
      — confirm the helper signature `(userId, supabase) => Promise<string>` is current
      (it is, `:190`).
- [ ] Read the KB-drift walker payload schema (Zod) in `kb-drift-ingest/route.ts` — confirm
      it does NOT carry `workspace_id` today and identify where to add it.
- [ ] Read-only prod probe (Supabase MCP, project `ifsccnjhymdmidffkzhl`, DEV first per
      `hr-dev-prd-distinct-supabase-projects`): count existing `messages` rows where
      `source = 'kb_drift'` to size the D7 backfill decision. Read-only; no writes to prod.
- [ ] Identify the KB-drift walker producer (the cron/Inngest function or workflow that
      POSTs to `/api/internal/kb-drift-ingest`) and confirm it knows the scanned
      `workspace_id` so D2 can thread it. File: `apps/web-platform/infra/kb-drift.tf` and the
      walker source (locate via `git grep -l "kb-drift-ingest\|KB_DRIFT"`).

### Phase 1 — Fix the knowledge-drift notification leak (read scoping) [TDD: write failing test first]

1. **`app/api/dashboard/today/route.ts`** — resolve the active workspace and add the filter:
   - Resolve `activeWorkspaceId = await resolveCurrentWorkspaceId(userId, supabase)` (import
     from `@/server/workspace-resolver`). The route already has a tenant/cookie client.
   - Add `.eq("workspace_id", activeWorkspaceId)` to the select chain alongside the existing
     `.eq("user_id", userId)`.
   - Update the route docblock (`:16-18`) to state the active-workspace scoping invariant.
2. **Sibling mutation routes** — `app/api/dashboard/today/[id]/{send,edit,discard,cancel,cost,undo}/route.ts`:
   audit each. They mutate a card by `id`; confirm each verifies the card belongs to the
   **active** workspace (not just `user_id`), or relies on RLS + an explicit
   `.eq("workspace_id", activeWorkspaceId)` guard. A card-by-id mutation that an owner can
   perform from the wrong active workspace is the IDOR-adjacent sibling of the read leak.
   List each file in *Files to Edit* with its disposition (fix vs. already-safe-with-rationale).
3. **Tests (RED→GREEN):** add a route test seeding two workspaces for one owner, a drift card
   in workspace A, assert the Today loader returns it only when A is active and NOT when B is
   active. Use `apps/web-platform/test/api/dashboard/today/` convention; verify the runner via
   `package.json scripts.test` + `vitest.config.ts include:` globs (per Sharp Edge — co-located
   tests are skipped; place under `test/`).

### Phase 2 — Attribute the drift card to the correct workspace (write scoping)

1. **Walker payload** — add `workspace_id` to the HMAC-signed `/api/internal/kb-drift-ingest`
   payload Zod schema and to the producer that POSTs it. The walker scans
   `<WORKSPACES_ROOT>/<workspace_id>/knowledge-base`, so the id is known at scan time.
2. **`insert-draft-card.ts`** — add an **explicit optional `workspace_id` override param**
   (the docblock at `:12-20` already prescribes this exact extension path: "A future caller
   that genuinely needs a non-solo workspace must add an explicit override param"). Default
   remains the solo-pin for github-on-event / cfo callers that are genuinely founder-identity
   rows; KB-drift passes the scanned `workspace_id`.
3. **`kb-drift-ingest/route.ts`** — pass `workspace_id` from the validated payload into
   `insertDraftCard`. **Note (deepen correction):** the `workspace_id: operatorFounderId` at
   `:208` is a `logger.info` structured-log FIELD, not a DB write — the only persist is via
   `insertDraftCard` at `:173`. Update the log field to the real scanned `workspace_id` for
   log accuracy, but it is not a leak source.
4. **Tests:** assert a KB-drift POST for workspace A writes a card with `workspace_id = A`,
   not `founderId`.

### Phase 3 — Decide + apply the optional migration 093 (D7)

- If Phase 0 prod probe shows existing solo-pinned `kb_drift` rows that must be re-homed:
  write `093_reattribute_kb_drift_drafts.sql` (+ `.down.sql`) following the most recent
  migration's conventions (`ls apps/web-platform/supabase/migrations/ | tail`; read 090-092
  for the txn-wrapped / no-CONCURRENTLY constraints). Forward-only if it drops/relabels rows.
- If forward-only writes suffice (stale solo cards expire/discard acceptably), record
  "no migration" with rationale and SKIP.

### Phase 4 — Audit: conversations (D4)

1. **Dashboard orphaned-conversations count** (`dashboard/page.tsx:240`): the
   `.eq("user_id", auth.user.id).not("repo_url", "is", null)` count is cross-workspace.
   Decide: scope to active workspace (`.eq("workspace_id", activeWorkspaceId)`) or document
   why a cross-workspace count is intended for the "reconnect repo" hint.
2. **Conversations list tool** (`server/conversations-tools.ts:163`): it scopes by
   `repo_url` (active workspace's repo). Audit whether two workspaces could share a `repo_url`
   (then the tool would mix them) — if so, add `.eq("workspace_id", activeWorkspaceId)`.
   Record finding; fix or document.
3. Enumerate every other `from("conversations")` site (grep list in Research Insights) and
   classify each as workspace-correct / user-scoped-by-design / needs-fix. Per
   AGENTS.md `hr-write-boundary-sentinel-sweep-all-write-sites`, sweep ALL sites, not just the
   helper.

### Phase 5 — Audit: rate limiting (D6) + billing (D5)

1. **Rate limiting:** document the per-user keying of `sessionThrottle` (`ws-handler.ts:1294`)
   and `user_concurrency_slots` (mig 029). Decide keep-per-user (recommended, D6 rationale) vs
   per-workspace. If keep: add a one-line invariant comment at the call site explaining the
   coupling to the per-user plan_tier model. If change wanted: file a tracking issue (do NOT
   implement per-workspace caps in this PR — it couples to billing).
2. **Billing:** the billing page conversation count (`settings/billing/page.tsx:54`,
   `.eq("user_id", user.id)`) is cross-workspace and may mislead. Decide: scope to active
   workspace, or relabel as "across all your workspaces". Confirm `const workspaceId = user.id`
   solo-assumption at `:30` is acceptable for the billing pane (it is, for per-user billing) or
   note the gap. File a tracking issue for per-workspace/per-org billing IF it is a roadmap goal
   (`knowledge-base/product/roadmap.md`), with CPO input.

### Phase 6 — Verify

- Run the full affected test surface via `package.json scripts.test` (vitest). RED→GREEN for
  Phases 1, 2; audit assertions for 4, 5.
- `tsc --noEmit` for the web-platform package.
- Manual/Playwright check (optional): two-workspace owner, drift card on A, switch to B,
  confirm absence.

## Files to Edit

- `apps/web-platform/app/api/dashboard/today/route.ts` — add active-workspace filter (Phase 1).
- `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts` — audit workspace guard.
- `apps/web-platform/app/api/dashboard/today/[id]/edit/route.ts` — audit workspace guard.
- `apps/web-platform/app/api/dashboard/today/[id]/discard/route.ts` — audit workspace guard.
- `apps/web-platform/app/api/dashboard/today/[id]/cancel/route.ts` — audit workspace guard.
- `apps/web-platform/app/api/dashboard/today/[id]/cost/route.ts` — audit workspace guard.
- `apps/web-platform/app/api/dashboard/today/[id]/undo/route.ts` — audit workspace guard.
- `apps/web-platform/server/messages/insert-draft-card.ts` — add explicit `workspace_id` override param (Phase 2).
- `apps/web-platform/app/api/internal/kb-drift-ingest/route.ts` — thread scanned `workspace_id` (Phase 2); fix `:208` second write site.
- KB-drift walker producer (Inngest fn / workflow — locate in Phase 0) — add `workspace_id` to payload.
- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — orphaned-conversation count scoping (Phase 4).
- `apps/web-platform/server/conversations-tools.ts` — conversations list workspace-proxy audit (Phase 4).
- `apps/web-platform/app/(dashboard)/dashboard/settings/billing/page.tsx` — conversation-count label/scope (Phase 5).
- `apps/web-platform/server/ws-handler.ts` — session-throttle invariant comment OR no change + tracking issue (Phase 5).
- Tests under `apps/web-platform/test/api/dashboard/today/` and `apps/web-platform/test/` (Phase 1, 2 — verify vitest `include:` globs).

## Files to Create

- `apps/web-platform/supabase/migrations/093_reattribute_kb_drift_drafts.sql` (+ `.down.sql`) — **only if** Phase 0/3 backfill decision requires it.
- New tests for the two-workspace leak repro (paths per vitest `include:` globs).

## Open Code-Review Overlap

To be populated at `/work` time after the final Files-to-Edit list is frozen
(`gh issue list --label code-review --state open --json number,title,body` then `jq --arg path …`).
Recorded here as a deferred check, not yet run.

## Risks & Mitigations

### Precedent-diff (gate 4.4) — active-workspace read scoping

**Pattern:** scope a read/mutation to the caller's ACTIVE workspace (claim → solo fallback).
**Precedent (canonical):** `app/api/workspace/active-repo/route.ts:35-65` and the shared
helper `server/workspace-resolver.ts:190` (`resolveCurrentWorkspaceId`) +
`resolveActiveWorkspaceKbRoot:271` (full claim→solo→J5-self-heal variant).

Side-by-side:

| Concern | Precedent (active-repo) | This plan (Today route) |
|---|---|---|
| Active id source | `user_session_state.current_workspace_id` via service client | `resolveCurrentWorkspaceId(userId, supabase)` via the route's existing cookie tenant client |
| Fallback | solo (`= userId`), never a sibling | same (helper guarantees this) |
| J5 self-heal | resets claim via `set_current_workspace_id` RPC on a non-member claim | NOT needed on a GET (read-only; helper falls back to solo without a corrective write — same posture as `resolveActiveWorkspaceKbRoot` which is explicitly read-only) |
| Defense-in-depth | RLS + explicit filter | RLS (`is_workspace_member`) + explicit `.eq("workspace_id", active)` |

**Divergence (intentional):** the Today route should use `resolveCurrentWorkspaceId` (the
helper) rather than re-implementing the inline `user_session_state` read, because it already
has a tenant client and the helper centralizes the solo-fallback invariant. Do NOT copy
active-repo's service-client read — that would be a gratuitous privilege escalation on a
read the tenant client already covers.

**No novel pattern introduced.** Both write-override (`insertDraftCard` optional param) and
read-scoping (`resolveCurrentWorkspaceId` + `.eq`) follow established precedents.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (read scoping):** `today/route.ts` select chain includes
      `.eq("workspace_id", <activeWorkspaceId>)`; a route test proves a drift card in
      workspace A is returned only when A is active and absent when B is active.
- [ ] **AC2 (write attribution):** a KB-drift ingest POST carrying `workspace_id = A`
      produces a `messages` row with `workspace_id = A` (test asserts the persisted value,
      not just no-error).
- [ ] **AC3 (sibling routes):** every `today/[id]/*` mutation route is audited. Each currently
      scopes by `.eq("id", messageId).eq("user_id", user.id)` (+ RLS) — id-scoped, owner-only,
      so NOT a cross-workspace list leak. Either add an active-workspace guard for consistency
      with the read fix, OR record per-route rationale that id+user+RLS scoping is sufficient
      (a card-by-id action an owner takes is owner-attributed regardless of active workspace).
- [ ] **AC4 (conversations audit):** the dashboard orphaned-count and the list-tool
      `repo_url` proxy each have a recorded disposition (fixed / safe-with-rationale).
- [ ] **AC5 (rate-limit + billing audit):** session-throttle keying decision recorded
      (keep-per-user OR tracking issue filed); billing conversation-count display gap fixed
      or relabeled; per-workspace-billing deferral issue filed IF on roadmap.
- [ ] **AC6:** `tsc --noEmit` clean; affected test suite green via `package.json scripts.test`.
- [ ] **AC7:** if migration 093 is created, it is read-only-reversible or forward-only-documented
      and follows 090-092 conventions; if skipped, the skip rationale is in the PR body.

### Post-merge (operator)

- [ ] **AC8:** if migration 093 created — apply via the canonical migration pipeline
      (`web-platform-release.yml#migrate` runs on merge; do NOT prescribe a separate SSH apply).
      Verify via Supabase MCP read-only that `kb_drift` rows now carry the correct `workspace_id`.

## Domain Review

**Domains relevant:** Engineering (tenant isolation / RLS), Product (workspace model, billing
display), Legal/Compliance (cross-workspace data bleed on `messages` — GDPR Art. 5 purpose
limitation / data minimization).

(Domain-leader subagent invocation deferred — Task subagent spawning was unavailable in the
planning environment; the CPO/CTO/CLO framing from the #4579 brainstorm carries forward, and
deepen-plan will spawn the domain triad given `brand_survival_threshold: single-user incident`.)

### Product/UX Gate

**Tier:** advisory (modifies existing dashboard data loaders + billing display; no new
user-facing page or component file). **Decision:** auto-accepted (pipeline). No new
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files created.

## GDPR / Compliance Gate

This plan touches a regulated-data surface (`messages` table, RLS policies, possibly a
migration, API routes carrying third-party-ingested KB content). `/soleur:gdpr-gate` MUST run
at deepen-plan against this plan + the FR/AC sections. Likely fold-ins at single-user-incident
threshold: cross-workspace `messages` visibility (purpose limitation), and whether re-homing
existing drift rows (migration 093) constitutes a processing-activity change requiring an
Article 30 register note.

## Infrastructure (IaC)

No new infrastructure (servers, secrets, vendors, cron, DNS). The KB-drift walker already
exists (`apps/web-platform/infra/kb-drift.tf`); Phase 2 adds a field to its existing payload,
not a new resource. `KB_DRIFT_OPERATOR_FOUNDER_ID` env already provisioned. Skip.

## Observability

```yaml
liveness_signal:
  what: Today-loader request success rate + KB-drift ingest insert/dedup ratio
  cadence: per-request (read) / nightly (walker)
  alert_target: Sentry (existing reportSilentFallback in today/route.ts + insert-draft-card.ts)
  configured_in: apps/web-platform/app/api/dashboard/today/route.ts (reportSilentFallback), apps/web-platform/server/messages/insert-draft-card.ts
error_reporting:
  destination: Sentry via reportSilentFallback (already wired on both read and write paths)
  fail_loud: yes — insert-draft-card re-throws all non-dedup errors; today/route returns 500 + mirrors
failure_modes:
  - mode: active-workspace filter too tight (drift card never shows)
    detection: route test asserts presence when correct workspace active; KB-drift insert/dedup counter in Sentry breadcrumb shows inserts but Today shows zero items
    alert_route: Sentry
  - mode: walker payload missing workspace_id (Zod reject)
    detection: kb-drift-ingest returns 400 + Sentry.captureMessage (existing pattern at route)
    alert_route: Sentry
  - mode: cross-workspace card still visible (leak not fixed)
    detection: two-workspace route test (AC1) fails in CI
    alert_route: CI red
logs:
  where: pino structured logs (server) + Sentry; existing logger.error in today/route.ts
  retention: existing Better Stack / Sentry retention (unchanged)
discoverability_test:
  command: ./node_modules/.bin/vitest run apps/web-platform/test/api/dashboard/today/
  expected_output: two-workspace leak repro test passes (card scoped to active workspace)
```

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **Fixing only the read OR only the write does not fix the leak** — the bug is the product of
  both (solo-pinned write + unscoped read). See D1/Research Reconciliation. Resist the
  temptation to ship a one-line `.eq("workspace_id")` and call it done; without the write fix
  the card becomes invisible instead of correctly-scoped.
- **`messages` RLS is NOT the guard** — `is_workspace_member(workspace_id, auth.uid())` passes
  for an owner across ALL owned workspaces. The application-layer `.eq("workspace_id", active)`
  is the actual scoping; RLS is defense-in-depth only.
- **Do not make rate limiting per-workspace without per-workspace billing.** Per-user session
  caps are coupled to the per-user `plan_tier`/`concurrency_override` model; per-workspace caps
  would let one user multiply paid capacity by creating workspaces. (D6.)
- **Test file placement:** `apps/web-platform/vitest.config.ts include:` only collects
  `test/**` — a co-located `app/api/.../route.test.ts` is silently never run. Place new tests
  under `apps/web-platform/test/`.
- **Migration 093 forward-only:** if a backfill migration is written, it is txn-wrapped by
  Supabase's runner — no `CONCURRENTLY`, no `VACUUM` (see migrations 025/027/029 comments).
- **`Closes #N` vs `Ref #N`:** if migration 093 is created and applied post-merge, use
  `Ref #<issue>` in the PR body and close the issue in the post-merge AC8 step, not `Closes`.
