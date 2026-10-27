/**
 * #11303 — gated-tier allowedTools bypass: census, in-suite mutation battery and wiring.
 *
 * The Claude Agent SDK approves a bare `allowedTools` entry BEFORE it consults `canUseTool`, so a gated platform tool that
 * is listed there runs with no review card. `buildAllowedTools` is the single filter between the registered platform tool
 * names and the SDK pre-approval list. Guard 1 of the plan: no platform tool whose effective tier is not `auto-approve`
 * is ever handed to the SDK as pre-approved by any runner.
 *
 * Layout:
 *   1. unit census over `buildAllowedTools` (booted universe, hand-written full tier table)
 *   2. mutation battery: mutant filters run through ONE oracle (`assertCensus`) that must flag each of them, plus a
 *      direct sensitivity check on the oracle (an always-green oracle fails the suite)
 *   3. explicit-tier-entry check over the names a booted `startAgentSession` really registers
 *   4. `startAgentSession` wiring: the SDK receives exactly `buildAllowedTools(...)`, `canUseTool` the unfiltered list
 *   5. sentinels: plugin skill/agent frontmatter, tool `annotations`
 */
import { vi, describe, test, expect, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

const { mockFrom, mockRpc, mockQuery, mockReadFileSync, toolExtras, canUseToolSpy } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockQuery: vi.fn(),
  mockReadFileSync: vi.fn(),
  toolExtras: [] as unknown[],
  canUseToolSpy: vi.fn(),
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: mockQuery,
  tool: vi.fn((name: string, _desc: string, _schema: unknown, handler: Function, extras?: unknown) => {
    toolExtras.push(extras);
    return { name, handler };
  }),
  createSdkMcpServer: vi.fn((opts: { name: string; tools: unknown[] }) => ({
    type: "sdk",
    name: opts.name,
    instance: { tools: opts.tools },
  })),
}));
vi.mock("fs", async (importOriginal) => {
  const actual = await importOriginal<typeof import("fs")>();
  return { ...actual, readFileSync: mockReadFileSync };
});
vi.mock("@supabase/supabase-js", () => ({ createClient: vi.fn(() => ({ from: mockFrom })) }));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockFrom, rpc: mockRpc })),
  mintFounderJwt: vi.fn(),
  RuntimeAuthError: class RuntimeAuthError extends Error {
    cause: string;
    constructor(cause: string, msg: string) {
      super(msg);
      this.name = "RuntimeAuthError";
      this.cause = cause;
    }
  },
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }),
}));
vi.mock("../server/byok", () => ({
  decryptKey: vi.fn(() => Buffer.from("sk-test-key", "utf8")),
  decryptKeyLegacy: vi.fn(() => Buffer.from("sk-test-key", "utf8")),
  zeroize: vi.fn(),
  encryptKey: vi.fn(),
}));
vi.mock("../server/error-sanitizer", () => ({ sanitizeErrorForClient: vi.fn(() => "error") }));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [],
  extractToolPath: vi.fn(),
  isFileTool: vi.fn(() => false),
  isSafeTool: vi.fn(() => false),
}));
vi.mock("../server/agent-env", async () => {
  const actual = await vi.importActual<typeof import("../server/agent-env")>("../server/agent-env");
  return { ...actual, buildAgentEnv: vi.fn(() => ({})) };
});
vi.mock("../server/sandbox-hook", () => ({ createSandboxHook: vi.fn(() => vi.fn()) }));
vi.mock("../server/review-gate", () => ({
  abortableReviewGate: vi.fn().mockResolvedValue("Approve"),
  validateSelection: vi.fn(),
  extractReviewGateInput: vi.fn(),
  buildReviewGateResponse: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => {
  const leaders = [{ id: "cpo", name: "CPO", title: "Chief Product Officer", description: "Product" }];
  return { DOMAIN_LEADERS: leaders, ROUTABLE_DOMAIN_LEADERS: leaders };
});
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({ syncPull: vi.fn(), syncPush: vi.fn() }));
vi.mock("../server/github-api", () => ({
  githubApiGet: vi.fn().mockResolvedValue({ default_branch: "main" }),
  githubApiGetText: vi.fn().mockResolvedValue(""),
  githubApiPost: vi.fn().mockResolvedValue(null),
}));
// The harness mocks the Plausible service client, so the explicit-entry check below must prove the Plausible TOOLS still
// registered (they are built from the user's stored key row, not from this client) rather than pass vacuously.
vi.mock("../server/service-tools", () => ({
  plausibleCreateSite: vi.fn(),
  plausibleAddGoal: vi.fn(),
  plausibleGetStats: vi.fn(),
}));
vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  reportSilentFallbackWarning: vi.fn(),
  warnSilentFallback: vi.fn(),
}));
vi.mock("../server/permission-callback", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../server/permission-callback")>();
  return {
    ...actual,
    createCanUseTool: (ctx: Parameters<typeof actual.createCanUseTool>[0]) => {
      canUseToolSpy(ctx);
      return actual.createCanUseTool(ctx);
    },
  };
});

