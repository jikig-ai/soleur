import { describe, it, expect } from "vitest";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { TOOL_TIER_MAP } from "@/server/tool-tiers";
import { CC_REGISTERED_PLATFORM_TOOL_NAMES } from "@/server/cc-dispatcher";

// Absence pin (#11258): no agent-reachable surface over the workspace egress audit summary exists today, and a change that
// adds one fails here first. The decision, the threat model, the constraints a future surface must meet and the three
// re-evaluation triggers are recorded in ADR-288, "Amendment 2026-11-04 (#11258)" (see its "What the pin does not see": this
// is a text scan of repository source plus two runtime assertions, not a proof that no surface exists).
//
// The scan deliberately does NOT strip comments: a comment that names an egress-audit function in an agent-surface file is a
// finding, not noise. It reads only files under apps/web-platform (never knowledge-base/), so it stays in the diff-gated
// `unit` project. It does not read the ADR: the record is held by review and by the failure message below.

const APP_ROOT = path.resolve(__dirname, "..");
// Every top-level directory is scanned unless named here, so a new directory is covered by default. These hold no
// application source: dependencies, build output and reports, this suite, browser tests, static assets, docs, SQL and CI config.
// Arm (g) refuses a production import that resolves into any of the source-bearing ones (test, e2e, docs, supabase).
const EXCLUDED_TOP_DIRS = new Set([
  "node_modules", ".next", ".git", ".github", "dist", "out", "coverage", "playwright-report", "test-results",
  "test", "e2e", "public", "assets", "docs", "supabase",
]);
const SOURCE_EXT = /\.[cm]?[jt]sx?$/;
// Test-named files are not scanned; arm (g) fails if production code imports one (or any module in an excluded directory).
const TEST_FILE = /\.(test|spec)\.[cm]?[jt]sx?$|(^|\/)__tests__\//;

// The two member-read functions (migrations 177 and 183), the egress-audit family in any spelling, the rollup table and the
// loader module. Import forms are bounded to real specifiers so a prose comment that says "from `x`" does not match.
const RPC_NAME = /get_egress_audit_(window_)?summary/;
const EGRESS_AUDIT = /egress[-_]?audit/i; // also camelCase (loadEgressAudit) and the rollup table name
const TABLE_NAME = /egress_audit_rollup/;
// Spellings: static `from`, dynamic `import(`, `require(`, `require.resolve(`, `new URL(`, and a bare `import "x"`, with block
// comments allowed before the specifier (webpack magic comments). The arms are unambiguous so a long whitespace run stays linear.
const CMT = String.raw`(?:\/\*[^*]*\*+(?:[^/*][^*]*\*+)*\/\s*)*`;
const IMPORT_SPEC =
  String.raw`(?:from\s*["']|import\s*(?:\(\s*` + CMT + String.raw`)?["'\x60]|require(?:\.resolve)?\s*\(\s*` + CMT +
  String.raw`["'\x60]|new\s+URL\s*\(\s*["'\x60])`;
const LOADER_IMPORT = new RegExp(IMPORT_SPEC + String.raw`[^"'\x60]*egress-audit-read[^"'\x60]*["'\x60]`);
const TEST_IMPORT = new RegExp(
  IMPORT_SPEC + String.raw`(?:[^"'\x60]*(?:\.(?:test|spec)|__tests__)|(?:@\/|(?:\.\.?\/)+)(?:test|e2e|docs|supabase)\/)[^"'\x60]*["'\x60]`,
);

// An agent-surface file is a platform tool builder (filename arm) or any file that builds, registers or classifies tools, or
// imports the Agent SDK (marker arm). Both arms are measured separately so that dropping one is visible.
// This arm is a mention check on files that look like tool code, not a reachability check (see the ADR amendment).
const AGENT_FILENAME = /(^|\/)(?:[^/]*-)?tools?\.[cm]?[jt]sx?$|[a-z]Tools?\.[cm]?[jt]sx?$|(^|\/)tools\//;
const AGENT_MARKER =
  /createSdkMcpServer|mcp__soleur_platform__|TOOL_TIER_MAP|CC_MCP_ALLOWLIST|mcpServers:|canUseTool|@anthropic-ai\/claude-agent-sdk/;

