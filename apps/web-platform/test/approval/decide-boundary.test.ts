/**
 * #4672 sentinel: the agent shares this process, so the only thing keeping it from deciding its own approval request is
 * code discipline: no MCP tool handler and nothing on the gate side may call the decide path.
 *
 * The plan asked for "no module reachable from the tool builders or the canUseTool deps imports decide.ts". As stated
 * that is unsatisfiable: `server/ws-handler.ts` (which MUST import decide.ts, it is the Owner's socket) is reachable
 * from `notifications.ts` -> `session-registry.ts`, so every module that sends a notification reaches it. The sentinel
 * is therefore a set of conjuncts that together pin the same property:
 *   1. the `decide_approval` RPC name appears, in code (comments stripped, any quote style), in exactly one module;
 *   2. decide.ts has exactly the allowlisted importers (the WebSocket handler and the HTTP decide route);
 *   3. walking the real VALUE import graph (static, dynamic, `export ... from`, `require`; type-only imports are erased
 *      at compile time and are not edges) from the gate side, every module under server/approval/ except decide.ts, and
 *      every MCP tool builder (found by glob, with a floor so a rename cannot empty the walk), with the WebSocket handler
 *      treated as the process hub (not traversed), never reaches decide.ts;
 *   4. the hub is not a back door: nothing outside tests imports `handleMessage` (the entry point that mints a tenant
 *      client and routes `approval_decide`), no gate-side or MCP-builder module value-imports ws-handler at all, and the
 *      only hub exports any reachable module may import are the two senders listed below.
 * What this does NOT prove: a module that reaches the hub's allowed exports can still call code in the same process. The
 * real fix is moving the decide path out of the agent process (ADR-307 follow-up); this is the tripwire until then.
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { describe, expect, test } from "vitest";

const ROOT = resolve(__dirname, "../..");
const DECIDE = join(ROOT, "server/approval/decide.ts");
const HUB = join(ROOT, "server/ws-handler.ts");

// ---------------------------------------------------------------------------
// Source scanning helpers (exported shapes are exercised by the self-tests below).
// ---------------------------------------------------------------------------

/** Blank out comments, keeping string/template/regex-free-enough code intact. Newlines are preserved. */
export function stripComments(src: string): string {
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === "/" && d === "/") {
      while (i < n && src[i] !== "\n") i++;
    } else if (c === "/" && d === "*") {
      i += 2;
      while (i < n && !(src[i] === "*" && src[i + 1] === "/")) {
        if (src[i] === "\n") out += "\n";
        i++;
      }
      i += 2;
    } else if (c === '"' || c === "'" || c === "`") {
      const quote = c;
      out += c;
      i++;
      while (i < n && src[i] !== quote) {
        if (src[i] === "\\") {
          out += src[i];
          i++;
        }
        if (i < n) out += src[i];
        i++;
      }
      if (i < n) out += quote;
      i++;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

export interface ImportEdge {
  spec: string;
  /** Names imported as VALUES (empty for `import "x"`, dynamic import and `export *`). `*` = namespace/dynamic/all. */
  names: string[];
}

const FROM_RE = /\b(import|export)\s+(type\s+)?([^;'"`]*?)\s*from\s*(["'])([^"'`]+)\4/g;
const SIDE_EFFECT_RE = /(?:^|[;\s])import\s*(["'])([^"'`]+)\1/g;
const DYNAMIC_RE = /\b(?:import|require)\(\s*(["'`])([^"'`]+)\1\s*\)/g;

function valueNames(clause: string): string[] {
  const names: string[] = [];
  const braces = clause.match(/\{([^}]*)\}/);
  const rest = clause.replace(/\{[^}]*\}/, "").replace(/,/g, " ").trim();
  if (rest) names.push(rest.startsWith("*") ? "*" : rest.split(/\s+/)[0]);
  if (braces) {
    for (const part of braces[1].split(",")) {
      const t = part.trim();
      if (!t || /^type\s+/.test(t)) continue; // `import { type A }` is erased
      names.push(t.split(/\s+as\s+/)[0].trim());
    }
  }
  return names;
}

/** The VALUE import/re-export edges of a module (type-only imports are not edges). */
export function valueEdges(rawSource: string): ImportEdge[] {
  const src = stripComments(rawSource);
  const edges: ImportEdge[] = [];
  for (const m of src.matchAll(FROM_RE)) {
    const [, kind, typeOnly, clause, , spec] = m;
    if (typeOnly) continue; // import type ... / export type ...
    const trimmed = clause.trim();
    if (kind === "import" && trimmed === "") continue;
    if (kind === "export" && !/^(\*|\{)/.test(trimmed)) continue;
    const names = trimmed.startsWith("*") && !trimmed.includes(" as ") ? ["*"] : valueNames(trimmed);
    // `import { type A, type B } from` has no value specifier: erased entirely.
    if (names.length === 0 && /\{/.test(trimmed)) continue;
    edges.push({ spec, names: names.length ? names : ["*"] });
  }
  for (const m of src.matchAll(SIDE_EFFECT_RE)) edges.push({ spec: m[2], names: [] });
  for (const m of src.matchAll(DYNAMIC_RE)) edges.push({ spec: m[2], names: ["*"] });
  return edges;
}

function resolveImport(from: string, spec: string): string | null {
  let base: string;
  if (spec.startsWith("@/")) base = join(ROOT, spec.slice(2));
  else if (spec.startsWith(".")) base = resolve(dirname(from), spec);
  else return null; // package
  for (const cand of [base, `${base}.ts`, `${base}.tsx`, join(base, "index.ts")]) {
    if (existsSync(cand) && /\.(ts|tsx)$/.test(cand)) return cand;
  }
  return null;
}

function reachable(roots: string[]): Map<string, string> {
  const seen = new Map<string, string>(); // file -> importer
  const queue = roots.map((r) => ({ file: r, via: "(root)" }));
  while (queue.length) {
    const { file, via } = queue.pop()!;
    if (seen.has(file)) continue;
    seen.set(file, via);
    if (file === HUB) continue; // the process hub: it legitimately imports decide.ts (see the header)
    for (const e of valueEdges(readFileSync(file, "utf8"))) {
      const target = resolveImport(file, e.spec);
      if (target && !seen.has(target)) queue.push({ file: target, via: file });
    }
  }
  return seen;
}

function walkSources(dirs: string[], include: (p: string) => boolean = () => true): string[] {
  const out: string[] = [];
  const walk = (dir: string) => {
    if (!existsSync(dir)) return;
    for (const ent of readdirSync(dir, { withFileTypes: true })) {
      if (ent.name === "node_modules" || ent.name === ".next" || ent.name.startsWith(".")) continue;
      const p = join(dir, ent.name);
      if (ent.isDirectory()) walk(p);
      else if (/\.(ts|tsx)$/.test(ent.name) && include(p)) out.push(p);
    }
  };
  for (const d of dirs) walk(join(ROOT, d));
  return out;
}

const rel = (p: string) => relative(ROOT, p);

// ---------------------------------------------------------------------------
// The entry set: found by glob, never hand-listed (a rename or a new builder cannot silently leave the walk).
// ---------------------------------------------------------------------------

const TOOL_BUILDERS = walkSources(["server"], (p) => /-tools\.ts$/.test(p) || /\/mcp-[^/]*\.ts$/.test(p));
/** Floor = the number of builders on the day this sentinel was rewritten. A rename that drops below it fails here. */
const TOOL_BUILDER_FLOOR = 16;

const APPROVAL_MODULES = walkSources(["server/approval"], (p) => p !== DECIDE);
const APPROVAL_MODULES_FLOOR = 14;

const GATE_SIDE = ["server/permission-callback.ts", "server/approval/gate-flow.ts", "server/approval/gate-types.ts", "server/approval/service.ts"].map((p) =>
  join(ROOT, p),
);

/** Hub exports a module reachable from the gate side or a builder may import: the senders, nothing that routes a message. */
const ALLOWED_HUB_EXPORTS = new Set(["sendToClient", "forceDisconnectForTierChange"]);

// ---------------------------------------------------------------------------

describe("the decide path is unreachable from anything the agent can reach", () => {
  test("the entry set is found by glob and the floors hold (a rename cannot empty the walk)", () => {
    expect(TOOL_BUILDERS.length).toBeGreaterThanOrEqual(TOOL_BUILDER_FLOOR);
    expect(APPROVAL_MODULES.length).toBeGreaterThanOrEqual(APPROVAL_MODULES_FLOOR);
    const names = TOOL_BUILDERS.map(rel);
    for (const must of [
      "server/github-tools.ts",
      "server/kb-share-tools.ts",
      "server/workspace-settings-tools.ts",
      "server/email-triage-tools.ts",
      "server/crm/crm-tools.ts",
      "server/c4-concierge-tools.ts",
      "server/conversations-tools.ts",
      "server/auth-status-tools.ts",
      "server/github-read-tools.ts",
      "server/workstream/workstream-tools.ts",
    ]) {
      expect(names, must).toContain(must);
    }
    for (const f of GATE_SIDE) expect(existsSync(f), f).toBe(true);
  });

  test("the walker is not vacuous: it reaches the known transitive imports and finds decide.ts from its own importers", () => {
    const g = reachable(GATE_SIDE);
    expect(g.size).toBeGreaterThan(5);
    expect(g.has(join(ROOT, "server/approval/canonical.ts"))).toBe(true);
    const fromDecide = reachable([DECIDE]);
    expect(fromDecide.has(join(ROOT, "server/approval/service.ts"))).toBe(true);
  });

  test("canUseTool, the gate flow and the service wrappers cannot reach decide.ts", () => {
    const g = reachable(GATE_SIDE);
    expect(g.has(DECIDE), `decide.ts reached via ${g.get(DECIDE)}`).toBe(false);
  });

  test.each(APPROVAL_MODULES.map(rel))("approval module %s cannot reach decide.ts", (file) => {
    const g = reachable([join(ROOT, file)]);
    expect(g.has(DECIDE), `decide.ts reached via ${g.get(DECIDE)}`).toBe(false);
  });

  test.each(TOOL_BUILDERS.map(rel))("MCP tool builder %s cannot reach decide.ts", (file) => {
    const g = reachable([join(ROOT, file)]);
    expect(g.has(DECIDE), `decide.ts reached via ${g.get(DECIDE)}`).toBe(false);
  });

  test("the decide_approval RPC name appears, in code and in any quote style, in exactly one source module", () => {
    const hits = walkSources(["server", "app", "lib", "components"], (p) => /decide_approval/.test(stripComments(readFileSync(p, "utf8")))).map(rel);
    expect(hits).toEqual(["server/approval/decide.ts"]);
  });

  test("decide.ts has exactly the allowlisted importers (the WebSocket handler and the HTTP decide route)", () => {
    const importers = walkSources(["server", "app", "lib", "components"], (p) => {
      if (p === DECIDE) return false;
      return valueEdges(readFileSync(p, "utf8")).some((e) => resolveImport(p, e.spec) === DECIDE);
    }).map(rel);
    expect(importers.sort()).toEqual(["app/api/approvals/[id]/decide/route.ts", "server/ws-handler.ts"]);
  });
});

describe("the hub (ws-handler) is not a back door", () => {
  const SOURCES = walkSources(["server", "app", "lib", "components"]).concat(existsSync(join(ROOT, "server.ts")) ? [join(ROOT, "server.ts")] : []);
  const hubImports = (file: string): ImportEdge[] =>
    valueEdges(readFileSync(file, "utf8")).filter((e) => {
      const t = resolveImport(file, e.spec);
      return t === HUB;
    });

  test("nothing outside tests imports handleMessage (the entry that mints a tenant client and routes approval_decide)", () => {
    const offenders = SOURCES.filter((f) => f !== HUB && hubImports(f).some((e) => e.names.includes("handleMessage") || e.names.includes("*"))).map(rel);
    expect(offenders).toEqual([]);
  });

  test("no gate-side, approval or MCP-builder module value-imports ws-handler at all", () => {
    const offenders = [...GATE_SIDE, ...APPROVAL_MODULES, ...TOOL_BUILDERS].filter((f) => hubImports(f).length > 0).map(rel);
    expect(offenders).toEqual([]);
  });

  test("every module reachable from them imports only the allowlisted hub exports", () => {
    const seen = reachable([...GATE_SIDE, ...APPROVAL_MODULES, ...TOOL_BUILDERS]);
    const bad: string[] = [];
    for (const f of seen.keys()) {
      if (f === HUB) continue;
      for (const e of hubImports(f)) {
        for (const name of e.names) if (!ALLOWED_HUB_EXPORTS.has(name)) bad.push(`${rel(f)} imports ${name}`);
      }
    }
    expect(bad).toEqual([]);
  });
});

/** The text of each `createCanUseTool(` call's argument (balanced parentheses). */
export function callSites(src: string): string[] {
  const code = stripComments(src);
  const out: string[] = [];
  for (const m of code.matchAll(/createCanUseTool\(/g)) {
    const start = m.index! + m[0].length;
    let depth = 1;
    let i = start;
    while (i < code.length && depth > 0) {
      if (code[i] === "(") depth++;
      else if (code[i] === ")") depth--;
      i++;
    }
    const before = code.slice(Math.max(0, m.index! - 20), m.index!);
    if (/function\s*$/.test(before)) continue; // the definition
    out.push(code.slice(start, i - 1));
  }
  return out;
}

describe("runner census: every createCanUseTool call site wires the approval dependency or is on the explicit allowlist", () => {
  // The cc runner (cc-dispatcher.ts) is deliberately NOT wired: it registers no slice-1 tool, and readCcMcpAllowlist
  // refuses to promote one (test/approval/tools-census.test.ts). A new call site fails here until it is wired or listed.
  const ALLOWLIST: Record<string, string> = {
    "server/cc-dispatcher.ts": "cc router: no approval-required tool is registered and CC_MCP_ALLOWLIST refuses them",
  };

  test("the call-site parser finds the real call sites (not vacuous)", () => {
    const all = walkSources(["server", "app", "lib"]).flatMap((f) => callSites(readFileSync(f, "utf8")).map(() => rel(f)));
    expect(all.sort()).toEqual(["server/agent-runner.ts", "server/cc-dispatcher.ts"]);
  });

  test("each call site passes `approval` or is allowlisted with a reason", () => {
    const unwired: string[] = [];
    for (const f of walkSources(["server", "app", "lib"])) {
      for (const site of callSites(readFileSync(f, "utf8"))) {
        if (/\bapproval\s*:/.test(site)) continue;
        if (!ALLOWLIST[rel(f)]) unwired.push(rel(f));
      }
    }
    expect(unwired).toEqual([]);
  });

  test("an allowlisted file really does not pass `approval` (a stale allowlist entry is a lie)", () => {
    for (const [file] of Object.entries(ALLOWLIST)) {
      const sites = callSites(readFileSync(join(ROOT, file), "utf8"));
      expect(sites.length, file).toBeGreaterThan(0);
      for (const s of sites) expect(/\bapproval\s*:/.test(s), `${file} now wires approval: remove it from the allowlist`).toBe(false);
    }
  });
});

describe("self-tests: the scanners catch what they claim to (mutation list)", () => {
  test("stripComments removes line and block comments but keeps strings, including URLs with //", () => {
    const out = stripComments(`// import x from "./decide"\n/* decide_approval */ const u = "https://a/b"; const q = 'decide_approval';`);
    expect(out).not.toContain("./decide");
    expect(out).toContain('"https://a/b"');
    expect(out).toContain("'decide_approval'");
    expect(out.split("\n")).toHaveLength(2);
  });

  test("a decide_approval name in any quote style is found in code, and in a comment is not", () => {
    for (const q of ['"', "'", "`"]) expect(/decide_approval/.test(stripComments(`rpc(${q}decide_approval${q})`))).toBe(true);
    expect(/decide_approval/.test(stripComments(`// rpc("decide_approval")\n/* 'decide_approval' */`))).toBe(false);
  });

  test("valueEdges: type-only imports and re-exports are erased; value, mixed, default, namespace, side-effect and dynamic are kept", () => {
    const src = `
      import type { A } from "./a";
      import { type B, type C } from "./b";
      import { type D, e } from "./c";
      import F from "./d";
      import * as G from "./e";
      import "./f";
      export type { H } from "./g";
      export { I } from "./h";
      export * from "./i";
      const j = await import("./j");
      const k = require("./k");
      // import { Z } from "./commented";
    `;
    const specs = valueEdges(src).map((e) => e.spec).sort();
    expect(specs).toEqual(["./c", "./d", "./e", "./f", "./h", "./i", "./j", "./k"]);
    expect(valueEdges(src).find((e) => e.spec === "./c")!.names).toEqual(["e"]);
  });

  test("a value import of handleMessage is seen even with other names, aliases and multi-line specifiers", () => {
    const e = valueEdges(`import {\n  sendToClient,\n  handleMessage as hm,\n} from "@/server/ws-handler";`);
    expect(e[0].names).toEqual(["sendToClient", "handleMessage"]);
    expect(valueEdges(`import type { handleMessage } from "@/server/ws-handler";`)).toEqual([]);
  });

  test("the call-site parser sees calls with and without `approval:` and ignores the definition", () => {
    const code = `export function createCanUseTool(ctx) {}\nconst a = createCanUseTool({ deps: { approval: x } });\nconst b = createCanUseTool({ deps: { y: f(1) } });`;
    const sites = callSites(code);
    expect(sites).toHaveLength(2);
    expect(/\bapproval\s*:/.test(sites[0])).toBe(true);
    expect(/\bapproval\s*:/.test(sites[1])).toBe(false);
  });
});
