# Tasks — Stage 2.12 Real-SDK queryFactory Binding

**Plan:** `knowledge-base/project/plans/2026-04-27-feat-stage-2-12-real-sdk-query-factory-binding-plan.md`
**Issue:** #2884
**Branch:** `feat-one-shot-2884-stage-2-12-real-sdk-query-factory`

## Phase 1 — Setup & decision gates

- [ ] 1.1 Confirm Bash usage in `/soleur:work` skill: `grep -rn "Bash\|child_process\|spawn\|exec" plugins/soleur/skills/work/SKILL.md`. Decide Option A vs Option C.
- [ ] 1.2 File V2-13 issue: `gh issue create --title "V2-13: Tier-classify in-process MCP servers for cc-soleur-go path" --milestone "Post-MVP / Later"`. Capture issue number for AC10.
- [ ] 1.3 Verify SDK pin: `grep '"@anthropic-ai/claude-agent-sdk"' apps/web-platform/package.json` returns `"0.2.85"` (exact). No bump.
- [ ] 1.4 Verify worktree git config: author identity is real (per `hr-never-fake-git-author`). `git config user.email` does NOT match `test@test`.

## Phase 2 — RED (failing tests)

- [ ] 2.1 Write `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` covering T1–T7 + T15–T17. Mock `@anthropic-ai/claude-agent-sdk`'s `query` and capture options.
- [ ] 2.2 Write T8 (KeyInvalidError throws → reportSilentFallback fires with `op: "queryFactory"`).
- [ ] 2.3 Write T9 (env shape — no SUPABASE_SERVICE_ROLE_KEY, no BYOK_ENCRYPTION_KEY, no Stripe).
- [ ] 2.4 Write T10 (patchWorkspacePermissions runs once per cold factory call).
- [ ] 2.5 Write T11 (FLAG_CC_SOLEUR_GO=false keeps factory cold).
- [ ] 2.6 Write T16 (sandbox-required-but-unavailable substring → `feature: "agent-sandbox"` Sentry tag; mock.calls filtered by feature).
- [ ] 2.7 (Option A only) Write `apps/web-platform/test/cc-dispatcher-bash-gate.test.ts` covering T12 (synthetic AgentSession Bash flow), T13 (cleanup on close/reap), T14 (BLOCKED_BASH_PATTERNS deny).
- [ ] 2.8 Write T17 in `apps/web-platform/test/agent-runner-helpers.test.ts` — `buildAgentSandboxConfig(workspacePath)` snapshot deep-equal against the prior inline shape.
- [ ] 2.9 Write T18, T19 in `cc-dispatcher.test.ts` (service-token allowlist, error sanitization).
- [ ] 2.10 Run vitest — all new tests RED. `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-dispatcher` must show failures only in the new tests.

## Phase 3 — GREEN (implementation)

- [ ] 3.1 Export `getUserApiKey` and `getUserServiceTokens` from `apps/web-platform/server/agent-runner.ts`. Add JSDoc warning per R12.
- [ ] 3.2 Extract `buildAgentSandboxConfig(workspacePath: string)` from `agent-runner.ts:807-829` into a new sibling module (e.g., `agent-runner-sandbox-config.ts`). Update `agent-runner.ts` to consume the helper.
- [ ] 3.3 Run all `apps/web-platform/test/agent-runner*` tests — must remain green (zero regression after extract). Snapshot test T17 must turn green.
- [ ] 3.4 Replace `realSdkQueryFactoryStub` body in `apps/web-platform/server/cc-dispatcher.ts` with the real factory closure. Use:
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
- [ ] 3.5 Wire `patchWorkspacePermissions(workspacePath)` to fire once per cold factory call.
- [ ] 3.6 (Option A only) Add `ccBashGates: Map<string, AgentSession>` exported from `cc-dispatcher.ts`. Synthetic session keyed by `${userId}:${conversationId}:${gateId}` per R8. Wire `resolveCcBashGate(userId, conversationId, gateId, selection)` for ws-handler dispatch.
- [ ] 3.7 (Option A only) Update `apps/web-platform/server/ws-handler.ts` `review_gate_response` handler to dispatch by routing kind: `soleur_go_*` → `resolveCcBashGate`; legacy → existing `resolveReviewGate`.
- [ ] 3.8 Add Sentry tagging in factory closure: stderr-substring match for `sandbox required but unavailable` → `reportSilentFallback({feature: "agent-sandbox", op: "sdk-startup"})` per `agent-runner.ts:1136-1141` precedent.
- [ ] 3.9 Extend `dispatchSoleurGo` catch in `cc-dispatcher.ts:256-266` to detect `KeyInvalidError` and surface `errorCode: "key_invalid"` to the client (R10).
- [ ] 3.10 Use `allow(toolInput)` helper from `permission-callback.ts:53` for ALL allow branches in any new `canUseTool` code (AC13).
- [ ] 3.11 Add cleanup hook on `closeConversation`/`reapIdle` to drain `ccBashGates` entries for the conversation.

## Phase 4 — Verification

- [ ] 4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` — full suite green.
- [ ] 4.2 `cd apps/web-platform && npx tsc --noEmit` — zero new errors.
- [ ] 4.3 Lint: `bun run lint` (root) — green.
- [ ] 4.4 Grep verification: `grep -rn "realSdkQueryFactoryStub" apps/web-platform/server/` returns ZERO hits.
- [ ] 4.5 Grep verification: `grep -rn '_stubMirroredOnce' apps/web-platform/server/` returns ZERO hits.
- [ ] 4.6 Grep verification: `grep -n 'feature: "agent-sandbox"' apps/web-platform/server/cc-dispatcher.ts` returns at least one hit (AC7).
- [ ] 4.7 Grep verification: `grep -n 'leaderId: "cc_router"' apps/web-platform/server/cc-dispatcher.ts` returns at least one hit (AC14).
- [ ] 4.8 Grep verification: code comment references V2-13 issue number in `cc-dispatcher.ts` (AC10).
- [ ] 4.9 Grep verification: no fake-author commits — `git log --pretty='%ae' main..HEAD` shows real authors only.

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
