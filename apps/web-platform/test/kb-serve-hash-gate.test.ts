import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { hashBytes } from "@/server/kb-content-hash";
import { validateBinaryFile } from "@/server/kb-binary-response";
import { __resetShareHashVerdictCacheForTest } from "@/server/share-hash-verdict-cache";
import { serveBinaryWithHashGate } from "@/server/kb-serve";

const loggerStub = {
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
  debug: vi.fn(),
  trace: vi.fn(),
  fatal: vi.fn(),
  silent: vi.fn(),
  child: vi.fn(() => loggerStub),
  level: "info",
};

function logger() {
  // Cast to any for test purposes — the helper only uses info/warn/error.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return loggerStub as any;
}

function buildRequest(headers?: Record<string, string>): Request {
  return new Request("http://localhost:3000/api/shared/tok", { headers });
}

let tmpWorkspace: string;
let kbRoot: string;

beforeEach(() => {
  vi.clearAllMocks();
  __resetShareHashVerdictCacheForTest();
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "kb-hash-gate-test-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("serveBinaryWithHashGate", () => {
  it("cache miss + hash match: serves 200 with strong ETag", async () => {
    const bytes = Buffer.from("fake-png-content");
    const expectedHash = hashBytes(bytes);
    const filePath = path.join(kbRoot, "logo.png");
    fs.writeFileSync(filePath, bytes);
    const meta = await validateBinaryFile(kbRoot, "logo.png");
    if (!meta.ok) throw new Error("meta not ok");

    const res = await serveBinaryWithHashGate({
      token: "tok",
      expectedHash,
      meta,
      request: buildRequest(),
      logger: logger(),
      logContext: { token: "tok", documentPath: "logo.png" },
    });
    expect(res.status).toBe(200);
    expect(res.headers.get("ETag")).toBe(`"${expectedHash}"`);
    expect(loggerStub.info).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "shared_page_viewed",
        cached: false,
      }),
      expect.any(String),
    );
  });

  it("cache hit: serves 200 without logging mismatch, cached=true", async () => {
    const bytes = Buffer.from("cache-hit-content");
    const expectedHash = hashBytes(bytes);
    const filePath = path.join(kbRoot, "cached.png");
    fs.writeFileSync(filePath, bytes);
    const meta = await validateBinaryFile(kbRoot, "cached.png");
    if (!meta.ok) throw new Error("meta not ok");

    // Prime the cache
    await serveBinaryWithHashGate({
      token: "tok",
      expectedHash,
      meta,
      request: buildRequest(),
      logger: logger(),
      logContext: { token: "tok", documentPath: "cached.png" },
    });
    loggerStub.info.mockClear();

    const res = await serveBinaryWithHashGate({
      token: "tok",
      expectedHash,
      meta,
      request: buildRequest(),
      logger: logger(),
      logContext: { token: "tok", documentPath: "cached.png" },
    });
    expect(res.status).toBe(200);
    expect(loggerStub.info).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "shared_page_viewed",
        cached: true,
      }),
      expect.any(String),
    );
  });

  it("cache miss + hash mismatch: returns 410 content-changed", async () => {
    const bytes = Buffer.from("actual-bytes");
    const filePath = path.join(kbRoot, "mismatch.png");
    fs.writeFileSync(filePath, bytes);
    const meta = await validateBinaryFile(kbRoot, "mismatch.png");
    if (!meta.ok) throw new Error("meta not ok");

    const res = await serveBinaryWithHashGate({
      token: "tok",
      expectedHash: "deadbeef-wrong-hash",
      meta,
      request: buildRequest(),
      logger: logger(),
      logContext: { token: "tok", documentPath: "mismatch.png" },
    });
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body).toMatchObject({ code: "content-changed" });
    expect(loggerStub.info).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "shared_content_mismatch",
        kind: "binary",
      }),
      expect.any(String),
    );
  });

  it("inode drift between validate and hash: returns 410 with reason=inode-drift", async () => {
    const bytes = Buffer.from("original-bytes");
    const expectedHash = hashBytes(bytes);
    const filePath = path.join(kbRoot, "drift.png");
    fs.writeFileSync(filePath, bytes);
    const meta = await validateBinaryFile(kbRoot, "drift.png");
    if (!meta.ok) throw new Error("meta not ok");

    // Simulate inode drift: remove and recreate with different size between
    // validateBinaryFile and the hash pass inside the helper.
    fs.rmSync(filePath);
    fs.writeFileSync(filePath, Buffer.from("different-size-bytes"));

    const res = await serveBinaryWithHashGate({
      token: "tok",
      expectedHash,
      meta,
      request: buildRequest(),
      logger: logger(),
      logContext: { token: "tok", documentPath: "drift.png" },
    });
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body).toMatchObject({ code: "content-changed" });
    expect(loggerStub.info).toHaveBeenCalledWith(
      expect.objectContaining({
        event: "shared_content_mismatch",
        kind: "binary",
        reason: "inode-drift",
      }),
      expect.any(String),
    );
  });

  it("BinaryOpenError (non content-changed) during hash: returns helper status", async () => {
    const bytes = Buffer.from("hash-fail-bytes");
    const expectedHash = hashBytes(bytes);
    const filePath = path.join(kbRoot, "gone.png");
    fs.writeFileSync(filePath, bytes);
    const meta = await validateBinaryFile(kbRoot, "gone.png");
    if (!meta.ok) throw new Error("meta not ok");

    // Remove the file entirely — openBinaryStream will throw
    // BinaryOpenError(404) with no code.
    fs.rmSync(filePath);

    const res = await serveBinaryWithHashGate({
      token: "tok",
      expectedHash,
      meta,
      request: buildRequest(),
      logger: logger(),
      logContext: { token: "tok", documentPath: "gone.png" },
    });
    expect(res.status).toBe(404);
    expect(loggerStub.warn).toHaveBeenCalledWith(
      expect.objectContaining({ token: "tok", path: "gone.png" }),
      expect.stringContaining("open failed on hash pass"),
    );
  });
});
