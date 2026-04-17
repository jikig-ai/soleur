import { describe, it, expect } from "vitest";

import { classifyResponse } from "@/app/shared/[token]/classify-response";
import { SHARED_CONTENT_KIND_HEADER } from "@/lib/shared-kind";

function jsonResponse(body: unknown, init?: ResponseInit): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: { "content-type": "application/json", ...(init?.headers ?? {}) },
  });
}

function binaryResponse(
  kind: string,
  disposition: string | null,
  init?: ResponseInit,
): Response {
  const headers: Record<string, string> = {
    "content-type": "application/octet-stream",
    [SHARED_CONTENT_KIND_HEADER]: kind,
  };
  if (disposition) headers["content-disposition"] = disposition;
  return new Response(new Uint8Array([1, 2, 3]), {
    ...init,
    headers: { ...headers, ...(init?.headers ?? {}) },
  });
}

describe("classifyResponse", () => {
  it("404 → error: not-found", async () => {
    const res = new Response(null, { status: 404 });
    expect(await classifyResponse(res, "t1")).toEqual({ error: "not-found" });
  });

  it("410 with code content-changed → error: content-changed", async () => {
    const res = jsonResponse({ code: "content-changed" }, { status: 410 });
    expect(await classifyResponse(res, "t1")).toEqual({
      error: "content-changed",
    });
  });

  it("410 with code legacy-null-hash → error: content-changed", async () => {
    const res = jsonResponse({ code: "legacy-null-hash" }, { status: 410 });
    expect(await classifyResponse(res, "t1")).toEqual({
      error: "content-changed",
    });
  });

  it("410 with no parseable body → error: revoked", async () => {
    const res = new Response("not-json", { status: 410 });
    expect(await classifyResponse(res, "t1")).toEqual({ error: "revoked" });
  });

  it("410 with other code → error: revoked", async () => {
    const res = jsonResponse({ code: "revoked" }, { status: 410 });
    expect(await classifyResponse(res, "t1")).toEqual({ error: "revoked" });
  });

  it("non-ok 500 → error: unknown", async () => {
    const res = new Response("oops", { status: 500 });
    expect(await classifyResponse(res, "t1")).toEqual({ error: "unknown" });
  });

  it("200 with missing X-Soleur-Kind → error: unknown", async () => {
    const res = new Response("ok", { status: 200 });
    expect(await classifyResponse(res, "t1")).toEqual({ error: "unknown" });
  });

  it("200 markdown kind → data markdown", async () => {
    const res = new Response(
      JSON.stringify({ content: "# Hi", path: "note.md" }),
      {
        status: 200,
        headers: {
          "content-type": "application/json",
          [SHARED_CONTENT_KIND_HEADER]: "markdown",
        },
      },
    );
    expect(await classifyResponse(res, "t1")).toEqual({
      data: { kind: "markdown", content: "# Hi", path: "note.md" },
    });
  });

  it("200 pdf kind with filename → data pdf", async () => {
    const res = binaryResponse("pdf", 'inline; filename="report.pdf"');
    expect(await classifyResponse(res, "tok-pdf")).toEqual({
      data: { kind: "pdf", src: "/api/shared/tok-pdf", filename: "report.pdf" },
    });
  });

  it("200 image kind without Content-Disposition → filename is null, never 'file'", async () => {
    const res = binaryResponse("image", null);
    const result = await classifyResponse(res, "tok-png");
    if (!("data" in result)) throw new Error("expected data");
    if (result.data.kind !== "image") throw new Error("unreachable");
    expect(result.data.src).toBe("/api/shared/tok-png");
    expect(result.data.filename).toBeNull();
    expect(result.data.filename).not.toBe("file");
  });

  it("200 image kind with filename → filename carried through", async () => {
    const res = binaryResponse("image", 'inline; filename="photo.png"');
    expect(await classifyResponse(res, "tok-png")).toEqual({
      data: { kind: "image", src: "/api/shared/tok-png", filename: "photo.png" },
    });
  });

  it("200 download kind → data download", async () => {
    const res = binaryResponse(
      "download",
      'attachment; filename="data.bin"',
    );
    expect(await classifyResponse(res, "tok-bin")).toEqual({
      data: { kind: "download", src: "/api/shared/tok-bin", filename: "data.bin" },
    });
  });

  it("pdf without Content-Disposition → falls back to basenameFromToken", async () => {
    const res = binaryResponse("pdf", null);
    const result = await classifyResponse(res, "abc123");
    if (!("data" in result)) throw new Error("expected data");
    if (result.data.kind !== "pdf") throw new Error("unreachable");
    expect(result.data.filename).toBe("shared-abc123");
  });

  it("download without Content-Disposition → falls back to basenameFromToken", async () => {
    const res = binaryResponse("download", null);
    const result = await classifyResponse(res, "xyz789");
    if (!("data" in result)) throw new Error("expected data");
    if (result.data.kind !== "download") throw new Error("unreachable");
    expect(result.data.filename).toBe("shared-xyz789");
  });

  it("fetch-like Response that throws on read → error: unknown", async () => {
    const res = {
      status: 200,
      ok: true,
      headers: {
        get: (name: string) =>
          name.toLowerCase() === SHARED_CONTENT_KIND_HEADER.toLowerCase()
            ? "markdown"
            : name.toLowerCase() === "content-type"
              ? "application/json"
              : null,
      },
      json: () => {
        throw new Error("boom");
      },
    } as unknown as Response;
    expect(await classifyResponse(res, "t1")).toEqual({ error: "unknown" });
  });

  describe("extractFilename RFC 5987 coverage (via download kind)", () => {
    it("prefers filename*=UTF-8'' over ASCII filename=", async () => {
      const res = binaryResponse(
        "download",
        "attachment; filename=\"fallback.jpg\"; filename*=UTF-8''caf%C3%A9.jpg",
      );
      const result = await classifyResponse(res, "tok");
      if (!("data" in result)) throw new Error("expected data");
      if (result.data.kind !== "download") throw new Error("unreachable");
      expect(result.data.filename).toBe("café.jpg");
    });

    it("falls back to ASCII filename= when no star form present", async () => {
      const res = binaryResponse(
        "download",
        'attachment; filename="plain.jpg"',
      );
      const result = await classifyResponse(res, "tok");
      if (!("data" in result)) throw new Error("expected data");
      if (result.data.kind !== "download") throw new Error("unreachable");
      expect(result.data.filename).toBe("plain.jpg");
    });

    it("quoted filename containing spaces survives", async () => {
      const res = binaryResponse(
        "download",
        'inline; filename="file with spaces.pdf"',
      );
      const result = await classifyResponse(res, "tok");
      if (!("data" in result)) throw new Error("expected data");
      if (result.data.kind !== "download") throw new Error("unreachable");
      expect(result.data.filename).toBe("file with spaces.pdf");
    });
  });
});
