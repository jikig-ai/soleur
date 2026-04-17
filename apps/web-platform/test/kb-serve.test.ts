import fs from "fs";
import os from "os";
import path from "path";
import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import { serveBinary, serveKbFile } from "@/server/kb-serve";
import { MAX_BINARY_SIZE } from "@/server/kb-binary-response";

let tmpWorkspace: string;
let kbRoot: string;

function buildRequest(): Request {
  return new Request("http://localhost:3000/anything");
}

beforeEach(() => {
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "kb-serve-test-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("serveBinary", () => {
  test("path traversal returns 403 with { error: 'Access denied' }", async () => {
    const res = await serveBinary(kbRoot, "../../etc/passwd.png", {
      request: buildRequest(),
    });
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "Access denied" });
  });

  test("symlink returns 403", async () => {
    const outside = path.join(tmpWorkspace, "secret.txt");
    fs.writeFileSync(outside, "secret");
    fs.symlinkSync(outside, path.join(kbRoot, "link.png"));

    const res = await serveBinary(kbRoot, "link.png", { request: buildRequest() });
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "Access denied" });
  });

  test("missing file returns 404", async () => {
    const res = await serveBinary(kbRoot, "missing.png", {
      request: buildRequest(),
    });
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: "File not found" });
  });

  test("file exceeding MAX_BINARY_SIZE returns 413", async () => {
    const big = path.join(kbRoot, "huge.pdf");
    const fd = fs.openSync(big, "w");
    fs.ftruncateSync(fd, MAX_BINARY_SIZE + 1);
    fs.closeSync(fd);

    const res = await serveBinary(kbRoot, "huge.pdf", { request: buildRequest() });
    expect(res.status).toBe(413);
    const body = await res.json();
    expect(body.error).toContain("exceed");
  });

  test("valid PNG returns 200 with expected headers", async () => {
    fs.writeFileSync(path.join(kbRoot, "logo.png"), Buffer.from("fake-png"));

    const res = await serveBinary(kbRoot, "logo.png", { request: buildRequest() });
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("image/png");
    expect(res.headers.get("Accept-Ranges")).toBe("bytes");
    expect(res.headers.get("ETag")).toBeTruthy();
  });

  test("invokes onError with (status, message) on validate rejection", async () => {
    const onError = vi.fn();
    const res = await serveBinary(kbRoot, "missing.png", {
      request: buildRequest(),
      onError,
    });
    expect(res.status).toBe(404);
    expect(onError).toHaveBeenCalledWith(404, "File not found");
  });
});

describe("serveKbFile dispatcher", () => {
  const okMarkdown = () =>
    vi.fn(async () => new Response("md", { status: 200 }));
  const okBinary = () =>
    vi.fn(async () => new Response("bin", { status: 200 }));

  test(".md path routes to onMarkdown", async () => {
    const onMarkdown = okMarkdown();
    const onBinary = okBinary();
    await serveKbFile(kbRoot, "foo.md", {
      request: buildRequest(),
      onMarkdown,
      onBinary,
    });
    expect(onMarkdown).toHaveBeenCalledWith(kbRoot, "foo.md");
    expect(onBinary).not.toHaveBeenCalled();
  });

  test("extensionless path routes to onMarkdown", async () => {
    const onMarkdown = okMarkdown();
    const onBinary = okBinary();
    await serveKbFile(kbRoot, "notes", {
      request: buildRequest(),
      onMarkdown,
      onBinary,
    });
    expect(onMarkdown).toHaveBeenCalledWith(kbRoot, "notes");
    expect(onBinary).not.toHaveBeenCalled();
  });

  test("uppercase .MD routes to onMarkdown (case-fold regression)", async () => {
    const onMarkdown = okMarkdown();
    const onBinary = okBinary();
    await serveKbFile(kbRoot, "NOTES.MD", {
      request: buildRequest(),
      onMarkdown,
      onBinary,
    });
    expect(onMarkdown).toHaveBeenCalledWith(kbRoot, "NOTES.MD");
    expect(onBinary).not.toHaveBeenCalled();
  });

  test("binary path routes to onBinary", async () => {
    const onMarkdown = okMarkdown();
    const onBinary = okBinary();
    await serveKbFile(kbRoot, "foo.pdf", {
      request: buildRequest(),
      onMarkdown,
      onBinary,
    });
    expect(onMarkdown).not.toHaveBeenCalled();
    expect(onBinary).toHaveBeenCalledWith(kbRoot, "foo.pdf");
  });

  test("uppercase .PDF routes to binary (case-fold regression)", async () => {
    const onMarkdown = okMarkdown();
    const onBinary = okBinary();
    await serveKbFile(kbRoot, "foo.PDF", {
      request: buildRequest(),
      onMarkdown,
      onBinary,
    });
    expect(onMarkdown).not.toHaveBeenCalled();
    expect(onBinary).toHaveBeenCalledWith(kbRoot, "foo.PDF");
  });
});
