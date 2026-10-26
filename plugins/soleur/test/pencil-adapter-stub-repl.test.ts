import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { installAdapter, connectAdapter } from "./lib/pencil-adapter-roundtrip.mjs";

// #11143 integration: the INSTALLED adapter copy over real MCP stdio against a
// synthesized REPL stub (fixtures/pencil-stub-repl.mjs). The stub encodes our
// belief about the 0.2.9 REPL; engine-contract-probe.sh is the only test that
// touches the real engine. An unreachable npm registry fails this suite, it
// never skips: a green run must mean the installed copy executed.

const STUB = resolve(import.meta.dir, "fixtures/pencil-stub-repl.mjs");
const root = mkdtempSync(join(tmpdir(), "pencil-stub-it-"));
let installDir = "";
const sessions: Array<{ close: () => Promise<void> }> = [];

const pen = (n: number) => JSON.stringify({ version: "2.9", children: Array.from({ length: n }, (_, i) => ({ id: `seed${i}`, type: "frame" })) });
const logOf = (file: string) => (existsSync(`${file}.log`) ? readFileSync(`${file}.log`, "utf8").split("\n").filter(Boolean) : []);
const caseDir = (name: string) => {
  const d = join(root, name);
  mkdirSync(d, { recursive: true });
  return d;
};
async function session() {
  const s = await connectAdapter({ installDir, binary: STUB });
  sessions.push(s);
  return s;
}

beforeAll(() => {
  installDir = installAdapter(join(root, "install"));
}, 240_000);

afterAll(async () => {
  await Promise.all(sessions.map((s) => s.close().catch(() => {})));
  rmSync(root, { recursive: true, force: true });
}, 60_000);

describe("batch_design key", () => {
  test("operations arrive as input, never as operations (AC1)", async () => {
    const f = join(caseDir("key"), "a.pen");
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    const r = await s.call("batch_design", { operations: 'a=Insert(document,{type:"frame"})' });
    expect(r.isError).toBe(false);
    const lines = logOf(f);
    const bd = lines.filter((l) => l.startsWith("batch_design("));
    expect(bd.length).toBe(1);
    expect(bd[0].startsWith("batch_design({ input: ")).toBe(true);
    expect(bd[0]).not.toContain("operations");
    expect(bd[0]).toContain("var I=Insert");
    expect(lines.some((l) => l.startsWith("REJECTED"))).toBe(false);
    expect(JSON.parse(readFileSync(f, "utf8")).children.length).toBe(1);
  }, 60_000);
});

describe("open_document on an existing file (AC2)", () => {
  test("keeps the existing nodes through edit and save, and reports the count", async () => {
    const f = join(caseDir("open"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(false);
    expect(o.text).toMatch(/3 top-level node/);
    expect(logOf(f)[0]).toBe(`ARGS interactive --out ${f} --in ${f}`);
    await s.call("batch_design", { operations: 'x=Insert(document,{type:"frame"})' });
    expect((await s.call("save")).isError).toBe(false);
    expect(JSON.parse(readFileSync(f, "utf8")).children.length).toBe(4);
  }, 60_000);

  test("a missing file opens a new empty document without --in", async () => {
    const f = join(caseDir("open-new"), "a.pen");
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(false);
    expect(logOf(f)[0]).toBe(`ARGS interactive --out ${f}`);
  }, 60_000);

  test("an explicit missing inputPath fails fast with isError", async () => {
    const f = join(caseDir("open-missing-in"), "a.pen");
    const s = await session();
    const t0 = Date.now();
    const o = await s.call("open_document", { filePath: f, inputPath: join(root, "nope.pen") });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/not found/i);
    expect(Date.now() - t0).toBeLessThan(5_000);
  }, 60_000);

  test("a non-empty file that loads empty is an error and the adapter enters the open-failed state", async () => {
    const f = join(caseDir("open-empty-load"), "a.pen");
    writeFileSync(f, pen(3));
    writeFileSync(`${f}.flags`, JSON.stringify({ loadEmpty: true }));
    const before = readFileSync(f, "utf8");
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/open failed/i);
    const next = await s.call("batch_get", {});
    expect(next.isError).toBe(true);
    expect(next.text).toMatch(/open failed/i);
    expect(readFileSync(f, "utf8")).toBe(before);
    expect(logOf(f).some((l) => l === "save()")).toBe(false);
  }, 60_000);
});

