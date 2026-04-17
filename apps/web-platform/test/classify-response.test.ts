import { describe, it, expect } from "vitest";

import { classifyResponse } from "@/app/shared/[token]/classify-response";

function jsonResponse(body: unknown, init?: ResponseInit): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: { "content-type": "application/json", ...(init?.headers ?? {}) },
  });
}

function binaryResponse(
  contentType: string,
  disposition: string | null,
  init?: ResponseInit,
): Response {
  const headers: Record<string, string> = { "content-type": contentType };
  if (disposition) headers["content-disposition"] = disposition;
  return new Response(new Uint8Array([1, 2, 3]), {
    ...init,
    headers: { ...headers, ...(init?.headers ?? {}) },
  });
}

describe("classifyResponse", () => {
  it("404 → error: not-found", async () => {
    const res = new Response(null, { status: 404 });
    const result = await classifyResponse(res, "t1");
    expect(result).toEqual({ error: "not-found" });
  });

  it("410 with code content-changed → error: content-changed", async () => {
    const res = jsonResponse({ code: "content-changed" }, { status: 410 });
    const result = await classifyResponse(res, "t1");
    expect(result).toEqual({ error: "content-changed" });
  });

  it("410 with code legacy-null-hash → error: content-changed", async () => {
    const res = jsonResponse({ code: "legacy-null-hash" }, { status: 410 });
    const result = await classifyResponse(res, "t1");
    expect(result).toEqual({ error: "content-changed" });
  });

  it("410 with no parseable body → error: revoked", async () => {
    const res = new Response("not-json", { status: 410 });
    const result = await classifyResponse(res, "t1");
    expect(result).toEqual({ error: "revoked" });
  });

  it("410 with other code → error: revoked", async () => {
    const res = jsonResponse({ code: "revoked" }, { status: 410 });
    const result = await classifyResponse(res, "t1");
    expect(result).toEqual({ error: "revoked" });
  });

  it("non-ok 500 → error: unknown", async () => {
    const res = new Response("oops", { status: 500 });
    const result = await classifyResponse(res, "t1");
    expect(result).toEqual({ error: "unknown" });
  });

  it("200 application/json → data markdown", async () => {
    const res = jsonResponse({ content: "# Hi", path: "note.md" });
    const result = await classifyResponse(res, "t1");
    expect(result).toEqual({
      data: { kind: "markdown", content: "# Hi", path: "note.md" },
    });
  });

  it("200 application/pdf with filename → data pdf", async () => {
    const res = binaryResponse(
      "application/pdf",
      'inline; filename="report.pdf"',
    );
    const result = await classifyResponse(res, "tok-pdf");
    expect(result).toEqual({
      data: { kind: "pdf", src: "/api/shared/tok-pdf", filename: "report.pdf" },
    });
  });

  it("200 image/png without Content-Disposition → filename is null, never 'file'", async () => {
    const res = binaryResponse("image/png", null);
    const result = await classifyResponse(res, "tok-png");
    if (!("data" in result)) throw new Error("expected data");
    expect(result.data.kind).toBe("image");
    if (result.data.kind !== "image") throw new Error("unreachable");
    expect(result.data.src).toBe("/api/shared/tok-png");
    expect(result.data.filename).toBeNull();
    expect(result.data.filename).not.toBe("file");
  });

  it("200 image/png with filename → filename carried through", async () => {
    const res = binaryResponse("image/png", 'inline; filename="photo.png"');
    const result = await classifyResponse(res, "tok-png");
    expect(result).toEqual({
      data: { kind: "image", src: "/api/shared/tok-png", filename: "photo.png" },
    });
  });

  it("200 application/octet-stream → data download", async () => {
    const res = binaryResponse(
      "application/octet-stream",
      'attachment; filename="data.bin"',
    );
    const result = await classifyResponse(res, "tok-bin");
    expect(result).toEqual({
      data: {
        kind: "download",
        src: "/api/shared/tok-bin",
        filename: "data.bin",
      },
    });
  });

  it("fetch-like Response that throws on read → error: unknown", async () => {
    const res = {
      status: 200,
      ok: true,
      headers: {
        get: (name: string) =>
          name.toLowerCase() === "content-type" ? "application/json" : null,
      },
      json: () => {
        throw new Error("boom");
      },
    } as unknown as Response;
    const result = await classifyResponse(res, "t1");
    expect(result).toEqual({ error: "unknown" });
  });

  describe("extractFilename RFC 5987 coverage (via download branch)", () => {
    it("prefers filename*=UTF-8'' over ASCII filename=", async () => {
      const res = binaryResponse(
        "application/octet-stream",
        "attachment; filename=\"fallback.jpg\"; filename*=UTF-8''caf%C3%A9.jpg",
      );
      const result = await classifyResponse(res, "tok");
      if (!("data" in result)) throw new Error("expected data");
      if (result.data.kind !== "download") throw new Error("unreachable");
      expect(result.data.filename).toBe("café.jpg");
    });

    it("falls back to ASCII filename= when no star form present", async () => {
      const res = binaryResponse(
        "application/octet-stream",
        'attachment; filename="plain.jpg"',
      );
      const result = await classifyResponse(res, "tok");
      if (!("data" in result)) throw new Error("expected data");
      if (result.data.kind !== "download") throw new Error("unreachable");
      expect(result.data.filename).toBe("plain.jpg");
    });

    it("falls back to ASCII when star form has malformed percent-encoding", async () => {
      const res = binaryResponse(
        "application/octet-stream",
        "attachment; filename=\"safe.jpg\"; filename*=UTF-8''%ZZbad",
      );
      const result = await classifyResponse(res, "tok");
      if (!("data" in result)) throw new Error("expected data");
      if (result.data.kind !== "download") throw new Error("unreachable");
      expect(result.data.filename).toBe("safe.jpg");
    });

    it("quoted filename containing spaces survives", async () => {
      const res = binaryResponse(
        "application/octet-stream",
        'inline; filename="file with spaces.pdf"',
      );
      const result = await classifyResponse(res, "tok");
      if (!("data" in result)) throw new Error("expected data");
      if (result.data.kind !== "download") throw new Error("unreachable");
      expect(result.data.filename).toBe("file with spaces.pdf");
    });
  });
});
