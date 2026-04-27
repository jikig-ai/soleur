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

import { buildAgentEnv } from "./agent-env";
import { buildAgentSandboxConfig } from "./agent-runner-sandbox-config";
import { createSandboxHook } from "./sandbox-hook";
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
  apiKey: string;
  serviceTokens: Record<string, string>;
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
   * NOTE: `disallowedTools` is intentionally NOT exposed as an arg.
   * Both legacy + cc paths share `["WebSearch", "WebFetch"]` and no
   * consumer overrides it today. Pinned as a constant inside the helper
   * (CANONICAL_DISALLOWED_TOOLS below). If a future caller needs a
   * different list, re-introduce the arg with a real test — see review
   * fix-inline #2954.
   */
  /** Legacy: 50; cc: omitted (cost-cap is enforced at the runner level). */
  maxTurns?: number;
  /** Legacy: 5.0; cc: omitted. */
  maxBudgetUsd?: number;
  /** Override the default SubagentStart hook payload (cc path uses Unicode-hardened sanitize + ccPath: true). */
  subagentStartPayloadOverride?: SubagentStartPayloadOverride;
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
    includePartialMessages: true,
    disallowedTools: [...CANONICAL_DISALLOWED_TOOLS],
    systemPrompt: args.systemPrompt,
    env: buildAgentEnv(args.apiKey, args.serviceTokens),
    // Sandbox literal lives in `buildAgentSandboxConfig` so legacy + cc
    // share the same shape verbatim (drift-guarded by
    // `agent-runner-helpers.test.ts`).
    sandbox: buildAgentSandboxConfig(args.workspacePath),
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
    },
    canUseTool: args.canUseTool,
  };

  if (args.resumeSessionId) opts.resume = args.resumeSessionId;
  if (args.mcpServers !== undefined) opts.mcpServers = args.mcpServers;
  if (args.allowedTools !== undefined) opts.allowedTools = args.allowedTools;
  if (args.maxTurns !== undefined) opts.maxTurns = args.maxTurns;
  if (args.maxBudgetUsd !== undefined) opts.maxBudgetUsd = args.maxBudgetUsd;

  return opts;
}
