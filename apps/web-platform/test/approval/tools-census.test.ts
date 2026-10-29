import { describe, expect, it } from "vitest";
import { TOOL_TIER_MAP } from "@/server/tool-tiers";
import {
  APPROVAL_EXEMPT_TOOLS,
  APPROVAL_REQUIRED_TOOLS,
  classifyGatedTools,
  isApprovalRequiredTool,
} from "@/server/approval/tools";
import { TOOLS } from "./fixtures";

describe("slice-1 tool set", () => {
  it("is exactly the eight tools of the spec (fully qualified names)", () => {
    expect([...APPROVAL_REQUIRED_TOOLS].sort()).toEqual(Object.values(TOOLS).sort());
    for (const t of Object.values(TOOLS)) expect(isApprovalRequiredTool(t)).toBe(true);
    expect(isApprovalRequiredTool("mcp__soleur_platform__create_issue")).toBe(false);
    expect(isApprovalRequiredTool("Bash")).toBe(false);
  });

  it("every slice-1 tool is gated in TOOL_TIER_MAP (an auto-approve tool must never need an approval row)", () => {
    for (const t of APPROVAL_REQUIRED_TOOLS) expect(TOOL_TIER_MAP[t]).toBe("gated");
  });
});

describe("Guard 2 census: every gated tool is required or exempt-with-a-reason", () => {
  it("the real TOOL_TIER_MAP is fully classified, non-vacuously", () => {
    const r = classifyGatedTools(TOOL_TIER_MAP, APPROVAL_REQUIRED_TOOLS, APPROVAL_EXEMPT_TOOLS);
    expect(r.gated.length).toBeGreaterThan(8);
    expect(r.unclassified).toEqual([]);
    expect(r.emptyReason).toEqual([]);
    expect(r.doubleClassified).toEqual([]);
    expect(r.staleExempt).toEqual([]);
  });

  it("an exempt tool carries a one-line reason", () => {
    for (const [name, reason] of Object.entries(APPROVAL_EXEMPT_TOOLS)) {
      expect(reason.trim().length, name).toBeGreaterThan(10);
      expect(reason.includes("\n"), name).toBe(false);
    }
  });

  const map = { a: "gated", b: "gated", c: "auto-approve" } as const;

  it("row 1: a new gated tool added to the map without classification is reported", () => {
    expect(classifyGatedTools({ ...map, n: "gated" }, ["a"], { b: "reason one here" }).unclassified).toEqual(["n"]);
  });

  it("row 2: an empty census is reported as vacuous", () => {
    expect(() => classifyGatedTools({ c: "auto-approve" }, [], {})).toThrow(/vacuous/i);
    expect(() => classifyGatedTools({}, [], {})).toThrow(/vacuous/i);
  });

  it("row 2b: a census with gated tools but no required tool, or required tools but no gated tool, is vacuous", () => {
    expect(() => classifyGatedTools(map, [], {})).toThrow(/vacuous/i);
    expect(() => classifyGatedTools({ c: "auto-approve" }, ["a"], {})).toThrow(/vacuous/i);
  });

  it("row 3: a second unclassified gated tool after a classified one is also reported", () => {
    expect(classifyGatedTools({ ...map, n: "gated", m: "gated" }, ["a"], { b: "reason one here" }).unclassified.sort()).toEqual(["m", "n"]);
  });

  it("row 4: an exempt tool with an empty or blank reason is reported", () => {
    expect(classifyGatedTools(map, ["a"], { b: "" }).emptyReason).toEqual(["b"]);
    expect(classifyGatedTools(map, ["a"], { b: "   " }).emptyReason).toEqual(["b"]);
  });

  it("a tool both required and exempt, and an exempt entry that is no longer gated, are reported", () => {
    expect(classifyGatedTools(map, ["a", "b"], { b: "reason one here" }).doubleClassified).toEqual(["b"]);
    expect(classifyGatedTools(map, ["a", "b"], { gone: "reason one here" }).staleExempt).toEqual(["gone"]);
  });
});