// Today's expected sets, each with the reason it is there. Editing one is a deliberate act that belongs in the same PR as the
// ADR record and its review.
const EXPECTED_NAME_FILES: Record<string, string> = {
  "lib/egress-audit/summary.ts": "type comment naming the function",
  "server/dsar-export-allowlist.ts": "comment only; may legitimately disappear when the table moves into the DSAR allowlist",
  "server/egress-audit-read.ts": "the only caller of the RPC (the member loader)",
};
const EXPECTED_TABLE_FILES: Record<string, string> = {
  "server/account-delete.ts": "erasure saga step",
  "server/dsar-export-allowlist.ts": "comment only (see above)",
  "server/egress-audit-ingest.ts": "write-side ingest",
};
const EXPECTED_LOADER_IMPORTERS: Record<string, string> = {
  "app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx": "member page (server component)",
  "app/(dashboard)/dashboard/settings/scope-grants/page.tsx": "Scope Grants card (server component)",
};
// Production files allowed to import from an excluded directory, each with its reason.
const EXPECTED_EXCLUDED_DIR_IMPORTERS: Record<string, string> = {
  "vitest.config.ts": "test-runner config importing the suite registry from test/; not application code",
};
// About 95% of the 1049 files measured on 2026-11-04 (a floor with margin, not an exact count), and a per-directory minimum so
// that excluding a whole directory (e.g. scripts, hooks, infra) is visible. Measured: server 446, lib 120, app 175, components
// 234, hooks 18, scripts 42, infra 3, top-level files 11.
const MIN_SCANNED_FILES = 1000;
const MIN_PER_TOP_DIR: Record<string, number> = { server: 400, lib: 100, app: 150, components: 200, hooks: 15, scripts: 35, infra: 2 };
// Named members of each arm, so that a regex or marker rename that shrinks an arm to a stray file is visible.
const FILENAME_ARM_MEMBERS = ["server/narrate-tool.ts", "server/inbox-tools.ts", "server/approval/tools.ts"];
const MARKER_ARM_MEMBERS = ["server/cc-dispatcher.ts", "server/tool-tiers.ts", "server/agent-runner.ts"];

const POINTER =
  "If this file is not an agent tool, MCP entry or allowlist, remove the egress-audit reference. If it is a UI-only consumer, " +
  "add it to the expected set with a reason and record it in the ADR. If it is agent-reachable, STOP: it needs the human " +
  "operator's sign-off, the CTO ruling holder, and legal and security review first; do not edit the expected sets to make this pass. A removed " +
  "entry means the set and the ADR need updating. Record: " +
  "knowledge-base/engineering/architecture/decisions/ADR-288-aggregated-egress-audit-spool-via-vector-to-app-ingest.md, " +
  "amendment 2026-11-04 (#11258).";

// For failures of the scan itself (not an egress-audit finding): the window must stay faithful to the tree.
const POINTER_SCAN =
  "The scan window must stay faithful to the tree: a symlink, an unreadable file or a production import of a module the scan " +
  "does not read (test, e2e, docs, SQL) hides code from this pin. Move the code into a scanned location or remove the import; " +
  "do not widen the exclusions without the review recorded in ADR-288, amendment 2026-11-04 (#11258).";

type Scanned = { rel: string; text: string };

function walkSources(dirRel: string, top: boolean): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(path.join(APP_ROOT, dirRel), { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name === ".next") continue;
    const rel = dirRel === "" ? entry.name : `${dirRel}/${entry.name}`;
    // A symlink would be read or skipped depending on its target type; refuse it so the scan never silently differs.
    if (entry.isSymbolicLink()) throw new Error(`symlink in the scanned tree: ${rel}. ${POINTER_SCAN}`);
    if (entry.isDirectory()) {
      if (top && EXCLUDED_TOP_DIRS.has(entry.name)) continue;
      out.push(...walkSources(rel, false));
    } else if (SOURCE_EXT.test(entry.name) && !TEST_FILE.test(rel)) out.push(rel);
  }
  return out;
}

let cache: Scanned[] | undefined;
function scan(): Scanned[] {
  if (cache) return cache;
  try {
    cache = walkSources("", true)
      .sort()
      .map((rel) => ({ rel, text: readFileSync(path.join(APP_ROOT, rel), "utf8") }));
  } catch (e) {
    throw new Error(`scan failed: ${(e as Error).message}. ${POINTER_SCAN}`);
  }
  return cache;
}

const names = (files: Scanned[]): string[] => files.map((f) => f.rel).sort();
const filenameArmOf = (files: Scanned[]): Scanned[] => files.filter((f) => AGENT_FILENAME.test(f.rel));
const markerArmOf = (files: Scanned[]): Scanned[] => files.filter((f) => AGENT_MARKER.test(f.text));
const offendersOf = (files: Scanned[]): string[] =>
  names([...new Map([...filenameArmOf(files), ...markerArmOf(files)].map((f) => [f.rel, f])).values()].filter((f) => EGRESS_AUDIT.test(f.text)));
const drift = (found: string[], expected: Record<string, string>) => {
  const want = Object.keys(expected).sort();
  return { added: found.filter((f) => !want.includes(f)), removed: want.filter((f) => !found.includes(f)) };
};
const CLEAN = { added: [], removed: [] };

// Every arm records itself; the last test fails if any arm was skipped, emptied or deleted.
const ARM_IDS = ["a", "b", "c", "d", "f", "g", "e2", "e3", "e5-rpc", "e5-egress", "e5-import", "e5-agent", "e6"];
const ran = new Set<string>();