import { join } from "node:path";
import { startAgentSession } from "../server/agent-runner";
import { buildAllowedTools, buildOfflineGateMessage, getToolTier, TOOL_TIER_MAP } from "../server/tool-tiers";
import { assertAllowedToolsPreApprovalSafe } from "../server/agent-runner-query-options";
import { DEFAULT_API_KEY_ROW, createSupabaseMockImpl, createQueryMock } from "./helpers/agent-runner-mocks";
import { EXPECTED_AUTO_APPROVE, EXPECTED_GATED, EXPECTED_TOOL_TIERS } from "./helpers/expected-tool-tiers";

// ---------------------------------------------------------------------------------------------------------------------
// The expected tier of every platform tool is the hand-written table in helpers/expected-tool-tiers.ts. It is NOT derived
// from TOOL_TIER_MAP, so flipping a tool's tier needs a second visible edit there and a flip alone reds the suite.
// ---------------------------------------------------------------------------------------------------------------------
const PREFIX = "mcp__soleur_platform__";
const fqn = (n: string) => `${PREFIX}${n}`;
const wildcard = (s: string) => `mcp__plugin_soleur_${s}__*`;

const EXPECTED_GATED_FQNS = EXPECTED_GATED.map(fqn);
const EXPECTED_AUTO_FQNS = EXPECTED_AUTO_APPROVE.map(fqn);

const PLUGIN_SERVERS = ["context7", "cloudflare", "vercel", "stripe"];

type Booted = {
  options: Record<string, any>;
  platformToolNames: string[];
  registered: string[];
};

async function bootLegacySession(): Promise<Booted> {
  const plausibleRow = { ...DEFAULT_API_KEY_ROW, id: "key-plausible", provider: "plausible" };
  createSupabaseMockImpl(mockFrom, {
    userData: {
      workspace_path: "/tmp/test-workspace",
      repo_status: "ready",
      github_installation_id: 12345,
      repo_url: "https://github.com/alice/my-repo",
    },
    apiKeyRows: [DEFAULT_API_KEY_ROW, plausibleRow],
    mockRpc,
  });
  createQueryMock(mockQuery);
  await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-1", "cpo");
  const options = mockQuery.mock.calls[0][0].options;
  const ctx = canUseToolSpy.mock.calls[0][0] as { platformToolNames: string[] };
  const registered = (options.mcpServers?.soleur_platform?.instance.tools ?? []).map((t: { name: string }) => fqn(t.name));
  return { options, platformToolNames: [...ctx.platformToolNames], registered };
}

