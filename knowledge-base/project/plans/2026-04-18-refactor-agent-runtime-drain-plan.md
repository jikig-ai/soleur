# refactor: drain agent-runtime review backlog (#1662 + #2333 + #2334 + #2335 + #2336)

**Branch:** `feat-one-shot-agent-runtime-1662-2333-2336`
**Status:** plan (deepened)
**Created:** 2026-04-18
**Deepened:** 2026-04-18
**Closes:** #1662, #2333, #2334, #2335, #2336

## Enhancement Summary

**Sections enhanced:** Files to Create, Files to Edit, Test Scenarios, Risks & Mitigations — plus a new Research Insights section derived from 7 relevant learnings and the SDK's shipped `PermissionResult` type.

### Key Improvements

1. **SDK type pinned at source.** `PermissionResult` is a shipped, runtime-importable type in `@anthropic-ai/claude-agent-sdk@0.2.85+` (`sdk.d.ts:1341-1353`). Tests will import it directly rather than hand-roll a zod schema.
2. **Mock-cascade pre-flight added.** Learning `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md` documents that new imports into `agent-runner.ts` break ~31 tests across ~12 files. A dedicated pre-flight grep step now runs BEFORE Phase 1 and BEFORE Phase 3 to mirror-add any new `vi.mock()` entries in the same commit.
3. **TOCTOU avoidance rule added to symlink fix.** Learning `2026-04-17-kb-share-mcp-parity-...` warns that "extra pre-flight checks" (the lstat-then-mkdir pattern) can *reintroduce* CWE-367 TOCTOU windows. The `ensureDir` rewrite is now framed as "replace `existsSync` with `lstatSync`" (single syscall, no second-lookup), not "add lstat before mkdir".
4. **Negative-space delegation test added.** Learning `2026-04-15-negative-space-tests-must-follow-extracted-logic.md` prescribes that when logic moves from A to B, tests must prove B is both *invoked* and its result *respected*. A new test asserts `agent-runner.ts` calls `createCanUseTool(` and no longer contains an inline `canUseTool: async`.
5. **Symlink-rejection test fixture clarified.** Same learning: tests that claim to exercise symlink rejection must point the symlink at a target inside the intended boundary to actually hit the `ELOOP`/non-directory branch — a symlink to `/tmp/outside-uuid` is rejected by `lstat.isDirectory() === false` for any non-directory path, which the test already catches. Verified unambiguous.
6. **Safe-tools/allowlist verification tied to canUseTool tests.** Learning `2026-04-06-mcp-tool-canusertool-scope-allowlist.md` caught the blanket `startsWith("mcp__")` regression. The canUseTool test suite now includes an explicit "unregistered MCP tool is denied-by-default" case.
7. **Service-tool scope-guard retained.** Learning `service-tool-registration-scope-guard-20260410.md` (the Plausible-nested-inside-GitHub-guard bug) means the `buildPlausibleTools` extraction must NOT accidentally re-nest the call inside the `if (installationId && repoUrl)` block. Extraction preserves the current two independent guards.

### New Considerations Discovered

- `PermissionResult` shape confirmed via direct read of `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:1341-1353`:

  ```ts
  export declare type PermissionResult = {
    behavior: 'allow';
    updatedInput?: Record<string, unknown>;
    updatedPermissions?: PermissionUpdate[];
    toolUseID?: string;
    decisionClassification?: PermissionDecisionClassification;
  } | {
    behavior: 'deny';
    message: string;
    interrupt?: boolean;
    toolUseID?: string;
    decisionClassification?: PermissionDecisionClassification;
  };
  ```

  `updatedInput` is declared **optional** in the `.d.ts`, but learning `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md` documents that the runtime Zod schema treated it as **required** in the 0.2.80 window. The `allow(toolInput)` helper echoes it unconditionally — this is the defensive posture the plan preserves. Tests assert the presence of `updatedInput` on all allow branches regardless of `.d.ts` optionality.
- `CanUseTool` is a shipped type: `sdk.d.ts:130 — export declare type CanUseTool = (toolName, input, options) => Promise<PermissionResult>`. The extracted `createCanUseTool` factory should return exactly this type (imported, not re-declared).
- The SDK permission chain has 5 steps (1: hooks, 2: deny rules, 3: permission mode, 4: allow rules, 5: canUseTool). Per learning `2026-03-20-canusertool-caching-verification.md`, the web platform uses BYOK keys (no bridge auth), so `canUseTool` fires for every tool invocation. Debug-log instrumentation on the canUseTool layer is guaranteed to produce signal in prod.

