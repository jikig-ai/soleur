import { beforeAll, describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { CC_ROUTER_TIER3_DENYLIST, TOOL_TIER_MAP } from "@/server/tool-tiers";
import { CC_GRANT_WIRED_APPROVAL_TOOLS } from "@/server/cc-github-push";
import {
  APPROVAL_EXEMPT_TOOLS,
  APPROVAL_REQUIRED_TOOLS,
  classifyGatedTools,
  isApprovalRequiredTool,
} from "@/server/approval/tools";
import { ExecutionGrants } from "@/server/approval/grants";
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
let buildPushTool: typeof import("@/server/github-tools").buildGithubPushBranchTool;
beforeAll(async () => {
  ({ readCcMcpAllowlist, soleurPlatformToolsForTests } = await import("@/server/cc-dispatcher"));
  ({ buildC4ConciergeTools: buildC4Tools } = await import("@/server/c4-concierge-tools"));
  ({ buildGithubPushBranchTool: buildPushTool } = await import("@/server/github-tools"));
}, 120_000);

describe("the cc runner cannot be promoted onto an approval tool through CC_MCP_ALLOWLIST (ADR-309, sentinel discipline)", () => {
  // Exactly ONE approval-required tool has a grant-wired cc builder (github_push_branch, registered through the gated
  // registrar in cc-github-push.ts, never through this env route: readCcMcpAllowlist returns {} regardless of the names).
  // Every OTHER required short name must still be REFUSED here as the backstop behind the cc fail-closed switch, in any
  // position of a mixed list, and the permanent denylist stays checked first.
  const P = "mcp__soleur_platform__";
  const WIRED = new Set<string>(CC_GRANT_WIRED_APPROVAL_TOOLS);
  const shortOf = (fqn: string) => fqn.replace(P, "");
  const required = [...APPROVAL_REQUIRED_TOOLS];
  const wired = required.filter((t) => WIRED.has(t));
  const notWired = required.filter((t) => !WIRED.has(t));

  it("is non-vacuous: exactly one grant-wired name, all of them required, and the rest of the required set is still refused", () => {
    expect(wired).toEqual([`${P}github_push_branch`]);
    expect([...WIRED].every((t) => isApprovalRequiredTool(t))).toBe(true);
    expect(notWired.length).toBeGreaterThanOrEqual(7);
  });

  for (const fqn of notWired) {
    const short = shortOf(fqn);
    it(`CC_MCP_ALLOWLIST naming ${short} throws (static message, no env echo beyond the short name)`, () => {
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: short })).toThrow(/approval/i);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `create_issue, ${short}` })).toThrow(/approval/i);
    });
  }

  it("the grant-wired name does not throw, and the env route still returns {} (registration never reads the env)", () => {
    expect(readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "github_push_branch" })).toEqual({});
    expect(readCcMcpAllowlist({ CC_MCP_ALLOWLIST: " github_push_branch , create_issue " })).toEqual({});
  });

  it("a mixed list throws for any other required name in BOTH orders (a compliant grant-wired name does not shield the next one)", () => {
    for (const fqn of notWired) {
      const short = shortOf(fqn);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `github_push_branch,${short}` }), `wired first, then ${short}`).toThrow(/approval/i);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `${short},github_push_branch` }), `${short} first, then wired`).toThrow(/approval/i);
    }
  });

  it("the permanent Tier 3 denylist still throws, in any position around the grant-wired name", () => {
    expect(CC_ROUTER_TIER3_DENYLIST.size).toBeGreaterThan(0);
    for (const fqn of CC_ROUTER_TIER3_DENYLIST) {
      const short = shortOf(fqn);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: short }), short).toThrow(/denylist/i);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `github_push_branch,${short}` }), `wired then ${short}`).toThrow(/denylist/i);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `${short},github_push_branch` }), `${short} then wired`).toThrow(/denylist/i);
    }
  });

  it("the throw for an unwired required tool says it has no grant-wired cc builder (the sentence stays true now that one tool is wired)", () => {
    expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "email_send" })).toThrow(/no grant-wired cc builder/);
  });
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
  const PUSH = `${P}github_push_branch`;

  /**
   * Pure so it can be driven with a fake registry (self-test below). `allowedRequired` is the set of approval-required
   * names a registrar is permitted to add (the grant-wired constant): any OTHER required name is `unexpectedRequired`.
   */
  function sweep(
    registered: readonly string[],
    tiers: Readonly<Record<string, string>> = TOOL_TIER_MAP,
    exempt: Readonly<Record<string, string>> = APPROVAL_EXEMPT_TOOLS,
    allowedRequired: readonly string[] = CC_GRANT_WIRED_APPROVAL_TOOLS,
  ) {
    const required = registered.filter((n) => isApprovalRequiredTool(n));
    const unexpectedRequired = required.filter((n) => !allowedRequired.includes(n));
    const notExplicitlyTiered = registered.filter((n) => !(n in tiers));
    const gatedNotExempt = registered.filter((n) => tiers[n] === "gated" && !(n in exempt) && !allowedRequired.includes(n));
    return { required, unexpectedRequired, notExplicitlyTiered, gatedNotExempt };
  }

  function buildPushToolForSweep() {
    return [
      buildPushTool({
        installationId: 1,
        owner: "example-org",
        repo: "example-repo",
        defaultBranch: "main",
        workspacePath: "/tmp/ws",
        grants: new ExecutionGrants(),
        requireGrant: true,
      }),
    ] as unknown as readonly { name: string }[];
  }

  /** Every name the cc registry function can produce, over BOTH crm-lead settings, with or without the registrar's tool. */
  function registeredNames(withPush = false): string[] {
    const c4 = buildC4ToolsForSweep();
    const approvalTools = withPush ? buildPushToolForSweep() : undefined;
    const names = new Set<string>();
    for (const crmLead of [true, false]) {
      for (const t of soleurPlatformToolsForTests({ userId: "sweep-user", crmLead, c4Tools: c4, ...(approvalTools ? { approvalTools } : {}) })) {
        names.add(`${P}${t.name}`);
      }
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

  it("non-vacuity floor with the registrar's tool: at least 10 names, and the push tool is among them", () => {
    const names = registeredNames(true);
    expect(names.length).toBeGreaterThanOrEqual(10);
    expect(names).toContain(PUSH);
    expect(names.filter((n) => n === PUSH)).toHaveLength(1);
  });

  it("without the registrar's tool no approval-required tool is registered in cc (the dark path)", () => {
    const names = registeredNames(false);
    expect(names).not.toContain(PUSH);
    expect(sweep(names).required).toEqual([]);
  });

  it("with the registrar's tool the approval-required set is EXACTLY the push FQN, and nothing else is required", () => {
    const r = sweep(registeredNames(true));
    expect(r.required).toEqual([PUSH]);
    expect(r.unexpectedRequired).toEqual([]);
  });

  it("every registered tool is explicitly in TOOL_TIER_MAP (an unlisted name would default to gated), with and without the push tool", () => {
    expect(sweep(registeredNames(false)).notExplicitlyTiered).toEqual([]);
    expect(sweep(registeredNames(true)).notExplicitlyTiered).toEqual([]);
  });

  it("every registered gated tool is exempt with a recorded reason (it stays on the human review card), the grant-wired push tool excepted", () => {
    expect(sweep(registeredNames(false)).gatedNotExempt).toEqual([]);
    expect(sweep(registeredNames(true)).gatedNotExempt).toEqual([]);
    // The exception is exactly the allowed set: without it the push tool is a gated non-exempt registration.
    expect(sweep(registeredNames(true), TOOL_TIER_MAP, APPROVAL_EXEMPT_TOOLS, []).gatedNotExempt).toEqual([PUSH]);
  });

  it("self-test: the sweep reports a required tool, an untiered tool and a gated non-exempt tool", () => {
    expect(sweep([...registeredNames(), PUSH], TOOL_TIER_MAP, APPROVAL_EXEMPT_TOOLS, []).unexpectedRequired).toEqual([PUSH]);
    expect(sweep([...registeredNames(), `${P}not_in_the_tier_map`]).notExplicitlyTiered).toEqual([`${P}not_in_the_tier_map`]);
    // A fabricated tier map and exempt set drive the gated-non-exempt arm: the live maps hold no such tool (the census
    // above guarantees it), so a conditional assertion over them would silently never run.
    const fake = `${P}fabricated_gated_tool`;
    expect(sweep([fake], { [fake]: "gated" }, {}).gatedNotExempt).toEqual([fake]);
    expect(sweep([fake], { [fake]: "gated" }, { [fake]: "a recorded reason" }).gatedNotExempt).toEqual([]);
    expect(sweep([`${P}narrate`]).required).toEqual([]);
  });

  it("self-test: a SECOND required tool next to the compliant push tool is reported (the allowed set is not a blanket pass)", () => {
    const withExtra = [...registeredNames(true), `${P}email_send`];
    const r = sweep(withExtra);
    expect(r.required.sort()).toEqual([`${P}email_send`, PUSH].sort());
    expect(r.unexpectedRequired).toEqual([`${P}email_send`]);
    // The harness row: widening the allowed set to include email_send is what a weakening edit would do; the sweep then
    // stops reporting it, so the constant itself is pinned to exactly the push FQN.
    expect(sweep(withExtra, TOOL_TIER_MAP, APPROVAL_EXEMPT_TOOLS, [PUSH, `${P}email_send`]).unexpectedRequired).toEqual([]);
    expect([...CC_GRANT_WIRED_APPROVAL_TOOLS]).toEqual([PUSH]);
  });

  it("must-pass non-canonical inputs: a registry of only narration tools, and narration plus the push tool, both sweep clean", () => {
    expect(sweep([`${P}narrate`, `${P}summarize`])).toMatchObject({ required: [], unexpectedRequired: [], gatedNotExempt: [] });
    expect(sweep([`${P}narrate`, `${P}summarize`, PUSH])).toMatchObject({ required: [PUSH], unexpectedRequired: [], gatedNotExempt: [] });
  });

  it("the dispatcher assembles one MCP server and permits no plugin MCP server tool (the sweep's blind spot, pinned structurally)", () => {
    const text = stripComments(readFileSync(join(__dirname, "../../server/cc-dispatcher.ts"), "utf8"));
    expect(text.match(/createSdkMcpServer\(/g)).toHaveLength(1);
    expect(text).toMatch(/pluginMcpServerNames:\s*\[\]/);
  });
});
