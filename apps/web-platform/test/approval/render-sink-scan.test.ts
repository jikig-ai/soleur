/**
 * #9601: the sentinel behind "an approval_request frame carries action text only for an Owner or the row's requester".
 *
 * A redaction rule with no pin on every caller of `renderApprovalView` rots the day someone adds the next caller. This
 * suite scans every non-test source under server/, app/, lib/ and components/, censuses the bare identifier
 * `renderApprovalView`, the module edges to `server/approval/render` and to `server/approval/requester-label` (resolved to
 * a file path: every in-tree importer uses a relative or aliased specifier, so a substring match would find none), and pins
 * each against an exact allow-list with counts. Anything the classifier cannot place is the red `unclassified` bucket.
 *
 * The allow-lists below are literals: changing them is a reviewed edit in the same diff as the source they name.
 * Named residual: a computed-name access is invisible to a lexical scan.
 */
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { censusSource, codeOffsets, tokenize, type CensusHit } from "./source-scan";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SCAN_DIRS = ["server", "app", "lib", "components"];
const RENDER = "server/approval/render";
const LABEL = "server/approval/requester-label";
const IDENT = "renderApprovalView";

function walk(dir: string, out: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "node_modules" || e.name === ".next" || e.name === "__tests__") continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (/\.(ts|tsx)$/.test(e.name) && !/\.(test|spec)\.(ts|tsx)$/.test(e.name) && !e.name.endsWith(".d.ts")) out.push(p);
  }
  return out;
}

const files = SCAN_DIRS.flatMap((d) => walk(join(ROOT, d))).map((p) => relative(ROOT, p).split("\\").join("/"));
const source = (rel: string) => readFileSync(join(ROOT, rel), "utf8");

interface FileCensus {
  file: string;
  hits: CensusHit[];
}
const census: FileCensus[] = files.map((file) => ({ file, hits: censusSource(source(file), file, IDENT, [RENDER, LABEL]) }));

const importers = (target: string, roles: string[]) =>
  census
    .filter((c) => c.hits.some((h) => h.kind === "edge" && h.resolved === target && roles.includes(h.role)))
    .map((c) => c.file)
    .sort();

const VALUE_EDGE_ROLES = ["import", "reexport", "namespace-import", "dynamic-import", "require"];