## Overview

Drain five open `code-review` issues that all touch the same sliver of the
`apps/web-platform` agent runtime. Grouping them in one PR avoids five
separate round-trips through review and keeps the coupled concerns
(permission layering, workspace provisioning, `canUseTool` shape, MCP tool
module boundary) inside a single atomic diff.

The five issues split cleanly into three code areas:

| Area                 | Issue  | Scope                                                                 |
|----------------------|--------|-----------------------------------------------------------------------|
| MCP tool boundary    | #1662  | Extract inline GitHub + Plausible tool definitions to a new module    |
| Workspace scaffolding| #2333  | Harden `ensureDir` against symlinks at provisioner scaffolding sites  |
| Workspace scaffolding| #2334  | Extract `scaffoldWorkspaceDefaults` helper; dedupe both provisioners  |
| Permission shape     | #2335  | Unit tests for `canUseTool` allow/deny return shape                   |
| Permission shape     | #2336  | `SOLEUR_DEBUG_PERMISSION_LAYER` log flag for layer bisection          |

## Research Reconciliation — Spec vs. Codebase

| Claim in issue                                         | Reality in worktree                                                                                  | Plan response                                                                                          |
|--------------------------------------------------------|------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|
| #1662: "extract when 2nd tool added"                    | 4 in-process tool families already live inline: `github_*` (5 tools), `plausible_*` (3 tools); `kb-share-tools.ts` and `conversations-tools.ts` already split out (PRs #2497, #2571). | Extract the remaining inline tool families (`github_*` → `github-tools.ts`, `plausible_*` → `plausible-tools.ts`). Follow the `kb-share-tools.ts` / `conversations-tools.ts` factoring precedent. |
| #1662: "coordinate with PR-E conversations_lookup"      | PR #2571 already merged (`buildConversationsTools` exists in `conversations-tools.ts`).              | No coordination needed. Leave note in PR body that PR-E has already landed; extracted module joins it. |
| #2333: `ensureDir` follows symlinks (uses `existsSync`) | Confirmed at `apps/web-platform/server/workspace.ts:339-343`.                                        | Rewrite `ensureDir` to use `lstatSync` and throw on non-directory entries.                             |
| #2334: three duplicated blocks across provisioners      | Confirmed at `workspace.ts:58-89` (provisionWorkspace) and `workspace.ts:211-244` (provisionWorkspaceWithRepo); tuple named `KNOWLEDGE_BASE_DIRS`. | Extract `scaffoldWorkspaceDefaults(workspacePath, { suppressWelcomeHook? })`; rename tuple to `KNOWLEDGE_BASE_PROJECT_DIRS`. |
| #2335: no unit tests for canUseTool allow branches      | Confirmed. `canusertool-caching.test.ts` and `canusertool-tiered-gating.test.ts` exist but cover adjacent concerns. | Extract callback builder to `permission-callback.ts`; add `canusertool-decisions.test.ts` covering all 7 allow branches + deny-by-default. |
| #2336: `SOLEUR_DEBUG_PERMISSION_LAYER` flag missing     | Confirmed. grep of `apps/web-platform` returns zero hits for the flag name.                          | Add `permission-log.ts` with `logPermissionDecision()`; instrument every allow/deny call site.         |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change,
internal refactor + security hardening + test coverage. No user-facing
surface. No marketing, legal, or pricing impact. Engineering-only.

## Open Code-Review Overlap

Open review issues touching the target files (grep against `apps/web-platform/server/{agent-runner,workspace,sandbox-hook}.ts`):

- #1662, #2335 touch `agent-runner.ts` — **Fold in** (both already in scope).
- #2333, #2334 touch `workspace.ts` — **Fold in** (both already in scope).
- No other open `code-review` issues overlap these files.

None outside the five tracked issues — no backlog leakage.

## Files to Edit

- `apps/web-platform/server/agent-runner.ts`
  - Remove inline `github_*` tool `tool()` calls (~lines 644-810).
  - Remove inline `plausible_*` tool `tool()` calls (~lines 815-857).
  - Replace with `buildGithubTools({...})` and `buildPlausibleTools({...})` calls that return `{ tools, toolNames }` tuples.
  - Replace the inline `canUseTool` closure with `createCanUseTool({...})` imported from the new `permission-callback.ts`.
  - Instrument sandbox-hook and every `canUseTool` branch with `logPermissionDecision(layer, toolName, decision, reason)` calls.
