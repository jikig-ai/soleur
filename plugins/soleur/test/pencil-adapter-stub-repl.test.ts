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
import { buildPenTree, LAYOUTS } from "./lib/pen-identity-tree.mjs";
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
let BIN = ""; // an untagged, mode-0755 wrapper around the stub (the adapter trusts --pencil-binary only for a safe regular file)
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
// `binary` is the engine binary the session is registered with (the --pencil-binary argv flag);
// "" leaves the adapter on its default resolution. `passwdHome` is what os.userInfo().homedir
// reports inside the adapter (default: the session's HOME).
async function session(opts: { binary?: string; keys?: Record<string, string>; cwd?: string; extraEnv?: Record<string, string>; nodeBin?: string; passwdHome?: string } = {}): Promise<Session> {
  const s = await connectAdapter({ installDir, penBinary: opts.binary ?? BIN, keys: opts.keys, cwd: opts.cwd, extraEnv: opts.extraEnv, nodeBin: opts.nodeBin, passwdHome: opts.passwdHome });
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

  test("a file removed behind a LIVE session is saved again (recreated): the engine's copy is the only one, and the result says so", async () => {
    const f = join(caseDir("removed-behind"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    rmSync(f);
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(false);
    expect(r.text.split("\n")[0]).toBe(
      `NOTE: ${f} had been removed from disk (a branch switch, a move or a delete); this save recreated it from the session's copy - tell the user and check that the file belongs at that path`
    );
    expect(r.text).toContain(`Document: ${f}`);
    expect(existsSync(f)).toBe(true);
    expect(children(f)).toBe(3); // the engine's copy: 2 seeds plus the edit
    expect(s.stderr()).toMatch(/\[pencil-adapter\] \[reason=recreated\] \S+ baseline=[0-9a-f]{8}/);
    expect(s.stderr()).not.toMatch(/REFUSED save/);
    // the recreated file is the new baseline: the next edit saves without a note
    const again = await s.call("batch_design", { operations: ADD });
    expect(again.isError).toBe(false);
    expect(again.text).not.toMatch(/^NOTE:/);
    expect(children(f)).toBe(4);
  });

  test("an explicit save over a file removed behind a live session is prefixed by the same note", async () => {
    const f = join(caseDir("removed-behind-save"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    rmSync(f);
    const r = await s.call("save");
    expect(r.isError).toBe(false);
    expect(r.text.split("\n")[0]).toMatch(/^NOTE: .* had been removed from disk/);
    expect(r.text).toMatch(/\nSaved /);
    expect(children(f)).toBe(2);
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

  test("G1a: in a document larger than 4096 bytes, a change only in the LAST node is still stale (the hash covers the whole document)", async () => {
    const f = join(caseDir("stale-large-tail"), "a.pen");
    const big = (tail: string) =>
      JSON.stringify({
        version: "2.21",
        children: Array.from({ length: 120 }, (_, i) => ({ id: `n${i}`, type: "frame", name: i === 119 ? tail : `node number ${i}`, width: 10, height: 10 })),
      });
    const a = big("tail-aaaa");
    expect(a.length).toBeGreaterThan(4096 * 2);
    writeFileSync(f, a);
    const s = await session();
    await s.call("open_document", { filePath: f });
    const b = big("tail-bbbb");
    expect(b.length).toBe(a.length);
    writeFileSync(f, b);
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text.split("\n")[0]).toBe(`REFUSED save: [reason=stale] ${f} was not modified.`);
    expect(read(f)).toBe(b);
  });

  test("an external rewrite that only reorders object keys does not refuse (canonical JSON)", async () => {
    const f = join(caseDir("same-keyorder"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    const doc = JSON.parse(read(f));
    const reordered = { children: doc.children.map((n: any) => Object.fromEntries(Object.entries(n).reverse())), ...Object.fromEntries(Object.entries(doc).filter(([k]) => k !== "children").reverse()) };
    writeFileSync(f, JSON.stringify(reordered));
    expect(read(f)).not.toBe(JSON.stringify(doc));
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(2);
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
    expect(r.text.split("\n")[0]).toBe(`NOT PERSISTED: [reason=unconfirmed] ${f} may or may not have been written: the engine's reply was not \`Saved <file>\`.`);
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
    expect(r.text).toMatch(/^NOT PERSISTED: \[reason=unconfirmed\]/);
    setFlags(f, {});
    const next = await s.call("save");
    expect(next.isError).toBe(true);
    expect(next.text).toMatch(/last save was not confirmed/);
  });

  test("a definite `Save failed:` keeps the previous baseline: the retry after the cause is fixed saves (no open_document, which would discard the edit)", async () => {
    const f = join(caseDir("save-failed"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { failSave: true });
    const failed = await s.call("batch_design", { operations: ADD });
    expect(failed.isError).toBe(true);
    expect(failed.text.split("\n")[0]).toMatch(/^NOT PERSISTED: \[reason=save-failed\] \S+ was not written: the engine reported a failed save \(Save failed: EACCES/);
    expect(failed.text).toMatch(/applied in memory only/);
    expect(failed.text).toMatch(/call save again/);
    expect(failed.text).toMatch(/Do NOT call open_document/);
    expect(s.stderr()).toMatch(/save failed \(definite\): baseline kept/);
    expect(s.stderr()).not.toContain("baseline=unknown");
    expect(children(f)).toBe(2);
    setFlags(f, {});
    const retry = await s.call("save");
    expect(retry.isError).toBe(false);
    expect(retry.text).toMatch(/Saved /);
    expect(children(f)).toBe(3); // the edit made before the failure
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(4);
  });

  test("a definite failure followed by a change on disk refuses as stale on the retry (the kept baseline still guards)", async () => {
    const f = join(caseDir("save-failed-then-changed"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { failSave: true });
    expect((await s.call("batch_design", { operations: ADD })).text).toMatch(/reason=save-failed/);
    setFlags(f, {});
    writeFileSync(f, pen(6, "other"));
    const before = read(f);
    const retry = await s.call("save");
    expect(retry.isError).toBe(true);
    expect(retry.text.split("\n")[0]).toBe(`REFUSED save: [reason=stale] ${f} was not modified.`);
    expect(read(f)).toBe(before);
  });

  test("an ambiguous reply is NOT a definite failure: the baseline becomes unknown (a retry is refused, only open_document recovers)", async () => {
    const f = join(caseDir("save-ambiguous"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { saveReply: "Save failed? who knows", saveWrites: false });
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.text).toMatch(/^NOT PERSISTED: \[reason=unconfirmed\]/);
    setFlags(f, {});
    const retry = await s.call("save");
    expect(retry.text.split("\n")[0]).toBe(`REFUSED save: [reason=unknown-baseline] ${f} was not modified.`);
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
  });

  test("a save that kills the engine mid-command is `NOT PERSISTED: [reason=save-incomplete]`, and the session recovers", async () => {
    const f = join(caseDir("save-incomplete"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { exitOnSave: true });
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text.split("\n")[0]).toMatch(/^NOT PERSISTED: \[reason=save-incomplete\] \S+: the edit was applied in memory but the save did not complete/);
    expect(r.text).toMatch(/pen exited during a command/);
    expect(s.stderr()).toMatch(/save did not complete: .*pen exited/);
    expect(children(f)).toBe(2);
    setFlags(f, {});
    const explicit = await s.call("save");
    expect(explicit.isError).toBe(false);
  });

  test("exports and screenshots are marked while ANY edit is unpersisted (NOT PERSISTED too), and the mark clears on a confirmed save", async () => {
    const d = caseDir("unpersisted-mark");
    const f = join(d, "a.pen");
    writeFileSync(f, pen(2));
    const s = await session({ cwd: d });
    await s.call("open_document", { filePath: f });
    const clean = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(d, "e1") });
    expect(clean.text).not.toMatch(/rendered from unsaved memory/);
    setFlags(f, { failSave: true });
    expect((await s.call("batch_design", { operations: ADD })).text).toMatch(/NOT PERSISTED/);
    const marked = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(d, "e2") });
    expect(marked.text.split("\n")[0]).toBe("WARNING: rendered from unsaved memory, not the file on disk");
    expect((await s.call("get_screenshot", { nodeId: "seed0" })).text).toMatch(/WARNING: rendered from unsaved memory/);
    setFlags(f, {});
    expect((await s.call("save")).isError).toBe(false);
    const after = await s.call("export_nodes", { nodeIds: ["seed0"], outputDir: join(d, "e3") });
    expect(after.text).not.toMatch(/rendered from unsaved memory/);
    expect((await s.call("get_screenshot", { nodeId: "seed0" })).text).not.toMatch(/rendered from unsaved memory/);
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

// ---------------------------------------------------------------------------
// The marker contract: the FIRST line of every refusal tool-result is
// `REFUSED save: [reason=<code>] <file> was not modified.`

describe("marker contract: reason codes in the tool result", () => {
  const first = (r: { text: string }) => r.text.split("\n")[0];

  test("empty (disk holds nodes, memory empty)", async () => {
    const f = join(caseDir("marker-empty"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    writeFileSync(f, pen(3));
    expect(first(await s.call("save"))).toBe(`REFUSED save: [reason=empty] ${f} was not modified.`);
  });

  test("empty also covers an unreadable in-memory count", async () => {
    const f = join(caseDir("marker-empty-unreadable"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { countForgery: "missing" });
    expect(first(await s.call("save"))).toBe(`REFUSED save: [reason=empty] ${f} was not modified.`);
  });

  test("unrecognized (disk is not a .pen document)", async () => {
    const f = join(caseDir("marker-unrecognized"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    writeFileSync(f, "# not a pen\n");
    expect(first(await s.call("save"))).toBe(`REFUSED save: [reason=unrecognized] ${f} was not modified.`);
  });

  test("stale, then refusal-pending on the next save", async () => {
    const f = join(caseDir("marker-stale"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    writeFileSync(f, pen(5, "other"));
    expect(first(await s.call("save"))).toBe(`REFUSED save: [reason=stale] ${f} was not modified.`);
    expect(first(await s.call("save"))).toBe(`REFUSED save: [reason=refusal-pending] ${f} was not modified.`);
  });

  test("unknown-baseline", async () => {
    const f = join(caseDir("marker-unknown"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { saveReply: "", saveWrites: false });
    expect((await s.call("save")).text).toMatch(/^NOT PERSISTED: \[reason=unconfirmed\]/);
    setFlags(f, {});
    expect(first(await s.call("save"))).toBe(`REFUSED save: [reason=unknown-baseline] ${f} was not modified.`);
  });

  test("every code that reaches the stderr line also reaches the tool result, with the same code", async () => {
    const f = join(caseDir("marker-both"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    writeFileSync(f, pen(5, "other"));
    const r = await s.call("batch_design", { operations: ADD });
    const code = /^REFUSED save: \[reason=([a-z-]+)\]/.exec(first(r))![1];
    expect(code).toBe("stale");
    expect(s.stderr()).toContain(`REFUSED save: [reason=${code}] ${f}`);
  });

  test("open_document warns when the captured baseline is unknown (a FIFO at the path)", async () => {
    const d = caseDir("open-unknown-baseline");
    const f = join(d, "a.pen");
    expect(spawnSync("mkfifo", [f]).status).toBe(0);
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(false);
    expect(o.text).toMatch(/Opened .* \(0 top-level node\(s\) loaded\)/);
    expect(o.text).toMatch(/\nWARNING: could not record a baseline for .*ENOTFILE.*every save is refused/);
    expect(s.stderr()).toMatch(/baseline capture failed for \S+ \(ENOTFILE\); baseline=unknown/);
  });
});

// ---------------------------------------------------------------------------
// Respawn rulings: a crash/timeout respawn onto a changed or vanished file arms the refusal;
// the respawn load is verified like open_document's.

describe("crash respawn onto a file the session did not see", () => {
  test("EXTERNAL CHANGE during the crash arms the refusal: the engine's reload is read, but the next edit is refused until open_document", async () => {
    const f = join(caseDir("respawn-external"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    await killAndWait(stubPid(f));
    writeFileSync(f, pen(5, "other"));
    const before = read(f);
    const g = await s.call("get_editor_state", {});
    expect(g.isError).toBe(false);
    expect(g.text).toContain("other4"); // the engine reloaded the NEW content
    expect(s.stderr()).toMatch(/respawn: file changed on disk behind a restarted session \(cause=external-change\) baseline=[0-9a-f]{8} disk=[0-9a-f]{8}; refusalPending armed/);
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text.split("\n")[0]).toBe(`REFUSED save: [reason=refusal-pending] ${f} was not modified.`);
    expect(r.text).toMatch(/the engine reloaded NEW content/);
    expect(r.text).toMatch(/Nothing on disk was overwritten/);
    expect(r.text).toContain("Insert(document"); // the refused operations are echoed
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
    expect(s.stderr()).toMatch(/REFUSED save: \[reason=refusal-pending\] \S+ baseline=[0-9a-f]{8} disk=[0-9a-f]{8}/);
    // recovery
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(6);
  });

  test("FILE REMOVED during the crash arms the refusal and is NOT silently recreated", async () => {
    const f = join(caseDir("respawn-missing"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    await killAndWait(stubPid(f));
    rmSync(f);
    const g = await s.call("get_editor_state", {});
    expect(g.isError).toBe(false);
    expect(s.stderr()).toMatch(/respawn: file is gone behind a restarted session \(cause=file-missing\) baseline=[0-9a-f]{8} disk=-; refusalPending armed/);
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text.split("\n")[0]).toBe(`REFUSED save: [reason=refusal-pending] ${f} was not modified.`);
    expect(r.text).toMatch(/no longer exists on disk/);
    expect(r.text).toMatch(/recreate the edits from your context/);
    expect(existsSync(f)).toBe(false);
    expect(saves(f)).toBe(0);
  });

  test("an UNCHANGED file adopts silently on respawn (no arm, the next edit saves)", async () => {
    const f = join(caseDir("respawn-unchanged"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    await s.call("open_document", { filePath: f });
    await killAndWait(stubPid(f));
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(s.stderr()).not.toMatch(/cause=(external-change|file-missing)/);
    expect(children(f)).toBe(4);
  });

  test("a missing baseline that is still missing adopts silently", async () => {
    const f = join(caseDir("respawn-still-missing"), "a.pen");
    const s = await session();
    await s.call("open_document", { filePath: f });
    await killAndWait(stubPid(f));
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(1);
  });

  test("A7: an unknown baseline plus a crash is not recaptured: the next save is refused, and the marker says so", async () => {
    const f = join(caseDir("respawn-unknown"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { saveReply: "", saveWrites: false });
    expect((await s.call("batch_design", { operations: ADD })).text).toMatch(/reason=unconfirmed/);
    setFlags(f, {});
    await killAndWait(stubPid(f));
    const r = await s.call("batch_design", { operations: ADD });
    expect(r.isError).toBe(true);
    expect(r.text.split("\n")[0]).toBe(`REFUSED save: [reason=unknown-baseline] ${f} was not modified.`);
    expect(s.stderr()).toContain("respawn: baseline unknown, not recaptured (open_document to re-baseline)");
    expect(saves(f)).toBe(1);
  });

  test("A19: a change made during the crash window is what arms (and pins the new behaviour, not a silent adopt)", async () => {
    const f = join(caseDir("respawn-a19"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session();
    await s.call("open_document", { filePath: f });
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false); // saved: 3 nodes, baseline = that
    await killAndWait(stubPid(f));
    const doc = JSON.parse(read(f));
    doc.children[0].name = "edited-elsewhere";
    writeFileSync(f, JSON.stringify(doc));
    expect((await s.call("get_editor_state", {})).isError).toBe(false);
    const r = await s.call("save");
    expect(r.text.split("\n")[0]).toBe(`REFUSED save: [reason=refusal-pending] ${f} was not modified.`);
    expect(saves(f)).toBe(1);
  });
});

describe("load fidelity (open_document and the respawn load)", () => {
  test("open_document refuses a load with FEWER top-level nodes than the file holds (any drop, not only zero)", async () => {
    const f = join(caseDir("fidelity-open"), "a.pen");
    writeFileSync(f, pen(5));
    setFlags(f, { loadFirst: 3 });
    const before = read(f);
    const s = await session();
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(true);
    expect(o.text).toMatch(/holds 5 top-level node\(s\) on disk but loaded 3; it was not modified/);
    expect((await s.call("get_editor_state", {})).text).toMatch(/open failed/);
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
  });

  test("a load with the same or more nodes is accepted", async () => {
    const f = join(caseDir("fidelity-ok"), "a.pen");
    writeFileSync(f, pen(5));
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).text).toMatch(/5 top-level node/);
  });

  test("RESPAWN loaded-empty (the P1 repro): no tool runs until open_document succeeds, and nothing is saved over the file", async () => {
    const f = join(caseDir("fidelity-respawn-empty"), "a.pen");
    writeFileSync(f, pen(3));
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    setFlags(f, { loadEmpty: true }); // the engine will load the unchanged file as an empty document
    await killAndWait(stubPid(f));
    const before = read(f);
    const g = await s.call("get_editor_state", {});
    expect(g.isError).toBe(true);
    expect(g.text).toMatch(/open failed: .*holds 3 top-level node\(s\) on disk but loaded empty/);
    const e = await s.call("batch_design", { operations: ADD });
    expect(e.isError).toBe(true);
    expect(e.text).toMatch(/open failed/);
    expect((await s.call("save")).isError).toBe(true);
    expect(read(f)).toBe(before);
    expect(saves(f)).toBe(0);
    expect(s.stderr()).toMatch(/respawn load check failed/);
    // recovery: the engine behaves again and open_document succeeds
    setFlags(f, {});
    const o = await s.call("open_document", { filePath: f });
    expect(o.isError).toBe(false);
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(false);
    expect(children(f)).toBe(4);
  });

  test("RESPAWN load with fewer (but not zero) nodes is refused the same way, using the count read BEFORE the spawn", async () => {
    const f = join(caseDir("fidelity-respawn-fewer"), "a.pen");
    writeFileSync(f, pen(4));
    const s = await session();
    await s.call("open_document", { filePath: f });
    setFlags(f, { loadFirst: 2, rewriteOnStart: JSON.parse(pen(2)) }); // the file shrinks to match the dropped load: only the count read BEFORE the spawn still sees 4
    await killAndWait(stubPid(f));
    const g = await s.call("get_editor_state", {});
    expect(g.isError).toBe(true);
    expect(g.text).toMatch(/holds 4 top-level node\(s\) on disk but loaded 2/);
    expect(saves(f)).toBe(0);
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
    // The rolling redactor is NOT flushed when a command ends (a spelling split across two
    // replies must still be caught), so the redacted line surfaces with the next stderr
    // output (or when the child's streams close): a second command moves the held tail out.
    await s.call("batch_design", { operations: ADD });
    expect(s.stderr()).toContain("<redacted>");
    expect(s.stderr()).not.toContain(SECRET);
    // the edits themselves still went through
    expect(children(f)).toBe(2);
  });

  test("A26: a key inside the refused operations is redacted in the tool result (the echo is not a leak path)", async () => {
    const f = join(caseDir("echo-refused-ops"), "a.pen");
    writeFileSync(f, pen(2));
    const s = await session({ keys: { PEN_CLI_KEY: SECRET } });
    await s.call("open_document", { filePath: f });
    writeFileSync(f, pen(5, "other"));
    const r = await s.call("batch_design", { operations: `${ADD}\nPrint("${SECRET}")` });
    expect(r.isError).toBe(true);
    expect(r.text.split("\n")[0]).toMatch(/^REFUSED save: \[reason=stale\]/);
    expect(r.text).not.toContain(SECRET);
    expect(r.text).toContain("<redacted>");
    expect(s.stderr()).not.toContain(SECRET);
  });

  test("A27: a key inside the document path is redacted on the stderr REFUSED line (logRefusal) and the armed line", async () => {
    const d = caseDir(`logrefusal-${SECRET}`);
    const f = join(d, "a.pen");
    writeFileSync(f, pen(2));
    const s = await session({ keys: { PEN_CLI_KEY: SECRET } });
    await s.call("open_document", { filePath: f });
    writeFileSync(f, pen(5, "other"));
    expect((await s.call("batch_design", { operations: ADD })).isError).toBe(true);
    expect(s.stderr()).toMatch(/REFUSED save: \[reason=stale\] \S*<redacted>\S*\/a\.pen/);
    expect(s.stderr()).toMatch(/refusalPending=true \S*<redacted>/);
    expect(s.stderr()).not.toContain(SECRET);
  });

  test("A12: the `baseline capture failed` line redacts a key in the path", async () => {
    const d = caseDir(`capture-failed-${SECRET}`);
    const f = join(d, "a.pen");
    expect(spawnSync("mkfifo", [f]).status).toBe(0);
    const s = await session({ keys: { PEN_CLI_KEY: SECRET } });
    await s.call("open_document", { filePath: f });
    expect(s.stderr()).toMatch(/baseline capture failed for \S*<redacted>\S* \(ENOTFILE\)/);
    expect(s.stderr()).not.toContain(SECRET);
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
  test("a relative --pencil-binary is refused", async () => {
    const d = caseDir("relative-binary");
    const s = await session({ binary: "relative/pen.js", cwd: d });
    const r = await s.call("open_document", { filePath: join(d, "a.pen") });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/--pencil-binary must be an absolute path/);
  });

  test("--pencil-binary must be a regular file owned by us, not group- or world-writable, not a symlink", async () => {
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
      expect(r.text).toMatch(/--pencil-binary/);
      expect(r.text).toMatch(why);
    }
  });

  test("a safe --pencil-binary works and each use writes a value-free stderr line", async () => {
    const f = join(caseDir("override-ok"), "a.pen");
    const s = await session();
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    expect(s.stderr()).toMatch(/--pencil-binary override in use/);
    expect(s.stderr()).not.toContain(BIN);
  });

  test("the PENCIL_BINARY environment variable ALONE is ignored (a project settings env block must not pick the binary), with a value-free WARN", async () => {
    const d = caseDir("env-binary-ignored");
    const home = caseDir("env-binary-ignored-home"); // nothing installed under it
    const s = await session({ binary: "", cwd: d, nodeBin: Bun.which("node") ?? "node", extraEnv: { HOME: home, PENCIL_BINARY: BIN } });
    const r = await s.call("open_document", { filePath: join(d, "a.pen") });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/pen CLI not found/);
    expect(s.stderr()).toMatch(/PENCIL_BINARY environment variable is ignored/);
    expect(s.stderr()).not.toContain(BIN);
    expect(existsSync(sideFile(join(d, "a.pen"), "log"))).toBe(false); // the stub never ran
  });

  test("--pencil-binary wins over a stray PENCIL_BINARY, and the stray one draws no warning", async () => {
    const f = join(caseDir("flag-and-env"), "a.pen");
    const s = await session({ extraEnv: { PENCIL_BINARY: "/nonexistent/evil.mjs" } });
    expect((await s.call("open_document", { filePath: f })).isError).toBe(false);
    expect(s.stderr()).not.toMatch(/PENCIL_BINARY environment variable is ignored/);
  });

  test("--pencil-binary inside the working directory is refused (a project cannot supply the binary)", async () => {
    const d = caseDir("override-in-cwd");
    const inside = join(d, "pen.mjs");
    copyFileSync(BIN, inside);
    chmodSync(inside, 0o755);
    const s = await session({ binary: inside, cwd: d });
    const r = await s.call("open_document", { filePath: join(d, "a.pen") });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/--pencil-binary must not be inside the working directory or the project directory/);
    expect(existsSync(sideFile(join(d, "a.pen"), "log"))).toBe(false);
  });

  test("--pencil-binary inside CLAUDE_PROJECT_DIR is refused too", async () => {
    const d = caseDir("override-in-project");
    const inside = join(d, "pen.mjs");
    copyFileSync(BIN, inside);
    chmodSync(inside, 0o755);
    const s = await session({ binary: inside, extraEnv: { CLAUDE_PROJECT_DIR: d } });
    const r = await s.call("open_document", { filePath: join(d, "a.pen") });
    expect(r.isError).toBe(true);
    expect(r.text).toMatch(/must not be inside the working directory or the project directory/);
  });

  // The default binary: the passwd home first, $HOME second; a candidate is used only when
  // its package directory is outside the working directory and CLAUDE_PROJECT_DIR and is
  // owned by us and not group- or world-writable.
  describe("default resolution: candidates and trust", () => {
    const openOn = async (name: string, opts: { passwdHome: string; home: string; cwd?: string; extraEnv?: Record<string, string> }) => {
      const d = caseDir(`${name}-doc`);
      const s = await session({
        binary: "",
        nodeBin: Bun.which("node") ?? "node",
        cwd: opts.cwd ?? d,
        passwdHome: opts.passwdHome,
        extraEnv: { HOME: opts.home, PATH: "/usr/bin:/bin", ...(opts.extraEnv ?? {}) },
      });
      const r = await s.call("open_document", { filePath: join(d, "doc.pen") });
      return { s, r, d };
    };
    const accepted = (r: { text: string }) => /exited before it was ready/.test(r.text) && !/pen CLI not found/.test(r.text);

    test("the $HOME candidate is used when the passwd home holds nothing, with one value-free stderr line", async () => {
      const empty = caseDir("cand-empty");
      const home = caseDir("cand-home");
      buildPenTree(home, "good");
      const { s, r } = await openOn("cand-home-fallback", { passwdHome: empty, home });
      expect(accepted(r)).toBe(true);
      expect(s.stderr()).toMatch(/using the pen CLI under \$HOME \(it differs from the passwd home directory\)/);
      expect(s.stderr()).not.toContain(home);
    });

    test("the passwd home is tried FIRST: a good install there wins over a bad $HOME one, and a bad one there falls through to a good $HOME", async () => {
      const goodHome = caseDir("cand-first-good");
      const badHome = caseDir("cand-first-bad");
      buildPenTree(goodHome, "good");
      buildPenTree(badHome, "name-mismatch");
      const one = await openOn("cand-order-1", { passwdHome: goodHome, home: badHome });
      expect(accepted(one.r)).toBe(true);
      expect(one.s.stderr()).not.toMatch(/using the pen CLI under \$HOME/);
      const two = await openOn("cand-order-2", { passwdHome: badHome, home: goodHome });
      expect(accepted(two.r)).toBe(true);
      expect(two.s.stderr()).toMatch(/using the pen CLI under \$HOME/);
    });

    test("when both are bad the error names the reason of the installed-but-untrusted one and `check_deps.sh --auto`", async () => {
      const empty = caseDir("cand-bad-empty");
      const badHome = caseDir("cand-bad-bad");
      buildPenTree(badHome, "name-mismatch");
      const { r } = await openOn("cand-both-bad", { passwdHome: empty, home: badHome });
      expect(r.isError).toBe(true);
      expect(r.text).toMatch(/pen CLI not found or not trusted \(the package name is not @pen\.dev\/cli\)/);
      expect(r.text).toMatch(/check_deps\.sh --auto/);
    });

    test("a package directory inside the working directory is refused (the repo cannot supply the binary), also via CLAUDE_PROJECT_DIR", async () => {
      const home = caseDir("cand-in-cwd");
      const tree = buildPenTree(home, "good");
      // the working directory is an ancestor of the package directory but not of $HOME itself
      const viaCwd = await openOn("cand-in-cwd-1", { passwdHome: home, home, cwd: join(home, ".local") });
      expect(viaCwd.r.text).toMatch(/pen CLI not found or not trusted \(the package directory is inside the working directory or the project directory\)/);
      const viaProject = await openOn("cand-in-cwd-2", { passwdHome: home, home, extraEnv: { CLAUDE_PROJECT_DIR: join(tree.prefix, "..") } });
      expect(viaProject.r.text).toMatch(/inside the working directory or the project directory/);
      expect(existsSync(join(home, "engine-env.log"))).toBe(false); // the credential was never handed over
    });

    test("a working directory that IS (or contains) the home directory does not disqualify the install", async () => {
      const home = caseDir("cand-cwd-is-home");
      buildPenTree(home, "good");
      const { r } = await openOn("cand-cwd-home", { passwdHome: home, home, cwd: home });
      expect(accepted(r)).toBe(true);
    });

    test("a group-writable package directory is refused", async () => {
      const home = caseDir("cand-writable");
      const tree = buildPenTree(home, "good");
      chmodSync(tree.pkgDir, 0o775);
      const { r } = await openOn("cand-writable-1", { passwdHome: home, home });
      expect(r.text).toMatch(/pen CLI not found or not trusted \(the package directory is group- or world-writable\)/);
      expect(existsSync(join(home, "engine-env.log"))).toBe(false);
    });
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
  test("the identity table covers every layout of the tree builder, and only those", () => {
    expect(rows.map((c) => c[0]).sort()).toEqual(Object.keys(LAYOUTS).sort());
    expect(rows.length).toBeGreaterThanOrEqual(17);
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
// registerTool's catch: every thrown tool error leaves ONE `tool=<name> error:` stderr line
// (redacted, one line, at most 300 characters) next to the result the caller gets.

describe("a tool error leaves a stderr marker", () => {
  const SECRET = ["stub", "credential", "delta", "echo", "foxtrot"].join("-");
  const lineOf = (stderr: string, tool: string) => stderr.split("\n").find((l) => l.startsWith(`[pencil-adapter] tool=${tool} error: `)) ?? "";

  test("penPath (open_document of a non-.pen file), containedDir (export outside the roots), formatReplCommand (a removed tool) and findPenBinary each log their tool", async () => {
    const d = caseDir("tool-marker");
    const f = join(d, "a.pen");
    const s = await session({ cwd: d });
    await s.call("open_document", { filePath: f });

    const notPen = await s.call("open_document", { filePath: join(d, "notes.md") });
    expect(notPen.isError).toBe(true);
    expect(lineOf(s.stderr(), "open_document")).toMatch(/error: filePath must be a \.pen file/);

    const outside = await s.call("export_nodes", { nodeIds: ["x"], outputDir: join(caseDir("tool-marker-outside"), "o") });
    expect(outside.isError).toBe(true);
    expect(lineOf(s.stderr(), "export_nodes")).toMatch(/error: outputDir .* is outside the allowed directories/);

    const removed = await s.call("snapshot_layout", {});
    expect(removed.isError).toBe(true);
    expect(lineOf(s.stderr(), "snapshot_layout")).toMatch(/error: Unknown tool: snapshot_layout/);

    const badId = await s.call("get_screenshot", { nodeId: "bad id" });
    expect(badId.isError).toBe(true);
    expect(lineOf(s.stderr(), "get_screenshot")).toMatch(/error: node id must match/);

    const home = caseDir("tool-marker-home");
    const bare = await session({ binary: "", cwd: d, nodeBin: Bun.which("node") ?? "node", extraEnv: { HOME: home, PATH: "/usr/bin:/bin" } });
    const noPen = await bare.call("get_editor_state", {});
    expect(noPen.isError).toBe(true);
    expect(lineOf(bare.stderr(), "get_editor_state")).toMatch(/error: pen CLI not found/);
  });

  test("the line is one line, at most 300 characters after the marker, and the key is redacted", async () => {
    const d = caseDir("tool-marker-redact");
    const s = await session({ cwd: d, keys: { PEN_CLI_KEY: SECRET } });
    const r = await s.call("open_document", { filePath: join(d, `${"x".repeat(400)}-${SECRET}.md`) });
    expect(r.isError).toBe(true);
    const line = lineOf(s.stderr(), "open_document");
    expect(line).not.toBe("");
    expect(line.length).toBeLessThanOrEqual("[pencil-adapter] tool=open_document error: ".length + 300);
    expect(s.stderr()).not.toContain(SECRET);
    expect(r.text).not.toContain(SECRET);
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