describe("egress audit: no agent-reachable surface (ADR-288 amendment 2026-11-04, #11258)", () => {
  it("(a) the two function names occur in exactly the expected non-test source files", () => {
    expect(drift(names(scan().filter((f) => RPC_NAME.test(f.text))), EXPECTED_NAME_FILES), POINTER).toEqual(CLEAN);
    ran.add("a");
  });

  it("(b) only the two Scope Grants pages import the loader module", () => {
    expect(drift(names(scan().filter((f) => LOADER_IMPORT.test(f.text))), EXPECTED_LOADER_IMPORTERS), POINTER).toEqual(CLEAN);
    ran.add("b");
  });

  it("(c) no file that builds, registers or classifies agent tools mentions egress audit (function, loader or table)", () => {
    expect(offendersOf(scan()), POINTER).toEqual([]);
    ran.add("c");
  });

  it("(d) no tier-map key and no router base-list tool name mentions egress audit", () => {
    const keys = Object.keys(TOOL_TIER_MAP);
    expect(keys.length).toBeGreaterThan(10);
    expect(CC_REGISTERED_PLATFORM_TOOL_NAMES.length).toBeGreaterThanOrEqual(2);
    const hits = {
      keys: keys.filter((k) => EGRESS_AUDIT.test(k)),
      registered: CC_REGISTERED_PLATFORM_TOOL_NAMES.filter((n) => EGRESS_AUDIT.test(n)),
    };
    expect(hits, POINTER).toEqual({ keys: [], registered: [] });
    ran.add("d");
  });

  it("(f) the rollup table name occurs in exactly the expected non-test source files (no neutral-named reader)", () => {
    expect(drift(names(scan().filter((f) => TABLE_NAME.test(f.text))), EXPECTED_TABLE_FILES), POINTER).toEqual(CLEAN);
    ran.add("f");
  });

  it("(g) no production file imports a test-named module or a module in an excluded directory (those are not scanned)", () => {
    expect(drift(names(scan().filter((f) => TEST_IMPORT.test(f.text))), EXPECTED_EXCLUDED_DIR_IMPORTERS), POINTER_SCAN).toEqual(CLEAN);
    ran.add("g");
  });
});

