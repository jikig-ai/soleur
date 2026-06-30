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
  Options as SDKOptions,
} from "@anthropic-ai/claude-agent-sdk";

import { buildAgentEnv, type AgentCredential } from "./agent-env";
import { buildAgentSandboxConfig } from "./agent-runner-sandbox-config";
import { createSandboxHook } from "./sandbox-hook";
import { createPhaseSurfaceHook } from "./phase-surface-hook";
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
  /** Defaults to "claude-sonnet-4-6" (matches both legacy + cc paths today). */
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

  // biome-ignore lint/suspicious/noExplicitAny: SDK Options is a wide union; partial-shape build avoids re-asserting every key
  const opts: any = {
    cwd: args.workspacePath,
    model: args.model ?? "claude-sonnet-4-6",
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
    plugins: [{ type: "local" as const, path: args.pluginPath }],
    hooks: {
      PreToolUse: [
        {
          // LS and NotebookEdit added for #891 path validation.
          // NotebookRead included defensively (SDK may route via Read).
          matcher: "Read|Write|Edit|Glob|Grep|LS|NotebookRead|NotebookEdit|Bash",
          hooks: [createSandboxHook(args.workspacePath)],
        },
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
      // L3 phase-surface hint (#5772 lever 1, ADR-070). Per-caller opt-in: only
      // the cc-soleur-go Concierge router enables it (the eval-covered path).
      // Fail-open additive `additionalContext` only; registered conditionally so
      // the legacy path stays zero-change and the fail-CLOSED lever 2 does not
      // inherit a both-callers default.
      ...(args.enablePhaseSurfaceHint
        ? { PostToolUse: [{ matcher: "Skill", hooks: [createPhaseSurfaceHook()] }] }
        : {}),
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