- `apps/web-platform/server/workspace.ts`
  - Rewrite `ensureDir()` to use `lstatSync` and throw on non-directory entries (#2333).
  - Extract `scaffoldWorkspaceDefaults(workspacePath, { suppressWelcomeHook? })` covering the three duplicated blocks (KB dirs, `.claude/` writes, plugin symlink) (#2334).
  - Rename `KNOWLEDGE_BASE_DIRS` → `KNOWLEDGE_BASE_PROJECT_DIRS` (same PR).
  - Call `scaffoldWorkspaceDefaults` from both `provisionWorkspace` and `provisionWorkspaceWithRepo`.
- `apps/web-platform/server/sandbox-hook.ts`
  - Instrument allow/deny paths with `logPermissionDecision("sandbox-hook", ...)`.

## Files to Create

- `apps/web-platform/server/github-tools.ts` — exports `buildGithubTools({ installationId, owner, repo, defaultBranch, workspacePath, workflowRateLimiter }): { tools, toolNames }`. Mirrors `kb-share-tools.ts` factoring pattern. Tool list: `create_pull_request`, `github_read_ci_status`, `github_read_workflow_logs`, `github_trigger_workflow`, `github_push_branch`.
- `apps/web-platform/server/plausible-tools.ts` — exports `buildPlausibleTools({ plausibleKey }): { tools, toolNames }`. Tool list: `plausible_create_site`, `plausible_add_goal`, `plausible_get_stats`.
- `apps/web-platform/server/permission-callback.ts` — exports `createCanUseTool(ctx): CanUseTool` (the SDK's `CanUseTool` type). Moves the 7 allow branches and deny-by-default out of the `agent-runner.ts` closure so they can be unit-tested. The signature takes the captured context (workspacePath, userId, conversationId, platformToolNames, pluginMcpServerNames, repoOwner, repoName, session, leaderId, controller, abortableReviewGate helpers, sendToClient, notifyOfflineUser, updateConversationStatus).
- `apps/web-platform/server/permission-log.ts` — exports `logPermissionDecision(layer, toolName, decision, reason?)`. Gated by `process.env.SOLEUR_DEBUG_PERMISSION_LAYER === "1"`. Layer enum: `"sandbox-hook" | "canUseTool-file-tool" | "canUseTool-agent" | "canUseTool-safe" | "canUseTool-review-gate" | "canUseTool-platform-auto" | "canUseTool-platform-gated" | "canUseTool-platform-blocked" | "canUseTool-plugin-mcp" | "canUseTool-deny-default"`.
- `apps/web-platform/test/canusertool-decisions.test.ts` — new file. Covers the 7 allow branches + deny-by-default for the extracted callback. Each assertion schema-validates the return against the SDK's permission-result shape (hand-written zod schema if `PermissionResult` is not exported).
- `apps/web-platform/test/permission-log.test.ts` — new file. Covers: (a) flag off → zero log calls, (b) flag on → one structured log per call, (c) log payload includes `layer`, `tool`, `decision`, `sec: true`.
- `apps/web-platform/test/workspace-symlink-hardening.test.ts` — new file. Creates a symlink at `knowledge-base/overview` pointing outside the workspace and asserts `provisionWorkspaceWithRepo` throws with a clear error message. Mirrors existing `workspace.test.ts` env setup (`WORKSPACES_ROOT=/tmp/soleur-test-workspaces`, `GIT_CEILING_DIRECTORIES=tmpdir()`).

## Implementation Phases

### Phase 0 — Mock-cascade pre-flight (all phases)

Run once before any edit and again before Phase 3 (which adds a new import to `agent-runner.ts`):

```bash
# Find every test that loads agent-runner (directly or transitively)
grep -l "startAgentSession\|from.*agent-runner\|server/agent-runner" \
  apps/web-platform/test/*.test.ts*

# For each, verify it already mocks @/server/logger and @/server/observability
# If we introduce permission-log.ts or permission-callback.ts imports that any
# test transitively loads, that test must mock the new module — add
# vi.mock("@/server/permission-log") as a single batch, not one-by-one on CI failure.
```

**Why:** Learning `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md` documents ~31 test failures across ~12 files from a single new import into `agent-runner.ts`. Grep the surface before adding imports; add missing mocks as a batch.

### Phase 1 — MCP tool extraction (#1662)

1. **RED:** Skip — Phase 1 is a pure refactor. The existing `agent-runner-tools.test.ts` covers tool registration; if it passes post-extraction, behavior parity is preserved.
2. Create `github-tools.ts`:
   - Signature: `buildGithubTools(opts): { tools: Array<ReturnType<typeof tool>>; toolNames: string[] }`
   - Takes installationId, owner, repo, defaultBranch, workspacePath, workflowRateLimiter.
   - Returns all 5 GitHub MCP tools + their canonical `mcp__soleur_platform__<name>` strings.
3. Create `plausible-tools.ts`:
   - Signature: `buildPlausibleTools({ plausibleKey }): { tools, toolNames }`.
   - Returns 3 plausible tools + names.
4. Update `agent-runner.ts`:
   - Remove the inline `tool(...)` definitions.
   - Call `buildGithubTools(...)` inside the `if (installationId && repoUrl)` block when `owner && repo`. GitHub tools need the GitHub App installation.
   - Call `buildPlausibleTools(...)` at top-level, guarded only by `if (plausibleKey)`. **Do NOT nest this inside the GitHub installation block** — learning `service-tool-registration-scope-guard-20260410.md` documents the exact regression (Plausible users without GitHub installations silently lost all Plausible tools).
   - Spread the returned `tools` into `platformTools` and `toolNames` into `platformToolNames`.
5. **Parity assertion:** after edits, grep `apps/web-platform/server/agent-runner.ts` for `plausible_` and `github_read_ci_status` tool strings — should return zero hits (all moved into the new modules).
6. **GREEN:** `cd apps/web-platform && ./node_modules/.bin/vitest run agent-runner-tools.test canusertool-tiered-gating.test` must pass.

### Phase 2 — Workspace hardening (#2333) + helper extraction (#2334)

1. **RED:** Write `test/workspace-symlink-hardening.test.ts` that creates a clone-simulated workspace with a symlink at `knowledge-base/overview` pointing to `/tmp/outside-<uuid>` (a non-directory) and asserts `provisionWorkspaceWithRepo` (or a test-only direct `scaffoldWorkspaceDefaults` call) throws. Run it — expect RED.
2. Rewrite `ensureDir` in `workspace.ts`. **TOCTOU-safe framing:** we replace `existsSync` with `lstatSync` — a single syscall that returns the existing entry's metadata without following symlinks. We do NOT introduce a pre-flight check followed by a later `mkdirSync`, which would open a CWE-367 TOCTOU window (see learning `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md`). The `try/catch` below preserves the single-lookup guarantee: if `lstatSync` throws `ENOENT`, we `mkdirSync`; otherwise we trust the metadata we already read.

   ```ts
   function ensureDir(dirPath: string): void {
     try {
       const st = lstatSync(dirPath);
       if (!st.isDirectory()) {
         throw new Error(`Refusing to scaffold over non-directory: ${dirPath}`);
       }
     } catch (err) {
       if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
       mkdirSync(dirPath, { recursive: true });
     }
   }
   ```

   **Note:** `mkdirSync(..., { recursive: true })` itself does not follow symlinks at the *terminal* component — but if a parent directory is a symlink, it follows that. This is acceptable for our threat model because the parent directories up to `knowledge-base/` are created by the provisioner itself (workspace root → git clone → scaffold) — user-committed symlinks at intermediate levels would be rejected by `lstatSync` at the enclosing scaffold level before we ever `mkdirSync` a child. The new symlink-hardening test should cover the `knowledge-base/overview` symlink case explicitly.

3. Rename `KNOWLEDGE_BASE_DIRS` → `KNOWLEDGE_BASE_PROJECT_DIRS`. Grep-stable symbol search (`rg '\bKNOWLEDGE_BASE_DIRS\b' apps/web-platform`) must return zero after edit.
4. Extract `scaffoldWorkspaceDefaults(workspacePath, options?)` covering the three duplicated blocks (KB dirs + `.claude/` writes + plugin symlink). Signature: `(workspacePath: string, options: { suppressWelcomeHook?: boolean } = {}) => void`.
5. Replace both inline blocks in `provisionWorkspace` and `provisionWorkspaceWithRepo` with a single call each.
6. **GREEN:** `cd apps/web-platform && ./node_modules/.bin/vitest run workspace workspace-cleanup workspace-error-handling workspace-symlink-hardening` must pass.

### Phase 3 — canUseTool extraction + tests (#2335)

1. **Mock-cascade pre-flight (Phase 0 re-run):** `permission-callback.ts` will be imported by `agent-runner.ts`. Any test that already mocks modules transitively loaded from `agent-runner.ts` must either (a) unmock `permission-callback` explicitly or (b) mock it with a factory that returns a working `createCanUseTool`. Without this, all `canusertool-*` tests that load `agent-runner` for closure access may break.
2. **SDK type import.** Import `PermissionResult` and `CanUseTool` directly from the SDK:

   ```ts
   import type { CanUseTool, PermissionResult } from "@anthropic-ai/claude-agent-sdk";
   ```

   Confirmed shipped at `sdk.d.ts:130` and `sdk.d.ts:1341-1353`. No hand-rolled zod schema needed.
3. **RED:** Write `test/canusertool-decisions.test.ts` with tests for each of the 7 allow branches + deny-by-default. All assertions schema-validate the return against the SDK permission shape:
   - `Write` with workspace-internal path → `{ behavior: "allow", updatedInput: { file_path: "<path>", ... } }`.
   - `Write` with `/etc/passwd` → `{ behavior: "deny", message: /outside workspace/ }`.
   - `Agent` tool → allow shape.
   - `TodoWrite` (safe tool) → allow shape.
   - `AskUserQuestion` (review gate) → allow shape after mocked selection.
   - Platform tool, auto-approve tier (e.g., `mcp__soleur_platform__github_read_ci_status`) → allow shape.
   - Platform tool, gated tier + mocked "Approve" selection → allow shape.
   - Platform tool, gated tier + mocked "Reject" selection → deny shape.
   - Plugin MCP tool (e.g., `mcp__plugin_soleur_cloudflare__<anything>`) → allow shape, given the server is in `pluginMcpServerNames`.
   - Unknown tool → deny-by-default.
   - Run — expect RED (module doesn't exist yet).
4. **Delegation-proof test (negative-space).** Per learning `2026-04-15-negative-space-tests-must-follow-extracted-logic.md`, a substring check that the helper is *mentioned* in `agent-runner.ts` is strictly weaker than what it replaces. Add to `canusertool-decisions.test.ts`:

   ```ts
   // Proves agent-runner DELEGATES to createCanUseTool, not just imports it.
   const agentRunner = readFileSync(
     resolve(__dirname, "../server/agent-runner.ts"),
     "utf-8",
   );
   const invokesFactory = /canUseTool:\s*createCanUseTool\s*\(/.test(agentRunner);
   const hasInlineClosure = /canUseTool:\s*async\s*\(/.test(agentRunner);
   expect(invokesFactory).toBe(true);
   expect(hasInlineClosure).toBe(false); // no inline closure left over
   ```

5. Create `permission-callback.ts`:
   - Export `createCanUseTool(ctx: CanUseToolContext): CanUseTool`. The context interface captures every closure variable the current inline callback uses (workspacePath, userId, conversationId, platformToolNames, pluginMcpServerNames, repoOwner, repoName, session, leaderId, controller.signal, and function refs for `abortableReviewGate`, `sendToClient`, `notifyOfflineUser`, `updateConversationStatus`, `extractReviewGateInput`, `buildReviewGateResponse`, `buildGateMessage`, `getToolTier`, `isFileTool`, `extractToolPath`, `isPathInWorkspace`, `isSafeTool`).
   - Keep the `allow(toolInput)` helper inside this module so both the callback and tests reference one source.
6. Rewrite `agent-runner.ts` to pass the closure vars into `createCanUseTool({...})` rather than inlining the body. Net diff should be negative — the ~200-line inline block contracts to a one-line factory call.
7. **GREEN:** `canusertool-decisions.test canusertool-tiered-gating.test canusertool-caching.test agent-runner-tools.test` must all pass.

### Phase 4 — SOLEUR_DEBUG_PERMISSION_LAYER flag (#2336)

1. **RED:** Write `test/permission-log.test.ts`:
   - Flag unset → 0 debug calls (stub `log.debug`).
   - Flag `"1"` → 1 debug call per invocation with `{ sec: true, layer, tool, decision, reason? }`.
   - Run — expect RED.
2. Create `permission-log.ts`:

   ```ts
   // apps/web-platform/server/permission-log.ts
   import { createChildLogger } from "./logger";

   const log = createChildLogger("permission");

   export type PermissionLayer =
     | "sandbox-hook"
     | "canUseTool-file-tool"
     | "canUseTool-agent"
     | "canUseTool-safe"
     | "canUseTool-review-gate"
     | "canUseTool-platform-auto"
     | "canUseTool-platform-gated"
     | "canUseTool-platform-blocked"
     | "canUseTool-plugin-mcp"
     | "canUseTool-deny-default";

   export function logPermissionDecision(
     layer: PermissionLayer,
     toolName: string,
     decision: "allow" | "deny",
     reason?: string,
   ): void {
     if (process.env.SOLEUR_DEBUG_PERMISSION_LAYER !== "1") return;
     log.debug(
       { sec: true, layer, tool: toolName, decision, reason },
       "permission-decision",
     );
   }
   ```

3. Instrument every allow/deny branch in:
   - `sandbox-hook.ts` (file-tool deny, bash env-access deny, explicit allow).
   - `permission-callback.ts` (all 7 allow branches + deny-by-default + review-gate deny).
4. **GREEN:** `permission-log.test` + all sibling tests remain green.

### Phase 5 — Follow-up note

Add a one-line note to the `canUseTool` callsite (inside `permission-callback.ts`) referencing the learning file that documents the `{ behavior: "allow", updatedInput }` shape requirement. Use symbol-anchor comments (`see allow()`), not line numbers (per `cq-code-comments-symbol-anchors-not-line-numbers`).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `#1662` — `github-tools.ts` and `plausible-tools.ts` exist; `agent-runner.ts` no longer contains inline `tool()` calls for GitHub or Plausible families.
- [ ] `#2333` — `ensureDir` uses `lstatSync` and throws on non-directory entries; `workspace-symlink-hardening.test` asserts `provisionWorkspaceWithRepo` rejects a malicious symlink at `knowledge-base/overview`.
- [ ] `#2334` — `scaffoldWorkspaceDefaults(workspacePath, options?)` exists and is called from both provisioners; `KNOWLEDGE_BASE_DIRS` renamed to `KNOWLEDGE_BASE_PROJECT_DIRS` everywhere; duplicated scaffolding blocks in `provisionWorkspace` and `provisionWorkspaceWithRepo` are gone (one call site each).
- [ ] `#2335` — `canusertool-decisions.test.ts` exists, covers all 7 allow branches + deny-by-default; every assertion schema-validates the SDK permission-result shape.
- [ ] `#2336` — `permission-log.ts` exists; flag `SOLEUR_DEBUG_PERMISSION_LAYER=1` enables a structured debug log per permission decision; every allow/deny site in `sandbox-hook.ts` and `permission-callback.ts` calls `logPermissionDecision`.
- [ ] All tests pass: `cd apps/web-platform && ./node_modules/.bin/vitest run`.
- [ ] `tsc --noEmit` passes.
- [ ] PR body contains `Closes #1662`, `Closes #2333`, `Closes #2334`, `Closes #2335`, `Closes #2336`.

### Post-merge (operator)

- [ ] Verify auto-close fired on all 5 issues.
- [ ] No post-merge infra actions required — pure code-internal refactor.

## Test Scenarios

1. **Symlink traversal (#2333):** Test seeds a temp workspace with a pre-existing symlink at `knowledge-base/overview` → `/tmp/outside-<uuid>`. `provisionWorkspaceWithRepo` (or direct `scaffoldWorkspaceDefaults`) must throw `Refusing to scaffold over non-directory: .../knowledge-base/overview`. A follow-up assertion verifies `/tmp/outside-<uuid>` was NOT modified.
2. **Parity — both provisioners (#2334):** Run `provisionWorkspace(uuid1)` and `provisionWorkspaceWithRepo(uuid2, ...)` (with repo mocked). Assert both produce identical directory layout under `knowledge-base/`, identical `.claude/settings.json`, and identical plugin symlink target. The `suppressWelcomeHook` option behaves identically in both paths.
3. **canUseTool allow-shape (#2335):** Per allow branch, assert `result.behavior === "allow"` AND `result.updatedInput !== undefined` AND `result.updatedInput` deep-equals `toolInput`. This catches the exact bug class of SDK v0.2.80 `ZodError: invalid_union`.
4. **canUseTool deny-shape (#2335):** Per deny branch, assert `result.behavior === "deny"` AND typeof `result.message === "string"` AND `result.message.length > 0`.
5. **Debug flag off (#2336):** Set `delete process.env.SOLEUR_DEBUG_PERMISSION_LAYER`, call `logPermissionDecision(...)`, assert `log.debug` was not invoked.
6. **Debug flag on (#2336):** Set `process.env.SOLEUR_DEBUG_PERMISSION_LAYER = "1"`, call `logPermissionDecision("canUseTool-agent", "Agent", "allow")`, assert `log.debug` was called once with payload matching `{ sec: true, layer: "canUseTool-agent", tool: "Agent", decision: "allow" }`.
7. **Delegation proof (#2335):** Read `apps/web-platform/server/agent-runner.ts` at test time; assert it contains `canUseTool: createCanUseTool(` AND does NOT contain `canUseTool: async (` — per negative-space-tests learning.
8. **Service-tool scope-guard (#1662 regression guard):** Mock a user with `plausibleKey` present but `installationId = null`. Assert `startAgentSession` still registers all three `plausible_*` tools in `platformToolNames`. Directly protects the `service-tool-registration-scope-guard-20260410.md` regression class.
9. **MCP allow-list scope (#1662 + #2335 regression guard):** After extraction, call `createCanUseTool(...)` with `toolName = "mcp__some_future_server__anything"` (a name NOT in `platformToolNames` or `pluginMcpServerNames`). Assert the result is deny-by-default — not auto-allow on the `mcp__` prefix. Protects the `2026-04-06-mcp-tool-canusertool-scope-allowlist.md` regression class.

## Risks & Mitigations

| Risk                                                                                                         | Mitigation                                                                                                                                 |
|--------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Extracting `canUseTool` into a factory may change closure identity for the SDK and break tool resumption.    | Unit-test the factory output by invoking it directly with mocked SDK inputs. Run `agent-runner-tools.test` as a behavior-parity guardrail. |
| Renaming `KNOWLEDGE_BASE_DIRS` could break import sites.                                                      | grep-sweep `apps/web-platform` + `plugins/` for the old name before committing. Targets: zero hits after rename.                           |
| The symlink-hardening change may reject legitimate nested symlink layouts a user committed to their repo.    | The reject is scoped to `ensureDir` calls inside `scaffoldWorkspaceDefaults` (our-managed paths only). User-committed symlinks elsewhere are untouched. |
| `permission-callback.ts` closure context object is wide (15+ refs).                                           | Use a single `CanUseToolContext` interface to document the shape. Refactor opportunity — may reveal further seams.                         |
| Factory extraction + test helper edits must stay in sync (cq-raf-batching-sweep-test-helpers class).          | Target files are not React components; no rAF/timer batching involved. But: ensure any new `vi.mock()` of `permission-callback` in sibling tests uses explicit factory return, not auto-mock (cq-test-mocked-module-constant-import). |
| New import into `agent-runner.ts` cascades mock failures across ~12 test files.                               | Phase 0 pre-flight grep locates every test that loads `agent-runner`. Add `vi.mock("@/server/permission-callback", ...)` + `vi.mock("@/server/permission-log", ...)` entries as a single batch. See learning `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md`. |
| Negative-space delegation check could accept dead imports of `createCanUseTool`.                              | Test pairs a positive regex (`canUseTool:\s*createCanUseTool\(`) with a negative regex (no `canUseTool:\s*async\s*\(` left over). Both must hold. Per learning `2026-04-15-negative-space-tests-must-follow-extracted-logic.md`. |

## Research Insights

Consolidated from 7 relevant learnings in `knowledge-base/project/learnings/` applied to this plan:

**SDK permission-shape (applies to Phase 3):**

- `PermissionResult` is a shipped, importable type — no hand-rolled schema needed. Source: `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:1341-1353`.
- `updatedInput` is optional in the `.d.ts` but was required by the runtime Zod in 0.2.80. The `allow(toolInput)` helper unconditionally echoes it — this is the defensive contract the plan preserves. Tests assert presence regardless of `.d.ts` optionality. Source: learning `2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md`.
- The SDK does NOT cache `canUseTool` results. Debug-log instrumentation on this layer will produce one log per tool invocation in production. Source: learning `2026-03-20-canusertool-caching-verification.md`.

**Symlink / filesystem security (applies to Phase 2):**

- "Add another validation check" can make code less secure. Pre-flight `lstat` followed by later `mkdir`/`open` opens a CWE-367 TOCTOU window. Prefer single-syscall authoritative checks. Source: learning `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md`.
- Knowledge-base files should never be symlinks in the first place — rejecting non-directory entries at scaffold time is simpler and more correct than resolving them through `isPathInWorkspace`. Source: learning `2026-04-07-symlink-escape-recursive-directory-traversal.md`.
- CWE-22/59 path-traversal defense operates in layers: (1) PreToolUse hook (sandbox-hook.ts), (2) canUseTool file-tool check, (3) point-access `isPathInWorkspace`, (4) enumeration skips symlinks. Our refactor preserves all four. Source: learning `2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`.

**Extraction-refactor hygiene (applies to Phases 1 + 3):**

- Shared-import mock cascade: one new import into `agent-runner.ts` can break ~31 tests across ~12 files. Grep the test surface BEFORE adding imports; mirror-add `vi.mock(...)` as a batch. Source: learning `2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md`.
- Negative-space tests must follow extracted logic: when enforcement moves from site A into helper B, tests must prove (a) B is invoked, (b) B's failure result is respected, AND (c) direct assertions on B's invariants exist. Substring-of-identifier is not proof of delegation. Source: learning `2026-04-15-negative-space-tests-must-follow-extracted-logic.md`.
- Service-tool scope guards must be independent. The Plausible-nested-inside-GitHub-guard bug silently hid Plausible tools from users without GitHub installations. Preserve top-level `if (plausibleKey)` guard, independent of `if (installationId && repoUrl)`. Source: learning `service-tool-registration-scope-guard-20260410.md`.
- Allow-check specificity: never use `startsWith("mcp__")` or other prefix patterns in `canUseTool`. Always check against an explicit registered-tool allowlist (`platformToolNames.includes(toolName)`). The extracted `createCanUseTool` must preserve this invariant. Source: learning `2026-04-06-mcp-tool-canusertool-scope-allowlist.md`.

**Observability (applies to Phase 4):**

- `logPermissionDecision` emits `{ sec: true, layer, tool, decision, reason? }` — the `sec: true` flag is the project convention for security-relevant log lines (already present in `agent-runner.ts` log calls at lines 969, 1005, 1084, 1105, 1148, 1164, 1179).
- Pino-to-Sentry mirroring (cq-silent-fallback-must-mirror-to-sentry) does NOT apply here: permission decisions are expected states, not degraded conditions. Debug logs stay in pino; Sentry is reserved for actual fallbacks/errors.

## Non-Goals

- Do NOT implement `conversations_list` or `conversation_archive` tools — those are tracked in a separate follow-up issue (deferred in PR #2571 scope-out).
- Do NOT change the SDK permission model or tier mapping (`tool-tiers.ts` is out of scope).
- Do NOT rename or restructure `sandbox-hook.ts` beyond instrumentation — its shape is dictated by the SDK `HookCallback` type.
- Do NOT bump any dependency versions — this is a pure internal refactor.
- Do NOT add telemetry beyond the opt-in debug log — `logPermissionDecision` stays gated on the env flag.

## Alternatives Considered

1. **Ship each issue as its own PR.** Rejected — the five touch overlapping surface area (agent-runner.ts + workspace.ts) and would merge-conflict with each other. One PR is cheaper for reviewers too (one context swap per area, not five).
2. **Extract canUseTool behind a trait/interface to enable multiple implementations.** Rejected — no second implementation exists or is planned; the factory function is the simplest testable seam.
3. **Use `AbortSignal.timeout` for review-gate abort.** Rejected per `cq-abort-signal-timeout-vs-fake-timers` — existing code uses `controller.signal` passthrough; no change needed here.
4. **Log permission decisions to Sentry instead of pino.** Rejected — these are debug-only bisection logs, not silent fallbacks (no error condition). `cq-silent-fallback-must-mirror-to-sentry` doesn't apply because allow/deny decisions are expected states, not degraded conditions.