describe("the pin cannot read green over an empty or shrunken scan (anti-vacuity)", () => {
  it("(e2) the scan covers at least the floor of source files", () => {
    expect(scan().length, "scan shrank below the floor; if files were legitimately removed, lower MIN_SCANNED_FILES").toBeGreaterThanOrEqual(MIN_SCANNED_FILES);
    const perDir: Record<string, number> = {};
    for (const f of scan()) perDir[f.rel.split("/")[0]] = (perDir[f.rel.split("/")[0]] ?? 0) + 1;
    for (const [dir, min] of Object.entries(MIN_PER_TOP_DIR)) {
      expect([dir, (perDir[dir] ?? 0) >= min], `${dir} has ${perDir[dir] ?? 0} scanned files, minimum ${min}`).toEqual([dir, true]);
    }
    ran.add("e2");
  });

  it("(e3) both agent-surface arms contain their named members", () => {
    expect(names(filenameArmOf(scan())).filter((n) => FILENAME_ARM_MEMBERS.includes(n))).toEqual([...FILENAME_ARM_MEMBERS].sort());
    expect(names(markerArmOf(scan())).filter((n) => MARKER_ARM_MEMBERS.includes(n))).toEqual([...MARKER_ARM_MEMBERS].sort());
    ran.add("e3");
  });

  it("(e5-rpc) RPC_NAME matches the function names and nothing else", () => {
    for (const s of ["get_egress_audit_window_summary", "get_egress_audit_summary", `rpc("get_egress_audit_summary", {})`]) {
      expect([s, RPC_NAME.test(s)]).toEqual([s, true]);
    }
    for (const s of ["get_egress_summary", "get_audit_summary"]) {
      expect([s, RPC_NAME.test(s)]).toEqual([s, false]);
    }
    ran.add("e5-rpc");
  });

  it("(e5-egress) EGRESS_AUDIT matches the egress-audit family and not neighbouring egress names", () => {
    for (const s of ["loadEgressAudit(", "egress_audit_rollup", `from("workspace_egress_audit_rollup")`, "egress-audit-read"]) {
      expect([s, EGRESS_AUDIT.test(s)]).toEqual([s, true]);
    }
    for (const s of ["web_egress", "egress gateway", "egress-forwarder", "WEB_EGRESS_PROMPT_ADDENDUM"]) {
      expect([s, EGRESS_AUDIT.test(s)]).toEqual([s, false]);
    }
    expect(TABLE_NAME.test(`from("workspace_egress_audit_rollup")`)).toBe(true);
    expect(TABLE_NAME.test("egress-forwarder")).toBe(false);
    ran.add("e5-egress");
  });

  it("(e5-import) the import matchers match every real specifier spelling and not prose", () => {
    const loader = [
      `import("@/server/egress-audit-read")`,
      `from "../server/egress-audit-read"`,
      `from '@/server/egress-audit-read'`,
      `require("./egress-audit-read")`,
      `from "@/server/egress-audit-read.js"`,
      `from "@/server/egress-audit-read.ts"`,
      `from "@/server/egress-audit-read/index"`,
      "import(`@/server/egress-audit-read`)",
      `import "@/server/egress-audit-read"`,
      `import(/* webpackChunkName: "x" */ "@/server/egress-audit-read")`,
      `import(/* webpackIgnore: true */ /* second */ "@/server/egress-audit-read")`,
      `require.resolve("./egress-audit-read")`,
      `new URL("./egress-audit-read.ts", import.meta.url)`,
    ];
    for (const s of loader) expect([s, LOADER_IMPORT.test(s)]).toEqual([s, true]);
    for (const s of [`from "@/server/observability"`, `feature: "egress-audit-read"`, `// see egress-audit-read.ts`, "imported from `egress-audit-read.ts`"]) {
      expect([s, LOADER_IMPORT.test(s)]).toEqual([s, false]);
    }
    for (const s of [
      `from "./x.test"`,
      `from "../x.spec.ts"`,
      `import("./__tests__/y")`,
      `require("./z.test.mjs")`,
      `import(/* webpackIgnore: true */ "./x.test")`,
      `from "@/test/helpers/x"`,
      `from "../e2e/fixtures"`,
      `from "../../docs/x"`,
      `import("@/supabase/functions/x")`,
    ]) {
      expect([s, TEST_IMPORT.test(s)]).toEqual([s, true]);
    }
    for (const s of [`from "./latest"`, "// the constants from `test/x.test.ts`", `from "./contest"`, `from "node:test"`, `from "@/lib/docsify"`, `from "@/lib/supabase/server"`, `from "../lib/test-utils"`]) {
      expect([s, TEST_IMPORT.test(s)]).toEqual([s, false]);
    }
    // A long run of whitespace after `import` must stay linear (no catastrophic backtracking).
    const long = `import${" ".repeat(100_000)}x`;
    const t0 = Date.now();
    expect([LOADER_IMPORT.test(long), TEST_IMPORT.test(long)]).toEqual([false, false]);
    expect(Date.now() - t0).toBeLessThan(1000);
    ran.add("e5-import");
  });

  it("(e5-agent) AGENT_FILENAME and AGENT_MARKER match what they must and nothing else", () => {
    for (const s of ["server/zz-probe-tools.ts", "server/inbox-tool.ts", "server/sub/x-tools.ts", "server/tools.ts", "lib/zz/tools.js", "hooks/x-tools.mts", "server/egressTools.ts", "lib/tools/x.ts"]) {
      expect([s, AGENT_FILENAME.test(s)]).toEqual([s, true]);
    }
    for (const s of ["server/tool-tiers.ts", "server/stools.ts", "server/toolbox.ts", "server/tools-census.sh"]) {
      expect([s, AGENT_FILENAME.test(s)]).toEqual([s, false]);
    }
    for (const s of [
      "createSdkMcpServer({",
      "mcp__soleur_platform__narrate",
      "TOOL_TIER_MAP",
      "CC_MCP_ALLOWLIST",
      "mcpServers: {",
      "canUseTool",
      `import { tool } from "@anthropic-ai/claude-agent-sdk"`,
    ]) {
      expect([s, AGENT_MARKER.test(s)]).toEqual([s, true]);
    }
    ran.add("e5-agent");
  });

  it("(e6) the composed predicate trips on a filename-only, a marker-only and an SDK-only agent file, and on nothing neutral", () => {
    const row = (rel: string, text: string): Scanned => ({ rel, text });
    expect(offendersOf([row("lib/zz-tools.ts", "loadEgressAudit()")])).toEqual(["lib/zz-tools.ts"]);
    expect(offendersOf([row("hooks/zz.ts", "createSdkMcpServer(); egress_audit_rollup")])).toEqual(["hooks/zz.ts"]);
    expect(offendersOf([row("lib/zz.ts", `import { tool } from "@anthropic-ai/claude-agent-sdk"; loadEgressAudit()`)])).toEqual(["lib/zz.ts"]);
    expect(offendersOf([row("lib/neutral.ts", "egress_audit_rollup"), row("server/zz-tools.ts", "web_egress")])).toEqual([]);
    ran.add("e6");
  });

  it("every arm above executed (a skipped, emptied or deleted arm fails here)", () => {
    expect([...ran].sort()).toEqual([...ARM_IDS].sort());
  });
});
