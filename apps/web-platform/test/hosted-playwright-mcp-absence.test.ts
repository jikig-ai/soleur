// Pin: Playwright MCP is not wired into hosted (web-platform) agent sessions (Ref #11076, epic #9601, ADR-287).
//
// Hosted sessions load the platform plugin copy via `plugins: [{ type: "local", path: trustedPluginPath }]`.
// `plugins/soleur/.mcp.json` DOES declare `playwright` (for the Claude Code plugin on a developer machine);
// the hosted path stays clear of it through a CHAIN, and a single string assertion would pin only one link:
//   1. plugin.json `mcpServers` (the list the legacy runner turns into allowedTools wildcards) names no playwright;
//   2. the app .dockerignore excludes `_plugin-vendored/.mcp.json` AFTER the `**/*.json` re-include (last match wins);
//   3. every workflow that vendors the plugin into `_plugin-vendored` deletes `.mcp.json` after the copy;
//   4. `buildAgentQueryOptions` (legacy + cc-shaped args, web egress on) emits no playwright mcpServers/allowedTools entry;
//   5. no server source outside server/inngest/ mentions playwright at all.
// A regression in any link turns this red. The test reads OUTSIDE apps/web-platform, so it is registered in
// `repo-wide-suites.ts` (repo-wide-containment.test.ts recomputes membership).

import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { buildAgentQueryOptions } from "@/server/agent-runner-query-options";
import { buildAllowedTools } from "@/server/tool-tiers";
import { resolveWorkspaceMode } from "@/server/workspace-mode";

const REPO_ROOT = resolve(__dirname, "../../..");
const APP_ROOT = resolve(REPO_ROOT, "apps/web-platform");
const PLAYWRIGHT = /playwright/i;

const read = (p: string): string => readFileSync(p, "utf-8");

// Collection-time census: every row below is registered through `row()`, and the floor at the end
// of the file fails if a refactor silently drops rows (a table that loses rows stays green otherwise).
let registered = 0;
const REGISTERED_FLOOR = 8;
function row(name: string, fn: () => void): void {
  registered += 1;
  it(name, fn);
}

// ---------------------------------------------------------------- leg 1: plugin.json
const PLUGIN_JSON = resolve(REPO_ROOT, "plugins/soleur/.claude-plugin/plugin.json");
const pluginMcpServerNames = Object.keys(
  (JSON.parse(read(PLUGIN_JSON)) as { mcpServers?: Record<string, unknown> }).mcpServers ?? {},
);

describe("leg 1: plugin.json mcpServers", () => {
  row("declares at least one MCP server (so the scan below is not vacuous)", () => {
    expect(pluginMcpServerNames.length).toBeGreaterThanOrEqual(1);
  });
  row("no mcpServers key matches /playwright/i", () => {
    expect(pluginMcpServerNames.filter((k) => PLAYWRIGHT.test(k))).toEqual([]);
  });
});

// ---------------------------------------------------------------- leg 2: .dockerignore ordering
describe("leg 2: apps/web-platform/.dockerignore", () => {
  const lines = read(join(APP_ROOT, ".dockerignore")).split("\n").map((l) => l.trim());
  // Content anchors, not line numbers: the position of each pattern is found by exact line text.
  const jsonBang = lines.lastIndexOf("!_plugin-vendored/**/*.json");
  const mcpExclude = lines.lastIndexOf("_plugin-vendored/.mcp.json");

  row("re-includes vendored json (anchor present, so the ordering check is meaningful)", () => {
    expect(jsonBang).toBeGreaterThanOrEqual(0);
  });
  row("excludes _plugin-vendored/.mcp.json AFTER the **/*.json bang (last match wins)", () => {
    expect(mcpExclude).toBeGreaterThanOrEqual(0);
    expect(mcpExclude).toBeGreaterThan(jsonBang);
  });
});

// ---------------------------------------------------------------- leg 3: vendoring workflows
const WORKFLOWS_DIR = resolve(REPO_ROOT, ".github/workflows");
// The vendoring copy: `cp -a [flags] plugins/soleur "$DEST"` (derived by grep, not a hard-coded list).
const VENDOR_CP = /^\s*cp -a\b[^\n]*\bplugins\/soleur\s+"\$DEST"/m;
const RM_MCP = 'rm -f "$DEST/.mcp.json"';
const vendoringWorkflows = readdirSync(WORKFLOWS_DIR)
  .filter((f) => /\.ya?ml$/.test(f))
  .map((f) => ({ file: f, text: read(join(WORKFLOWS_DIR, f)) }))
  .filter(({ text }) => VENDOR_CP.test(text));

