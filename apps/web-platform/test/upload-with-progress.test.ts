import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// First suite for lib/upload-with-progress.ts — until now every consumer
// mocked the module (upload-attachments.test.ts), so the XHR failure surface
// (the leg that mints "Upload to storage failed") had no coverage.

const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

import { uploadWithProgress } from "@/lib/upload-with-progress";

// ---------------------------------------------------------------------------
// Fake XHR — captures the one instance uploadWithProgress constructs so a test
// can drive onload/onerror/onabort with a chosen xhr.status. abort() fires
// onabort like a real XHR so tests exercise the public contract
// ({ promise, xhr } callers invoke xhr.abort(), they don't poke handlers).
// ---------------------------------------------------------------------------

class FakeXHR {
  static last: FakeXHR | null = null;

  upload = { onprogress: null as ((e: ProgressEvent) => void) | null };
  onload: (() => void) | null = null;
  onerror: (() => void) | null = null;
  onabort: (() => void) | null = null;
  status = 0;
  method = "";
  url = "";
  headers: Record<string, string> = {};

  constructor() {
    FakeXHR.last = this;
  }
  open(method: string, url: string) {
    this.method = method;
    this.url = url;
  }
  setRequestHeader(k: string, v: string) {
    this.headers[k] = v;
  }
  send(_body: unknown) {}
  abort() {
    this.onabort?.();
  }
}

beforeEach(() => {
  mockReportSilentFallback.mockReset();
  FakeXHR.last = null;
  vi.stubGlobal("XMLHttpRequest", FakeXHR);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

const SIGNED_URL =
  "https://api.soleur.ai/storage/v1/object/upload/sign/chat-attachments/u/c/f.md?token=SECRET";

function makeFile(name = "note.md") {
  return new File(["hello"], name, { type: "text/markdown" });
}

describe("uploadWithProgress", () => {
  it("issues a PUT with the file's content type", () => {
    uploadWithProgress(SIGNED_URL, makeFile(), "text/markdown", vi.fn());
    const xhr = FakeXHR.last!;
    expect(xhr.method).toBe("PUT");
    expect(xhr.url).toBe(SIGNED_URL);
    expect(xhr.headers["Content-Type"]).toBe("text/markdown");
  });

  it.each([200, 204, 299])("resolves on a %i onload and reports nothing", async (status) => {
    const { promise } = uploadWithProgress(SIGNED_URL, makeFile(), "text/markdown", vi.fn());
    const xhr = FakeXHR.last!;
    xhr.status = status;
    xhr.onload!();
    await expect(promise).resolves.toBeUndefined();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it.each([300, 400, 403, 500])(
    "non-2xx onload (status %i) rejects AND reports op:storage-put with xhr.status + sanitized filename",
    async (status) => {
      const { promise } = uploadWithProgress(
        SIGNED_URL,
        makeFile("bad\nname.md"),
        "text/markdown",
        vi.fn(),
      );
      const xhr = FakeXHR.last!;
      xhr.status = status;
      xhr.onload!();
      await expect(promise).rejects.toThrow("Upload to storage failed");
      expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
      const [err, opts] = mockReportSilentFallback.mock.calls[0];
      expect(err).toBeInstanceOf(Error);
      expect(opts).toMatchObject({
        feature: "attachments",
        op: "storage-put",
        extra: { status, filename: "bad_name.md" },
      });
    },
  );

  it("onerror (CSP/network block) rejects AND reports with status 0", async () => {
    const { promise } = uploadWithProgress(SIGNED_URL, makeFile(), "text/markdown", vi.fn());
    const xhr = FakeXHR.last!;
    xhr.status = 0; // xhr.status is 0 on a blocked/failed network request
    xhr.onerror!();
    await expect(promise).rejects.toThrow("Upload to storage failed");
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "attachments",
      op: "storage-put",
      extra: { status: 0, filename: "note.md" },
    });
  });

  it("marks the rejected error so a caller catch does not double-report", async () => {
    const { promise } = uploadWithProgress(SIGNED_URL, makeFile(), "text/markdown", vi.fn());
    const xhr = FakeXHR.last!;
    xhr.status = 500;
    xhr.onload!();
    await expect(promise).rejects.toMatchObject({ reportedToSentry: true });
  });

  it("still rejects when reportSilentFallback throws (report can never hang the upload)", async () => {
    mockReportSilentFallback.mockImplementationOnce(() => {
      throw new Error("sentry down");
    });
    const { promise } = uploadWithProgress(SIGNED_URL, makeFile(), "text/markdown", vi.fn());
    const xhr = FakeXHR.last!;
    xhr.status = 0;
    xhr.onerror!();
    await expect(promise).rejects.toThrow("Upload to storage failed");
  });

  it("xhr.abort() rejects via onabort WITHOUT reporting (user cancel is not a failure signal)", async () => {
    const { promise, xhr } = uploadWithProgress(
      SIGNED_URL,
      makeFile(),
      "text/markdown",
      vi.fn(),
    );
    xhr.abort();
    await expect(promise).rejects.toThrow("Upload cancelled");
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("the reported payload never carries the signed URL or its token", async () => {
    const { promise } = uploadWithProgress(SIGNED_URL, makeFile(), "text/markdown", vi.fn());
    const xhr = FakeXHR.last!;
    xhr.status = 0;
    xhr.onerror!();
    await expect(promise).rejects.toThrow();
    // Non-vacuous guard: the report must actually have fired.
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = mockReportSilentFallback.mock.calls[0];
    // Error.message is non-enumerable — JSON.stringify(calls) cannot see it,
    // yet captureException transmits it. Check the message channel directly.
    expect(String(err instanceof Error ? err.message : err)).not.toContain("SECRET");
    expect(String(err instanceof Error ? err.message : err)).not.toContain("token=");
    const optsJson = JSON.stringify(opts);
    expect(optsJson).not.toContain("SECRET");
    expect(optsJson).not.toContain("token=");
    expect(optsJson).not.toContain("api.soleur.ai/storage");
  });
});
