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
- [x] A1 `cc-dispatcher.ts:2387` → `getPluginPath()` (+ import). T3 flipped. **DONE — commit 18db92d5c** (349 tests green, tsc clean).
- [x] A2 `agent-runner.ts:1109` (legacy `startAgentSession`) → `getPluginPath()` (the factory #6115 missed). **DONE — same commit.**
- [x] A3 **F3:** `context-queries-hook.ts:161` `skillsDir` → `getPluginPath()`; keep `knowledge-base/` workspace-rooted. **DONE.** Shared helper `test/helpers/context-queries-fixture.ts` gained `fixturePluginPath(root)`; both `context-queries-hook.test.ts` + `context-queries-shell-parity.test.ts` stub `SOLEUR_PLUGIN_PATH` at each construction site. Added the discriminating `F3: SKILL.md loads from the deployed plugin root` shadow-closed test (deployed declares `safe.md`, workspace shadow declares `evil.md` — mutation-verified non-vacuous).
- [x] A4 Loaded-gun guard: **DONE.** `assertTrustedPluginPath(p)` in `plugin-path.ts` (test-tolerant, reuses the `/app/` allowlist), wired at the `plugins:[{path}]` chokepoint (`agent-runner-query-options.ts:231`). `test/plugin-path.test.ts` covers the production throw + AC12b/F4 non-regression.
- [x] A5 Tests: `cc-dispatcher-real-factory.test.ts` T3, `agent-runner-query-options.test.ts` green; AC1 broad grep = **0** residual workspace-relative Concierge-path readers.
- [x] A6 hooks.json closure verified: both factories load `plugins:[{path: getPluginPath()}]`, so the SDK resolves `hooks/hooks.json` command-hooks against the DEPLOYED root — the untrusted workspace `hooks/*.sh` never execute in-process.

## Slice B — Delivery / #4826 wedge (Phase 2 + 3) [after F1/F2 resolved on-host]
- [ ] B1 `agent-env.ts` `BuildAgentEnvOptions.pluginPath` → `CLAUDE_PLUGIN_ROOT` injection (canary-neutral).
- [ ] B2 `agent-runner-query-options.ts:206` thread `pluginPath`.
- [ ] B3 **F2:** in-image test — `CLAUDE_PLUGIN_ROOT` reaches the sandboxed Bash env; server fails CLOSED if unset (no silent `./plugins/…` fallback).
- [ ] B4 **F1:** `safe-bash.ts` exact-literal carve-out (NOT a `$`-regex extension); remove `./plugins/…` server auto-approve of the untrusted copy. Unit-test allow/deny matrix. Route through security-sentinel.
- [ ] B5 Migrate wedge-flow invocations only: `go.md:24,41`, `one-shot:47,65`, `work:43,85,163`. Defer other families → follow-up issue.
- [ ] B6 Phase 6 (optional, 1-line): non-silent collision warn in `scaffoldWorkspaceDefaults` (`workspace.ts:433-444`).

## Cross-cutting
- [x] C1 **ADR-093** created (`accepted`): SDK plugin/hook/skill source = platform-deployed root, never connected-repo workspace copy. Ordinal verified next-free vs origin/main; `ADR-0NN` placeholders swept in plan + model.c4.
- [x] C2 C4: **DONE.** Added `connectedRepoPlugin` untrusted `#external` element + trust-boundary comment (mirrors `contributor`); annotated `claude -> skillloader "Loads plugin from the PLATFORM-DEPLOYED root"`; added the `connectedRepoPlugin -> skillloader "IGNORED (trust boundary)"` edge; included it in the `containers` view. `c4-code-syntax.test.ts` + `c4-render.test.ts` green (23 passed).
- [x] C3 Observability: **DONE (reduced Phase 5 + folds in Phase-6/B6 collision warn).** `scaffoldWorkspaceDefaults` emits a `connectedRepoShipsPlugin` diagnostic breadcrumb when a connected repo ships a committed `plugins/soleur/` dir (existing-logger channel; no new pipeline). No dead-branch per-dispatch `source` probe. 2 new tests.
- [x] C4 Learning file re-captured + enhanced (canary reconciliation, two-factory correction, F3/loaded-gun, reduced observability): `knowledge-base/project/learnings/bug-fixes/2026-07-06-connected-repo-shadows-deployed-plugin-via-workspace-relative-path.md`.
- [x] C5 Follow-up issue **#6121** filed (consolidated: Slice B Phase 2+3 + broader `${CLAUDE_PLUGIN_ROOT}` migration). `type/security` + `deferred-scope-out`, milestone Phase 4. Net-flow +1 (justified — larger on-host-gated work-stream).
- [x] C6 `tsc --noEmit` clean; full web-platform vitest suite green: **11997 passed / 0 failed** (256 skipped, 967 files), VITEST_RC=0.

## Post-merge (operator)
- [ ] P1 Read `/hooks/deploy-status` reason == `ok`; if `canary_sandbox_failed`, triage as HOST bwrap/userns (NOT the plugin path — do not revert).
- [ ] P2 Sentry: deploy SHA advanced + zero plugin-mount fallbacks on the operator's container.
- [ ] P3 `gh issue close` the tracker after P1+P2 (PR body uses `Ref #N`, not `Closes`).
