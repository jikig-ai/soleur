---
title: "ADR-044 PR-2b reader/writer cutover — cut last users.repo_url / users.workspace_path live access"
type: refactor
date: 2026-06-17
branch: feat-one-shot-5437-pr2b-reader-writer-cutover
ref_issue: 5437
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# ♻️ ADR-044 PR-2b reader/writer cutover

## Enhancement Summary

**Deepened on:** 2026-06-17
**Sections enhanced:** cron join design, test guidance, test scenarios, AC7,
provisionWorkspace side-effect note.
**Agents used:** spec-flow-analyzer, data-integrity-guardian, Explore
(claim-verification), plus the deepen-plan hard-halt gates (4.6 User-Brand
Impact, 4.7 Observability, 4.8 PAT, 4.9 UI-wireframe) — all passed.

### Key improvements from deepen pass
1. **Row-set divergence is BIDIRECTIONAL.** Documented Direction B (stale
   `users.repo_status='ready'` + live `workspaces.repo_status != 'ready'` →
   now correctly dropped) alongside the already-known Direction A latent-bug
   fix. Added a Direction-B test so the drop is intentional, not accidental.
2. **Test-coupling P1:** the existing single shared `eqSpy` cannot prove the
   `repo_status='ready'` filter moved to the `workspaces` chain — AC7 now
   requires a per-table eq spy.
3. **Mutual exclusion is polarity-based, not population-based** — clarified so
   the two-query Shape B is not misread as requiring a shared row-set.
4. **Step-scoped early return + heartbeat continuity:** `ids.length===0` must
   return the step's `{reported:0}`/`{wentQuiet:0}` shape, never bubble to the
   handler (would skip the Sentry heartbeat). Added a zero-rows-heartbeat test.
5. **NOT-NULL safety** for the callback site-1 upsert documented (column default
   `''` covers the dropped key on the trigger-failure INSERT path).

### Claims verified live (Explore agent — all CONFIRM)
- Arm-1 `.from("workspaces").select("id, repo_url").eq("repo_status","ready")`
  precedent exists. `.in("id", ids)` is an established service-client idiom
  (org-memberships / notifications / team-membership resolvers).
- `kb_sync_history` is `users`-only (mig 017); never on `workspaces`.
- `repo/status/route.ts` reads `repo_url` from `workspaces` (the AC1 grep
  false-positive is genuine; leave it alone).
- N2 invariant (`workspaces.id == users.id`) is trigger-enforced in mig 053.
- Cited PR/issue states verified: #5437 OPEN (umbrella), #5466/#5481/#5482
  MERGED, #5470 CLOSED (issue), #3739 OPEN (overlap, acknowledged).

## Overview

NON-DESTRUCTIVE precondition for ADR-044 PR-2b's column DROP. This PR cuts the
**last live readers/writers** of `users.repo_url` and `users.workspace_path` off
the `users` table so the eventual `ALTER TABLE users DROP COLUMN repo_url,
workspace_path` (PR-2b proper) is fully unblocked. It is the third ADR-044 PR
this cycle, after #5481/#5482 cleaned `users.github_installation_id` to 0 readers.

**This PR does NOT drop any column, does NOT add a migration, does NOT run any
destructive migration.** It only relocates the remaining read/write sites.

Two surfaces remain:

1. **`server/inngest/functions/cron-workspace-sync-health.ts`** — arms 2
   (`scan-stale-sync-failed`, currently ~L113) and 3 (`scan-went-quiet`,
   currently ~L197) both filter `.from("users").eq("repo_status","ready")`.
   `users.repo_status` is now **stale** — its write relocated to `workspaces`
   in #5466 (and `workspaces.repo_status` is the ADR-044 source of truth per
   migration 108). Arm 3 additionally `.select("…, repo_url, …")` from `users`.
   Both must read repo state from the user's solo `workspaces` row
   (`workspaces.id == users.id`, ADR-038/053 N2 invariant), while continuing to
   read `kb_sync_history` from `users` (that column lives on `users` only —
   migration `017_kb_sync_history.sql` — and ADR-044 deliberately did NOT
   relocate it).

   **Latent-bug fix (free with this change):** post-#5466 the cron filters on
   the stale `users.repo_status`, so it MISSES newly-connected users (whose
   `users.repo_status` was never written but whose `workspaces.repo_status` is
   `ready`). Cutting the filter to `workspaces` fixes that false-negative.

