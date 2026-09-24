import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { EventEmitter } from "node:events";
import { tmpdir } from "node:os";

// Mock child_process.spawn so we drive the CLI lifecycle deterministically.
const spawnMock = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", () => ({ spawn: spawnMock }));

// Mock node:fs/promises so renderC4Model's temp-dir lifecycle (mkdtemp →
// readFile(temp) → rm) is deterministic. The fake `readFile` returns whatever
// model JSON the test stages — that string is what renderC4Model now RETURNS as
// `json` (#4976: off-tree render, no write onto the tracked path).
// `copyFile`/`rename`/`writeFile` are kept as spies even though the source no
// longer imports them: `vi.mock` replaces the WHOLE module, so any regression
// that re-introduces an in-place publish — via the old `copyFile`+`rename`
// shape OR a direct `writeFile(realPath, …)` — would call one of these spies and
// trip the `.not.toHaveBeenCalled()` assertions below.
const fsMock = vi.hoisted(() => ({
  lstat: vi.fn(),
  readdir: vi.fn(),
  mkdir: vi.fn(),
  mkdtemp: vi.fn(),
  readFile: vi.fn(),
  copyFile: vi.fn(),
  rename: vi.fn(),
  writeFile: vi.fn(),
  rm: vi.fn(),
}));
vi.mock("node:fs/promises", () => fsMock);

import { renderC4Model, STAGE_DEADLINE_MS, type StageFn } from "@/server/c4-render";
import { canonicalizeC4Model } from "@/lib/c4-canonical.mjs";

type FakeChild = EventEmitter & {
  stderr: EventEmitter;
  kill: ReturnType<typeof vi.fn>;
};

function makeChild(): FakeChild {
  const child = new EventEmitter() as FakeChild;
  child.stderr = new EventEmitter();
  child.kill = vi.fn();
  return child;
}

/** Capture the most recent spawn call's (cmd, args, opts). */
function lastSpawn() {
  const calls = spawnMock.mock.calls;
  return calls[calls.length - 1] as [string, string[], Record<string, unknown>];
}

// Wire the spawn mock to return `child` AND run `emit` in a microtask scheduled
// the moment spawn is invoked — so the close/error/stderr events fire AFTER
// runLikeC4 attaches its listeners (the render path awaits mkdtemp before
// spawning, so a test-level queueMicrotask would fire too early and the event
// would be lost → timeout).
function spawnThenEmit(child: FakeChild, emit: () => void) {
  spawnMock.mockImplementation(() => {
    queueMicrotask(emit);
    return child;
  });
}

const TMP_DIR = "/tmp/c4-render-abc123";
// A non-empty, valid layouted model (the success fixture).
const VALID_MODEL = JSON.stringify({
  elements: { founder: { id: "founder" }, platform: { id: "platform" } },
  views: { index: { hash: "6v56Y9lvx4UMwclrRQ4gL_jWujZQPMIQbDx8qnXD68w" }, context: {} },
});
// likec4 exits 0 but emits this when spec.c4 is missing (the bug class).
const EMPTY_MODEL = JSON.stringify({ elements: {}, views: {} });

