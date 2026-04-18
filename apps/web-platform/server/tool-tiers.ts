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
 * Tools not in this map default to "gated" in getToolTier()
 * (fail-closed: new tools require explicit tier assignment).
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

  // KB share tools (#2309): list is read-only, create/revoke are
  // user-visible side effects (public URL / permanent revocation) → gated.
  "mcp__soleur_platform__kb_share_list": "auto-approve",
  "mcp__soleur_platform__kb_share_create": "gated",
  "mcp__soleur_platform__kb_share_revoke": "gated",
  // Preview (#2322): metadata-only (no bytes, no state change) — same
  // tier as kb_share_list. Gating it would produce consent fatigue without
  // a security benefit.
  "mcp__soleur_platform__kb_share_preview": "auto-approve",
};

/**
 * Look up the tier for a platform MCP tool.
 * Returns "gated" for tools not in the map (fail-closed: new tools
 * require explicit tier assignment before they can auto-approve).
 */
export function getToolTier(toolName: string): ToolTier {
  return TOOL_TIER_MAP[toolName] ?? "gated";
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
    case "kb_share_create":
      return `Agent wants to create a public share link for **${toolInput.documentPath ?? "unknown"}**. Allow?`;
    case "kb_share_revoke": {
      const raw = String(toolInput.token ?? "unknown");
      const preview = raw.length > 12 ? `${raw.slice(0, 12)}…` : raw;
      return `Agent wants to revoke share token **${preview}**. This is permanent. Allow?`;
    }
    default:
      return `Agent wants to use **${shortName}**. Allow?`;
  }
}