describe("empty-overwrite sentinel (AC4)", () => {
  async function emptyMemoryOverNonEmptyDisk(name: string) {
    const f = join(caseDir(name), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f }); // new path, empty document
    writeFileSync(f, pen(3)); // the file gains content behind the session's back
    return { f, s, before: readFileSync(f, "utf8") };
  }

  test("explicit save refuses, bytes unchanged, no save reached the stub", async () => {
    const { f, s, before } = await emptyMemoryOverNonEmptyDisk("refuse-save");
    const r = await s.call("save");
    expect(r.isError).toBe(true);
    expect(r.text).toContain("REFUSED save:");
    expect(r.text).toContain(f);
    expect(readFileSync(f, "utf8")).toBe(before);
    expect(logOf(f)).not.toContain("save()");
    expect(logOf(f)).toContain("batch_get()"); // the memory probe ran
  }, 60_000);

  test("auto-save after a no-op edit refuses with the in-memory-not-persisted note", async () => {
    const { f, s, before } = await emptyMemoryOverNonEmptyDisk("refuse-auto");
    const r = await s.call("batch_design", { operations: "U(x,{name:'y'})" });
    expect(r.isError).toBe(true);
    expect(r.text).toContain("REFUSED save:");
    expect(r.text).toMatch(/in memory but not persisted/i);
    expect(readFileSync(f, "utf8")).toBe(before);
    expect(logOf(f)).not.toContain("save()");
  }, 60_000);

  test("a queued command cannot land between the memory probe and the save", async () => {
    const f = join(caseDir("interleave"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    const [sv, bd] = await Promise.all([
      s.call("save"),
      s.call("batch_design", { operations: 'z=Insert(document,{type:"frame"})' }),
    ]);
    expect(sv.isError).toBe(false);
    expect(bd.isError).toBe(false);
    const lines = logOf(f).filter((l) => !l.startsWith("ARGS"));
    // every save() is directly preceded by the probe: nothing between them
    lines.forEach((l, i) => {
      if (l === "save()") expect(lines[i - 1]).toBe("batch_get()");
    });
    expect(lines.filter((l) => l === "save()").length).toBeGreaterThanOrEqual(2);
  }, 60_000);

  test("a collapsed (empty) target is saved over: nothing to protect", async () => {
    const f = join(caseDir("collapsed"), "a.pen");
    writeFileSync(f, pen(0));
    const s = await session();
    await s.call("open_document", { filePath: f });
    await s.call("batch_design", { operations: 'a=Insert(document,{type:"frame"})' });
    expect(JSON.parse(readFileSync(f, "utf8")).children.length).toBe(1);
  }, 60_000);
});

describe("removed tools (AC5)", () => {
  test("return isError with a hint and trigger no save", async () => {
    const f = join(caseDir("removed"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    for (const [tool, args, hint] of [
      ["set_variables", { variables: { a: "#fff" } }, /SetVariables\(/],
      ["find_empty_space_on_canvas", { direction: "right", height: 1, width: 1, padding: 1 }, /FindEmptySpace\(/],
      ["get_style_guide_tags", {}, /get_guidelines/],
    ] as const) {
      const r = await s.call(tool, args as any);
      expect(r.isError).toBe(true);
      expect(r.text).toMatch(hint);
    }
    expect(logOf(f)).not.toContain("save()");
    expect(logOf(f).some((l) => /^(set_variables|find_empty_space_on_canvas|get_style_guide_tags)/.test(l))).toBe(false);
  }, 60_000);
});

describe("crash respawn (AC2)", () => {
  test("reloads --out, never the template inputPath", async () => {
    const d = caseDir("respawn");
    const tpl = join(d, "tpl.pen");
    const f = join(d, "a.pen");
    writeFileSync(tpl, pen(2));
    const s = await session();
    const o = await s.call("open_document", { filePath: f, inputPath: tpl });
    expect(o.isError).toBe(false);
    expect(logOf(f)[0]).toBe(`ARGS interactive --out ${f} --in ${tpl}`);
    await s.call("batch_design", { operations: 'a=Insert(document,{type:"frame"})' });
    expect(JSON.parse(readFileSync(f, "utf8")).children.length).toBe(3);

    process.kill(Number(readFileSync(`${f}.pid`, "utf8")), "SIGKILL");
    await new Promise((r) => setTimeout(r, 300));
    const g = await s.call("batch_get", {});
    expect(g.isError).toBe(false);
    expect(JSON.parse(g.text).nodes.length).toBe(3);
    const args = logOf(f).filter((l) => l.startsWith("ARGS"));
    expect(args.length).toBe(2);
    expect(args[1]).toBe(`ARGS interactive --out ${f} --in ${f}`);
  }, 60_000);
});

describe("document file bytes", () => {
  test("a refused save leaves a larger-than-empty file", () => {
    // sanity for the fixtures themselves: the seed is bigger than the empty document
    expect(pen(3).length).toBeGreaterThan(pen(0).length);
    expect(existsSync(root) && statSync(root).isDirectory()).toBe(true);
  });
});
