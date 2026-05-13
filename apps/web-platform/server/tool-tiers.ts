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
  // cc-router (#2909): Tier 1 candidate (Phase 2 promotion via #3722)
  "mcp__soleur_platform__github_read_ci_status": "auto-approve",
  "mcp__soleur_platform__github_read_workflow_logs": "auto-approve",

  // Issue/PR reads (#2843): all auto-approve — read-only, narrowed responses.
  // cc-router (#2909): Tier 1 candidates (Phase 2 promotion via #3722)
  "mcp__soleur_platform__github_read_issue": "auto-approve",
  "mcp__soleur_platform__github_read_issue_comments": "auto-approve",
  "mcp__soleur_platform__github_read_pr": "auto-approve",
  "mcp__soleur_platform__github_list_pr_comments": "auto-approve",

  // Phase 3: Trigger workflows (gated — write action)
  // cc-router (#2909): Tier 2 candidate (Phase 2 via #3722; review-gate UX integration required)
  "mcp__soleur_platform__github_trigger_workflow": "gated",

  // Phase 4: Push branches and open PRs (gated — write action)
  // cc-router (#2909): Tier 2 candidates (Phase 2 via #3722)
  "mcp__soleur_platform__github_push_branch": "gated",
  "mcp__soleur_platform__create_pull_request": "gated",

  // KB share tools (#2309): list is read-only, create/revoke are
  // user-visible side effects (public URL / permanent revocation) → gated.
  // cc-router (#2909): list = Tier 1 candidate; create/revoke = Tier 2 (Phase 2 via #3722)
  "mcp__soleur_platform__kb_share_list": "auto-approve",
  "mcp__soleur_platform__kb_share_create": "gated",
  "mcp__soleur_platform__kb_share_revoke": "gated",
  // Preview (#2322): metadata-only (no bytes, no state change) — same
  // tier as kb_share_list. Gating it would produce consent fatigue without
  // a security benefit.
  // cc-router (#2909): Tier 1 candidate (Phase 2 via #3722)
  "mcp__soleur_platform__kb_share_preview": "auto-approve",
};

/**
 * Permanent Tier 3 denylist for the cc-soleur-go router (#2909).
 *
 * Tools in this set MAY NEVER be promoted to the router's mcpServers via
 * the inline `readCcMcpAllowlist()` helper in `cc-dispatcher.ts`. Enforced
 * fail-closed at factory construction (the helper throws if any short-name
 * resolving to a member of this set appears in `CC_MCP_ALLOWLIST`).
 *
 * Plausible tools (`plausible_create_site/add_goal/get_stats`) share a
 * single backend `PLAUSIBLE_API_KEY` with no per-user / per-site
 * enforcement (see `apps/web-platform/server/plausible-tools.ts:52-74`).
 * Exposing them via the router is a cross-tenant credential by
 * construction, regardless of any future demand signal.
 *
 * See brainstorm Key Decision #3:
 *   knowledge-base/project/brainstorms/2026-05-13-mcp-tier-classify-cc-soleur-go-brainstorm.md
 *
 * NOTE: legacy `TOOL_TIER_MAP` entries for Plausible tools do not exist;
 * `getToolTier()` returns "gated" by default for them on the legacy path,
 * which is correct (legacy review-gate UX surfaces them with founder
 * confirmation). This denylist is the cc-router-specific permanent block.
 */
export const CC_ROUTER_TIER3_DENYLIST: ReadonlySet<string> = new Set([
  "mcp__soleur_platform__plausible_create_site",
  "mcp__soleur_platform__plausible_add_goal",
  "mcp__soleur_platform__plausible_get_stats",
]);

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
