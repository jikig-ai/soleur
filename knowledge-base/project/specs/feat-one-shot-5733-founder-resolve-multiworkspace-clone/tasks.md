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

## Phase 1 — Deliverable D0 (consume the EXISTING in-process clone outcome — loud + F4-safe) — TDD
NO new clone site; NO service-role column read (architecture P0 — phantom premise + posture regression).
- [ ] 1.1 RED: `test/dispatch-inprocess-reclone.test.ts` — clone FAILURE → `repo_clone_failed` event (exception value has NO token AND NO `/workspaces/<uuid>` path; `extra` excludes repoUrl/install, pre-hashes ws id) + RepoNotReadyError (no spawn). F4: member-path (ws!==user) → emit-only NO set_repo_status; solo/owner (ws===user) + `.git` still absent → error write. CAS: `.git` present after attempt → no error write. No duplicate clone call (grep).
- [ ] 1.2 GREEN: `cc-dispatcher.ts:1987` — capture the discarded outcome; on "failed" emit `repo_clone_failed` (reason via `sanitizeGitStderr`) + F4-gated+CAS `repo_error`/error write + honest-block. Build path via existing `workspacePathForWorkspaceId` UUID guard. NO service-role read.
- [ ] 1.3 GREEN: add `repo_clone_failed` reporter to `repo-resolver-divergence.ts` (sanitized, `hashUserId`, ADR-029); wire into `ensure-workspace-repo.ts:271-285` `op:clone` catch so every caller emits.
- [ ] 1.4 GREEN: `repo-readiness-self-heal.ts` — gate `graftReadyButGitAbsent`→`failHonestly`'s `set_repo_status(error)` on solo/owner + CAS (fix pre-existing F4 inconsistency).
- [ ] 1.5 Phase-0 gate: confirm `effectiveInstallationId` is non-null for the 754ee124 member dispatch (RPC any-role); if the clone succeeds but `.git` absent at agent read path → STOP, fix path/mount divergence (real bug). Verify `cc-dispatcher*`/`repo-readiness*`/`cc-reprovision*` suites green.

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
