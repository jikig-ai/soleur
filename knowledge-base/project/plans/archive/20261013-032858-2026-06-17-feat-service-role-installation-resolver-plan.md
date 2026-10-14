---
title: "feat: Service-role-safe GitHub-App installation resolver + cut two Inngest readers"
type: feat
date: 2026-06-17
issue: 5470
branch: feat-one-shot-5470-installation-resolver
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: Service-role-safe GitHub-App installation resolver + cut two Inngest readers

Add a **service-role-safe** resolver `resolveInstallationIdForWorkspace(workspaceId, service)` that reads `workspaces.github_installation_id` directly via the service-role client (no `auth.uid()` needed), and cut the two Inngest service-role readers (`agent-on-spawn-requested`, `cron-workspace-sync-health`) off `users.github_installation_id` onto it. This is a **PR-2b (#5437) precondition**: PR-2b drops `users.github_installation_id`, so both readers MUST be on the workspaces-keyed path before that drop or they break git-auth for **all** users.

The canonical authenticated reader `resolve_workspace_installation_id` (mig 079) gates on `is_workspace_member(p_workspace_id, auth.uid())` and is `REVOKE`'d from `service_role`, so it returns NULL in any Inngest/cron context. A distinct service-role path is required (CTO Option-D ruling, ADR-044 amendment).

## User-Brand Impact

- **If this lands broken, the user experiences:** the autonomous Concierge agent (`agent-on-spawn`) fails to dispatch any GitHub work for a newly-connected user — every action card returns `github_installation_unauthorized` ("GitHub authorization failed") — and the KB sync-health cron silently misclassifies users (false "needs re-authorization" alerts or missed went-quiet detection). At PR-2b drop time, with `users.github_installation_id` gone, **every** user's agent-on-spawn dispatch breaks, not just newly-connected ones.
- **If this leaks, the user's GitHub repository access is exposed via:** `workspaces.github_installation_id` is a GitHub App installation-token grant (write access to the user's connected repos). A resolver that returns the **wrong** workspace's installation id would let one tenant's autonomous agent act on another tenant's repo — a cross-tenant write. The membership-bypass is justified ONLY because the *caller* is trusted server code (Inngest/cron) keying on a server-derived id, never on a request-supplied workspace id.
- **Brand-survival threshold:** `single-user incident` (inherited from ADR-044 — a stranded or mis-keyed single user is a brand-survival event).

## Enhancement Summary

**Deepened on:** 2026-06-17. Hard gates (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped, 4.9 UI-wireframe) all pass. Precedent-diff gate (4.4) + verify-the-negative pass run.

**Key verifications (all confirmed against `origin/main` code):**
1. `service_role` retains the `workspaces` table grant — mig `079:88` and `110:61` both `REVOKE SELECT ... FROM authenticated` only (never service_role). Direct service-role read is correct; **no new RPC, no new migration**.
2. Precedent `workspace-identity-resolver.ts:70` mirrors faithfully (injected `service`, `.maybeSingle()`, `MaybeSingleChain<T>`) — the one thing NOT to copy is its `auth.getUser()` gate (plan already excludes it).
3. agent-on-spawn solo-keying (`founderId`) is behavior-preserving vs the current `users WHERE id=founderId` read — verified via the backfilled-solo invariant; team-workspace case is a pre-existing, orthogonal blind spot (out of scope).
4. Cron arms preserve detection semantics + strictly improve newly-connected solo coverage (Test Scenario 6).
5. New Sentry *feature* tag has no dedicated alert rule — by design; the loud signal is the caller's path (Observability section updated to state this explicitly).

**Precedent diff (Phase 4.4) — `workspace-identity-resolver.ts:70` vs the new resolver:**

| Axis | Precedent (`workspace-identity-resolver.ts`) | New `resolveInstallationIdForWorkspace` |
|---|---|---|
| client | injected `service: ServiceClient` (`{ from }` iface) | injected `service` — **same** |
| read | `service.from("workspaces").select(...).eq("id", wsId).maybeSingle()` | `…select("github_installation_id").eq("id", workspaceId).maybeSingle()` — **same shape** |
| not-found | `if (resp.error || !resp.data) return null` | `null` — **same** |
| auth gate | HAS `supabase.auth.getUser()` (auth-scoped resolver) | **MUST OMIT** — service-role, no `auth.uid()` (only divergence; intentional) |

