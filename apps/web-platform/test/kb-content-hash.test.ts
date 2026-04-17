import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { Readable } from "node:stream";
import { describe, it, expect, beforeAll, afterAll } from "vitest";

import { hashBytes, hashStream } from "@/server/kb-content-hash";

const EMPTY_SHA256 =
  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

describe("kb-content-hash", () => {
  describe("hashBytes", () => {
    it("returns lowercase-hex SHA-256 of an empty buffer (known vector)", () => {
      expect(hashBytes(Buffer.from(""))).toBe(EMPTY_SHA256);
    });

    it("returns a 64-char lowercase hex digest for arbitrary bytes", () => {
      const hash = hashBytes(Buffer.from("hello world"));
      expect(hash).toMatch(/^[a-f0-9]{64}$/);
    });

    it("returns a stable hash across invocations for the same input", () => {
      const buf = Buffer.from("deterministic-content");
      expect(hashBytes(buf)).toBe(hashBytes(buf));
    });
  });

  describe("hashStream", () => {
    it("returns the SHA-256 of an empty readable (known vector)", async () => {
      const empty = Readable.from(Buffer.alloc(0));
      await expect(hashStream(empty)).resolves.toBe(EMPTY_SHA256);
    });

    it("matches hashBytes for the same small buffer", async () => {
      const buf = Buffer.from("small-content");
      const streamed = await hashStream(Readable.from(buf));
      expect(streamed).toBe(hashBytes(buf));
    });

    it("matches hashBytes on a ≥1 MB file via fs.createReadStream", async () => {
      const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "hash-stream-"));
      const filePath = path.join(tmpDir, "blob.bin");
      // 1.5 MB of repeated pattern — exercises chunk boundaries.
      const content = Buffer.alloc(1_500_000, "ab");
      fs.writeFileSync(filePath, content);
      try {
        const streamed = await hashStream(fs.createReadStream(filePath));
        const buffered = hashBytes(content);
        expect(streamed).toBe(buffered);
      } finally {
        fs.rmSync(tmpDir, { recursive: true, force: true });
      }
    });

    it("rejects with the underlying error if the stream errors", async () => {
      const broken = new Readable({
        read() {
          this.destroy(new Error("stream boom"));
        },
      });
      await expect(hashStream(broken)).rejects.toThrow(/stream boom/);
    });
  });
});
