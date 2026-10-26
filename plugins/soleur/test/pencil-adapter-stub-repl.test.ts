import { describe, test, expect, beforeAll, afterAll, setDefaultTimeout } from "bun:test";
import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  statSync,
  symlinkSync,
  utimesSync,
  writeFileSync,
} from "node:fs";
import { spawnSync } from "node:child_process";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { tmpdir } from "node:os";
import {
  installAdapter,
  connectAdapter,
  killAndWait,
  stubPid,
  sideFile,
  taggedStub,
} from "./lib/pencil-adapter-roundtrip.mjs";
import { buildPenTree } from "./lib/pen-identity-tree.mjs";
import { REPL_SURFACE } from "../skills/pencil-setup/scripts/pencil-repl-surface.mjs";
import { LIVE_TOOL_NAMES, REMOVED_TOOL_NAMES } from "../skills/pencil-setup/scripts/pencil-error-enrichment.mjs";

// #11143 / #11156 / #11168 integration: the INSTALLED adapter copy over real MCP stdio
// against the stub REPL (fixtures/pencil-stub-repl.mjs), which reproduces the measured
// @pen.dev/cli 0.3.13 shapes (every failure on STDERR, coloured prompt, `Saved <path>`).
// The stub is pinned to a captured real transcript by pencil-stub-transcript.test.ts and
// engine-contract-probe.sh is the only test that touches the real engine. An unreachable
// npm registry fails this suite, it never skips: a green run must mean the installed copy
// executed.

setDefaultTimeout(60_000);

const STUB = resolve(import.meta.dir, "fixtures/pencil-stub-repl.mjs");
const IDENTITY_TSV = resolve(import.meta.dir, "fixtures/pen-identity-cases.tsv");
const root = realpathSync(mkdtempSync(join(tmpdir(), "pencil-stub-it-")));
let installDir = "";
let BIN = ""; // an untagged, mode-0755 wrapper around the stub (the adapter trusts PENCIL_BINARY only for a safe regular file)
const sessions: Array<{ close: () => Promise<void> }> = [];

const pen = (n: number, tag = "seed") =>
  JSON.stringify({ version: "2.21", children: Array.from({ length: n }, (_, i) => ({ id: `${tag}${i}`, type: "frame" })) });
const logOf = (file: string, tag = "") => {
  const p = sideFile(file, "log", tag);
  return existsSync(p) ? readFileSync(p, "utf8").split("\n").filter(Boolean) : [];
};
const setFlags = (f: string, flags: object, tag = "") => writeFileSync(sideFile(f, "flags", tag), JSON.stringify(flags));
const saves = (f: string, tag = "") => logOf(f, tag).filter((l) => l === "save()").length;
const isCount = (l: string) => l.startsWith("COUNT ");
const caseDir = (name: string) => {
  const d = join(root, name);
  mkdirSync(d, { recursive: true });
  return d;
};
const ADD = 'x=Insert(document,{type:"frame",width:10,height:10})';
const read = (f: string) => readFileSync(f, "utf8");
const children = (f: string) => JSON.parse(read(f)).children.length;

type Session = Awaited<ReturnType<typeof connectAdapter>>;
async function session(opts: { binary?: string; keys?: Record<string, string>; cwd?: string; extraEnv?: Record<string, string>; nodeBin?: string } = {}): Promise<Session> {
  const s = await connectAdapter({ installDir, binary: opts.binary ?? BIN, keys: opts.keys, cwd: opts.cwd, extraEnv: opts.extraEnv, nodeBin: opts.nodeBin });
  sessions.push(s);
  return s;
}
// a session whose stub writes its side channels under a tag (two sessions on one file)
async function taggedSession(dir: string, tag: string) {
  return session({ binary: taggedStub(STUB, tag, dir) });
}

beforeAll(() => {
  installDir = installAdapter(join(root, "install"));
  BIN = taggedStub(STUB, "", root);
}, 240_000);

afterAll(async () => {
  await Promise.all(sessions.map((s) => s.close().catch(() => {})));
  rmSync(root, { recursive: true, force: true });
}, 60_000);

