import { describe, it, expect, vi, beforeEach } from "vitest";
import { EventEmitter } from "node:events";

const { mockSpawn, mockWriteFile, mockReadFile, mockMkdtemp, mockRm } =
  vi.hoisted(() => ({
    mockSpawn: vi.fn(),
    mockWriteFile: vi.fn(),
    mockReadFile: vi.fn(),
    mockMkdtemp: vi.fn(),
    mockRm: vi.fn(),
  }));

vi.mock("node:child_process", () => ({ spawn: mockSpawn }));
vi.mock("node:fs/promises", () => ({
  writeFile: mockWriteFile,
  readFile: mockReadFile,
  mkdtemp: mockMkdtemp,
  rm: mockRm,
}));

import { linearizePdf } from "../server/pdf-linearize";

type FakeChildOpts = {
  stderrChunks?: Buffer[];
  exitCode?: number | null;
  exitSignal?: NodeJS.Signals | null;
  spawnError?: Error;
  holdOpen?: boolean;
};

// mockImplementation (not mockReturnValue) is required: queueMicrotask inside
// fakeChild must run AFTER the SUT attaches listeners, so fakeChild must be
// constructed lazily on each spawn() call.
function fakeChild(opts: FakeChildOpts) {
  const stderr = new EventEmitter();
  const child = new EventEmitter() as EventEmitter & {
    stderr: EventEmitter;
    kill: ReturnType<typeof vi.fn>;
  };
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

const MKDTEMP_DIR = "/tmp/pdf-linearize-abc123";

beforeEach(() => {
  mockSpawn.mockReset();
  mockWriteFile.mockReset().mockResolvedValue(undefined);
  mockReadFile.mockReset();
  mockMkdtemp.mockReset().mockResolvedValue(MKDTEMP_DIR);
  mockRm.mockReset().mockResolvedValue(undefined);
});

describe("linearizePdf", () => {
  it("returns ok=true with linearized bytes on exit 0", async () => {
    const linearized = Buffer.from("%PDF-1.7-linearized");
    mockSpawn.mockImplementation(() => fakeChild({ exitCode: 0 }));
    mockReadFile.mockResolvedValue(linearized);

    const result = await linearizePdf(Buffer.from("%PDF-1.7-original"));

    expect(result).toEqual({ ok: true, buffer: linearized });
    expect(mockSpawn).toHaveBeenCalledTimes(1);
    const [binary, args] = mockSpawn.mock.calls[0];
    expect(binary).toBe("qpdf");
    expect(args).toEqual(["--linearize", `${MKDTEMP_DIR}/in.pdf`, `${MKDTEMP_DIR}/out.pdf`]);
    expect(mockRm).toHaveBeenCalledWith(MKDTEMP_DIR, {
      recursive: true,
      force: true,
    });
  });

  it("env passed to spawn is an allowlist, not a process.env spread", async () => {
    process.env.SOLEUR_LEAK_PROBE = "leak-me";
    try {
      mockSpawn.mockImplementation(() => fakeChild({ exitCode: 0 }));
      mockReadFile.mockResolvedValue(Buffer.from("x"));

      await linearizePdf(Buffer.from("%PDF"));

      const opts = mockSpawn.mock.calls[0][2] as {
        env: Record<string, string | undefined>;
      };
      expect(opts.env.SOLEUR_LEAK_PROBE).toBeUndefined();
      expect(opts.env.PATH).toBe(process.env.PATH);
      for (const key of Object.keys(opts.env)) {
        expect(["PATH", "LANG", "LC_ALL", "TMPDIR"]).toContain(key);
      }
    } finally {
      delete process.env.SOLEUR_LEAK_PROBE;
    }
  });

  it("returns ok=false reason=non_zero_exit on non-zero exit with sanitized stderr", async () => {
    // Include a line separator that would otherwise enable log forgery.
    const stderr = Buffer.from("qpdf: encrypted\u2028forged=true");
    mockSpawn.mockImplementation(() =>
      fakeChild({ exitCode: 3, stderrChunks: [stderr] }),
    );

    const result = await linearizePdf(Buffer.from("%PDF-encrypted"));

    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("non_zero_exit");
      expect(result.detail).toMatch(/encrypted/);
      expect(result.detail).not.toMatch(/\u2028/);
    }
    expect(mockReadFile).not.toHaveBeenCalled();
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

  it("returns ok=false reason=io_error when writeFile fails", async () => {
    mockWriteFile.mockRejectedValue(new Error("ENOSPC"));
    const result = await linearizePdf(Buffer.from("%PDF"));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("io_error");
      expect(result.detail).toMatch(/ENOSPC/);
    }
    expect(mockSpawn).not.toHaveBeenCalled();
  });

  it("returns ok=false reason=io_error when qpdf exit 0 but output is empty", async () => {
    mockSpawn.mockImplementation(() => fakeChild({ exitCode: 0 }));
    mockReadFile.mockResolvedValue(Buffer.alloc(0));

    const result = await linearizePdf(Buffer.from("%PDF"));
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.reason).toBe("io_error");
      expect(result.detail).toMatch(/empty/);
    }
  });

  it("returns ok=false reason=skip_signed without invoking qpdf for signed PDFs", async () => {
    const signed = Buffer.from(
      "%PDF-1.4\n1 0 obj<</Type /Sig /Contents <abcd>>>>endobj\n%%EOF",
    );
    const result = await linearizePdf(signed);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("skip_signed");
    expect(mockSpawn).not.toHaveBeenCalled();
    // No tempdir created for skipped inputs.
    expect(mockMkdtemp).not.toHaveBeenCalled();
  });

  it("returns ok=false reason=skip_signed for PDFs with /ByteRange", async () => {
    const signed = Buffer.from(
      "%PDF-1.4\n/ByteRange [0 100 200 50]\n%%EOF",
    );
    const result = await linearizePdf(signed);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("skip_signed");
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

  // Concurrency gate: closes #2472. Default POOL_SIZE=2 (env-overridable via
  // PDF_LINEARIZE_CONCURRENCY, tested in the separate describe block below).
  it("caps concurrent qpdf subprocesses to POOL_SIZE (2) and queues the rest", async () => {
    vi.useFakeTimers();
    const children: Array<ReturnType<typeof fakeChild>> = [];
    mockSpawn.mockImplementation(() => {
      const c = fakeChild({ holdOpen: true });
      children.push(c);
      return c;
    });
    mockReadFile.mockResolvedValue(Buffer.from("%PDF-out"));

    const p1 = linearizePdf(Buffer.from("%PDF-1"));
    const p2 = linearizePdf(Buffer.from("%PDF-2"));
    const p3 = linearizePdf(Buffer.from("%PDF-3"));

    await vi.advanceTimersByTimeAsync(0);
    expect(mockSpawn).toHaveBeenCalledTimes(2); // p3 queued behind the gate

    // Release slot 0 → p3 should enter the gate.
    children[0].emit("close", 0, null);
    await vi.advanceTimersByTimeAsync(0);
    expect(mockSpawn).toHaveBeenCalledTimes(3);

    children[1].emit("close", 0, null);
    children[2].emit("close", 0, null);
    const results = await Promise.all([p1, p2, p3]);
    vi.useRealTimers();
    expect(results.every((r) => r.ok)).toBe(true);
  });

  // Release-discipline tests (Tests 2-4). Each proves a specific error branch
  // inside the gated block still calls release(), so a queued call can proceed.
  it("releases slot on timeout so a queued call can proceed", async () => {
    vi.useFakeTimers();
    mockSpawn.mockImplementation(() => fakeChild({ holdOpen: true }));

    const p1 = linearizePdf(Buffer.from("%PDF-1"));
    const p2 = linearizePdf(Buffer.from("%PDF-2"));
    const p3 = linearizePdf(Buffer.from("%PDF-3"));

    await vi.advanceTimersByTimeAsync(0);
    expect(mockSpawn).toHaveBeenCalledTimes(2);

    // Fire the 10s qpdf timeout for both in-flight subprocesses. Their slots
    // must release via finally, letting p3 enter the gate.
    await vi.advanceTimersByTimeAsync(10_001);
    await vi.advanceTimersByTimeAsync(0);
    expect(mockSpawn).toHaveBeenCalledTimes(3);

    // Drain the pending promises.
    await vi.advanceTimersByTimeAsync(10_001);
    await Promise.all([p1, p2, p3]);
    vi.useRealTimers();
  });

  it("releases slot on spawn_error so a queued call can proceed", async () => {
    vi.useFakeTimers();
    const children: Array<ReturnType<typeof fakeChild>> = [];
    mockSpawn.mockImplementation(() => {
      const c = fakeChild({ holdOpen: true });
      children.push(c);
      return c;
    });
    mockReadFile.mockResolvedValue(Buffer.from("%PDF-out"));

    const p1 = linearizePdf(Buffer.from("%PDF-1"));
    const p2 = linearizePdf(Buffer.from("%PDF-2"));
    const p3 = linearizePdf(Buffer.from("%PDF-3"));

    await vi.advanceTimersByTimeAsync(0);
    expect(mockSpawn).toHaveBeenCalledTimes(2); // p3 queued

    // Synthesize an ENOENT-style spawn error on slot 0. Release must fire via
    // finally so p3 enters the gate.
    (children[0] as EventEmitter).emit("error", new Error("ENOENT"));
    await vi.advanceTimersByTimeAsync(0);
    expect(mockSpawn).toHaveBeenCalledTimes(3);

    const r1 = await p1;
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.reason).toBe("spawn_error");

    children[1].emit("close", 0, null);
    children[2].emit("close", 0, null);
    await Promise.all([p2, p3]);
    vi.useRealTimers();
  });

  it("releases slot on non_zero_exit so a queued call can proceed", async () => {
    vi.useFakeTimers();
    const children: Array<ReturnType<typeof fakeChild>> = [];
    mockSpawn.mockImplementation(() => {
      const c = fakeChild({ holdOpen: true });
      children.push(c);
      return c;
    });
    mockReadFile.mockResolvedValue(Buffer.from("%PDF-out"));

    const p1 = linearizePdf(Buffer.from("%PDF-1"));
    const p2 = linearizePdf(Buffer.from("%PDF-2"));
    const p3 = linearizePdf(Buffer.from("%PDF-3"));

    await vi.advanceTimersByTimeAsync(0);
    expect(mockSpawn).toHaveBeenCalledTimes(2); // p3 queued

    // Slot 0 exits non-zero. Release must fire via finally so p3 enters.
    children[0].emit("close", 3, null);
    await vi.advanceTimersByTimeAsync(0);
    expect(mockSpawn).toHaveBeenCalledTimes(3);

    const r1 = await p1;
    expect(r1.ok).toBe(false);
    if (!r1.ok) expect(r1.reason).toBe("non_zero_exit");

    children[1].emit("close", 0, null);
    children[2].emit("close", 0, null);
    await Promise.all([p2, p3]);
    vi.useRealTimers();
  });
});

