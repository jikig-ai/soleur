---
date: 2026-05-21
issue: 4224
pr: 4226
spec: knowledge-base/project/specs/feat-workspace-reconciliation-4224/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-21-workspace-reconciliation-brainstorm.md
branch: feat-workspace-reconciliation-4224
worktree: .worktrees/feat-workspace-reconciliation-4224/
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
domain_leaders: [cpo, clo, cto]
type: feature
classification: webhook + ui
deferred_issues: [4228]
plan_review_applied: [dhh, kieran, code-simplicity]
---

# Plan: Periodic Workspace Reconciliation with Main (#4224)

## Overview

Operator workspace clones at `userData.workspace_path/knowledge-base/` drift hours/days behind the operator's connected default branch because no background reconciliation exists; only session-boundary `syncPull`/`syncPush` and KB-mutation `syncWorkspace` trigger pulls. This plan adds a GitHub `push` webhook dispatch branch that fires the existing `syncWorkspace(installationId, workspacePath, log, ctx)` helper via a new dedicated Inngest function, plus a KB-viewer staleness signal (single `KbSyncStatus` chip with synced / out-of-sync states and an inline "Sync now" affordance), plus a Sentry-mirror sweep across the existing `syncWorkspace` / `syncPull` / `syncPush` callers (two of which silently swallow failures today — fix inline per brainstorm CTO workflow-gate, not split to a separate PR per DHH dissent).

