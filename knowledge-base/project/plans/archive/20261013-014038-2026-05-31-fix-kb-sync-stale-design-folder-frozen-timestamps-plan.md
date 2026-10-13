---
title: "fix: KB sync stale — screenshot workspace has NULL github_installation_id, unreachable by webhook reconcile"
type: bug
status: draft
created: 2026-05-31
branch: feat-one-shot-kb-sync-stale-design-folder
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: Knowledge Base frozen ~5w — workspace 754ee124 has NULL `github_installation_id` and can never match the push-webhook reconcile

> **Rewritten 2026-05-31 (v3) against live prod data.** Earlier versions asserted, in sequence: H1 path-divergence, H2 shallow-clone non-fast-forward, a #4666 ignore-list shadowing workspace 52af49c2, and a prod migration-lag. **All four were wrong** (see Diagnostic Errors). The data-confirmed cause is below. No fix is implemented — this is the evidence-complete writeup; the operator chose "full data writeup, then decide."

## Verified Evidence (live prod, read-only via Doppler `DATABASE_URL_POOLER`, 2026-05-31)

The screenshot is **ops@jikigai.com viewing `jikig-ai/soleur`** → workspace/user **`754ee124-706a-4f21-a4f4-e828257b0380`**.

| Probe | Value | Source |
|---|---|---|
| `users.754ee124`: repo_url / repo_status / **github_installation_id** / repo_last_synced_at / kb_sync_history len | `github.com/jikig-ai/soleur` / `ready` / **NULL** / `2026-04-23T12:07:38Z` / **0 rows** | `users` row |
| `workspaces.754ee124` | repo_url set, repo_status `ready`, **github_installation_id NULL**, created `2026-05-21` | `workspaces` row |
| Migrations applied in prod | **114 rows, latest `088`** — 079/080/081 (ADR-044) + all through 088 applied. **No migration lag.** | `_schema_migrations` |
| Every `github_installation_id` in the system | **exactly one: `122213433`** → jean.deruelle@ / `jikig-ai/chatte` (ws 52af49c2) | full `users`+`workspaces` scan |
| GitHub App token use against `soleur` | **none** (`audit_github_token_use` empty for `%soleur%`) | audit ledger |

The "5w ago" = the Apr-23 last legacy sync, ~5 weeks before the May-31 screenshot.

## Root Cause (data-confirmed)

KB sync is now **entirely webhook-driven**: GitHub push → `app/api/webhooks/github/route.ts` resolves founder by `installation_id`, emits `platform/workspace.reconcile.requested`; `workspace-reconcile-on-push.ts` selects target workspaces with `WHERE github_installation_id = <push.installation.id> AND repo_url = <composed-from-fullName>`.

Workspace **754ee124's `github_installation_id` is NULL.** NULL never equals any numeric webhook id → the workspace is **never selected by the fan-out** → it has produced **zero `kb_sync_history` rows** (not even failures; it never enters the loop). Its last sync (Apr 23, `ready`) came from the **legacy** pre-GitHub-App connection path that the webhook/App path replaced.

Migration 080 (ADR-044 backfill, already applied) copies `users.github_installation_id → workspaces`, but user 754ee124's own value was already NULL → NULL→NULL copy, correct. **No GitHub App installation for `jikig-ai/soleur` exists anywhere** (only install `122213433` = chatte). So: not a backfill bug, not a missing migration — the repo was connected before the GitHub App model and never re-authorized through it.

**Two layers, both real:**
1. **Data:** 754ee124 needs a GitHub App installation for `jikig-ai/soleur` with `github_installation_id` set, so the reconcile can reach it. None exists today → requires a GitHub App install/authorize (genuine OAuth consent gate) on that repo, OR extending an existing install if `soleur` is under the same account/org.
2. **Code/product gap (why this was invisible for 5 weeks):** a workspace with `repo_status='ready'` but `github_installation_id IS NULL` is silently unreachable by the only sync path AND writes zero observability rows. No guard flags "ready but unreconcilable." This is the systemic fix worth shipping.

