// Structural boundary for the C4 re-render (#8623, Guard 1 rows 1 and 8).
//
// The render must take no workspace path (so untracked, agent-written configs
// and symlinks in the worktree, and anything in its `.git`, can never reach
// likec4), and the likec4 binary must be spawned from exactly one module.
// Source is read with comments stripped, so prose naming these tokens cannot
// satisfy or trip the checks.
import { describe, it, expect, expectTypeOf } from "vitest";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { stripComments } from "./helpers/strip-comments";
import { renderC4Model, type StageFn } from "@/server/c4-render";

const APP = join(fileURLToPath(new URL(".", import.meta.url)), "..");

function code(rel: string): string {
  return stripComments(readFileSync(join(APP, rel), "utf8"), rel);
}

/** Named imports from `node:fs` / `node:fs/promises` / `fs` in a module. */
function fsImports(src: string): string[] {
  const names: string[] = [];
  for (const m of src.matchAll(/import\s*\{([^}]*)\}\s*from\s*["'](?:node:)?fs(?:\/promises)?["']/g)) {
    for (const n of m[1].split(",")) {
      const name = n.trim().split(/\s+as\s+/)[0];
      if (name) names.push(name);
    }
  }
  // A namespace or default import would hide what is used — refuse it.
  expect(src).not.toMatch(/import\s+(?:\*\s+as\s+\w+|\w+)\s+from\s*["'](?:node:)?fs(?:\/promises)?["']/);
  return names.sort();
}

function walk(dir: string, out: string[] = []): string[] {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|mjs|js)$/.test(n)) out.push(p);
  }
  return out;
}

describe("C4 re-render boundary (#8623)", () => {
  it("row 1: renderC4Model takes only a stage function — no workspace path", () => {
    expectTypeOf(renderC4Model).parameters.toEqualTypeOf<[StageFn]>();
    expect(renderC4Model.length).toBe(1);
  });

  it("row 1: c4-render.ts touches the filesystem only through its listed fs imports", () => {
    // constants/open: the no-follow read of the child's output (#8696 Guard 5);
    // realpath: binary resolution; writeFile: the boot probe's fixture stage.
    expect(fsImports(code("server/c4-render.ts"))).toEqual([
      "constants", "lstat", "mkdir", "mkdtemp", "open", "readFile", "readdir", "realpath", "rm", "writeFile",
    ]);
  });

  it("#8696: c4-render.ts has exactly one spawn( call site and imports only `spawn` from child_process", () => {
    const src = code("server/c4-render.ts");
    expect([...src.matchAll(/\bspawn\(/g)]).toHaveLength(1);
    const cp = [...src.matchAll(/import\s*(.*?)\s*from\s*["'](?:node:)?child_process["']/gs)].map((m) => m[1].trim());
    expect(cp).toEqual(["{ spawn }"]);
    expect(src).not.toMatch(/require\(\s*["'](?:node:)?child_process["']\s*\)|import\(\s*["'](?:node:)?child_process["']\s*\)/);
  });

  it("#8696: the ADR-050 amendment names exactly the failure classes the module emits", async () => {
    const { DETAIL_CLASSES } = await import("@/server/c4-render");
    const adr = readFileSync(
      join(APP, "..", "..", "knowledge-base", "engineering", "architecture", "decisions", "ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md"),
      "utf8",
    );
    const line = adr.split("\n").find((l) => l.startsWith("Failure classes:"));
    expect(line, "ADR-050 needs a `Failure classes:` line").toBeTruthy();
    const listed = [...line!.matchAll(/`([a-z0-9-]+)`/g)].map((m) => m[1]);
    expect(listed.sort()).toEqual([...DETAIL_CLASSES].sort());
  });

  it("#8696: the sandbox opt-out and its NODE_ENV decision are read only in c4-render.ts", () => {
    const hits = [...walk(join(APP, "server")), ...walk(join(APP, "lib")), ...walk(join(APP, "app"))]
      .filter((p) => /\bC4_RENDER_SANDBOX\b/.test(stripComments(readFileSync(p, "utf8"), p)))
      .map((p) => relative(APP, p));
    expect(hits).toEqual(["server/c4-render.ts"]);
    expect(code("server/c4-render.ts")).toMatch(/process\.env\.NODE_ENV === "production" \|\| process\.env\.C4_RENDER_SANDBOX !== "off"/);
  });

  it("#8696: server/index.ts calls the boot probe only inside the listen callback, under !dev, never awaited", () => {
    const src = code("server/index.ts");
    const calls = [...src.matchAll(/verifyC4RenderSandboxOnce/g)].map((m) => m.index!);
    // one import + one call
    expect(calls).toHaveLength(2);
    const listen = src.indexOf("server.listen(");
    expect(listen).toBeGreaterThan(-1);
    // The `if (!dev) {` block inside the listen callback, found by brace
    // matching, must contain the call itself (not a function returning it).
    const guard = src.indexOf("if (!dev) {", listen);
    expect(guard).toBeGreaterThan(listen);
    expect(guard).toBeLessThan(src.indexOf("\n  });", listen));
    let depth = 0;
    let end = -1;
    for (let i = src.indexOf("{", guard); i < src.length; i++) {
      if (src[i] === "{") depth++;
      else if (src[i] === "}" && --depth === 0) {
        end = i;
        break;
      }
    }
    const block = src.slice(guard, end);
    expect(block).toMatch(/\.then\(verifyC4RenderSandboxOnce\)/);
    expect(calls[1]).toBeGreaterThan(guard);
    expect(calls[1]).toBeLessThan(end);
    expect(block).not.toMatch(/await/);
  });

  it("row 1: c4-stage-sources.ts only creates directories and writes files", () => {
    expect(fsImports(code("server/c4-stage-sources.ts"))).toEqual(["mkdir", "writeFile"]);
  });

  it("row 1: neither module reads the workspace or os.tmpdir()", () => {
    for (const rel of ["server/c4-render.ts", "server/c4-stage-sources.ts"]) {
      const src = code(rel);
      expect(src, rel).not.toMatch(/\bworkspacePath\b/);
      expect(src, rel).not.toMatch(/\btmpdir\s*\(/);
      expect(src, rel).not.toMatch(/C4_DIAGRAMS_DIR\s*\)/); // no join(<ws>, …, C4_DIAGRAMS_DIR)
    }
  });

  it("row 8: the identifier LIKEC4_BIN occurs only in server/c4-render.ts", () => {
    const hits = [...walk(join(APP, "server")), ...walk(join(APP, "lib"))]
      .filter((p) => /\bLIKEC4_BIN\b/.test(stripComments(readFileSync(p, "utf8"), p)))
      .map((p) => relative(APP, p));
    expect(hits).toEqual(["server/c4-render.ts"]);
  });
  it("the render's only production caller is c4-writer.ts, and it stages with stageCommittedC4Sources", () => {
    const importers = [...walk(join(APP, "server")), ...walk(join(APP, "lib")), ...walk(join(APP, "app"))]
      .filter((p) => /\brenderC4Model\b/.test(stripComments(readFileSync(p, "utf8"), p)))
      .map((p) => relative(APP, p))
      .sort();
    expect(importers).toEqual(["server/c4-render.ts", "server/c4-writer.ts"]);
    const writer = code("server/c4-writer.ts");
    const call = writer.slice(writer.indexOf("renderC4Model("));
    const body = call.slice(0, call.indexOf("});") + 3);
    expect(body).toMatch(/stageCommittedC4Sources\(\{/);
    expect(body).not.toMatch(/workspacePath/);
  });
});