describe("the scanner itself (inline sources)", () => {
  const run = (src: string, file = "server/approval/x.ts") => censusSource(src, file, IDENT, [RENDER, LABEL]);
  const roles = (hs: CensusHit[]) => hs.map((h) => `${h.kind}:${h.role}`);

  it("classifies a plain import and a call", () => {
    const hs = run(`import { renderApprovalView } from "./render";\nconst v = renderApprovalView(a);`);
    expect(roles(hs)).toEqual(expect.arrayContaining(["id:import", "edge:import", "id:call"]));
    expect(hs.find((h) => h.kind === "edge")?.resolved).toBe(RENDER);
  });

  it("an aliased import is still an importer of the module and of the name", () => {
    const hs = run(`import { renderApprovalView as r } from "@/server/approval/render";\nr(a);`);
    expect(roles(hs)).toEqual(expect.arrayContaining(["id:import", "edge:import"]));
  });

  it("export { x } from, export *, and export * as ns are reexports", () => {
    expect(roles(run(`export { renderApprovalView } from "./render";`))).toEqual(expect.arrayContaining(["id:reexport", "edge:reexport"]));
    expect(roles(run(`export * from "./render";`))).toEqual(["edge:reexport"]);
    expect(roles(run(`export * as R from "./render";`))).toEqual(["edge:reexport"]);
  });

  it("a namespace import and its member call", () => {
    const hs = run(`import * as R from "./render";\nR.renderApprovalView(a);`);
    expect(roles(hs)).toEqual(expect.arrayContaining(["edge:namespace-import", "id:namespace-member"]));
  });

  it("a dynamic import and a require", () => {
    expect(roles(run(`const m = await import("./render");`))).toEqual(["edge:dynamic-import"]);
    expect(roles(run(`const m = require("./render");`))).toEqual(["edge:require"]);
  });

  it("a type-only import is reported as type-import, never as a value importer", () => {
    expect(roles(run(`import type { ApprovalView } from "./render";`))).toEqual(["edge:type-import"]);
    expect(roles(run(`import { type ApprovalView } from "./render";`))).toEqual(["edge:type-import"]);
    expect(roles(run(`import { renderApprovalView, type ApprovalView } from "./render";`))).toEqual(expect.arrayContaining(["id:import", "edge:import"]));
  });

  it("a call inside a string literal, a template text or a comment is not code", () => {
    expect(run(`const s = "renderApprovalView(x)";`)).toEqual([]);
    expect(run("const s = `renderApprovalView(x) and ${1}`;")).toEqual([]);
    expect(run(`// renderApprovalView(x)\n/* renderApprovalView(y) */`)).toEqual([]);
  });

  it("a call inside a template expression IS code", () => {
    expect(roles(run("const s = `a ${renderApprovalView(x)} b`;"))).toEqual(["id:call"]);
  });

  it("a regex literal containing // does not hide a call on the same line", () => {
    const hs = run(`const r = /https?:\\/\\//; const v = renderApprovalView(a);`);
    expect(roles(hs)).toEqual(["id:call"]);
    const hs2 = run(`const r = x.replace(/a\\//g, ""); renderApprovalView(a);`);
    expect(roles(hs2)).toEqual(["id:call"]);
  });

  it("a definition, and a bare reference, are classified (the bare reference is the unclassified bucket)", () => {
    expect(roles(run(`export function renderApprovalView(a) {}`))).toEqual(["id:definition"]);
    expect(roles(run(`const f = renderApprovalView;`))).toEqual(["id:other"]);
  });

  it("an edge to an unrelated module or a package is not reported", () => {
    expect(run(`import { z } from "zod";\nimport { a } from "./other";`)).toEqual([]);
  });

  it("relative specifiers resolve against the importing file", () => {
    const hs = censusSource(`import { x } from "../approval/requester-label";`, "server/foo/y.ts", IDENT, [LABEL]);
    expect(hs.map((h) => h.resolved)).toEqual([LABEL]);
  });

  it("the tokenizer treats codeOffsets as call sites only", () => {
    expect(codeOffsets(`renderApprovalView(a); const x = renderApprovalView;`, IDENT)).toHaveLength(1);
    expect(tokenize(`a / b / c`).filter((t) => t.t === "id")).toHaveLength(3);
  });
});

describe("the scan covers the tree (instrument controls)", () => {
  it("scans at least every known server/approval source file, and the four roots are all present", () => {
    const approvalDir = readdirSync(join(ROOT, "server/approval")).filter((f) => f.endsWith(".ts") && !f.endsWith(".d.ts"));
    expect(files.filter((f) => f.startsWith("server/approval/")).length).toBeGreaterThanOrEqual(approvalDir.length);
    expect(files.length).toBeGreaterThan(200);
    for (const d of SCAN_DIRS) expect(files.some((f) => f.startsWith(`${d}/`)), d).toBe(true);
  });

  it("finds the definition and every allowed caller (a path typo that walks zero files fails here)", () => {
    for (const f of ["server/approval/render.ts", "server/approval/view-model.ts", "server/approval/gate-flow.ts", "server/approval/reattach.ts"]) {
      expect(files, f).toContain(f);
    }
  });
});

describe("renderApprovalView: callers are exactly the allowed ones", () => {
  const idHits = (role: string) =>
    census
      .flatMap((c) => c.hits.filter((h) => h.kind === "id" && h.role === role).map(() => c.file))
      .reduce<Record<string, number>>((acc, f) => ({ ...acc, [f]: (acc[f] ?? 0) + 1 }), {});

  it("calls: view-model.ts 1, gate-flow.ts 1, reattach.ts 1, and nothing else", () => {
    expect(idHits("call")).toEqual({
      "server/approval/view-model.ts": 1,
      "server/approval/gate-flow.ts": 1,
      "server/approval/reattach.ts": 1,
    });
  });

  it("the definition is render.ts, once", () => {
    expect(idHits("definition")).toEqual({ "server/approval/render.ts": 1 });
  });

  it("imports of the name: exactly the three callers", () => {
    expect(Object.keys(idHits("import")).sort()).toEqual(["server/approval/gate-flow.ts", "server/approval/reattach.ts", "server/approval/view-model.ts"]);
  });

  it("no alias, re-export, namespace use or bare reference anywhere (the red unclassified bucket is empty)", () => {
    expect(idHits("reexport")).toEqual({});
    expect(idHits("namespace-member")).toEqual({});
    expect(idHits("other")).toEqual({});
  });

  it("direct value importers of server/approval/render are exactly the known five-module set", () => {
    expect(importers(RENDER, VALUE_EDGE_ROLES)).toEqual([
      "server/approval/gate-flow.ts",
      "server/approval/inbox-enrich.ts",
      "server/approval/reattach.ts",
      "server/approval/view-model.ts",
    ].sort());
  });

  it("no client-tree module (app/, components/, lib/) imports the server render module", () => {
    const client = importers(RENDER, [...VALUE_EDGE_ROLES, "type-import"]).filter((f) => !f.startsWith("server/"));
    expect(client).toEqual([]);
  });
});