2. **`users.workspace_path` vestigial writes** at three sites — two in
   `app/(auth)/callback/route.ts` (the `.upsert(...)` ~L378 and the
   `.update(...)` ~L406) and one in `app/api/workspace/route.ts`
   (the `.update(...)` ~L60). The on-disk workspace path is DERIVED now via
   `workspacePathForWorkspaceId(workspaceId)` (see `agent-runner.ts:1057`:
   "NOT the legacy `users.workspace_path` column. That column is stale/empty").
   Remove ONLY the `workspace_path` field from each payload; KEEP
   `workspace_status` (it is NOT in PR-2b's drop set and is still read at the
   callback gate `existing.workspace_status !== "ready"` ~L401 and the workspace
   route gate ~L39).

## Research Reconciliation — Spec vs. Codebase

The arguments described the cron arms as still reading the `users` install
predicate; the live code shows #5470 **already** cut that (arms 2/3 now resolve
the install per-row via `resolveInstallationIdForWorkspace`). The ONLY residual
`users` repo-column access in the cron is the **`repo_status` FILTER** (arms 2
and 3) and the **`repo_url` SELECT** (arm 3). The plan below targets exactly
those residuals — it does not re-do #5470's install cutover.

| Claim (from arguments) | Codebase reality (verified) | Plan response |
|---|---|---|
| Arms do `.select("id[, repo_url], kb_sync_history").eq("repo_status","ready")` on `users` | TRUE for the **filter** + arm-3 `repo_url` select; install predicate already cut by #5470 | Cut the `repo_status` filter + arm-3 `repo_url` to `workspaces`; keep `kb_sync_history` on `users` |
| `repo/status/route.ts` is a live `users.repo_url` reader (grep hit) | FALSE POSITIVE — that route reads `repo_url`/`repo_status` from **`workspaces`** (`wsRes`, L37-40); the adjacent `.from("users").select("health_snapshot")` is a *parallel* `Promise.all` query 400 chars away | No change; documented in AC as expected false-positive |
| Callback site 1 is `.upsert({... workspace_path, workspace_status ...})` ~L378 | TRUE (L378-386) | Remove `workspace_path` key only |
| Callback site 2 is `.update({ workspace_path, workspace_status })` ~L405 | TRUE (L405-407) | Remove `workspace_path` key only |
| Workspace route is `.update({ workspace_path, workspace_status })` ~L59 | TRUE (L58-61) | Remove `workspace_path` key only |
| `provisionWorkspace(userId)` return is written to the column | PARTIAL — in callback site 1 (`.upsert`) the return is consumed ONLY by `workspace_path`; in callback site 2 (`.update`) ditto; in **workspace route** the return `workspacePath` is ALSO returned in the JSON response body (`route.ts:72` `workspace_path: workspacePath`) | See "provisionWorkspace side-effect preservation" below |

## provisionWorkspace side-effect preservation (HARD requirement)

`provisionWorkspace(workspaceId)` (`server/workspace.ts:104-133`) performs the
**on-disk** side effect: `ensureDir`, `scaffoldWorkspaceDefaults`, `git init`.
That side effect MUST be preserved — it is what actually creates the workspace
directory. Its **return value** (the absolute path string) is what we stop
writing to the DB column. Per-site treatment:

- **Callback site 1 (`.upsert`, L375-386):** `const workspacePath = await provisionWorkspace(userId);`
  is currently consumed ONLY by `workspace_path: workspacePath`. After removing
  that key, `workspacePath` becomes an **unused local** → TS/lint will flag it.
  Change to `await provisionWorkspace(userId);` (call kept for side effect,
  return discarded). The `.upsert` keeps `{ id, email, workspace_status: "ready" }`.
  **NOT-NULL safety (deepen P2):** `users.workspace_path` is `text NOT NULL
  DEFAULT ''` (`001_initial_schema.sql`); this INSERT-path branch only fires when
  `handle_new_user` failed, so the column relies on its DB-side `''` default to
  satisfy NOT NULL — dropping the key is safe because the default populates it.
  (PR-2b-proper drops the column entirely, removing this dependency; no `DROP
  DEFAULT` is in scope here.)

- **Callback site 2 (`.update`, L403-407):** same — `const workspacePath = await provisionWorkspace(userId);`
  is consumed only by the removed key. Change to `await provisionWorkspace(userId);`.
  The `.update` keeps `{ workspace_status: "ready" }`.

