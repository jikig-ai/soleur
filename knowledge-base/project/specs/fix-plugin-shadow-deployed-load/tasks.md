# Tasks — connected-repo plugin shadows the deployed platform plugin

Derived from `knowledge-base/project/plans/2026-07-06-fix-connected-repo-plugin-shadows-deployed-platform-plugin-plan.md`.
lane: cross-domain · brand_survival_threshold: single-user incident · requires_cpo_signoff · security_review: required

> **Sequencing decision pending (S1 split vs S2 bundle).** Slice A = security core (Phase 1 + F3), Slice B =
> delivery (Phase 2 + 3). If S1, Slice A ships first; Slice B follows after F1/F2 on-host verification.

## Phase 0 — Preconditions (/work)
- [ ] 0.1 Read `views.c4` + `spec.c4` (only `model.c4` read at plan time); confirm the trust-boundary element/edit renders.
- [ ] 0.2 Confirm which factory the operator's Concierge surface runs (cc-dispatcher vs `startAgentSession`) — fix both regardless.
- [ ] 0.3 Verify on-host: hardcoded bwrap probe (`ci-deploy.sh:1281`) is green on the target host BEFORE any cutover.
- [ ] 0.4 CPO sign-off (single-user-incident threshold).
- [ ] 0.5 Open Code-Review Overlap grep against Files-to-Edit; record dispositions.

## Slice A — Security core (Phase 1 + F3)
- [ ] A1 `cc-dispatcher.ts:2387` → `getPluginPath()` (+ import). RED test first (T3 flip).
- [ ] A2 `agent-runner.ts:1109` (legacy `startAgentSession`) → `getPluginPath()` (the factory #6115 missed).
- [ ] A3 **F3:** `context-queries-hook.ts:161` `skillsDir` → `getPluginPath()`; keep `knowledge-base/` workspace-rooted.
- [ ] A4 Loaded-gun guard: consumers assert `path.isAbsolute(p) && p.startsWith("/app/")`.
- [ ] A5 Tests: `cc-dispatcher-real-factory.test.ts` T3, `agent-runner-query-options.test.ts`, `agent-runner-helpers.test.ts`, `mu1-integration.test.ts` (symlink expectations still valid). AC1 broad grep = 0 residual workspace-relative readers.
- [ ] A6 hooks.json closure verified (SDK sets `${CLAUDE_PLUGIN_ROOT}` for command-hook expansion to the loaded=deployed root).

## Slice B — Delivery / #4826 wedge (Phase 2 + 3) [after F1/F2 resolved on-host]
- [ ] B1 `agent-env.ts` `BuildAgentEnvOptions.pluginPath` → `CLAUDE_PLUGIN_ROOT` injection (canary-neutral).
- [ ] B2 `agent-runner-query-options.ts:206` thread `pluginPath`.
- [ ] B3 **F2:** in-image test — `CLAUDE_PLUGIN_ROOT` reaches the sandboxed Bash env; server fails CLOSED if unset (no silent `./plugins/…` fallback).
- [ ] B4 **F1:** `safe-bash.ts` exact-literal carve-out (NOT a `$`-regex extension); remove `./plugins/…` server auto-approve of the untrusted copy. Unit-test allow/deny matrix. Route through security-sentinel.
- [ ] B5 Migrate wedge-flow invocations only: `go.md:24,41`, `one-shot:47,65`, `work:43,85,163`. Defer other families → follow-up issue.
- [ ] B6 Phase 6 (optional, 1-line): non-silent collision warn in `scaffoldWorkspaceDefaults` (`workspace.ts:433-444`).

## Cross-cutting
- [ ] C1 ADR-0NN (trust boundary: SDK plugin/hook source = deployed root). Provisional ordinal; re-verify at ship.
- [ ] C2 C4: add untrusted connected-repo-plugin-source element + boundary note (mirror `contributor` precedent); annotate `claude -> skillloader "Loads plugin"`. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] C3 Observability: reduced Phase 5 (verifyPluginMountOnce + `connectedRepoShipsPlugin` breadcrumb; no dead-branch source probe).
- [ ] C4 Learning file already re-captured (enhanced): `knowledge-base/project/learnings/bug-fixes/2026-07-06-connected-repo-shadows-deployed-plugin-via-workspace-relative-path.md`.
- [ ] C5 Follow-up issue: broader `${CLAUDE_PLUGIN_ROOT}` migration (ship/brainstorm/merge-pr/drain-prs/fix-issue/git-worktree examples + archive-kb/deploy/pencil-setup/feature-video/community families).
- [ ] C6 `tsc --noEmit` clean (`cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`); full suite green (vitest, NOT `npm run -w`).

## Post-merge (operator)
- [ ] P1 Read `/hooks/deploy-status` reason == `ok`; if `canary_sandbox_failed`, triage as HOST bwrap/userns (NOT the plugin path — do not revert).
- [ ] P2 Sentry: deploy SHA advanced + zero plugin-mount fallbacks on the operator's container.
- [ ] P3 `gh issue close` the tracker after P1+P2 (PR body uses `Ref #N`, not `Closes`).
