// Canonical SDK Options builder shared between the legacy domain-leader
// runner (`agent-runner.ts startAgentSession`) and the cc-soleur-go
// `realSdkQueryFactory` in `cc-dispatcher.ts`. Drift-guarded by
// `agent-runner-query-options.test.ts` (#2922).
//
// Why a helper: the prior inline `query({ options: {...} })` literal at
// each call site was identical for ~12 fields and divergent for ~5.
// Two consumers maintaining independent literals routinely drift on a
// shared field (sandbox profile, settingSources guard) until a review
// catches it. The helper makes the shared shape canonical; per-call
// divergence flows through the args interface.
//
// Per-call overrides are expressed as INPUT FIELDS, not post-build
// patches. Keeping the canonical shape immutable means a reader of any
// call site sees exactly what the SDK receives.
//
// SubagentStart payload divergence (Enhancement #5): legacy strips
// `[\r\n]`; cc strips control chars + Unicode separators + adds
// `ccPath: true`. Both shapes are intentional. The
// `subagentStartPayloadOverride` arg lets the cc path swap the
// sanitizer + extra log fields without forking the helper.

import type {
  CanUseTool,
  HookCallback,
  Options as SDKOptions,
} from "@anthropic-ai/claude-agent-sdk";

import { buildAgentEnv, type AgentCredential } from "./agent-env";
import { assertTrustedPluginPath } from "./plugin-path";
import { buildAgentSandboxConfig } from "./agent-runner-sandbox-config";
import { createSandboxHook } from "./sandbox-hook";
import { createContextQueriesHook } from "./context-queries-hook";
import { createPhaseSurfaceHook } from "./phase-surface-hook";
import { createGitLockMarkerHook } from "./git-lock-marker-telemetry";
import { createChildLogger } from "./logger";

const log = createChildLogger("agent-query-options");

/** Legacy (`agent-runner.ts`) SubagentStart payload — strips `[\r\n]`. */
function defaultSubagentSanitize(v: unknown): string {
  return String(v ?? "")
    .replace(/[\r\n]/g, " ")
    .slice(0, 200);
}

/**
 * Pinned `disallowedTools` for both legacy + cc paths. Was previously
 * exposed as an `args.disallowedTools` override that no consumer wired;
 * removed per review-finding YAGNI. If a future caller needs a different
 * list, reintroduce the arg with a real test.
 */
const CANONICAL_DISALLOWED_TOOLS: readonly string[] = ["WebSearch", "WebFetch"];

export interface SubagentStartPayloadOverride {
  /** Replaces the default `[\r\n]` strip when the cc path needs Unicode-line + control-char hardening. */
  sanitizer?: (v: unknown) => string;
  /** Extra structured log fields merged into every SubagentStart record (e.g. `{ ccPath: true }`). */
  extraLogFields?: Record<string, unknown>;
  /** Override the log message; default is "Subagent started". */
  logMessage?: string;
}