beforeEach(() => {
  spawnMock.mockReset();
  fsMock.mkdir.mockReset().mockResolvedValue(undefined);
  fsMock.lstat.mockReset().mockResolvedValue(PRIVATE_DIR_STAT);
  fsMock.readdir.mockReset().mockResolvedValue([FILE_ENTRY("model.c4")]);
  fsMock.mkdtemp.mockReset().mockResolvedValue(TMP_DIR);
  stageMock.mockReset().mockResolvedValue(STAGED_OK);
  fsMock.readFile.mockReset().mockResolvedValue(VALID_MODEL);
  fsMock.copyFile.mockReset().mockResolvedValue(undefined);
  fsMock.rename.mockReset().mockResolvedValue(undefined);
  fsMock.writeFile.mockReset().mockResolvedValue(undefined);
  fsMock.rm.mockReset().mockResolvedValue(undefined);
  vi.useRealTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

// #8623: the render takes an injected stage function, never a workspace path.
// The fake stage writes nothing (fs is mocked); it reports what it staged.
const STAGED_OK = { ok: true as const, paths: ["model.c4"], sourceKey: "model.c4\0abc" };
const PRIVATE_DIR_STAT = {
  isDirectory: () => true,
  isSymbolicLink: () => false,
  uid: typeof process.getuid === "function" ? process.getuid() : 0,
};
const FILE_ENTRY = (name: string) => ({ name, isDirectory: () => false, isFile: () => true });
const stageMock = vi.fn<StageFn>();
const STAGE = stageMock as unknown as StageFn;
const EXPECTED_CWD = `${TMP_DIR}/src`;

describe("renderC4Model", () => {
  it("spawns the likec4 CLI in the private stage dir with -o beside it", async () => {
    const child = makeChild();
    spawnThenEmit(child, () => child.emit("close", 0, null));
    const p = renderC4Model(STAGE);
    const res = await p;
    expect(res.ok).toBe(true);

    const [bin, args, opts] = lastSpawn();
    expect(typeof bin).toBe("string");
    expect(bin.length).toBeGreaterThan(0);
    // argv is fixed except the `-o` target, which is now the process-temp path
    // (NOT the literal model.likec4.json in the diagrams dir) so an invalid
    // export can't clobber the good model.
    expect(args[0]).toBe("export");
    expect(args[1]).toBe("json");
    expect(args[2]).toBe("-o");
    expect(args[3]).toBe(`${TMP_DIR}/model.likec4.json`);
    // The output sits BESIDE the stage dir, never inside likec4's input.
    expect(args[3].startsWith(`${EXPECTED_CWD}/`)).toBe(false);
    expect(args[4]).toBe(".");
    // cwd is the private stage dir the stage function was handed — never a
    // workspace path (#8623).
    expect(opts.cwd).toBe(EXPECTED_CWD);
    expect(stageMock).toHaveBeenCalledTimes(1);
    expect(stageMock.mock.calls[0][0]).toBe(EXPECTED_CWD);
    expect(stageMock.mock.calls[0][1]).toBeInstanceOf(AbortSignal);
    // The mkdtemp parent is the server-private staging root, not os.tmpdir().
    const root = String(fsMock.mkdtemp.mock.calls[0][0]);
    expect(root.endsWith("/c4-render-")).toBe(true);
    expect(root.startsWith(tmpdir())).toBe(false);
    // scoped env: the allow-list keys are present (HOME is load-bearing for
    // npm-global bin resolution) and no secret leaks through.
    const env = opts.env as Record<string, string>;
    expect(Object.keys(env)).toEqual(
      expect.arrayContaining(["PATH", "HOME"]),
    );
    // HOME is the private per-render dir, never the server's (node executes
    // $HOME/.node_modules fallbacks; likec4 keeps a store under $HOME/.config).
    expect(env.HOME).toBe(TMP_DIR);
    // Only allow-list keys — nothing outside PATH/LANG/LC_ALL/HOME/TMPDIR.
    const ALLOWED = new Set(["PATH", "LANG", "LC_ALL", "HOME", "TMPDIR"]);
    expect(Object.keys(env).every((k) => ALLOWED.has(k))).toBe(true);
    expect(env).not.toHaveProperty("SUPABASE_SERVICE_ROLE_KEY");
  });

  it("returns the validated temp model as `json` and NEVER writes the tracked path on a non-empty export", async () => {
    const child = makeChild();
    fsMock.readFile.mockResolvedValue(VALID_MODEL);
    spawnThenEmit(child, () => child.emit("close", 0, null));
    const p = renderC4Model(STAGE);
    const res = await p;
    expect(res.ok).toBe(true);
    // The validated bytes are RETURNED in the canonical on-disk format (one
    // value per line, view hashes blanked — #8542), byte-identical to what the
    // repo and plugin writers emit through the same module, so the app never
    // reformats a file another writer produced.
    if (res.ok) {
      expect(res.json).toBe(canonicalizeC4Model(VALID_MODEL));
      // Pinned literal, independent of the module under test.
      expect(res.json).toBe(
        '{\n"elements": {\n"founder": {\n"id": "founder"\n},\n"platform": {\n"id": "platform"\n}\n},\n' +
          '"views": {\n"index": {\n"hash": ""\n},\n"context": {}\n}\n}\n',
      );
    }
    // #4976: the tracked model.likec4.json is never published onto — the render
    // produces only a process-temp artifact. No copy/rename/write onto any path.
    expect(fsMock.copyFile).not.toHaveBeenCalled();
    expect(fsMock.rename).not.toHaveBeenCalled();
    expect(fsMock.writeFile).not.toHaveBeenCalled();
    // The ONLY fs mutation is the temp-dir cleanup (proves temp-only lifecycle).
    expect(fsMock.rm).toHaveBeenCalledWith(
      TMP_DIR,
      expect.objectContaining({ recursive: true, force: true }),
    );
  });

  it("treats a non-object `elements` (untrusted CLI output) as empty_model — no clobber", async () => {
    const child = makeChild();
    // A non-empty STRING would make a bare Object.keys(elements) non-zero.
    fsMock.readFile.mockResolvedValue(JSON.stringify({ elements: "oops" }));
    spawnThenEmit(child, () => child.emit("close", 0, null));
    const res = await renderC4Model(STAGE);
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.reason).toBe("empty_model");
    // No `json` on a failed render → the writer can never commit a bad model.
    expect(Object.prototype.hasOwnProperty.call(res, "json")).toBe(false);
    expect(fsMock.copyFile).not.toHaveBeenCalled();
    expect(fsMock.rename).not.toHaveBeenCalled();
  });

  it("maps a canonicalize failure to io_error and returns no json", async () => {
    // V8 parses deep nesting iteratively but stringifies recursively, so a
    // model that passes the elements gate can still fail to canonicalize.
    const child = makeChild();
    const deep = "[".repeat(20000) + "]".repeat(20000);
    fsMock.readFile.mockResolvedValue(`{"elements":{"a":{"id":"a","x":${deep}}},"views":{}}`);
    spawnThenEmit(child, () => child.emit("close", 0, null));
    const res = await renderC4Model(STAGE);
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.reason).toBe("io_error");
      expect(res.detail).toContain("canonicalize failed");
    }
    expect(Object.prototype.hasOwnProperty.call(res, "json")).toBe(false);
  });

  it("treats an empty-elements export (exit 0) as empty_model and does NOT copy", async () => {
    const child = makeChild();
    fsMock.readFile.mockResolvedValue(EMPTY_MODEL);
    spawnThenEmit(child, () => {
      // likec4 prints validation errors to stderr but still exits 0.
      child.stderr.emit(
        "data",
        Buffer.from(
          "Line 135: Could not resolve reference to ElementKind named 'container'.\n",
        ),
      );
      child.emit("close", 0, null);
    });
    const p = renderC4Model(STAGE);
    const res = await p;
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.reason).toBe("empty_model");
      // The captured stderr is the diagnostic (gate is on element count, not
      // on stderr substring).
      expect(res.detail).toContain("Could not resolve reference");
    }
    // No committable bytes leak out of a failed render.
    expect(Object.prototype.hasOwnProperty.call(res, "json")).toBe(false);
    // The real model.likec4.json was NEVER overwritten with the empty export.
    expect(fsMock.copyFile).not.toHaveBeenCalled();
    // Temp dir still cleaned.
    expect(fsMock.rm).toHaveBeenCalledWith(
      TMP_DIR,
      expect.objectContaining({ recursive: true, force: true }),
    );
  });

  it("treats a non-JSON / truncated temp write as empty_model (no throw)", async () => {
    const child = makeChild();
    fsMock.readFile.mockResolvedValue("{not json");
    spawnThenEmit(child, () => child.emit("close", 0, null));
    const p = renderC4Model(STAGE);
    const res = await p;
    expect(res.ok).toBe(false);
    if (!res.ok) {
      // A parse failure is OUR io problem, not the user's source.
      expect(res.reason).toBe("io_error");
      expect(res.detail).toContain("parse failed");
    }
    expect(Object.prototype.hasOwnProperty.call(res, "json")).toBe(false);
    expect(fsMock.copyFile).not.toHaveBeenCalled();
  });

  it("returns io_error when mkdtemp fails", async () => {
    fsMock.mkdtemp.mockRejectedValue(new Error("ENOSPC"));
    const child = makeChild();
    spawnMock.mockImplementation(() => child);
    const res = await renderC4Model(STAGE);
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.reason).toBe("io_error");
      expect(res.detail).toBe("staging root unavailable");
    }
    // Never even spawned.
    expect(spawnMock).not.toHaveBeenCalled();
  });

  it("returns non_zero_exit with sanitized, truncated stderr", async () => {
    const child = makeChild();
    spawnThenEmit(child, () => {
      child.stderr.emit("data", Buffer.from("parse error\x1b[2J\n"));
      child.emit("close", 1, null);
    });
    const p = renderC4Model(STAGE);
    const res = await p;
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.reason).toBe("non_zero_exit");
      expect(res.detail).toContain("exit=1");
      // control chars sanitized
      expect(res.detail).not.toContain("\x1b");
    }
    // Non-zero exit never copies onto the real model.
    expect(fsMock.copyFile).not.toHaveBeenCalled();
  });

  it("returns spawn_error when the CLI binary is missing (ENOENT)", async () => {
    const child = makeChild();
    spawnThenEmit(child, () =>
      child.emit("error", Object.assign(new Error("spawn likec4 ENOENT"), { code: "ENOENT" })),
    );
    const p = renderC4Model(STAGE);
    const res = await p;
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.reason).toBe("spawn_error");
    expect(fsMock.copyFile).not.toHaveBeenCalled();
  });

  it("does NOT kill a healthy render before the 25s budget, then SIGKILLs past it", async () => {
    vi.useFakeTimers();
    const child = makeChild();
    spawnMock.mockImplementation(() => child);
    const p = renderC4Model(STAGE);
    // Just under the budget: the timer must NOT have fired — a healthy cold
    // render that finishes at 24.9s must not be killed.
    await vi.advanceTimersByTimeAsync(24_999);
    expect(child.kill).not.toHaveBeenCalled();
    // Cross the boundary: SIGKILL fires and the result is a timeout.
    await vi.advanceTimersByTimeAsync(2);
    const res = await p;
    expect(child.kill).toHaveBeenCalledWith("SIGKILL");
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.reason).toBe("timeout");
    // Even on timeout the temp dir is cleaned (finally), never copied/renamed.
    expect(fsMock.rm).toHaveBeenCalledWith(
      TMP_DIR,
      expect.objectContaining({ recursive: true, force: true }),
    );
    expect(fsMock.copyFile).not.toHaveBeenCalled();
  });
  it("maps an unsafe_source stage refusal through, never spawning", async () => {
    stageMock.mockResolvedValue({
      ok: false,
      reason: "unsafe_source",
      refusalClass: "likec4-config",
      path: "likec4.config.mjs",
      more: 0,
    });
    const res = await renderC4Model(STAGE);
    expect(res).toEqual({
      ok: false,
      reason: "unsafe_source",
      refusalClass: "likec4-config",
      path: "likec4.config.mjs",
      more: 0,
      phase: "stage",
    });
    expect(spawnMock).not.toHaveBeenCalled();
    expect(fsMock.rm).toHaveBeenCalledWith(TMP_DIR, expect.objectContaining({ recursive: true }));
  });

  it("maps a stage io_error / a throwing stage to io_error phase=stage, never spawning", async () => {
    stageMock.mockResolvedValue({ ok: false, reason: "io_error", detail: "fetch: rate-limited" });
    expect(await renderC4Model(STAGE)).toEqual({
      ok: false,
      reason: "io_error",
      detail: "fetch: rate-limited",
      phase: "stage",
    });
    stageMock.mockRejectedValue(new Error("boom"));
    const res = await renderC4Model(STAGE);
    expect(res).toMatchObject({ ok: false, reason: "io_error", phase: "stage" });
    expect(spawnMock).not.toHaveBeenCalled();
  });

  it("aborts a stalled stage at the deadline: timeout 'stage: deadline', signal aborted, no spawn", async () => {
    vi.useFakeTimers();
    let seen: AbortSignal | undefined;
    stageMock.mockImplementation((_d, signal) => {
      seen = signal;
      return new Promise(() => {});
    });
    const p = renderC4Model(STAGE);
    await vi.advanceTimersByTimeAsync(STAGE_DEADLINE_MS + 1);
    // The stalled stage never settles, so cleanup waits out its bounded grace.
    await vi.advanceTimersByTimeAsync(2_001);
    expect(await p).toEqual({ ok: false, reason: "timeout", detail: "stage: deadline", phase: "stage" });
    expect(seen?.aborted).toBe(true);
    expect(spawnMock).not.toHaveBeenCalled();
    expect(fsMock.rm).toHaveBeenCalledWith(TMP_DIR, expect.objectContaining({ recursive: true }));
  });

  it("row 10: stages that stall do not hold render slots (stall POOL_SIZE=2, a third still spawns promptly)", async () => {
    const release: Array<(r: Awaited<ReturnType<StageFn>>) => void> = [];
    stageMock.mockImplementation(
      () => new Promise((resolve) => release.push(resolve)),
    );
    const stalled = [renderC4Model(STAGE), renderC4Model(STAGE)];
    await vi.waitFor(() => expect(release.length).toBe(2));
    stageMock.mockResolvedValue(STAGED_OK);
    const child = makeChild();
    spawnThenEmit(child, () => child.emit("close", 0, null));
    // Bounded well below the 10 s stage deadline: if staging held a slot, the
    // third render could only spawn after the deadline freed one.
    const third = await Promise.race([
      renderC4Model(STAGE),
      new Promise<"blocked">((r) => setTimeout(() => r("blocked"), 1_000)),
    ]);
    expect(third).not.toBe("blocked");
    expect(spawnMock).toHaveBeenCalledTimes(1);
    for (const r of release) r({ ok: false, reason: "io_error", detail: "released" });
    await Promise.all(stalled);
  });

  it("refuses to render when the stage changed between staging and spawn (extra file / symlink)", async () => {
    for (const entries of [
      [FILE_ENTRY("model.c4"), FILE_ENTRY("likec4.config.mjs")],
      [{ name: "model.c4", isDirectory: () => false, isFile: () => false }],
      [],
    ]) {
      fsMock.readdir.mockResolvedValue(entries);
      const res = await renderC4Model(STAGE);
      expect(res).toEqual({ ok: false, reason: "io_error", detail: "stage: contents changed before render", phase: "stage" });
    }
    expect(spawnMock).not.toHaveBeenCalled();
  });

  it("refuses a staging root that is a symlink or owned by someone else", async () => {
    for (const st of [
      { ...PRIVATE_DIR_STAT, isSymbolicLink: () => true, isDirectory: () => false },
      { ...PRIVATE_DIR_STAT, uid: PRIVATE_DIR_STAT.uid + 1 },
    ]) {
      fsMock.lstat.mockResolvedValue(st);
      const res = await renderC4Model(STAGE);
      expect(res).toEqual({ ok: false, reason: "io_error", detail: "staging root unavailable", phase: "stage" });
    }
    expect(stageMock).not.toHaveBeenCalled();
  });

  it("replaces the random stage path inside rendered file:// URIs with a stable root", async () => {
    const child = makeChild();
    fsMock.readFile.mockResolvedValue(
      JSON.stringify({ elements: { a: { id: "a", icon: `file://${TMP_DIR}/src/icons/a.svg` } }, views: {} }),
    );
    spawnThenEmit(child, () => child.emit("close", 0, null));
    const res = await renderC4Model(STAGE);
    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(res.json).toContain("file:///c4-sources/icons/a.svg");
      expect(res.json).not.toContain(TMP_DIR);
    }
  });

  it("sweeps stage dirs a crashed render left behind (older than 10 min), leaving fresh ones", async () => {
    const child = makeChild();
    spawnThenEmit(child, () => child.emit("close", 0, null));
    const dirEntry = (name: string) => ({ name, isDirectory: () => true, isFile: () => false });
    fsMock.readdir.mockImplementation(async (p: string) =>
      String(p).endsWith("/src") ? [FILE_ENTRY("model.c4")] : [dirEntry("c4-render-old"), dirEntry("c4-render-new"), dirEntry("other")],
    );
    fsMock.lstat.mockImplementation(async (p: string) =>
      String(p).endsWith("c4-render-old")
        ? { ...PRIVATE_DIR_STAT, mtimeMs: Date.now() - 11 * 60_000 }
        : { ...PRIVATE_DIR_STAT, mtimeMs: Date.now() },
    );
    const res = await renderC4Model(STAGE);
    expect(res.ok).toBe(true);
    const removed = fsMock.rm.mock.calls.map((c) => String(c[0]));
    expect(removed.some((p) => p.endsWith("/c4-render-old"))).toBe(true);
    expect(removed.some((p) => p.endsWith("/c4-render-new"))).toBe(false);
    expect(removed.some((p) => p.endsWith("/other"))).toBe(false);
  });
});