// Separate describe block so vi.resetModules() + dynamic import can capture
// a fresh POOL_SIZE from PDF_LINEARIZE_CONCURRENCY. The default-pool tests
// above use the top-level static import, which binds to the original load's
// POOL_SIZE=2; this block is the only path that exercises the env override.
describe("linearizePdf POOL_SIZE env override", () => {
  it("serializes concurrent calls when PDF_LINEARIZE_CONCURRENCY=1", async () => {
    const prev = process.env.PDF_LINEARIZE_CONCURRENCY;
    process.env.PDF_LINEARIZE_CONCURRENCY = "1";
    vi.useFakeTimers();
    vi.resetModules();
    mockSpawn.mockReset();
    mockWriteFile.mockReset().mockResolvedValue(undefined);
    mockReadFile.mockReset().mockResolvedValue(Buffer.from("%PDF-out"));
    mockMkdtemp.mockReset().mockResolvedValue(MKDTEMP_DIR);
    mockRm.mockReset().mockResolvedValue(undefined);

    try {
      const mod = await import("../server/pdf-linearize");
      const children: Array<ReturnType<typeof fakeChild>> = [];
      mockSpawn.mockImplementation(() => {
        const c = fakeChild({ holdOpen: true });
        children.push(c);
        return c;
      });

      const p1 = mod.linearizePdf(Buffer.from("%PDF-1"));
      const p2 = mod.linearizePdf(Buffer.from("%PDF-2"));

      await vi.advanceTimersByTimeAsync(0);
      expect(mockSpawn).toHaveBeenCalledTimes(1); // serialized

      children[0].emit("close", 0, null);
      await vi.advanceTimersByTimeAsync(0);
      expect(mockSpawn).toHaveBeenCalledTimes(2);

      children[1].emit("close", 0, null);
      await Promise.all([p1, p2]);
    } finally {
      if (prev === undefined) delete process.env.PDF_LINEARIZE_CONCURRENCY;
      else process.env.PDF_LINEARIZE_CONCURRENCY = prev;
      vi.useRealTimers();
    }
  });
});
