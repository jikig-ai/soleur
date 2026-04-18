// canUseTool callback factory — extracted from the inline closure that
// previously lived in `agent-runner.ts`. Extraction lets unit tests
// exercise the 7 allow branches + deny-by-default without booting an
// entire SDK session (see #2335).
//
// The SDK's permission chain has 5 steps (hooks → deny rules →
// permission mode → allow rules → canUseTool). This factory implements
// step 5; the earlier layers are configured elsewhere (PreToolUse hook,
// settingSources: [], allowedTools, sandbox deny list).
//
// Allow-path contract: SDK v0.2.80 rejected bare `{ behavior: "allow" }`
// with `ZodError: invalid_union`. The `allow(toolInput)` helper
// unconditionally echoes the input as `updatedInput` — behaviorally a
// no-op, satisfies both permissive and strict variants of the schema.
// See learning 2026-04-15-sdk-v0.2.80-zoderror-allow-shape.md.

import { randomUUID } from "crypto";
import type {
  CanUseTool,
  PermissionResult,
} from "@anthropic-ai/claude-agent-sdk";

import { createChildLogger } from "./logger";
import type { AgentSession, ReviewGateInput } from "./review-gate";
import type { NotificationPayload } from "./notifications";
import type { WSMessage } from "@/lib/types";

const log = createChildLogger("agent");

// Exported so the inline-closure deletion assertion (negative-space
// delegation test) does not give false positives — see
// canusertool-decisions.test.ts.
export function allow(toolInput: Record<string, unknown>): Extract<PermissionResult, { behavior: "allow" }> {
  return { behavior: "allow" as const, updatedInput: toolInput };
}

export interface CanUseToolContext {
  userId: string;
  conversationId: string;
  leaderId: string | undefined;
  workspacePath: string;
  /** Registered platform tool names (full `mcp__soleur_platform__*`). Allowlist. */
  platformToolNames: string[];
  /** Plugin MCP server names from plugin.json. Allowlist for `mcp__plugin_soleur_<server>__*`. */
  pluginMcpServerNames: string[];
  repoOwner: string;
  repoName: string;
  session: AgentSession;
  controllerSignal: AbortSignal;
  // Async helpers — injected so tests can substitute fakes without
  // reaching into global module state.
  abortableReviewGate: (
    session: AgentSession,
    gateId: string,
    signal: AbortSignal,
    timeoutMs: number | undefined,
    options: string[],
  ) => Promise<string>;
  sendToClient: (userId: string, payload: WSMessage) => boolean;
  notifyOfflineUser: (
    userId: string,
    payload: NotificationPayload,
  ) => Promise<void>;
  updateConversationStatus: (
    conversationId: string,
    status: string,
  ) => Promise<void>;
  extractReviewGateInput: (input: Record<string, unknown>) => ReviewGateInput;
  buildReviewGateResponse: (
    input: Record<string, unknown>,
    selection: string,
  ) => Record<string, unknown>;
  buildGateMessage: (toolName: string, input: Record<string, unknown>) => string;
  getToolTier: (toolName: string) => "auto-approve" | "gated" | "blocked";
  isFileTool: (name: string) => boolean;
  extractToolPath: (input: Record<string, unknown>) => string | null;
  isPathInWorkspace: (path: string, workspacePath: string) => boolean;
  isSafeTool: (name: string) => boolean;
  /** Tools whose input parameter names the SDK may have renamed (#891 guard). */
  unverifiedParamTools: readonly string[];
}