## Research Reconciliation — Spec vs. Codebase

The task description and issue #5470 body both describe the cron readers imprecisely. The codebase reality (verified by reading `cron-workspace-sync-health.ts` in full + migrations 011/017/079) differs in ways that change the plan's shape:

| Spec / task claim | Codebase reality (file:line) | Plan response |
|---|---|---|
| Cron reads `users.github_installation_id` in `scan-went-quiet` (~L192) and `scan-ready-null-installation` / non-null scans (~L57, L116) | `scan-ready-null-installation` (L57-79) reads **`from("workspaces")`** — already workspaces-keyed, NOT a `users` read. The two **`from("users")`** reads are `scan-stale-sync-failed` (L113) and `scan-went-quiet` (L191). Line 116 is the `.not("github_installation_id"…)` predicate **inside** the L113 `users` query, not a separate read. | Plan targets the **two** actual `from("users")` reads (L109-155 `scan-stale-sync-failed`, L186-301 `scan-went-quiet`). Arm-1 (L57) needs no change — it already reads workspaces. |
| All `from("users")` reads of `github_installation_id` "move to the workspaces-keyed resolver" | Both `users` arms read **`kb_sync_history`** in the same query. `kb_sync_history` lives on **`users` only** (mig 017; ADR-044 deliberately did NOT mirror history to workspaces — see cron comment L105-107). | The arms CANNOT become workspaces-only reads. Design: keep the `users` read for `kb_sync_history` + `id` (+ `repo_url` for went-quiet), but resolve the **installation id** via the new resolver keyed on the user's solo workspace (`workspaces.id = users.id`, ADR-038 N2). The `users.github_installation_id` **select/predicate** is removed; the install is resolved per-row from workspaces. |
| Two readers (agent-on-spawn + cron) | ADR-044 amendment (L243-257) records the #5470 set as **three reads + one write**: also `app/api/webhooks/github/route.ts` (reverse `.eq("github_installation_id",…)` lookup) and `server/session-sync.ts` (writes `users.repo_last_synced_at`). | These two are **out of scope** for this issue (AC4 is scoped to `server/inngest/**`; the webhook + session-sync are separate surfaces tracked by the same #5470 blocker umbrella). See `## Out of Scope`. Plan documents them explicitly so the reviewer does not re-file. |
| "membership-bypass SECURITY DEFINER RPC **or** direct service-role read" | `service_role` **keeps its default table SELECT grant** on `workspaces` (the mig-079 column REVOKE hit `authenticated` only — see 079 §2 comment). Direct service-role read of `workspaces.github_installation_id` **works today**, no new RPC needed. Precedent: `workspace-identity-resolver.ts:70`, `org-memberships-resolver.ts:100` already do service-role `from("workspaces")` reads. | **Chosen: direct service-role read** (Option A), not a new RPC. Smaller surface, no new migration, mirrors existing precedent. See Decision 1. |
| Premise PRs/issues | #5462 (PR-2) CLOSED; PR #5466 MERGED; #5437 (PR-2b) OPEN. | Premise holds. |

## Considered Approaches

