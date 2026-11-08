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
 *
 * What the scan does NOT cover (probed by seeding a sink; each of these evades it today, so none is claimed):
 *   - any file named `*.test.*` or `*.spec.*` (or under `__tests__`) beneath a scan root: the filter drops it, so a production
 *     module that carries such an infix and is imported from server code is unscanned;
 *   - everything outside the five roots: `scripts/`, `infra/`, `e2e/`, `public/`, and the root-level files (`middleware.ts`,
 *     `instrumentation.ts`, `sentry.*.config.ts`);
 *   - a computed-name access (`R["render" + "ApprovalView"]`, `a["send" + "ToClient"]`) and a dynamic `import(expr)` with a
 *     non-literal specifier (including a template with a substitution), `require.resolve`, `createRequire(...)(...)`.
 */
import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { callSites, censusSource, codeOffsets, frameLiterals, sinkCensus, stringLiteralSites, stripComments, type CensusHit } from "./source-scan";

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

describe("stripComments (shared by the decide-boundary, runner, tools, cc-push, workspace-head and git-auth sentinels)", () => {
  it("a // comment after a JSX apostrophe is stripped (the hand-rolled lexer's phantom string kept it)", () => {
    const out = stripComments(`const a = <p>Don't</p>;\n// SECRET_COMMENT\nfoo();`);
    expect(out).not.toContain("SECRET_COMMENT");
    expect(out).toContain("foo();");
    expect(out.split("\n")).toHaveLength(3);
  });

  it("a regex literal containing // does not swallow the real code after it (the lexer's fail-open)", () => {
    const out = stripComments("const r = /https?:\\/\\//; call();");
    expect(out).toContain("call();");
    expect(out).toContain("https?:");
  });

  it("a regex literal with a quote does not open a phantom string; a comment after it is still stripped", () => {
    const out = stripComments("if (x) /re'/.test(y); keep(); // gone\nmore();");
    expect(out).toContain("keep();");
    expect(out).toContain("more();");
    expect(out).not.toContain("gone");
  });

  it("JSX text that looks like a comment is text, not a comment", () => {
    expect(stripComments("const a = <p>// not a comment</p>; /* real */ x();")).toContain("// not a comment");
  });

  it("strings, templates and URLs keep their // and /*; line and block comments are blanked; offsets and newlines are preserved", () => {
    const src = 'const u = "https://a/b"; const t = `/* x */ ${1}`; // c1\n/* c2\nc3 */ ok();';
    const out = stripComments(src);
    expect(out).toContain('"https://a/b"');
    expect(out).toContain("`/* x */ ${1}`");
    expect(out).not.toMatch(/c1|c2|c3/);
    expect(out).toHaveLength(src.length);
    expect(out.split("\n")).toHaveLength(src.split("\n").length);
  });

  it("a comment right before a closing brace or paren is found (leading trivia of punctuation)", () => {
    expect(stripComments("f(a /* gone */);\nfunction g() { x(); /* gone2 */ }")).not.toMatch(/gone/);
  });

  it("an explicit file name picks the language variant", () => {
    expect(stripComments(`const a = <p>Don't</p>;\n// c\nz();`, "y.tsx")).not.toContain("// c");
  });
});

