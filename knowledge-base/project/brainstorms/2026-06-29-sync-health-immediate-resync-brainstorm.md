---
date: 2026-06-29
topic: sync-health immediate re-sync after backfill
issue: 5689
parent_issue: 5675
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Immediate re-sync after arm-1 backfill (#5689 item 2)

## Scope

This brainstorm covers **only item 2** of tracking issue #5689 ("immediate re-sync
after backfill"). **Item 1 (producer investigation) is explicitly out of scope** —
it is "required-on-signal," gated on a one-week soak after arm-1 (#5684) merged
2026-06-29T13:06:55Z. The soak ends ~2026-07-06; there is no signal to investigate
yet. Item 1 stays OPEN and soak-gated. (Operator decision, 2026-06-29.)

## What We're Building

When arm-1 of `cron-workspace-sync-health.ts` backfills a missing
`github_installation_id` onto a solo workspace that is `repo_status='ready'`, it
currently repairs **reachability** (the next push webhook will now sync) but does
**not** sync the current default-branch HEAD. For a low-activity solo repo — the
exact connect-and-walk-away profile — the user's KB stays stale/empty for days
even though the UI told them they are "ready/connected."

The fix: after a successful backfill, immediately call the existing
`syncWorkspace()` helper **inside arm-1's existing per-workspace step boundary**,
and record a truthfully-labeled `kb_sync_history` audit row. Lag shrinks from
"days until next push" to **zero**.

## Why This Approach (A — direct in-arm sync)

The issue body framed item 2 as "needs a push-shaped payload and expands blast
radius." That framing describes only the **synthetic-event** path (Approach B),
which the verified code disproves:

- **Key code finding:** `syncWorkspace(installationId, workspacePath, logger, …)`
  (`workspace-reconcile-on-push.ts:331`) pulls the **live default-branch HEAD**
  itself. It never consumes `headSha`/`beforeSha` — those only populate the audit
  row's `sha_before`/`sha_after`. So a synthetic push payload buys **nothing**
  functional.
- Approach B would also **break ADR-033 I6** ("arm-1 emits no Inngest events"),
  invent a sentinel `deliveryId`/`headSha`, and widen blast radius into the
  reconcile fan-out + concurrency pipeline.

Approach A reuses what arm-1 already holds at backfill time (resolved `installId`
+ `workspacePathForWorkspaceId(workspaceId)`), reuses the existing
`workspaceDirExists` guard, and reuses the service-role audit writer the
owner-less path already uses (`append_kb_sync_row_for_user`, migration 100 — no
`auth.uid()`, exactly arm-1's context). **All three domain leaders converged on A.**

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Approach | **A — direct in-arm `syncWorkspace`** | Dominates B (B is vacuous + breaks I6). Operator-confirmed 2026-06-29. |
| Inngest event? | **No** | Preserves ADR-033 I6. Direct helper call only. |
| DB migration? | **None** | `kb_sync_history` is JSONB on `users`; `trigger` is free-form (mig 017 has no CHECK; RPCs 053/100 take `jsonb`). |
| Audit `trigger` value | **New distinct value** (e.g. `reconcile_backfill`) | CLO: must NOT spoof `webhook_push` — truthful provenance. Requires widening the TS union `"webhook_push"\|"manual"\|"session"` (session-sync.ts:639). |
| Write ordering | **Backfill commits first, then sync** | Re-entrancy safety: once `github_installation_id` is NOT NULL the row leaves arm-1's scan predicate, so a sync failure self-heals on the next fire rather than stranding or double-backfilling. |
| `workspaceDirExists` drift (ready row, no dir) | **Reuse existing skip-and-audit branch** (`ERROR_CLASS_WORKSPACE_NOT_READY`) | Do not error the step. |
| User-visible signal | **None — silent self-heal** | CPO: a "we synced after a bug" toast advertises the failure and erodes trust; converge silently to the promised state. |
| Sequencing vs item 1 | **Independent — ship now** | CPO: item 2 shrinks user-visible harm during the item-1 soak window; waiting is strictly worse. |
| Scope | **Solo-only** (inherits arm-1's entitlement-scoped, solo-only predicate) | Matches ADR-044 amendment 2026-06-29. |

## Open Questions

1. **Exact `trigger` literal:** `reconcile_backfill` vs `backfill_resync` vs
   `system_initiated`. Pick at plan time; must be distinct from `webhook_push`.
2. **Step duration ceiling:** a cold clone is heavier than a column write. Mitigated
   by (a) cohort trends to zero post-soak, (b) `workspaceDirExists` guard means most
   hits are pulls not clones, (c) per-workspace step isolation. If the first soak
   shows arm-1 step times creeping, fall back to **A′** (defer the sync to arm-3's
   existing went-quiet machinery via a `needs_initial_sync` marker). Measure first;
   do not pre-optimize.
3. **ADR:** capture the per-arm sync-ownership + new-trigger-value boundary decision
   (CTO suggested `/soleur:architecture` against ADR-033/044). Decide at plan time
   whether this rises to an ADR or an ADR-044 amendment note.

## Rejected Alternatives

- **B — synthetic `workspace/reconcile-on-push` event:** vacuous (syncWorkspace
  needs no push payload), breaks I6, pollutes audit trail with sentinel `sha_after`.
  Rejected by all three leaders.
- **Status quo / keep deferred:** leaves the broken onboarding promise live for
  days on low-activity solo repos. CPO argues against. Rejected.

## User-Brand Impact

- **Artifact:** the immediate-reconcile-after-backfill path in `cron-workspace-sync-health` arm-1.
- **Vector:** a reconciled solo workspace's default-branch HEAD silently stays stale
  (UI says "ready", KB shows old/empty content) with no error surfaced — persists
  days for a low-activity repo.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Approach A (direct in-arm `syncWorkspace`) dominates B and is the
recommendation — risk medium, complexity small (hours). A is ADR-033 I6-clean and
I1-holds; no migration (trigger is free-form JSONB). Primary risk is step duration
(clone/pull); mitigated by the to-zero cohort, the dir guard, and per-workspace step
isolation. Re-entrancy is safe if backfill commits before sync. Fourth option A′
(defer sync to arm-3) only if soak shows arm-1 step times creeping.

### Product (CPO)

**Summary:** High severity — "ready but silently stale" is a broken onboarding
promise at the highest-stakes moment, meeting the single-user-incident bar. Ship now;
do not wait for the item-1 soak (item 2 shrinks harm during that window). Silent
self-heal is the correct UX — no new user notification.

### Legal (CLO)

**Summary:** No material legal/data-protection surface — internal timing optimization
on data the user already authorized (their own repo → their own workspace, same
tenant, same region). One requirement: the audit row must carry a truthful
system-initiated `trigger`, never a spoofed `webhook_push`. No p2 ship blocker.