- **Workspace route (`route.ts:55-73`):** `const workspacePath = await provisionWorkspace(user.id);`
  is consumed by BOTH the removed `.update` key AND the **response body**
  `route.ts:72` (`workspace_path: workspacePath`). The response field is a
  caller-facing contract, NOT a `users` column — **KEEP `const workspacePath`
  and KEEP the response field.** Remove ONLY `workspace_path: workspacePath`
  from the `.update({...})` payload at L60. `provisionWorkspace` is still called;
  `workspacePath` is still consumed (by the response). No unused-local risk here.

## User-Brand Impact

**If this lands broken, the user experiences:** (cron) a service-role daily scan
that either crashes (Sentry-mirrored, scan returns `{reported:0}`) or — worse —
silently goes dark: if the join is wrong it could stop reporting stale/went-quiet
KB for ALL users, re-creating the exact "founder's KB frozen for 5 weeks, nothing
loud" failure the cron was built to prevent. (callback) if `workspace_status` is
accidentally dropped or the `provisionWorkspace` side effect is removed, a brand
new user's first login fails to provision their workspace → blank/broken dashboard
on their very first session.

**If this leaks, the user's data is exposed via:** N/A — no new data surface, no
new external call, no widened SELECT. `repo_url` and the install id are read with
the SAME service-role client already in use; the per-row resolver
(`resolveInstallationIdForWorkspace`) is a server-derived `eq("id", userId)` read
(no sibling discovery, CLO-vetted in #5470).

**Brand-survival threshold:** single-user incident — the cron is service-role
(one wrong join darks every user's KB-health signal); the callback is auth-critical
(one wrong payload breaks first-login provisioning). CPO sign-off required at plan
time; `user-impact-reviewer` invoked at review time.

## Files to Edit

1. `apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts`
   - Arm 2 `scan-stale-sync-failed` (~L113-166): cut the `repo_status='ready'`
     filter from the `users` query to the `workspaces` query.
   - Arm 3 `scan-went-quiet` (~L197-317): cut the `repo_status='ready'` filter
     AND the `repo_url` select from `users` to `workspaces`.
   - Update the leading comments (L102-112, L168-191) that say "Scans `users`
     … `.eq("repo_status","ready")`" to reflect the workspaces-authoritative
     filter and the latent-bug fix.
2. `apps/web-platform/app/(auth)/callback/route.ts`
   - Site 1 (~L375-386): drop `workspace_path` from `.upsert`; change
     `const workspacePath = await provisionWorkspace(userId);` →
     `await provisionWorkspace(userId);`.
   - Site 2 (~L403-407): drop `workspace_path` from `.update`; change
     `const workspacePath = await provisionWorkspace(userId);` →
     `await provisionWorkspace(userId);`.
3. `apps/web-platform/app/api/workspace/route.ts`
   - Drop ONLY `workspace_path: workspacePath` from the `.update({...})` at L60.
     KEEP `const workspacePath = await provisionWorkspace(user.id);` (L55) and
     KEEP the response field `workspace_path: workspacePath` (L72).
4. `apps/web-platform/test/server/inngest/cron-workspace-sync-health.test.ts`
   - Update arm-2/arm-3 mocks + assertions. **CRITICAL test-coupling fix
     (deepen P1):** the mock currently uses a SINGLE shared `eqSpy` (L40) for
     BOTH the `workspaces` chain (L61) and the `users` chain (L87), so
     `expect(eqSpy).toHaveBeenCalledWith("repo_status","ready")` (L185, L278)
     CANNOT distinguish which table the filter hit — it stays green even if the
     `repo_status='ready'` filter is wired to the wrong chain. Give the
     `workspaces` scan chain and the `users` fetch chain SEPARATE eq spies (or
     capture `(table, col, val)` tuples) so the test FAILS if `repo_status='ready'`
     is applied to `users` instead of `workspaces`. The AC3 grep is weaker than a
     test; this is single-user-incident class (a wrong join darks every user's
     KB signal), so the test must pin the table.
   - Arm-3 `repo_url` fixtures move from the users-row shape to the
     workspaces-row shape (repo_url now comes from the `workspaces` Step-A row).
   - Add RED→GREEN test for **Direction A** (latent-bug fix): a newly-connected
     user (`workspaces.repo_status='ready'`, no `users.repo_status` write) is now
     **caught** by arms 2/3 where the old filter false-excluded it.
   - Add test for **Direction B** (symmetric drop, deepen P1): a user with stale
     `users.repo_status='ready'` but `workspaces.repo_status='error'` is NOT
     reported after cutover (was reported before) — proves the drop is intentional.
   - Add test: **zero ready workspaces → heartbeat STILL posts** (deepen P2) —
     the `ids.length===0` early return is step-scoped, so `sentry-heartbeat`
     still fires. Asserts the early-return did not bubble to the handler.

## Files to Create

None.

## The cron join — design (PLAN-REVIEW DECISION)

Both arms must select users whose **solo `workspaces` row** (`id == users.id`)
has `repo_status='ready'`, then read `kb_sync_history` (arms 2+3) and provide
`repo_url` (arm 3) from the workspaces row. Two shapes:

### Shape A — embedded join from `users` (rejected as primary)
```ts
service.from("users")
  .select("id, kb_sync_history, workspaces!inner(repo_url, repo_status)")
  .eq("workspaces.repo_status", "ready")
```
**Risk:** PostgREST embeds require a discoverable FK relationship between
`users` and `workspaces`. The N2 invariant (`workspaces.id == users.id`) is an
*application* invariant, not necessarily a declared FK from `users.id →
workspaces.id` that PostgREST can introspect for an embed in this direction.
The Sharp-Edge corpus warns that PostgREST embedded-resource syntax is more
limited than expected. **Do not assume this resolves.** deepen-plan Phase 4.4
MUST verify embed-resolvability against the live schema / migration FK
definitions before this shape is chosen.

### Shape B — scan `workspaces`, then fetch users by id (RECOMMENDED) ✅
Mirror arm 1 exactly (arm 1 already does `.from("workspaces").select("id,
repo_url").eq("repo_status","ready")`):

```ts
// Step A: authoritative readiness comes from workspaces (solo id == users.id).
const { data: wsRows } = await service
  .from("workspaces")
  .select("id, repo_url")
  .eq("repo_status", "ready");
// Build the Map DIRECTLY from wsRows (not via a derived `ids` index) — a
// positional index map drifts if anyone later filters `ids` (deepen P2).
const repoUrlById = new Map((wsRows ?? []).map(w => [w.id, w.repo_url]));
const ids = [...repoUrlById.keys()];
// IMPORTANT: this early return MUST return the STEP's shape ({reported:0} for
// arm 2, {wentQuiet:0} for arm 3) — it returns from the step.run callback, NOT
// from the handler. Bubbling a bare `return` to the handler would SKIP the
// separate sentry-heartbeat step.run and trigger a false missed-checkin alert
// (deepen P2; mirrors the existing "Heartbeat isolation is STRUCTURAL" comment).
if (ids.length === 0) return { reported: 0 }; // arm 2; { wentQuiet: 0 } in arm 3

// Step B: kb_sync_history lives on users only — fetch by the same ids.
const { data: userRows, error } = await service
  .from("users")
  .select("id, kb_sync_history")
  .in("id", ids);
// On `error`, reuse the existing op slug (scan-stale / scan-went-quiet) — do
// NOT mint a new slug (op-contract test continuity).
// arm 3 uses repoUrlById.get(r.id) where it previously used r.repo_url
```

**Why Shape B is the recommendation:**
- FK-agnostic: relies only on the N2 `workspaces.id == users.id` invariant
  (used everywhere in this codebase), not on an introspectable PostgREST embed.
- Mirrors arm 1's already-shipped `.from("workspaces").eq("repo_status","ready")`
  — consistent, reviewable, and uses the `.in("id", ids)` precedent that exists
  in `org-memberships-resolver.ts:103`, `notifications.ts:306`, etc.
- `repo_url` for arm 3 comes straight from the workspaces row (Step A),
  satisfying "whatever repo_url is used downstream must now come from workspaces".
- The latent-bug fix is structural: scanning `workspaces.repo_status` catches
  newly-connected users the stale `users.repo_status` filter missed.

**Trade-off:** two round trips instead of one (Step A + Step B). At cron cadence
(daily, low row count) this is irrelevant. The `.in("id", ids)` list is bounded
by the count of ready workspaces (small). If ready-workspace count ever grows
unbounded, batch the `.in()` — note in Risks, not a blocker now.

**Decision:** implement **Shape B** unless deepen-plan Phase 4.4 proves Shape A's
embed resolves against the live FK graph AND demonstrably simplifies (it does not
meaningfully — the two-query shape is already the arm-1 idiom). Default Shape B.
deepen-plan confirmed (data-integrity-guardian) the N2 invariant is
trigger-enforced (`053…sql` `handle_new_user` creates the `users` and
`workspaces` rows with the SAME `id` in one SECURITY DEFINER trigger), so the
`.in("id", ids)` join is 1:1-safe.

### Row-set divergence is BIDIRECTIONAL and intentional (deepen P1)

Moving the readiness filter from stale `users.repo_status` to authoritative
`workspaces.repo_status` changes the scanned set in BOTH directions — only one
was originally documented:

- **Direction A (the latent-bug fix):** newly-connected users whose
  `users.repo_status` was never written but whose `workspaces.repo_status='ready'`
  — were false-EXCLUDED before, now CAUGHT.
- **Direction B (the symmetric drop):** a pre-#5466 user whose STALE
  `users.repo_status` still reads `'ready'` but whose CURRENT
  `workspaces.repo_status != 'ready'` (e.g. repo later went to `error`) — was
  REPORTED before, now correctly DROPPED (workspaces is the source of truth per
  mig 108). This is a per-user coverage *reduction* for exactly the rows whose
  `users` column froze — defensible and correct, but it MUST be tested so the
  drop is intentional, not accidental.

### Mutual exclusion is POLARITY-based, not population-based (deepen P1)

The arm-2 (`latest ok:false`) vs arm-3 (`latest ok:true`) partition is enforced
PER-ROW by the `kb_sync_history` latest-row ok-polarity check
(`cron…:140` and `:233-238`), which is UNCHANGED by this refactor. It does NOT
depend on both arms scanning the identical row-set. Each arm runs its own
`.from("workspaces").eq("repo_status","ready")` at its own `step.run` boundary;
a workspace flipping `repo_status` between the two scans can appear in one arm's
set but not the other — but this race ALSO existed pre-refactor (two `users`
queries) and is harmless for an idempotent loud-reporter with no write/dedup key
(daily cadence; caught next run). "Never double-report" survives because it
rests on the polarity check, not a shared population. Update the existing
`cron…:177` comment if it implies population-based exclusion.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — zero `users.repo_url` live readers/writers.**
  `rg -nU 'from\("users"\)[\s\S]{0,400}?\brepo_url\b' apps/web-platform/{app,server,lib}`
  returns ONLY the documented false-positive `apps/web-platform/app/api/repo/status/route.ts`
  (where `repo_url` belongs to the adjacent `workspaces` query, not the `users`
  `health_snapshot` query). No hit in `cron-workspace-sync-health.ts`.
- [ ] **AC2 — zero `users.workspace_path` live readers/writers.**
  `rg -nU 'from\("users"\)[\s\S]{0,400}?\bworkspace_path\b' apps/web-platform/{app,server,lib}`
  returns 0 hits. (The `agent-runner.ts:1057` comment is prose, not a
  `from("users")…workspace_path` query, so it does not match this regex; confirm.)
- [ ] **AC3 — no `users.repo_status` filter remains in the cron.**
  `rg -nU 'from\("users"\)[\s\S]{0,200}?repo_status' apps/web-platform/server`
  returns 0 hits (the two cron-arm hits at L117-119 and L202-204 are gone).
- [ ] **AC4 — `workspace_status` preserved.** Both callback payloads still carry
  `workspace_status: "ready"` and the workspace-route payload still carries
  `workspace_status: "ready"`; the callback gate `existing.workspace_status !==
  "ready"` and the route gate `existingUser?.workspace_status === "ready"` are
  unchanged. `git grep -n 'workspace_status' apps/web-platform/app` shows the
  gates + writes intact.
- [ ] **AC5 — `provisionWorkspace` side effect preserved.**
  `git grep -n 'provisionWorkspace(' apps/web-platform/app` shows all three calls
  still present. Workspace-route response body still returns
  `workspace_path: workspacePath` (`route.ts:72`).
- [ ] **AC6 — typecheck clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  exits 0 (catches the unused-local case if a `const workspacePath` is left
  dangling in the callback sites).
- [ ] **AC7 — cron tests pass + table-pinned filter assertion.**
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-workspace-sync-health.test.ts`
  exits 0, including: Direction-A (newly-connected caught), Direction-B
  (stale-users-ready/live-workspaces-error dropped), and zero-rows-heartbeat
  scenarios. The `repo_status='ready'` filter assertion MUST be pinned to the
  **workspaces** chain (separate eq spy per table) — a shared `eqSpy` that
  cannot distinguish the table is insufficient and fails this AC.
- [ ] **AC8 — full suite green.** `cd apps/web-platform && ./node_modules/.bin/vitest run`
  exits 0 (orphan-suite safety: confirm `sentry-workspace-sync-health-alert-op-contract.test.ts`
  and `function-registry-count.test.ts` still pass — the op slugs and function
  count are unchanged by this PR).
- [ ] **AC9 — PR body uses `Ref #5437`, NOT `Closes #5437`** (umbrella stays open
  for the actual DROP).

### Post-merge (operator)

- None. Pure code change against already-provisioned surfaces; the
  `web-platform-release.yml` pipeline restarts the container on merge to main
  touching `apps/web-platform/**`, which re-syncs the Inngest function. No
  migration, no Doppler change, no infra change.

## Test Scenarios

1. **Arm 2 — stale-sync-failed, ready via workspaces:** a user whose
   `workspaces.repo_status='ready'` and whose latest `kb_sync_history` row is
   `ok:false` (install resolves non-null) → reported `op:"stale-sync-failed"`.
2. **Arm 2 — newly-connected (latent-bug fix):** a user with NO
   `users.repo_status` write but `workspaces.repo_status='ready'` and latest
   `kb_sync_history` `ok:false` → NOW reported (old filter false-excluded). RED
   before the change, GREEN after.
3. **Arm 2 — not-ready excluded:** a user whose `workspaces.repo_status != 'ready'`
   → never fetched in Step B → not reported.
3b. **Arm 2 — Direction-B symmetric drop:** a user with stale
   `users.repo_status='ready'` but `workspaces.repo_status='error'` is NOT
   reported after cutover (was reported before — proves the drop is intentional).
3c. **Zero ready workspaces → heartbeat still posts:** Step-A returns no rows;
   the step-scoped early return fires; `sentry-heartbeat` step.run STILL posts
   (proves the early return did not bubble to the handler).
4. **Arm 3 — went-quiet uses workspaces repo_url:** a ready user whose latest
   row is `ok:true` and whose default-branch HEAD is newer than last sync →
   reported `op:"went-quiet"`, using `repo_url` from the **workspaces** row.
5. **Arm 3 — null repo_url skipped:** a ready workspace with `repo_url=null` →
   `continue` (no probe), as today.
6. **Callback — first login provisions on disk:** `provisionWorkspace` still
   creates the dir; the `users` row carries `workspace_status:"ready"` without
   `workspace_path`.
7. **Workspace route — response still carries path:** POST returns
   `{ status:"ready", workspace_path: <derived path> }` while the `users` write
   no longer includes `workspace_path`.

## Risks & Mitigations

- **Wrong join darks the cron for everyone (single-user-incident class).**
  Mitigated by Shape B mirroring arm 1's shipped idiom + the dedicated test file
  exercising both arms + AC8 full-suite. deepen-plan Phase 4.4 precedent-diff
  against arm 1.
- **PostgREST embed (Shape A) may not resolve.** Mitigated by recommending
  Shape B as default; Shape A gated behind a deepen-plan live-schema FK check.
- **Unused `workspacePath` local in callback sites → tsc error.** Mitigated by
  AC6 and the explicit per-site treatment above (drop the `const`, keep the call).
- **`.in("id", ids)` unbounded if ready-workspace count grows large.** Accepted
  at p3 (daily cron, small N today); batch later if needed.
- **`repo_url` semantics:** workspaces `repo_url` is the same canonical
  `https://github.com/owner/repo` (normalizeRepoUrl) the arm-3 slug parser
  already expects — no parser change needed.

## Domain Review

**Domains relevant:** Engineering (data-integrity / observability). Product: NONE
(no UI surface — `## Files to Edit` contains no `components/**`, `app/**/page.tsx`,
or `app/**/layout.tsx`; callback/workspace routes are server route handlers).

This is an infrastructure/data-access refactor. Engineering concerns
(service-role join correctness, observability continuity) are captured in Risks
and Observability. No marketing/legal/finance/sales/support/ops implications.

## Architecture Decision (ADR/C4)

No NEW architectural decision. ADR-044 (`workspace-repo-ownership.md`) already
records the user→workspace ownership relocation; this PR is the *implementation
cleanup* that makes its column DROP precondition true. No ADR amend, no C4 edit
required — the architecture (repo cols owned by `workspaces`) is unchanged; this
PR removes the last code that still touched the deprecated `users` columns.
Skip per gate ("would a competent engineer reading the existing ADRs be misled
after this ships?" — No; ADR-044 already documents the target state).

## Observability

```yaml
liveness_signal:
  what: "cron-workspace-sync-health Sentry heartbeat (postSentryHeartbeat, slug cron-workspace-sync-health)"
  cadence: "daily (23 6 * * *)"
  alert_target: "Sentry cron monitor cron-workspace-sync-health (missed-checkin alert)"
  configured_in: "apps/web-platform/infra/sentry/ (sentry_cron_monitor), function L321-328"
error_reporting:
  destination: "Sentry via reportSilentFallback (op: scan-stale, scan-went-quiet, stale-sync-failed, went-quiet-probe, went-quiet)"
  fail_loud: "true — every DB error and per-row probe error is mirrored to Sentry; scan returns deterministic {reported:0}/{wentQuiet:0} on failure"
failure_modes:
  - mode: "workspaces readiness query fails"
    detection: "reportSilentFallback op=scan-stale / scan-went-quiet"
    alert_route: "Sentry workspace-sync-health feature"
  - mode: "users kb_sync_history fetch fails"
    detection: "reportSilentFallback (new op on the .in() fetch — reuse scan-stale / scan-went-quiet op)"
    alert_route: "Sentry workspace-sync-health feature"
  - mode: "per-row GitHub HEAD probe fails (arm 3)"
    detection: "reportSilentFallback op=went-quiet-probe (unchanged)"
    alert_route: "Sentry workspace-sync-health feature"
logs:
  where: "Inngest function logs + pino logger.info('Went-quiet scan complete')"
  retention: "Inngest run history + Better Stack (server logs)"
discoverability_test:
  command: "Sentry: search issues filtered to feature:workspace-sync-health; trigger-cron skill fires cron/workspace-sync-health.manual-trigger and observe heartbeat checkin (NO ssh)"
  expected_output: "heartbeat checkin recorded for slug cron-workspace-sync-health; any scan error appears as a Sentry issue under the workspace-sync-health feature"
```

**Op-slug continuity:** This PR does NOT remove any `reportSilentFallback` op
slug (`scan-stale`, `scan-went-quiet`, `stale-sync-failed`, `went-quiet`,
`went-quiet-probe`, `ready-null-installation`). If the Step-B `.in()` fetch adds
a NEW error path, reuse the existing `scan-stale`/`scan-went-quiet` op rather
than minting a new slug, so the existing
`sentry-workspace-sync-health-alert-op-contract.test.ts` stays green (verify in
AC8). Do not dark any alert that filters on these op slugs.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/TODO,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- The `rg -nU 'from("users")…repo_url'` AC will ALWAYS show
  `app/api/repo/status/route.ts` as a hit because the multi-line window spans the
  parallel `workspaces` query. This is the documented false-positive; the AC
  passes when that is the ONLY hit. Do not "fix" `repo/status/route.ts` — its
  `repo_url` is correctly read from `workspaces`.
- Do NOT remove `const workspacePath` in the **workspace route** (`route.ts:55`)
  — it still feeds the JSON response body (`route.ts:72`). Only the callback
  sites lose the local.
- `kb_sync_history` is `users`-only (mig 017). Do NOT relocate it. Step B fetches
  it from `users` by the workspace ids (which equal user ids under N2).
- PostgREST embed direction (`users` → `workspaces`) is unverified; default to
  Shape B (two queries) unless deepen-plan proves the embed resolves.

## Open Code-Review Overlap

1 open scope-out touches files this plan edits: **#3739** (extract
`reportSilentFallbackWithUser` helper — collapse 11-site
`withIsolationScope+setUser` duplication) names both `callback/route.ts` and
`api/workspace/route.ts`.

**Disposition: Acknowledge.** #3739 is an orthogonal observability-DRY refactor
(collapsing the `Sentry.withIsolationScope(() => { setUser; reportSilentFallback })`
boilerplate around the error paths). This PR only removes the `workspace_path`
KEY from the success-path payloads — it does not touch the `withIsolationScope`
error blocks #3739 targets. Folding #3739 in would balloon a tightly-scoped
PR-2b-precondition cleanup into an 11-site cross-file refactor, defeating the
"strictly this scope" mandate. #3739 stays open; the two PRs do not conflict
(different lines, different concern).
