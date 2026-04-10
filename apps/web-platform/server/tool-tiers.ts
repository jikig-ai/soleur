/**
 * Tool tier classification for platform MCP tools (#1926).
 *
 * Extracted from agent-runner.ts for unit testability (following the
 * tool-path-checker.ts and review-gate.ts extraction pattern).
 *
 * Tiers:
 * - auto-approve: read-only tools, pass through without review gate
 * - gated: write tools, require founder confirmation via review gate
 * - blocked: destructive patterns, rejected unconditionally
 */

export type ToolTier = "auto-approve" | "gated" | "blocked";

/**
 * Canonical tier assignments for all platform MCP tools.
 * Tools not in this map default to "auto-approve" in getToolTier()
 * because they are already validated by platformToolNames inclusion.
 */
export const TOOL_TIER_MAP: Record<string, ToolTier> = {
  // Phase 2: Read CI status (auto-approve — read-only)
  "mcp__soleur_platform__github_read_ci_status": "auto-approve",
  "mcp__soleur_platform__github_read_workflow_logs": "auto-approve",

  // Phase 3: Trigger workflows (gated — write action)
  "mcp__soleur_platform__github_trigger_workflow": "gated",

  // Phase 4: Push branches and open PRs (gated — write action)
  "mcp__soleur_platform__github_push_branch": "gated",
  "mcp__soleur_platform__create_pull_request": "gated",
};

/**
 * Look up the tier for a platform MCP tool.
 * Returns "auto-approve" for tools not in the map (safe default for
 * platform tools already validated by platformToolNames inclusion).
 */
export function getToolTier(toolName: string): ToolTier {
  return TOOL_TIER_MAP[toolName] ?? "auto-approve";
}

/**
 * Build a human-readable review gate message for a gated tool invocation.
 * The message should clearly describe what the agent wants to do so the
 * founder can make an informed approval decision.
 */
export function buildGateMessage(
  toolName: string,
  toolInput: Record<string, unknown>,
): string {
  const shortName = toolName.replace("mcp__soleur_platform__", "");

  switch (shortName) {
    case "github_trigger_workflow":
      return `Agent wants to trigger workflow **${toolInput.workflow_id ?? "unknown"}** on branch **${toolInput.ref ?? "unknown"}**. Allow?`;
    case "github_push_branch":
      return `Agent wants to push to branch **${toolInput.branch ?? "unknown"}**. Allow?`;
    case "create_pull_request":
      return `Agent wants to open PR: **${toolInput.title ?? "untitled"}** (${toolInput.base ?? "main"} ← ${toolInput.head ?? "unknown"}). Allow?`;
    default:
      return `Agent wants to use **${shortName}**. Allow?`;
  }
}
