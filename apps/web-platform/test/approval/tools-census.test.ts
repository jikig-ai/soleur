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
  // The env route refuses EVERY approval-required short name, the grant-wired github_push_branch included: that tool reaches cc
  // only through the gated registrar (cc-github-push.ts), never by naming it in CC_MCP_ALLOWLIST. This is the backstop behind
  // the cc fail-closed switch, in any position of a mixed list, and the permanent denylist stays checked first.
  const P = "mcp__soleur_platform__";
  const STATIC_MESSAGE = (short: string) =>
    `CC_MCP_ALLOWLIST contains approval-required tool "${short}" \u2014 the env route cannot register approval-required tools; they register only through their gated registrar (ADR-309, ADR-311)`;
  const shortOf = (fqn: string) => fqn.replace(P, "");
  const required = [...APPROVAL_REQUIRED_TOOLS];

  it("is non-vacuous: all 8 required names are covered, and the grant-wired name is one of them", () => {
    expect(required).toHaveLength(8);
    expect(required).toContain(`${P}github_push_branch`);
    expect([...CC_GRANT_WIRED_APPROVAL_TOOLS].every((t) => isApprovalRequiredTool(t))).toBe(true);
  });

  for (const fqn of required) {
    const short = shortOf(fqn);
    it(`CC_MCP_ALLOWLIST naming ${short} throws with the static message (no env echo beyond the short name)`, () => {
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: short })).toThrow(STATIC_MESSAGE(short));
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `create_issue, ${short}` })).toThrow(STATIC_MESSAGE(short));
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: ` ${short} ,create_issue` })).toThrow(STATIC_MESSAGE(short));
    });
  }

  it("a mixed list throws for every required name in BOTH orders around the grant-wired name", () => {
    for (const fqn of required) {
      const short = shortOf(fqn);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `github_push_branch,${short}` }), `push first, then ${short}`).toThrow(/approval-required/);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `${short},github_push_branch` }), `${short} first, then push`).toThrow(/approval-required/);
    }
  });

  it("the permanent Tier 3 denylist is checked first per name: a denylist name before an approval name reports the denylist, after it the approval name is reported first", () => {
    expect(CC_ROUTER_TIER3_DENYLIST.size).toBeGreaterThan(0);
    for (const fqn of CC_ROUTER_TIER3_DENYLIST) {
      const short = shortOf(fqn);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: short }), short).toThrow(/denylist/i);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `${short},github_push_branch` }), `${short} then push`).toThrow(/denylist/i);
      expect(() => readCcMcpAllowlist({ CC_MCP_ALLOWLIST: `github_push_branch,${short}` }), `push then ${short}`).toThrow(/approval-required/);
    }
  });

  it("a name that is not approval-required still passes and the env route returns {}", () => {
    expect(readCcMcpAllowlist({ CC_MCP_ALLOWLIST: "create_issue" })).toEqual({});
  });
});

/**
 * Guard 2 of the cc approval wiring: a registration sweep DERIVED from the cc registry function, not a hand-kept list.
 * `soleurPlatformToolsForTests` is the one place the cc dispatcher assembles its soleur_platform tool list (narration, c4,
 * the gated push tool when the registrar registered it, and the CRM tools only for a crm-lead chat). Every tool it can
 * register must be explicitly tiered; the ONLY approval-required tool allowed is the grant-wired push tool (and only from the
 * registrar's output), and every other gated one must be exempt with a recorded reason.
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

  // The REAL registrar output (every seam true: persona, repo, installation, entitlement, flag, default-branch lookup), not a
  // hand-built fixture: the sweep sees exactly what the dispatcher would hand to the registry function.
  let registration: Awaited<ReturnType<typeof import("@/server/cc-github-push").resolveCcGithubPushRegistration>>;
  beforeAll(async () => {
    const { resolveCcGithubPushRegistration } = await import("@/server/cc-github-push");
    registration = await resolveCcGithubPushRegistration({
      userId: "sweep-user",
      workspaceId: "00000000-0000-4000-8000-000000000001",
      persona: "command_center",
      owner: "example-org",
      repo: "example-repo",
      installationId: 1,
      workspacePath: "/tmp/ws",
      webEgressEntitled: true,
      grants: new ExecutionGrants(),
      isEnabled: async () => true,
      lookupDefaultBranch: async () => "main",
    });
  }, 120_000);

  /** Every name the cc registry function can produce, over BOTH crm-lead settings, with or without the registrar's tool. */
  function registeredNames(withPush = false): string[] {
    const c4 = buildC4ToolsForSweep();
    const approvalTools = withPush ? registration.tools : undefined;
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

  it("the real registrar output (all seams true) is registered with exactly the push FQN, one-to-one", () => {
    expect(registration.registered).toBe(true);
    expect(registration.toolNames).toEqual([PUSH]);
    expect(registration.tools.map((t) => `${P}${t.name}`)).toEqual([PUSH]);
  });

  it("non-vacuity floor with the registrar's tool: at least 10 names, and the push tool is among them", () => {
    const names = registeredNames(true);
    expect(names.length).toBeGreaterThanOrEqual(10);
    expect(names).toContain(PUSH);
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
