import { beforeAll, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { TOOL_TIER_MAP } from "@/server/tool-tiers";
import {
  APPROVAL_EXEMPT_TOOLS,
  APPROVAL_REQUIRED_TOOLS,
  classifyGatedTools,
  isApprovalRequiredTool,
} from "@/server/approval/tools";
import { TOOLS } from "./fixtures";
import { stripComments } from "./source-scan";

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

// The cc-dispatcher module is a very large import graph (~13 s cold, measured), so it is imported ONCE for the whole file
// with its own generous budget; every test below then runs in microseconds.
let readCcMcpAllowlist: typeof import("@/server/cc-dispatcher").readCcMcpAllowlist;
let soleurPlatformToolsForTests: typeof import("@/server/cc-dispatcher").soleurPlatformToolsForTests;
let buildC4Tools: typeof import("@/server/c4-concierge-tools").buildC4ConciergeTools;
beforeAll(async () => {
  ({ readCcMcpAllowlist, soleurPlatformToolsForTests } = await import("@/server/cc-dispatcher"));
  ({ buildC4ConciergeTools: buildC4Tools } = await import("@/server/c4-concierge-tools"));
}, 120_000);

describe("the cc runner cannot be promoted onto an approval tool through CC_MCP_ALLOWLIST (ADR-309, sentinel discipline)", () => {
  // No cc tool builder is wired to the execution grants (the cc path has the gate and a grants object, but nothing reads a
  // grant), so a promoted approval tool could not be bound to an approval. readCcMcpAllowlist must therefore REFUSE
  // every APPROVAL_REQUIRED_TOOLS short name; it is the backstop behind the cc fail-closed switch.
  for (const fqn of APPROVAL_REQUIRED_TOOLS) {
    const short = fqn.replace("mcp__soleur_platform__", "");
    it(`CC_MCP_ALLOWLIST naming ${short} throws (static message, no env echo beyond the short name)`, () => {
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: short })).toThrow(/approval/i);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `create_issue, ${short}` })).toThrow(/approval/i);
    });
  }
});

/**
 * Guard 2 of the cc approval wiring: a registration sweep DERIVED from the cc registry function, not a hand-kept list.
 * `soleurPlatformToolsForTests` is the one place the cc dispatcher assembles its soleur_platform tool list (narration, c4,
 * and the CRM tools only for a crm-lead chat). Every tool it can register must be explicitly tiered, none may be an
 * approval-required tool, and every gated one must be exempt with a recorded reason.
 *
 * What this cannot see: a tool registered through some other route (a second MCP server in the cc options). The census
 * therefore also pins, over the comment-stripped dispatcher source, exactly one `createSdkMcpServer(` call and
 * `pluginMcpServerNames: []`.
 */
describe("cc registration sweep (derived from the registry function)", () => {
  const P = "mcp__soleur_platform__";

  /** Pure so it can be driven with a fake registry (self-test below). */
  function sweep(
    registered: readonly string[],
    tiers: Readonly<Record<string, string>> = TOOL_TIER_MAP,
    exempt: Readonly<Record<string, string>> = APPROVAL_EXEMPT_TOOLS,
  ) {
    const required = registered.filter((n) => isApprovalRequiredTool(n));
    const notExplicitlyTiered = registered.filter((n) => !(n in tiers));
    const gatedNotExempt = registered.filter((n) => tiers[n] === "gated" && !(n in exempt));
    return { required, notExplicitlyTiered, gatedNotExempt };
  }

  function registeredNames(): string[] {
    const c4 = buildC4ToolsForSweep();
    const names = new Set<string>();
    for (const crmLead of [true, false]) {
      for (const t of soleurPlatformToolsForTests({ userId: "sweep-user", crmLead, c4Tools: c4 })) names.add(`${P}${t.name}`);
    }
    return [...names];
  }

  function buildC4ToolsForSweep() {
    return buildC4Tools({ userId: "sweep-user", installationId: 1, owner: "example-org", repo: "example-repo", workspacePath: "/tmp/ws" });
  }

  it("registers a non-vacuous set that includes the narration tools, the c4 tool and the CRM tools", () => {
    const names = registeredNames();
    expect(names.length).toBeGreaterThanOrEqual(10);
    for (const must of ["narrate", "summarize", "edit_c4_diagram", "crm_contact_upsert", "crm_note_append", "crm_contact_set_stage"]) {
      expect(names, must).toContain(`${P}${must}`);
    }
  });

  it("no approval-required tool is registered in cc", () => {
    expect(sweep(registeredNames()).required).toEqual([]);
  });

  it("every registered tool is explicitly in TOOL_TIER_MAP (an unlisted name would default to gated)", () => {
    expect(sweep(registeredNames()).notExplicitlyTiered).toEqual([]);
  });

  it("every registered gated tool is exempt with a recorded reason (it stays on the human review card)", () => {
    expect(sweep(registeredNames()).gatedNotExempt).toEqual([]);
  });

  it("self-test: the sweep reports a required tool, an untiered tool and a gated non-exempt tool", () => {
    expect(sweep([...registeredNames(), `${P}github_push_branch`]).required).toEqual([`${P}github_push_branch`]);
    expect(sweep([...registeredNames(), `${P}not_in_the_tier_map`]).notExplicitlyTiered).toEqual([`${P}not_in_the_tier_map`]);
    // A fabricated tier map and exempt set drive the gated-non-exempt arm: the live maps hold no such tool (the census
    // above guarantees it), so a conditional assertion over them would silently never run.
    const fake = `${P}fabricated_gated_tool`;
    expect(sweep([fake], { [fake]: "gated" }, {}).gatedNotExempt).toEqual([fake]);
    expect(sweep([fake], { [fake]: "gated" }, { [fake]: "a recorded reason" }).gatedNotExempt).toEqual([]);
    expect(sweep([`${P}narrate`]).required).toEqual([]);
  });

  it("the dispatcher assembles one MCP server and permits no plugin MCP server tool (the sweep's blind spot, pinned structurally)", () => {
    const text = stripComments(readFileSync(join(__dirname, "../../server/cc-dispatcher.ts"), "utf8"));
    expect(text.match(/createSdkMcpServer\(/g)).toHaveLength(1);
    expect(text).toMatch(/pluginMcpServerNames:\s*\[\]/);
  });
});