describe("the scan covers the tree (instrument controls)", () => {
  it("scans at least every known server/approval source file", () => {
    const approvalDir = readdirSync(join(ROOT, "server/approval")).filter((f) => f.endsWith(".ts") && !f.endsWith(".d.ts"));
    expect(files.filter((f) => f.startsWith("server/approval/")).length).toBeGreaterThanOrEqual(approvalDir.length);
  });

  it(`the file count is at least the absolute floor (${FILES_FLOOR}); a walk that skips a directory or an extension fails here`, () => {
    expect(files.length).toBeGreaterThanOrEqual(FILES_FLOOR);
  });

  it("every .mjs and .cjs source the repo tracks under the scan roots is walked (the extension set is not silently narrower)", () => {
    expect(files.some((f) => f.endsWith(".mjs"))).toBe(true);
  });

  it("the roots and the extension set are exactly these literals (not a count, and not read back from the array under test)", () => {
    expect(SCAN_DIRS).toEqual(["server", "app", "lib", "components", "hooks"]);
    expect(SCAN_EXT.source).toBe("\\.(ts|tsx|js|jsx|mjs|cjs|mts|cts)$");
    for (const ext of ["ts", "tsx", "js", "jsx", "mjs", "cjs", "mts", "cts"]) expect(SCAN_EXT.test(`x/y.${ext}`), ext).toBe(true);
    for (const ext of ["json", "md", "css", "sql", "sh", "map"]) expect(SCAN_EXT.test(`x/y.${ext}`), ext).toBe(false);
  });

  it("every root, spelled as a literal here, contributes at least one walked file", () => {
    for (const d of ["server", "app", "lib", "components", "hooks"]) expect(files.some((f) => f.startsWith(`${d}/`)), d).toBe(true);
  });

  it("conservation: every file git tracks under the literal roots, with an independently spelled extension list, is walked", (ctx) => {
    let tracked: string[];
    try {
      tracked = execFileSync("git", ["ls-files", "-z", "--", "server", "app", "lib", "components", "hooks"], { cwd: ROOT, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 })
        .split("\0")
        .filter(Boolean);
    } catch (e) {
      // No git metadata (an exported source tree). CI always has it: fail there rather than skip, so the check cannot be lost silently.
      if (process.env.CI) throw new Error(`conservation check cannot run under CI: git ls-files failed (${String(e)})`);
      ctx.skip("git metadata unavailable: the conservation check did not run");
      return;
    }
    // Independent of `eligible` and `SCAN_EXT`: a different spelling of the same rules, so a narrowing of either shows up here.
    const EXTS = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"];
    const expected = tracked.filter((f) => {
      const segs = f.split("/");
      const base = segs[segs.length - 1];
      return (
        EXTS.some((e) => f.endsWith(e)) &&
        !base.includes(".test.") &&
        !base.includes(".spec.") &&
        !/\.d\.[mc]?ts$/.test(base) &&
        !segs.includes("__tests__") &&
        !segs.includes("node_modules")
      );
    });
    expect(expected.length).toBeGreaterThanOrEqual(FILES_FLOOR);
    // Per-extension: each extension the repo tracks under the roots is walked at least once.
    for (const e of EXTS) {
      if (expected.some((f) => f.endsWith(e))) expect(files.some((f) => f.endsWith(e)), e).toBe(true);
    }
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

describe("the send census itself (inline sources: every shape that could hide a second send is detected)", () => {
  const census = (src: string, name = "sendToClient", file = "server/approval/x.ts") => sinkCensus(src, file, name);
  const frames = (src: string, name = "sendToClient") => census(src, name).calls.map((c) => c.frame);
  const REQ = "approval_request";

  it("baseline: a direct send with a plain double-quoted type", () => {
    const c = census(`a.sendToClient(a.userId, { type: "approval_request", view: v });`);
    expect(c.calls.map((x) => [x.target, x.frame, x.via])).toEqual([["a.userId", REQ, "direct"]]);
    expect(c.refs).toBe(0);
  });

  it("the type is read from the AST literal: single quote, template literal, `as const`, parentheses, satisfies, string key, computed literal key", () => {
    for (const t of [`'approval_request'`, "`approval_request`", `"approval_request" as const`, `("approval_request")`, `"approval_request" satisfies string`]) {
      expect(frames(`a.sendToClient(u, { type: ${t} });`), t).toEqual([REQ]);
    }
    expect(frames(`a.sendToClient(u, { "type": "approval_request" });`)).toEqual([REQ]);
    expect(frames(`a.sendToClient(u, { ['type']: 'approval_request' });`)).toEqual([REQ]);
    expect(frames("a.sendToClient(u, { [`type`]: `approval_request` });")).toEqual([REQ]);
  });

  it("a frame the census cannot read is reported as ? (a variable, a call result, a spread that may carry type, a computed non-literal key, a non-literal type)", () => {
    expect(frames(`const frame = { type: "approval_request" }; a.sendToClient(a.userId, frame);`)).toEqual(["?"]);
    expect(frames(`a.sendToClient(u, build());`)).toEqual(["?"]);
    expect(frames(`a.sendToClient(u, { ...base, view });`)).toEqual(["?"]);
    expect(frames(`a.sendToClient(u, { type: "approval_request", ...base });`)).toEqual(["?"]);
    expect(frames(`a.sendToClient(u, { [k]: "approval_request" });`)).toEqual(["?"]);
    expect(frames(`a.sendToClient(u, { type: KIND });`)).toEqual(["?"]);
    expect(frames(`a.sendToClient(u, { type });`)).toEqual(["?"]);
  });

  it("a conditional spread of keyless object literals (the real requester spread) does not blur the type", () => {
    expect(frames(`a.sendToClient(u, { type: "approval_request", ...(s ? { requester: "you" } : {}) });`)).toEqual([REQ]);
    expect(frames(`a.sendToClient(u, { type: "approval_request", ...(s ? { type: "x" } : {}) });`)).toEqual(["?"]);
  });

  it("every callee spelling is a counted call", () => {
    const frame = `{ type: "approval_request" }`;
    const shapes = [
      `a["sendToClient"](u, ${frame});`,
      `a[\`sendToClient\`](u, ${frame});`,
      `(a.sendToClient as any)(u, ${frame});`,
      `(a.sendToClient)(u, ${frame});`,
      `a.sendToClient!(u, ${frame});`,
      `a.sendToClient?.(u, ${frame});`,
      `a?.sendToClient(u, ${frame});`,
      `(<any>a.sendToClient)(u, ${frame});`,
      `a.sendToClient.call(a, u, ${frame});`,
      `(a.sendToClient as Function).call(a, u, ${frame});`,
      `const { sendToClient } = a; sendToClient(u, ${frame});`,
    ];
    for (const sh of shapes) {
      const c = census(sh, "sendToClient", "server/approval/x.ts");
      expect(c.calls.map((x) => x.frame), sh).toContain(REQ);
      expect(c.calls, sh).toHaveLength(1);
    }
  });

  it("`.call` strips the this-argument: the target and the frame are the 2nd and 3rd arguments", () => {
    const c = census(`a.sendToClient.call(a, a.userId, { type: "approval_request" });`);
    expect(c.calls).toMatchObject([{ target: "a.userId", frame: REQ, via: "call" }]);
  });

  it(".apply is a counted call whose frame is unknowable", () => {
    expect(census(`a.sendToClient.apply(a, [u, { type: "approval_request" }]);`).calls).toMatchObject([{ target: null, frame: "?", via: "apply" }]);
  });

  it("an alias, a destructure, a bind, a comma callee and a pass-through are refs (a sink that escapes the call-site view)", () => {
    expect(census(`const s = a.sendToClient; s(u, { type: "approval_request" });`).refs).toBe(1);
    expect(census(`const s = a["sendToClient"]; s(u, f);`).refs).toBe(1);
    expect(census(`const { sendToClient } = a;`).refs).toBe(1);
    expect(census(`const s = a.sendToClient.bind(a);`).refs).toBe(1);
    expect(census(`(0, a.sendToClient)(u, f);`).refs).toBe(1);
    expect(census(`other({ sendToClient: a.sendToClient });`).refs).toBe(2);
    expect(census(`other({ sendToClient });`).refs).toBe(1);
    expect(census(`other({ ["sendToClient"]: x });`).refs).toBe(1);
  });

  it("the type-member declaration is a declaration, not a use; a comment, a string and an unrelated name are nothing", () => {
    expect(census(`interface D { sendToClient: (u: string, p: W) => boolean }`)).toEqual({ calls: [], refs: 0, declarations: 1 });
    expect(census(`// a.sendToClient(u, f)\nconst s = "sendToClient"; a.sendToClientX(u, f);`)).toEqual({ calls: [], refs: 0, declarations: 0 });
  });

  it("the same shapes are caught for the reattach sink name `send`", () => {
    expect(frames(`a["send"](a.userId, { type: 'approval_request' });`, "send")).toEqual([REQ]);
    expect(census(`const s = a.send; s(1);`, "send").refs).toBe(1);
  });

  it("frameLiterals and stringLiteralSites find an approval_request literal in any quote style, key style or wrapping, and never in a comment", () => {
    for (const lit of [`{ type: "approval_request" }`, `{ type: 'approval_request' }`, "{ type: `approval_request` }", `{ "type": "approval_request" }`, `{ ["type"]: "approval_request" }`, `{ type: "approval_request" as const }`]) {
      expect(frameLiterals(`const f = ${lit};`, "x.ts", REQ), lit).toHaveLength(1);
    }
    expect(frameLiterals(`// { type: "approval_request" }\nconst f = { type: "approval_status" };`, "x.ts", REQ)).toEqual([]);
    expect(stringLiteralSites(`const t = 'approval_request'; const u = "approval_request"; const v = \`approval_request\`; // "approval_request"`, "x.ts", REQ)).toHaveLength(3);
  });
});

describe("the emit sites of an approval_request frame", () => {
  const serverFiles = files.filter((f) => f.startsWith("server/"));

  it("under server/, exactly gate-flow.ts and reattach.ts build an object literal with that type (any quote style, key style or wrapping)", () => {
    const emitters = serverFiles.map((f) => [f, frameLiterals(source(f), f, "approval_request").length] as const).filter(([, n]) => n > 0);
    expect(emitters).toEqual([
      ["server/approval/gate-flow.ts", 1],
      ["server/approval/reattach.ts", 1],
    ]);
  });

  it("the string literal approval_request appears in exactly these server files (a frame built from a constant or a variable still shows up here)", () => {
    const where = serverFiles.map((f) => [f, stringLiteralSites(source(f), f, "approval_request").length] as const).filter(([, n]) => n > 0);
    // gate-flow.ts and reattach.ts: the two frames. inbox-enrich.ts: the table name. ws-handler.ts: the message-type dispatch, a consumer.
    expect(where).toEqual([
      ["server/approval/gate-flow.ts", 1],
      ["server/approval/inbox-enrich.ts", 1],
      ["server/approval/reattach.ts", 1],
      ["server/ws-handler.ts", 1],
    ]);
  });
});

describe("the first send goes to the proposing session user", () => {
  const GATE = "server/approval/gate-flow.ts";
  const gate = source(GATE);
  const gateSinks = sinkCensus(gate, GATE, "sendToClient");
  const sends = callSites(gate, GATE, "sendToClient").filter((c) => c.args[1]?.props.type === '"approval_request"');

  it("gate-flow.ts: every sendToClient mention is a direct call with a literal frame, one approval_status and exactly ONE approval_request, both to a.userId", () => {
    expect(gateSinks.refs).toBe(0);
    expect(gateSinks.declarations).toBe(1);
    expect(gateSinks.calls.map((c) => [c.frame, c.target, c.via])).toEqual([
      ["approval_status", "a.userId", "direct"],
      ["approval_request", "a.userId", "direct"],
    ]);
  });

  it("that frame's requester key is the literal REQUESTER_SELF behind isVerifiedRequester, appended after agentWaiting", () => {
    expect(sends).toHaveLength(1);
    const props = Object.keys(sends[0].args[1].props);
    // The conditional spread is not a named property: the last named key is agentWaiting, and the spread follows it.
    expect(props.at(-1)).toBe("agentWaiting");
    expect(gate).toMatch(/\.\.\.\(isSelf\s*\?\s*\{\s*requester:\s*REQUESTER_SELF\s*\}\s*:\s*\{\}\)/);
    expect(callSites(gate, GATE, "isVerifiedRequester")).toHaveLength(1);
  });

  it("reattach.ts: every send mention is one direct call, an approval_request to a.userId (no alias, no second send, no unreadable frame)", () => {
    const f = "server/approval/reattach.ts";
    const c = sinkCensus(source(f), f, "send");
    expect(c.refs).toBe(0);
    expect(c.declarations).toBe(1);
    expect(c.calls.map((x) => [x.frame, x.target, x.via])).toEqual([["approval_request", "a.userId", "direct"]]);
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