export interface AgentQueryOptionsArgs {
  workspacePath: string;
  pluginPath: string;
  /**
   * The resolved agent credential (`{ value, scheme }`). Threaded as a
   * single object — NOT a bare key string — so `buildAgentEnv` injects
   * exactly one auth var; a forgotten scheme is a TYPE error, not a silent
   * wrong-var (feat-operator-cc-oauth Phase 3).
   */
  credential: AgentCredential;
  serviceTokens: Record<string, string>;
  /**
   * Optional freshly-minted GitHub App installation token, injected as
   * `GH_TOKEN` into the agent env (Issue A — Concierge gh-auth). Per-call
   * divergent (the cc path mints it per-dispatch; the legacy runner leaves
   * it undefined), so it is NOT part of the shared-field drift snapshot.
   * Never logged. See `buildAgentEnv` `BuildAgentEnvOptions.ghToken`.
   */
  ghToken?: string;
  /**
   * Optional absolute path to the in-sandbox GIT_ASKPASS helper script,
   * written by the cc path under the user's `workspacePath` (plan item 1).
   * When set alongside `ghToken`, threaded into `buildAgentEnv` so raw `git`
   * push/fetch/pull in the sandbox authenticates. The askpass token IS the
   * installation token (`ghToken`), passed as `gitInstallationToken`.
   * Per-call divergent (cc path sets it per-dispatch; legacy runner leaves it
   * undefined), so NOT part of the shared-field drift snapshot. Never logged.
   */
  gitAskpassScriptPath?: string;
  systemPrompt: string;
  /** SDK chain step 5 — the canUseTool callback. Required. */
  // biome-ignore lint/suspicious/noExplicitAny: SDK CanUseTool is a typed callable; helper accepts the SDK's type
  canUseTool: CanUseTool;
  /** Defaults to "claude-sonnet-5" (matches both legacy + cc paths today). */
  model?: string;
  /** Defaults to "default" (matches both paths). */
  permissionMode?: SDKOptions["permissionMode"];
  /** When set, threads through to options.resume. */
  resumeSessionId?: string;
  /** Per-call MCP server registration. Legacy: `{ soleur_platform: ... }` when platform tools register; cc: `{}`. */
  mcpServers?: Record<string, unknown>;
  /** Per-call allowedTools list (legacy: platform tool names + plugin MCP wildcards; cc: omitted at V1). */
  allowedTools?: string[];
  /**
   * Per-call disallowedTools extension (#3338). Merged with the canonical
   * `[WebSearch, WebFetch]` list. The cc path passes `["Edit", "Write"]`
   * (`CC_PATH_DISALLOWED_TOOLS`, cc-dispatcher.ts) so the model cannot emit
   * those tools — Bash is intentionally NOT disallowed (it flows through the
   * permission-callback Bash gate / safe-bash / autonomous bypass instead).
   * `allowedTools` is auto-approve only per SDK semantics (sdk.d.ts:858-862),
   * so the only way to actually restrict the model's tool surface is
   * `disallowedTools` (or the `tools` option). Legacy path leaves this undefined.
   */
  extraDisallowedTools?: readonly string[];
  /** Legacy: 50; cc: omitted (cost-cap is enforced at the runner level). */
  maxTurns?: number;
  /** Legacy: 5.0; cc: omitted. */
  maxBudgetUsd?: number;
  /** Override the default SubagentStart hook payload (cc path uses Unicode-hardened sanitize + ccPath: true). */
  subagentStartPayloadOverride?: SubagentStartPayloadOverride;
  /**
   * Cancellation surface for the SDK iterator and any in-flight HTTP
   * fetch / hook callbacks (`abortController?: AbortController` per
   * `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:816`). Wired
   * by `startAgentSession` in `agent-runner.ts` so user-initiated Stop
   * propagates beyond the for-await loop boundary
   * (feat-abort-conversation-web PR1, plan §1.6).
   */
  abortController?: AbortController;
  /**
   * Opt in to the L3 phase-surface hint (#5772 lever 1, ADR-070). When true, a
   * fail-open `PostToolUse(Skill)` hook injects the current phase's additive
   * surface hint as `additionalContext`. ONLY the cc-soleur-go Concierge router
   * (the eval-covered workflow-routing path) sets this; the legacy domain-leader
   * runner leaves it undefined (no workflow-phase concept), so the fail-CLOSED
   * deferred lever 2 never inherits a "both-callers-always-on" default. Additive
   * hint only — never touches `canUseTool`/`disallowedTools`.
   */
  enablePhaseSurfaceHint?: boolean;
  /**
   * Opt in to the declarative `context_queries` context-injection hook (#6046,
   * ADR-086 — the web-parity port of the CLI `.claude/hooks/skill-context-queries.sh`).
   * When true, a fail-open `PostToolUse(Skill)` hook resolves the invoked skill's
   * SKILL.md `context_queries:` frontmatter to committed `knowledge-base/`
   * artifacts and injects a POINTER (a Read-directive) as `additionalContext`.
   * Registered INDEPENDENTLY of `enablePhaseSurfaceHint` (both use matcher
   * "Skill"; the SDK delivers both `additionalContext` values). ONLY the
   * cc-soleur-go Concierge router sets this; the legacy domain-leader runner
   * leaves it undefined so the AC5 drift snapshot stays byte-identical. Additive
   * pointer only — never touches `canUseTool`/`disallowedTools`.
   */
  enableContextQueries?: boolean;
  /**
   * TR3 tool-attempt telemetry (#5843, ADR-070 amendment). When set, this single
   * fail-open `PreToolUse` hook (minted per query by `createToolAttemptCollector`
   * in the cc dispatcher) is registered as a SEPARATE, matcher-less PreToolUse
   * entry — matcher-less so it captures the FULL tool surface (`Skill`/`Task`/
   * `mcp__*`/`Read`/`Bash`/...), not just the sandbox subset. ONLY the
   * cc-soleur-go path passes it (its `flush()` fires from `handleCcCloseQuery`);
   * the legacy runner leaves it undefined so the AC5 drift snapshot stays
   * byte-identical. Never mutates `canUseTool`/`disallowedTools`; the collector's
   * hook always returns `{}` (observe-only). Passed as the hook (not a boolean)
   * because the paired `flush()` handle must escape to the close chokepoint.
   */
  toolAttemptPreToolUseHook?: HookCallback;
}

