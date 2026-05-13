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
  buildGateMessage,
  CC_ROUTER_TIER3_DENYLIST,
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

  test("returns gated for unregistered platform tools (fail-closed default)", () => {
    // Platform tools not in the tier map default to gated
    // so new tools require explicit tier assignment before auto-approve
    expect(getToolTier("mcp__soleur_platform__unknown_future_tool")).toBe(
      "gated",
    );
  });

});

describe("buildGateMessage", () => {
  test("trigger workflow message includes workflow_id and ref", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__github_trigger_workflow",
      { workflow_id: 42, ref: "main" },
    );
    expect(msg).toContain("42");
    expect(msg).toContain("main");
    expect(msg).toMatch(/trigger workflow/i);
  });

  test("push branch message includes branch name", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__github_push_branch",
      { branch: "feat-new-feature" },
    );
    expect(msg).toContain("feat-new-feature");
    expect(msg).toMatch(/push/i);
  });

  test("create PR message includes title and branches", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__create_pull_request",
      { title: "My PR", base: "main", head: "feat-x" },
    );
    expect(msg).toContain("My PR");
    expect(msg).toContain("main");
    expect(msg).toContain("feat-x");
    expect(msg).toMatch(/open PR/i);
  });

  test("unknown tool uses short tool name", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__some_new_tool",
      {},
    );
    expect(msg).toContain("some_new_tool");
  });
});

describe("CC_ROUTER_TIER3_DENYLIST (#2909)", () => {
  test("contains exactly 3 entries", () => {
    expect(CC_ROUTER_TIER3_DENYLIST.size).toBe(3);
  });

  test("contains all three Plausible tool FQNs", () => {
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__plausible_create_site"),
    ).toBe(true);
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__plausible_add_goal"),
    ).toBe(true);
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__plausible_get_stats"),
    ).toBe(true);
  });

  test("does not contain non-Plausible tools (no Tier 3 creep)", () => {
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__kb_share_create"),
    ).toBe(false);
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__github_push_branch"),
    ).toBe(false);
    expect(
      CC_ROUTER_TIER3_DENYLIST.has("mcp__soleur_platform__conversations_lookup"),
    ).toBe(false);
  });
});
