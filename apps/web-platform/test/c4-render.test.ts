import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { EventEmitter } from "node:events";

// Mock child_process.spawn so we drive the CLI lifecycle deterministically.
const spawnMock = vi.hoisted(() => vi.fn());
vi.mock("node:child_process", () => ({ spawn: spawnMock }));

// Mock node:fs/promises so renderC4Model's temp-dir lifecycle (mkdtemp →
// readFile(temp) → rm) is deterministic. The fake `readFile` returns whatever
// model JSON the test stages — that string is what renderC4Model now RETURNS as
// `json` (#4976: off-tree render, no copy/rename onto the tracked path).
// `copyFile`/`rename` are kept as spies so a regression that re-introduces an
// in-place publish is caught by the `.not.toHaveBeenCalled()` assertions below;
// the source no longer imports them.
const fsMock = vi.hoisted(() => ({
  mkdtemp: vi.fn(),
  readFile: vi.fn(),
  copyFile: vi.fn(),
  rename: vi.fn(),
  rm: vi.fn(),
}));
vi.mock("node:fs/promises", () => fsMock);

import { renderC4Model } from "@/server/c4-render";

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
  views: { index: {} },
});
// likec4 exits 0 but emits this when spec.c4 is missing (the bug class).
const EMPTY_MODEL = JSON.stringify({ elements: {}, views: {} });

beforeEach(() => {
  spawnMock.mockReset();
  fsMock.mkdtemp.mockReset().mockResolvedValue(TMP_DIR);
  fsMock.readFile.mockReset().mockResolvedValue(VALID_MODEL);
  fsMock.copyFile.mockReset().mockResolvedValue(undefined);
  fsMock.rename.mockReset().mockResolvedValue(undefined);
  fsMock.rm.mockReset().mockResolvedValue(undefined);
  vi.useRealTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

const WS = "/workspaces/ws-1";
const EXPECTED_CWD = "/workspaces/ws-1/knowledge-base/engineering/architecture/diagrams";

describe("renderC4Model", () => {
  it("spawns the likec4 CLI into a temp -o path in the scope-guarded diagrams dir", async () => {
    const child = makeChild();
    spawnThenEmit(child, () => child.emit("close", 0, null));
    const p = renderC4Model(WS);
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
    expect(args[3].startsWith(EXPECTED_CWD)).toBe(false);
    expect(args[4]).toBe(".");
    // cwd is the constant-derived diagrams dir, never a user filename.
    expect(opts.cwd).toBe(EXPECTED_CWD);
    // scoped env: the allow-list keys are present (HOME is load-bearing for
    // npm-global bin resolution) and no secret leaks through.
    const env = opts.env as Record<string, string>;
    expect(Object.keys(env)).toEqual(
      expect.arrayContaining(["PATH", "HOME"]),
    );
    // Only allow-list keys — nothing outside PATH/LANG/LC_ALL/HOME/TMPDIR.
    const ALLOWED = new Set(["PATH", "LANG", "LC_ALL", "HOME", "TMPDIR"]);
    expect(Object.keys(env).every((k) => ALLOWED.has(k))).toBe(true);
    expect(env).not.toHaveProperty("SUPABASE_SERVICE_ROLE_KEY");
  });

  it("returns the validated temp model as `json` and NEVER writes the tracked path on a non-empty export", async () => {
    const child = makeChild();
    fsMock.readFile.mockResolvedValue(VALID_MODEL);
    spawnThenEmit(child, () => child.emit("close", 0, null));
    const p = renderC4Model(WS);
    const res = await p;
    expect(res.ok).toBe(true);
    // The validated bytes are RETURNED verbatim (byte-identical to the read), so
    // the writer commits exactly what likec4 produced — never re-stringified.
    if (res.ok) expect(res.json).toBe(VALID_MODEL);
    // #4976: the tracked model.likec4.json is never published onto — the render
    // produces only a process-temp artifact. No copy/rename onto any path.
    expect(fsMock.copyFile).not.toHaveBeenCalled();
    expect(fsMock.rename).not.toHaveBeenCalled();
    // Temp dir always cleaned.
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
    const res = await renderC4Model(WS);
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.reason).toBe("empty_model");
    // No `json` on a failed render → the writer can never commit a bad model.
    expect(Object.prototype.hasOwnProperty.call(res, "json")).toBe(false);
    expect(fsMock.copyFile).not.toHaveBeenCalled();
    expect(fsMock.rename).not.toHaveBeenCalled();
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
    const p = renderC4Model(WS);
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
    const p = renderC4Model(WS);
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
    const res = await renderC4Model(WS);
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.reason).toBe("io_error");
      expect(res.detail).toBe("mkdtemp failed");
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
    const p = renderC4Model(WS);
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
    const p = renderC4Model(WS);
    const res = await p;
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.reason).toBe("spawn_error");
    expect(fsMock.copyFile).not.toHaveBeenCalled();
  });

  it("does NOT kill a healthy render before the 25s budget, then SIGKILLs past it", async () => {
    vi.useFakeTimers();
    const child = makeChild();
    spawnMock.mockImplementation(() => child);
    const p = renderC4Model(WS);
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
});
