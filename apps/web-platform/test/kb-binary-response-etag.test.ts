import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, it, expect, beforeEach, afterEach } from "vitest";

import {
  validateBinaryFile,
  buildBinaryResponse,
} from "@/server/kb-binary-response";

let tmpDir: string;
let filePath: string;

beforeEach(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "etag-"));
  filePath = path.join(tmpDir, "doc.pdf");
  fs.writeFileSync(filePath, Buffer.from("hello world payload"));
});

afterEach(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

function req(headers: Record<string, string> = {}): Request {
  return new Request("http://localhost/test", { headers });
}

describe("buildBinaryResponse — ETag / If-None-Match", () => {
  it("emits a weak ETag when no strong ETag is supplied", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");

    const res = await buildBinaryResponse(meta, req());
    expect(res.status).toBe(200);
    const etag = res.headers.get("ETag");
    expect(etag).toMatch(/^W\/"\d+-\d+-\d+"$/);
  });

  it("emits the supplied strong ETag verbatim", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");

    const sha = "a".repeat(64);
    const res = await buildBinaryResponse(meta, req(), { strongETag: sha });
    expect(res.headers.get("ETag")).toBe(`"${sha}"`);
  });

  it("returns 304 when If-None-Match matches the strong ETag", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");

    const sha = "b".repeat(64);
    const etag = `"${sha}"`;
    const res = await buildBinaryResponse(
      meta,
      req({ "if-none-match": etag }),
      { strongETag: sha },
    );
    expect(res.status).toBe(304);
    expect(res.headers.get("ETag")).toBe(etag);
    expect(res.headers.get("Content-Length")).toBeNull();
    expect(res.headers.get("Content-Type")).toBeNull();
  });

  it("returns 304 when If-None-Match matches the weak ETag (fstat tuple)", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");

    // Build the expected weak ETag the same way the helper does.
    const weak = `W/"${meta.ino}-${meta.size}-${Math.floor(meta.mtimeMs)}"`;
    const res = await buildBinaryResponse(meta, req({ "if-none-match": weak }));
    expect(res.status).toBe(304);
    expect(res.headers.get("ETag")).toBe(weak);
  });

  it("treats `*` as a wildcard If-None-Match match", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");

    const res = await buildBinaryResponse(meta, req({ "if-none-match": "*" }));
    expect(res.status).toBe(304);
  });

  it("serves 200 + body when If-None-Match does not match", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");

    const res = await buildBinaryResponse(
      meta,
      req({ "if-none-match": '"different-hash"' }),
      { strongETag: "a".repeat(64) },
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("ETag")).toBe(`"${"a".repeat(64)}"`);
    const body = await res.arrayBuffer();
    expect(Buffer.from(body).toString()).toBe("hello world payload");
  });

  it("weak-equal: If-None-Match with W/ prefix matches strong ETag", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");

    const sha = "c".repeat(64);
    const res = await buildBinaryResponse(
      meta,
      req({ "if-none-match": `W/"${sha}"` }),
      { strongETag: sha },
    );
    expect(res.status).toBe(304);
  });

  it("If-None-Match with multiple candidates matches any one", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");

    const sha = "d".repeat(64);
    const res = await buildBinaryResponse(
      meta,
      req({ "if-none-match": `"other", "${sha}", "another"` }),
      { strongETag: sha },
    );
    expect(res.status).toBe(304);
  });

  it("304 short-circuits Range requests when ETag matches the whole resource", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");

    const sha = "e".repeat(64);
    const res = await buildBinaryResponse(
      meta,
      req({ "if-none-match": `"${sha}"`, range: "bytes=0-4" }),
      { strongETag: sha },
    );
    expect(res.status).toBe(304);
  });
});

const PUBLIC_CACHE_CONTROL =
  "public, max-age=60, s-maxage=300, stale-while-revalidate=3600, must-revalidate";
const PRIVATE_CACHE_CONTROL = "private, max-age=60";

describe("buildBinaryResponse — Cache-Control scope", () => {
  it("emits private, max-age=60 by default", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");
    const res = await buildBinaryResponse(meta, req());
    expect(res.headers.get("Cache-Control")).toBe(PRIVATE_CACHE_CONTROL);
  });

  it("emits the public Cache-Control string when scope is 'public'", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");
    const res = await buildBinaryResponse(meta, req(), { scope: "public" });
    expect(res.headers.get("Cache-Control")).toBe(PUBLIC_CACHE_CONTROL);
  });

  it("304 short-circuit inherits scope='public'", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");
    const sha = "f".repeat(64);
    const res = await buildBinaryResponse(
      meta,
      req({ "if-none-match": `"${sha}"` }),
      { strongETag: sha, scope: "public" },
    );
    expect(res.status).toBe(304);
    expect(res.headers.get("Cache-Control")).toBe(PUBLIC_CACHE_CONTROL);
  });

  it("304 short-circuit defaults to scope='private'", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");
    const weak = `W/"${meta.ino}-${meta.size}-${Math.floor(meta.mtimeMs)}"`;
    const res = await buildBinaryResponse(meta, req({ "if-none-match": weak }));
    expect(res.status).toBe(304);
    expect(res.headers.get("Cache-Control")).toBe(PRIVATE_CACHE_CONTROL);
  });

  it("206 Range response inherits scope='public'", async () => {
    const meta = await validateBinaryFile(tmpDir, "doc.pdf");
    const res = await buildBinaryResponse(
      meta,
      req({ range: "bytes=0-4" }),
      { scope: "public" },
    );
    expect(res.status).toBe(206);
    expect(res.headers.get("Cache-Control")).toBe(PUBLIC_CACHE_CONTROL);
  });
});
