import { tool } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod/v4";
import { resolveBashAutonomous } from "./resolve-bash-autonomous";
import { setBashAutonomous } from "./set-bash-autonomous";

// Issue B part 2 — agent-native parity for the autonomous-mode toggle (AC18).
//
// Whatever a user can see/toggle in Settings > Privacy, the agent can read/set
// too. The READ tool is auto-approve (read-only); the SET tool is `gated` in
// tool-tiers.ts — flipping an approval-bypass MUST itself require a review-gate
// even for the agent. The owner check lives in the SECURITY DEFINER RPC, so a
// non-owner agent call raises and surfaces as an error result.
//
// ASYMMETRY (documented to prevent a false "missing tool" review flag): these
// tools register on the LEGACY `agent-runner.ts` platform-tools surface where
// tool-capable domain-leader agents run. The cc-router (`cc-dispatcher`) wires
// `platformToolNames: []` by design and exposes NO platform MCP tools, so the
// pair is intentionally absent there. The cc-router toggles via the HTTP route
// + UI; these MCP tools are the agent-facing equivalent on the leader surface.

interface BuildWorkspaceSettingsToolsOpts {
  userId: string;
}

type ToolTextResponse = {
  content: Array<{ type: "text"; text: string }>;
  isError?: true;
};

function textResponse(payload: unknown, isError = false): ToolTextResponse {
  const body: ToolTextResponse = {
    content: [{ type: "text", text: JSON.stringify(payload) }],
  };
  if (isError) body.isError = true;
  return body;
}

export function buildWorkspaceSettingsTools(
  opts: BuildWorkspaceSettingsToolsOpts,
) {
  const { userId } = opts;

  return {
    tools: [
      tool(
        "workspace_get_autonomous",
        "Read whether the active workspace's Concierge 'autonomous mode' is ON. " +
          "When ON, the Concierge auto-approves every non-blocked Bash command " +
          "(skips the per-command Approve/Deny gate; the command blocklist still " +
          "applies). Read-only. Returns { autonomous: boolean }. Defaults to false " +
          "(fail-closed) on any error or for non-members.",
        {},
        async () => {
          try {
            const autonomous = await resolveBashAutonomous(userId);
            return textResponse({ autonomous });
          } catch (err) {
            return textResponse(
              {
                error: "read_failed",
                message: err instanceof Error ? err.message : "unknown",
              },
              true,
            );
          }
        },
      ),
      tool(
        "workspace_set_autonomous",
        "Set the active workspace's Concierge 'autonomous mode'. " +
          "RISK: enabling this is an approval-bypass on a code-executing surface — " +
          "the Concierge will run any non-blocked command without asking, so a " +
          "prompt-injected agent (malicious issue body / repo file) could delete " +
          "files or leak data with no approval step. Only enable for fully trusted " +
          "repos and workspaces. OWNER-ONLY: a non-owner caller is rejected. " +
          "Returns { autonomous: boolean }. Error codes: 403 not_authorized_or_failed.",
        {
          value: z
            .boolean()
            .describe("true to enable autonomous mode, false to disable"),
        },
        async (input) => {
          try {
            const autonomous = await setBashAutonomous(userId, input.value);
            return textResponse({ autonomous });
          } catch (err) {
            return textResponse(
              {
                error: "not_authorized_or_failed",
                code: "403",
                message: err instanceof Error ? err.message : "unknown",
              },
              true,
            );
          }
        },
      ),
    ],
    toolNames: [
      "mcp__soleur_platform__workspace_get_autonomous",
      "mcp__soleur_platform__workspace_set_autonomous",
    ] as const,
  };
}