describe("the emit sites of an approval_request frame", () => {
  it("under server/, exactly gate-flow.ts and reattach.ts build one (ws-handler only receives the type)", () => {
    const re = /type:\s*"approval_request"/g;
    const emitters = files
      .filter((f) => f.startsWith("server/"))
      .map((f) => [f, (source(f).match(re) ?? []).length] as const)
      .filter(([, n]) => n > 0);
    expect(emitters).toEqual([
      ["server/approval/gate-flow.ts", 1],
      ["server/approval/reattach.ts", 1],
    ]);
  });
});

describe("reattach.ts: the redaction gate is structural", () => {
  const src = source("server/approval/reattach.ts");

  it("the three gate lines each appear once (whitespace-tolerant)", () => {
    expect((src.match(/const\s+mayView\s*=\s*canSeeAction\(/g) ?? []).length).toBe(1);
    expect((src.match(/toolName:\s*mayView\s*\?\s*approval\.tool_name\s*:\s*"redacted",/g) ?? []).length).toBe(1);
    expect((src.match(/view:\s*mayView\s*\?\s*renderApprovalView\(action\)\s*:\s*null,/g) ?? []).length).toBe(1);
  });

  it("exactly one canSeeAction( call and one renderApprovalView( call, the latter after the former", () => {
    const can = codeOffsets(src, "canSeeAction");
    const render = codeOffsets(src, IDENT);
    expect(can).toHaveLength(1);
    expect(render).toHaveLength(1);
    expect(render[0]).toBeGreaterThan(can[0]);
  });

  it("the call text is never in a comment of a scanned file (a comment would make the structural count lie)", () => {
    for (const f of ["server/approval/reattach.ts", "server/approval/gate-flow.ts"]) {
      const raw = source(f);
      const inCode = codeOffsets(raw, IDENT).length;
      const textual = (raw.match(/renderApprovalView\(/g) ?? []).length;
      expect(textual, f).toBe(inCode);
    }
  });

  it("the Guard-1 anchor lines are intact", () => {
    expect(src.split("\n").filter((l) => l.includes("isApprovalQueueEnabled({ userId: a.userId, workspaceId: w })"))).toHaveLength(1);
    expect(src.split("\n").filter((l) => l.includes("}) === approval.action_sha256;"))).toHaveLength(1);
    expect(src.split("\n").filter((l) => l.includes('reportApprovalOp("keyUnavailable", null, {'))).toHaveLength(1);
    const gate = source("server/approval/gate-flow.ts");
    expect(gate.split("\n").filter((l) => l.includes("view: renderApprovalView(action),"))).toHaveLength(1);
  });
});

describe("requester-label.ts: who may import the service-role email read", () => {
  it("direct value importers are exactly the gate deps, the ws handler and the Owner landing page", () => {
    expect(importers(LABEL, VALUE_EDGE_ROLES)).toEqual([
      "app/(dashboard)/dashboard/approvals/[id]/page.tsx",
      "server/approval/gate.ts",
      "server/ws-handler.ts",
    ]);
  });

  it("no client-tree module (components/, lib/) imports it in any form, including type-only", () => {
    const all = importers(LABEL, [...VALUE_EDGE_ROLES, "type-import"]);
    expect(all.filter((f) => f.startsWith("components/") || f.startsWith("lib/"))).toEqual([]);
    expect(all.some((f) => f.endsWith("approval-landing.tsx"))).toBe(false);
  });

  it("the file is on the CODEOWNERS-pinned service-role allowlist", () => {
    const allow = readFileSync(join(ROOT, ".service-role-allowlist"), "utf8");
    expect(allow.split("\n").map((l) => l.trim())).toContain("apps/web-platform/server/approval/requester-label.ts");
  });
});