// ---------------------------------------------------------------------------------------------------------------------
// The oracle. Every mutant below is run through THIS function; it must flag each one.
// ---------------------------------------------------------------------------------------------------------------------
function assertCensus(output: readonly string[], universe: readonly string[], plugins: readonly string[]): string[] {
  const problems: string[] = [];
  for (const n of output) {
    if (n.startsWith(PREFIX) && EXPECTED_TOOL_TIERS[n] !== "auto-approve") problems.push(`non-auto platform tool pre-approved: ${n}`);
  }
  // a vacuous census or a vacuous filter must not read as green: the booted universe must be non-trivial in BOTH tiers
  const gatedInUniverse = universe.filter((n) => EXPECTED_TOOL_TIERS[n] === "gated");
  const autoInUniverse = universe.filter((n) => EXPECTED_TOOL_TIERS[n] === "auto-approve");
  if (gatedInUniverse.length === 0 || autoInUniverse.length === 0) problems.push("census holds no tool of one tier");
  for (const g of EXPECTED_GATED_FQNS) {
    if (getToolTier(g) !== "gated") problems.push(`gated tool changed tier: ${g}`);
  }
  for (const a of EXPECTED_AUTO_FQNS) {
    if (getToolTier(a) !== "auto-approve") problems.push(`auto-approve tool changed tier: ${a}`);
    if (universe.includes(a) && !output.includes(a)) problems.push(`auto-approve tool dropped from the output: ${a}`);
  }
  if (!output.some((n) => n.startsWith(PREFIX))) problems.push("no auto-approve platform tool in the output");
  for (const s of plugins) {
    if (!output.includes(wildcard(s))) problems.push(`plugin wildcard missing: ${wildcard(s)}`);
  }
  return problems;
}