## Diagnostic Errors (on file so the disconfirming evidence is preserved)

1. **H1 (path divergence)** — N2 solo invariant ⇒ read-dir == write-dir. Disproven.
2. **H2 (shallow-clone non-ff)** — would write `ok=false` ledger rows; 754ee124 has zero rows; sync code never reached. Disproven.
3. **"#4666 ignore-list shadows ws 52af49c2"** — wrong id→repo mapping (52af49c2 is `chatte`; screenshot ws is 754ee124). Retracted.
4. **"Prod 5 migrations behind (079–083)"** — false; `_schema_migrations` has 114 rows through 088. Retracted. **No migrations were applied.**

## Chosen scope — Track B: systemic detection + observability (operator decision 2026-05-31)

Operator will handle the `jikig-ai/soleur` GitHub-App reconnect manually (Track A). This PR ships **Track B only**: make the "ready but unreconcilable" failure class **loud instead of silent**, so it can never again sit frozen for weeks unnoticed.

**Why detection-only (not state mutation):** flipping `users.repo_status` to `error` was considered and **rejected** — `app/api/kb/tree/route.ts:36` returns **409 on `repo_status='error'`**, which would *blank the user's KB tree* (strictly worse than today's stale-but-visible tree). No `repo_status` mutation. No migration. No UI change (so no UX gate). Pure observability cron, matching the read-only `cron-membership-health` precedent exactly.

### Implementation
- **New Inngest cron `cron-workspace-sync-health`** (`apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts`), modeled on `cron-membership-health.ts`. Daily schedule. Scans `workspaces` (the reconcile authority) for the exact unreconcilable class:
  `repo_status = 'ready' AND github_installation_id IS NULL`.
  Each such workspace can **never** match the push-reconcile filter (`workspace-reconcile-on-push.ts:164` — `.eq("github_installation_id", installationId)`), so it silently never syncs. For each finding, `reportSilentFallback(...)` (feature `workspace-sync-health`, op `ready-null-installation`) → Sentry page. Read-only; no mutation.
- **Register** in `app/api/inngest/route.ts` `serve({ functions: [...] })`.
- **Tests** (`apps/web-platform/test/server/inngest/workspace-sync-health.test.ts`), modeled on `membership-health.test.ts`: (RED) a `ready`+NULL-install workspace triggers exactly one `reportSilentFallback`; a `ready`+non-NULL-install workspace and a `not_connected` workspace trigger none; a DB error path reports once and returns no findings.

### Non-goals (documented, not built)
- **Stale-last-sync heuristic** (alert when a `ready`+installed workspace has no `kb_sync_history ok:true` row in N days) — broader, higher false-positive risk; follow-up.
- **UI reconnect affordance for the `ready`+NULL-install state** — the existing `RepoConnectionCard` only shows "Reconnect" on `repo_status='error'`, which we deliberately don't set. A `needsReconnect` derived flag + card change needs UX review; follow-up. Operator is reconnecting manually this time.

## Acceptance Criteria (Track B)
- [ ] RED→GREEN: `cron-workspace-sync-health` reports each `repo_status='ready' AND github_installation_id IS NULL` workspace to Sentry via `reportSilentFallback`; emits nothing for ready+installed or not_connected; DB-error path reports once and returns `{ ok:true, findings:[] }`. Read-only (no `.update`/`.upsert` on the SUT).
- [ ] Registered in `app/api/inngest/route.ts`.
- [ ] `./node_modules/.bin/vitest run` (the new test + reconcile suite) green; `./node_modules/.bin/tsc --noEmit` clean in `apps/web-platform`.

## Open question (non-blocking; resolved for Track A by operator)
`jikig-ai/soleur` is the platform's own dev repo and is on the `#4666` reconcile ignore-list — note that even after reconnect, the ignore-list short-circuit (`workspace-reconcile-on-push.ts:149`) may also need attention for this specific repo. Out of scope for Track B (detection still fires regardless).
