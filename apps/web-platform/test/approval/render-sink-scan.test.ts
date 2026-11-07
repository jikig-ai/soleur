/**
 * #9601: the sentinel behind "an approval_request frame carries action text only for an Owner or the row's requester".
 *
 * A redaction rule with no pin on every caller of `renderApprovalView` rots the day someone adds the next caller. This
 * suite scans every non-test source under server/, app/, lib/, components/ and hooks/ (all of .ts .tsx .js .jsx .mjs .cjs
 * .mts .cts), parses each with the TypeScript parser (see ./source-scan), censuses the bare identifier `renderApprovalView`
 * and the module edges to `server/approval/render`, `server/approval/requester-label` and `server/approval/view-model`
 * (resolved to a file path: every in-tree importer uses a relative or aliased specifier, so a substring match would find
 * none), and pins each against an exact allow-list with counts. Anything the classifier cannot place is the red
 * `unclassified` bucket.
 *
 * The allow-lists below are literals: changing them is a reviewed edit in the same diff as the source they name.
 * Named residual: a computed-name access and a dynamic `import(expr)` with a non-literal specifier are invisible to a
 * static scan.
 */
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { callSites, censusSource, codeOffsets, type CensusHit } from "./source-scan";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SCAN_DIRS = ["server", "app", "lib", "components", "hooks"];
const SCAN_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|mts|cts)$/;
const RENDER = "server/approval/render";
const LABEL = "server/approval/requester-label";
const VIEW_MODEL = "server/approval/view-model";
const IDENT = "renderApprovalView";
/** An absolute floor (about 90% of the real count): a walk that silently skips a directory or an extension fails below it. */
const FILES_FLOOR = 915;

/** The scan's file filter, shared by the walker and the git enumerator so the two can only differ on what exists. */
const eligible = (rel: string) =>
  SCAN_EXT.test(rel) && !/\.(test|spec)\./.test(rel) && !/\.d\.(ts|mts|cts)$/.test(rel) && !rel.split("/").includes("__tests__") && !rel.split("/").includes("node_modules") && !rel.split("/").includes(".next");

function walk(dir: string, out: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "node_modules" || e.name === ".next" || e.name === "__tests__") continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (eligible(relative(ROOT, p).split("\\").join("/"))) out.push(p);
  }
  return out;
}

const files = SCAN_DIRS.flatMap((d) => {
  try {
    return walk(join(ROOT, d));
  } catch {
    return [];
  }
})
  .map((p) => relative(ROOT, p).split("\\").join("/"))
  .sort();
const source = (rel: string) => readFileSync(join(ROOT, rel), "utf8");

