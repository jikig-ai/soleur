---
title: "feat: bulk archive for /dashboard/inbox (multi-select + Archive selected)"
date: 2026-09-30
slug: feat-inbox-bulk-archive
branch: feat-inbox-bulk-archive
issue: 9284
closes: 9284
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Add checkbox multi-select, per-section Select-all, and a bulk "Archive selected" action to the Active tab of `/dashboard/inbox`, backed by one thin `POST /api/inbox/bulk-archive` route that loops the existing per-id RPCs server-side with per-item outcomes. Unarchivable rows (statutory, un-acted `action_required`, acknowledged emails) are visibly excluded — disabled checkbox with reason — and re-checked server-side. No unarchive (tracked separately in #9285); "Archived" never implies deletion.

Brainstorm: `knowledge-base/project/brainstorms/2026-09-30-inbox-bulk-archive-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-inbox-bulk-archive/spec.md`. Approved wireframe: `knowledge-base/product/design/app-ui/inbox-bulk-archive.pen` (+ screenshots `01-…-selected.png`, `02-…-confirm.png`).

## Problem Statement / Motivation

`/dashboard/inbox` offers only per-item archive (`inbox-item-row` → `POST /api/inbox/[id]/state`; `email-triage-row` → `POST /api/inbox/emails/[id]/archive`). Clearing a noisy GOOD TO KNOW section is N clicks. There is no row multi-select pattern anywhere in the app — the entire interaction (checkboxes, select-all, action bar, confirm) is built new.

## Proposed Solution

Per spec FR1–FR6, tightened by spec-flow review (findings F1–F7, F9 folded in):

1. **Selection.** A `Set<"kind:id">` in `inbox-surface.tsx` (active tab only). The checkbox is rendered as a **sibling** of the row at the `Row` dispatch site (`inbox-surface.tsx:44-56`) — `<div class="flex gap-2"><input type="checkbox" …/><Row/></div>` — NOT as a prop inside the row components: rows are `role="button"` containers whose keydown `preventDefault`s bubbled keys and navigates, so a nested checkbox's Space would navigate instead of toggle (nested-interactive violation). Disabled-with-reason when unarchivable. Per-section "Select all" strip on its own line under each group header, archivable rendered rows only, indeterminate on subset, disabled when the section has none (NEEDS YOU routinely has zero — statutory pins and un-acted items live there). `+N more` overflow rows are unrendered and unreachable.
2. **Bulk bar.** Below the list when ≥1 selected: "N selected", ghost "Clear", gold `Button` "Archive N selected". Escape clears selection when no dialog is open.
3. **Confirm.** `ResponsiveModal` via `usePendingAction` — `loading={pending}` on Archive; the pending-dismissal pattern is `typed-confirm-modal.tsx`'s `onClose={pending ? undefined : onCancel}` — ResponsiveModal keys every dismiss vector (Escape, backdrop, sheet Close) off `onClose` presence, so suppressing means withholding the callback (`conversation-row` has no confirm modal — wrong precedent).
4. **Mutation.** One `POST /api/inbox/bulk-archive` call, body `{items:[{kind,id}]}` → `{results:[{id,kind,outcome}]}` (`archived|guarded|not_found|conflict|error`; predicate-ineligible → `guarded` with the reason code as a detail field — there is no separate `skipped` outcome). No client fan-out (60/min `withUserRateLimit` would trip past ~60).
5. **Outcome.** `role="status"` line ABOVE the list (sibling of `StaleRefreshBar`, `inbox-surface.tsx` header region), persisting until dismissed or the next selection change: "Archived N." plus, per outcome class, "M can't be archived until handled." (`guarded`) / "M were already handled elsewhere." (`not_found`/`conflict`) / "M failed — try again." (`error`). Non-archived ids stay selected after `mutate()` so the residual set is self-identifying; focus moves to the result line. `useSWRConfig().mutate` both keys `swrKeys.inbox("active")` + `swrKeys.inbox("archived")` (`swrKeys.inboxEmails` was removed — `swr-config.ts`; the SWR-bound `mutate` only hits the mounted key, so use the unbound one). 429 gets its own copy ("wait a moment"). Selection is pruned to rendered archivable ids on every data update (`useEffect` intersecting against the fresh list).

## Technical Considerations

- **Eligibility is ONE shared pure function, not a client/server mirror** (advisor consult — two implementations drift): new `lib/inbox-archive-eligibility.ts`, importable from both sides like `lib/inbox-severity.ts` is today. Email: `status === 'new' && statutory_class === null`; inbox: `!(severity === 'action_required' && acted_at === null) && status !== 'archived'`. It returns a **reason code** (`statutory | needs_action | already_acknowledged | already_archived | ok`) that doubles as the disabled-checkbox copy key AND the server's `guarded` outcome detail — disambiguating RPC errors: pre-classified rows are `guarded`; a `P0001` then unambiguously means `conflict`. The predicate reads `item.email.status`/`item.inbox.acted_at`/`statutory_class` directly — do NOT shortcut through `MergedInboxItem.pinned`/`outstanding` (an acknowledged non-statutory email is `pinned=false, outstanding=false` yet ineligible — the flags can't express `already_acknowledged`).
- **Server-side pre-fetch + classifier:** the bulk handler fetches submitted rows with `.in("id", ids)` on the user-context client — **chunked to ≤100 ids per query** (200 UUIDs ≈ 7.4 KB of request-line; arch review flagged ingress headroom). Do NOT reuse `server/inbox-sources.ts › fetchInboxSources` (a `LIST_LIMIT = 100` display-set query — wrong semantics for "check these ids"). Post-mig-145 the RPC itself refuses statutory archive, so the predicate's job here is three-fold: honest `guarded` outcome + reason code, no-oracle collapse (submitted id absent from fetched rows → `not_found`), and never dispatching an RPC for a pre-classified id.
- **Soft deadline in the loop** (~60 s): a cold PostgREST leg can run 20–38 s; a 200-batch must land inside the ~100 s edge window. On expiry, flush `results` with remaining ids as `outcome: "error"` — a mid-loop timeout otherwise applies some archives but returns nothing, and a disconnected client keeps mutating (Node does not abort the handler on disconnect; retries are safe — outcomes are idempotent-ish — but the result copy must acknowledge partial application may have occurred).
- **Row components stay visually untouched** except a one-line fix: gate their keydown handler on `e.target === e.currentTarget` (pre-existing bug — focused inner buttons' Space currently triggers navigation).
- **DB-level statutory guard ships in this PR** (the deferral filing gate rejected the scope-out as inside the ≤100-line inline threshold — it is folded in, per ADR-131 mechanics): mig 145 re-creates `set_email_triage_status` with `archived` rejected when `statutory_class IS NOT NULL`. The transition matrix already makes acknowledged rows terminal (`status <> 'new'` check), so the clause blocks exactly the `new`-statutory→`archived` path the UI has always hidden — turning a UI-only protection into a DB invariant.
- **Per-item outcomes over transactions:** one bad row must not strand the rest; each RPC error maps to an outcome (42501→`not_found`, P0001→`guarded`/`conflict`, else `error`).
- **Row components take no new props** — the checkbox is a sibling at the dispatch site; archived-tab dispatch renders no wrapper (no checkboxes there). Selection state + toggle/select-all/prune logic lives in a small `hooks/use-row-selection.ts` (with `keyOf({kind,id})` colocated in the eligibility lib — the `kind:id` format is a contract shared with the request body and results; `inbox-surface.tsx` is already ~276 lines).
- **Reason affordance ships** (CPO note): visible hint or accessible label on every disabled checkbox — "Statutory — must stay visible", "Awaiting your call", "Already acknowledged".
- **Checkbox hit area** ≥44px effective (padding on the cell; spec-flow F12).
- **Rate limit:** `withUserRateLimit(handler, { perMinute: 60, feature: "inbox.bulk-archive" })` — one request counts once regardless of batch size.
- **Route shape:** thin route file (`cq-nextjs-route-files-http-only-exports`) + testable handler in `server/inbox-bulk-archive-handler.ts`, mirroring `inbox-state-handler.ts`.
- **Validation:** max 200 items/request (payload DoS bound), UUID-validate every id, dedupe before dispatch.
- **Implementer traps (CTO review):** `indeterminate` on the select-all checkbox needs a ref callback (`ref={el => el && (el.indeterminate = …)}` — not a JSX attribute); the sibling wrapper needs `flex-1 min-w-0` on the row (rows render `w-full`, which overflows inside flex); the global Escape-to-clear listener must gate on confirm-dialog-open (ResponsiveModal handles its own Esc — don't rely on event ordering); the `e.target === e.currentTarget` keydown fix is an *opportunistic pre-existing-bug fix* (inner Mark done/Archive Space currently navigates), landed as its own commit — it is not what enables sibling checkboxes.

## Files to Create

- `apps/web-platform/app/api/inbox/bulk-archive/route.ts` — thin route: `export const dynamic = "force-dynamic"`, `POST = withUserRateLimit(inboxBulkArchiveHandler, { perMinute: 60, feature: "inbox.bulk-archive" })`.
- `apps/web-platform/server/inbox-bulk-archive-handler.ts` — auth'd handler: parse+validate `{items:[{kind,id}]}`, dedupe, ≤200 cap, fetch rows user-context, `isBulkArchivable` predicate, per-id RPC dispatch, per-item outcome map.
- `apps/web-platform/test/inbox-bulk-archive-handler.test.ts` — handler contract tests (see Test Scenarios).
- `apps/web-platform/supabase/migrations/145_email_triage_statutory_archive_guard.sql` + `.down.sql` — re-`CREATE OR REPLACE` `set_email_triage_status` adding, after the `status <> 'new'` check and BEFORE the GUC arms: `IF p_status = 'archived' AND v_row.statutory_class IS NOT NULL THEN RAISE EXCEPTION ... USING ERRCODE='P0001'`; refresh the function `COMMENT` to document the pin; keep the REVOKE/GRANT block for convention. Ordinal provisional (next free vs origin/main is 145 — re-check against freshly-fetched `origin/main` at merge; sibling branches claim ordinals silently — note the existing duplicate-141 drift).
- `apps/web-platform/test/migration-145-email-triage-statutory-archive-guard.test.ts` — SQL-text assertions per the `migration-122` test pattern (comment-stripped `code` body for negative assertions) AND pinning `is_email_triage_workspace_owner` + `SET search_path = public, pg_temp` in the up-file body. The down-file restores the mig **111** body verbatim — NOT 102 (111.down.sql restores the user_id-pinned ancestor; a copy-paste of the wrong ancestor passes clause assertions while silently re-pinning authz). Optionally a `verify/145` `pg_get_functiondef`-contains-`statutory_class` sentinel (verify/111 checks grants only).
- `apps/web-platform/lib/inbox-archive-eligibility.ts` — shared pure predicate + `keyOf({kind,id})` + reason codes (single source, no client/server drift; `lib/inbox-severity.ts` is the precedent).
- `apps/web-platform/lib/inbox-archive-eligibility.ts` — shared pure predicate + reason codes (advisor consult: single source, no client/server drift).

## Files to Edit

- `apps/web-platform/components/inbox/inbox-surface.tsx` — selection state, select-all strips, sibling-checkbox wrapper at the Row dispatch site, bulk bar, confirm dialog, result line, pruning effect.
- `apps/web-platform/components/inbox/inbox-item-row.tsx` — one-line keydown fix (`e.target === e.currentTarget`); no new props.
- `apps/web-platform/components/inbox/email-triage-row.tsx` — same one-line keydown fix; no new props.
- `apps/web-platform/test/inbox-surface.test.tsx` — selection/select-all/bar/result-line coverage.
- `apps/web-platform/test/lib/inbox-archive-eligibility.test.ts` — predicate truth table over every status/severity combination (enum-exhaustive per sharp edge: email `new|acknowledged|archived`, inbox `action_required|attention|info` × acted/archived).
- `apps/web-platform/test/components/inbox/inbox-item-row.test.tsx`, `email-triage-row.test.tsx` — keydown-gate regression only (no checkbox inside rows).
- `apps/web-platform/test/inbox-no-service-client.test.ts` — extend the `SERVER_MODULES` allowlist with `server/inbox-bulk-archive-handler.ts` (the walk covers `app/api/inbox/**` + listed modules; the new handler must be named explicitly or the no-service-client gate won't see it).

## Research Insights

**Repo:** `inbox-surface.tsx` (Active/Archived tabs, `mergeAndRank` ordering, `NEEDS_YOU_CAP`, overflow `+N more` banner, `StaleRefreshBar`, SWR keys `swrKeys.inbox`/`swrKeys.inboxEmails`); `inbox-item-row.tsx` (severity dot, per-row Archive guard hiding statutory/un-acted); `email-triage-row.tsx` (Acknowledge/Archive, `isStatutoryEmail`, `usePendingAction`); `app/api/inbox/[id]/state/route.ts` (thin route → `server/inbox-state-handler.ts` — the handler pattern to mirror); `server/email-triage/email-triage-status-handler.ts` (handler factory for the two email lifecycle routes); `lib/inbox-severity.ts` (`MergedInboxItem` discriminated union, `pinned`/`outstanding`); `components/ui/responsive-modal.tsx` (modal primitive, `closeOnBackdrop` default true); `hooks/use-pending-action.ts` (pending latch + focus restore); `supabase/migrations/122_inbox_item.sql` (`set_inbox_item_state` — single-id, actions `read|acted|archived`, archive-guard P0001 on un-acted `action_required`, auth 42501); `set_email_triage_status` (mig ~111: `new→acknowledged|archived`, authz 42501, **no statutory check**).

**Learnings applied:** `2026-04-24-email-triage-row-never-mutates-or-hides-statutory` (statutory exclusion must survive every render path — hence server-side re-check, not just UI); brainstorm (2026-06-18): "Archived" wording must not imply erasure; ADR-085 invariant — statutory rows are never filtered from view; `cq-nextjs-route-files-http-only-exports`; `cq-test-fixtures-synthesized-only`; #8668 fixme-stub discipline.

**Premise Validation:** issue #9284 OPEN, PR #9283 draft OPEN (verified `gh` 2026-09-30). Cited paths all confirmed on the branch: `[id]/state` route + handler, `emails/[id]/archive` handler factory, `set_inbox_item_state` signature in mig 122, `MergedInboxItem` in `lib/inbox-severity.ts`. Brainstorm claims re-verified against source this session.

**Property List:** (1) select multiple rendered rows; (2) select-all per section over archivable rows only; (3) archive the selection in one action; (4) ineligible rows are visibly and server-side excluded; (5) partial failure is reported per item; (6) no irreversible consequence without confirm.

**Cut List:** array-parameter RPC (property 3+4 already bought by looping existing RPCs — keeps guards single-sourced, no migration); client-side N-parallel calls (property 3, but trips the 60/min rate limit past ~60 ids and multiplies request auth surface); selection "mode" toggle (checkboxes are always-visible per approved wireframe); unarchive path (deferred, #9285).

**Open Code-Review Overlap:** None — `gh issue list --label code-review` bodies contain none of the planned file paths (checked 2026-09-30).

## User-Brand Impact

**If this lands broken, the user experiences:** bulk-archiving hiding or mis-filing notifications on the operator's primary triage surface — worst case an `action_required` or statutory row silently archived (the exact failure the RPC archive-guard exists to prevent).
**If this leaks, the user's [data / workflow / money] is exposed via:** a bulk endpoint that skips per-row workspace authorization → another tenant's notifications archived en masse.
**Brand-survival threshold:** single-user incident

`requires_cpo_signoff: true` set; `soleur:engineering:review:user-impact-reviewer` runs at review-time.

## Observability

```yaml
liveness_signal:    # POST /api/inbox/bulk-archive returns per-item results on every request; errors mirrored to Sentry via reportSilentFallback on 5xx paths. Cadence: per-request. Alert target: existing Sentry web-platform alert rules. Configured in: server/inbox-bulk-archive-handler.ts.
error_reporting:    # reportSilentFallback → Sentry (feature: "inbox", op: "bulk-archive", ids only — no PII). fail_loud: per-item 5xx surfaces as outcome="error" rows + a failed count in the result line.
failure_modes:      # - RPC rejects a row (P0001 guard / 42501 auth) → outcome=guarded|not_found, no alert (expected); - handler throws on connect/parse → 500 + Sentry; - 429 under repeated sweeps → client copy "wait a moment".
logs:               # Next.js function logs on the web-platform deployment; Sentry events carry feature/op/userId+itemId only.
discoverability_test:
  command:          grep -c 'inboxBulkArchiveHandler' apps/web-platform/app/api/inbox/bulk-archive/route.ts
  expected_output:  "1"
```

Field RUM: the webapp already emits Core Web Vitals through its existing instrumentation; this change adds no new page or render-path that would move LCP/INP budgets (a Set toggle + one modal).

## Guard Contract

### Guard 1 — bulk archive eligibility re-check (server-side)

**Property.** No submitted id produces an archive mutation when the row is ineligible — statutory email (any non-archived `statutory_class`), un-acted `action_required` inbox item, already-acknowledged email, or already-archived row — regardless of what the client sent; and no submitted id receives a response that reveals whether the row exists but isn't theirs (no-oracle). Post-mig-145 the statutory pin is also a DB invariant — this guard's distinct job is honest outcome classification + oracle collapse, not sole enforcement.

**Assembly.** The `items[]` loop inside `inboxBulkArchiveHandler` is the single chokepoint: every id is fetched server-side and evaluated by `isBulkArchivable(row)` before its RPC call. Two mutation targets (`set_inbox_item_state`, `set_email_triage_status`) both sit downstream of the predicate; there is no second write path (the per-id routes are separate, pre-existing, and out of this guard's scope — their own guards are unchanged).

**Mutation matrix:**

| # | Edit | Must drive RED because |
|---|------|------------------------|
| 1 | Delete the `isBulkArchivable` call so every item reaches its RPC | statutory/acknowledged emails would archive — the RPC has no statutory check |
| 2 | Narrow the predicate to `kind === "email"` only | un-acted `action_required` inbox items dispatch to `set_inbox_item_state` → P0001 → reported `conflict` (wrong class + wrong copy — "already handled elsewhere" shown for a row still needing action) |
| 3 | Submit `[eligibleEmail, statutoryEmail]` in one request (second-member row) | proves the predicate runs per-item inside the loop, not once on the batch |
| 4 | Make the predicate read client-supplied eligibility flags instead of fetched rows | a forged `archivable: true` on a statutory id must still be skipped |
| 5 | Harness row: mutate the test fixture so `fetchRow` returns `statutory_class: null` while the test still asserts `skipped` | a fixture-only pass proves the suite can't see a vacuous predicate |
| 6 | Must-pass: `[emailNew, emailNew2, inboxActedActionRequired]` all archive | an over-broad predicate (e.g. rejects anything action_required ever) must fail — acted action_required IS archivable |
| 7 | Handler echoes the raw RPC error/detail for an id absent from the fetched rows (oracle row) | a foreign-workspace id must collapse to `not_found` like missing — surfacing its RPC error verbatim re-introduces the existence oracle the 42501→404 collapse exists to kill |

**Anchor.** The predicate reads rows fetched via the user-context Supabase client at request time — the fixture set in `test/inbox-bulk-archive-handler.test.ts` is the independently reviewed registry; a weakening of the predicate can't pass by editing the same file unless the suite's fixtures are also edited (row 5 exists to catch exactly that).

## Architecture Decision (ADR/C4)

**None required.** Checked against the C4 completeness mandate — read `model.c4`, `views.c4`, `spec.c4`: external human actors (workspace Owner — `model.c4` Owner-shared surfaces), external systems (Resend ingress — modeled; no new outbound), containers/data-stores (`inbox_item` "operationalInbox" store and the email-triage WORM store both modeled with webapp mutation edges, `model.c4` ~L245/L516), access relationships (Owner-scoped reads/writes — unchanged). The change adds one HTTP route + UI affordance on already-modeled surfaces; no new substrate, trust boundary, or tenancy move. Below the ADR threshold.

## Acceptance Criteria

1. Active-tab rows render a checkbox; disabled-with-reason on statutory (`pinned`) emails, un-acted `action_required` inbox rows, and acknowledged emails.
2. Each section shows a "Select all" strip on its own line: selects all rendered archivable rows in that section; indeterminate on subset; disabled when the section has none.
3. With ≥1 selected, the bulk bar shows "N selected", "Clear", and "Archive N selected"; Escape clears selection when no dialog is open.
4. The confirm dialog is `ResponsiveModal`-based with the mandated copy; Archive runs one `POST /api/inbox/bulk-archive` `{items:[{kind,id}]}`; Escape/backdrop equals Cancel when idle and is suppressed while pending.
5. The route returns 200 `{results:[{id,kind,outcome}]}` where each id resolves to `archived|guarded|not_found|conflict|error`; predicate-ineligible ids return `guarded` + reason code and the RPC is never invoked for them; an un-acted `action_required` id in the request never reaches `set_inbox_item_state`.
6. A statutory email id in the request is never passed to `set_email_triage_status` (server-side predicate test, Guard Contract row 1/3), and the RPC itself rejects `archived` on a `statutory_class IS NOT NULL` row (mig 145; migration test asserts the clause + ERRCODE).
7. After success the list refetches (both SWR keys); archived items leave the Active tab; non-archived ids stay selected; the `role="status"` result line reports archived/guarded/already-handled/failed counts and takes focus.
8. Selection prunes to rendered archivable ids on every data update; tab switch clears it; no selection UI on the Archived tab.
9. All existing inbox tests stay green; `vitest run` on the touched surfaces + full web-platform suite passes.
10. Browser QA screenshots land under the feature's evidence dir.

## Test Scenarios

- `test/inbox-bulk-archive-handler.test.ts` — 401 unauthenticated; 400 on malformed body (>200 items, bad UUID, bad kind, dupes handled); statutory email → `guarded` + `statutory` reason (RPC never invoked); un-acted action_required → `guarded` + `needs_action` (RPC never invoked); acknowledged email → `guarded` + `already_acknowledged`; foreign-workspace id → `not_found` (RLS-invisible → absent from fetched rows, matching the 42501→404 collapse convention); all-eligible → all archived; mixed batch → per-item outcomes; 200-item bound at 201.
- `test/inbox-surface.test.tsx` (extend) — checkbox renders per row; disabled on the three ineligible classes with reason; select-all per section selects archivable-only; indeterminate; bar appears/disappears; Clear empties; result line renders split copy; selection prunes on data change.
- `test/migration-145-email-triage-statutory-archive-guard.test.ts` — up-file contains the `CREATE OR REPLACE` + statutory clause + `ERRCODE='P0001'`; comment-stripped body; down-file restores the 111 body verbatim.
- `test/inbox-no-service-client.test.ts` — new handler module added to `SERVER_MODULES`.
- `test/inbox-state-handler.test.ts`, `test/inbox-sources.test.ts`, row component tests — regression: unchanged.

## Success Metrics

- One action archives an N-item selection with correct per-item outcomes.
- Zero mutations for ineligible ids, verified by tests (not by UI assumption).
- No rate-limit trips at realistic batch sizes (≤200/request, 60 requests/min budget).

## Dependencies & Risks

- **Deferred:** unarchive lifecycle → #9285 (operator decision: confirm dialog only). The DB-level statutory guard was candidate-deferred but is folded into this PR — the filing gate classed it ≤100-line/≤4-file inline scope (ADR-131), and it ships here as mig 145 + handler predicate belt-and-suspenders.
- **Risk:** `mutate()` on both SWR keys + sequential per-id RPCs inside one request — a 200-item batch is up to ~200 sequential round-trips in one HTTP call; acceptable for the triage-volume reality (inboxes measure in tens), noted not engineered-for. (`swrKeys.inbox("active")` is shared with `inbox-nav-badge` — one `mutate` refreshes badge + list; advisor confirm.)
- **Asymmetry (documented, not fixed):** `set_inbox_item_state` silently re-archives an already-archived row (success, bumps `archived_at`) while the email RPC P0001s — same stale-request race yields `archived` vs `conflict` per kind. The `.in("id", ids)` pre-fetch mostly prevents reaching it (predicate returns `already_archived` → `guarded`); residual race documented for reviewers.
- **Bonus fix the shared module lands:** `email-triage-row.tsx` currently shows Archive on acknowledged non-statutory emails — a live UI/RPC mismatch (`acknowledged→archived` is P0001-rejected). The reason-code predicate makes the disabled state match RPC reality.
- **Risk:** migration ordinal 145 is provisional — re-check against freshly-fetched `origin/main` at merge time (sibling PRs claim ordinals silently).
- **Depends on:** nothing unmerged — all referenced code is on this branch's base.

## Domain Review

**Domains relevant:** Product, Legal & Compliance, Engineering/Architecture (carried forward from brainstorm `## Domain Assessments`)

### Product/UX Gate

**Tier:** blocking
**Decision:** reviewed
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo, soleur:product:design:ux-design-lead (at brainstorm Phase 3.55)
**Skipped specialists:** none
**Pencil available:** yes — `.pen` committed at `knowledge-base/product/design/app-ui/inbox-bulk-archive.pen`, referenced by spec FRs, operator-approved after two revision rounds.

#### Findings

- **spec-flow-analyzer:** no blockers; 8 should-fix findings folded into the plan — Clear-selection affordance + Escape (F1); skipped ids stay selected + self-identifying residual (F2); split copy by outcome class (F3); result line anchored as `role="status"` above the list (F4); dialog pending-state contract (F5); focus → result line (F6); selection pruning on refetch (F7); 429-specific copy (F9). Nice-to-haves F8/F10/F11/F12/F14 noted (row-click navigates mid-selection — acceptable per ephemeral-selection decision; archived-tab helper line; ≥44px hit area — folded into Technical Considerations).
- **CPO:** APPROVE-WITH-NOTES — all four brainstorm findings hold; notes carried forward (reason affordance must ship; statutory-guard deferral recorded — done above; `requires_cpo_signoff` satisfied by this review).
- **ux-design-lead (brainstorm):** two-frame wireframe delivered and approved; taste-profile updated (`app-ui` → `dark-minimal-existing-chrome`).

### Legal & Compliance (carried forward)

**Status:** reviewed
**Assessment:** "Archived" retains-vs-erases distinction holds (mig 019 sets `archived_at`, no delete); copy bounded to no-undo/no-deletion claims; statutory exclusion duplicated server-side satisfies belt-and-suspenders; no new data collected → low GDPR exposure.

### GDPR gate (Phase 2.7 — advisory)

Five v1 checks run against the plan's file list: no new columns/tables (Art-6/5e/17 N/A), no new vendor (Chapter-V N/A), no Art-9 columns. Extra triggers (a/c/d) absent; (b) single-user-incident is what fired the gate. Advisory note: Sentry mirroring carries ids only — already the constraint. No Critical findings; no compliance-posture row needed.

### Engineering/Architecture (carried forward)

**Status:** reviewed
**Assessment:** Option A (thin route, server loop) — reuses existing authz+guards, no migration; per-item outcomes; server-side eligibility re-check in one place.
