# Tasks — Stage 2.12 Real-SDK queryFactory Binding

**Plan:** `knowledge-base/project/plans/2026-04-27-feat-stage-2-12-real-sdk-query-factory-binding-plan.md`
**Issue:** #2884
**Branch:** `feat-one-shot-2884-stage-2-12-real-sdk-query-factory`

## Phase 1 — Setup & decision gates

- [x] 1.1 Confirm Bash usage in `/soleur:work` skill — Option A confirmed (Bash is required; synthetic AgentSession bridge via ccBashGates).
- [x] 1.2 File V2-13 issue — #2909 referenced in `cc-dispatcher.ts realSdkQueryFactory` body code comment.
- [x] 1.3 Verify SDK pin — `@anthropic-ai/claude-agent-sdk@0.2.85` (exact). No bump.
- [x] 1.4 Verify worktree git config: real author (`jean.deruelle@jikigai.com`).

## Phase 2 — RED (failing tests)

- [x] 2.1 Write `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` covering T1–T7 + T15–T17. Mock `@anthropic-ai/claude-agent-sdk`'s `query` and capture options.
- [x] 2.2 Write T8 (KeyInvalidError throws via iterator — runner mirrors).
- [x] 2.3 Write T9 (env shape — no SUPABASE_SERVICE_ROLE_KEY, no BYOK_ENCRYPTION_KEY).
- [x] 2.4 Write T10 (patchWorkspacePermissions runs once per cold factory call).
- [x] 2.5 Write T11 — covered by routing kind gate in ws-handler; flag-off path keeps factory unreachable (existing soleur-go-runner-flag-stickiness test continues to pass).
- [x] 2.6 Write T16 (sandbox-required-but-unavailable substring → `feature: "agent-sandbox"` Sentry tag; mock.calls filtered by feature).
- [x] 2.7 (Option A) Write `apps/web-platform/test/cc-dispatcher-bash-gate.test.ts` covering T12, T13, T14.
- [x] 2.8 Write T17 in `apps/web-platform/test/agent-runner-helpers.test.ts` — `buildAgentSandboxConfig(workspacePath)` deep-equal snapshot vs prior inline shape.
- [x] 2.9 Write T18, T19 in `cc-dispatcher.test.ts` (service-token allowlist + KeyInvalidError sanitization with errorCode propagation).
- [x] 2.10 Run vitest — RED confirmed pre-implementation; new tests now GREEN after Phase 3.

## Phase 3 — GREEN (implementation)

- [x] 3.1 Export `getUserApiKey` and `getUserServiceTokens` from `apps/web-platform/server/agent-runner.ts`. JSDoc warning added per R12.
- [x] 3.2 Extract `buildAgentSandboxConfig(workspacePath: string)` into `apps/web-platform/server/agent-runner-sandbox-config.ts`. `agent-runner.ts` updated to consume helper.
- [x] 3.3 All `agent-runner*` tests green — zero regression after extraction. T17 snapshot drift-guard green.
- [x] 3.4 Replace `realSdkQueryFactoryStub` body in `apps/web-platform/server/cc-dispatcher.ts` with the real factory closure. Use:
  - `cwd: workspacePath` (per-user from Supabase)
  - `model: "claude-sonnet-4-6"`
  - `settingSources: []`
  - `mcpServers: {}` (V1; reference V2-13 issue in code comment)
  - `plugins: [{ type: "local" as const, path: path.join(workspacePath, "plugins", "soleur") }]`
  - `sandbox: buildAgentSandboxConfig(workspacePath)`
  - `disallowedTools: ["WebSearch", "WebFetch"]` (and `["Bash", ...]` if Option C chosen)
  - `hooks: { PreToolUse: [...createSandboxHook(...)], SubagentStart: [...] }`
  - `env: buildAgentEnv(apiKey, serviceTokens)`
  - `canUseTool: createCanUseTool({ userId, conversationId, leaderId: "cc_router", workspacePath, platformToolNames: [], pluginMcpServerNames: [], repoOwner: "", repoName: "", session: syntheticSession, controllerSignal: controller.signal, deps: {...} })`
  - `includePartialMessages: true`
  - resume key: `resume: resumeSessionId` (from QueryFactoryArgs)
