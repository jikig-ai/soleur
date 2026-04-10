/**
 * Tool Tier Classification Tests (Phase 1, #1926)
 *
 * Tests the tiered permission model for platform MCP tools:
 * - auto-approve: read-only tools pass through without review gate
 * - gated: write tools require founder confirmation via review gate
 * - blocked: destructive patterns rejected unconditionally
 *
 * Extracted to a standalone module (following tool-path-checker.ts pattern)
 * for unit testability without SDK/Supabase dependencies.
 */
import { describe, test, expect } from "vitest";
import {
  getToolTier,
  TOOL_TIER_MAP,
  type ToolTier,
} from "../server/tool-tiers";

describe("getToolTier", () => {
  test("returns auto-approve for github_read_ci_status", () => {
    expect(getToolTier("mcp__soleur_platform__github_read_ci_status")).toBe(
      "auto-approve",
    );
  });

  test("returns auto-approve for github_read_workflow_logs", () => {
    expect(getToolTier("mcp__soleur_platform__github_read_workflow_logs")).toBe(
      "auto-approve",
    );
  });

  test("returns gated for github_trigger_workflow", () => {
    expect(getToolTier("mcp__soleur_platform__github_trigger_workflow")).toBe(
      "gated",
    );
  });

  test("returns gated for github_push_branch", () => {
    expect(getToolTier("mcp__soleur_platform__github_push_branch")).toBe(
      "gated",
    );
  });

  test("returns gated for create_pull_request", () => {
    expect(getToolTier("mcp__soleur_platform__create_pull_request")).toBe(
      "gated",
    );
  });

  test("returns auto-approve for unregistered platform tools (safe default)", () => {
    // Platform tools not in the tier map default to auto-approve
    // because they are already validated by platformToolNames inclusion
    expect(getToolTier("mcp__soleur_platform__unknown_future_tool")).toBe(
      "auto-approve",
    );
  });

  test("TOOL_TIER_MAP contains all expected tools", () => {
    const expectedTools = [
      "mcp__soleur_platform__github_read_ci_status",
      "mcp__soleur_platform__github_read_workflow_logs",
      "mcp__soleur_platform__github_trigger_workflow",
      "mcp__soleur_platform__github_push_branch",
      "mcp__soleur_platform__create_pull_request",
    ];

    for (const tool of expectedTools) {
      expect(TOOL_TIER_MAP).toHaveProperty(tool);
    }
  });

  test("no tool is mapped to an invalid tier", () => {
    const validTiers: ToolTier[] = ["auto-approve", "gated", "blocked"];
    for (const tier of Object.values(TOOL_TIER_MAP)) {
      expect(validTiers).toContain(tier);
    }
  });
});
