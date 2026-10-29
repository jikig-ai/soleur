/**
 * #4672 sentinel: the agent shares this process, so the only thing keeping it from deciding its own approval request is
 * code discipline: no MCP tool handler and nothing on the gate side may call the decide path.
 *
 * The plan asked for "no module reachable from the tool builders or the canUseTool deps imports decide.ts". As stated
 * that is unsatisfiable: `server/ws-handler.ts` (which MUST import decide.ts, it is the Owner's socket) is reachable
 * from `notifications.ts` -> `session-registry.ts`, so every module that sends a notification reaches it. The sentinel is
 * therefore three conjuncts that together pin the same property:
 *   1. the `decide_approval` RPC name appears in exactly one source module (approval/decide.ts);
 *   2. decide.ts has exactly the allowlisted importers (today: the WebSocket handler);
 *   3. walking the real import graph (static, dynamic, `export ... from`) from the gate side and every MCP tool builder,
 *      with the WebSocket handler treated as the process hub (not traversed), never reaches decide.ts.
 * Adding a decide importer, a second `decide_approval` caller, or an import of decide.ts from a tool builder fails here.
 */
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { describe, expect, test } from "vitest";

const ROOT = resolve(__dirname, "../..");
const DECIDE = join(ROOT, "server/approval/decide.ts");

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

const IMPORT_RE = /(?:import|export)\s[^;"']*?from\s*["']([^"']+)["']|import\s*["']([^"']+)["']|import\(\s*["']([^"']+)["']\s*\)|require\(\s*["']([^"']+)["']\s*\)/g;

const HUB = join(ROOT, "server/ws-handler.ts");

function reachable(roots: string[]): Map<string, string> {
  const seen = new Map<string, string>(); // file -> importer
  const queue = roots.map((r) => ({ file: r, via: "(root)" }));
  while (queue.length) {
    const { file, via } = queue.pop()!;
    if (seen.has(file)) continue;
    seen.set(file, via);
    if (file === HUB) continue; // the process hub: it legitimately imports decide.ts (see the header)
    const src = readFileSync(file, "utf8");
    for (const m of src.matchAll(IMPORT_RE)) {
      const spec = m[1] ?? m[2] ?? m[3] ?? m[4];
      const target = spec ? resolveImport(file, spec) : null;
      if (target && !seen.has(target)) queue.push({ file: target, via: file });
    }
  }
  return seen;
}

const TOOL_BUILDERS = [
  "email-triage-tools",
  "github-tools",
  "kb-share-tools",
  "workspace-settings-tools",
  "account-tools",
  "ci-tools",
  "inbox-tools",
  "routines-tools",
  "service-tools",
  "plausible-tools",
].map((n) => join(ROOT, `server/${n}.ts`));

const GATE_SIDE = ["server/permission-callback.ts", "server/approval/gate-flow.ts", "server/approval/gate-types.ts", "server/approval/service.ts"].map((p) =>
  join(ROOT, p),
);

describe("the decide path is unreachable from anything the agent can reach", () => {
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

  test("the gate dependency factory cannot reach decide.ts", () => {
    const factory = join(ROOT, "server/approval/gate.ts");
    expect(existsSync(factory)).toBe(true);
    const g = reachable([factory]);
    expect(g.has(DECIDE), `decide.ts reached via ${g.get(DECIDE)}`).toBe(false);
  });

  test.each(TOOL_BUILDERS.filter(existsSync))("MCP tool builder %s cannot reach decide.ts", (builder) => {
    const g = reachable([builder]);
    expect(g.has(DECIDE), `decide.ts reached via ${g.get(DECIDE)}`).toBe(false);
  });

  test("the decide_approval RPC name appears in exactly one source module", () => {
    const hits: string[] = [];
    const walk = (dir: string) => {
      for (const ent of readdirSync(dir, { withFileTypes: true })) {
        if (ent.name === "node_modules" || ent.name === ".next" || ent.name.startsWith(".")) continue;
        const p = join(dir, ent.name);
        if (ent.isDirectory()) walk(p);
        else if (/\.(ts|tsx)$/.test(ent.name) && readFileSync(p, "utf8").includes('"decide_approval"')) hits.push(p.replace(`${ROOT}/`, ""));
      }
    };
    for (const d of ["server", "app", "lib", "components"]) walk(join(ROOT, d));
    expect(hits).toEqual(["server/approval/decide.ts"]);
  });

  test("decide.ts has exactly the allowlisted importers (the WebSocket handler and the HTTP decide route)", () => {
    const importers: string[] = [];
    const walk = (dir: string) => {
      for (const ent of readdirSync(dir, { withFileTypes: true })) {
        if (ent.name === "node_modules" || ent.name === ".next" || ent.name.startsWith(".")) continue;
        const p = join(dir, ent.name);
        if (ent.isDirectory()) walk(p);
        else if (/\.(ts|tsx)$/.test(ent.name) && p !== DECIDE && /approval\/decide["']/.test(readFileSync(p, "utf8"))) {
          importers.push(p.replace(`${ROOT}/`, ""));
        }
      }
    };
    for (const d of ["server", "app", "lib", "components"]) walk(join(ROOT, d));
    expect(importers.sort()).toEqual(["app/api/approvals/[id]/decide/route.ts", "server/ws-handler.ts"]);
  });
});
