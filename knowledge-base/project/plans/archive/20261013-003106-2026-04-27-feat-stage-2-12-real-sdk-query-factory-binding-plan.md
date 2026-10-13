# Stage 2.12 Real-SDK queryFactory Binding (#2884)

**Type:** feature (follow-through)
**Issue:** #2884
**Source PR:** #2858 (Stage 1 + Stage 2 merged 2026-04-24)
**Source plan:** `knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md`
**Branch:** `feat-one-shot-2884-stage-2-12-real-sdk-query-factory`
**Worktree:** `.worktrees/feat-one-shot-2884-stage-2-12-real-sdk-query-factory`

## Enhancement Summary

**Deepened on:** 2026-04-27
**Sections enhanced:** 6 (Open Design Question, Files to Edit, Risks, Acceptance Criteria, Test Scenarios, Research Insights)

### Key Improvements

1. **SDK pin verified.** `apps/web-platform/package.json` pins `@anthropic-ai/claude-agent-sdk@0.2.85` (exact). Plan now leverages the post-0.2.81 `canUseTool` fix and post-0.2.85 PreToolUse `permissionDecision: "ask"` fix. **No SDK bump required.**
2. **`bash_approval` already exists end-to-end.** `cc-interactive-prompt-types.ts:37` defines the `bash_approval` kind with `response: "approve" | "deny"`. `soleur-go-runner.ts:186` already classifies Bash as `bash_approval` and emits via `bridgeInteractivePromptIfApplicable`. The infrastructure for **Option B is mostly built** — but it currently sits AFTER `canUseTool` allow (the SDK has already permitted). The interactive_prompt is a UX surface, not a gate. This changes the design choice — see updated Open Design Question.
3. **`canUseTool` and interactive_prompt are at different layers.** `canUseTool` is the SDK's step-5 sync permission callback (returns allow/deny BEFORE the tool runs). `bridgeInteractivePromptIfApplicable` fires from `consumeStream` AFTER `tool_use` content blocks arrive — meaning the tool has already been permitted. **Implication:** keeping the existing Bash review-gate logic in `permission-callback.ts` (which uses `AgentSession.reviewGateResolvers`) is required for actual gating. The interactive_prompt UX is supplemental, not load-bearing.
4. **Synthetic `AgentSession` is the minimum-viable path** (Option A confirmed). Option B's full integration would require extending `PendingPromptRegistry` with a separate `canUseTool`-gating channel — large refactor, defer to V2.
5. **Sentry tagging follows the `agent-sandbox` precedent.** `agent-runner.ts:1136-1141` already mirrors `sandbox required but unavailable` stderr substring matches via `reportSilentFallback({feature:"agent-sandbox", op:"sdk-startup"})`. The cc-soleur-go path must mirror this precedent — add the same substring check around the factory's `query()` call.
6. **`leaderId: "cc_router"` already exists** as a non-routable internal leader (`agent-runner.ts:1209` reference + `domain-leaders.ts`) — the cc-soleur-go factory should pass `leaderId: "cc_router"` (not `undefined`) to `createCanUseTool` so audit logs and any future leader-scoped behavior stays attributable.

### New Considerations Discovered