describe("leg 3: workflows vendoring the plugin delete .mcp.json", () => {
  row("finds at least 2 vendoring workflows (ci.yml + reusable-release.yml today)", () => {
    expect(vendoringWorkflows.length).toBeGreaterThanOrEqual(2);
  });
  for (const { file, text } of vendoringWorkflows) {
    row(`${file}: rm -f of $DEST/.mcp.json follows the vendoring cp`, () => {
      const cpAt = text.search(VENDOR_CP);
      const rmAt = text.indexOf(RM_MCP, cpAt);
      expect(cpAt).toBeGreaterThanOrEqual(0);
      expect(rmAt).toBeGreaterThan(cpAt);
    });
  }
});

// ---------------------------------------------------------------- leg 4: runtime option build
const egress = { workspaceId: "w", token: "t", port: 1 };
const baseArgs = {
  workspacePath: "/tmp/test-workspace",
  pluginPath: "/tmp/test-workspace/plugins/soleur",
  credential: { value: "sk-test", scheme: "api_key" as const },
  serviceTokens: {} as Record<string, string>,
  systemPrompt: "router",
  canUseTool: (async () => ({ behavior: "allow" as const, updatedInput: {} })) as never,
  webEgress: egress,
};

const RUNTIME_CASES: ReadonlyArray<readonly [string, Parameters<typeof buildAgentQueryOptions>[0]]> = [
  [
    // Legacy runner: allowedTools = buildAllowedTools(platform names, REAL plugin.json server names).
    "legacy args (real plugin.json server names -> wildcards)",
    {
      ...baseArgs,
      mode: resolveWorkspaceMode("command_center"),
      mcpServers: { soleur_platform: {} },
      allowedTools: buildAllowedTools([], pluginMcpServerNames),
    },
  ],
  [
    // cc-soleur-go shape: empty mcpServers, read-only auto-approve list, extraDisallowedTools.
    "cc-shaped args (command center)",
    {
      ...baseArgs,
      mode: resolveWorkspaceMode("command_center"),
      mcpServers: {},
      allowedTools: ["Read", "Glob", "Grep", "WebFetch"],
      extraDisallowedTools: ["TodoWrite"],
    },
  ],
  [
    "cc-shaped args (support)",
    {
      ...baseArgs,
      mode: resolveWorkspaceMode("support"),
      mcpServers: {},
      allowedTools: ["Read", "Glob", "Grep"],
    },
  ],
];

describe("leg 4: buildAgentQueryOptions with web egress on", () => {
  for (const [name, args] of RUNTIME_CASES) {
    row(`${name}: no playwright in mcpServers keys or allowedTools`, () => {
      const opts = buildAgentQueryOptions(args) as {
        mcpServers?: Record<string, unknown>;
        allowedTools?: string[];
      };
      const mcpKeys = Object.keys(opts.mcpServers ?? {});
      const allowed = opts.allowedTools ?? [];
      // The sentinel: the legacy row proves the real plugin servers flowed through, so "no playwright" is not vacuous.
      if (name.startsWith("legacy")) expect(allowed.length).toBeGreaterThanOrEqual(1);
      expect(mcpKeys.filter((k) => PLAYWRIGHT.test(k))).toEqual([]);
      expect(allowed.filter((t) => PLAYWRIGHT.test(t))).toEqual([]);
    });
  }
});

// ---------------------------------------------------------------- leg 5: source scan
const SERVER_DIR = join(APP_ROOT, "server");
const SCAN_FLOOR = 250;

function walk(dir: string, out: string[]): string[] {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) {
      // The cron/Inngest tree legitimately names Playwright (ux-audit); it never builds a hosted agent session.
      if (full === join(SERVER_DIR, "inngest")) continue;
      walk(full, out);
    } else {
      out.push(full);
    }
  }
  return out;
}
const scanned = walk(SERVER_DIR, []);

describe("leg 5: server source outside server/inngest/", () => {
  row(`scans at least ${SCAN_FLOOR} files (the scan is not vacuous)`, () => {
    expect(scanned.length).toBeGreaterThanOrEqual(SCAN_FLOOR);
  });
  row("no file mentions playwright (case-insensitive)", () => {
    const offenders = scanned
      .filter((f) => PLAYWRIGHT.test(read(f)))
      .map((f) => relative(APP_ROOT, f));
    expect(offenders).toEqual([]);
  });
});

// ---------------------------------------------------------------- census
describe("census", () => {
  it(`registered at least ${REGISTERED_FLOOR} rows at collection time`, () => {
    expect(registered).toBeGreaterThanOrEqual(REGISTERED_FLOOR);
  });
});
