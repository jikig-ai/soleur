# Tasks — Service-role-safe GitHub-App installation resolver (#5470)

Plan: `knowledge-base/project/plans/2026-06-17-feat-service-role-installation-resolver-plan.md`
Lane: cross-domain · Brand-survival threshold: single-user incident (CPO sign-off required at plan time)

## Phase 0 — Preconditions
- [ ] 0.1 `git grep -n 'github_installation_id' apps/web-platform/server/inngest/` — confirm current read sites match plan line refs (file may have drifted).
- [ ] 0.2 Confirm mig 079 §2 REVOKE is `FROM authenticated` only (service_role keeps table grant); confirm no later migration revokes workspaces from service_role.
- [ ] 0.3 Re-read `apps/web-platform/server/workspace-identity-resolver.ts` (~L70) — the resolver shape to mirror (injected `service`, `MaybeSingleChain<T>`, `.maybeSingle()`, NO `auth.getUser()`).
- [ ] 0.4 Re-run Open Code-Review Overlap query against live state (two-stage `gh --json` + standalone `jq --arg`).
- [ ] 0.5 Confirm commands: test `cd apps/web-platform && npx vitest run test/server/inngest/resolve-installation-id-for-workspace.test.ts`; typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 1 — RED (resolver unit tests)
- [ ] 1.1 Write `apps/web-platform/test/server/inngest/resolve-installation-id-for-workspace.test.ts` (mirror cron test's structural `serviceFrom` chain). Cases: (a) populated install → number; (b) row exists, NULL install → null; (c) no row → null; (d) db-error → null + asserts `reportSilentFallback` called with `op: "workspaces-read"`.
- [ ] 1.2 Confirm tests fail (module not created yet).

## Phase 2 — GREEN (resolver + allowlist)
- [ ] 2.1 Create `apps/web-platform/server/resolve-installation-id-for-workspace.ts` — `resolveInstallationIdForWorkspace(workspaceId: string, service: ServiceClient): Promise<number | null>`; reads `workspaces.github_installation_id`; on error → `reportSilentFallback({feature:"resolve-installation-id-for-workspace", op:"workspaces-read", extra:{workspaceId}})` + null. NO `auth.getUser()`.
- [ ] 2.2 Add `apps/web-platform/server/resolve-installation-id-for-workspace.ts` to `apps/web-platform/.service-role-allowlist` with a PERMANENT justification comment (service-role read of the workspaces credential column for Inngest/cron contexts; membership-bypass justified — server-derived ids only). NOTE: CODEOWNERS-gated (@jeanderuelle) — flag in PR.
- [ ] 2.3 Phase 1 tests green.

## Phase 3 — Cut agent-on-spawn
- [ ] 3.1 Edit `agent-on-spawn-requested.ts` `resolve-installation` step (L224-243): replace the `from("users").select("github_installation_id").eq("id", founderId)` read with `resolveInstallationIdForWorkspace(founderId, getServiceClient())`. Preserve throw-on-null → `github_installation_unauthorized`.
- [ ] 3.2 Rewrite the I1 comment block (L15-18) to cite `workspaces.github_installation_id` via the resolver (load-bearing for AC4 grep == 0).
- [ ] 3.3 Add/extend test: newly-connected founder (NULL `users`, populated `workspaces` keyed `id=founderId`) → install resolves; dispatch proceeds. (Service mock seeds `workspaces`, not `users`, for the install.)

## Phase 4 — Cut cron arms
- [ ] 4.1 `scan-stale-sync-failed` (L109-155): drop `github_installation_id` from the `users` select; drop `.not("github_installation_id","is",null)` predicate; per row add `const install = await resolveInstallationIdForWorkspace(r.id, service); if (install === null) continue;` before the `kb_sync_history` check. Keep `users` read for `id, kb_sync_history`.
- [ ] 4.2 `scan-went-quiet` (L186-301): drop `github_installation_id` from the `users` select; drop predicate; per row resolve `install`; replace `r.github_installation_id` at the L217 gate and the L251 `getDefaultBranchHeadCommitAt(...)` call with the resolved `install`. Keep `users` read for `id, repo_url, kb_sync_history`.
- [ ] 4.3 Rewrite the file header comment (L1-19) where it describes reading `users.github_installation_id` (load-bearing for AC4).
- [ ] 4.4 Leave arm-1 `scan-ready-null-installation` (L57-79) untouched — already reads `workspaces`.
- [ ] 4.5 Extend `cron-workspace-sync-health.test.ts`: newly-connected user (NULL `users`, populated `workspaces`) resolves install in BOTH arms; stale-sync fires on ok:false latest; went-quiet probes GitHub with resolved install.

## Phase 5 — Verify AC4 + typecheck + suite
- [ ] 5.1 `git grep 'users.*github_installation_id' apps/web-platform/server/inngest/` → **0** (code AND comments).
- [ ] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 5.3 `cd apps/web-platform && npx vitest run test/server/inngest/` green.

## Phase 6 — ADR amendment + C4
- [ ] 6.1 Amend `ADR-044-workspace-repo-ownership.md` "Considered Options (amendment)" / "Capability gap recorded": record the gap as CLOSED by `resolveInstallationIdForWorkspace` (direct service-role read); two inngest readers cut over; webhook-route + session-sync remain in #5470 umbrella.
- [ ] 6.2 C4 Component-view edge note (Inngest "reads installation credential" edge: users → workspaces) routed through `/soleur:architecture` (c4-edit flag, Concierge-only).

## Ship (post-merge)
- [ ] S.1 PR body uses `Ref #5437` (NOT `Closes`). CPO sign-off recorded.
- [ ] S.2 Post-merge: `gh issue comment 5437` noting precondition satisfied for the two inngest readers; remaining #5470 set = webhook-route reverse-lookup + session-sync write. (Automatable via `gh`; fold into `/soleur:ship`.)
