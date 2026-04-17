import { describe, it, expect, vi, beforeEach } from "vitest";
import { EventEmitter } from "node:events";

const { mockSpawn, mockWriteFile, mockReadFile, mockUnlink } = vi.hoisted(
  () => ({
    mockSpawn: vi.fn(),
    mockWriteFile: vi.fn(),
    mockReadFile: vi.fn(),
    mockUnlink: vi.fn(),
  }),
);

vi.mock("node:child_process", () => ({ spawn: mockSpawn }));
vi.mock("node:fs/promises", () => ({
  writeFile: mockWriteFile,
  readFile: mockReadFile,
  unlink: mockUnlink,
}));

import { linearizePdf } from "../server/pdf-linearize";

type FakeChildOpts = {
  stderrChunks?: Buffer[];
  exitCode?: number | null;
  exitSignal?: NodeJS.Signals | null;
  spawnError?: Error;
  holdOpen?: boolean;
};

function fakeChild(opts: FakeChildOpts) {
  const stdout = new EventEmitter();
  const stderr = new EventEmitter();
  const child = new EventEmitter() as EventEmitter & {
    stdout: EventEmitter;
    stderr: EventEmitter;
    kill: ReturnType<typeof vi.fn>;
  };
  child.stdout = stdout;
  child.stderr = stderr;
  child.kill = vi.fn();

  if (opts.spawnError) {
    queueMicrotask(() => child.emit("error", opts.spawnError!));
    return child;
  }

  queueMicrotask(() => {
    for (const c of opts.stderrChunks ?? []) stderr.emit("data", c);
    if (!opts.holdOpen) {
      child.emit(
        "close",
        opts.exitCode === undefined ? 0 : opts.exitCode,
        opts.exitSignal ?? null,
      );
    }
  });

  return child;
}

beforeEach(() => {
  mockSpawn.mockReset();
  mockWriteFile.mockReset().mockResolvedValue(undefined);
  mockReadFile.mockReset();
  mockUnlink.mockReset().mockResolvedValue(undefined);
});

describe("linearizePdf", () => {
  it("returns ok=true with linearized bytes on exit 0", async () => {
    const linearized = Buffer.from("%PDF-1.7-linearized");
    mockSpawn.mockImplementation(() => fakeChild({ exitCode: 0 }));
    mockReadFile.mockResolvedValue(linearized);

    const result = await linearizePdf(Buffer.from("%PDF-1.7-original"));

    expect(result).toEqual({ ok: true, buffer: linearized });
    // spawn is called with qpdf --linearize <inPath> <outPath>
    expect(mockSpawn).toHaveBeenCalledTimes(1);
    const [binary, args] = mockSpawn.mock.calls[0];
    expect(binary).toBe("qpdf");
    expect(args[0]).toBe("--linearize");
    expect(args[1]).toMatch(/pdf-linearize-in-[0-9a-f]+\.pdf$/);
    expect(args[2]).toMatch(/pdf-linearize-out-[0-9a-f]+\.pdf$/);
    // Env passed to spawn is an allowlist — no full process.env spread
    const opts = mockSpawn.mock.calls[0][2] as { env: Record<string, unknown> };
    expect(Object.keys(opts.env).sort()).toEqual(
      Object.keys(opts.env)
        .filter((k) => ["PATH", "HOME", "LANG", "LC_ALL", "TMPDIR"].includes(k))
        .sort(),
    );
    // Tempfiles cleaned up
    expect(mockUnlink).toHaveBeenCalledTimes(2);
  });

  it("returns ok=false reason=non_zero_exit on non-zero exit", async () => {
    mockSpawn.mockImplementation(() =>
      fakeChild({
        exitCode: 3,
        stderrChunks: [Buffer.from("qpdf: file is encrypted")],
      }),
    );

    const result = await linearizePdf(Buffer.from("%PDF-encrypted"));

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("non_zero_exit");
      expect(result.detail).toMatch(/encrypted/);
    }
    // readFile never called on non-zero exit
    expect(mockReadFile).not.toHaveBeenCalled();
    // Tempfiles cleaned up even on failure
    expect(mockUnlink).toHaveBeenCalledTimes(2);
  });

  it("returns ok=false reason=non_zero_exit with signal detail when killed by OS (code=null)", async () => {
    mockSpawn.mockImplementation(() =>
      fakeChild({ exitCode: null, exitSignal: "SIGKILL" }),
    );
    const result = await linearizePdf(Buffer.from("%PDF"));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("non_zero_exit");
      expect(result.detail).toMatch(/SIGKILL/);
    }
  });

  it("returns ok=false reason=spawn_error when qpdf binary is missing", async () => {
    const err = Object.assign(new Error("ENOENT"), { code: "ENOENT" });
    mockSpawn.mockImplementation(() => fakeChild({ spawnError: err }));
    const result = await linearizePdf(Buffer.from("%PDF"));
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("spawn_error");
  });

  it("returns ok=false reason=spawn_error when writeFile fails", async () => {
    mockWriteFile.mockRejectedValue(new Error("ENOSPC"));
    const result = await linearizePdf(Buffer.from("%PDF"));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("spawn_error");
      expect(result.detail).toMatch(/ENOSPC/);
    }
    // spawn should not be invoked if writeFile failed
    expect(mockSpawn).not.toHaveBeenCalled();
  });

  it("kills the subprocess and returns reason=timeout when qpdf never closes", async () => {
    vi.useFakeTimers();
    let child!: ReturnType<typeof fakeChild>;
    mockSpawn.mockImplementation(() => {
      child = fakeChild({ holdOpen: true });
      return child;
    });
    const p = linearizePdf(Buffer.from("%PDF"));
    await vi.advanceTimersByTimeAsync(10_001);
    const result = await p;
    vi.useRealTimers();
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("timeout");
    expect(child.kill).toHaveBeenCalledWith("SIGKILL");
  });
});
