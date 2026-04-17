import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Mock uploadWithProgress so we don't hit real XHR.
const mockUpload = vi.fn();
vi.mock("@/lib/upload-with-progress", () => ({
  uploadWithProgress: (url: string, file: File, contentType: string, onProgress: (p: number) => void) => {
    return mockUpload(url, file, contentType, onProgress);
  },
}));

// Mock Sentry so we can assert captureException is invoked on failure.
const mockSentry = vi.fn();
vi.mock("@sentry/nextjs", () => ({
  captureException: (err: unknown) => mockSentry(err),
}));

// The module under test — does not exist yet (RED).
import { uploadPendingFiles } from "@/lib/upload-attachments";

function fakePresignOk(file: File) {
  return {
    ok: true,
    json: async () => ({
      uploadUrl: `https://storage.example.com/upload/${file.name}`,
      storagePath: `uploads/${file.name}`,
    }),
  } as Response;
}

function fakePresignErr(status: number) {
  return {
    ok: false,
    status,
    json: async () => ({ error: "presign boom" }),
  } as Response;
}

describe("uploadPendingFiles", () => {
  // Cast sidesteps vi.spyOn's stricter generic on `typeof globalThis`
  // (which does not always expose `fetch` as a valid key).
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    mockUpload.mockReset();
    mockSentry.mockReset();
    fetchSpy = vi.spyOn(
      globalThis as unknown as { fetch: typeof fetch },
      "fetch",
    ) as unknown as ReturnType<typeof vi.fn>;
    mockUpload.mockImplementation(() => ({
      promise: Promise.resolve(),
      xhr: {} as XMLHttpRequest,
    }));
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it("presigns and uploads each file, returning AttachmentRefs in order", async () => {
    const fileA = new File(["a".repeat(10)], "a.png", { type: "image/png" });
    const fileB = new File(["b".repeat(20)], "b.pdf", { type: "application/pdf" });

    fetchSpy.mockResolvedValueOnce(fakePresignOk(fileA));
    fetchSpy.mockResolvedValueOnce(fakePresignOk(fileB));

    const refs = await uploadPendingFiles([fileA, fileB], "conv-1");

    // Two presign POSTs hit /api/attachments/presign.
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    const firstCallArgs = fetchSpy.mock.calls[0];
    expect(firstCallArgs[0]).toBe("/api/attachments/presign");
    const firstInit = firstCallArgs[1] as RequestInit;
    const firstBody = JSON.parse(firstInit.body as string);
    expect(firstBody).toMatchObject({
      filename: "a.png",
      contentType: "image/png",
      sizeBytes: fileA.size,
      conversationId: "conv-1",
    });

    // Two successful AttachmentRefs returned in input order.
    expect(refs).toHaveLength(2);
    expect(refs[0]).toMatchObject({
      storagePath: "uploads/a.png",
      filename: "a.png",
      contentType: "image/png",
      sizeBytes: fileA.size,
    });
    expect(refs[1]).toMatchObject({
      storagePath: "uploads/b.pdf",
      filename: "b.pdf",
    });
    // Both files hit uploadWithProgress.
    expect(mockUpload).toHaveBeenCalledTimes(2);
  });

  it("skips files whose presign fails but returns the successful ones (no throw)", async () => {
    const fileA = new File(["a"], "a.png", { type: "image/png" });
    const fileB = new File(["b"], "b.png", { type: "image/png" });

    fetchSpy.mockResolvedValueOnce(fakePresignErr(500));
    fetchSpy.mockResolvedValueOnce(fakePresignOk(fileB));

    const refs = await uploadPendingFiles([fileA, fileB], "conv-2");

    expect(refs).toHaveLength(1);
    expect(refs[0]?.filename).toBe("b.png");
    expect(mockUpload).toHaveBeenCalledTimes(1); // Only the successful presign uploaded.
  });

  it("returns an empty array when every presign fails", async () => {
    const fileA = new File(["a"], "a.png", { type: "image/png" });
    fetchSpy.mockResolvedValueOnce(fakePresignErr(500));

    const refs = await uploadPendingFiles([fileA], "conv-3");
    expect(refs).toEqual([]);
    expect(mockUpload).not.toHaveBeenCalled();
  });

  it("invokes onProgress with fileIndex and percent for each upload", async () => {
    const fileA = new File(["a"], "a.png", { type: "image/png" });
    const fileB = new File(["b"], "b.png", { type: "image/png" });

    fetchSpy.mockResolvedValueOnce(fakePresignOk(fileA));
    fetchSpy.mockResolvedValueOnce(fakePresignOk(fileB));

    mockUpload.mockImplementation(
      (_url: string, _file: File, _ct: string, onProgress: (p: number) => void) => {
        onProgress(50);
        onProgress(100);
        return { promise: Promise.resolve(), xhr: {} as XMLHttpRequest };
      },
    );

    const progressCalls: Array<[number, number]> = [];
    await uploadPendingFiles([fileA, fileB], "conv-4", {
      onProgress: (i, p) => progressCalls.push([i, p]),
    });

    expect(progressCalls).toEqual([
      [0, 50],
      [0, 100],
      [1, 50],
      [1, 100],
    ]);
  });

  it("propagates partial success when a storage upload rejects", async () => {
    const fileA = new File(["a"], "a.png", { type: "image/png" });
    const fileB = new File(["b"], "b.png", { type: "image/png" });

    fetchSpy.mockResolvedValueOnce(fakePresignOk(fileA));
    fetchSpy.mockResolvedValueOnce(fakePresignOk(fileB));

    mockUpload
      .mockImplementationOnce(() => ({
        promise: Promise.reject(new Error("storage 503")),
        xhr: {} as XMLHttpRequest,
      }))
      .mockImplementationOnce(() => ({
        promise: Promise.resolve(),
        xhr: {} as XMLHttpRequest,
      }));

    const refs = await uploadPendingFiles([fileA, fileB], "conv-5");
    expect(refs).toHaveLength(1);
    expect(refs[0]?.filename).toBe("b.png");
  });

  it("logs a [kb-chat] warning and reports to Sentry on per-file failure (#2384 5D)", async () => {
    const fileA = new File(["a"], "a.png", { type: "image/png" });
    fetchSpy.mockResolvedValueOnce(fakePresignErr(500));
    const warnSpy = vi.spyOn(console, "warn").mockImplementation(() => {});

    try {
      const refs = await uploadPendingFiles([fileA], "conv-6");
      expect(refs).toEqual([]);
      expect(warnSpy).toHaveBeenCalled();
      const [msg, ctx] = warnSpy.mock.calls[0];
      expect(String(msg)).toContain("[kb-chat]");
      expect(ctx).toMatchObject({ filename: "a.png" });
      expect(mockSentry).toHaveBeenCalledTimes(1);
      expect((mockSentry.mock.calls[0][0] as Error).message).toContain("[kb-chat]");
    } finally {
      warnSpy.mockRestore();
    }
  });
});