export function createCanUseTool(ctx: CanUseToolContext): CanUseTool {
  return async (toolName, toolInput, options): Promise<PermissionResult> => {
    const subagentCtx = options.agentID ? ` [subagent=${options.agentID}]` : "";

    // Defense-in-depth: catch any file tool that bypasses PreToolUse hooks.
    // Hooks are the primary enforcement (layer 1); this is layer 2. See #891.
    if (ctx.isFileTool(toolName)) {
      const filePath = ctx.extractToolPath(toolInput);
      if (filePath && !ctx.isPathInWorkspace(filePath, ctx.workspacePath)) {
        return {
          behavior: "deny" as const,
          message: `Access denied: outside workspace${subagentCtx}`,
        };
      }
      if (
        !filePath &&
        ctx.unverifiedParamTools.includes(toolName) &&
        Object.keys(toolInput).length > 0
      ) {
        log.warn(
          { sec: true, toolName, inputKeys: Object.keys(toolInput) },
          "Tool invoked without recognized path parameter; SDK may have changed parameter names (see #891)",
        );
      }
      return allow(toolInput);
    }

    // Review gates: intercept AskUserQuestion
    if (toolName === "AskUserQuestion") {
      const gateId = randomUUID();
      const gate = ctx.extractReviewGateInput(toolInput);

      if (gate.isNewSchema) {
        const questions = toolInput.questions as unknown[];
        if (Array.isArray(questions) && questions.length > 1) {
          log.warn(
            { questionCount: questions.length },
            "AskUserQuestion received multiple questions; only the first is surfaced",
          );
        }
      }

      // Parse step progress from header (e.g., "Step 2 of 6: Configure DNS")
      const stepMatch = gate.header?.match(/^Step (\d+) of (\d+): .+$/);
      const stepProgress = stepMatch
        ? { current: Number(stepMatch[1]), total: Number(stepMatch[2]) }
        : undefined;

      const gateDelivered = ctx.sendToClient(ctx.userId, {
        type: "review_gate",
        gateId,
        question: gate.question,
        header: gate.header,
        options: gate.options,
        descriptions: Object.keys(gate.descriptions).length > 0
          ? gate.descriptions
          : undefined,
        stepProgress,
      });

      if (!gateDelivered) {
        ctx.notifyOfflineUser(ctx.userId, {
          type: "review_gate",
          conversationId: ctx.conversationId,
          agentName: ctx.leaderId ?? "Agent",
          question: gate.question,
        }).catch((err) =>
          log.error({ userId: ctx.userId, err }, "Offline notification failed"),
        );
      }

      await ctx.updateConversationStatus(ctx.conversationId, "waiting_for_user");

      const selection = await ctx.abortableReviewGate(
        ctx.session,
        gateId,
        ctx.controllerSignal,
        undefined,
        gate.options,
      );

      await ctx.updateConversationStatus(ctx.conversationId, "active");

      return {
        behavior: "allow" as const,
        updatedInput: ctx.buildReviewGateResponse(toolInput, selection),
      };
    }

    // Agent tool: spawns subagents under the same SDK sandbox. Explicit
    // allow (replaces prior SAFE_TOOLS auto-allow) for auditability. See #910.
    if (toolName === "Agent") {
      if (subagentCtx) {
        log.info(
          { sec: true, agentId: options.agentID },
          "Agent tool invoked by subagent",
        );
      }
      return allow(toolInput);
    }

    // Safe SDK tools (no filesystem-path inputs). See tool-path-checker.ts.
    if (ctx.isSafeTool(toolName)) {
      return allow(toolInput);
    }

    // Tiered gating for in-process MCP server tools (#1926). Scoped to
    // `platformToolNames` (not blanket mcp__ prefix) so future MCP servers
    // never auto-allow without explicit review.
    if (ctx.platformToolNames.includes(toolName)) {
      const tier = ctx.getToolTier(toolName);

      if (tier === "blocked") {
        log.info(
          {
            sec: true,
            tool: toolName,
            tier,
            decision: "deny",
            repo: `${ctx.repoOwner}/${ctx.repoName}`,
          },
          "Platform tool blocked",
        );
        return {
          behavior: "deny" as const,
          message: "This action is not allowed from cloud agents",
        };
      }

      if (tier === "gated") {
        const gateId = randomUUID();
        const question = ctx.buildGateMessage(toolName, toolInput);

        const toolGateDelivered = ctx.sendToClient(ctx.userId, {
          type: "review_gate",
          gateId,
          question,
          options: ["Approve", "Reject"],
        });

        if (!toolGateDelivered) {
          ctx.notifyOfflineUser(ctx.userId, {
            type: "review_gate",
            conversationId: ctx.conversationId,
            agentName: ctx.leaderId ?? "Agent",
            question,
          }).catch((err) =>
            log.error(
              { userId: ctx.userId, err },
              "Offline notification failed (tool gate)",
            ),
          );
        }

        await ctx.updateConversationStatus(ctx.conversationId, "waiting_for_user");

        const selection = await ctx.abortableReviewGate(
          ctx.session,
          gateId,
          options.signal,
          undefined,
          ["Approve", "Reject"],
        );

        await ctx.updateConversationStatus(ctx.conversationId, "active");

        const decision = selection === "Approve" ? "approved" : "rejected";
        log.info(
          {
            sec: true,
            tool: toolName,
            tier,
            decision,
            repo: `${ctx.repoOwner}/${ctx.repoName}`,
          },
          "Platform tool gated",
        );

        if (selection !== "Approve") {
          return {
            behavior: "deny" as const,
            message: "User rejected the action",
          };
        }

        return allow(toolInput);
      }

      // auto-approve: read-only tools pass through
      log.info(
        {
          sec: true,
          tool: toolName,
          tier,
          decision: "auto-approved",
          repo: `${ctx.repoOwner}/${ctx.repoName}`,
        },
        "Platform tool auto-approved",
      );
      return allow(toolInput);
    }

    // Plugin MCP tools — allow only when the server is registered in
    // plugin.json. Explicit server-name matching (not blanket mcp__ prefix).
    // See learning: 2026-04-06-mcp-tool-canusertool-scope-allowlist.md
    if (
      toolName.startsWith("mcp__plugin_soleur_") &&
      ctx.pluginMcpServerNames.some((server) =>
        toolName.startsWith(`mcp__plugin_soleur_${server}__`),
      )
    ) {
      log.info(
        { sec: true, toolName, agentId: options.agentID },
        "Plugin MCP tool invoked",
      );
      return allow(toolInput);
    }

    // Deny-by-default: block unrecognized tools
    return {
      behavior: "deny" as const,
      message: "Tool not permitted in this environment",
    };
  };
}