- [x] 3.5 `patchWorkspacePermissions(workspacePath)` fires once per cold factory call (inside `ensureInner` IIFE).
- [x] 3.6 (Option A) `_ccBashGates: Map<string, CcBashGateRecord>` keyed by `${userId}:${conversationId}:${gateId}` (R8). `registerCcBashGate` + `resolveCcBashGate` exported.
- [x] 3.7 (Option A) `ws-handler.ts review_gate_response` handler dispatches by routing kind — `soleur_go_*` → `resolveCcBashGate` first, fall through to `resolveReviewGate`.
- [x] 3.8 Sentry tagging in factory closure: `sandbox required but unavailable` substring → `feature: "agent-sandbox", op: "sdk-startup"` (mirrors `agent-runner.ts` precedent).
- [x] 3.9 `dispatchSoleurGo` catch detects `KeyInvalidError` → surfaces `errorCode: "key_invalid"` to client (R10 / T19).
- [x] 3.10 `allow(toolInput)` helper used by `permission-callback.ts createCanUseTool` (consumed unchanged by the cc factory; no new bare `{behavior: "allow"}` returns introduced).
- [x] 3.11 `cleanupCcBashGatesForConversation` exported and invoked from `dispatchSoleurGo`'s `onWorkflowEnded` + dispatch catch path. Aborts the synthetic AgentSession `controller` so awaiting resolvers reject cleanly.

## Phase 4 — Verification

- [x] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` — 2598 tests pass, 11 skipped.
- [x] 4.2 `cd apps/web-platform && npx tsc --noEmit` — zero errors.
- [ ] 4.3 Lint: `bun run lint` (root) — `next lint` deprecated; not run (interactive prompt). tsc + vitest cover the gap.
- [x] 4.4 `grep -rn "realSdkQueryFactoryStub" apps/web-platform/server/` returns ZERO hits.
- [x] 4.5 `grep -rn '_stubMirroredOnce' apps/web-platform/server/` returns ZERO hits.
- [x] 4.6 `grep -n 'feature: "agent-sandbox"' apps/web-platform/server/cc-dispatcher.ts` returns line 463 (AC7).
- [x] 4.7 `grep -n 'leaderId: "cc_router"' apps/web-platform/server/cc-dispatcher.ts` returns 4 hits incl. line 442 (createCanUseTool ctx) and line 468 (Sentry extra) (AC14).
- [x] 4.8 V2-13 issue number `#2909` referenced in `cc-dispatcher.ts` lines 246 + 401 (AC10).
- [x] 4.9 `git log --pretty='%ae' main..HEAD` shows only `jean.deruelle@jikigai.com` (no fake authors).

## Phase 5 — Compound + Ship

- [ ] 5.1 Run `skill: soleur:compound` to capture any session learnings (per `wg-before-every-commit-run-compound-skill`).
- [ ] 5.2 Commit + push: `git add` only the modified files; commit message format per repo convention; push to remote.
- [ ] 5.3 Run `skill: soleur:review` (multi-agent review per `rf-never-skip-qa-review-before-merging` and learning `2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md`). Spawn at least: security-sentinel, architecture-strategist, performance-oracle, data-integrity-guardian.
- [ ] 5.4 Address review findings per `rf-review-finding-default-fix-inline`. Scope-out only with justification.
- [ ] 5.5 Run `skill: soleur:ship` — set semver labels, mark PR ready, queue auto-merge.
- [ ] 5.6 Poll PR until MERGED per `wg-after-marking-a-pr-ready-run-gh-pr-merge`.

## Phase 6 — Post-merge operator actions

- [ ] 6.1 PM1: Confirm `FLAG_CC_SOLEUR_GO=true` in Doppler `dev`. If not: `doppler secrets set FLAG_CC_SOLEUR_GO=true -p soleur -c dev`.
- [ ] 6.2 PM2: Restart `apps/web-platform` container in `dev`.
- [ ] 6.3 PM3: Send a Command Center message that triggers `/soleur:go`. Confirm WS streams include `stream` events from the SDK (not just `error`).
- [ ] 6.4 PM4: Sentry filter `feature:"soleur-go-runner" op:"queryFactory"` shows zero events for ~30 min after smoke. `feature:"agent-sandbox"` also zero.
- [ ] 6.5 PM5: Notify Stage 4 / Stage 6 maintainers that the binding is live; they can proceed with UI testing + smoke.
- [ ] 6.6 PM6: Capture a 2026-04-XX-stage-2-12-real-sdk-binding learning if the smoke uncovered surprises.

## Dependencies

- Phase 1.1 → Phase 1.2 → Phase 2 (decision affects test scope)
- Phase 2 → Phase 3 (RED before GREEN per `cq-write-failing-tests-before`)
- Phase 3.1, 3.2 must precede 3.4 (factory uses the new exports + helper)
- Phase 3.6, 3.7 are Option A-only; skip if Option C chosen
- Phase 4 → Phase 5 (verify before commit)
- Phase 5 → Phase 6 (post-merge operator actions only after MERGED)
