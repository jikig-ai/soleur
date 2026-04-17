import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, beforeEach, afterEach } from "vitest";

import {
  validateBinaryFile,
  buildBinaryResponse,
  buildBinaryHeaders,
  buildBinaryHeadResponse,
  build304Response,
  formatStrongETag,
  ifNoneMatchMatches,
  type BinaryFileMetadata,
} from "@/server/kb-binary-response";

let tmpDir: string;
let filePath: string;

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "head-"));
  filePath = path.join(tmpDir, "doc.pdf");
  fs.writeFileSync(filePath, Buffer.from("hello world payload"));
});

afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

function req(headers: Record<string, string> = {}): Request {
  return new Request("http://localhost/test", { headers });
}

async function getPayload(): Promise<BinaryFileMetadata> {
  return validateBinaryFile(tmpDir, "doc.pdf");
}

describe("buildBinaryHeaders — pure header derivation", () => {
  it("returns the same body-agnostic headers as buildBinaryResponse on 200", async () => {
    const payload = await getPayload();
    const headers = buildBinaryHeaders(payload);
    const res = await buildBinaryResponse(payload);
    for (const key of [
      "Content-Type",
      "Content-Disposition",
      "Cache-Control",
      "X-Content-Type-Options",
      "Content-Security-Policy",
      "Accept-Ranges",
      "ETag",
    ]) {
      expect(headers[key]).toBe(res.headers.get(key));
    }
  });

  it("applies a supplied strong ETag", async () => {
    const payload = await getPayload();
    const sha = "a".repeat(64);
    const headers = buildBinaryHeaders(payload, { strongETag: sha });
    expect(headers.ETag).toBe(`"${sha}"`);
  });
});

describe("buildBinaryHeadResponse — 200 + 304 + Content-Length", () => {
  it("returns 200 with empty body and Content-Length equal to payload size", async () => {
    const payload = await getPayload();
    const res = buildBinaryHeadResponse(payload);
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Length")).toBe(String(payload.size));
    expect(res.headers.get("Content-Type")).toBe("application/pdf");
    const body = await res.arrayBuffer();
    expect(body.byteLength).toBe(0);
  });

  it("mirrors the header shape of buildBinaryResponse 200", async () => {
    const payload = await getPayload();
    const headRes = buildBinaryHeadResponse(payload);
    const getRes = await buildBinaryResponse(payload);
    for (const key of [
      "Content-Type",
      "Content-Disposition",
      "Cache-Control",
      "X-Content-Type-Options",
      "Content-Security-Policy",
      "Accept-Ranges",
      "ETag",
      "Content-Length",
    ]) {
      expect(headRes.headers.get(key)).toBe(getRes.headers.get(key));
    }
  });

  it("returns 304 when If-None-Match matches the strong ETag (no fd open)", async () => {
    const payload = await getPayload();
    const sha = "b".repeat(64);
    const res = buildBinaryHeadResponse(
      payload,
      req({ "if-none-match": `"${sha}"` }),
      { strongETag: sha },
    );
    expect(res.status).toBe(304);
    expect(res.headers.get("ETag")).toBe(`"${sha}"`);
    expect(res.headers.get("Content-Length")).toBeNull();
    expect(res.headers.get("Content-Type")).toBeNull();
  });

  it("returns 304 when If-None-Match matches the weak ETag", async () => {
    const payload = await getPayload();
    const weak = `W/"${payload.ino}-${payload.size}-${Math.floor(payload.mtimeMs)}"`;
    const res = buildBinaryHeadResponse(payload, req({ "if-none-match": weak }));
    expect(res.status).toBe(304);
    expect(res.headers.get("ETag")).toBe(weak);
  });

  it("returns 304 for `*` wildcard If-None-Match", async () => {
    const payload = await getPayload();
    const res = buildBinaryHeadResponse(payload, req({ "if-none-match": "*" }));
    expect(res.status).toBe(304);
  });

  it("returns 200 with empty body when If-None-Match does not match", async () => {
    const payload = await getPayload();
    const res = buildBinaryHeadResponse(
      payload,
      req({ "if-none-match": '"no-match"' }),
      { strongETag: "a".repeat(64) },
    );
    expect(res.status).toBe(200);
    const body = await res.arrayBuffer();
    expect(body.byteLength).toBe(0);
  });
});

describe("build304Response + formatStrongETag + ifNoneMatchMatches", () => {
  it("build304Response emits ETag + Cache-Control with status 304", () => {
    const res = build304Response('"deadbeef"');
    expect(res.status).toBe(304);
    expect(res.headers.get("ETag")).toBe('"deadbeef"');
    expect(res.headers.get("Cache-Control")).toBe("private, max-age=60");
  });

  it("formatStrongETag wraps a hash in double quotes", () => {
    expect(formatStrongETag("abc123")).toBe('"abc123"');
  });

  it("ifNoneMatchMatches applies weak-equality against comma-separated candidates", () => {
    expect(ifNoneMatchMatches('"a", "b", "c"', '"b"')).toBe(true);
    expect(ifNoneMatchMatches('W/"x"', '"x"')).toBe(true);
    expect(ifNoneMatchMatches('"x"', '"y"')).toBe(false);
    expect(ifNoneMatchMatches("*", '"anything"')).toBe(true);
  });
});