/**
 * Build the canonical SDK Options object both consumers pass to
 * `query({ prompt, options })`. The returned object is structurally
 * identical for shared fields; divergent fields originate from `args`.
 *
 * Drift-guard: `agent-runner-query-options.test.ts` snapshots the
 * shared-field stable serialization. A field drop here trips that test.
 */
export function buildAgentQueryOptions(
  args: AgentQueryOptionsArgs,
  // biome-ignore lint/suspicious/noExplicitAny: SDK Options has many optional fields not all present in our subset
): SDKOptions & Record<string, any> {
  const subagentOverride = args.subagentStartPayloadOverride;
  const sanitizeFn = subagentOverride?.sanitizer ?? defaultSubagentSanitize;
  const extraLogFields = subagentOverride?.extraLogFields ?? {};
  const logMessage = subagentOverride?.logMessage ?? "Subagent started";

  // Loaded-gun guard, computed ONCE (Slice A + Slice B). Both factories source
  // args.pluginPath from getPluginPath() (an absolute /app/ platform path).
  // assertTrustedPluginPath throws LOUDLY if a future regression threads a
  // connected-repo workspace path — which would both (a) re-execute the
  // untrusted repo's hooks.json in-process AND (b) inject an untrusted
  // CLAUDE_PLUGIN_ROOT the deployed skills would shell out to. Validating BEFORE
  // buildAgentEnv (below) means an untrusted value fails CLOSED — it can never
  // reach the agent env NOR the plugins: binding of a live dispatch (AC7b).
  // Test-tolerant (mirrors getPluginPath's VITEST/NODE_ENV=test bypass).
  const trustedPluginPath = assertTrustedPluginPath(args.pluginPath);

  // biome-ignore lint/suspicious/noExplicitAny: SDK Options is a wide union; partial-shape build avoids re-asserting every key
  const opts: any = {
    cwd: args.workspacePath,
    model: args.model ?? "claude-sonnet-5",
    permissionMode: args.permissionMode ?? "default",
    // settingSources: [] — defense-in-depth alongside `patchWorkspacePermissions`.
    // Prevents the SDK from loading `.claude/settings.json` whose
    // `permissions.allow` would bypass `canUseTool` (chain step 4 before step 5).
    settingSources: [],
    // Load-bearing for the SDK `tool_progress` mid-tool heartbeats that re-arm
    // the per-block idle watchdog in BOTH runners (soleur-go-runner.ts:2194 and
    // agent-runner.ts:1901). Flipping this off silently stops those heartbeats
    // and resurrects premature `runner_runaway` on long single-tool turns.
    includePartialMessages: true,
    disallowedTools: [
      ...CANONICAL_DISALLOWED_TOOLS,
      ...(args.extraDisallowedTools ?? []),
    ],
    systemPrompt: args.systemPrompt,
    env: buildAgentEnv(args.credential, args.serviceTokens, {
      ghToken: args.ghToken,
      // In-sandbox raw-git credential path (item 1). The askpass token IS the
      // installation token (`ghToken`); `buildAgentEnv` injects the GIT_* set
      // only when BOTH the path and token are present (both-or-nothing).
      gitAskpassScriptPath: args.gitAskpassScriptPath,
      gitInstallationToken: args.ghToken,
      // Deployed plugin root → CLAUDE_PLUGIN_ROOT for the agent's `bash`
      // shell-outs (Slice B). The assertTrustedPluginPath-validated value (an
      // absolute /app/ platform path) is threaded so the deployed skills'
      // `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` runs the platform copy, never
      // the untrusted connected-repo copy. Proven to reach the bwrap-sandboxed
      // bash via env inheritance (F2, AC7a — plugin-root-propagation gate).
      pluginPath: trustedPluginPath,
    }),
    // Sandbox literal lives in `buildAgentSandboxConfig` so legacy + cc
    // share the same shape — identical except for the token-derived
    // `network.allowedDomains` below (drift-guarded by
    // `agent-runner-helpers.test.ts`).
    //
    // GitHub egress is DERIVED from ghToken presence — both-or-nothing,
    // same family as the askpass both-or-nothing guard in buildAgentEnv.
    // An entitled installation token without network egress is the
    // #5041-followup bug (in-sandbox gh dead at the proxy with
    // `Post "...": Forbidden`); egress without a token would be
    // unauthenticated surface for nothing. Deriving (not a separate flag)
    // makes the half-wired state unrepresentable. The legacy
    // startAgentSession never passes ghToken → its sandbox stays fully
    // closed (fail-closed, zero behavior change).
    sandbox: buildAgentSandboxConfig(args.workspacePath, {
      allowGithubEgress: Boolean(args.ghToken),
    }),
    // Loaded-gun guard: both factories source args.pluginPath from getPluginPath()
    // (an absolute /app/ platform path). assertTrustedPluginPath fails LOUDLY if a
    // future regression threads a connected-repo workspace path here — which would
    // silently re-execute the untrusted repo's hooks.json in-process (the
    // connected-repo-shadow security hole this PR closes). Test-tolerant.
    plugins: [{ type: "local" as const, path: trustedPluginPath }],
    hooks: {
      PreToolUse: [
        {
          // LS and NotebookEdit added for #891 path validation.
          // NotebookRead included defensively (SDK may route via Read).
          matcher: "Read|Write|Edit|Glob|Grep|LS|NotebookRead|NotebookEdit|Bash",
          hooks: [createSandboxHook(args.workspacePath)],
        },
        // TR3 tool-attempt telemetry (#5843, ADR-070). Separate gated entry — NOT
        // a modification of the sandbox matcher (preserves the AC5 drift snapshot).
        // Matcher-less so it captures the FULL surface (`Skill`/`Task`/`mcp__*`/
        // `Read`/`Bash`/...) — the sandbox regex above only lists the fs/exec
        // subset. Observe-only + fail-open (always returns `{}`). cc-only opt-in.
        ...(args.toolAttemptPreToolUseHook
          ? [{ hooks: [args.toolAttemptPreToolUseHook] }]
          : []),
      ],
      // Defense-in-depth: log subagent spawns for audit visibility.
      // If a future SDK version stops routing subagent tool calls
      // through canUseTool, these logs provide evidence. See #910.
      SubagentStart: [
        {
          hooks: [
            async (input: unknown) => {
              const subInput = input as Record<string, unknown>;
              log.info(
                {
                  sec: true,
                  agentId: sanitizeFn(subInput.agent_id),
                  agentType: sanitizeFn(subInput.agent_type),
                  ...extraLogFields,
                },
                logMessage,
              );
              return {};
            },
          ],
        },
      ],
      // PostToolUse hooks (all fail-open, observe/additive-only — never touch the
      // tool floor):
      //   - ALWAYS: the #4826 git-lock marker mirror (matcher "Bash"). Observe-only;
      //     re-emits the in-sandbox SOLEUR_GIT_LOCK_*/"worktree wedge" markers to the
      //     server-side logger (→ Better Stack + Sentry breadcrumb), closing ADR-081's
      //     "blind sandbox stdout, not mirrored to any queryable sink" gap. Path-agnostic
      //     (a wedge can happen on any dispatch), so it is unconditional, not opt-in.
      //   - Per-caller opt-ins (matcher "Skill"), each additive `additionalContext`:
      //     the L3 phase-surface hint (#5772 lever 1, ADR-070) and the declarative
      //     context_queries injection (#6046, ADR-086). Both use matcher "Skill"; the SDK
      //     runs parallel matching hooks and delivers both values. Only the cc-soleur-go
      //     Concierge router opts in.
      PostToolUse: [
        { matcher: "Bash", hooks: [createGitLockMarkerHook(args.workspacePath)] },
        ...(args.enablePhaseSurfaceHint
          ? [{ matcher: "Skill", hooks: [createPhaseSurfaceHook()] }]
          : []),
        ...(args.enableContextQueries
          ? [{ matcher: "Skill", hooks: [createContextQueriesHook(args.workspacePath)] }]
          : []),
      ],
    },
    canUseTool: args.canUseTool,
  };

  if (args.resumeSessionId) opts.resume = args.resumeSessionId;
  if (args.mcpServers !== undefined) opts.mcpServers = args.mcpServers;
  if (args.allowedTools !== undefined) opts.allowedTools = args.allowedTools;
  if (args.maxTurns !== undefined) opts.maxTurns = args.maxTurns;
  if (args.maxBudgetUsd !== undefined) opts.maxBudgetUsd = args.maxBudgetUsd;
  if (args.abortController !== undefined) opts.abortController = args.abortController;

  return opts;
}