- **V2-13 issue does NOT exist.** `gh issue list --search "V2-13" --state all` returns empty. AC must include filing it before merging this PR (per `wg-when-deferring-a-capability-create-a`).
- **`patchWorkspacePermissions` mutates the user's workspace** every call. Idempotent but cumulative — verify the cc-soleur-go path doesn't multiply this across cold-start re-dispatches (it shouldn't because `createSoleurGoRunner` runs queryFactory ONCE per cold conversation; reused dispatches skip).
- **Sandbox config helper extraction risk class is documented.** Per learning `2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md`, helper-extraction snapshot tests must filter `mock.calls` by feature tag because module-init can fire `feature: "kb-share"` from a sibling code path. Test design must mirror this.
- **`canUseTool` allow-shape schema is verified at v0.2.85.** Per learning `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`, the `allow(toolInput)` helper exists at `permission-callback.ts:53` and unconditionally echoes `updatedInput`. New factory MUST use this helper, not bare `{behavior: "allow"}`.

## Overview

Replace the `realSdkQueryFactoryStub` in `apps/web-platform/server/cc-dispatcher.ts`
with a real `query()` from `@anthropic-ai/claude-agent-sdk`. After this binding lands,
the cc-soleur-go path actually invokes the SDK end-to-end (still gated behind
`FLAG_CC_SOLEUR_GO=0` in prod) and unlocks Stage 4 UI testing + Stage 6 smoke tests
in `dev` (`FLAG_CC_SOLEUR_GO=true`).

The work is mostly **glue + per-call data fetching**: the per-user workspace, BYOK
key, service tokens, plugin path, sandbox config, and `canUseTool` already exist in
`agent-runner.ts`. We need to expose / lift the user-data fetchers so a closure
inside `cc-dispatcher.ts` can build a `QueryFactory` that calls `query(...)` with
the same shape `agent-runner.ts:778-877` uses, minus the parts that don't apply
(no `mcpServers` for V1, no `pluginMcpServerNames` allowlist for V1, no
review-gate `AskUserQuestion` path because the runner has its own
interactive_prompt bridge).

## Research Reconciliation — Spec vs. Codebase

| Spec (issue body / source plan) | Codebase reality | Plan response |
|---|---|---|
| Issue: `cwd: workspacePath` (per-user) | `agent-runner.ts:445` reads `workspacePath` from `users.workspace_path` per session start; the same fetch must run inside the new factory | Lift `getUserWorkspaceData()` helper or duplicate inline; favour exporting the existing query from `agent-runner.ts` for grep-stable single source. |
| Issue: `mcpServers: {}` (empty — V2-13 tracks expansion) | `agent-runner.ts:765-772` registers `soleur_platform` in-process MCP server (kb_share + conversations + github + plausible). Source plan §Stage 2.17 prescribes "start with empty set". | Keep MCP allowlist EMPTY for V1 per issue. File V2 issue (already exists per source plan §Stage 2 V2 backlog — verify `V2-13` exists and re-link). Open question: do agents lose `kb_share_*` in cc-soleur-go path? Yes, by design — the runner is a router that delegates to `/soleur:go`, which dispatches to skills that own their own tooling. |
| Issue: `plugins: [{ type: "local", path: pluginPath }]` | `agent-runner.ts:830` uses `path.join(workspacePath, "plugins", "soleur")` (per-user workspace plugin copy). NOT `process.env.SOLEUR_PLUGIN_PATH` (which is unused outside `PLUGIN_PATH` constant on line 51 — dead constant). | Use `path.join(workspacePath, "plugins", "soleur")` for parity. Note the `PLUGIN_PATH` constant in `agent-runner.ts:51-52` is dead — flag for cleanup in a follow-up issue (NOT scope of this PR). |
| Issue: `sandbox: { ... }` copy from `agent-runner.ts` | `agent-runner.ts:807-829` is the canonical block. | Extract to a small helper `buildAgentSandboxConfig(workspacePath)` so both call sites share the literal — symbol anchor per `cq-code-comments-symbol-anchors-not-line-numbers`. |
| Issue: `canUseTool: createCanUseTool(ctx)` | `permission-callback.ts:127` `createCanUseTool` requires `session: AgentSession` (with `reviewGateResolvers` Map) and `controllerSignal: AbortSignal`. The cc-soleur-go runner has NEITHER — it tracks per-conversation `Query` lifecycle in `activeQueries: Map<conversationId, ActiveQuery>`. The runner uses `pendingPrompts` + `emitInteractivePrompt` for AskUserQuestion-style UX (Stage 2.10), NOT review-gate. | The cc-soleur-go path does NOT use `AskUserQuestion` review-gate (interactive_prompt mechanism replaces it for the router itself). For Bash review-gate we need a path: either (a) construct a synthetic `AgentSession` per `query()` call inside the factory, OR (b) build a runner-aware `canUseTool` factory variant that uses the runner's interactive_prompt bridge for Bash gating. Decision: **(a) synthetic AgentSession** — minimal change, preserves all existing `permission-callback.ts` semantics (file-tool sandbox, BLOCKED_BASH_PATTERNS, MCP tier gating). The synthetic session's `reviewGateResolvers` Map is wired to a thin shim that emits an `interactive_prompt` of kind `bash_approval` and resolves on `respondToToolUse`. **See "Open Design Question" below.** |
| Issue: `hooks: { PreToolUse: [createSandboxHook] }` | `agent-runner.ts:831-851` includes BOTH `PreToolUse` AND `SubagentStart` hooks. | Mirror BOTH (SubagentStart audit log is defense-in-depth for #910). |
| Issue: `env: buildAgentEnv(apiKey, serviceTokens)` | `agent-env.ts:42` — already exported, accepts `(apiKey, serviceTokens?)`. | Direct call. `getUserApiKey` and `getUserServiceTokens` are NOT exported from `agent-runner.ts` — must be exported (or factored to a new module). |
| Issue: model `claude-sonnet-4-6` | `agent-runner.ts:782` uses `claude-sonnet-4-6`. Hard-coded. | Match. Bump path tracked separately. |
| Issue: `settingSources: []` | `agent-runner.ts:787` matches; comment refers to defense-in-depth alongside `patchWorkspacePermissions`. | Match. NOTE: `patchWorkspacePermissions(workspacePath)` (`agent-runner.ts:65`) must also run from the cc-soleur-go path so workspaces created before Stage 2.12 don't carry stale `permissions.allow` entries that bypass `canUseTool`. **Add to plan.** |
| Issue body claims "Real-SDK binding unlocks Stage 4 UI testing + Stage 6 smoke tests." | Confirmed via `grep "Stage 4\|Stage 6" knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md`. Stage 6 in that plan is "Cost-cap calibration + smoke" — depends on a real query. | Match. |
| Issue claims `realSdkQueryFactoryStub` "throws a controlled error (caught by the runner's `reportSilentFallback`)" | `cc-dispatcher.ts:98-111` confirmed; `soleur-go-runner.ts:717-732` catches and re-throws after `reportSilentFallback`. | Match. After binding, the catch path stays (covers any factory exception, e.g., `KeyInvalidError` from BYOK). |
| Issue claims `FLAG_CC_SOLEUR_GO=0` default keeps prod inert | `lib/feature-flags/server.ts:12` confirmed; default false. ws-handler routes by `parseConversationRouting(routing)` and only writes `soleur_go_pending` when flag is on. | Match. Plan ships with flag UNCHANGED in Doppler `prd`. Dev-only smoke. |

## Open Design Question — Bash Review-Gate Bridge

**Status:** RESOLVED — Option A (synthetic AgentSession), with deepen-pass clarification below.

### Layer Clarification (deepen-pass)

There are TWO separate gating layers in play, at different lifecycle points:

| Layer | Where | When | Synchronous? | Effect |
|---|---|---|---|---|
| `canUseTool` (SDK step 5) | `permission-callback.ts:127` | BEFORE the SDK actually executes the tool | Yes — must return `Promise<PermissionResult>` synchronously to the SDK | Allow / deny the tool execution |
| `bridgeInteractivePromptIfApplicable` | `soleur-go-runner.ts:423` invoked from `consumeStream` | AFTER the SDK has emitted a `tool_use` content block (i.e., model decided to call it AND `canUseTool` already permitted) | No — fire-and-forget WS event + registry record | UX surface only — the tool has already run or is running |

**The interactive_prompt mechanism is NOT a gate.** It's a UX notification. The runner emits `interactive_prompt` events for `bash_approval`, `plan_preview`, `diff`, etc. so the chat UI can render rich confirmations. Resolution via `respondToToolUse` posts a `tool_result` content block back to the SDK as the model's tool-execution-result — NOT a permission decision.

This means **gating Bash inside cc-soleur-go must happen at `canUseTool`, not at the interactive_prompt bridge.** Three architectural options:

**Option A — Synthetic AgentSession (RECOMMENDED, confirmed after deepen).** Construct a per-`query()` `AgentSession` inside the factory:
- `controller = new AbortController()` — bound to the Query lifetime, abortable by the runner's existing close paths
- `session: AgentSession = { abort: controller, reviewGateResolvers: new Map(), sessionId: null }`
- Register the synthetic session under a userKey-derived key in a small Map `ccBashGates: Map<userKey, AgentSession>` exported from `cc-dispatcher.ts`
- A new exported `resolveCcBashGate(userId, conversationId, gateId, selection)` mirrors `resolveReviewGate` for the cc path; ws-handler `review_gate_response` for cc-routed conversations dispatches here.

The Bash review-gate WS event uses `type: "review_gate"` — same shape the legacy path emits. The client `review_gate_response` handler routes by conversation routing kind.

Trade-off: introduces a parallel session-tracking Map inside cc-dispatcher. Mitigated by:
- One place (cc-dispatcher.ts factory closure)
- Symbol-anchored comments (`cq-code-comments-symbol-anchors-not-line-numbers`)
- Cleanup hook on `closeConversation`/`reapIdle` (runner already exposes both)

**Option B — Extend `PendingPromptRegistry` with canUseTool resolvers.** Add a separate channel `pendingCanUseToolGates: Map<key, (allow: boolean) => void>` to the registry. The factory's `canUseTool` for Bash registers a resolver, emits an `interactive_prompt` of kind `bash_approval`, awaits the resolver, returns allow/deny. Client uses `interactive_prompt_response` (already wired) but ws-handler routes `bash_approval` responses to a new `resolveCanUseToolGate` API.

Trade-off: cleaner long-term (one mechanism), but:
- Conflates two concepts (model-tool-result vs permission-decision) on the same wire shape — schema drift risk
- Requires extending `respondToToolUse` or adding `respondToCanUseTool` parallel API
- Larger blast radius (`PendingPromptRegistry` is shipped + tested)
- Renders existing Bash review-gate logic in `permission-callback.ts` partially-dead for the cc path, increasing maintenance surface

**Option C — Defer Bash to V2 (`disallowedTools: ["Bash", "WebSearch", "WebFetch"]`).** Configure cc-soleur-go path with Bash disallowed for V1. Test against `/soleur:work` smoke to verify acceptable.

Trade-off: highly likely to break `/soleur:work` (which executes git, lint, test, build commands via Bash). Verify before adopting.

### Recommendation (confirmed after deepen)

**Option A.** Smallest surface change, preserves all existing `permission-callback.ts` semantics (file-tool sandbox, BLOCKED_BASH_PATTERNS, MCP tier gating). The "parallel infrastructure" concern is a single Map confined to the factory closure.

If reviewer pushes back, fall to **Option C for V1** and file V2 issue for **Option B** as the proper long-term integration. **Do NOT mix Options A + B**.

### Pre-implementation verification

Before RED phase, run a `/soleur:work` invocation against the bound stub (or grep `/soleur:work` skill source) to confirm Bash is needed. Quick test:

```bash
grep -rn "Bash\|child_process\|spawn\|exec" plugins/soleur/skills/work/SKILL.md | head -10
```

If Bash is unused, Option C becomes viable for V1 and lowers the PR size by ~80 LoC. **Do not skip this check.**

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — replace `realSdkQueryFactoryStub` with the real factory closure. Remove `_stubMirroredOnce` gating (the throw path stays for any inner error). Wire `getUserApiKey`/`getUserServiceTokens` (newly exported from `agent-runner.ts`).
- `apps/web-platform/server/agent-runner.ts` — export `getUserApiKey` and `getUserServiceTokens` (currently module-private). Lift `buildAgentSandboxConfig(workspacePath)` helper from the inline `sandbox: {...}` block at lines 807-829 — both call sites (`agent-runner.ts` and `cc-dispatcher.ts`) consume it. Run `patchWorkspacePermissions(workspacePath)` in the cc path too.
- `apps/web-platform/test/cc-dispatcher.test.ts` — extend the existing tests:
  - new `it()` asserting that with a mocked `query()` the factory builds the expected options shape (`cwd`, `model`, `settingSources: []`, `mcpServers: {}`, `plugins`, `env`, `disallowedTools`, `sandbox.failIfUnavailable: true`, `sandbox.allowUnsandboxedCommands: false`).
  - `it()` asserting `KeyInvalidError` from `getUserApiKey` propagates through the factory and surfaces via `reportSilentFallback` (the catch in `soleur-go-runner.ts:717-732`).
  - `it()` asserting `getUserApiKey` is INVOKED only when factory is called (lazy — no DB hit when flag off).
  - `it()` asserting service-token allowlist is propagated to env (`buildAgentEnv` → ANTHROPIC_API_KEY + service tokens, no SUPABASE_SERVICE_ROLE_KEY leak).
- `apps/web-platform/server/__tests__/agent-runner-helpers.test.ts` (new) — unit-test for `buildAgentSandboxConfig` (drift guard against the hardcoded shape).

## Files to Create

- `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` (new) — focused tests for the real factory closure. Mocks `@anthropic-ai/claude-agent-sdk` `query`, asserts options shape per checklist above. Separate from `cc-dispatcher.test.ts` to keep that file focused on singletons.

## Implementation Order

0. **PRE — Bash usage check.** Run `grep -rn "Bash\|child_process\|spawn\|exec" plugins/soleur/skills/work/SKILL.md plugins/soleur/skills/brainstorm/SKILL.md plugins/soleur/skills/plan/SKILL.md` to confirm whether `/soleur:work` and friends actually invoke Bash via the SDK. If yes → Option A (synthetic AgentSession). If no → Option C (`disallowedTools` includes Bash) for V1, file Option B as V2-X.
0.5. **PRE — File V2-13 issue.** `gh issue create --title "V2-13: Tier-classify in-process MCP servers for cc-soleur-go path" --body "..." --milestone "Post-MVP / Later"`. Reference the new issue number in `cc-dispatcher.ts` factory closure code comment (AC10).
1. **RED — assertion tests for factory options shape (T1–T7, T15).** Write `cc-dispatcher-real-factory.test.ts` with mocked `query()` + captured `options`. Assertions fail until factory implemented.
2. **GREEN — export user-data helpers (AC2).** Make `getUserApiKey`/`getUserServiceTokens` exported from `agent-runner.ts` (zero behavior change). Add JSDoc warning per R12. Run existing tests — green.
3. **GREEN — extract `buildAgentSandboxConfig` (AC3).** Refactor `agent-runner.ts:807-829` into a helper in a small co-located module. Add T17 snapshot drift-guard. Run existing tests — green.
4. **GREEN — implement real factory.** Replace `realSdkQueryFactoryStub` body. Wire `mcpServers: {}`, `disallowedTools: ["WebSearch", "WebFetch"]` (AC15), hooks (PreToolUse + SubagentStart), `canUseTool` per Option A (with synthetic `AgentSession` + `ccBashGates: Map`), `leaderId: "cc_router"` (AC14), `allow()` helper (AC13). Tests from step 1 turn green.
5. **GREEN — Sentry tagging (AC7, T16).** Around the factory's body, mirror the `agent-runner.ts:1136-1141` substring check for `sandbox required but unavailable` → `feature: "agent-sandbox"`.
6. **GREEN — `KeyInvalidError` propagation (R10, T19).** Extend `dispatchSoleurGo` catch to detect `KeyInvalidError` and pass `errorCode: "key_invalid"` to the client.
7. **GREEN — `ws-handler` `review_gate_response` cc routing (Option A only, T12–T14).** When the active conversation routing kind is `soleur_go_*`, route `review_gate_response` messages to `resolveCcBashGate(...)` instead of `resolveReviewGate(...)`. Wire the cleanup hook on `closeConversation`/`reapIdle`.
8. **GREEN — extend `cc-dispatcher.test.ts` with T8–T11.**
9. **GREEN — extend with T18–T19.** Service-token allowlist + `KeyInvalidError` sanitization.
10. **VERIFY — `agent-runner.ts` regression.** Run `apps/web-platform/test/agent-runner*` to confirm zero regression after the helper extraction.
11. **VERIFY — feature-flag gate (T11).** Confirm `getFlag("command-center-soleur-go") === false` keeps the factory cold-path. Add explicit test if not covered by step 8.
12. **VERIFY — full local test suite + tsc + lint (AC5).** `cd apps/web-platform && ./node_modules/.bin/vitest run && npx tsc --noEmit`.
13. **VERIFY — fake-author guard (AC18).** `git log --pretty='%ae' main..HEAD` — must NOT contain `test@test` or any `noreply@` not equal to the GitHub installation bot.
14. **DEV smoke (post-PR-merge, separate session — see PM1–PM5).** Set `FLAG_CC_SOLEUR_GO=true` in Doppler `dev`, restart container, send a Command Center message that triggers `/soleur:go` routing. Confirm: (a) Sentry has zero `op: "queryFactory"` errors, (b) WS sees `stream` events from the SDK, (c) sticky workflow detection fires when the router dispatches to a skill, (d) `feature: "agent-sandbox"` filter shows zero events.

### Implementation order failure modes (deepen-pass additions)

- **Step 2 risk:** exporting `getUserApiKey` triggers test imports that pull in `@supabase/supabase-js` runtime — per learning `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md` §Session Errors. Mitigation: keep the new tests in `apps/web-platform/test/` (where Supabase boot config is loaded), NOT in a peer module. If the import chain remains too heavy, factor `getUserApiKey`/`getUserServiceTokens` into a new `user-credentials.ts` module (R12 long-term).
- **Step 3 risk:** snapshot helper test must NOT be sensitive to readonly object identity (use `toEqual`, not `toBe`).
- **Step 4 risk:** `canUseTool` schema strictness — must use `allow(toolInput)` per AC13 (learning `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`). Bare `{behavior: "allow"}` triggers ZodError at SDK level even on v0.2.85.
- **Step 7 risk:** ws-handler `review_gate_response` for cc-routed conversations must dispatch by routing kind, NOT by checking the existence of an `AgentSession` (currently `resolveReviewGate` raises if no session — for cc, the synthetic session lives in `ccBashGates`, not `activeSessions`). Add explicit routing-kind branch.

## Test Scenarios

| # | Scenario | Asserts |
|---|---|---|
| T1 | factory called with valid user → returns Query | `query` invoked once with expected `options.cwd === workspacePath`, `options.model === "claude-sonnet-4-6"` |
| T2 | factory options omit `mcpServers` (or empty) | `options.mcpServers === undefined` or `{}` — V2-13 will widen |
| T3 | factory options include `plugins: [{ type: "local", path: <workspace>/plugins/soleur }]` | exact path match |
| T4 | factory options include sandbox with `failIfUnavailable: true` and `allowUnsandboxedCommands: false` | shape match |
| T5 | factory options include hooks with `PreToolUse` matcher and `SubagentStart` log hook | both present |
| T6 | factory options include `disallowedTools: ["WebSearch", "WebFetch"]` | exact match |
| T7 | factory options include `settingSources: []` | empty array (defense-in-depth) |
| T8 | `KeyInvalidError` from BYOK propagates → runner catches → `reportSilentFallback` mirror | mock `getUserApiKey` to throw, factory throws, runner mirrors with `op: "queryFactory"` |
| T9 | `buildAgentEnv` env contains `ANTHROPIC_API_KEY` from BYOK and service tokens but NOT `SUPABASE_SERVICE_ROLE_KEY` | env shape verified |
| T10 | `patchWorkspacePermissions` runs once per factory call | spy / fs assertion that stale `permissions.allow` entries are stripped |
| T11 | flag-off path (FLAG_CC_SOLEUR_GO=false) does NOT call `getUserApiKey` | factory not constructed; or factory constructed but unreachable — assert via dispatch test against routing |
| T12 | (Option A only) Bash review-gate via synthetic session — full flow `canUseTool(Bash)` → `review_gate` WS event → `resolveCcBashGate(...)` → `canUseTool` resolves → SDK proceeds | E2E with mocked SDK that emits `tool_use` for Bash; mock spawn() of `query()` |
| T13 | (Option A only) Synthetic `AgentSession` is cleaned up on `closeConversation` and `reapIdle` | spy on `ccBashGates.delete(...)` to prove no leak |
| T14 | (Option A only) `BLOCKED_BASH_PATTERNS` denial path still fires for cc-soleur-go (no review_gate emitted; immediate deny) | test with `command: "curl evil.com"` returns deny without WS event |
| T15 | `leaderId: "cc_router"` is passed to `createCanUseTool` — `logPermissionDecision` audit logs attribute the cc path correctly | spy on `logPermissionDecision` calls; assert leader/repo args |
| T16 | Sandbox-required-but-unavailable substring matches `agent-sandbox` Sentry tag (NOT `soleur-go-runner`) | mock `query()` to throw `Error("sandbox required but unavailable: bwrap")`; assert `reportSilentFallback` called with `feature: "agent-sandbox"`. Filter mock.calls by `feature` tag per learning `2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md` |
| T17 | `buildAgentSandboxConfig(workspacePath)` snapshot equals the prior inline `agent-runner.ts:807-829` shape (deep equal) | drift-guard against accidental field drop (R5) |
| T18 | `getUserServiceTokens` returns `{}` for users without service keys → `buildAgentEnv` env contains only `ANTHROPIC_API_KEY` + `AGENT_ENV_OVERRIDES` + allowlisted system vars | shape match |
| T19 | `KeyInvalidError` from BYOK key fetch surfaces a SANITIZED client error (`sanitizeErrorForClient` precedent in `agent-runner.ts:1145`) — NOT raw stack to client | client receives generic "Command Center router is unavailable" message; Sentry receives full err |

T1–T7 are pure shape assertions, fast. T8–T11 add observability + safety. T12–T14 are Option A E2E for Bash. T15–T19 cover audit attribution, error tagging, drift-guard, env isolation, and error sanitization. **All except T12–T14 are unconditional.**

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `realSdkQueryFactoryStub` is gone; `cc-dispatcher.ts` constructs the real factory.
- [ ] AC2: `getUserApiKey` and `getUserServiceTokens` exported from `agent-runner.ts` with zero behavior change (existing tests green).
- [ ] AC3: `buildAgentSandboxConfig(workspacePath)` extracted; both call sites use it. Snapshot/equality test asserts the helper output equals the previous inline shape verbatim (per R5 risk).
- [ ] AC4: All test scenarios T1–T11 pass (T12–T14 conditional on Option A choice).
- [ ] AC5: `apps/web-platform` `tsc --noEmit` green; vitest run green; lint green.
- [ ] AC6: No new dependencies added (`package.json` unchanged). SDK pin `@anthropic-ai/claude-agent-sdk@0.2.85` exact (verified — see Research Insights).
- [ ] AC7: Sentry op tags preserved: `feature: "soleur-go-runner"`, `op: "queryFactory"` for any inner factory throw. **AND** the `sandbox required but unavailable` stderr substring is mirrored as `feature: "agent-sandbox"`, `op: "sdk-startup"` per the `agent-runner.ts:1136-1141` precedent (learning `2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md`).
- [ ] AC8: `patchWorkspacePermissions(workspacePath)` runs in the cc-soleur-go path too (defense-in-depth from `cq-` rules class). Idempotent; only fires once per cold-Query construction (not per dispatch turn).
- [ ] AC9: `FLAG_CC_SOLEUR_GO=false` keeps the production path inert — verified via test T11.
- [ ] AC10: `mcpServers: {}` for V1; V2-13 tracking issue **created in this PR** (does not currently exist — `gh issue list --search "V2-13"` returns empty as of 2026-04-27). Title: `V2-13: Tier-classify in-process MCP servers for cc-soleur-go path`. Reference issue number in `cc-dispatcher.ts` factory closure code comment.
- [ ] AC11: Open Design Question (Bash review-gate bridge) decided and recorded in PR description with reviewer ack. If Option A: `ccBashGates: Map` + `resolveCcBashGate` exported from cc-dispatcher; ws-handler `review_gate_response` for cc-routed conversations dispatches there.
- [ ] AC12: PR body uses `Closes #2884`.
- [ ] AC13: `allow(toolInput)` helper is used for ALL `canUseTool` allow branches in the cc-soleur-go path (per learning `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`); no bare `{behavior: "allow"}` returns.
- [ ] AC14: `leaderId: "cc_router"` (NOT `undefined`) is passed to `createCanUseTool` so audit logs (`logPermissionDecision`) attribute correctly. Verified by test T15.
- [ ] AC15: `disallowedTools: ["WebSearch", "WebFetch"]` mirrored from `agent-runner.ts:797` parity (per R7 risk). Verified by test T6.
- [ ] AC16: `env: buildAgentEnv(apiKey, serviceTokens)` — env shape verified to NOT contain `SUPABASE_SERVICE_ROLE_KEY`, `BYOK_ENCRYPTION_KEY`, or any Stripe secret (CWE-526 — learning `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`). Verified by test T9.
- [ ] AC17: All explicit string literals (`feature` tags, `op` tags, error messages) appear identically across plan, code, tests. Greppable single canonical value for each.
- [ ] AC18: No fake-author commits (per `hr-never-fake-git-author`); worktree git config validated.

### Brainstorm-recommended specialists

None applicable — no brainstorm exists for this issue. CMO/CPO not relevant (engineering-only follow-through behind off-by-default flag in prod, no user-facing UI delta). CTO domain auto-accepted.

### Post-merge (operator)

- [ ] PM1: Set `FLAG_CC_SOLEUR_GO=true` in Doppler `dev` if not already set; restart `apps/web-platform` container in `dev`.
- [ ] PM2: Send a Command Center message in `dev` Command Center; confirm WS streams include `stream` events from the SDK (not just `error`).
- [ ] PM3: Sentry filter `feature:"soleur-go-runner" op:"queryFactory"` shows zero events for ~30 min after smoke.
- [ ] PM4: Stage 4 UI testing and Stage 6 smoke tests (separate plans/issues) can now proceed — verify with maintainers of those stages.
- [ ] PM5: After Stage 6 acceptance, file separate PR(s) for V2 follow-ups (mcpServers expansion → V2-13; if Option B chosen for Bash → V2-X).

## Domain Review

**Domains relevant:** Engineering (CTO).

This is an internal infrastructure binding behind a feature flag default-off in prod.
No user-visible UI change, no new pages, no marketing surface, no pricing/billing
implication, no legal/compliance touch, no operational cost change (FLAG off in prod).
Per `hr-new-skills-agents-or-user-facing` the CPO/CMO gate fires for new
USER-FACING capabilities — this is binding a stub to an existing flagged path.

### CTO

**Status:** auto-accepted (engineering-only follow-through binding behind off-by-default flag in prod)
**Assessment:** Low-risk implementation of a previously planned binding. Risk concentrated
in the Open Design Question (Bash review-gate). Recommend Option A for incremental
delivery; defer Option B to V2 follow-up issue if reviewer prefers cleaner mechanism.

No Product/UX Gate triggered (no `components/**/*.tsx`, no `app/**/page.tsx`, no
`app/**/layout.tsx` in Files to create/edit).

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open` — zero open
review issues touch `cc-dispatcher.ts`, `soleur-go-runner.ts`, `permission-callback.ts`,
or `agent-runner.ts`.

## Risks

- **R1 — Bash review-gate mismatch.** The cc-soleur-go path lacks `AgentSession` infrastructure. Option A creates a parallel synthetic-session map; Option B requires extending interactive_prompt. Mitigation: the Open Design Question above; recommend A and ship; revisit at Stage 6.
- **R2 — `patchWorkspacePermissions` side effect.** This mutates `.claude/settings.json` on disk in the user's workspace. Already runs in `agent-runner.ts`; running here too is idempotent. Risk is low but explicit.
- **R3 — In-process MCP server omission for V1.** `kb_share_*`, `conversations_lookup`, github read tools, plausible tools are unavailable to the cc-soleur-go router. By design — the router delegates to `/soleur:go` which delegates to skills. Acceptable for V1 per source plan §2.17. **Mitigation:** smoke-test that the router CAN dispatch to a skill that needs these tools (e.g., `/soleur:work`) — the skill-spawned subagent inherits the SDK options including its own tools.
- **R4 — Stub deletion blast radius.** `_stubMirroredOnce` is removed. If the factory's BYOK fetch fails on a high-QPS misconfigured prod, Sentry could see N events. Mitigation: rate-limit at `reportSilentFallback` is owned by `observability.ts`; verify the once-per-process gate is not load-bearing — it's not, because `FLAG_CC_SOLEUR_GO=false` in prod gates the entire dispatch path.
- **R5 — Helper extraction regression.** Extracting `buildAgentSandboxConfig` from `agent-runner.ts:807-829` is a pure refactor — but if the helper accidentally drops one field (e.g., `enableWeakerNestedSandbox`), the agent runs with a different sandbox profile in prod. Mitigation: snapshot test that the helper's output equals the literal block (T-helper drift guard).
- **R6 — `agent-runner.ts` `PLUGIN_PATH` dead constant.** Lines 51-52 — unused since `agent-runner.ts:830` switched to `path.join(workspacePath, "plugins", "soleur")`. NOT in scope of this PR but flag for follow-up cleanup.
- **R7 — `disallowedTools` parity drift.** `agent-runner.ts:797` blocks `WebSearch` and `WebFetch`. If the cc-soleur-go path omits this, the router could fetch arbitrary URLs. Mitigation: AC15 explicitly mirrors the disallow list.
- **R8 — Composite-key cross-user prompt collision (Option A).** When introducing `ccBashGates: Map<key, AgentSession>`, the key MUST be `${userId}:${conversationId}:${gateId}` (NOT just `gateId`) — same security invariant `pending-prompt-registry.ts` enforces. Mitigation: copy the `makePendingPromptKey` pattern; lookup must verify `userId` matches before resolving (silent denial if mismatch). Test T12 covers cross-user attempt.
- **R9 — `respondToToolUse` confused with `resolveCcBashGate` (Option A).** Two separate response paths exist for cc-routed conversations: (a) `interactive_prompt_response` → `respondToToolUse` (model gets a `tool_result`); (b) `review_gate_response` → `resolveCcBashGate` (canUseTool gate resolves). The ws-handler MUST route by message `type`, not by overload. Mitigation: explicit ws-handler case for each; PR description includes a sequence diagram if ambiguous.
- **R10 — `KeyInvalidError` user UX in cc-soleur-go path.** `agent-runner.ts:1149` surfaces `errorCode: "key_invalid"` so the client can prompt for a fresh BYOK key. The cc-soleur-go path's `dispatchSoleurGo` catch (`cc-dispatcher.ts:256-266`) currently surfaces a generic "Command Center router is unavailable" — `KeyInvalidError` is swallowed under the generic message. Mitigation: extend the catch to detect `KeyInvalidError` and pass `errorCode: "key_invalid"`. **Verified at deepen — line 264 of `cc-dispatcher.ts`.**
- **R11 — Sentry event quota exhaustion if FLAG flips on prematurely.** Removing the `_stubMirroredOnce` once-per-process gate (R4) creates risk: if `FLAG_CC_SOLEUR_GO=true` flips on but BYOK is broken, every dispatch fails the factory and mirrors to Sentry. At ~1 QPS sustained that's 86k events/day. Mitigation: keep a once-per-cause Sentry mirror in the factory closure, OR rely on Sentry's dedup. **Decision: rely on Sentry dedup + `feature: "agent-sandbox"` tag filter for triage; if dedup proves insufficient, add per-`(userId, errorCode)` debounce with 5-minute window.**
- **R12 — `getUserApiKey` and `getUserServiceTokens` export breaks encapsulation.** Currently module-private. Exporting widens surface for unrelated callers to bypass the agent flow. Mitigation: export with explicit JSDoc comment scoping ("INTERNAL: cc-dispatcher real-SDK factory only — do not call from new modules"). Long-term consideration: factor user-data fetching into a dedicated `user-credentials.ts` module — out of scope here, file as cleanup issue.
- **R13 — Missing test for `KeyInvalidError` propagation.** Test T8 covers the throw path; T19 verifies sanitization. But the error code propagation to `WSMessage.errorCode` is currently NOT tested for the cc path. Mitigation: T19 widened to cover error code propagation explicitly.

## Non-Goals / Out of Scope

- **NG1 — `mcpServers` expansion.** Issue body explicitly says "empty — V2-13 tracks tier classification before expanding." Verify V2-13 issue exists; if not, file it before merging this PR (per `wg-when-deferring-a-capability-create-a`).
- **NG2 — Per-user / per-cohort percentage rollout.** V2-8 in source plan tracking. This PR keeps the flag binary on/off.
- **NG3 — `agent-runner.ts` deletion.** Stage 8 in source plan. This PR keeps both runners coexisting.
- **NG4 — Stage 4 UI testing.** Tracked in Stage 4 of source plan; this PR enables it but does not perform it.
- **NG5 — Stage 6 smoke + cost calibration.** Same — enabled, not performed.
- **NG6 — `PLUGIN_PATH` dead constant cleanup.** R6 above; follow-up issue.

## Research Insights

### SDK + repo invariants (verified at deepen-pass 2026-04-27)

- **SDK pin:** `apps/web-platform/package.json` → `"@anthropic-ai/claude-agent-sdk": "0.2.85"` (exact, no caret). Above the 0.2.81 `canUseTool` fix and at the 0.2.85 PreToolUse `permissionDecision: "ask"` fix. **No SDK bump required**; relevant per learning `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`.
- **`bash_approval` interactive_prompt kind exists:** `cc-interactive-prompt-types.ts:37` defines it with `response: "approve" | "deny"`. Already wired through `pending-prompt-registry.ts:43`, `cc-interactive-prompt-response.ts:103,152`, `soleur-go-runner.ts:186`, ws-handler. **But this is a UX surface, not a permission gate** (see Open Design Question Layer Clarification).
- **`leaderId: "cc_router"` exists** as a non-routable leader (per learning `2026-04-24-multi-agent-review-catches-feature-wiring-bugs.md` §"`cc_router` leader"). Pass this to `createCanUseTool` for audit log attribution.
- **`agent-runner.ts:1136-1141` Sentry tagging precedent:** stderr-substring match for `sandbox required but unavailable` → `reportSilentFallback({feature: "agent-sandbox", op: "sdk-startup"})`. The cc-soleur-go factory MUST mirror this precedent (AC7).
- **V2-13 issue does NOT exist:** `gh issue list --search "V2-13"` returns empty. AC10 requires creating it.
- **`allow(toolInput)` helper:** `permission-callback.ts:53` — must be used for ALL allow branches per learning `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`.

### Module-level reference points

- `soleur-go-runner.ts:412-440` — `createSoleurGoRunner` factory; `dispatch()` calls `deps.queryFactory(...)` exactly once per (cold) `conversationId`. Reused dispatches skip queryFactory.
- `soleur-go-runner.ts:261-273` — `QueryFactoryArgs` shape: `{prompt, systemPrompt, resumeSessionId, pluginPath, cwd, userId, conversationId}`. Factory fetches workspacePath/apiKey/serviceTokens given userId.
- `soleur-go-runner.ts:717-732` — runner's catch around `queryFactory(...)` — `reportSilentFallback({feature: "soleur-go-runner", op: "queryFactory"})` then re-throws.
- `agent-runner.ts:417-877` — full reference for the `query()` invocation. Factory must mirror with these omissions: no `mcpServers` (V1; V2-13 will widen), no `pluginMcpServerNames` allowlist, simplified `canUseTool` ctx (no `platformToolNames`, no `repoOwner`/`repoName`, synthetic AgentSession per Option A).
- `permission-callback.ts:127-512` — `createCanUseTool`. Required ctx: `{userId, conversationId, leaderId, workspacePath, platformToolNames, pluginMcpServerNames, repoOwner, repoName, session, controllerSignal, deps}`. For cc-soleur-go: `leaderId: "cc_router"`, `platformToolNames: []`, `pluginMcpServerNames: []`, `repoOwner: ""`, `repoName: ""`, synthetic session per Option A, controller bound to per-Query lifetime.
- `permission-callback.ts:53` — `allow(toolInput)` helper (mandatory for all allow branches).
- `agent-env.ts:42-72` — `buildAgentEnv(apiKey, serviceTokens?)` already exported. Allowlist-only env (CWE-526 mitigation per learning `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`).
- `lib/feature-flags/server.ts:12` — `FLAG_CC_SOLEUR_GO` env-var-driven via `getFlag("command-center-soleur-go")`.
- `cc-dispatcher.ts:98-111` — current stub (to be replaced).
- `cc-dispatcher.ts:256-266` — `dispatchSoleurGo` catch path (R10 — extend for `KeyInvalidError`).

### Tests

- Tests live in `apps/web-platform/test/`. Vitest config: `cd apps/web-platform && ./node_modules/.bin/vitest run` per `cq-in-worktrees-run-vitest-via-node-node`.
- Example mock pattern for `@anthropic-ai/claude-agent-sdk`: `apps/web-platform/test/agent-runner-kb-share-preview.test.ts:178+` mocks `query` and intercepts `options` via captured args.
- Example pattern for filter-by-tag: see learning `2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md` §"Test pattern" — `mock.calls.filter(([, opts]) => opts?.feature === "agent-sandbox")` not `.toHaveBeenCalledOnce()`.

### Live verifications performed at deepen-pass

```bash
# SDK pin verified
grep '"@anthropic-ai/claude-agent-sdk"' apps/web-platform/package.json
# → "@anthropic-ai/claude-agent-sdk": "0.2.85",

# bash_approval kind exists
grep -n "bash_approval" apps/web-platform/server/cc-interactive-prompt-types.ts
# → line 37 (kind def) + line 50 (response def)

# V2-13 issue does NOT exist
gh issue list --search "V2-13" --state all --json number,title
# → []

# canUseTool layered before tool execution; bridge fires after tool_use
grep -n "bridgeInteractive\|consumeStream" apps/web-platform/server/soleur-go-runner.ts
# → line 423 (bridge def) + line 590 (bridge invoke from consumeStream)

# allow(toolInput) helper exists at module scope
grep -n "^export function allow" apps/web-platform/server/permission-callback.ts
# → line 53
```

## Institutional Learnings Applied

- `cq-silent-fallback-must-mirror-to-sentry` — every catch path mirrors via `reportSilentFallback`. Already wired in the runner; preserved by AC7.
- `cq-code-comments-symbol-anchors-not-line-numbers` — refactor extracts `buildAgentSandboxConfig` so comments reference a symbol, not line numbers.
- `cq-write-failing-tests-before` — RED/GREEN order in Implementation Order.
- `cq-mutation-assertions-pin-exact-post-state` — test scenarios pin exact option shapes (`.toBe(post)` style).
- `cq-in-worktrees-run-vitest-via-node-node` — vitest invocation in this worktree.
- `wg-use-closes-n-in-pr-body-not-title-to` — AC12.
- `cq-test-mocked-module-constant-import` — when mocking `@anthropic-ai/claude-agent-sdk`, ensure the mock factory exports `query` and any other symbols the file imports (cf. similar mock patterns in `apps/web-platform/test/agent-runner-*.test.ts`).
- `cq-doppler-service-tokens-are-per-config` — operator step PM1 references the right `dev` config.

## Test Plan Summary

- 12 vitest scenarios (T1–T12)
- Helper drift-guard test (`buildAgentSandboxConfig` snapshot)
- `tsc --noEmit` green for `apps/web-platform`
- Smoke in `dev` (post-merge) confirms WS stream + zero Sentry events for ~30 min

## Implementation Estimate

Per-section LoC delta projection:

| Change | Estimated LoC |
|---|---|
| `cc-dispatcher.ts` real factory + `ccBashGates` Map + `resolveCcBashGate` | +95, −20 |
| `agent-runner.ts` exports + helper extract + JSDoc | +12, −22 (helper replaces inline) |
| `agent-runner-sandbox-config.ts` (new helper module) | +35 |
| `ws-handler.ts` review_gate_response routing-kind branch | +15 |
| `cc-dispatcher.ts` `dispatchSoleurGo` `KeyInvalidError` branch | +12 |
| `cc-dispatcher.test.ts` extensions (T8–T11, T18–T19) | +180 |
| `cc-dispatcher-real-factory.test.ts` (new) — T1–T7, T15–T17 | +260 |
| `cc-dispatcher-bash-gate.test.ts` (new) — T12–T14 (Option A only) | +180 |
| `agent-runner-helpers.test.ts` (new) — T17 drift-guard | +40 |
| **Total (Option A)** | **~+829, −42** (~785 net) |
| **Total (Option C — disallow Bash)** | ~+520, −42 (skip ws-handler routing + bash gate tests) |

If Option B (extend `PendingPromptRegistry`) chosen, add ~250 LoC across `pending-prompt-registry.ts` + handler + tests; defer to V2 issue.

## PR Body Template

Title: `feat(cc-soleur-go): Stage 2.12 — bind real-SDK queryFactory in cc-dispatcher`

```markdown
Closes #2884

## Summary

Replaces `realSdkQueryFactoryStub` in `cc-dispatcher.ts` with a real `query()`
call that fetches per-user workspace + BYOK key + service tokens, builds
sandbox config, and wires `canUseTool` + hooks. Behind `FLAG_CC_SOLEUR_GO=0`
in prod (default), so production behavior is unchanged. In `dev`
(`FLAG_CC_SOLEUR_GO=true`), the cc-soleur-go path now actually invokes the
SDK end-to-end.

## Bash Review-Gate Decision

Adopted **Option A** (synthetic AgentSession). [Or Option B / Option C with
rationale.]

## Test Plan

- [x] T1–T7 factory option shape assertions
- [x] T8–T11 error/observability/flag-gate
- [x] T12 Bash review-gate E2E (Option A only)
- [x] `apps/web-platform` `tsc --noEmit` + vitest + lint
- [x] Helper drift-guard snapshot

## Post-merge

- [ ] Operator: `FLAG_CC_SOLEUR_GO=true` in Doppler `dev`, restart container
- [ ] Smoke a Command Center message; check WS stream events
- [ ] Sentry filter `feature:"soleur-go-runner" op:"queryFactory"` = 0 events
```

## References

- Issue: #2884
- Source PR: #2858
- Source plan: `knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md`
- AGENTS.md rules cited above (cq-, wg-, hr- prefixes resolve in repo root AGENTS.md)