describe("buildAllowedTools: unit census", () => {
  let booted: Booted;
  beforeEach(async () => {
    vi.clearAllMocks();
    toolExtras.length = 0;
    mockReadFileSync.mockImplementation((filePath: string) => {
      if (String(filePath).includes("plugin.json")) {
        return JSON.stringify({ mcpServers: Object.fromEntries(PLUGIN_SERVERS.map((s) => [s, { type: "http", url: "https://x.invalid" }])) });
      }
      throw new Error(`ENOENT: no such file ${filePath}`);
    });
    booted = await bootLegacySession();
  });

  test("the tier map equals the hand-written full table exactly (a flip on ONE side only, in either direction, reds here)", () => {
    expect(TOOL_TIER_MAP).toEqual(EXPECTED_TOOL_TIERS);
    expect(Object.keys(EXPECTED_TOOL_TIERS)).toHaveLength(EXPECTED_AUTO_APPROVE.length + EXPECTED_GATED.length); // no name in both lists
  });

  test("the booted universe is exactly the registered tools; each is in the table; auto-approve ones are pre-approved and gated ones are not", () => {
    const { platformToolNames, options } = booted;
    for (const n of platformToolNames) expect(EXPECTED_TOOL_TIERS, `no expected tier for registered tool ${n}`).toHaveProperty([n]);
    const allowed = options.allowedTools as string[];
    const autoRegistered = platformToolNames.filter((n) => EXPECTED_TOOL_TIERS[n] === "auto-approve");
    const gatedRegistered = platformToolNames.filter((n) => EXPECTED_TOOL_TIERS[n] === "gated");
    expect(autoRegistered.length).toBeGreaterThan(0);
    expect(gatedRegistered.length).toBeGreaterThan(0);
    for (const n of autoRegistered) expect(allowed, `auto-approve tool missing from allowedTools: ${n}`).toContain(n);
    for (const n of gatedRegistered) expect(allowed, `gated tool pre-approved: ${n}`).not.toContain(n);
    // and the platform part of allowedTools is exactly the auto-approve registered set
    expect(allowed.filter((n) => n.startsWith(PREFIX)).sort()).toEqual([...new Set(autoRegistered)].sort());
    expect(assertCensus(buildAllowedTools(platformToolNames, PLUGIN_SERVERS), platformToolNames, PLUGIN_SERVERS)).toEqual([]);
  });

  test("the booted legacy session registers every hand-listed tool except the cc-only ones (a deleted or renamed tool shows here)", () => {
    const ccOnly = new Set(["edit_c4_diagram", "narrate", "summarize", "auth_revocation_status"].map(fqn));
    const expectedRegistered = [...EXPECTED_GATED_FQNS, ...EXPECTED_AUTO_FQNS].filter((n) => !ccOnly.has(n));
    for (const n of expectedRegistered) expect(booted.platformToolNames, `expected registered: ${n}`).toContain(n);
  });

  test("every hand-listed gated entry is absent even when handed to the filter explicitly", () => {
    expect(buildAllowedTools(EXPECTED_GATED_FQNS, PLUGIN_SERVERS)).toEqual(PLUGIN_SERVERS.map(wildcard));
  });

  test("every gated tool has a content-free offline label (not the generic fallback)", () => {
    const generic = buildOfflineGateMessage(fqn("some_unlisted_future_tool"), {});
    for (const g of EXPECTED_GATED_FQNS) expect(buildOfflineGateMessage(g, {}), `no OFFLINE_ACTION_LABELS entry for ${g}`).not.toBe(generic);
  });

  // --- must-PASS inputs that are not the canonical one -----------------------------------------------------------------
  test("a shuffled input yields the same set", () => {
    const names = [...booted.platformToolNames];
    const shuffled = [...names].reverse().sort((a, b) => (a.length % 3) - (b.length % 3));
    expect([...buildAllowedTools(shuffled, PLUGIN_SERVERS)].sort()).toEqual([...buildAllowedTools(names, PLUGIN_SERVERS)].sort());
  });

  test("duplicate names do not duplicate the output", () => {
    const out = buildAllowedTools([fqn("kb_share_list"), fqn("kb_share_list"), fqn("email_send")], ["context7", "context7"]);
    expect(out.filter((n) => n === fqn("kb_share_list"))).toHaveLength(1);
    expect(out.filter((n) => n === wildcard("context7"))).toHaveLength(1);
    expect(out).not.toContain(fqn("email_send"));
  });

  test("a list holding only auto-approve names is returned whole", () => {
    expect(buildAllowedTools(EXPECTED_AUTO_FQNS, [])).toEqual(EXPECTED_AUTO_FQNS);
  });

  test.each([
    ["no plugin servers", [] as string[]],
    ["one plugin server", ["context7"]],
    ["two plugin servers", ["context7", "stripe"]],
  ])("%s: wildcards are exactly mcp__plugin_soleur_<server>__*", (_l, servers) => {
    const out = buildAllowedTools([fqn("kb_share_list")], servers);
    expect(out).toEqual([fqn("kb_share_list"), ...servers.map(wildcard)]);
  });

  test("an empty input is an empty array (the call site omits the key; an empty list pre-approves nothing)", () => {
    expect(buildAllowedTools([], [])).toEqual([]);
  });

  test("invalid plugin server names are omitted (fail closed), valid ones kept", () => {
    const out = buildAllowedTools([], ["ok-1", "Bad Name", "a/b", "", "UPPER", "x__y*", "mcp__*"]);
    expect(out).toEqual([wildcard("ok-1")]);
  });

  test("blocked-tier, unknown-prefix, empty-suffix, case-variant and rule-content names are all dropped", () => {
    const hostile = [
      "mcp__other_server__kb_share_list",
      PREFIX,
      "MCP__soleur_platform__kb_share_list",
      ` ${fqn("kb_share_list")}`,
      `${fqn("kb_share_list")}(*)`,
      "kb_share_list",
      "Read",
      "__proto__",
    ];
    expect(buildAllowedTools(hostile, [])).toEqual([]);
  });

  test("the source arrays are not mutated", () => {
    const names = Object.freeze([fqn("kb_share_list"), fqn("email_send")]);
    const servers = Object.freeze(["context7"]);
    expect(() => buildAllowedTools(names, servers)).not.toThrow();
    expect(names).toEqual([fqn("kb_share_list"), fqn("email_send")]);
  });

  // -------------------------------------------------------------------------------------------------------------------
  // Mutation battery (Guard 1, rows 1 to 3 plus the call-site revert): each mutant filter must be flagged by the oracle.
  // -------------------------------------------------------------------------------------------------------------------
  describe("mutation battery (mutant filters through one oracle)", () => {
    const real = (names: readonly string[], plugins: readonly string[]) => buildAllowedTools(names, plugins);
    const NEW_TOOL = fqn("new_write_tool"); // no tier entry: default-gated
    const mutants: [string, (names: readonly string[], plugins: readonly string[]) => string[]][] = [
      ["1: keeps one gated tool (special-cased email_send)", (n, p) => [...real(n, p), fqn("email_send")]],
      ["2a: empty filter", () => []],
      ["2b: drops the plugin wildcards", (n) => real(n, [])],
      ["2c: inverted predicate", (n, p) => [...n.filter((x) => getToolTier(x) !== "auto-approve"), ...p.map(wildcard)]],
      [
        "3: explicit-only key (keeps anything not explicitly gated)",
        (n, p) => [...n.filter((x) => TOOL_TIER_MAP[x] !== "gated"), ...p.map(wildcard)],
      ],
      ["4: call-site revert (raw list plus wildcards)", (n, p) => [...n, ...p.map(wildcard)]],
    ];

    test("the real filter is clean on the same inputs (control, green before any mutant is believed)", () => {
      const universe = [...booted.platformToolNames, NEW_TOOL];
      expect(assertCensus(real(universe, PLUGIN_SERVERS), universe, PLUGIN_SERVERS)).toEqual([]);
    });

    test.each(mutants)("mutant %s is flagged", (_label, mutant) => {
      // an unclassified tool appended AFTER compliant first entries (row 3)
      const universe = [...booted.platformToolNames, NEW_TOOL];
      expect(assertCensus(mutant(universe, PLUGIN_SERVERS), universe, PLUGIN_SERVERS).length).toBeGreaterThan(0);
    });

    test("an empty census (the derivation yields nothing) is flagged, not read as vacuously clean", () => {
      expect(assertCensus([], [], PLUGIN_SERVERS).length).toBeGreaterThan(0);
    });

    test("the oracle itself is sensitive: one gated name in an otherwise perfect output is reported by name", () => {
      const universe = [...booted.platformToolNames];
      const good = real(universe, PLUGIN_SERVERS);
      expect(assertCensus(good, universe, PLUGIN_SERVERS)).toEqual([]);
      const bad = assertCensus([...good, fqn("email_send")], universe, PLUGIN_SERVERS);
      expect(bad.join("\n")).toContain(fqn("email_send"));
    });

    test.each(["routine_run", "crm_contact_upsert", "crm_contact_set_stage", "workstream_issue_create", "workstream_issue_set_status", "workstream_issue_update_title"])(
      "tier flip: %s made auto-approve is caught by the full table (it was NOT caught by the eight-name pin)",
      (name) => {
        const original = TOOL_TIER_MAP[fqn(name)];
        TOOL_TIER_MAP[fqn(name)] = "auto-approve";
        try {
          const universe = [...booted.platformToolNames];
          const out = real(universe, PLUGIN_SERVERS);
          expect(out).toContain(fqn(name));
          expect(assertCensus(out, universe, PLUGIN_SERVERS).join("\n")).toContain(`gated tool changed tier: ${fqn(name)}`);
          expect(TOOL_TIER_MAP).not.toEqual(EXPECTED_TOOL_TIERS);
        } finally {
          TOOL_TIER_MAP[fqn(name)] = original;
        }
        expect(getToolTier(fqn(name))).toBe("gated");
      },
    );

    test("tier flip: email_send made auto-approve in the map is caught by the table", () => {
      const original = TOOL_TIER_MAP[fqn("email_send")];
      TOOL_TIER_MAP[fqn("email_send")] = "auto-approve";
      try {
        const universe = [...booted.platformToolNames];
        const out = real(universe, PLUGIN_SERVERS);
        expect(out).toContain(fqn("email_send")); // the flipped filter now keeps it...
        expect(assertCensus(out, universe, PLUGIN_SERVERS).join("\n")).toMatch(/gated tool changed tier/); // ...and the table says so
        expect(TOOL_TIER_MAP).not.toEqual(EXPECTED_TOOL_TIERS);
      } finally {
        TOOL_TIER_MAP[fqn("email_send")] = original;
      }
      expect(getToolTier(fqn("email_send"))).toBe("gated");
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  // Explicit tier entry for every registered platform name ("decided", not "defaulted"), read from a booted session.
  // -------------------------------------------------------------------------------------------------------------------
  describe("explicit tier entries over a booted legacy session", () => {
    test("every name handed to canUseTool has an explicit TOOL_TIER_MAP entry (a new tool fails CI until its tier is decided)", () => {
      const missing = booted.platformToolNames.filter((n) => !Object.hasOwn(TOOL_TIER_MAP, n));
      expect(missing).toEqual([]);
    });

    test("the cc-soleur-go registry names (narrate/summarize, edit_c4_diagram, the crm-lead set) are decided in the table too", async () => {
      const { CC_REGISTERED_PLATFORM_TOOL_NAMES, crmLeadPermissionToolNames } = await import("../server/cc-dispatcher");
      const { C4_TOOL_FQN } = await import("../server/c4-concierge-tools");
      const ccNames = [...CC_REGISTERED_PLATFORM_TOOL_NAMES, C4_TOOL_FQN, ...crmLeadPermissionToolNames(true)];
      expect(ccNames.length).toBeGreaterThan(5); // not vacuous: narrate, summarize, c4 and the crm tools
      for (const n of ccNames) {
        expect(Object.hasOwn(TOOL_TIER_MAP, n), `no explicit tier for cc-registered tool ${n}`).toBe(true);
        expect(TOOL_TIER_MAP[n]).toBe(EXPECTED_TOOL_TIERS[n]);
      }
    });

    test("vacuity guard: the booted census really includes the Plausible, GitHub, account, routines, workstream and CRM builders", () => {
      for (const prefix of ["plausible_", "github_", "account_", "routine", "workstream_issue_", "crm_", "kb_share_", "email_"]) {
        expect(booted.platformToolNames.some((n) => n.startsWith(`${PREFIX}${prefix}`))).toBe(true);
      }
    });

    test("the allowlist is a subset of what the MCP server registered (the allowlist cannot name a tool that does not exist)", () => {
      expect(booted.registered.length).toBeGreaterThan(0);
      for (const n of booted.platformToolNames) expect(booted.registered).toContain(n);
    });

    test("a registered tool that is NOT on the canUseTool allowlist is never pre-approved either", () => {
      const unlisted = booted.registered.filter((n) => !booted.platformToolNames.includes(n));
      for (const n of unlisted) expect(booted.options.allowedTools).not.toContain(n);
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  // Wiring (row 4): the SDK receives exactly the filter's output; canUseTool keeps the UNFILTERED allowlist.
  // -------------------------------------------------------------------------------------------------------------------
  describe("startAgentSession wiring", () => {
    test("options.allowedTools equals buildAllowedTools(platformToolNames, plugin servers) by equality", () => {
      expect(booted.options.allowedTools).toEqual(buildAllowedTools(booted.platformToolNames, PLUGIN_SERVERS));
    });

    test("non-empty, holds an auto-approve tool and the plugin wildcards, holds no registered tool that is not auto-approve", () => {
      const allowed = booted.options.allowedTools as string[];
      expect(allowed.length).toBeGreaterThan(0);
      const autoBooted = EXPECTED_AUTO_FQNS.filter((n) => booted.platformToolNames.includes(n));
      expect(autoBooted.length).toBeGreaterThan(10);
      for (const a of autoBooted) expect(allowed).toContain(a);
      for (const s of PLUGIN_SERVERS) expect(allowed).toContain(wildcard(s));
      for (const n of booted.registered) {
        if (getToolTier(n) !== "auto-approve") expect(allowed).not.toContain(n);
      }
      for (const g of EXPECTED_GATED_FQNS) expect(allowed).not.toContain(g);
    });

    test("canUseTool still receives the unfiltered platform list (filtering it would deny every gated tool outright)", () => {
      for (const g of EXPECTED_GATED_FQNS) expect(booted.platformToolNames).toContain(g);
      expect(booted.platformToolNames.length).toBeGreaterThan(
        (booted.options.allowedTools as string[]).filter((n) => n.startsWith(PREFIX)).length,
      );
    });

    test("canUseTool really routes a gated tool to the review gate (the end-to-end shape the fix depends on)", async () => {
      const verdict = await booted.options.canUseTool(fqn("email_send"), { to: "a@example.invalid", subject: "s", body: "b" }, {
        signal: new AbortController().signal,
      });
      expect(verdict.behavior).toBe("allow"); // the harness gate answers Approve
      const { abortableReviewGate } = await import("../server/review-gate");
      expect(abortableReviewGate).toHaveBeenCalled();
    });
  });

  describe("non-interactive wiring (auto-sync)", () => {
    test("startAgentSession(..., nonInteractive=true) hands the flag to canUseTool, which then denies a gated tool at once", async () => {
      const { abortableReviewGate } = await import("../server/review-gate");
      mockQuery.mockClear();
      canUseToolSpy.mockClear();
      vi.mocked(abortableReviewGate).mockClear();
      await startAgentSession("11111111-1111-4111-8111-111111111111", "conv-2", undefined, undefined, "/soleur:sync --headless", undefined, undefined, false, true);
      expect((canUseToolSpy.mock.calls[0][0] as { nonInteractive?: boolean }).nonInteractive).toBe(true);
      const options = mockQuery.mock.calls[0][0].options;
      const verdict = await options.canUseTool(fqn("email_send"), { to: "a@example.invalid", subject: "s", body: "b" }, { signal: new AbortController().signal });
      expect(verdict).toEqual({
        behavior: "deny",
        message: "This action needs interactive approval and is not available in background sync. Do not retry.",
      });
      expect(abortableReviewGate).not.toHaveBeenCalled();
    });

    test("an ordinary session leaves the flag unset", () => {
      expect((canUseToolSpy.mock.calls[0][0] as { nonInteractive?: boolean }).nonInteractive).toBeUndefined();
    });
  });

  // -------------------------------------------------------------------------------------------------------------------
  // Sentinels for the other routes that could pre-approve a tool ahead of canUseTool.
  // -------------------------------------------------------------------------------------------------------------------
  describe("sentinels", () => {
    test("no platform tool definition passes annotations (readOnlyHint-style hints must not become a pre-approval route)", () => {
      expect(toolExtras.length).toBeGreaterThan(10); // the harness registered real tools
      for (const extras of toolExtras) expect(extras).toBeUndefined();
    });

    // Skill and agent frontmatter `allowed-tools` / `tools` is a pre-approval route. Parse the entries and apply the SAME
    // entry grammar as assertAllowedToolsPreApprovalSafe (not a substring match) to every MCP entry.
    const FRONTMATTER_KEYS = new Set(["allowed-tools", "tools"]);
    function frontmatterToolEntries(text: string): string[] {
      const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
      if (m === null) return [];
      const lines = m[1].split(/\r?\n/);
      const entries: string[] = [];
      const splitTopLevel = (v: string): string[] => {
        const parts: string[] = [];
        let depth = 0;
        let cur = "";
        for (const ch of v) {
          if (ch === "(") depth += 1;
          if (ch === ")") depth = Math.max(0, depth - 1);
          if ((ch === "," || ch === " ") && depth === 0) {
            if (cur.trim()) parts.push(cur.trim());
            cur = "";
          } else cur += ch;
        }
        if (cur.trim()) parts.push(cur.trim());
        return parts;
      };
      for (let i = 0; i < lines.length; i++) {
        const kv = /^([A-Za-z-]+):\s*(.*)$/.exec(lines[i]);
        if (kv === null || !FRONTMATTER_KEYS.has(kv[1])) continue;
        const inline = kv[2].replace(/^\[|\]$/g, "").trim();
        if (inline) entries.push(...splitTopLevel(inline).map((e) => e.replace(/^["']|["']$/g, "")));
        for (let j = i + 1; j < lines.length; j++) {
          const item = /^\s+-\s+(.*)$/.exec(lines[j]);
          if (item === null) break;
          entries.push(item[1].trim().replace(/^["']|["']$/g, ""));
        }
      }
      return entries;
    }

    test("the frontmatter parser handles inline, bracketed and block lists, and parenthesised commas", () => {
      expect(frontmatterToolEntries("---\nname: x\nallowed-tools: Read, Bash(git add:*, git commit:*), mcp__a__b\n---\nbody")).toEqual([
        "Read",
        "Bash(git add:*, git commit:*)",
        "mcp__a__b",
      ]);
      expect(frontmatterToolEntries('---\ntools: ["Read", "mcp__soleur_platform__email_send"]\n---')).toEqual(["Read", "mcp__soleur_platform__email_send"]);
      expect(frontmatterToolEntries("---\nallowed-tools:\n  - Read\n  - mcp__soleur_platform__email_send\nother: 1\n---")).toEqual([
        "Read",
        "mcp__soleur_platform__email_send",
      ]);
      expect(frontmatterToolEntries("no frontmatter")).toEqual([]);
    });

    test("the entry grammar the sentinel applies rejects a gated platform entry in skill frontmatter and accepts an auto-approve one", () => {
      expect(() => assertAllowedToolsPreApprovalSafe({ allowedTools: ["mcp__soleur_platform__email_send"] })).toThrow(/pre-approv/i);
      expect(() => assertAllowedToolsPreApprovalSafe({ allowedTools: ["mcp__soleur_platform__kb_share_list"] })).not.toThrow();
    });

    // An entry can pre-approve a platform tool when it names the platform server or is a wildcard whose prefix covers it.
    const couldCoverPlatform = (entry: string): boolean => {
      const n = entry.trim().toLowerCase();
      if (n.startsWith("mcp__soleur_platform")) return true;
      const star = n.indexOf("*");
      return star !== -1 && "mcp__soleur_platform__".startsWith(n.slice(0, star));
    };

    // Walks the given files and returns every frontmatter tool entry that would pre-approve a platform tool the assertion
    // refuses. Third-party plugin MCP entries (stripe, linear) are pre-approved by their skills by design and are outside this
    // guard: they are not gated platform tools (reported separately in the PR notes).
    function findOffenders(files: readonly string[], readFile: (f: string) => string): { offenders: string[]; parsedEntries: number } {
      let parsedEntries = 0;
      const offenders: string[] = [];
      for (const f of files) {
        for (const entry of frontmatterToolEntries(readFile(f))) {
          parsedEntries += 1;
          if (!couldCoverPlatform(entry)) continue;
          try {
            assertAllowedToolsPreApprovalSafe({ allowedTools: [entry] });
          } catch {
            offenders.push(`${f}: ${entry}`);
          }
        }
      }
      return { offenders, parsedEntries };
    }

    test("findOffenders known-positive control: a temp SKILL.md pre-approving a gated platform tool, or a bare mcp__* wildcard, is flagged", async () => {
      const fs = await vi.importActual<typeof import("fs")>("fs");
      const os = await vi.importActual<typeof import("os")>("os");
      const dir = fs.mkdtempSync(join(os.tmpdir(), "census-control-"));
      try {
        const gated = join(dir, "gated.md");
        const wild = join(dir, "wild.md");
        const clean = join(dir, "clean.md");
        fs.writeFileSync(gated, "---\nname: x\nallowed-tools: mcp__soleur_platform__email_send\n---\nbody");
        fs.writeFileSync(wild, "---\nname: y\nallowed-tools:\n  - Read\n  - mcp__*\n---\nbody");
        fs.writeFileSync(clean, "---\nname: z\nallowed-tools: Read, mcp__soleur_platform__kb_share_list, mcp__plugin_soleur_stripe__*\n---\nbody");
        const read = (f: string) => fs.readFileSync(f, "utf8");
        expect(findOffenders([gated], read).offenders).toEqual([`${gated}: mcp__soleur_platform__email_send`]);
        expect(findOffenders([wild], read).offenders).toEqual([`${wild}: mcp__*`]);
        expect(findOffenders([clean], read).offenders).toEqual([]); // and the control is not simply flagging everything
        expect(findOffenders([clean], read).parsedEntries).toBe(3);
      } finally {
        fs.rmSync(dir, { recursive: true, force: true });
      }
    });

    test("no plugin skill, agent or command frontmatter pre-approves a platform tool the assertion would refuse", async () => {
      const fs = await vi.importActual<typeof import("fs")>("fs");
      const root = join(__dirname, "..", "..", "..", "plugins", "soleur");
      const files: string[] = [];
      const walk = (dir: string, match: (f: string) => boolean) => {
        for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
          const p = join(dir, e.name);
          if (e.isDirectory()) walk(p, match);
          else if (match(e.name)) files.push(p);
        }
      };
      walk(join(root, "skills"), (f) => f === "SKILL.md");
      walk(join(root, "agents"), (f) => f.endsWith(".md"));
      walk(join(root, "commands"), (f) => f.endsWith(".md"));
      expect(files.length).toBeGreaterThan(20); // not vacuous: the walk found the plugin
      const { offenders, parsedEntries } = findOffenders(files, (f) => fs.readFileSync(f, "utf8"));
      expect(parsedEntries).toBeGreaterThan(0); // the parser found real allowed-tools entries
      expect(offenders).toEqual([]);
    });
  });
});