interface FileCensus {
  file: string;
  hits: CensusHit[];
}
const census: FileCensus[] = files.map((file) => ({ file, hits: censusSource(source(file), file, IDENT, [RENDER, LABEL, VIEW_MODEL]) }));

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

  it("JSX text with an apostrophe does not desync the scan: a call and an import below it are still found (the lexer's failure)", () => {
    const src = `export function C() { return <p>Don't panic</p>; }\nconst v = renderApprovalView(a);\nimport { renderApprovalView } from "./render";`;
    const hs = run(src, "server/approval/x.tsx");
    expect(roles(hs)).toEqual(expect.arrayContaining(["id:import", "edge:import", "id:call"]));
    expect(roles(hs).filter((r) => r === "id:call")).toHaveLength(1);
  });

  it("a regex literal with a quote after an if-condition does not hide the call that follows (the lexer's other failure)", () => {
    const hs = run(`if (x) /re'/.test(y); renderApprovalView(a);\nimport { renderApprovalView } from "./render";`);
    expect(roles(hs).filter((r) => r === "id:call")).toHaveLength(1);
    expect(roles(hs)).toContain("edge:import");
  });

  it("a regex literal containing // does not hide a call on the same line", () => {
    expect(roles(run(`const r = /https?:\\/\\//; const v = renderApprovalView(a);`))).toEqual(["id:call"]);
    expect(roles(run(`const r = x.replace(/a\\//g, ""); renderApprovalView(a);`))).toEqual(["id:call"]);
  });

  it("an aliased import is still an importer of the module and of the name, and a call through the alias is a call", () => {
    const hs = run(`import { renderApprovalView as r } from "@/server/approval/render";\nr(a);`);
    expect(roles(hs)).toEqual(expect.arrayContaining(["id:import", "edge:import", "id:call"]));
    expect(roles(run(`import { renderApprovalView as r } from "./render";\nconst f = r;`))).toContain("id:other");
  });

  it("export { x } from, export *, and export * as ns are reexports", () => {
    expect(roles(run(`export { renderApprovalView } from "./render";`))).toEqual(expect.arrayContaining(["id:reexport", "edge:reexport"]));
    expect(roles(run(`export { renderApprovalView as show } from "./render";`))).toEqual(expect.arrayContaining(["id:reexport", "edge:reexport"]));
    expect(roles(run(`export * from "./render";`))).toEqual(["edge:reexport"]);
    expect(roles(run(`export * as R from "./render";`))).toEqual(["edge:reexport"]);
  });

  it("a namespace import and its member call", () => {
    const hs = run(`import * as R from "./render";\nR.renderApprovalView(a);`);
    expect(roles(hs)).toEqual(expect.arrayContaining(["edge:namespace-import", "id:namespace-member"]));
    expect(roles(run(`import * as R from "./render";\nR["renderApprovalView"](a);`))).toContain("id:namespace-member");
  });

  it("a dynamic import, a require and an import-equals are edges of their own role", () => {
    expect(roles(run(`const m = await import("./render");`))).toEqual(["edge:dynamic-import"]);
    expect(roles(run(`const m = require("./render");`))).toEqual(["edge:require"]);
    expect(roles(run(`import m = require("./render");`))).toEqual(["edge:require"]);
    expect(roles(run(`const m = await import(\`./render\`);`))).toEqual(["edge:dynamic-import"]);
  });

  it("a type-only import is reported as type-import, never as a value importer", () => {
    expect(roles(run(`import type { ApprovalView } from "./render";`))).toEqual(["edge:type-import"]);
    expect(roles(run(`import { type ApprovalView } from "./render";`))).toEqual(["edge:type-import"]);
    expect(roles(run(`import { renderApprovalView, type ApprovalView } from "./render";`))).toEqual(expect.arrayContaining(["id:import", "edge:import"]));
    expect(roles(run(`let v: import("./render").ApprovalView;`))).toEqual(["edge:type-import"]);
  });

  it("a call inside a string literal, a template text or a comment is NOT counted", () => {
    expect(run(`const s = "renderApprovalView(x)";`)).toEqual([]);
    expect(run("const s = `renderApprovalView(x) and ${1}`;")).toEqual([]);
    expect(run(`// renderApprovalView(x)\n/* renderApprovalView(y) */`)).toEqual([]);
    expect(run(`const s = 'import { renderApprovalView } from "./render"';`)).toEqual([]);
  });

  it("a call inside a template expression IS code", () => {
    expect(roles(run("const s = `a ${renderApprovalView(x)} b`;"))).toEqual(["id:call"]);
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
    expect(censusSource(`import { x } from "./view-model.js";`, "server/approval/y.mjs", IDENT, [VIEW_MODEL]).map((h) => h.resolved)).toEqual([VIEW_MODEL]);
  });

  it("codeOffsets and callSites see real calls only; a call's arguments and object properties are readable", () => {
    expect(codeOffsets(`renderApprovalView(a); const x = renderApprovalView; // renderApprovalView(b)`, IDENT)).toHaveLength(1);
    const [c] = callSites(`a.sendToClient(a.userId, { type: "approval_request", view: v });`, "x.ts", "sendToClient");
    expect(c.args[0].text).toBe("a.userId");
    expect(c.args[1].props.type).toBe('"approval_request"');
  });
});

