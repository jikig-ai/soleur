/**
 * #11303 — gated-tier allowedTools bypass: census, in-suite mutation battery and wiring.
 *
 * The Claude Agent SDK approves a bare `allowedTools` entry BEFORE it consults `canUseTool`, so a gated platform tool that
 * is listed there runs with no review card. `buildAllowedTools` is the single filter between the registered platform tool
 * names and the SDK pre-approval list. Guard 1 of the plan: no platform tool whose effective tier is not `auto-approve`
 * is ever handed to the SDK as pre-approved by any runner.
 *
 * Layout:
 *   1. unit census over `buildAllowedTools` (derived universe, pinned floors)
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
import { buildAllowedTools, getToolTier, TOOL_TIER_MAP } from "../server/tool-tiers";
import { DEFAULT_API_KEY_ROW, createSupabaseMockImpl, createQueryMock } from "./helpers/agent-runner-mocks";

// ---------------------------------------------------------------------------------------------------------------------
// Pinned anchors (live in the test on purpose: a single diff that edits the tier map AND this file is what review catches;
// the real-SDK probe independently refuses to run if these eight are not gated).
// ---------------------------------------------------------------------------------------------------------------------
const PREFIX = "mcp__soleur_platform__";
const fqn = (n: string) => `${PREFIX}${n}`;
const wildcard = (s: string) => `mcp__plugin_soleur_${s}__*`;

const PINNED_GATED = [
  "email_send",
  "email_reply",
  "email_suppress",
  "github_push_branch",
  "create_pull_request",
  "github_trigger_workflow",
  "kb_share_create",
  "workspace_set_autonomous",
].map(fqn);
const PINNED_AUTO = [
  "kb_share_list",
  "kb_share_preview",
  "email_triage_list",
  "email_triage_get",
  "inbox_list",
  "crm_contact_list",
  "github_read_issue",
  "conversations_lookup",
  "workspace_get_autonomous",
].map(fqn);

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
    if (n.startsWith(PREFIX) && getToolTier(n) !== "auto-approve") problems.push(`non-auto platform tool pre-approved: ${n}`);
  }
  // floors: a vacuous census or a vacuous filter must not read as green
  if (universe.length < PINNED_GATED.length + PINNED_AUTO.length) problems.push("census smaller than the pinned floor");
  for (const g of PINNED_GATED) {
    if (!universe.includes(g)) problems.push(`pinned gated tool missing from the census: ${g}`);
    if (getToolTier(g) !== "gated") problems.push(`pinned gated tool changed tier: ${g}`);
  }
  for (const a of PINNED_AUTO) {
    if (universe.includes(a) && !output.includes(a)) problems.push(`pinned auto-approve tool dropped from the output: ${a}`);
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

  test("the universe is derived from the real builders, covers the pinned sets, and the output is exactly its auto-approve part", () => {
    const { platformToolNames } = booted;
    for (const n of [...PINNED_GATED, ...PINNED_AUTO]) expect(platformToolNames).toContain(n);
    const out = buildAllowedTools(platformToolNames, PLUGIN_SERVERS);
    const platformOut = out.filter((n) => n.startsWith(PREFIX));
    expect([...platformOut].sort()).toEqual(
      [...new Set(platformToolNames.filter((n) => getToolTier(n) === "auto-approve"))].sort(),
    );
    expect(assertCensus(out, platformToolNames, PLUGIN_SERVERS)).toEqual([]);
    // the gated part of the universe is non-trivial and entirely absent
    const gated = platformToolNames.filter((n) => getToolTier(n) !== "auto-approve");
    expect(gated.length).toBeGreaterThan(PINNED_GATED.length - 1);
    for (const g of gated) expect(out).not.toContain(g);
  });

  test("every TOOL_TIER_MAP gated entry is absent even when handed to the filter explicitly", () => {
    const gatedKeys = Object.entries(TOOL_TIER_MAP).filter(([, t]) => t === "gated").map(([k]) => k);
    expect(gatedKeys.length).toBeGreaterThan(PINNED_GATED.length - 1);
    expect(buildAllowedTools(gatedKeys, PLUGIN_SERVERS)).toEqual(PLUGIN_SERVERS.map(wildcard));
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
    expect(buildAllowedTools(PINNED_AUTO, [])).toEqual(PINNED_AUTO);
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

    test("tier flip: email_send made auto-approve in the map is caught by the pinned set", () => {
      const original = TOOL_TIER_MAP[fqn("email_send")];
      TOOL_TIER_MAP[fqn("email_send")] = "auto-approve";
      try {
        const universe = [...booted.platformToolNames];
        const out = real(universe, PLUGIN_SERVERS);
        expect(out).toContain(fqn("email_send")); // the flipped filter now keeps it...
        expect(assertCensus(out, universe, PLUGIN_SERVERS).join("\n")).toMatch(/pinned gated tool changed tier/); // ...and the pin says so
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
      for (const a of PINNED_AUTO) expect(allowed).toContain(a);
      for (const s of PLUGIN_SERVERS) expect(allowed).toContain(wildcard(s));
      for (const n of booted.registered) {
        if (getToolTier(n) !== "auto-approve") expect(allowed).not.toContain(n);
      }
      for (const g of PINNED_GATED) expect(allowed).not.toContain(g);
    });

    test("canUseTool still receives the unfiltered platform list (filtering it would deny every gated tool outright)", () => {
      for (const g of PINNED_GATED) expect(booted.platformToolNames).toContain(g);
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

  // -------------------------------------------------------------------------------------------------------------------
  // Sentinels for the other routes that could pre-approve a tool ahead of canUseTool.
  // -------------------------------------------------------------------------------------------------------------------
  describe("sentinels", () => {
    test("no platform tool definition passes annotations (readOnlyHint-style hints must not become a pre-approval route)", () => {
      expect(toolExtras.length).toBeGreaterThan(10); // the harness registered real tools
      for (const extras of toolExtras) expect(extras).toBeUndefined();
    });

    test("no plugin skill or agent frontmatter names mcp__soleur_platform__ (skill allowed-tools is a pre-approval route)", async () => {
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
      expect(files.length).toBeGreaterThan(20); // not vacuous: the walk found the plugin
      const offenders = files.filter((f) => {
        const text = fs.readFileSync(f, "utf8");
        const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
        return m !== null && m[1].includes("mcp__soleur_platform__");
      });
      expect(offenders).toEqual([]);
    });
  });
});
