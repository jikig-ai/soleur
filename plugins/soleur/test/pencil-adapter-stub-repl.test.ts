import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync, statSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { installAdapter, connectAdapter } from "./lib/pencil-adapter-roundtrip.mjs";
import { REPL_SURFACE } from "../skills/pencil-setup/scripts/pencil-repl-surface.mjs";
import { symlinkSync } from "node:fs";

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
    expect(next.text).toMatch(/Next step: open_document a different \.pen path/);
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
      ["set_variables", { variables: { a: "#fff" } }, /SetVariables\(.*include_schema: true/],
      ["find_empty_space_on_canvas", { direction: "right", height: 1, width: 1, padding: 1 }, /FindEmptySpace\(.*include_schema: true/],
      ["get_style_guide_tags", {}, /get_guidelines\(\) with no arguments/],
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

  test("a crash before the first save respawns from the template, not an empty document", async () => {
    const d = caseDir("respawn-before-save");
    const tpl = join(d, "tpl.pen");
    const f = join(d, "a.pen");
    writeFileSync(tpl, pen(2));
    const s = await session();
    expect((await s.call("open_document", { filePath: f, inputPath: tpl })).isError).toBe(false);
    expect(existsSync(f)).toBe(false); // nothing saved yet
    process.kill(Number(readFileSync(`${f}.pid`, "utf8")), "SIGKILL");
    await new Promise((r) => setTimeout(r, 300));
    const g = await s.call("batch_get", {});
    expect(g.isError).toBe(false);
    expect(JSON.parse(g.text).nodes.length).toBe(2);
    const args = logOf(f).filter((l) => l.startsWith("ARGS"));
    expect(args[1]).toBe(`ARGS interactive --out ${f} --in ${tpl}`);
  }, 60_000);
});

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const setFlags = (f: string, flags: object) => writeFileSync(`${f}.flags`, JSON.stringify(flags));
const crash = async (f: string) => {
  process.kill(Number(readFileSync(`${f}.pid`, "utf8")), "SIGKILL");
  await sleep(300);
};

