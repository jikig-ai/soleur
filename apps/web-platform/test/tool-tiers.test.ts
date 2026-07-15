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

  test("returns auto-approve for edit_c4_diagram (scope-guarded write)", () => {
    expect(getToolTier("mcp__soleur_platform__edit_c4_diagram")).toBe(
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

  test("returns gated for create_issue", () => {
    expect(getToolTier("mcp__soleur_platform__create_issue")).toBe(
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

describe("workstream edit-fields tool tiers (agent-user parity)", () => {
  test("workstream_issue_update_fields is gated (real GitHub write)", () => {
    expect(
      getToolTier("mcp__soleur_platform__workstream_issue_update_fields"),
    ).toBe("gated");
  });

  test("workstream_issue_options is auto-approve (read-only discovery)", () => {
    expect(
      getToolTier("mcp__soleur_platform__workstream_issue_options"),
    ).toBe("auto-approve");
  });

  test("update_fields gate message names the edited fields", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__workstream_issue_update_fields",
      { number: 7, labels: ["bug"], milestone: null, assignees: ["harry"] },
    );
    expect(msg).toContain("#7");
    expect(msg).toContain("bug");
    expect(msg).toContain("harry");
    expect(msg).toMatch(/milestone/i);
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

  test("create issue message includes title", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__create_issue",
      { title: "Login is broken" },
    );
    expect(msg).toContain("Login is broken");
    expect(msg).toMatch(/file an issue/i);
  });

  test("unknown tool uses short tool name", () => {
    const msg = buildGateMessage(
      "mcp__soleur_platform__some_new_tool",
      {},
    );
    expect(msg).toContain("some_new_tool");
  });

  // #5325 — the operator MUST see recipient + body before approving an
  // outbound send; a content-free "Allow?" would make the gate decorative.
  test("email_send gate shows the recipient, subject, and body", () => {
    const msg = buildGateMessage("mcp__soleur_platform__email_send", {
      to: "journalist@example.com",
      subject: "Your listicle",
      body: "Hi — I built something relevant to your piece.",
    });
    expect(msg).toContain("journalist@example.com");
    expect(msg).toContain("Your listicle");
    expect(msg).toContain("I built something relevant");
    expect(msg).not.toMatch(/^Agent wants to use/); // not the default
  });

  test("email_reply gate names the inbound item + shows the body (recipient is server-derived)", () => {
    const msg = buildGateMessage("mcp__soleur_platform__email_reply", {
      messageId: "abc-123",
      subject: "Re: hello",
      body: "Thanks for your note.",
    });
    expect(msg).toContain("abc-123");
    expect(msg).toContain("Thanks for your note");
  });

  test("email_suppress gate names the recipient + flags permanence", () => {
    const msg = buildGateMessage("mcp__soleur_platform__email_suppress", {
      recipient: "person@example.com",
      reason: "decline",
    });
    expect(msg).toContain("person@example.com");
    expect(msg).toMatch(/permanent/i);
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
