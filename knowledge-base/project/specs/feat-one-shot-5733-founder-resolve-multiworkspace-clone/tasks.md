---
title: "Tasks — agent-readiness absent-.git strand heal/block + observable backstop + per-workspace ready-clone (Ref #5733)"
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-30-fix-agent-readiness-absent-git-strand-and-per-workspace-clone-plan.md
issue: 5733
---

# Tasks — Ref #5733 (D0 in-process re-clone + absent-.git strand heal/block + observability)

Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
Tests: `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` (NOT bun test)
PR body: `Ref #5733` (NOT Closes — soak-gated).

## Phase 0 — Preconditions
- [ ] 0.1 Confirm new test paths sit under `apps/web-platform/test/` (vitest `include:` glob).
- [ ] 0.2 Baseline `tsc --noEmit` green.
- [ ] 0.3 Read all three `.c4` files; confirm no-C4-impact citing actors/systems/relationships checked.
- [ ] 0.4 Read precedents: `ensure-workspace-repo.ts:148-356`, `session-sync.ts` cred helper, `resolve_workspace_installation_id` RPC (member vs owner scope). FS-divergence Phase-0 verdict (single vs multi-replica /workspaces) — record, don't block.

## Phase 1 — Deliverable D0 (PRIMARY — in-process dispatch-time re-clone) — TDD
- [ ] 1.1 RED: `test/dispatch-inprocess-reclone.test.ts` — absent .git + connected workspace → clone runs into `workspacePath` keyed on the WORKSPACE'S OWN install (not membership-resolved user install); member-null user install still clones; `repo_status='ready'` does NOT short-circuit; clone FAILURE → distinct `repo_clone_failed` (sanitized, token never present) + `repo_error` write + RepoNotReadyError; non-UUID activeWorkspaceId rejected (id-shape guard).
- [ ] 1.2 GREEN: `cc-dispatcher.ts` cold path — in-process guaranteed re-clone before `query()`; resolve install from workspace's own column when user/membership null; reuse `ensureWorkspaceRepoCloned` hardened clone (GIT_ASKPASS token, `--`-guard, github-https allowlist).
- [ ] 1.3 GREEN: `ensure-workspace-repo.ts` — workspace-own-install fallback (no benign-skip for a CONNECTED workspace) + distinct `repo_clone_failed` loud emit; `repo-resolver-divergence.ts` (or sibling) — add the `repo_clone_failed` reporter (sanitized, ADR-029).
- [ ] 1.4 GREEN: `cc-reprovision.ts` (warm) + `repo-readiness-self-heal.ts` (`graftReadyButGitAbsent`) — same workspace-own-install fallback so warm-turn member dispatch lands the repo.
- [ ] 1.5 Verify `cc-dispatcher*` / `cc-reprovision*` / `repo-readiness*` suites green.

## Phase 2 — Deliverable D3 (C2 detector empty-output) — TDD
- [ ] 1.1 RED: `test/in-sandbox-revparse-strand.test.ts` — empty output → strand; `"false\ntrue"` → not strand; `"true\nfalse"` → not strand; keep `fatal:`/`not a git repository`/`false` green.
- [ ] 1.2 GREEN: `server/tool-labels.ts:35-46` — work-tree probe with no standalone `true` token → strand; keep `isWorkTreeProbe` command guard.
- [ ] 1.3 Verify `test/tool-labels.test.ts` + `test/cc-dispatcher-self-heal-observability.test.ts` still green.

## Phase 3 — Deliverable D2 (absent/dir-invalid → emit + block, FALLBACK) — TDD
- [ ] 2.1 RED: `test/agent-readiness-absent-git.test.ts` — absent + dir-invalid → `"block"` + `reportAgentReadinessSelfStop({gitKind, gitRevParseValid:false, source:"host-pre-heal"})`; dir-valid+worktree → ready; inconclusive×2 → ready.
- [ ] 2.2 GREEN: `server/git-worktree-validity.ts:401-433` — shape-aware routing; absent/dir-invalid → emit + block; preserve `!connected||!dbReady` and file-pointer behaviour. Add `phase: "post-heal"|"pre-heal"` to `AgentReadinessContext`; emit the absent self-stop ONLY on `post-heal` (terminal). Reconcile passes `pre-heal` → no false-positive emit (architecture P1).
- [ ] 2.2b Thread `phase` at call sites: `cc-dispatcher.ts:2010` = post-heal; `workspace-reconcile-on-push.ts:372` = pre-heal; `cc-reprovision.ts:145` = post-heal.
- [ ] 2.3 Cold-absent emits + RepoNotReadyError (no spawn); reconcile-absent does NOT emit (heals via `!isReadyGitWorkTree`); warm-absent routes to heal (never reaches gate). 3 call-site assertions.

## Phase 4 — Deliverable D1 (founder/membership-INDEPENDENT clone) — TEST-ONLY
- [ ] 4.1 RED: `test/ready-clone-per-workspace.test.ts` — (a) two workspaces, one installation, distinct repo_urls → each clones independently; (b) founder-independence: canary-drifted owner rows + member dispatcher still clones from the workspace's own install column. Real workspace-id resolution (not all-stubbed).

## Phase 5 — Docs + gates
- [ ] 5.1 Amend ADR-044 dispatch-readiness consequence (§line 552): D0 in-process re-clone from workspace's own install + absent/dir-invalid gate + empty-output backstop.
- [ ] 5.2 Add `scripts/followthroughs/agent-readiness-absent-strand-observable-5733.sh` (Sentry-rate soak; mirror reconcile-ff-only-sentry-4977.sh) + tracker directive on #5733. KEEP existing operator-confirm `concierge-strand-754ee124-5733.sh`.
- [ ] 5.3 `tsc --noEmit` green; Phase-5 vitest suite list green (incl. dispatch-inprocess-reclone, cc-dispatcher*, repo-readiness*, cc-reprovision*, workspace-reconcile* orphan suites).
- [ ] 5.4 Open Code-Review Overlap check (gh issue list --label code-review, two-stage jq) — include cc-dispatcher.ts / ensure-workspace-repo.ts.

## Exit
- [ ] PR with `Ref #5733`; `## Acceptance Criteria` split Pre-merge / Post-merge; CPO sign-off recorded (single-user-incident threshold).