Triad-endorsed (CPO + CLO + CTO) Approach A. Brand-survival threshold = single-user incident (operator endorsed cross-tenant / credential-exposure failure modes during the Phase 0.1 framing).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| spec.md FR1: "Extend `GITHUB_EVENT_STRATEGIES` with a `push` action class" | `GITHUB_EVENT_STRATEGIES` is shaped for message-drafting (`owningDomain`, `sourceRefPrefix`, `urgency`, `redactSource`). `push` doesn't fit. | Do NOT extend the strategy table. Add a parallel dispatch branch in `route.ts` AFTER founder-lookup + `workflow_run` gate, BEFORE the `HEADER_TO_ACTION_CLASS` lookup. Dispatch directly to a new Inngest event `platform/workspace.reconcile.requested`. |
| spec.md implicit: scope_grant gating like other webhook events | Existing webhook (`route.ts:256`) gates dispatch on `isGranted(supabase, founderId, actionClass)`. Workspace reconciliation is structurally NOT an `ActionClass` (per ADR-034). GitHub App install IS the consent surface per CLO carry-forward (Art. 6(1)(b)). | Branch BEFORE the grant check with inline comment citing CLO finding, ADR-034, and this plan. New event class never enters `ACTION_CLASSES` taxonomy (free-form Inngest event name, no `EventSchemas` registry exists today per `inngest/client.ts` grep). |
| spec.md FR5: append rich `{ at, trigger, sha_before, sha_after, ok, error_class }` to `users.kb_sync_history` | Existing column shape is `Array<{ date: string; count: number }>` (migration 017; `session-sync.ts:286`). RLS prevents client-side updates (server-side only). | Heterogeneous JSONB: legacy `{ date, count }` rows from `recordKbSyncHistory` stay untouched; new rows from webhook-push + manual-sync carry the richer shape. Reader inlines a 12-line discriminator at the badge consumer (NO separate `lib/kb-sync.ts` module — Simplicity #1, DHH #2). Write-side: new `appendKbSyncRow(userId, row)` helper next to `recordKbSyncHistory` in `session-sync.ts`; existing `recordKbSyncHistory` signature is NOT widened (Simplicity #3). |
| spec.md TR1: "in-process mutex per `installation_id`" | Inngest CEL concurrency key is the canonical cross-process primitive. In-process Map is YAGNI defense-in-depth (DHH #1). | Use ONLY Inngest CEL `concurrency: [{ key: "'wsr-' + event.data.installationId", limit: 1 }]` for coalescing. No in-process Map. No throttle (CEL already serializes; `--ff-only` makes redundant pulls idempotent; Simplicity #8). |
| spec.md TR2: Sentry-mirror via inline `Sentry.captureException` | Canonical helper is `reportSilentFallback(err, { feature, op, extra, message })` at `observability.ts:138` (40+ sites; pseudonymizes `userId → userIdHash` per Recital 26). Per PR #3731 sharp-edge: explicit `message:` arg required to preserve dashboard keying. Existing per-file tag taxonomy: `feature: "kb-route-helpers"` (kb-route-helpers sites), `feature: "session-sync"` (session-sync sites) — Kieran #3. | Use `reportSilentFallback` with EXPLICIT `message:` arg and existing per-file `feature` tag at each site. Reserve NEW tag `feature: "workspace-reconcile-push"` strictly for the new Inngest function. |
| Implicit: "Sync now" reuses existing endpoint | No endpoint accepts an authenticated operator-initiated workspace-sync request. | Create `POST /api/kb/sync` at `apps/web-platform/app/api/kb/sync/route.ts`. Auth-gated; resolves `workspace_path` SERVER-SIDE from `session.user_id` (never accepts from request body); calls `syncWorkspace` directly (NOT via webhook re-emission — must be webhook-independent per spec-flow EC2.10). |

## User-Brand Impact

**If this lands broken, the user experiences:** stale KB tree in the webapp KB viewer (deletions / renames / uploads on operator's default branch not reflected; merges to main missing) OR contradictory state — badge says "Synced 2m ago" while latest sync actually failed. Operator may act on stale source-of-truth (trust breach).

**If this leaks, the user's workspace data is exposed via:** mis-routed `syncWorkspace` invocation pulling into the wrong operator's `workspace_path`. Mitigated by: (a) install-scoped `gitWithInstallationAuth` (existing), (b) write-scope test in Phase 2 covering `installation_id → user_id → workspace_path` AND concurrent two-installation isolation (Kieran #8), (c) Inngest CEL key scoped to `installation_id` (no cross-operator coalescing).

**Brand-survival threshold:** single-user incident. Carry-forward from brainstorm Phase 0.1 framing. CPO sign-off REQUIRED before `/work` — brainstorm Phase 0.5 CPO assessment covers this; reaffirm before starting Phase 1.

## Open Code-Review Overlap

None. 74 open `code-review` issues scanned; zero matches against expected Files to Edit.

## Files to Edit

- `apps/web-platform/app/api/webhooks/github/route.ts` — insert `push` dispatch branch **AFTER** founder lookup (around line 230) and **AFTER** the `workflow_run` conclusion gate (around line 218), **BEFORE** the `actionClass = HEADER_TO_ACTION_CLASS[githubEvent]` lookup (line 256). On `inngest.send` failure, call `releaseDedupRow()` per the existing pattern (line 309–315). Inline comment must cite ADR-034 (`ACTION_CLASSES` union stays closed) + CLO Art. 6(1)(b) + this plan.
- `apps/web-platform/server/kb-route-helpers.ts:282` — `syncWorkspace`: add `reportSilentFallback(syncError, { feature: "kb-route-helpers", op: \`workspace-sync-${context.op}\`, extra: { userId: context.userId, workspacePath }, message: \`kb/${context.op}: workspace sync failed\` })` before the existing `{ok:false}` return. Preserves existing pino literal as `message:`. Tag is `kb-route-helpers` to match existing tag taxonomy at that file.
- `apps/web-platform/server/session-sync.ts:380` — `syncPull` catch block: add `reportSilentFallback(err, { feature: "session-sync", op: "syncPull", extra: { userId, workspacePath }, message: "Sync pull failed — continuing with local state" })`.
- `apps/web-platform/server/session-sync.ts:451` — inner `recordKbSyncHistory` catch (called from `syncPush`): add `reportSilentFallback(err, { feature: "session-sync", op: "recordKbSyncHistory", extra: { userId, workspacePath }, message: "KB sync history recording failed" })`.
- `apps/web-platform/server/session-sync.ts:457` — `syncPush` catch block: add `reportSilentFallback(err, { feature: "session-sync", op: "syncPush", extra: { userId, workspacePath }, message: "Sync push failed — next session will retry" })`.
- `apps/web-platform/server/session-sync.ts:266` (adjacent) — add new helper `appendKbSyncRow(userId, row)` writing the richer shape. Reuses fetch/update/cap-100 logic from `recordKbSyncHistory` but does NOT widen `recordKbSyncHistory` itself.
- `apps/web-platform/components/kb/kb-content-header.tsx` — mount `<KbSyncStatus lastSync={lastSync} />` in the right-side action group beside `SharePopover`.
- `apps/web-platform/components/kb/kb-desktop-layout.tsx` and `kb-mobile-layout.tsx` — thread `lastSync` from layout state into the header (single prop addition each; grep at /work time to confirm exact prop propagation surface).
- `apps/web-platform/hooks/use-kb-layout-state.ts` (or `kb-context.tsx` if state lives there per grep at /work) — extend layout state hook with `lastSync` field fetched alongside the tree (one read of latest `kb_sync_history` row per layout mount; client-cached, refetched on `KbSyncStatus`'s "Sync now" click resolving).
- `knowledge-base/legal/article-30-register.md` — PA-17 row cell amendment under (b) Purposes AND (g) TOMs. **Wording MUST distinguish "display-only signal ingestion" (existing PA-17 scope) vs "workspace clone reconciliation — filesystem write side-effect" (new sub-bullet)** per Kieran #10. Update `last_updated:` to today.
- `docs/legal/data-protection-disclosure.md` §2.3(r) — append one sentence clarifying workspace synchronization runs outside the operator's session on receipt of a GitHub `push` webhook. Update `last_updated:` to today.

## Files to Create

- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — Inngest function. Listens on `platform/workspace.reconcile.requested`. Concurrency CEL `[{ key: "'wsr-' + event.data.installationId", limit: 1 }]`. No throttle. Fetches user row by `event.data.founderId`, branches on `workspace_status !== "ready"` (skip + append row + `reportSilentFallback` with `feature: "workspace-reconcile-push"`, `op: "skip-not-ready"`, `message: "Workspace not ready — skipping reconcile"`), otherwise calls `syncWorkspace` + appends rich row.
- `apps/web-platform/app/api/kb/sync/route.ts` — `POST` route. Auth: session required; rate-limit per existing `rate-limiter.ts` (6/min/operator default — tune at /work if convention differs). Server-side: resolves `workspace_path` from `session.user_id` (NEVER from request body). 409 + structured error on `workspace_status !== "ready"`. Calls `syncWorkspace`, appends `{ trigger: "manual" }` row, returns `{ ok, at, sha_before?, sha_after?, error_class? }`. Webhook-independent.
- `apps/web-platform/components/kb/kb-sync-status.tsx` — single component covering badge + button. Two primary states: `synced` (renders `<RelativeTime at={row.at} prefix="Synced" />`; clicking opens a small popover with "Sync now") and `desync` (renders chip "Workspace out of sync — reconnect"; clicking calls `/api/kb/sync` for transient errors or opens reconnect modal for `non_fast_forward`). Implicit in-flight overlay during sync (spinner + disabled). Empty-state (no rows) renders `synced` variant with copy "Workspace ready" — Kieran/Simplicity converge: this avoids a third dedicated state.
- `apps/web-platform/test/server/webhook-push-dispatch.test.ts` — RED tests for the dispatch branch.
- `apps/web-platform/test/server/workspace-reconcile-on-push.test.ts` — RED tests for the Inngest function + write-scope + cross-tenant concurrent (load-bearing TOMs in one file).
- `apps/web-platform/test/server/kb-sync-route.test.ts` — RED tests for `POST /api/kb/sync`.
- `apps/web-platform/test/components/kb-sync-status.test.tsx` — RED tests for the merged status component (both states + in-flight + empty-state + 409 toast).

## Implementation Phases

### Phase 1: Webhook Push Dispatch Branch

RED: `webhook-push-dispatch.test.ts` covers (Kieran #6 — 9 cases total):
1. `ref === "refs/heads/<default_branch>"`, after !== zeros → dispatches `platform/workspace.reconcile.requested` with `{ founderId, installationId, deliveryId, defaultBranch, headSha, beforeSha }`.
2. `ref === "refs/tags/v1"` → drop, no dispatch, 200 received.
3. `after === "0000000000000000000000000000000000000000"` (branch deletion) → drop, no dispatch.
4. **New (Kieran #6a):** `before === "0000...0"`, after !== zeros, ref === default branch (initial creation of default branch) → SHOULD dispatch.
5. `ref === "refs/heads/feature-x"` (non-default) → drop, no dispatch.
6. **New (Kieran #6c):** `ref === "refs/heads/main"` AND `repository.default_branch === "develop"` → drop (operator's default is develop, not main).
7. **New (Kieran #6b):** Malformed payload (missing `repository.default_branch`) → drop with 200 received; pino warn; no Sentry error.
8. No `installation.id` → drop (existing behavior).
9. Unmapped `installation_id` → 404 (existing behavior); zero `inngest.send` calls; AND `releaseDedupRow` called (Kieran #1).

GREEN: Edit `route.ts` per Files to Edit. Branch inserted after founder lookup (line ~230) + workflow_run gate (line ~218), before HEADER_TO_ACTION_CLASS (line 256). On `inngest.send` throw: `releaseDedupRow()` + 500.

REFACTOR: Extract `isReconcilablePush(body): { ok: true, defaultBranch, headSha, beforeSha } | { ok: false, reason: string }` for testability.

### Phase 2: Inngest Function + Write-Scope + Cross-Tenant Concurrent (Load-bearing TOMs)

RED: `workspace-reconcile-on-push.test.ts` covers:
- Happy path: founderId resolves, workspace_status=ready, syncWorkspace returns ok → `kb_sync_history` row `{ at, trigger: "webhook_push", sha_before, sha_after, ok: true, push_received_at, sync_completed_at }`.
- ff-only failure: syncWorkspace returns `{ok:false}` → row `{ ok:false, error_class:"non_fast_forward" }`; `reportSilentFallback` invoked with `feature:"workspace-reconcile-push"`, `op:"sync"`, `message:"Workspace sync failed"`.
- workspace_status=cloning: skip; row `{ ok:false, error_class:"workspace_not_ready" }`; Sentry mirror with `op:"skip-not-ready"`.
- **Write-scope (G5 / Art. 32 TOM):** installation_id=A payload → asserts syncWorkspace touched A's workspace_path only; B's path mtime unchanged.
- **Unmapped installation:** the dispatcher already produces 404 (Phase 1); but the Inngest function defends-in-depth — if event arrives with founderId that no longer maps to an active user, the function skips + Sentry-mirrors WITHOUT calling syncWorkspace (assert via fs-spy).
- **Cross-tenant concurrent (Kieran #8):** Two Inngest invocations dispatched simultaneously (installation_id=A and installation_id=B; distinct workspace_paths). Assert (i) both syncWorkspace calls execute, (ii) A's path receives only A's pull, B's path receives only B's pull, (iii) CEL concurrency key scopes per-installation (no cross-coalescing).

GREEN: Create the Inngest function file per the existing `cron-follow-through-monitor.ts` shape. Create the `appendKbSyncRow` helper in `session-sync.ts`.

REFACTOR: none.

### Phase 3: Sentry Mirror Sweep (Inline per Brainstorm CTO Workflow-Gate)

DHH dissent acknowledged: he prefers this sweep land as a separate prerequisite PR for bisect-friendliness. **Brainstorm CTO workflow-gate overrides** — "existing silent-fallback bugs surfaced during this work must be fixed inline, not deferred". This decision is load-bearing for `cq-silent-fallback-must-mirror-to-sentry` rule compliance and the User-Brand-Impact mitigation column above (without the sweep, the cross-tenant exposure mitigation is partial).

RED: Update existing test files (or add new) asserting `reportSilentFallback` IS called at:
- `kb-route-helpers.ts:282` (syncWorkspace) with `feature:"kb-route-helpers"`.
- `session-sync.ts:380` (syncPull catch) with `feature:"session-sync"`.
- `session-sync.ts:451` (recordKbSyncHistory inner catch) with `feature:"session-sync"`, `op:"recordKbSyncHistory"`.
- `session-sync.ts:457` (syncPush outer catch) with `feature:"session-sync"`, `op:"syncPush"`.
Per Kieran #5: any pre-existing test asserting SILENT fallback (no Sentry call) for these sites must be flipped to assert `reportSilentFallback` IS called with the expected triple.

GREEN: Single-statement insertions per Files to Edit lines 380/451/457 in session-sync, line 282 in kb-route-helpers.

REFACTOR: none.

### Phase 4: UI — `KbSyncStatus` Component + `POST /api/kb/sync` Route

RED: `kb-sync-status.test.tsx` covers two primary states + in-flight + empty-state + 409 toast. `kb-sync-route.test.ts` covers auth + 409 on not-ready + happy-path `{ trigger:"manual" }` row append + server-side `workspace_path` resolution.

GREEN: Create both files per Files to Create. Inline 12-line discriminator inside the component (handles legacy `{date,count}` vs new richer shape) — no separate `lib/kb-sync.ts` module.

REFACTOR: extract relative-time formatting if not already shared util.

### Phase 5: Compliance Docs + Post-merge Wiring

- Article 30 PA-17 cell amendment with explicit display-only-vs-filesystem-write distinction per Kieran #10.
- DPD §2.3(r) sentence.
- Update `last_updated:` on both.
- Verify deferred-scope-out issue #4228 (cron backstop) is linked in PR body as `Ref #4228` (NOT `Closes`).
- Confirm `kb_sync_history` rows carry `push_received_at` + `sync_completed_at` (TR4) for 30-day drift analysis.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `webhook-push-dispatch.test.ts` passes — all 9 RED cases per Phase 1.
- [ ] AC2: `workspace-reconcile-on-push.test.ts` passes — happy path, ff-only failure, workspace_not_ready, unmapped-defense-in-depth, write-scope (single-tenant), cross-tenant concurrent (two installations).
- [ ] AC3: `kb-sync-route.test.ts` passes — auth gate, 409 on not-ready, manual-trigger row append, server-side `workspace_path` resolution (request body workspace_path ignored / rejected).
- [ ] AC4: `kb-sync-status.test.tsx` passes — synced / desync / in-flight / empty / 409-toast.
- [ ] AC5: All four `syncWorkspace`/`syncPull`/`syncPush`/`recordKbSyncHistory` sites Sentry-mirror via `reportSilentFallback` with EXPLICIT `message:` arg. Verify: `grep -cE 'reportSilentFallback\(' apps/web-platform/server/{kb-route-helpers,session-sync}.ts apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` returns ≥ 5 (4 in the two existing files + ≥1 in the new function file). Kieran #9.
- [ ] AC6: Article 30 PA-17 cell amendment + DPD §2.3(r) sentence land in this PR (verify via `git diff origin/main`). PA-17 wording explicitly distinguishes display-only-signal-ingestion vs filesystem-write reconciliation (Kieran #10).
- [ ] AC7: `bun test apps/web-platform/test/` is green. Specifically: (a) all previously-green tests remain green, (b) any test asserting silent-fallback for `syncPull`/`syncPush`/`syncWorkspace`/`recordKbSyncHistory` is updated to assert `reportSilentFallback` IS called with the expected `feature/op/message` triple, (c) zero new failures introduced (Kieran #5).
- [ ] AC8: PR body includes `Closes #4224` AND `Ref #4228` (cron backstop, deferred — never auto-closes via merge).

### Post-merge (operator) — automated via `/soleur:ship` where feasible

- [ ] AC9: Smoke-test push to `knowledge-base/` on a personal connected repo; verify `kb_sync_history` row appended within 30s via `mcp__plugin_supabase_supabase__execute_sql`: `SELECT kb_sync_history->-1 FROM public.users WHERE id = '<id>'`. Automation: feasible via Supabase MCP at `/soleur:ship` time.
- [ ] AC10: Query Sentry via existing `/health/sentry-residency` for the 24h period post-deploy; verify zero `feature:"workspace-reconcile-push"` events of severity `error` (warning-level events for non-default-branch pushes are expected and fine).
- [ ] AC11: `gh issue close 4224` after AC9 + AC10 pass. Automation: feasible via gh CLI.

## Observability

```yaml
liveness_signal:
  what: Inngest function "workspace-reconcile-on-push" success-rate over 24h rolling window
  cadence: continuous (per invocation)
  alert_target: Sentry rule "workspace-reconcile-push success-rate < 95% over 1h"
  configured_in: apps/web-platform/infra/sentry/alerts.tf (existing alerts root)

error_reporting:
  destination: Sentry via reportSilentFallback + pino structured logs (container stdout → Better Stack)
  fail_loud: true — every reconcile failure mirrors to Sentry with feature:"workspace-reconcile-push" | feature:"session-sync" | feature:"kb-route-helpers"

failure_modes:
  - mode: webhook delivery failure (network, GitHub-side outage)
    detection: GitHub redelivery (1h) + dedup row catches; backstop = operator clicks Sync-now affordance on KbSyncStatus
    alert_route: passive (operator-visible status stays old; no Sentry alert until cron backstop #4228 ships)
  - mode: non-fast-forward (force-push, rebased main)
    detection: syncWorkspace returns {ok:false, error_class:"non_fast_forward"}; kb_sync_history records; Sentry mirror
    alert_route: Sentry warning + KbSyncStatus flips to "Workspace out of sync — reconnect"
  - mode: workspace_status != "ready" at reconcile time
    detection: explicit guard before syncWorkspace call
    alert_route: Sentry mirror at warning level
  - mode: cross-tenant installation routing bug
    detection: Phase 2 write-scope + cross-tenant concurrent tests at CI; Sentry exception if syncWorkspace touches a workspace_path NOT owned by resolved founderId
    alert_route: Sentry critical + PagerDuty
  - mode: kb_sync_history row write failure (RLS, JSONB rejection)
    detection: update returns error; Sentry mirrored; sync proceeds without history (degraded telemetry, no data loss)
    alert_route: Sentry warning

logs:
  where: container stdout (pino) + Better Stack
  retention: 30 days (existing tier per knowledge-base/legal/sub-processors.md)

discoverability_test:
  command: |
    mcp__plugin_supabase_supabase__execute_sql with SQL:
      SELECT kb_sync_history->-1 AS latest FROM public.users WHERE id = '<operator-uuid>';
  expected_output: |
    Latest entry is either legacy {date, count} (pre-merge data) or new shape
    {at, trigger ∈ ["webhook_push","manual","session"], ok, ...}. Empty array
    on never-synced operators is acceptable; renders "Workspace ready" copy.
```

## Domain Review

**Domains relevant:** Product, Legal, Engineering (carried forward from brainstorm Phase 0.5).
**Brainstorm-recommended specialists:** None additional. CPO recommended UI staleness signal IN SCOPE (a scope decision, not a specialist invocation).

### Product (CPO carry-forward)

**Status:** reviewed (brainstorm Phase 0.5).
**Assessment:** Approach A is the only option holding the seconds-level user-truth-floor. UI staleness signal MUST be in scope. Cross-tenant concern is a test obligation, not a design constraint. Reject "sync now button only" as standalone — shifts correctness burden to operator.

### Legal (CLO carry-forward)

**Status:** reviewed (brainstorm Phase 0.5).
**Assessment:** Approach A wins on legal grounds. Per-event installation_id scoping = lowest credential blast radius. Lawful basis under Art. 6(1)(b). PA-17 cell amendment + DPD §2.3(r) at PR-merge time. Load-bearing TOMs: write-scope test (Phase 2), Sentry-mirror failures (Phase 3), audit ledger reuse via existing `audit_github_token_use` (deferred to /work).

### Engineering (CTO carry-forward, plan-review refined)

**Status:** reviewed (brainstorm Phase 0.5 + DHH + Kieran + Simplicity plan-review).
**Assessment:** Ship A only. Defer cron backstop (B, #4228) behind 30-day telemetry. Reject C. Default branch from webhook payload. `--ff-only` is sacred. Sentry-mirror sweep across 3 callers — fixed inline per workflow-gate (DHH dissent on PR-split rejected). Inngest CEL concurrency key as sole coalescing primitive (in-process Map dropped per DHH+Simplicity). No throttle (Simplicity #8). Heterogeneous JSONB with inline reader (no separate normalizer module per DHH+Simplicity).

### Product/UX Gate

**Tier:** blocking (mechanical escalation — new `components/kb/kb-sync-status.tsx` file creation triggers the components/**/*.tsx rule).
**Decision:** reviewed (partial — wireframes deferred with rationale).
**Agents invoked:** spec-flow-analyzer (Phase 1.5 — surfaced 5 P0 + 4 P1 edge cases folded into FR/TR/AC), CPO + CTO + CLO via brainstorm carry-forward.
**Skipped specialists:** ux-design-lead — scope is one merged UI primitive (`KbSyncStatus`) plus a state machine surfaced by spec-flow. Brainstorm CPO already validated the affordance set; the additions sit in existing `KbContentHeader` (no new page, no new flow). Wireframes are over-engineering for this scope. If badge/button visual design is contested at PR review, file a follow-up.
**Pencil available:** yes (deferred, not invoked).
**copywriter:** not recommended by any leader; skip silently.

### Compliance — GDPR Gate (Phase 2.7)

**Status:** satisfied via brainstorm CLO carry-forward + Article 30 PA-17 amendment wording sharpened per Kieran #10. All four Critical-finding classes addressed at brainstorm; CR1–CR4 in spec.md + this plan's PA-17 wording requirement encode the gate findings.

### IaC Routing Gate (Phase 2.8)

**Status:** skip silently — no new infrastructure surface. Inngest function inherits existing Inngest deployment per ADR-033.

## Sharp Edges

- **Inngest CEL key is the SOLE coalescing primitive.** No in-process Map. If `/work` time grep finds existing Inngest functions using in-process Map (uncommon), do NOT reconcile — those are legacy patterns. CEL key is correct.
- **Heterogeneous `kb_sync_history` JSONB.** Reader inlines a 12-line discriminator at `KbSyncStatus`; do NOT extract to a shared module until a second consumer exists. Test fixtures must cover both legacy `{date, count}` and new richer shape.
- **`workspace_path` is OWNED by `userData.workspace_path` — never accept from client.** Manual-sync endpoint resolves server-side from `session.user_id` and ignores request-body path fields. This is the manual-endpoint TOM; covered by AC3.
- **Article 30 PA-17 wording MUST distinguish display-only signal ingestion (existing PA-17 scope) vs workspace clone reconciliation — filesystem write side-effect (new sub-bullet).** Otherwise CLO carry-forward "extends timing of an inventoried processing activity, not its categories" is contestable. Workspace clone reconciliation is structurally a different data flow (write-side).
- **`Closes #4224` vs `Ref #4228` timing.** PR auto-closes #4224 on merge; AC9–AC11 (post-merge smoke) MUST complete in the merge window or via `/soleur:ship` automation, OR the issue auto-closes before verification (false-resolved state). #4228 stays open by design (cron backstop is gated on 30-day telemetry from this PR).
- **DHH dissent on Sentry-sweep PR split — REJECTED.** Brainstorm CTO workflow-gate ("existing silent-fallback bugs surfaced during this work must be fixed inline") + `cq-silent-fallback-must-mirror-to-sentry` rule compliance + User-Brand-Impact mitigation completeness all require inline fix. If `/work`-time discovery surfaces additional non-trivial silent-fallback callers beyond the four named above, file as separate scope-out, do not snowball into this PR.

## Deferred / Out of Scope

- **DS1: Cron backstop (Approach B)** — issue #4228, gated on 30-day webhook-delivery telemetry from this PR showing >0.1% drift.
- **DS2: Debounce window for rapid pushes** — relying on `--ff-only` idempotency + Inngest CEL coalescing. Add only if observed >5% duplicate pull rate post-deploy.
- **DS3: `recordKbSyncHistory` legacy `{date,count}` backfill** — back-compat reads suffice. YAGNI.
- **DS4: Reconnect-flow recovery on `/dashboard/settings/integrations/github`** — `KbSyncStatus` desync state links there; the page-level recovery flow (re-clone, reset, etc.) is out of scope. File follow-up at /work if missing.

## Plan-time Verification Receipts

- All cited files (`route.ts`, `kb-route-helpers.ts`, `session-sync.ts`, `github-event-strategies.ts`, `observability.ts`, `KbContentHeader.tsx`, migration 017) verified present on the worktree HEAD.
- `reportSilentFallback` exists at `observability.ts:138` with signature `(err, { feature, op?, extra?, message? })`.
- 74 open code-review issues scanned via gh; zero overlap with expected Files to Edit.
- Existing Inngest concurrency CEL pattern confirmed at `github-on-event.ts:271`, `cron-follow-through-monitor.ts:578`, `cfo-on-payment-failed.ts:245`.
- Existing per-file Sentry tags confirmed: `feature:"kb-route-helpers"`, `feature:"session-sync"`.
- Existing cron/dot event-name convention confirmed: `cron/daily-triage.manual-trigger`, `cron/follow-through-monitor.manual-trigger`. New `platform/workspace.reconcile.requested` consistent.
- `ACTION_CLASSES` typed-literals lint at `test/lint/action-class-typed-literals.test.ts` confirmed; new event name does NOT need to enter the union (no `EventSchemas` registry in `inngest/client.ts`).
- spec-flow-analyzer findings (5 P0 + 4 P1 edge cases) folded into Files to Edit, Files to Create, Implementation Phases, and AC1–AC4.
- Plan-review applied: DHH (8 push-backs — 7 accepted, 1 rejected with documented rationale), Kieran (10 findings — all 7 P0/P1 accepted, 3 P2 incorporated), Code-Simplicity (10 findings — all accepted).
