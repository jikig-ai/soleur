import { describe, it, expect, vi, beforeEach } from "vitest";

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
// can drive onload/onerror/onabort with a chosen xhr.status.
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
  abort() {}
}

beforeEach(() => {
  mockReportSilentFallback.mockReset();
  FakeXHR.last = null;
  vi.stubGlobal("XMLHttpRequest", FakeXHR);
});

const SIGNED_URL =
  "https://api.soleur.ai/storage/v1/object/upload/sign/chat-attachments/u/c/f.md?token=SECRET";

function makeFile(name = "note.md") {
  return new File(["hello"], name, { type: "text/markdown" });
}

describe("uploadWithProgress", () => {
  it("resolves on a 2xx onload and reports nothing", async () => {
    const { promise } = uploadWithProgress(SIGNED_URL, makeFile(), "text/markdown", vi.fn());
    const xhr = FakeXHR.last!;
    xhr.status = 200;
    xhr.onload!();
    await expect(promise).resolves.toBeUndefined();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("non-2xx onload rejects AND reports op:storage-put with xhr.status + sanitized filename", async () => {
    const { promise } = uploadWithProgress(
      SIGNED_URL,
      makeFile("bad\nname.md"),
      "text/markdown",
      vi.fn(),
    );
    const xhr = FakeXHR.last!;
    xhr.status = 403;
    xhr.onload!();
    await expect(promise).rejects.toThrow("Upload to storage failed");
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = mockReportSilentFallback.mock.calls[0];
    expect(err).toBeInstanceOf(Error);
    expect(opts).toMatchObject({
      feature: "attachments",
      op: "storage-put",
      extra: { status: 403, filename: "bad_name.md" },
    });
  });

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

  it("onabort rejects WITHOUT reporting (user-driven cancel is not a failure signal)", async () => {
    const { promise } = uploadWithProgress(SIGNED_URL, makeFile(), "text/markdown", vi.fn());
    const xhr = FakeXHR.last!;
    xhr.onabort!();
    await expect(promise).rejects.toThrow("Upload cancelled");
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("the reported payload never carries the signed URL or its token", async () => {
    const { promise } = uploadWithProgress(SIGNED_URL, makeFile(), "text/markdown", vi.fn());
    const xhr = FakeXHR.last!;
    xhr.status = 0;
    xhr.onerror!();
    await expect(promise).rejects.toThrow();
    const payload = JSON.stringify(mockReportSilentFallback.mock.calls);
    expect(payload).not.toContain("token=");
    expect(payload).not.toContain("SECRET");
    expect(payload).not.toContain("api.soleur.ai/storage");
  });
});
