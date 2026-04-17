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
});
