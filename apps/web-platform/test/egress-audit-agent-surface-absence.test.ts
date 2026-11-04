import { describe, it, expect } from "vitest";
import { existsSync, readdirSync, readFileSync } from "node:fs";
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
const SCAN_ROOTS = ["server", "lib", "app", "components"];
const SOURCE_EXT = /\.(ts|tsx|mjs)$/;
const TEST_FILE = /\.test\.(ts|tsx|mjs)$|(^|\/)__tests__\//;

// The two member-read functions (migrations 177 and 183), the egress-audit family in any spelling, and the loader module.
const RPC_NAME = /get_egress_audit_(window_)?summary/;
const EGRESS_AUDIT = /egress[-_]?audit/i; // also camelCase (loadEgressAudit) and the rollup table name
const LOADER_IMPORT = /(?:from|import\s*\(|require\s*\()\s*["'][^"']*egress-audit-read["']/;

// An agent-surface file is a platform tool builder (filename arm) or any file that builds, registers or classifies tools
// (marker arm). Both arms are measured separately so that dropping one is visible.
const AGENT_FILENAME = /(^|\/)[^/]*-tools?\.ts$/;
const AGENT_MARKER = /createSdkMcpServer|mcp__soleur_platform__|TOOL_TIER_MAP|CC_MCP_ALLOWLIST|mcpServers:|canUseTool/;

// Today's expected sets. Editing either is a deliberate act that belongs in the same PR as the ADR record and its review.
const EXPECTED_NAME_FILES = [
  "lib/egress-audit/summary.ts",
  "server/dsar-export-allowlist.ts",
  "server/egress-audit-read.ts",
];
const EXPECTED_LOADER_IMPORTERS = [
  "app/(dashboard)/dashboard/settings/scope-grants/egress-audit/page.tsx",
  "app/(dashboard)/dashboard/settings/scope-grants/page.tsx",
];
// Hard-coded and independent of SCAN_ROOTS: a root dropped from the scan, or a layout change that empties it, fails arm (e).
const ROOT_ANCHORS: Record<string, string> = {
  server: "server/egress-audit-read.ts",
  lib: "lib/egress-audit/summary.ts",
  app: "app/(dashboard)/dashboard/settings/scope-grants/page.tsx",
  components: "components/settings/egress-audit-view.tsx",
};
// 90% of the 975 files measured on 2026-11-04 (a floor with margin, not an exact count).
const MIN_SCANNED_FILES = 877;

const POINTER =
  "ADR-288, amendment 2026-11-04 (#11258): building an agent-reachable egress-audit surface needs legal and security review " +
  "and an edit of this test's expected sets in the same PR; see the amendment's constraints.";

type Scanned = { rel: string; text: string };

function walkSources(dirRel: string): string[] {
  const abs = path.join(APP_ROOT, dirRel);
  if (!existsSync(abs)) return [];
  const out: string[] = [];
  for (const entry of readdirSync(abs, { withFileTypes: true })) {
    if (entry.name === "node_modules" || entry.name === ".next") continue;
    const rel = `${dirRel}/${entry.name}`;
    if (entry.isDirectory()) out.push(...walkSources(rel));
    else if (SOURCE_EXT.test(entry.name) && !TEST_FILE.test(rel)) out.push(rel);
  }
  return out;
}

function loadScan(roots: string[]): Scanned[] {
  return roots
    .flatMap((r) => walkSources(r))
    .sort()
    .map((rel) => ({ rel, text: readFileSync(path.join(APP_ROOT, rel), "utf8") }));
}

const scanned = loadScan(SCAN_ROOTS);
const filenameArm = scanned.filter((f) => f.rel.startsWith("server/") && AGENT_FILENAME.test(f.rel));
const markerArm = scanned.filter((f) => AGENT_MARKER.test(f.text));
const agentSurface = [...new Map([...filenameArm, ...markerArm].map((f) => [f.rel, f])).values()];

const names = (files: Scanned[]): string[] => files.map((f) => f.rel).sort();

describe("egress audit: no agent-reachable surface (ADR-288 amendment 2026-11-04, #11258)", () => {
  it("(a) the two function names occur in exactly the expected non-test source files", () => {
    const found = names(scanned.filter((f) => RPC_NAME.test(f.text)));
    expect(found, POINTER).toEqual([...EXPECTED_NAME_FILES].sort());
  });

  it("(b) only the two Scope Grants pages import the loader module", () => {
    const found = names(scanned.filter((f) => LOADER_IMPORT.test(f.text)));
    expect(found, POINTER).toEqual([...EXPECTED_LOADER_IMPORTERS].sort());
  });

  it("(c) no file that builds, registers or classifies agent tools mentions egress audit (function, loader or table)", () => {
    const offenders = names(agentSurface.filter((f) => EGRESS_AUDIT.test(f.text)));
    expect(offenders, POINTER).toEqual([]);
  });

  it("(d) no tier-map key and no router-registered platform tool name mentions egress audit", () => {
    const keys = Object.keys(TOOL_TIER_MAP).filter((k) => EGRESS_AUDIT.test(k));
    const registered = CC_REGISTERED_PLATFORM_TOOL_NAMES.filter((n) => EGRESS_AUDIT.test(n));
    expect({ keys, registered }, POINTER).toEqual({ keys: [], registered: [] });
  });
});

describe("the pin cannot read green over an empty or shrunken scan (anti-vacuity)", () => {
  it("(e1) every root anchor exists and is in the scanned set, whatever SCAN_ROOTS says", () => {
    const set = new Set(scanned.map((f) => f.rel));
    for (const [root, anchor] of Object.entries(ROOT_ANCHORS)) {
      expect([root, existsSync(path.join(APP_ROOT, anchor)), set.has(anchor)]).toEqual([root, true, true]);
    }
    expect([...SCAN_ROOTS].sort()).toEqual(Object.keys(ROOT_ANCHORS).sort());
  });

  it("(e2) the scan covers at least the floor of source files", () => {
    expect(scanned.length).toBeGreaterThanOrEqual(MIN_SCANNED_FILES);
  });

  it("(e3) the agent-surface population is non-empty on both of its arms", () => {
    expect(filenameArm.length).toBeGreaterThan(0);
    expect(markerArm.length).toBeGreaterThan(0);
  });

  it("(e4) every expected member exists on disk", () => {
    for (const rel of [...EXPECTED_NAME_FILES, ...EXPECTED_LOADER_IMPORTERS]) {
      expect([rel, existsSync(path.join(APP_ROOT, rel))]).toEqual([rel, true]);
    }
  });

  it("(e5) the matchers match what they must and nothing else (positive and negative controls)", () => {
    for (const s of ["get_egress_audit_window_summary", "get_egress_audit_summary", `rpc("get_egress_audit_summary", {})`]) {
      expect([s, RPC_NAME.test(s)]).toEqual([s, true]);
    }
    for (const s of ["get_egress_summary", "get_audit_summary"]) {
      expect([s, RPC_NAME.test(s)]).toEqual([s, false]);
    }
    for (const s of ["loadEgressAudit(", "egress_audit_rollup", `from("workspace_egress_audit_rollup")`, "egress-audit-read"]) {
      expect([s, EGRESS_AUDIT.test(s)]).toEqual([s, true]);
    }
    for (const s of ["web_egress", "egress gateway", "egress-forwarder", "WEB_EGRESS_PROMPT_ADDENDUM"]) {
      expect([s, EGRESS_AUDIT.test(s)]).toEqual([s, false]);
    }
    for (const s of [`import("@/server/egress-audit-read")`, `from "../server/egress-audit-read"`, `from '@/server/egress-audit-read'`, `require("./egress-audit-read")`]) {
      expect([s, LOADER_IMPORT.test(s)]).toEqual([s, true]);
    }
    for (const s of [`from "@/server/observability"`, `feature: "egress-audit-read"`, `// see egress-audit-read.ts`]) {
      expect([s, LOADER_IMPORT.test(s)]).toEqual([s, false]);
    }
    for (const s of ["server/zz-probe-tools.ts", "server/inbox-tool.ts", "server/sub/x-tools.ts"]) {
      expect([s, AGENT_FILENAME.test(s)]).toEqual([s, true]);
    }
    for (const s of ["server/tools.ts", "server/tool-tiers.ts", "server/stools.ts"]) {
      expect([s, AGENT_FILENAME.test(s)]).toEqual([s, false]);
    }
    for (const s of ["createSdkMcpServer({", "mcp__soleur_platform__narrate", "TOOL_TIER_MAP", "CC_MCP_ALLOWLIST", "mcpServers: {", "canUseTool"]) {
      expect([s, AGENT_MARKER.test(s)]).toEqual([s, true]);
    }
  });
});