| # | Approach | Decision |
|---|----------|----------|
| 1 | **Direct service-role `from("workspaces").select("github_installation_id").eq("id", workspaceId)`** in a new shared resolver module | **Chosen.** `service_role` retains the table grant (mig 079 §2 revoked only `authenticated`); the credential column is reachable by service-role today. Mirrors `workspace-identity-resolver.ts`. No new migration, no new RPC EXECUTE grant to audit. |
| 2 | New `service_role`-granted SECURITY DEFINER RPC `resolve_workspace_installation_id_service(uuid)` (membership-bypass) | Rejected. Adds a migration, a second credential-reading RPC, and a `service_role` EXECUTE grant — a *new* privileged surface to audit — for zero capability gain over the direct read (service-role already reads the column). The 079 RPC's whole purpose was to keep the column off the *authenticated* grant; service-role was never the threat model. |
| 3 | Reuse `resolveInstallationId(userId, workspaceId?)` (the tenant-client/RPC reader) | Rejected — structurally impossible. It calls `getFreshTenantClient(userId)` + the `auth.uid()`-gated RPC; in an Inngest context there is no session, so the RPC returns NULL (the exact gap #5470 exists to close). |
| 4 | Inline the read in each of the two functions (no shared module) | Rejected. Duplicates the credential-read shape across two files, and the unit test (AC: "resolves in BOTH contexts") wants one resolver to test once. A shared module also concentrates the allowlist/CODEOWNERS surface to one new file. |

## Key Decisions

1. **Direct service-role read, not a new RPC** (Approach 1). `resolveInstallationIdForWorkspace(workspaceId: string, service: ServiceClient): Promise<number | null>` reads `workspaces.github_installation_id` and returns the id or `null` (genuine "not connected" / not found). Errors mirror to Sentry via `reportSilentFallback` and return `null` (the callers already treat null as "no install"). Injected `service` param mirrors `workspace-identity-resolver.ts` (testable, no in-fn client construction).
2. **Founder→workspace keying = solo workspace** (`workspaces.id = users.id`, ADR-038 N2). `agent-on-spawn` carries only `founderId` on the event (no workspace id); the handler already uses `workspaceId: founderId` downstream (L331). So `resolveInstallationIdForWorkspace(founderId, service)` is a faithful drop-in for the current `users.github_installation_id WHERE id = founderId` read. **Not** `resolveActiveWorkspace` — that resolves the *current* workspace from `user_session_state`, a behavioral change (agent-on-spawn today resolves the founder's own row, i.e. solo). Keeping solo keying preserves current behavior exactly; broadening to active-workspace is a separate concern (north-star, out of scope).
   - **Equivalence basis (verified):** post-PR-2, the connect-time writer (`repo/setup`) writes `github_installation_id` to `workspaces[activeWorkspaceId]`, and `users.github_installation_id` is **no longer written by any code** (zero write sites repo-wide). So the `users WHERE id=founderId` → `workspaces WHERE id=founderId` swap is exact *via the backfilled-solo invariant* (mig 080 backfilled `workspaces[userId].github_installation_id` from `users`), not a live column copy. For a user whose ACTIVE workspace is a TEAM workspace, BOTH the current `users` read AND the planned solo read return NULL/stale (the install lives on the team row) — agent-on-spawn is **already** solo-only and cannot dispatch team-connected repos today. This cut-over neither fixes nor worsens the team case; it only additionally catches newly-connected SOLO users whose `users.github_installation_id` is NULL but `workspaces[solo]` is populated.
3. **Cron arms keep their `users` read for `kb_sync_history`**; only the install resolution moves. `kb_sync_history` is users-only (mig 017). For each `users` row the arm already iterates, resolve the install via `resolveInstallationIdForWorkspace(r.id, service)` (the user's solo workspace) instead of reading `r.github_installation_id`. This removes `github_installation_id` from the `users` select AND the `.not("github_installation_id","is",null)` predicate; the per-row null-install skip replaces the predicate. **Net behavior preserved:** a row with NULL workspace install is skipped exactly as the predicate skipped a NULL `users` install.
4. **New resolver file added to `.service-role-allowlist`** (CODEOWNERS-gated). `resolve-installation-id.ts` was *removed* from the allowlist in PR #4559 (it uses the tenant client now); the new service-role file needs its own PERMANENT entry with a one-line justification. The two inngest files are already allowlisted.
5. **ADR-044 amendment + C4 edge is a deliverable of this PR** (plan Phase 2.10 gate), not a deferred issue — the capability gap recorded in ADR-044 §"Considered Options (amendment)" is closed here; the ADR must record the closure and the chosen mechanism.
6. **Link #5470 as a blocker on #5437 at ship time** (post-merge step) — `Ref #5437` in the PR body (NOT `Closes`, since #5437 is the umbrella PR-2b that this only unblocks), plus a comment on #5437 noting the blocker is resolved.

## Files to Create

- `apps/web-platform/server/resolve-installation-id-for-workspace.ts` — the new service-role resolver. Mirrors `workspace-identity-resolver.ts` structure: local `interface ServiceClient { from: (t: string) => unknown }`, reuse the `MaybeSingleChain<T>` shape, no `auth.getUser()` gate. Signature: `resolveInstallationIdForWorkspace(workspaceId: string, service: ServiceClient): Promise<number | null>`. On error → `reportSilentFallback({feature:"resolve-installation-id-for-workspace", op:"workspaces-read", extra:{workspaceId}})` + return null.
- `apps/web-platform/test/server/inngest/resolve-installation-id-for-workspace.test.ts` — unit tests for the resolver in isolation (NULL `users` / populated `workspaces` → resolves; not-found → null; db-error → null + Sentry mirror).

## Files to Edit

- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` — replace the `resolve-installation` step body (L224-243): drop the `from("users").select("github_installation_id").eq("id", founderId)` read; call `resolveInstallationIdForWorkspace(founderId, getServiceClient())`. Preserve the throw-on-null behavior (`no github_installation_id for founder` → `github_installation_unauthorized`). Update the I1 comment block (L15-18) to cite `workspaces.github_installation_id` via the new resolver, not `users.github_installation_id`.
- `apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts` — two arms:
  - `scan-stale-sync-failed` (L109-155): drop `github_installation_id` from the `users` select; drop `.not("github_installation_id","is",null)` predicate; per row, `const install = await resolveInstallationIdForWorkspace(r.id, service); if (install === null) continue;` before the `kb_sync_history` check. (This arm currently uses the install only as an existence gate, so the per-row resolve + skip is exact-behavior.)
  - `scan-went-quiet` (L186-301): drop `github_installation_id` from the `users` select; drop the predicate; per row resolve `const install = await resolveInstallationIdForWorkspace(r.id, service)`; replace `r.github_installation_id` usage at the `getDefaultBranchHeadCommitAt(r.github_installation_id, …)` call (L251) and the `if (!r.repo_url || !r.github_installation_id) continue;` gate (L217) with the resolved `install`.
  - Update the file header comment (L1-19) where it describes reading `users.github_installation_id`.
  - **Leave arm-1 `scan-ready-null-installation` (L57-79) untouched** — already reads `workspaces`.
- `apps/web-platform/.service-role-allowlist` — add PERMANENT entry: `apps/web-platform/server/resolve-installation-id-for-workspace.ts` with a `# <reason>` comment (service-role read of the `workspaces` credential column for Inngest/cron contexts where `auth.uid()` is NULL; membership-bypass justified — caller keys on server-derived ids only).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — amend the "Considered Options (amendment)" / "Capability gap recorded" section to record the gap as **closed** by the direct service-role resolver (Decision 1), and note the two inngest readers cut over; flag webhook-route + session-sync as still-open within the #5470 umbrella.

## Open Code-Review Overlap

`gh issue list --label code-review --state open` → checked the planned file paths (`resolve-installation-id-for-workspace.ts`, `agent-on-spawn-requested.ts`, `cron-workspace-sync-health.ts`, `.service-role-allowlist`). **None** — no open code-review scope-out touches these files. (Run the two-stage `gh --json` + standalone `jq --arg` form at /work Phase 0 to re-confirm against live state.)

## Implementation Phases

### Phase 0 — Preconditions (verify, don't assume)
- `git grep -n 'github_installation_id' apps/web-platform/server/inngest/` to confirm the current read sites match the plan's line refs (the file may have drifted).
- Confirm `service_role` reads `workspaces.github_installation_id`: read mig 079 §2 (the REVOKE is `FROM authenticated`, service_role keeps its grant). Cited; no live DB call needed (read-only schema fact).
- Confirm `workspace-identity-resolver.ts` resolver shape to mirror.
- Re-run the Open Code-Review Overlap query against live state.
- Confirm test command: `cd apps/web-platform && npx vitest run test/server/inngest/resolve-installation-id-for-workspace.test.ts` (NOT `bun test` — `bunfig.toml` `pathIgnorePatterns=["**"]`). Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

### Phase 1 — RED: resolver unit tests
- Write `resolve-installation-id-for-workspace.test.ts` with the structural service-client mock (mirror `cron-workspace-sync-health.test.ts`'s `serviceFrom` chain). Cases: (a) populated `workspaces.github_installation_id` → resolves the number; (b) row exists, install NULL → `null`; (c) no workspace row → `null`; (d) db error → `null` + asserts `reportSilentFallback` called. Tests fail (module does not exist yet).

### Phase 2 — GREEN: resolver
- Create `resolve-installation-id-for-workspace.ts`. Run Phase 1 tests green.
- Add the `.service-role-allowlist` entry. (The CI `service-role-allowlist-gate` job will reject the new import otherwise.)

### Phase 3 — Cut agent-on-spawn
- Edit `agent-on-spawn-requested.ts` `resolve-installation` step + I1 comment.
- Extend / add to `agent-on-spawn-requested-leader-loop.test.ts` (or a focused test): newly-connected founder (NULL `users.github_installation_id`, populated `workspaces` keyed `id=founderId`) → install resolves, dispatch proceeds. (Contract change: the test's service mock now seeds `workspaces`, not `users`, for the install.)

### Phase 4 — Cut cron arms
- Edit `scan-stale-sync-failed` + `scan-went-quiet` per Decision 3. Update header comment.
- Extend `cron-workspace-sync-health.test.ts`: newly-connected user (NULL `users.github_installation_id`, populated `workspaces`) — assert both arms still resolve the install and behave identically (stale-sync fires on ok:false latest; went-quiet probes GitHub with the resolved install).

### Phase 5 — Verify AC4 + typecheck + full suite
- `git grep 'users.*github_installation_id' apps/web-platform/server/inngest/` → 0 (comments included — the I1 + cron header comments must be rewritten so the grep is genuinely 0, not just the code). **Note:** the grep matches comment lines too (Phase 0 showed the original comment hit), so AC4 requires comment cleanup, not just code cuts.
- `./node_modules/.bin/tsc --noEmit` clean.
- `npx vitest run test/server/inngest/` green.

### Phase 6 — ADR amendment + C4
- Amend ADR-044 (Decision 5). Route any C4 connection-owner edge note through `/soleur:architecture` (c4-edit flag, Concierge-only) — but the ADR text amendment lands in this PR.

### Post-merge (operator-automatable)
- Link #5470 → #5437: `Ref #5437` in PR body (pre-merge); post-merge `gh issue comment 5437 --body "…#5470 service-role resolver merged; PR-2b column-drop precondition satisfied for the two inngest readers. Remaining #5470 set: webhook-route reverse-lookup + session-sync write."` — automatable via `gh` CLI; bake into `/soleur:ship`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `resolveInstallationIdForWorkspace(workspaceId, service)` exists at `apps/web-platform/server/resolve-installation-id-for-workspace.ts`, reads `workspaces.github_installation_id` via service-role, returns `number | null`, mirrors errors to Sentry. Unit-tested (4 cases above green).
- [ ] `apps/web-platform/server/resolve-installation-id-for-workspace.ts` present in `.service-role-allowlist` with a justification comment.
- [ ] `agent-on-spawn-requested.ts` `resolve-installation` step no longer reads `users.github_installation_id`; resolves via the new resolver keyed on `founderId`. Test: newly-connected founder (NULL `users`, populated `workspaces`) resolves the install.
- [ ] `cron-workspace-sync-health.ts` `scan-stale-sync-failed` + `scan-went-quiet` no longer select/predicate `users.github_installation_id`; resolve per-row via the new resolver. `kb_sync_history` still read from `users`. Test: newly-connected user resolves the install in BOTH arms.
- [ ] `git grep 'users.*github_installation_id' apps/web-platform/server/inngest/` returns **0** (code AND comments).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean; `npx vitest run test/server/inngest/` green.
- [ ] ADR-044 amended: capability gap recorded as closed (direct service-role resolver), two inngest readers cut over, webhook+session-sync flagged as remaining #5470 set.
- [ ] PR body uses `Ref #5437` (not `Closes`).
- [ ] CPO sign-off recorded (single-user-incident threshold).

### Post-merge (operator)
- [ ] `gh issue comment 5437` posted noting the precondition is satisfied for the two inngest readers. *Automatable via `gh` CLI; fold into `/soleur:ship`.*

## Out of Scope (with rationale)
- **`app/api/webhooks/github/route.ts`** reverse `.eq("github_installation_id",…)` founder-resolver — part of the #5470 ADR-044 umbrella but NOT a `server/inngest/**` reader (AC4 scope) and needs the *fan-out reconcile* shape (workspaces install is non-unique), a materially different change. Tracked under #5437/#5470 umbrella; do not fold in.
- **`server/session-sync.ts` `updateLastSynced`** — a *write* of `users.repo_last_synced_at` (different column, different verb). Out of the github_installation_id scope. Tracked under the same umbrella.
- **Broadening agent-on-spawn to active-workspace keying** (north-star) — current behavior is solo-keyed; preserving it is correct. Active-workspace is a separate behavioral change.
- The PR-2b column DROP itself (#5437) — this is its precondition, not the drop.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)
**Status:** carry-forward from ADR-044 brainstorm `2026-06-16-adr-044-workspace-owned-connection-brainstorm.md`
**Assessment:** Option-D ruling already binding: service-role readers need a net-new service-role-safe resolver. Direct service-role read (not a new RPC) is the smallest safe shape — service_role retains the `workspaces` table grant; no new privileged RPC surface. Mirror `workspace-identity-resolver.ts`. The `kb_sync_history` users-only constraint is the load-bearing cron design fact.

### Legal (CLO)
**Status:** carry-forward from ADR-044 brainstorm + GDPR gate (Phase 2.7)
**Assessment:** `workspaces.github_installation_id` is a GitHub App token grant — an Art. 6(1)(b) contract credential. The membership-bypass is acceptable in trusted server context ONLY because callers key on server-derived ids (`founderId`/own-row id), never request-supplied. CLO's brainstorm forbid (no unscoped membership scan, no `MIN(created_at)` first-membership lookup) is satisfied: the resolver takes an explicit `workspaceId` and does a single `eq("id", …)` read — no sibling discovery. GDPR gate (Phase 2.7) ran: no new processing activity (same credential, same purpose, narrower-than-RLS server context); no Art. 30 register change.

### Product (CPO)
**Status:** carry-forward from ADR-044 brainstorm
**Assessment:** Single-user-incident threshold inherited. The user-facing failure (broken autonomous dispatch / false sync-health alerts) is total product-value loss for the affected user; correctness of the cut-over is brand-survival. CPO sign-off required at plan time (frontmatter `requires_cpo_signoff: true`); `user-impact-reviewer` runs at review time.

### Product/UX Gate
**Tier:** none — no UI surface (no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit). Server-only change.

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-044** (`ADR-044-workspace-repo-ownership.md`): record the "service-role-safe installation-id resolver" capability gap as **closed** by `resolveInstallationIdForWorkspace` (direct service-role `workspaces` read), and the two inngest readers as cut over. Note webhook-route + session-sync remain in the #5470 umbrella. This is an in-scope task (Phase 6), not a follow-up issue.

### C4 views
- **Component** view (web-platform server): the Inngest agent-on-spawn + sync-health components' "reads installation credential" edge moves from `users` to `workspaces` (via the service-role resolver). Edit routes through `/soleur:architecture` (c4-edit flag, Concierge-only) — note for the implementer; lands in this feature's lifecycle.

### Sequencing
- The decision is true on merge (no soak gate — additive resolver, behavior-preserving cut-over). ADR amendment authored at status "adopted".

## Infrastructure (IaC)
None — pure application-code change against already-provisioned surfaces (Supabase, Inngest). No new server, secret, vendor, cron, or runtime process. No migration (the `workspaces.github_installation_id` column already exists from mig 079). Phase 2.8 trigger set: not fired.

## Observability

```yaml
liveness_signal:
  what: "Sentry cron monitor 'cron-workspace-sync-health' heartbeat (postSentryHeartbeat) — unchanged by this PR; agent-on-spawn surfaces via action_sends.failure_reason"
  cadence: "daily (cron 23 6 * * *) / per-spawn (agent-on-spawn)"
  alert_target: "Sentry issue + op-contract alert 'sentry-workspace-sync-health-alert' (existing)"
  configured_in: "apps/web-platform/server/inngest/functions/cron-workspace-sync-health.ts:305 (heartbeat); existing Sentry op-contract test test/sentry-workspace-sync-health-alert-op-contract.test.ts"
error_reporting:
  destination: "Sentry web-platform via reportSilentFallback (feature: resolve-installation-id-for-workspace, op: workspaces-read). NO dedicated sentry_issue_alert rule — issue-alerts.tf filters on feature tag and the new feature is intentionally alert-rule-less; the LOUD signal is the caller's path (agent-on-spawn → github_installation_unauthorized card; cron arm-1 already alerts on ready-but-NULL-install). reportSilentFallback ops are free-form (op-contract tests filter on feature, not op) — no op-registration step needed."
  fail_loud: "agent-on-spawn: null install → throws → action_sends.failure_reason='github_installation_unauthorized' (operator-visible card state). resolver db-error → Sentry capture (no dedicated alert rule by design — caller surfaces the user-facing failure)."
failure_modes:
  - mode: "workspaces.github_installation_id read fails (db error) in resolver"
    detection: "reportSilentFallback → Sentry issue (op: workspaces-read); not operator-eyeball"
    alert_route: "Sentry web-platform project (existing DSN)"
  - mode: "resolver returns null for a newly-connected user whose workspaces row is also NULL (genuine not-connected)"
    detection: "agent-on-spawn: github_installation_unauthorized failure_reason; cron arm-1 (scan-ready-null-installation, unchanged) already reports ready-but-NULL-install workspaces to Sentry"
    alert_route: "existing cron-workspace-sync-health Sentry signal + action_sends card state"
logs:
  where: "Inngest run logs (pino via run-log middleware) + Sentry"
  retention: "Sentry default retention; Inngest run history per substrate config"
discoverability_test:
  command: "cd apps/web-platform && npx vitest run test/server/inngest/resolve-installation-id-for-workspace.test.ts && git grep 'users.*github_installation_id' apps/web-platform/server/inngest/ | wc -l"
  expected_output: "vitest: all pass; grep wc -l: 0"
```

## Test Scenarios

1. **Resolver — newly-connected (NULL users, populated workspaces):** `resolveInstallationIdForWorkspace(ws, service)` where `workspaces.github_installation_id = 12345` → returns `12345`. (Core AC.)
2. **Resolver — not connected:** workspace row exists, `github_installation_id = NULL` → returns `null`.
3. **Resolver — no row:** unknown workspace id → returns `null`.
4. **Resolver — db error:** service mock returns `{error}` → returns `null` AND `reportSilentFallback` invoked once with `op: "workspaces-read"`.
5. **agent-on-spawn — newly-connected founder:** event `{founderId}`, `users.github_installation_id = NULL`, `workspaces` keyed `id=founderId` has install → `resolve-installation` step returns the install; dispatch proceeds (no `github_installation_unauthorized`).
6. **cron scan-stale-sync-failed — newly-connected user:** `users` row has `kb_sync_history` latest `ok:false` + NULL `github_installation_id`; `workspaces id=user.id` has install → arm resolves install (non-null) and reports the stale-sync finding (previously the `.not(... install ...)` predicate would have excluded the NULL-`users`-install row → false negative; new path catches it).
7. **cron scan-went-quiet — newly-connected user:** `users` row latest `ok:true` + old timestamp + NULL `github_installation_id`; `workspaces` has install + `repo_url` set on users → arm resolves install, probes GitHub HEAD, fires went-quiet when commits are newer.
8. **AC4 grep:** `git grep 'users.*github_installation_id' apps/web-platform/server/inngest/` → 0 lines (code + comments).

## Sharp Edges

- **AC4 grep matches comments.** Phase 0 showed the original grep hit was a *comment* line (`agent-on-spawn:16`). The two file header comment blocks describe reading `users.github_installation_id`; they MUST be rewritten or AC4 fails on a correct code change. Verify with the grep, not eyeballing the code diff.
- **`kb_sync_history` is users-only** (mig 017; ADR-044 did NOT mirror history). The cron arms cannot become workspaces-only reads — they keep the `users` read for history and resolve install per-row. A reviewer expecting "all `from('users')` gone" is wrong: the `from("users")` for `kb_sync_history` stays; only the `github_installation_id` select+predicate goes.
- **service_role retains the `workspaces` table grant** — the mig-079 column REVOKE hit `authenticated` only (079 §2 comment is explicit). The direct service-role read is correct and needs no new GRANT. Do not "fix" this by adding an RPC.
- **`.service-role-allowlist` is CODEOWNERS-gated** (@jeanderuelle). The new resolver file's allowlist line lands in the same PR as the import; CI's `service-role-allowlist-gate` rejects the import otherwise, but the CODEOWNERS approval is a merge gate — flag in the PR.
- **Per-row resolver call in the cron arms is N extra service-role reads** (one per ready+installed user). Acceptable: the population is small (internal dogfood + early users), the cron is daily, and each read is a single indexed `eq("id",…)`. If the population grows, a batched `.in("id", [...])` resolver is the optimization — note but do not pre-build (YAGNI).
- **A plan whose `## User-Brand Impact` section is empty, placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6.** This section is filled (threshold: single-user incident).
- **Behavior-preservation in the cron arms:** the old `.not("github_installation_id","is",null)` predicate skipped NULL-install rows at the DB; the new per-row `if (install === null) continue;` skips them in JS. These are equivalent for the *installed* set, but the new path also surfaces the newly-connected case (NULL `users` install, populated `workspaces`) that the old predicate would have *false-negatively excluded* — a strict improvement, captured in Test Scenario 6.
