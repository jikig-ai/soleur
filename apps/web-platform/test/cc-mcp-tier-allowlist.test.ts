/**
 * CC_MCP_ALLOWLIST + Sentry-mirror tests for cc-soleur-go router (#2909).
 *
 * Phase 1 deny-by-default scaffolding:
 * - `readCcMcpAllowlist(env)` returns mcpServers config. Empty/unset/
 *   whitespace-only env returns `{}` (current behavior preserved).
 *   Tier 3 denylist short-names throw plain Error. Phase 1 does NOT
 *   yet validate unknown non-denylist names (deferred to Phase 2 / #3722).
 * - `shouldMirrorUnregisteredPlatformToolUse(toolName, registered)`
 *   returns true when the cc-router iterator observes a
 *   `mcp__soleur_platform__*` tool_use that isn't registered. Hook for
 *   `reportSilentFallback` (Candidate B per Kieran SDK-source read —
 *   canUseTool does NOT fire for unknown MCP tools).
 *
 * Plan: knowledge-base/project/plans/2026-05-13-feat-mcp-tier-classify-cc-soleur-go-phase-1-plan.md
 */
import { describe, test, expect } from "vitest";
import {
  readCcMcpAllowlist,
  shouldMirrorUnregisteredPlatformToolUse,
} from "../server/cc-dispatcher";

describe("readCcMcpAllowlist (#2909 FR1)", () => {
  test("unset env returns empty object", () => {
    expect(readCcMcpAllowlist({})).toEqual({});
  });

  test("empty string env returns empty object", () => {
    expect(readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "" })).toEqual({});
  });

  test("whitespace-only env returns empty object", () => {
    expect(readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "   " })).toEqual({});
  });

  test("comma-only env (no names) returns empty object", () => {
    expect(readCcMcpAllowlist({ CC_MCP_ALLOWLIST: ", , " })).toEqual({});
  });

  test("Tier 3 plausible_create_site throws with permanent denylist message", () => {
    expect(() =>
      readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "plausible_create_site" }),
    ).toThrow(/permanent Tier 3 denylist/);
    expect(() =>
      readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "plausible_create_site" }),
    ).toThrow(/plausible_create_site/);
  });

  test("Tier 3 plausible_add_goal throws", () => {
    expect(() =>
      readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "plausible_add_goal" }),
    ).toThrow(/permanent Tier 3 denylist/);
  });

  test("Tier 3 plausible_get_stats throws", () => {
    expect(() =>
      readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "plausible_get_stats" }),
    ).toThrow(/permanent Tier 3 denylist/);
  });

  test("denylist-first ordering pinned: leading position throws on Plausible", () => {
    expect(() =>
      readCcMcpAllowlist({
        CC_MCP_ALLOWLIST: "plausible_create_site,foo,bar",
      }),
    ).toThrow(/plausible_create_site/);
  });

  test("denylist-first ordering pinned: trailing position still throws on Plausible", () => {
    expect(() =>
      readCcMcpAllowlist({
        CC_MCP_ALLOWLIST: "foo,plausible_create_site,bar",
      }),
    ).toThrow(/plausible_create_site/);
  });

  test("denylist-first ordering pinned: middle position", () => {
    expect(() =>
      readCcMcpAllowlist({
        CC_MCP_ALLOWLIST: "kb_share_list,plausible_get_stats,github_read_ci_status",
      }),
    ).toThrow(/plausible_get_stats/);
  });

  // PHASE-1-CONTRACT — delete in #3722
  test("non-denylist valid name returns {} in Phase 1 (Phase 2 builds populated server)", () => {
    // Phase 1: the allowlist mechanism enforces the denylist only. Even with
    // a valid non-denylist name present, we return {} — building a populated
    // soleur_platform server is deferred to #3722 alongside actual promotion.
    expect(readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "kb_share_list" })).toEqual({});
  });

  // PHASE-1-CONTRACT — delete in #3722
  test("non-denylist names with whitespace stripped, still return {} in Phase 1", () => {
    expect(
      readCcMcpAllowlist({
        CC_MCP_ALLOWLIST: "  kb_share_list  ,  github_read_ci_status  ",
      }),
    ).toEqual({});
  });

  // PHASE-1-CONTRACT — delete in #3722
  test("unknown non-denylist names do NOT throw in Phase 1 (validation deferred to Phase 2)", () => {
    // Phase 1 contract: only the denylist is enforced. Unknown names pass
    // through silently and return {} (since Phase 1 always returns {}).
    // Phase 2 (#3722) will add `KNOWN_PLATFORM_TOOLS` validation alongside
    // the first real tool registration.
    expect(() =>
      readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "not_a_real_tool" }),
    ).not.toThrow();
    expect(readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "not_a_real_tool" })).toEqual(
      {},
    );
  });

  test("default process.env branch (no explicit env arg) returns {}", () => {
    // Coverage for the parameter-default branch — readCcMcpAllowlist() with
    // no arg must read process.env (which has CC_MCP_ALLOWLIST unset in the
    // test environment). Confirms the default-param path is exercised.
    const originalEnv = process.env.CC_MCP_ALLOWLIST;
    delete process.env.CC_MCP_ALLOWLIST;
    try {
      expect(readCcMcpAllowlist()).toEqual({});
    } finally {
      if (originalEnv !== undefined) process.env.CC_MCP_ALLOWLIST = originalEnv;
    }
  });

  test("denylist throw message points to the source-of-truth file (operator debugging)", () => {
    // The error message must mention `tool-tiers.ts` so a misconfigured
    // operator immediately knows where to inspect the denylist. Pinning the
    // file pointer guards against future message refactors silently dropping
    // the operator's only breadcrumb.
    expect(() =>
      readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "plausible_create_site" }),
    ).toThrow(/tool-tiers\.ts/);
  });
});

describe("shouldMirrorUnregisteredPlatformToolUse (#2909 FR2)", () => {
  test("returns true for unregistered soleur_platform tool", () => {
    expect(
      shouldMirrorUnregisteredPlatformToolUse(
        "mcp__soleur_platform__kb_share_list",
        [],
      ),
    ).toBe(true);
  });

  test("returns false for registered soleur_platform tool (Phase 2 case)", () => {
    expect(
      shouldMirrorUnregisteredPlatformToolUse(
        "mcp__soleur_platform__kb_share_list",
        ["mcp__soleur_platform__kb_share_list"],
      ),
    ).toBe(false);
  });

  test("returns false for non-soleur_platform tools (other MCP servers)", () => {
    expect(
      shouldMirrorUnregisteredPlatformToolUse(
        "mcp__some_other_server__some_tool",
        [],
      ),
    ).toBe(false);
  });

  test("returns false for non-MCP tool names (Bash, Edit, etc.)", () => {
    expect(shouldMirrorUnregisteredPlatformToolUse("Bash", [])).toBe(false);
    expect(shouldMirrorUnregisteredPlatformToolUse("Edit", [])).toBe(false);
    expect(shouldMirrorUnregisteredPlatformToolUse("Read", [])).toBe(false);
  });

  test("returns true even when other platform tools are registered", () => {
    expect(
      shouldMirrorUnregisteredPlatformToolUse(
        "mcp__soleur_platform__plausible_get_stats",
        ["mcp__soleur_platform__kb_share_list"],
      ),
    ).toBe(true);
  });
});