describe("process lifecycle (review round)", () => {
  test("a failed respawn keeps the target: later edits error, then recover on the SAME file", async () => {
    const f = join(caseDir("failed-respawn"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    setFlags(f, { exitOnStart: true });
    await crash(f);
    const a = await s.call("batch_get", {});
    expect(a.isError).toBe(true);
    expect(a.text).toMatch(/exited before it was ready/);
    // the old defect: the next call fell through to a hidden scratch document and reported success
    const b = await s.call("batch_design", { operations: 'x=Insert(document,{type:"frame"})' });
    expect(b.isError).toBe(true);
    setFlags(f, {});
    const c = await s.call("batch_get", {});
    expect(c.isError).toBe(false);
    expect(JSON.parse(c.text).nodes.length).toBe(3);
    expect(JSON.parse(readFileSync(f, "utf8")).children.length).toBe(3);
  }, 60_000);

  test("a slow-dying old child does not fail the next open_document", async () => {
    const d = caseDir("slow-exit");
    const a = join(d, "a.pen");
    const b = join(d, "b.pen");
    setFlags(a, { slowExitMs: 800 });
    const s = await session();
    expect((await s.call("open_document", { filePath: a })).isError).toBe(false);
    setFlags(a, {});
    setFlags(b, { startDelayMs: 1500 }); // the NEW child is slow too, so the old child's late exit lands mid-wait
    const o = await s.call("open_document", { filePath: b });
    expect(o.isError).toBe(false);
    expect((await s.call("batch_get", {})).isError).toBe(false);
  }, 60_000);

  test("two parallel first calls both succeed (the spawn is serialized in the queue)", async () => {
    const s = await session();
    const [x, y] = await Promise.all([
      s.call("get_editor_state", { include_schema: false }),
      s.call("get_variables", {}),
    ]);
    expect(x.isError).toBe(false);
    expect(y.isError).toBe(false);
  }, 60_000);

  test("a call parallel to open_document never spawns a second child", async () => {
    const d = caseDir("parallel-open");
    const a = join(d, "a.pen");
    const b = join(d, "b.pen");
    const s = await session();
    await s.call("open_document", { filePath: a });
    const [o, g] = await Promise.all([
      s.call("open_document", { filePath: b }),
      s.call("batch_get", {}),
    ]);
    expect(o.isError).toBe(false);
    expect(g.isError).toBe(false);
    expect(logOf(a).filter((l) => l.startsWith("ARGS")).length).toBe(1);
    expect(logOf(b).filter((l) => l.startsWith("ARGS")).length).toBe(1);
  }, 60_000);

  test("an edit and its save are one job: a queued open_document cannot land between them", async () => {
    const d = caseDir("edit-save-atomic");
    const a = join(d, "a.pen");
    const b = join(d, "b.pen");
    const s = await session();
    await s.call("open_document", { filePath: a });
    const [edit, open] = await Promise.all([
      s.call("batch_design", { operations: 'x=Insert(document,{type:"frame"})' }),
      s.call("open_document", { filePath: b }),
    ]);
    expect(edit.isError).toBe(false);
    expect(open.isError).toBe(false);
    // the edit was persisted to a.pen BEFORE the document switched
    expect(JSON.parse(readFileSync(a, "utf8")).children.length).toBe(1);
  }, 60_000);
});

describe("engine errors and large documents (review round)", () => {
  test("a rejected edit never saves, and a failing save is an error on both paths", async () => {
    const f = join(caseDir("engine-errors"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    const bad = await s.call("batch_design", { operations: "BADOP" });
    expect(bad.isError).toBe(true);
    expect(logOf(f)).not.toContain("save()");
    setFlags(f, { failSave: true });
    const edit = await s.call("batch_design", { operations: 'x=Insert(document,{type:"frame"})' });
    expect(edit.isError).toBe(true);
    expect(edit.text).toMatch(/save failed/i);
    const explicit = await s.call("save");
    expect(explicit.isError).toBe(true);
    expect(explicit.text).toMatch(/disk full/);
  }, 60_000);

  test("a memory probe that is not a node list refuses and says why (not 'never loaded')", async () => {
    const f = join(caseDir("junk-probe"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { junkBatchGet: true });
    const before = readFileSync(f, "utf8");
    const r = await s.call("save");
    expect(r.isError).toBe(true);
    expect(r.text).toContain("REFUSED save:");
    expect(r.text).toMatch(/could not be read/);
    expect(r.text).not.toMatch(/never loaded/i);
    expect(readFileSync(f, "utf8")).toBe(before);
    expect(logOf(f)).not.toContain("save()");
  }, 60_000);

  test("a design whose batch_get() exceeds 64 KiB still opens and saves", async () => {
    const f = join(caseDir("big-design"), "a.pen");
    writeFileSync(f, pen(3));
    setFlags(f, { bigBatchGet: true });
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(false);
    expect(o.text).toMatch(/3 top-level node/);
    const r = await s.call("batch_design", { operations: 'x=Insert(document,{type:"frame"})' });
    expect(r.isError).toBe(false);
    expect(JSON.parse(readFileSync(f, "utf8")).children.length).toBe(4);
  }, 60_000);

  test("export_nodes never reaches the engine's save", async () => {
    const d = caseDir("export");
    const f = join(d, "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    const r = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: d });
    expect(r.isError).toBe(false);
    expect(logOf(f).some((l) => l.startsWith("export_nodes("))).toBe(true);
    expect(logOf(f)).not.toContain("save()");
  }, 60_000);
});

describe("targets the sentinel must not let through (review round)", () => {
  test("a non-blank file that is not a .pen is refused at open and never overwritten", async () => {
    const f = join(caseDir("garbage"), "a.pen");
    writeFileSync(f, "# notes, not a pen file\n");
    setFlags(f, { invalidAsEmpty: true }); // the real engine loads such a file as an EMPTY document
    const before = readFileSync(f, "utf8");
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/not a recognizable \.pen/);
    expect(o.text).toMatch(/Next step:/);
    expect(readFileSync(f, "utf8")).toBe(before);
    expect(logOf(f)).not.toContain("save()");
  }, 60_000);

  test("a file the CLI refuses to load fails fast with the CLI's own message", async () => {
    const f = join(caseDir("cli-exit"), "a.pen");
    writeFileSync(f, "{not json");
    const s = await session();
    const t0 = Date.now();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/exited before it was ready/);
    expect(o.text).toMatch(/not a valid \.pen/);
    expect(Date.now() - t0).toBeLessThan(10_000);
    expect(readFileSync(f, "utf8")).toBe("{not json");
  }, 60_000);

  test("a corrupted file written behind the session's back is refused on save", async () => {
    const f = join(caseDir("corrupt-after-open"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f }); // new document
    writeFileSync(f, "<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> x\n");
    const before = readFileSync(f, "utf8");
    const r = await s.call("batch_design", { operations: 'x=Insert(document,{type:"frame"})' });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/not a recognizable \.pen/);
    expect(readFileSync(f, "utf8")).toBe(before);
  }, 60_000);

  test("open-failed blocks EVERY tool, and a successful open_document clears it", async () => {
    const d = caseDir("open-failed-recovery");
    const bad = join(d, "bad.pen");
    const good = join(d, "good.pen");
    writeFileSync(bad, "# not a pen\n");
    setFlags(bad, { invalidAsEmpty: true });
    const s = await session();
    expect((await s.call("open_document", { filePath: bad })).isError).toBe(true);
    for (const [tool, args] of [
      ["save", {}],
      ["batch_get", {}],
      ["get_variables", {}],
      ["get_editor_state", { include_schema: false }],
      ["batch_design", { operations: 'x=Insert(document,{type:"frame"})' }],
    ] as const) {
      const r = await s.call(tool, args as any);
      expect(r.isError).toBe(true);
      expect(r.text).toMatch(/open failed/);
    }
    const ok = await s.call("open_document", { filePath: good });
    expect(ok.isError).toBe(false);
    expect((await s.call("batch_get", {})).isError).toBe(false);
    expect((await s.call("save")).isError).toBe(false);
  }, 60_000);

  test("a template cannot replace an existing document, and the live session is untouched", async () => {
    const d = caseDir("template-over-existing");
    const live = join(d, "live.pen");
    const existing = join(d, "existing.pen");
    const tpl = join(d, "tpl.pen");
    writeFileSync(existing, pen(3));
    writeFileSync(tpl, pen(2));
    const before = readFileSync(existing, "utf8");
    const s = await session();
    await s.call("open_document", { filePath: live });
    const r = await s.call("open_document", { filePath: existing, inputPath: tpl });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/Refusing to open/);
    expect(readFileSync(existing, "utf8")).toBe(before);
    expect((await s.call("batch_get", {})).isError).toBe(false); // still on live.pen
    expect(logOf(live).filter((l) => l.startsWith("ARGS")).length).toBe(1);
  }, 60_000);

  test("a template whose own content will not load is an open failure, not a silent empty document", async () => {
    const d = caseDir("bad-template");
    const f = join(d, "new.pen");
    const tpl = join(d, "tpl.pen");
    writeFileSync(tpl, "{not json");
    setFlags(f, { invalidAsEmpty: true });
    const s = await session();
    const r = await s.call("open_document", { filePath: f, inputPath: tpl });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/not a recognizable \.pen/);
  }, 60_000);

  test("only plain .pen files: a wrong extension or a symlink is refused without touching the session", async () => {
    const d = caseDir("paths");
    const real = join(d, "real.pen");
    const link = join(d, "link.pen");
    writeFileSync(real, pen(3));
    symlinkSync(real, link);
    const live = join(d, "live.pen");
    const s = await session();
    await s.call("open_document", { filePath: live });
    const notes = await s.call("open_document", { filePath: join(d, "notes.md") });
    expect(notes.isError).toBe(true);
    expect(notes.text).toMatch(/must be a \.pen file/);
    const l = await s.call("open_document", { filePath: link });
    expect(l.isError).toBe(true);
    expect(l.text).toMatch(/symlink/);
    expect((await s.call("batch_get", {})).isError).toBe(false);
  }, 60_000);
});

describe("registered tools (review round)", () => {
  test("the exact tool set is registered, and no schema accepts a key the engine would drop", async () => {
    const s = await session();
    const tools = await s.listTools();
    expect(tools.map((t: any) => t.name).sort()).toEqual(
      [
        "batch_design",
        "batch_get",
        "export_nodes",
        "find_empty_space_on_canvas",
        "get_editor_state",
        "get_guidelines",
        "get_screenshot",
        "get_style_guide",
        "get_style_guide_tags",
        "get_variables",
        "open_document",
        "replace_all_matching_properties",
        "save",
        "search_all_unique_properties",
        "set_variables",
        "snapshot_layout",
      ].sort()
    );
    for (const t of tools as any[]) {
      if (!(t.name in REPL_SURFACE) || t.name === "batch_design" || t.name === "save") continue;
      const keys = Object.keys(t.inputSchema?.properties ?? {});
      for (const k of keys) {
        expect((REPL_SURFACE as Record<string, string[]>)[t.name]).toContain(k);
      }
    }
    const bd = (tools as any[]).find((t) => t.name === "batch_design");
    expect(Object.keys(bd.inputSchema.properties)).toEqual(["operations"]);
    expect(bd.description).toMatch(/get_editor_state/);
  }, 60_000);

  test("every removed tool answers with its replacement hint, whatever arguments the caller sends", async () => {
    const f = join(caseDir("removed-all"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    for (const name of [
      "set_variables",
      "find_empty_space_on_canvas",
      "get_style_guide",
      "get_style_guide_tags",
      "search_all_unique_properties",
      "replace_all_matching_properties",
    ]) {
      const r = await s.call(name, { whatever: 1, parents: ["x"] });
      expect(r.isError).toBe(true);
      expect(r.text).toMatch(/Unknown tool:/);
      expect(r.text).toMatch(/\[adapter hint\]/);
    }
    expect(logOf(f)).not.toContain("save()");
  }, 60_000);
});

describe("credential redaction (review round)", () => {
  test("an engine reply that echoes the key never reaches the tool result", async () => {
    const f = join(caseDir("echo-key"), "a.pen");
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    writeFileSync(`${f}.flags`, JSON.stringify({ echoKey: true }));
    const r = await s.call("batch_design", { operations: 'a=Insert(document,{type:"frame"})' });
    expect(r.isError).toBe(true);
    expect(r.text).toContain("<redacted>");
    expect(r.text).not.toContain("stub-key");
    expect(s.stderr()).not.toContain("stub-key");
  }, 60_000);
});

describe("binary resolution (review round)", () => {
  test("a relative PENCIL_BINARY is refused", async () => {
    const d = caseDir("relative-binary");
    const s = await connectAdapter({ installDir, binary: "relative/pencil.js", cwd: d });
    sessions.push(s);
    const r = await s.call("open_document", { filePath: join(d, "a.pen") });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/PENCIL_BINARY must be an absolute path/);
  }, 60_000);

  test("with no pencil on PATH the adapter errors; it never runs ./pencil.js from the working directory", async () => {
    const d = caseDir("no-binary");
    const project = join(d, "project");
    const home = join(d, "home");
    mkdirSync(project, { recursive: true });
    mkdirSync(home, { recursive: true });
    const marker = join(d, "EXECUTED");
    writeFileSync(join(project, "pencil.js"), `require("fs").writeFileSync(${JSON.stringify(marker)}, "ran");`);
    const s = await connectAdapter({
      installDir,
      binary: "", // no PENCIL_BINARY: the real resolution path
      cwd: project,
      nodeBin: Bun.which("node") ?? "node",
      extraEnv: { HOME: home, PATH: "/usr/bin:/bin" },
    });
    sessions.push(s);
    const r = await s.call("open_document", { filePath: join(d, "a.pen") });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/pencil CLI not found/);
    expect(existsSync(marker)).toBe(false);
  }, 60_000);
});
