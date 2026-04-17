import { describe, it, expect, vi, beforeEach } from "vitest";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";

const { mockSpawn } = vi.hoisted(() => ({ mockSpawn: vi.fn() }));
vi.mock("node:child_process", () => ({ spawn: mockSpawn }));

import { linearizePdf } from "../server/pdf-linearize";

type FakeChildOpts = {
  stdoutChunks?: Buffer[];
  stderrChunks?: Buffer[];
  exitCode?: number | null;
  exitSignal?: NodeJS.Signals | null;
  spawnError?: Error;
  holdStdinOpen?: boolean;
};

function fakeChild(opts: FakeChildOpts) {
  const child = new EventEmitter() as EventEmitter & {
    stdin: PassThrough;
    stdout: PassThrough;
    stderr: PassThrough;
    kill: ReturnType<typeof vi.fn>;
  };
  child.stdin = new PassThrough();
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.kill = vi.fn();

  if (opts.spawnError) {
    queueMicrotask(() => child.emit("error", opts.spawnError!));
    return child;
  }

  queueMicrotask(() => {
    for (const c of opts.stdoutChunks ?? []) child.stdout.write(c);
    for (const c of opts.stderrChunks ?? []) child.stderr.write(c);
    child.stdout.end();
    child.stderr.end();
    if (!opts.holdStdinOpen) {
      queueMicrotask(() =>
        child.emit(
          "close",
          opts.exitCode === undefined ? 0 : opts.exitCode,
          opts.exitSignal ?? null,
        ),
      );
    }
  });

  return child;
}

beforeEach(() => mockSpawn.mockReset());

describe("linearizePdf", () => {
  it("returns ok=true with linearized bytes on exit 0", async () => {
    const linearized = Buffer.from("%PDF-1.7-linearized");
    mockSpawn.mockReturnValue(
      fakeChild({ stdoutChunks: [linearized], exitCode: 0 }),
    );
    const result = await linearizePdf(Buffer.from("%PDF-1.7-original"));
    expect(result).toEqual({ ok: true, buffer: linearized });
  });

  it("returns ok=false reason=non_zero_exit on non-zero exit", async () => {
    mockSpawn.mockReturnValue(
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
  });

  it("returns ok=false reason=non_zero_exit with signal detail when killed by OS (code=null)", async () => {
    mockSpawn.mockReturnValue(
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
    mockSpawn.mockReturnValue(fakeChild({ spawnError: err }));
    const result = await linearizePdf(Buffer.from("%PDF"));
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("spawn_error");
  });

  it("kills the subprocess and returns reason=timeout when qpdf never closes", async () => {
    vi.useFakeTimers();
    const child = fakeChild({ holdStdinOpen: true });
    mockSpawn.mockReturnValue(child);
    const p = linearizePdf(Buffer.from("%PDF"));
    await vi.advanceTimersByTimeAsync(10_001);
    const result = await p;
    vi.useRealTimers();
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("timeout");
    expect(child.kill).toHaveBeenCalledWith("SIGKILL");
  });
});
