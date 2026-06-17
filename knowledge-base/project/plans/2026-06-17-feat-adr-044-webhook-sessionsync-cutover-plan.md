---
title: "ADR-044 PR-2b precondition — cut the last two users.* repo-column sites off users (webhook reverse-lookup + session-sync write)"
date: 2026-06-17
type: feat
issue: "#5437 (umbrella, OPEN — Ref, NOT Closes)"
branch: feat-one-shot-adr044-webhook-sessionsync-cutover
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: ADR-044 PR-2b precondition — webhook founder attribution + session-sync write cutover

🔒 SECURITY-SENSITIVE · brand-survival threshold = **single-user incident**

## Overview

ADR-044 relocates the GitHub-App install credential and repo-state columns from `users.*` to `workspaces.*`. PR-2 (#5466) moved the connect-time **writes**; PR 5481 (#5470) added the service-role-safe `resolveInstallationIdForWorkspace` resolver and cut the two Inngest **readers** (agent-on-spawn, cron-sync-health) over. Two `users.*` sites explicitly remain (ADR-044 "Amendment 2026-06-17" closure §"Remaining #5470 set"):

1. **SURFACE 1 — webhook reverse-lookup** (`app/api/webhooks/github/route.ts` Step 5): resolves `founderId` via `service.from("users").select("id").eq("github_installation_id", installationId).maybeSingle()`, load-bearing on the mig-052 partial-UNIQUE. PR-2b drops that column AND the UNIQUE index, so this `.maybeSingle()` reverse-lookup breaks (and is structurally invalid against the NON-UNIQUE `workspaces.github_installation_id`).
2. **SURFACE 2 — session-sync write** (`server/session-sync.ts` `updateLastSynced`): writes `users.repo_last_synced_at`. PR-2 already moved the repo/status **read** to `workspaces.repo_last_synced_at`, so the displayed last-synced timestamp **freezes at connect-time** for newly-connected users until this write relocates.

This plan completes the remaining set so PR-2b's `users.github_installation_id` column drop is fully unblocked.

**The webhook attribution model was ROUTED TO THE CTO** (`soleur:engineering:cto`, binding ruling transcribed below and into the ADR). It is NOT guessed. The decision is **Option C (hybrid)** with a single-founder solo-workspace rule for non-push events and an explicit `>1`-match fail-closed branch.

**Split decision: TWO PRs** (per the CTO ruling — review-cycle isolation is itself a safety control at the single-user-incident threshold):

- **PR-A (this branch's primary, security-sensitive):** webhook founder attribution cutover.
- **PR-B (trivial, separable):** session-sync write relocation.

This branch carries BOTH (one-shot), but they land as two commits / are reviewable as two logical units; if the operator prefers strict separation the session-sync commit can be cherry-picked to its own PR. The PR body uses `Ref #5437` (umbrella — NOT `Closes`).

## Research Reconciliation — Spec vs. Codebase

| Claim (from ARGUMENTS / ADR) | Reality (verified against origin/main) | Plan response |
|---|---|---|
| "session-sync is the harder/security site's trivial sibling" | Session-sync writes `repo_last_synced_at` keyed on `.eq("id", userId)` — it does **NOT** touch `github_installation_id`. Strictly, it is not a *column-drop* precondition; it is a *correctness* fix (frozen timestamp). | Keep in scope (ARGUMENTS explicitly scope it; the read already moved so the freeze is a live bug), but characterize it correctly as a separable concern → PR-B. |
| "preserve tenant UPDATE posture if possible; only re-add to allowlist if the workspaces write genuinely requires service-role" (SURFACE 2) | **A tenant UPDATE is NOT possible.** `workspaces` has exactly ONE RLS policy — `workspaces_select_for_members` (SELECT only, mig 053:169). There is NO `GRANT UPDATE` on `workspaces` to `authenticated` anywhere, and NO UPDATE RLS policy. `writeRepoColsToWorkspace` doc-comment (lines 45-47): "Members cannot UPDATE `workspaces` directly (no UPDATE RLS policy)… the caller passes a service client." | The write genuinely requires service-role. Preserve session-sync's no-allowlist posture by **injecting** the service client from the already-allowlisted caller (`agent-runner.ts`, allowlist line 59), mirroring the in-file `appendKbSyncRowForWorkspace` precedent (session-sync.ts:726-755). session-sync.ts does NOT acquire service-role itself. (Alternative — a net-new `GRANT UPDATE (repo_last_synced_at)` + `workspaces_update_*` RLS policy — is rejected: net-new authenticated write boundary on the credential table, the exact surface the ADR amendment avoided for reads.) |
| "installation_id → founder via .maybeSingle() on workspaces" | `workspaces.github_installation_id` is NON-UNIQUE; one install → N workspaces (solo + team; two users + same fork). `.maybeSingle()` is structurally invalid. | Non-push founder resolution = solo-workspace self-join (below) with `>1` fail-closed; push keeps existing fan-out. |
| "founderId feeds isGranted + dispatch" | Confirmed: Step 6 `isGranted(service, founderId, actionClass)` (founder_id IS the tenant gate — service-role bypasses RLS); Step 7 dispatches `{founderId, …}`; Step 5.5 push dispatches `{founderId, …}` but the reconcile re-derives workspaces from `(installationId, repo_url)` → founderId is **vestigial** in the push payload. | Push: drop `founderId` from the reconcile payload (bump SCHEMA_V). Non-push: single founder via solo rule. |

## User-Brand Impact

**If this lands broken, the user experiences:** (a) webhook — GitHub PR-review / CI-failure / issue / advisory drafts silently stop arriving for a connected user (404-drop on a now-broken lookup), OR — far worse — a draft/action authorized against the WRONG founder's scope-grant and dispatched using the WRONG founder's installation token; (b) session-sync — the repo "last synced" timestamp on the dashboard stays frozen at connect-time forever, so a user can never tell whether their agent sessions are actually syncing their repo.

**If this leaks, the user's workflow / repo access is exposed via:** a shared-installation push or non-push event mis-attributed to a co-tenant founder → that founder's `scope_grant` gates an action and that founder's installation-token (repo write access) is used → cross-tenant action draft / repo write. This is the precise hazard the mig-052 UNIQUE silently prevented; PR-2b removes that guarantee, so the fail-closed `>1`-match branch is the load-bearing new defense.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. CPO is covered by the Domain Review carry-forward / must confirm the approach before work. `user-impact-reviewer` will be invoked at review-time.

## CTO Binding Ruling (transcribed — record verbatim in ADR-044)

**Decision: Option C (hybrid).**

- **Push stays exactly as-is.** Do not touch Step 5.5 or the reconcile fan-out (`workspace-reconcile-on-push.ts:163-175` re-derives workspaces from `(installation_id, repo_url)`). The only change push needs: `founderId` must no longer be sourced from the deleted `users` read. **Recommendation: drop `founderId` from the `WORKSPACE_RECONCILE_REQUESTED` payload entirely** (it is vestigial) and bump `WORKSPACE_RECONCILE_SCHEMA_V`.
- **Non-push events** (`pull_request`, `workflow_run` failure, `issues`, `repository_advisory`, `secret_scanning_alert`) resolve a **SINGLE** founder via the solo-workspace rule; Steps 6 (`isGranted`) and 7 (dispatch) remain single-decision, structurally unchanged. **Do NOT fan out Steps 6/7** (Option A rejected — fanning out grant-checks / N action dispatches multiplies the consent + installation-token surface by N; the cross-tenant hazard).

**Non-push founder resolution rule** (replaces the Step 5 `users` read for non-push events) — service-role read on `workspaces` filtered to SOLO workspaces via the membership self-join:

```sql
SELECT w.id
FROM workspaces w
JOIN workspace_members m
  ON m.workspace_id = w.id
 AND m.user_id      = w.id        -- solo invariant: member.user_id == workspace.id (ADR-038 N2)
 AND m.role         = 'owner'
WHERE w.github_installation_id = :installationId
```

`founderId := w.id` (== owner `users.id` by the invariant, so value-compatible with the old `users` read; `isGranted` + the installation-token path need no other change). There is no `is_solo` column — solo identity is structural (`workspaces.id == owner users.id`); the `m.user_id = w.id` join is the only sound discriminator and deliberately excludes team workspaces sharing the install (a team `id` is a fresh uuid, never == a member's user_id).

**Fail-closed by match count:**
- **0 rows** → `logger.warn` + `releaseDedupRow()` + **404** (preserves current "no founder" behavior; GitHub does not retry 4xx).
- **1 row** → proceed to Step 6 with `founderId = w.id`.
- **>1 rows** (two users, same fork — now genuinely reachable since the column is NON-UNIQUE) → **fail closed: do NOT pick one. `Sentry.captureException` (new tag `op: "founder-ambiguous"`, level error) + `releaseDedupRow()` + 404-drop. ZERO `inngest.send`, ZERO `isGranted`.** Dropping a recoverable event (GitHub state unchanged; re-drivable) is strictly safer than misattributing it (unrecoverable cross-tenant action). This is the single most important new code path.
- **DB error** → `Sentry.captureException` + `releaseDedupRow()` + **500** (preserves the existing Step 5 `founderErr` contract — do NOT regress to a silent 200).

**One-PR-vs-split: SPLIT.** PR-A = webhook attribution (security-sensitive, isolated review: security-sentinel + data-integrity-guardian + user-impact-reviewer). PR-B = session-sync write relocation (trivial, independent — does not touch `github_installation_id`). The actual `DROP COLUMN` is a *later* PR-2b, strictly after PR-A deploys + verifies (clean rollback boundary).

## Architecture Decision (ADR/C4)

### ADR
Amend `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — add an "Amendment 2026-06-17b — webhook founder attribution + session-sync write (remaining set CLOSED)" subsection that:
- transcribes the CTO ruling above (Decision, resolution rule incl. `>1` fail-closed, push-stays + vestigial-founderId removal, split-PR call, test invariants);
- records the verified fact that webhook Step 5 was the SOLE remaining `users.github_installation_id` 1:N reverse-lookup;
- marks the §"Remaining #5470 set" CLOSED once both surfaces land;
- notes the session-sync write resolves via service-role-injected `writeRepoColsToWorkspace` (no tenant UPDATE policy exists on `workspaces`).

This is an in-scope task of THIS plan (a `wg-architecture-decision-is-a-plan-deliverable` deliverable), not a follow-up issue. No `/soleur:architecture create` needed — the ruling IS the amendment content (Edit tool on the ADR file).

### C4 views
**Container/Component:** the connection edge moves from `read=Workspace / write=User (dual)` (the current `adopting` state) toward `read=Workspace / write=Workspace`. After this plan + PR-2b, the credential reverse-lookup edge (webhook) and the last repo-column write edge (session-sync) both originate at `Workspace`. Update the connection-owner edge note in the ADR-044 C4 view to reflect that the webhook + session-sync edges are now workspace-sourced. **Edit the `.c4` model file directly** if a corresponding view exists; otherwise the edge change is captured in the ADR amendment prose (grep `knowledge-base/**/*.c4` for an ADR-044 view at /work time).

### Sequencing
The ADR amendment is authored NOW (status: the webhook/session-sync edges are workspace-sourced as of this PR). The column DROP invariant fully holds only after PR-2b; the amendment notes PR-2b as the residual step but is not postponed to it.

## Files to Edit

**SURFACE 1 (webhook — PR-A):**
- `apps/web-platform/app/api/webhooks/github/route.ts` — Step 5: replace the `users` reverse-lookup. Split founder resolution by event type:
  - **Push branch (Step 5.5):** stop sourcing `founderId` from a `users` read; drop `founderId` from the `inngest.send` payload (see SCHEMA_V bump below). The reconcile already re-derives workspaces.
  - **Non-push branch (before Step 6):** resolve `founderId` via the new solo-workspace resolver; 0→404, 1→proceed, >1→Sentry `founder-ambiguous` + 404-drop, DB-error→500. Update the load-bearing comment block (lines 231-236) to describe the new fan-out-safe resolution (and ensure the `users.*github_installation_id` tokens do NOT co-occur on one line — the AC grep matches comments: learning `2026-06-17-injected-client-resolver-needs-no-allowlist…`).
- `apps/web-platform/server/resolve-installation-id-for-workspace.ts` (or a new sibling `server/resolve-founder-for-installation.ts`) — add the non-push solo-workspace founder resolver `resolveSoloFounderForInstallation(installationId, service): Promise<{ kind: "found"; founderId } | { kind: "none" } | { kind: "ambiguous"; count } | { kind: "db-error" }>`. **Injected service client (no allowlist entry** — mirrors `resolve-installation-id-for-workspace.ts` per ADR amendment + learning `2026-06-17-injected-client-resolver-needs-no-allowlist…`). Return a discriminated union (not a bare `string | null`) so the route can branch the 0/1/>1/error cases distinctly — the `>1` case must be distinguishable from `0`.
- `apps/web-platform/server/session-sync.ts` — the push payload's `founderId` is referenced via the shared `WORKSPACE_RECONCILE_*` consts exported here; bump `WORKSPACE_RECONCILE_SCHEMA_V` (currently `2`) → `3` and update the reconcile event's typed payload to drop `founderId`.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — drop `founderId` from the consumed event payload type (it was vestigial; the function already re-derives workspaces). Verify no read of `event.data.founderId` remains.

**SURFACE 2 (session-sync write — PR-B):**
- `apps/web-platform/server/session-sync.ts` — `updateLastSynced`: change signature to accept an **injected service client + resolved workspace id**, OR keep `(userId)` and have it resolve the active workspace + use an injected service client. Chosen shape: `updateLastSynced(service, workspaceId)` (mirrors `appendKbSyncRowForWorkspace(client, workspaceId, row)`). Write via `writeRepoColsToWorkspace(service, workspaceId, { repo_last_synced_at: new Date().toISOString() })`. Remove the `users` UPDATE.
- `apps/web-platform/server/session-sync.ts` — `syncPull` / `syncPush` (lines 778, 852): they call `updateLastSynced(userId)` at lines 830, 974. They must now (a) resolve the active workspace id (membership-verified `resolveActiveWorkspace(userId, <client>)`, never request input) and (b) pass a service client. **Decision:** thread the service client + resolved workspace id from the caller (`agent-runner.ts`) into `syncPull`/`syncPush`, OR resolve inside session-sync using an injected service client. Prefer threading the resolved workspace id from `agent-runner.ts` (which already calls `resolveActiveWorkspacePath`/has the service client and is allowlisted) — single resolution, no second divergent resolver call (learning `2026-06-05-adr-resolver-migration-must-sweep-write-routes…`).
- `apps/web-platform/server/agent-runner.ts` (lines 1166, 2262) — the `syncPull`/`syncPush` call sites: pass the injected service client + the resolved active workspace id. `agent-runner.ts` is already on the service-role allowlist (line 59) and already resolves the active workspace path — reuse that resolution to avoid a second resolver round-trip.

**Tests (both surfaces):**
- `apps/web-platform/test/github-webhook-founder-attribution.test.ts` (NEW; `test/**/*.test.ts` matches the vitest node project, `vitest.config.ts:44`) — webhook attribution matrix (see Test Scenarios). Mirror the structure of `test/webhook-subscription.test.ts` / `test/stripe-webhook-*.test.ts` (the existing webhook-route test pattern; there is currently NO github-webhook test).
- `apps/web-platform/test/server/session-sync-workspace-last-synced.test.ts` (NEW) OR extend `test/server/session-sync.tenant-isolation.test.ts` (which already documents `updateLastSynced` at :206) — assert the write lands on `workspaces.repo_last_synced_at` keyed on the resolved workspace id, no `users` write.

**ADR / C4:**
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — Amendment 2026-06-17b (above). Mark §"Remaining #5470 set" CLOSED.
- `knowledge-base/**/*.c4` (if an ADR-044 view exists) — connection-owner edge note.

## Files to Create
- `apps/web-platform/server/resolve-founder-for-installation.ts` (if not folded into the existing resolver file) — the non-push solo-founder resolver (injected service client, discriminated-union return).
- `apps/web-platform/test/github-webhook-founder-attribution.test.ts`
- `apps/web-platform/test/server/session-sync-workspace-last-synced.test.ts` (or extend existing).

## Open Code-Review Overlap
Run at /work after the file list is final:
```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
# then per planned path: jq -r --arg path "<path>" '.[]|select(.body//""|contains($path))|"#\(.number): \(.title)"' /tmp/open-review-issues.json
```
Baseline at plan time: not yet run (defer the per-path query to /work once the exact paths are frozen). Record `None` or the matches + disposition there.

## Acceptance Criteria

### Pre-merge (PR)

**SURFACE 1 — webhook:**
1. `git grep 'github_installation_id' apps/web-platform/app/api/webhooks/github/` resolves via `workspaces` (the solo-founder resolver) — **no `users` reverse-lookup remains**. Verify the literal grep; ensure no `users` + `github_installation_id` co-occur on one comment line (the grep matches comments).
2. `git grep -nE '\.from\("users"\)' apps/web-platform/app/api/webhooks/github/route.ts` returns **0** (the founder lookup was the only `users` read in this route).
3. Non-push founder resolution is a discriminated union over {found, none, ambiguous, db-error}; the `>1` (ambiguous) case is handled distinctly from `0` (none) — NOT a silent `.maybeSingle()` against a non-unique column.
4. `WORKSPACE_RECONCILE_SCHEMA_V` bumped (2→3); `founderId` dropped from the reconcile event payload type AND `workspace-reconcile-on-push.ts` reads no `event.data.founderId`. (`git grep 'event.data.founderId\|data.founderId' apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` == 0.)
5. Push branch performs **no** `from("users")` call and the reconcile fan-out still keys on `(installationId, repo_url)`.

**SURFACE 2 — session-sync:**
6. `git grep -nE 'from\("users"\)\.update' apps/web-platform/server/session-sync.ts` returns **0** for `repo_last_synced_at` (the `updateLastSynced` `users` write is gone).
7. `updateLastSynced` writes `workspaces.repo_last_synced_at` via `writeRepoColsToWorkspace` (service client injected, NOT acquired in session-sync.ts).
8. session-sync.ts is **NOT** added to `apps/web-platform/.service-role-allowlist` (`grep -c 'session-sync' .service-role-allowlist` in the file-entry section stays 0; the privilege-acquisition site stays in `agent-runner.ts`). CI `service-role-allowlist-gate.sh` passes.
9. The repo/status read (`workspaces.repo_last_synced_at`, `app/api/repo/status/route.ts:106`) reads back the value written by a session sync — no longer frozen at connect-time. (Test scenario, below.)

**Both:**
10. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes (NOT `npm run -w` — repo root has no `workspaces` field; learning `2026-05-13-npm-workspaces-flag…`).
11. `cd apps/web-platform && ./node_modules/.bin/vitest run test/github-webhook-founder-attribution.test.ts test/server/session-sync*.test.ts` passes (check `bunfig.toml` — `apps/web-platform` uses vitest, not bun test).
12. ADR-044 amended (Amendment 2026-06-17b transcribing the CTO ruling); §"Remaining #5470 set" marked CLOSED.
13. PR body uses `Ref #5437` (NOT `Closes`). `git grep` of every `knowledge-base/` path cited in the plan resolves (`grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'`).

### Post-merge (operator)
- None automatable-or-otherwise required for PR-A/PR-B themselves (the column DROP is the *separate* PR-2b, out of scope here). `Ref #5437` keeps the umbrella open.

## Test Scenarios (webhook attribution — the load-bearing matrix)

1. **Single solo match → correct founder.** One solo workspace (`workspaces.id == users.id`, member role=owner self-row) with `installation_id=X`, a non-push event (`pull_request`). Assert `founderId == workspaces.id`, `isGranted` called with that exact value, dispatch proceeds.
2. **Zero match → 404 + dedup released, no dispatch.** No workspace carries `installation_id=X`. Assert 404, `releaseDedupRow` invoked, zero `inngest.send`.
3. **>1 solo match → fail-closed drop (LOAD-BEARING).** Two solo workspaces (two distinct user ids, each `workspaces.id == own users.id`) both with `installation_id=X`. Assert: NO founder selected, `Sentry.captureException` with `op: "founder-ambiguous"`, `releaseDedupRow` invoked, 404, **zero `inngest.send`, zero `isGranted`**.
4. **Team workspace sharing install is NOT a founder.** One solo (id==user) + one team (fresh uuid id, member but `id != user_id`) both with `installation_id=X`. Resolver returns exactly the solo founder (the `m.user_id = w.id` join excludes the team row) → resolves to 1, NOT the `>1` branch.
5. **Push dispatches reconcile without a `users` read** (and without `founderId` in the payload). Assert no `from("users")` call on the push path; reconcile still keys on `(installationId, repo_url)`.
6. **DB error on resolver → 500 + dedup released** (existing Step 5 contract preserved; not a silent 200).

## Test Scenarios (session-sync write)
7. **Write lands on workspaces, keyed on resolved workspace id.** `updateLastSynced(service, workspaceId)` issues `from("workspaces").update({repo_last_synced_at}).eq("id", workspaceId)` (via `writeRepoColsToWorkspace`); assert no `users` write.
8. **Read-back parity.** A simulated sync writes `workspaces.repo_last_synced_at`; the repo/status read (`activeWorkspaceId`) returns the fresh value (not the connect-time value). Asserts the freeze bug is fixed.
9. **0-row write surfaces (not silent).** Workspace id doesn't exist → `writeRepoColsToWorkspace` Sentry-mirrors the 0-row no-op (inherited behavior). Best-effort: does not throw (sync must not fail on a missing audit row).

## Domain Review

**Domains relevant:** Engineering (CTO — ruling obtained, above), Product (CPO sign-off — single-user-incident threshold). Legal/compliance touched lightly (credential/auth boundary) — covered by gdpr-gate at /work Phase 2.7 (auth-flow + API-route surfaces in the canonical regex).

### Engineering (CTO)
**Status:** reviewed (binding ruling obtained during planning — transcribed above + into ADR).
**Assessment:** Option C hybrid; non-push solo-founder rule with `>1` fail-closed; push unchanged + vestigial `founderId` dropped; split into PR-A (webhook) + PR-B (session-sync); 6 webhook test invariants mandated.

### Product/UX Gate
**Tier:** none — no user-facing page/component/flow file in Files to Edit (the `from("users")`-grep of `## Files to Create`/`## Files to Edit` matches no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). The repo/status timestamp is rendered by an already-existing component; no new UI surface. CPO sign-off (threshold-driven) is a strategy ack, not a UX-gate wireframe.

## Observability

```yaml
liveness_signal:
  what: "GitHub webhook non-push events dispatch (inngest.send for action classes) + push reconcile dispatch"
  cadence: "event-driven (per GitHub delivery)"
  alert_target: "Sentry — existing feature:github-webhook tag set"
  configured_in: "apps/web-platform/infra/sentry/ (existing github-webhook ops) + apps/web-platform/app/api/webhooks/github/route.ts"
error_reporting:
  destination: "Sentry.captureException / captureMessage with tags { feature: 'github-webhook', op: <op> }"
  fail_loud: "yes — new op:'founder-ambiguous' (level error) on the >1-match fail-closed branch; existing op:'founder-lookup' on DB error; session-sync write 0-row + error via reportSilentFallback (feature:'workspace-repo-write')"
failure_modes:
  - { mode: "installation→>1 solo workspaces (ambiguous founder)", detection: "Sentry op:founder-ambiguous", alert_route: "Sentry github-webhook" }
  - { mode: "installation→0 founders (404 drop)", detection: "logger.warn + 404 (no Sentry — expected for uninstalled)", alert_route: "Better Stack log query on the warn line" }
  - { mode: "founder-resolver DB error (500)", detection: "Sentry op:founder-lookup (or new op:founder-resolve)", alert_route: "Sentry github-webhook" }
  - { mode: "session-sync workspace write 0-row / error", detection: "reportSilentFallback → Sentry feature:workspace-repo-write", alert_route: "Sentry" }
logs:
  where: "pino → stdout (container) ; Sentry for error class"
  retention: "Sentry default project retention"
discoverability_test:
  command: "Query Sentry issues filtered tag feature:github-webhook op:founder-ambiguous via the Sentry API (no ssh); confirm the >1-match test scenario would surface there"
  expected_output: "an event with op:founder-ambiguous when two solo workspaces share an installation_id"
```

## Risks & Mitigations

- **R1 — Cross-tenant misattribution (the brand-survival risk).** Mitigated by the `>1`-match fail-closed branch (Test Scenario 3, mandatory) + the solo self-join that excludes team workspaces (Scenario 4). The OLD mig-052 UNIQUE made `>1` unreachable; this branch makes the previously-structural guarantee an explicit runtime fail-closed.
- **R2 — Reader sweep misses a `.eq()`-shaped lookup.** Per learning `2026-06-17-column-relocation-reader-sweep-and-stranded-eq-lookups.md`: run the DUAL-shape grep at /work: `git grep -nE "\.(eq|in|match|or|filter)\([\"']?github_installation_id|select\([^)]*\bgithub_installation_id\b" -- apps/web-platform/`. The webhook reverse-lookup is itself a `.eq()` reader; confirm no OTHER stranded `.eq("github_installation_id", …)` on `users` survives outside the two known sites + the self-read in `detect-installation/route.ts` (keyed on `.eq("id", user.id)` — a column-location cutover, not a 1:N lookup; verify it's already handled or note it).
- **R3 — Tenant write to workspaces silently rejected in prod.** Avoided entirely by NOT attempting a tenant UPDATE (no GRANT/policy exists; learning `2026-05-21-rls-restrictive-policy-plus-column-grant-blocks-tenant-writes.md`). Service-role injection is the only viable path; tests must exercise the injected-service path, not a mocked tenant client (the auth boundary is at the wire).
- **R4 — Second divergent workspace resolver in session-sync.** Avoided by threading the ONE resolved active-workspace id from `agent-runner.ts` into `syncPull`/`syncPush` (learning `2026-06-05-adr-resolver-migration-must-sweep-write-routes…`), not re-resolving inside session-sync.
- **R5 — AC grep false-fail on cutover comments.** Reword the Step 5 comment so `users` and `github_installation_id` don't co-occur on a single line (learning `2026-06-17-injected-client-resolver-needs-no-allowlist…`).
- **R6 — SCHEMA_V bump + in-flight events.** Dropping `founderId` from the reconcile payload while events with the old shape are in flight: the consumer drops `founderId` (it was vestigial — never read for routing), so old-shape events with an extra `founderId` field are harmless. Confirm the consumer doesn't *require* `founderId`'s presence (it won't, post-edit). Inngest `event.id` dedup unaffected by SCHEMA_V.

## Precedent diff (for deepen-plan Phase 4.4)
- Non-push founder resolver: precedent = `resolve-installation-id-for-workspace.ts` (injected service client, single `.eq("id",…)`, no allowlist). Diff: this resolver keys on `github_installation_id` (not `id`) and must handle `>1` (the existing resolver's `.maybeSingle()` cannot — the difference is the whole point).
- Service-role write injection: precedent = `appendKbSyncRowForWorkspace` (session-sync.ts:726-755) + `writeRepoColsToWorkspace` (workspace-repo-mirror.ts). Diff: none material — reuse `writeRepoColsToWorkspace` directly.
- Webhook test shape: precedent = `test/webhook-subscription.test.ts`, `test/stripe-webhook-*.test.ts`.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan Phase 4.6 — it is filled above (threshold: single-user incident).
- Session-sync is NOT a `github_installation_id` column-drop precondition (it writes `repo_last_synced_at`); it is in scope as a correctness fix and as the last `users.*` repo-column write. Do not conflate it with the credential drop in the ADR amendment.
- The `>1`-match branch is genuinely reachable (column is NON-UNIQUE by design) — it is the one new path that, if wrong, causes the brand-survival incident. Test Scenario 3 is mandatory, not optional.