describe("the scan covers the tree (instrument controls)", () => {
  it("scans at least every known server/approval source file, and every root is present", () => {
    const approvalDir = readdirSync(join(ROOT, "server/approval")).filter((f) => f.endsWith(".ts") && !f.endsWith(".d.ts"));
    expect(files.filter((f) => f.startsWith("server/approval/")).length).toBeGreaterThanOrEqual(approvalDir.length);
    for (const d of SCAN_DIRS) expect(files.some((f) => f.startsWith(`${d}/`)), d).toBe(true);
  });

  it(`the file count is at least the absolute floor (${FILES_FLOOR}); a walk that skips a directory or an extension fails here`, () => {
    expect(files.length).toBeGreaterThanOrEqual(FILES_FLOOR);
  });

  it("every .mjs and .cjs source the repo tracks under the scan roots is walked (the extension set is not silently narrower)", () => {
    expect(files.some((f) => f.endsWith(".mjs"))).toBe(true);
  });

  it("conservation: every file git tracks under the scan roots that passes the filter is in the walked set", () => {
    let tracked: string[];
    try {
      tracked = execFileSync("git", ["ls-files", "-z", "--", ...SCAN_DIRS], { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 })
        .split("\0")
        .filter(Boolean);
    } catch {
      // No git metadata (an exported source tree): the absolute floor above still holds the line.
      return;
    }
    const expected = tracked.filter(eligible);
    expect(expected.length).toBeGreaterThanOrEqual(FILES_FLOOR);
    const walked = new Set(files);
    expect(expected.filter((f) => !walked.has(f))).toEqual([]);
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

  it("direct value importers of server/approval/render are exactly the known four-module set", () => {
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
    const re = /type:\s*["'`]approval_request["'`]/g;
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

describe("the first send goes to the proposing session user", () => {
  const GATE = "server/approval/gate-flow.ts";
  const gate = source(GATE);
  const sends = callSites(gate, GATE, "sendToClient").filter((c) => c.args[1]?.props.type === '"approval_request"');

  it("gate-flow.ts has exactly ONE sendToClient of an approval_request, and it targets a.userId", () => {
    expect(sends).toHaveLength(1);
    expect(sends[0].args[0].text).toBe("a.userId");
  });

  it("that frame's requester key is the literal REQUESTER_SELF behind isVerifiedRequester, appended after agentWaiting", () => {
    const props = Object.keys(sends[0].args[1].props);
    // The conditional spread is not a named property: the last named key is agentWaiting, and the spread follows it.
    expect(props.at(-1)).toBe("agentWaiting");
    expect(gate).toMatch(/\.\.\.\(isSelf\s*\?\s*\{\s*requester:\s*REQUESTER_SELF\s*\}\s*:\s*\{\}\)/);
    expect(callSites(gate, GATE, "isVerifiedRequester")).toHaveLength(1);
  });

  it("reattach.ts has exactly ONE send of an approval_request, and it targets a.userId", () => {
    const f = "server/approval/reattach.ts";
    const re = callSites(source(f), f, "send").filter((c) => c.args[1]?.props.type === '"approval_request"');
    expect(re).toHaveLength(1);
    expect(re[0].args[0].text).toBe("a.userId");
  });
});

describe("reattach.ts: the redaction gate is structural", () => {
  const FILE = "server/approval/reattach.ts";
  const src = source(FILE);

  it("the three gate lines each appear once (whitespace-tolerant), and the gate is the FULL canSeeAction call", () => {
    expect(
      (src.match(/const\s+mayView\s*=\s*canSeeAction\(\s*a\.userId\s*,\s*viewerRole\s*===\s*"owner"\s*,\s*approval\.requested_by_user_id\s*\)/g) ?? []).length,
    ).toBe(1);
    expect((src.match(/toolName:\s*mayView\s*\?\s*approval\.tool_name\s*:\s*"redacted",/g) ?? []).length).toBe(1);
    expect((src.match(/view:\s*mayView\s*\?\s*renderApprovalView\(action\)\s*:\s*null,/g) ?? []).length).toBe(1);
  });

  it("exactly one canSeeAction( call with exactly those arguments, and one renderApprovalView( call, the latter after the former", () => {
    const can = callSites(src, FILE, "canSeeAction");
    const render = codeOffsets(src, IDENT, FILE);
    expect(can).toHaveLength(1);
    expect(can[0].args.map((a) => a.text)).toEqual(["a.userId", 'viewerRole==="owner"', "approval.requested_by_user_id"]);
    expect(render).toHaveLength(1);
    expect(render[0]).toBeGreaterThan(can[0].pos);
  });

  it("the call text is never in a comment of a scanned file (a comment would make the structural count lie)", () => {
    for (const f of [FILE, "server/approval/gate-flow.ts"]) {
      const raw = source(f);
      const inCode = codeOffsets(raw, IDENT, f).length;
      const textual = (raw.match(/renderApprovalView\(/g) ?? []).length;
      expect(textual, f).toBe(inCode);
    }
  });

  it("the Guard-1 anchor lines are intact", () => {
    const lines = (text: string, needle: string) => text.split("\n").filter((l) => l.includes(needle));
    expect(lines(src, "isApprovalQueueEnabled({ userId: a.userId, workspaceId: w })")).toHaveLength(1);
    expect(lines(src, "}) === approval.action_sha256;")).toHaveLength(1);
    expect(lines(src, 'reportApprovalOp("keyUnavailable", null, {')).toHaveLength(1);
    expect(lines(source("server/approval/gate-flow.ts"), "view: renderApprovalView(action),")).toHaveLength(1);
  });
});

describe("view-model.ts: who may import the stored-row renderer", () => {
  it("importers (value or type) are exactly the Owner landing page and inbox-enrich.ts", () => {
    expect(importers(VIEW_MODEL, [...VALUE_EDGE_ROLES, "type-import"])).toEqual([
      "app/(dashboard)/dashboard/approvals/[id]/page.tsx",
      "server/approval/inbox-enrich.ts",
    ]);
  });
});

describe("requester-label.ts: who may import the service-role email read", () => {
  it("direct value importers are exactly the ws handler and the Owner landing page", () => {
    expect(importers(LABEL, VALUE_EDGE_ROLES)).toEqual([
      "app/(dashboard)/dashboard/approvals/[id]/page.tsx",
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