describe("batch_design -> execute", () => {
  test("operations arrive as execute({ input }) with the alias preamble, never as a batch_design( line", async () => {
    const f = join(caseDir("key"), "a.pen");
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    const r = await s.call("batch_design", { operations: 'a=I(document,{type:"frame",width:10,height:10})' });
    expect(r.isError).toBe(false);
    const lines = logOf(f);
    const exec = lines.filter((l) => l.startsWith("execute({ input: ") && !l.includes("TOPLEVEL_COUNT"));
    expect(exec.length).toBe(1);
    expect(exec[0]).toContain("var I=Insert,U=Update");
    expect(exec[0]).not.toContain("operations");
    expect(lines.some((l) => l.startsWith("batch_design("))).toBe(false);
    expect(lines.some((l) => l.startsWith("REJECTED"))).toBe(false);
    expect(children(f)).toBe(1);
    // one line tells parallel agents which file the call hit
    expect(r.text.split("\n").at(-1)).toBe(`Document: ${f}`);
  });

  test("an `## issues detected:` block passes through: not an error, and the save still ran", async () => {
    const f = join(caseDir("issues"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    const r = await s.call("batch_design", { operations: 'box=I(document,{type:"frame",name:"Box"})' });
    expect(r.isError).toBe(false);
    expect(r.text).toContain("## issues detected:");
    expect(saves(f)).toBe(1);
    expect(children(f)).toBe(1);
  });

  test("a rejected edit is an error, never saves, and the engine's retry advice is rewritten", async () => {
    const f = join(caseDir("rejected"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    const bad = await s.call("batch_design", { operations: "BADOP" });
    expect(bad.isError).toBe(true);
    expect(bad.text).toMatch(/re-send the corrected operations with batch_design/);
    expect(bad.text).not.toMatch(/`edits` parameter|`editId`/);
    expect(saves(f)).toBe(0);
  });

  test("a node name that looks like the prompt, and a prompt-shaped read_skill page, do not desynchronise the REPL", async () => {
    const f = join(caseDir("framing"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    const named = await s.call("batch_design", { operations: 'h=I(document,{type:"frame",name:"Hero\\npen > x",width:10,height:10})' });
    expect(named.isError).toBe(false);
    expect(named.text).toContain("pen > x");
    const skill = await s.call("read_skill", { path: "guide/table.md" });
    expect(skill.isError).toBe(false);
    expect(skill.text).toContain("this line starts with the prompt text");
    const sv = await s.call("save");
    expect(sv.isError).toBe(false);
    expect(sv.text).toMatch(/^Saved /);
    expect(children(f)).toBe(1);
    expect(s.stderr()).not.toMatch(/desync/i);
  });
});

describe("open_document on an existing file", () => {
  test("keeps the existing nodes through edit and save, and reports the count", async () => {
    const f = join(caseDir("open"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(false);
    expect(o.text).toMatch(/Opened .* \(3 top-level node\(s\) loaded\)/);
    expect(logOf(f)[0]).toBe(`ARGS interactive --out ${f} --in ${f}`);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect((await s.call("save")).isError).toBe(false);
    expect(children(f)).toBe(4);
  });

  test("a missing file opens a new empty document without --in", async () => {
    const f = join(caseDir("open-new"), "a.pen");
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    expect(logOf(f)[0]).toBe(`ARGS interactive --out ${f}`);
  });

  test("an explicit missing inputPath fails fast with isError", async () => {
    const f = join(caseDir("open-missing-in"), "a.pen");
    const s = await session();
    const t0 = Date.now();
    const o = await s.call("open_document", { filePath: f, inputPath: join(root, "nope.pen") });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/not found/i);
    expect(Date.now() - t0).toBeLessThan(5_000);
  });

  test("a non-empty file that loads empty is an error and the adapter enters the open-failed state", async () => {
    const f = join(caseDir("open-empty-load"), "a.pen");
    writeFileSync(f, pen(3));
    setFlags(f, { loadEmpty: true });
    const before = read(f);
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/open failed/i);
    const next = await s.call("get_editor_state", {});
    expect(next.isError).toBe(true);
    expect(next.text).toMatch(/open failed/i);
    expect(next.text).toMatch(/Next step: open_document a different \.pen path/);
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
  });

  test("a count reply that cannot be read (forged nonce) over a non-empty file fails the open, it is not read as empty-but-fine", async () => {
    const f = join(caseDir("open-forged"), "a.pen");
    writeFileSync(f, pen(3));
    setFlags(f, { countForgery: "wrongNonce" });
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/unreadable/);
    expect(saves(f)).toBe(0);
  });
});

describe("empty-overwrite sentinel (#11143, unchanged predicate)", () => {
  async function emptyMemoryOverNonEmptyDisk(name: string) {
    const f = join(caseDir(name), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f }); // new path, empty document
    writeFileSync(f, pen(3)); // the file gains content behind the session's back
    return { f, s, before: read(f) };
  }

  test("explicit save refuses, bytes unchanged, no save reached the stub, the probe ran", async () => {
    const { f, s, before } = await emptyMemoryOverNonEmptyDisk("refuse-save");
    const r = await s.call("save");
    expect(r.isError).toBe(true);
    expect(r.text).toContain("REFUSED save:");
    expect(r.text).toContain(f);
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
    expect(logOf(f).some(isCount)).toBe(true);
    expect(s.stderr()).toMatch(/\[pencil-adapter\] REFUSED save: \[reason=empty\] .*via=save/);
  });

  test("auto-save after a no-op edit refuses with the in-memory-not-persisted note", async () => {
    const { f, s, before } = await emptyMemoryOverNonEmptyDisk("refuse-auto");
    const r = await s.call("batch_design", { operations: 'Print("noop")' });
    expect(r.isError).toBe(true);
    expect(r.text).toContain("REFUSED save:");
    expect(r.text).toMatch(/in memory but not persisted/i);
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
    expect(s.stderr()).toMatch(/REFUSED save: \[reason=empty\] .*via=auto-save/);
  });

  test("deleting every top-level node stays refused, with the open-a-new-path text", async () => {
    const f = join(caseDir("delete-all"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    const before = read(f);
    const r = await s.call("batch_design", { operations: 'Delete(["seed0","seed1"])' });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/in-memory document has 0/);
    expect(r.text).toMatch(/open_document a new file path/);
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
  });

  test("a queued command cannot land between the memory probe and the save", async () => {
    const f = join(caseDir("interleave"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    const [sv, bd] = await Promise.all([s.call("save"), s.call("batch_design", { operations: ADD })]);
    expect(sv.isError).toBe(false);
    expect(bd.isError).toBe(false);
    const lines = logOf(f).filter((l) => !/^(ARGS|ENVKEYS|CWD)/.test(l));
    lines.forEach((l, i) => {
      if (l === "save()") expect(isCount(lines[i - 1])).toBe(true);
    });
    expect(lines.filter((l) => l === "save()").length).toBe(2);
  });

  test("a collapsed (empty) target is saved over: nothing to protect", async () => {
    const f = join(caseDir("collapsed"), "a.pen");
    writeFileSync(f, pen(0));
    const s = await session();
    await s.call("open_document", { filePath: f });
    await s.call("batch_design", { operations: ADD });
    expect(children(f)).toBe(1);
  });

  test("a count reply that is forged, duplicated or missing refuses the save (the nonce is compared)", async () => {
    for (const forgery of ["wrongNonce", "duplicate", "missing"]) {
      const f = join(caseDir(`forgery-${forgery}`), "a.pen");
      writeFileSync(f, pen(3));
      const s = await session();
      await s.call("open_document", { filePath: f });
      const before = read(f);
      setFlags(f, { countForgery: forgery });
      const r = await s.call("batch_design", { operations: ADD }); // memory 4 > 0: a TRUE count would allow it
      expect(r.isError).toBe(true);
      expect(r.text).toContain("REFUSED save:");
      expect(r.text).toMatch(/could not be read/);
      expect(read(f)).toBe(before);
      expect(saves(f)).toBe(0);
    }
  });
});

describe("registered tools", () => {
  test("exactly 8 live tools and 9 removed stubs; no schema accepts a key the engine would drop", async () => {
    const s = await session();
    const tools = await s.listTools();
    const names = tools.map((t: any) => t.name).sort();
    expect(names).toEqual([...LIVE_TOOL_NAMES, ...REMOVED_TOOL_NAMES].sort());
    expect(LIVE_TOOL_NAMES.length).toBe(8);
    expect(REMOVED_TOOL_NAMES.length).toBe(9);
    for (const t of tools as any[]) {
      if (!(t.name in REPL_SURFACE)) continue; // save, read_skill share a REPL name
      const keys = Object.keys(t.inputSchema?.properties ?? {});
      for (const k of keys) expect((REPL_SURFACE as Record<string, string[]>)[t.name]).toContain(k);
    }
    const bd = (tools as any[]).find((t) => t.name === "batch_design");
    expect(Object.keys(bd.inputSchema.properties)).toEqual(["operations"]);
    expect(bd.description).toMatch(/read_skill/);
    const state = (tools as any[]).find((t) => t.name === "get_editor_state");
    expect(state.description).toMatch(/include_schema/);
  });

  test("every removed tool answers with a hint naming a live tool, whatever arguments the caller sends, and never saves", async () => {
    const f = join(caseDir("removed-all"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    for (const name of REMOVED_TOOL_NAMES) {
      const r = await s.call(name, { whatever: 1, parents: ["x"] });
      expect(r.isError).toBe(true);
      expect(r.text).toMatch(/Unknown tool:/);
      const hint = r.text.split("[adapter hint]")[1] ?? "";
      expect(hint.length).toBeGreaterThan(20);
      expect(LIVE_TOOL_NAMES.some((t) => hint.includes(t))).toBe(true);
    }
    expect(saves(f)).toBe(0);
    expect(logOf(f).some((l) => REMOVED_TOOL_NAMES.some((n) => l.startsWith(`${n}(`)))).toBe(false);
  });

  test("get_editor_state, get_variables and read_skill read without saving", async () => {
    const f = join(caseDir("readers"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    const state = await s.call("get_editor_state", { include_schema: true });
    expect(state.isError).toBe(false);
    expect(state.text).toContain("# Current App State");
    expect(state.text).toContain("seed1");
    const vars = await s.call("get_variables", {});
    expect(vars.isError).toBe(false);
    expect(vars.text).toContain('{"variables":{}}');
    const index = await s.call("read_skill", {});
    expect(index.isError).toBe(false);
    expect(index.text).toContain("guide/table.md");
    const bad = await s.call("read_skill", { path: "../../etc/passwd" });
    expect(bad.isError).toBe(true);
    expect(bad.text).toMatch(/read_skill path must match/);
    const missing = await s.call("read_skill", { path: "nope.md" });
    expect(missing.isError).toBe(true);
    expect(saves(f)).toBe(0);
    expect(logOf(f).some((l) => l.startsWith("REJECTED"))).toBe(false);
  });

  test("two parallel first calls both succeed (the spawn is serialized in the queue)", async () => {
    const s = await session();
    const [x, y] = await Promise.all([s.call("get_editor_state", { include_schema: false }), s.call("get_variables", {})]);
    expect(x.isError).toBe(false);
    expect(y.isError).toBe(false);
  });
});

describe("crash respawn", () => {
  test("reloads --out, never the template inputPath", async () => {
    const d = caseDir("respawn");
    const tpl = join(d, "tpl.pen");
    const f = join(d, "a.pen");
    writeFileSync(tpl, pen(2, "tpl"));
    const s = await session();
    expect((await s.call("open_document", { filePath: f, inputPath: tpl })).isError).toBe(false);
    expect(logOf(f)[0]).toBe(`ARGS interactive --out ${f} --in ${tpl}`);
    await s.call("batch_design", { operations: ADD });
    expect(children(f)).toBe(3);

    await killAndWait(stubPid(f));
    const g = await s.call("get_editor_state", {});
    expect(g.isError).toBe(false);
    expect(g.text).toContain("tpl1");
    expect(g.text).toMatch(/`[A-Za-z0-9]{5}` \(frame\)/); // the node added before the crash was reloaded from --out
    const args = logOf(f).filter((l) => l.startsWith("ARGS"));
    expect(args.length).toBe(2);
    expect(args[1]).toBe(`ARGS interactive --out ${f} --in ${f}`);
    // an ordinary respawn recaptures the baseline: the next edit saves
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(4);
  });

  test("a crash before the first save respawns from the template, not an empty document", async () => {
    const d = caseDir("respawn-before-save");
    const tpl = join(d, "tpl.pen");
    const f = join(d, "a.pen");
    writeFileSync(tpl, pen(2, "tpl"));
    const s = await session();
    expect((await s.call("open_document", { filePath: f, inputPath: tpl })).isError).toBe(false);
    expect(existsSync(f)).toBe(false);
    await killAndWait(stubPid(f));
    const g = await s.call("get_editor_state", {});
    expect(g.isError).toBe(false);
    expect(g.text).toContain("tpl1");
    expect(logOf(f).filter((l) => l.startsWith("ARGS"))[1]).toBe(`ARGS interactive --out ${f} --in ${tpl}`);
  });

  test("a failed respawn keeps the target: later edits error, then recover on the SAME file", async () => {
    const f = join(caseDir("failed-respawn"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    setFlags(f, { exitOnStart: true });
    await killAndWait(stubPid(f));
    const a = await s.call("get_editor_state", {});
    expect(a.isError).toBe(true);
    expect(a.text).toMatch(/exited before it was ready/);
    // the old defect: the next call fell through to a hidden scratch document and reported success
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(true);
    setFlags(f, {});
    const c = await s.call("get_editor_state", {});
    expect(c.isError).toBe(false);
    expect(c.text).toContain("seed2");
    expect(children(f)).toBe(3);
  });

  test("a slow-dying old child does not fail the next open_document", async () => {
    const d = caseDir("slow-exit");
    const a = join(d, "a.pen");
    const b = join(d, "b.pen");
    setFlags(a, { slowExitMs: 800 });
    const s = await session();
    expect((await s.call("open_document", { filePath: a })).isError).toBe(false);
    setFlags(a, {});
    setFlags(b, { startDelayMs: 1500 }); // the NEW child is slow too, so the old child's late exit lands mid-wait
    expect((await s.call("open_document", { filePath: b })).isError).toBe(false);
    expect((await s.call("get_editor_state", {})).isError).toBe(false);
  });

  test("a call parallel to open_document never spawns a second child", async () => {
    const d = caseDir("parallel-open");
    const a = join(d, "a.pen");
    const b = join(d, "b.pen");
    const s = await session();
    await s.call("open_document", { filePath: a });
    const [o, g] = await Promise.all([s.call("open_document", { filePath: b }), s.call("get_editor_state", {})]);
    expect(o.isError).toBe(false);
    expect(g.isError).toBe(false);
    expect(logOf(a).filter((l) => l.startsWith("ARGS")).length).toBe(1);
    expect(logOf(b).filter((l) => l.startsWith("ARGS")).length).toBe(1);
  });

  test("an edit and its save are one job: a queued open_document cannot land between them", async () => {
    const d = caseDir("edit-save-atomic");
    const a = join(d, "a.pen");
    const b = join(d, "b.pen");
    const s = await session();
    await s.call("open_document", { filePath: a });
    const [edit, open] = await Promise.all([s.call("batch_design", { operations: ADD }), s.call("open_document", { filePath: b })]);
    expect(edit.isError).toBe(false);
    expect(open.isError).toBe(false);
    expect(children(a)).toBe(1);
  });
});

describe("engine errors and large documents", () => {
  test("a design whose edit reply exceeds 64 KiB still opens, saves and reports", async () => {
    const f = join(caseDir("big-design"), "a.pen");
    writeFileSync(f, pen(3));
    setFlags(f, { bigExecute: true });
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).text).toMatch(/3 top-level node/);
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(false);
    expect(r.text.length).toBeGreaterThan(64 * 1024);
    expect(children(f)).toBe(4);
  });

  test("export_nodes never reaches the engine's save", async () => {
    const d = caseDir("export-nosave");
    const f = join(d, "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    const r = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(d, "out") });
    expect(r.isError).toBe(false);
    expect(logOf(f).some((l) => l.includes("Export("))).toBe(true);
    expect(saves(f)).toBe(0);
  });
});

describe("targets the sentinel must not let through", () => {
  test("a non-blank file that is not a .pen is refused at open and never overwritten", async () => {
    const f = join(caseDir("garbage"), "a.pen");
    writeFileSync(f, "# notes, not a pen file\n");
    setFlags(f, { invalidAsEmpty: true }); // 0.2.9 loaded such a file EMPTY; the sentinel must still hold if a future engine does
    const before = read(f);
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/not a recognizable \.pen/);
    expect(o.text).toMatch(/Next step:/);
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
  });

  test("a file the CLI refuses to load fails fast with the CLI's own message", async () => {
    const f = join(caseDir("cli-exit"), "a.pen");
    writeFileSync(f, "{not json");
    const s = await session();
    const t0 = Date.now();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/exited before it was ready/);
    expect(o.text).toMatch(/Failed to open document/);
    expect(Date.now() - t0).toBeLessThan(10_000);
    expect(read(f)).toBe("{not json");
  });

  test("a corrupted file written behind the session's back is refused on save", async () => {
    const f = join(caseDir("corrupt-after-open"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    writeFileSync(f, "<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> x\n");
    const before = read(f);
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/not a recognizable \.pen/);
    expect(read(f)).toBe(before);
  });

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
      ["get_variables", {}],
      ["get_editor_state", { include_schema: false }],
      ["read_skill", {}],
      ["batch_design", { operations: ADD }],
    ] as const) {
      const r = await s.call(tool, args as any);
      expect(r.isError).toBe(true);
      expect(r.text).toMatch(/open failed/);
    }
    expect((await s.call("open_document", { filePath: good })).isError).toBe(false);
    expect((await s.call("get_editor_state", {})).isError).toBe(false);
    expect((await s.call("save")).isError).toBe(false);
  });

  test("a template cannot replace an existing document, and the live session is untouched", async () => {
    const d = caseDir("template-over-existing");
    const live = join(d, "live.pen");
    const existing = join(d, "existing.pen");
    const tpl = join(d, "tpl.pen");
    writeFileSync(existing, pen(3));
    writeFileSync(tpl, pen(2));
    const before = read(existing);
    const s = await session();
    await s.call("open_document", { filePath: live });
    const r = await s.call("open_document", { filePath: existing, inputPath: tpl });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/Refusing to open/);
    expect(read(existing)).toBe(before);
    expect((await s.call("get_editor_state", {})).isError).toBe(false);
    expect(logOf(live).filter((l) => l.startsWith("ARGS")).length).toBe(1);
  });

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
  });

  test("only plain .pen files: a wrong extension or a symlink is refused without touching the session", async () => {
    const d = caseDir("paths");
    const real = join(d, "real.pen");
    const link = join(d, "link.pen");
    writeFileSync(real, pen(3));
    symlinkSync(real, link);
    const s = await session();
    await s.call("open_document", { filePath: join(d, "live.pen") });
    const notes = await s.call("open_document", { filePath: join(d, "notes.md") });
    expect(notes.isError).toBe(true);
    expect(notes.text).toMatch(/must be a \.pen file/);
    const l = await s.call("open_document", { filePath: link });
    expect(l.isError).toBe(true);
    expect(l.text).toMatch(/symlink/);
    expect((await s.call("get_editor_state", {})).isError).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// #11168: the stale-file save guard.

describe("stale-file save guard (#11168)", () => {
  test("a SMALLER non-empty document over a larger one behind the session is refused, bytes untouched, no save sent", async () => {
    const f = join(caseDir("stale-smaller"), "a.pen");
    writeFileSync(f, pen(5));
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).text).toMatch(/5 top-level/);
    writeFileSync(f, pen(8, "other")); // another session / git / an editor
    const before = read(f);
    const r = await s.call("batch_design", { operations: ADD }); // memory 6, disk 8: decideSave allows it
    expect(r.isError).toBe(true);
    expect(r.text).toContain("REFUSED save:");
    expect(r.text).toMatch(/changed on disk since this session loaded or last saved it/);
    expect(r.text).toMatch(/re-opening discards them/);
    expect(r.text).toMatch(/replay the refused operations in order/);
    expect(r.text).toContain(f);
    // the refused operations are echoed so the replay does not depend on the agent's context
    expect(r.text).toContain("Insert(document");
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
    expect(logOf(f).some(isCount)).toBe(true); // the probe ran before the stale decision
    expect(s.stderr()).toMatch(/\[pencil-adapter\] REFUSED save: \[reason=stale\] \S+ baseline=[0-9a-f]{8} disk=[0-9a-f]{8} via=auto-save/);
    expect(s.stderr()).toContain("refusalPending=true");
    // the explicit save is refused the same way, through the same log helper
    const sv = await s.call("save");
    expect(sv.isError).toBe(true);
    expect(sv.text).toContain("REFUSED save:");
    expect(saves(f)).toBe(0);
    expect(s.stderr()).toMatch(/REFUSED save: \[reason=refusal-pending\] \S+ .*via=save/);
  });

  test("a save that follows the session's own save is allowed (own-save re-baseline), repeatedly", async () => {
    const f = join(caseDir("own-save"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect((await s.call("save")).isError).toBe(false);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(3);
    expect(saves(f)).toBe(4);
  });

  test("RECOVERY: open_document on the changed file, replay the refused edit, and the save is allowed", async () => {
    const f = join(caseDir("recovery"), "a.pen");
    writeFileSync(f, pen(5));
    const s = await session();
    await s.call("open_document", { filePath: f });
    writeFileSync(f, pen(8, "other"));
    // a three-operation script: operation 3 refers to a node operation 1 created
    const script = 'a=I(document,{type:"frame",name:"A",width:20,height:20})\nb=I(a,{type:"frame",name:"B",width:5,height:5})\nU(a,{name:"A2"})';
    const refused = await s.call("batch_design", { operations: script });
    expect(refused.isError).toBe(true);
    expect(refused.text).toContain("U(a,{name:\"A2\"})"); // the whole script is echoed, in order
    expect(refused.text.indexOf("a=I(document")).toBeLessThan(refused.text.indexOf("b=I(a"));
    expect(children(f)).toBe(8);

    const reopened = await s.call("open_document", { filePath: f });
    expect(reopened.isError).toBe(false);
    expect(reopened.text).toMatch(/8 top-level node/);
    expect(s.stderr()).toContain("refusalPending=false");
    const replay = await s.call("batch_design", { operations: script });
    expect(replay.isError).toBe(false);
    expect(children(f)).toBe(9);
    const doc = JSON.parse(read(f));
    const a = doc.children.find((n: any) => n.name === "A2");
    expect(a).toBeDefined();
    expect(a.children.some((n: any) => n.name === "B")).toBe(true);
    expect((await s.call("save")).isError).toBe(false);
  });

  test("a file removed behind the session is refused with its own reason, and not recreated", async () => {
    const f = join(caseDir("removed-behind"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    rmSync(f);
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toContain("REFUSED save:");
    expect(r.text).toMatch(/no longer exists on disk/);
    expect(r.text).not.toMatch(/changed on disk since/);
    expect(existsSync(f)).toBe(false);
    expect(saves(f)).toBe(0);
    expect(s.stderr()).toMatch(/REFUSED save: \[reason=missing\] \S+ baseline=[0-9a-f]{8}/);
  });

  test("a symlink or a FIFO swapped in after open_document is refused with its own reason, never as `missing`", async () => {
    const d = caseDir("swapped");
    const elsewhere = join(d, "elsewhere.pen");
    writeFileSync(elsewhere, pen(2));
    for (const kind of ["symlink", "fifo"]) {
      const f = join(d, `${kind}.pen`);
      writeFileSync(f, pen(2));
      const s = await session();
      await s.call("open_document", { filePath: f });
      rmSync(f);
      if (kind === "symlink") symlinkSync(elsewhere, f);
      else expect(spawnSync("mkfifo", [f]).status).toBe(0);
      const r = await s.call("batch_design", { operations: ADD });
      expect(r.isError).toBe(true);
      expect(r.text).toContain("REFUSED save:");
      expect(r.text).not.toMatch(/no longer exists/);
      expect(r.text).toMatch(/could not be read/);
      expect(saves(f)).toBe(0);
      expect(read(elsewhere)).toBe(pen(2));
    }
  });

  test("an external rewrite with identical content (CRLF, reformatted, mtime an hour ahead) does not refuse", async () => {
    const f = join(caseDir("same-content"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    const doc = JSON.parse(read(f));
    writeFileSync(f, JSON.stringify(doc, null, 2).replace(/\n/g, "\r\n"));
    const future = new Date(Date.now() + 3600_000);
    utimesSync(f, future, future);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(2);
  });

  test("a same-size rewrite that changes one node value is refused", async () => {
    const f = join(caseDir("same-size"), "a.pen");
    writeFileSync(f, pen(3, "seed"));
    const s = await session();
    await s.call("open_document", { filePath: f });
    const swapped = pen(3, "seeX");
    expect(swapped.length).toBe(pen(3, "seed").length);
    writeFileSync(f, swapped);
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/changed on disk since/);
    expect(read(f)).toBe(swapped);
  });

  test("a session that loads from a template onto an absent --out saves cleanly, twice", async () => {
    const d = caseDir("template-clean");
    const tpl = join(d, "tpl.pen");
    const f = join(d, "a.pen");
    writeFileSync(tpl, pen(2, "tpl"));
    const s = await session();
    expect((await s.call("open_document", { filePath: f, inputPath: tpl })).isError).toBe(false);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(4);
  });

  test("STARTUP WINDOW: a rewrite while the engine is still starting refuses the first save", async () => {
    const f = join(caseDir("start-window"), "a.pen");
    writeFileSync(f, pen(2));
    setFlags(f, { rewriteOnStart: JSON.parse(pen(4, "late")) });
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    expect(logOf(f).some((l) => l.startsWith("ARGS"))).toBe(true); // the start (and its rewrite) happened
    const before = read(f);
    expect(JSON.parse(before).children[0].id).toBe("late0");
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/changed on disk since/);
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
  });

  test("PROBE WINDOW: a rewrite that lands while the count probe is in flight refuses, with no save line", async () => {
    const f = join(caseDir("probe-window"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { rewriteOnProbe: JSON.parse(pen(7, "probe")) }); // armed AFTER open: fires on the save's probe
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/changed on disk since/);
    expect(logOf(f).some((l) => isCount(l) && l.includes("memory=4"))).toBe(true);
    expect(saves(f)).toBe(0);
    expect(JSON.parse(read(f)).children.length).toBe(7);
    expect(JSON.parse(read(f)).children[0].id).toBe("probe0");
  });

  test("an unconfirmed save (empty reply, nothing written) makes the baseline unknown: a foreign write is never adopted", async () => {
    const f = join(caseDir("unconfirmed-empty"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { saveReply: "", saveWrites: false });
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/not confirmed/);
    expect(s.stderr()).toContain("save unconfirmed: reply did not match the expected Saved line; baseline=unknown");
    setFlags(f, {});
    writeFileSync(f, pen(5, "foreign"));
    const before = read(f);
    const again = await s.call("batch_design", { operations: ADD });
    expect(again.isError).toBe(true);
    expect(again.text).toMatch(/last save was not confirmed/);
    expect(again.text).not.toMatch(/changed on disk since/);
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(1); // only the unconfirmed one ever reached the engine
    expect(s.stderr()).toMatch(/REFUSED save: \[reason=unknown-baseline\] \S+ cause=unconfirmed-save/);
  });

  test("a `Saved <other path>` reply is an error, and the baseline is not adopted from disk", async () => {
    const f = join(caseDir("unconfirmed-other"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { saveReply: "Saved /somewhere/else.pen" });
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/not confirmed/);
    setFlags(f, {});
    const next = await s.call("save");
    expect(next.isError).toBe(true);
    expect(next.text).toMatch(/last save was not confirmed/);
  });

  test("after one `Save failed:` a retry uses the unconfirmed wording, and a re-open then allows the save", async () => {
    const f = join(caseDir("save-failed"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { failSave: true });
    const failed = await s.call("batch_design", { operations: ADD });
    expect(failed.isError).toBe(true);
    expect(failed.text).toMatch(/Save failed: EACCES/);
    setFlags(f, {});
    const retry = await s.call("save");
    expect(retry.isError).toBe(true);
    expect(retry.text).toMatch(/last save was not confirmed/);
    expect(retry.text).not.toMatch(/changed on disk since/);
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(3);
  });

  test("REFUSAL THEN CRASH RESPAWN: the next save is still refused (restart wording) until open_document succeeds", async () => {
    const f = join(caseDir("refuse-then-crash"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    writeFileSync(f, pen(6, "other"));
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(true);
    const before = read(f);
    await killAndWait(stubPid(f));
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/session restarted/);
    expect(r.text).toMatch(/earlier edits were discarded/);
    expect(s.stderr()).toContain("respawn: refusalPending still armed, baseline not recaptured");
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
    expect(logOf(f).filter((l) => l.startsWith("ARGS")).length).toBe(2); // it did respawn
    // recovery
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(7);
  });

  test("an edit queued after a refusal reads the document with get_editor_state, which is not refused", async () => {
    const f = join(caseDir("read-under-refusal"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    writeFileSync(f, pen(4, "other"));
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(true);
    expect((await s.call("get_editor_state", {})).isError).toBe(false);
  });
});

describe("two sessions on one file (#11168)", () => {
  async function pair(name: string, nodes = 2) {
    const d = caseDir(name);
    const f = join(d, "a.pen");
    writeFileSync(f, pen(nodes));
    const A = await taggedSession(d, "A");
    const B = await taggedSession(d, "B");
    await A.call("open_document", { filePath: f });
    await B.call("open_document", { filePath: f });
    return { f, A, B };
  }

  test("A saves, then B edits and saves: B is refused, the file holds A's work", async () => {
    const { f, A, B } = await pair("two-sessions-1");
    expect((await A.call("batch_design", { operations: ADD })).isError).toBe(false);
    const after = read(f);
    const r = await B.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/changed on disk since/);
    expect(read(f)).toBe(after);
    expect(saves(f, "B")).toBe(0);
  });

  test("B re-opens, replays and saves", async () => {
    const { f, A, B } = await pair("two-sessions-2");
    await A.call("batch_design", { operations: ADD });
    expect((await B.call("batch_design", { operations: ADD })).isError).toBe(true);
    expect((await B.call("open_document", { filePath: f })).text).toMatch(/3 top-level/);
    expect((await B.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(4);
  });

  test("then A's next save is refused: B's save is a change behind A", async () => {
    const { f, A, B } = await pair("two-sessions-3");
    await A.call("batch_design", { operations: ADD });
    await B.call("open_document", { filePath: f });
    await B.call("batch_design", { operations: ADD });
    const after = read(f);
    const r = await A.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/changed on disk since/);
    expect(read(f)).toBe(after);
    expect(saves(f, "A")).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Credential and child isolation.

describe("credential handling", () => {
  const SECRET = ["stub", "credential", "alpha", "bravo", "charlie"].join("-"); // synthesized, long enough to be redacted

  test("the child receives PEN_CLI_KEY only, in a private empty cwd", async () => {
    const f = join(caseDir("env"), "a.pen");
    const s = await session({ keys: { PEN_CLI_KEY: SECRET, PENCIL_CLI_KEY: "other-key-9876543210" } });
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    const envkeys = logOf(f).find((l) => l.startsWith("ENVKEYS"))!;
    expect(envkeys).toContain("PEN_CLI_KEY");
    expect(envkeys).not.toContain("PENCIL_CLI_KEY");
    const cwd = logOf(f).find((l) => l.startsWith("CWD "))!.slice(4);
    expect(cwd).not.toBe(process.cwd());
    expect(cwd).not.toBe(root);
    expect(readdirSync(cwd)).toEqual([]); // private and empty while the session lives
  });

  for (const [label, keys, winner] of [
    ["PEN_CLI_KEY alone", { PEN_CLI_KEY: "key-from-pen-0123456789" }, "key-from-pen-0123456789"],
    ["PENCIL_CLI_KEY alone (deprecated fallback)", { PENCIL_CLI_KEY: "key-from-legacy-0123456789" }, "key-from-legacy-0123456789"],
    ["PEN_CLI_KEY empty with a valid PENCIL_CLI_KEY", { PEN_CLI_KEY: "", PENCIL_CLI_KEY: "key-fallback-0123456789" }, "key-fallback-0123456789"],
    ["PEN_CLI_KEY whitespace with a valid PENCIL_CLI_KEY", { PEN_CLI_KEY: "   ", PENCIL_CLI_KEY: "key-fallback2-0123456789" }, "key-fallback2-0123456789"],
    ["both set with different values: PEN_CLI_KEY wins", { PEN_CLI_KEY: "key-winner-0123456789", PENCIL_CLI_KEY: "key-loser-0123456789" }, "key-winner-0123456789"],
  ] as const) {
    test(`${label}: the adapter starts and the child gets that value under PEN_CLI_KEY`, async () => {
      const d = caseDir(`keys-${label.replace(/\W+/g, "-")}`);
      const wrapper = join(d, "keyprobe.mjs");
      writeFileSync(
        wrapper,
        `import { writeFileSync } from "node:fs";
const i = process.argv.indexOf("--out");
writeFileSync(process.argv[i + 1] + ".keyseen", process.env.PEN_CLI_KEY ?? "");
process.env.STUB_TAG = "";
await import(${JSON.stringify(pathToFileURL(STUB).href)});
`,
        { mode: 0o755 }
      );
      chmodSync(wrapper, 0o755);
      const f = join(d, "a.pen");
      const s = await session({ binary: wrapper, keys: keys as any });
      expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
      expect(read(`${f}.keyseen`)).toBe(winner);
      if (label.includes("fallback)") || label.includes("valid PENCIL")) expect(s.stderr()).toMatch(/PENCIL_CLI_KEY is deprecated/);
      for (const v of Object.values(keys)) if (v.trim()) expect(s.stderr()).not.toContain(v);
    });
  }

  test("an engine reply that echoes the key (stdout or stderr) never reaches the tool result or the adapter's stderr", async () => {
    for (const mode of [true, "stdout"] as const) {
      const f = join(caseDir(`echo-key-${mode}`), "a.pen");
      const s = await session({ keys: { PEN_CLI_KEY: SECRET } });
      expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
      setFlags(f, { echoKey: mode });
      const r = await s.call("batch_design", { operations: ADD });
      expect(r.isError).toBe(true);
      expect(r.text).toContain("<redacted>");
      expect(r.text).not.toContain(SECRET);
      expect(s.stderr()).not.toContain(SECRET);
    }
  });

  test("a key written to stderr in two chunks 50 ms apart is redacted in the result and in the adapter's stderr", async () => {
    const f = join(caseDir("echo-split"), "a.pen");
    const s = await session({ keys: { PEN_CLI_KEY: SECRET } });
    await s.call("open_document", { filePath: f });
    setFlags(f, { echoKeySplit: true });
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.text).not.toContain(SECRET);
    expect(s.stderr()).not.toContain(SECRET);
    expect(s.stderr()).not.toContain(SECRET.slice(0, 16));
    expect(s.stderr()).toContain("<redacted>");
    // the edit itself still went through
    expect(children(f)).toBe(1);
  });

  test("-e KEY=VALUE on argv: only the two key names are accepted, with a value-free warning", async () => {
    const r = spawnSync(
      "node",
      [join(installDir, "pencil-mcp-adapter.mjs"), "-e", "PEN_CLI_KEY=argv-key-0123456789", "-e", "OTHER_VAR=ignored-value-xyz"],
      { env: { PATH: process.env.PATH ?? "", HOME: process.env.HOME ?? "" }, input: "", encoding: "utf8", timeout: 6000 }
    );
    expect(r.stderr).toMatch(/argv is visible to other local users/);
    expect(r.stderr).toMatch(/OTHER_VAR/);
    expect(r.stderr).not.toContain("argv-key-0123456789");
    expect(r.stderr).not.toContain("ignored-value-xyz");
    expect(r.stderr).toContain("MCP server started on stdio");
  });
});

describe("binary resolution", () => {
  test("a relative PENCIL_BINARY is refused", async () => {
    const d = caseDir("relative-binary");
    const s = await session({ binary: "relative/pen.js", cwd: d });
    const r = await s.call("open_document", { filePath: join(d, "a.pen") });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/PENCIL_BINARY must be an absolute path/);
  });

  test("PENCIL_BINARY must be a regular file owned by us, not group- or world-writable, not a symlink", async () => {
    const d = caseDir("override-modes");
    const writable = join(d, "writable.mjs");
    copyFileSync(BIN, writable);
    chmodSync(writable, 0o775);
    const link = join(d, "link.mjs");
    symlinkSync(BIN, link);
    for (const [binary, why] of [
      [writable, /writable/],
      [link, /symlink|regular file/],
      [d, /regular file/],
    ] as const) {
      const s = await session({ binary });
      const r = await s.call("open_document", { filePath: join(d, "a.pen") });
      expect(r.isError).toBe(true);
      expect(r.text).toMatch(/PENCIL_BINARY/);
      expect(r.text).toMatch(why);
    }
  });

  test("a safe PENCIL_BINARY works and each use writes a value-free stderr line", async () => {
    const f = join(caseDir("override-ok"), "a.pen");
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    expect(s.stderr()).toMatch(/PENCIL_BINARY override in use/);
  });

  test("the child's PATH has no empty or relative entries", async () => {
    const d = caseDir("path-filter");
    const wrapper = join(d, "pathprobe.mjs");
    writeFileSync(
      wrapper,
      `import { writeFileSync } from "node:fs";
const i = process.argv.indexOf("--out");
writeFileSync(process.argv[i + 1] + ".pathseen", process.env.PATH ?? "");
process.env.STUB_TAG = "";
await import(${JSON.stringify(pathToFileURL(STUB).href)});
`,
      { mode: 0o755 }
    );
    chmodSync(wrapper, 0o755);
    const f = join(d, "a.pen");
    const s = await session({ binary: wrapper, extraEnv: { PATH: `${process.env.PATH}::relative/bin:.:/usr/bin` } });
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    const entries = read(`${f}.pathseen`).split(":");
    expect(entries.every((e) => e.startsWith("/"))).toBe(true);
    expect(entries).toContain("/usr/bin");
  });

  // The shared identity table (Guard 2): the same rows run through check_deps.sh in
  // check-deps-adapter-drift.test.sh. `accept` = the adapter goes on to spawn the declared
  // binary (the fake engine exits at once, so the open fails with "exited before it was ready"
  // and the credential reached it); `refuse` = it never spawns anything.
  const rows = readFileSync(IDENTITY_TSV, "utf8")
    .split("\n")
    .filter((l) => l.trim() && !l.startsWith("#"))
    .map((l) => l.split("\t"))
    .filter((c) => c[0] !== "layout");
  test("the identity table is non-empty and every layout is covered", () => {
    expect(rows.length).toBeGreaterThanOrEqual(14);
  });
  for (const [layout, adapterVerdict] of rows) {
    test(`identity row ${layout}: adapter ${adapterVerdict}`, async () => {
      const home = caseDir(`identity-${layout}`);
      const tree = buildPenTree(home, layout);
      const nodeBin = Bun.which("node") ?? "node";
      const s = await session({
        binary: "",
        nodeBin,
        cwd: caseDir(`identity-${layout}-cwd`),
        extraEnv: { HOME: home, PATH: `${tree.fakeBin}:/usr/bin:/bin` },
      });
      const r = await s.call("open_document", { filePath: join(home, "doc.pen") });
      expect(r.isError).toBe(true);
      const engineLog = join(home, "engine-env.log");
      if (adapterVerdict === "accept") {
        expect(r.text).toMatch(/exited before it was ready/);
        expect(r.text).not.toMatch(/pen CLI not found/);
        expect(readFileSync(engineLog, "utf8")).toMatch(/KEYS=PEN_CLI_KEY\n/); // the credential reached the declared binary, under one name
        if (layout === "version-differs") expect(s.stderr()).toMatch(/version 0\.3\.12/);
      } else {
        expect(r.text).toMatch(/pen CLI not found/);
        expect(r.text).toMatch(/check_deps\.sh|pencil-setup/);
        expect(existsSync(engineLog)).toBe(false); // the credential was never handed to anything
      }
    });
  }

  test("with no pen installed the adapter errors; it never runs ./pen.js from the working directory", async () => {
    const d = caseDir("no-binary");
    const project = join(d, "project");
    const home = join(d, "home");
    mkdirSync(project, { recursive: true });
    mkdirSync(home, { recursive: true });
    const marker = join(d, "EXECUTED");
    writeFileSync(join(project, "pen.js"), `require("fs").writeFileSync(${JSON.stringify(marker)}, "ran");`);
    const s = await session({ binary: "", cwd: project, nodeBin: Bun.which("node") ?? "node", extraEnv: { HOME: home, PATH: "/usr/bin:/bin" } });
    const r = await s.call("open_document", { filePath: join(d, "a.pen") });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/pen CLI not found/);
    expect(existsSync(marker)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Screenshot and export persistence (containedDir).

describe("export_nodes and get_screenshot persistence", () => {
  async function opened(name: string, cwd?: string) {
    const d = caseDir(name);
    const f = join(d, "a.pen");
    writeFileSync(f, pen(2));
    const s = await session({ cwd: cwd ?? d });
    await s.call("open_document", { filePath: f });
    return { d, f, s };
  }

  test("an export lands in the directory, reports `Exported to:` and only the paths inside it; a repeat lists the overwrite", async () => {
    const { d, s } = await opened("export-ok");
    const out = join(d, "exports");
    const r = await s.call("export_nodes", { nodeIds: ["seed0", "seed1"], outputDir: out, format: "png", scale: 2 });
    expect(r.isError).toBe(false);
    expect(r.text.split("\n")[0]).toBe(`Exported to: ${out}`);
    expect(r.text).toContain(`Exported ${join(out, "seed0.png")}`);
    expect(existsSync(join(out, "seed1.png"))).toBe(true);
    expect(r.text).not.toMatch(/already existed/);
    const again = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: out });
    expect(again.text).toMatch(/already existed/);
    expect(again.text).toContain("seed0.png");
    expect(again.text).not.toMatch(/WARNING: rendered from unsaved memory/);
  });

  test("a relative outputDir, a bad id, an out-of-range scale and an unknown format are rejected before anything is written", async () => {
    const { d, s, f } = await opened("export-validate");
    const before = logOf(f).length;
    for (const [args, why] of [
      [{ nodeIds: ["seed0"], outputDir: "exports" }, /absolute/],
      [{ nodeIds: ["se ed"], outputDir: join(d, "o") }, /node id/],
      [{ nodeIds: ["seed0"], outputDir: join(d, "o"), scale: 99 }, /scale/],
      [{ nodeIds: ["seed0"], outputDir: join(d, "o"), quality: 0 }, /quality/],
    ] as const) {
      const r = await s.call("export_nodes", args as any);
      expect(r.isError).toBe(true);
      expect(r.text).toMatch(why);
    }
    expect(logOf(f).length).toBe(before); // nothing reached the engine
    expect(existsSync(join(d, "o"))).toBe(false);
  });

  test("a directory outside the allowed roots, and a symlinked component, are refused", async () => {
    const { d, s } = await opened("export-contain");
    const outside = caseDir("export-contain-outside");
    const r = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(outside, "x") });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/outside/);
    expect(existsSync(join(outside, "x"))).toBe(false);

    const real = join(d, "real");
    mkdirSync(real);
    symlinkSync(real, join(d, "leaf"));
    const leaf = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(d, "leaf") });
    expect(leaf.isError).toBe(true);
    expect(leaf.text).toMatch(/symlink/);
    const below = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(d, "leaf", "sub") });
    expect(below.isError).toBe(true);
    expect(existsSync(join(real, "sub"))).toBe(false);
  });

  test("a cwd equal to $HOME is not an allowed root: the document's directory is", async () => {
    const home = caseDir("export-home");
    const other = caseDir("export-home-doc");
    const f = join(other, "a.pen");
    writeFileSync(f, pen(2));
    const s = await session({ cwd: home, extraEnv: { HOME: home } });
    await s.call("open_document", { filePath: f });
    const viaHome = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(home, "exports") });
    expect(viaHome.isError).toBe(true);
    expect(existsSync(join(home, "exports"))).toBe(false);
    const viaDoc = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(other, "exports") });
    expect(viaDoc.isError).toBe(false);
  });

  test("a symlinked alias of the allowed root is accepted when the real path is inside it", async () => {
    const real = caseDir("export-alias-real");
    const alias = join(root, "export-alias-link");
    symlinkSync(real, alias);
    const f = join(real, "a.pen");
    writeFileSync(f, pen(2));
    const s = await session({ cwd: real });
    await s.call("open_document", { filePath: f });
    const r = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(alias, "exports") });
    expect(r.isError).toBe(false);
    expect(existsSync(join(real, "exports", "seed0.png"))).toBe(true);
  });

  test("get_screenshot saves a PNG next to the document with the wx flag; a symlinked screenshots directory is refused but the image still comes back", async () => {
    const { d, f, s } = await opened("shot");
    const r = await s.call("get_screenshot", { nodeId: "seed0" });
    expect(r.isError).toBe(false);
    const m = /Screenshot saved: (\S+)/.exec(r.text);
    expect(m).not.toBeNull();
    expect(m![1].startsWith(join(d, "screenshots"))).toBe(true);
    expect(readFileSync(m![1]).subarray(1, 4).toString()).toBe("PNG");
    expect(saves(f)).toBe(0);
    expect((await s.call("get_screenshot", { nodeId: "bad id" })).isError).toBe(true);

    const d2 = caseDir("shot-symlink");
    const f2 = join(d2, "a.pen");
    writeFileSync(f2, pen(2));
    const elsewhere = caseDir("shot-symlink-target");
    symlinkSync(elsewhere, join(d2, "screenshots"));
    const s2 = await session({ cwd: d2 });
    await s2.call("open_document", { filePath: f2 });
    const r2 = await s2.call("get_screenshot", { nodeId: "seed0" });
    expect(r2.isError).toBe(false);
    expect(r2.text).toMatch(/Screenshot not saved to disk/);
    expect(readdirSync(elsewhere)).toEqual([]);
  });

  test("while a refusal is pending, exports and screenshots are marked as rendered from unsaved memory", async () => {
    const { d, f, s } = await opened("export-pending");
    writeFileSync(f, pen(5, "other"));
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(true);
    const ex = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(d, "exports") });
    expect(ex.isError).toBe(false);
    expect(ex.text.split("\n")[0]).toBe("WARNING: rendered from unsaved memory, not the file on disk");
    const shot = await s.call("get_screenshot", { nodeId: "seed0" });
    expect(shot.text).toMatch(/WARNING: rendered from unsaved memory/);
  });
});
