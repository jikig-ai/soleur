import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockLinearize, mockWarn } = vi.hoisted(() => ({
  mockLinearize: vi.fn(),
  mockWarn: vi.fn(),
}));

vi.mock("@/server/pdf-linearize", () => ({ linearizePdf: mockLinearize }));
vi.mock("@/server/observability", () => ({
  warnSilentFallback: mockWarn,
  reportSilentFallback: vi.fn(),
}));
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

import { prepareUploadPayload } from "../server/kb-upload-payload";

function fakeFile(bytes: Uint8Array): File {
  return {
    stream() {
      let sent = false;
      return {
        getReader() {
          return {
            async read() {
              if (sent) return { done: true, value: undefined };
              sent = true;
              return { done: false, value: bytes };
            },
          };
        },
      } as unknown as ReadableStream<Uint8Array>;
    },
  } as unknown as File;
}

beforeEach(() => {
  mockLinearize.mockReset();
  mockWarn.mockReset();
});

describe("prepareUploadPayload", () => {
  it("non-PDF passthrough returns raw buffer without invoking linearize or warn", async () => {
    const f = fakeFile(new Uint8Array([1, 2, 3]));
    const out = await prepareUploadPayload(f, "notes.md", "u1", "path/notes.md");
    expect(out).toEqual(Buffer.from([1, 2, 3]));
    expect(mockLinearize).not.toHaveBeenCalled();
    expect(mockWarn).not.toHaveBeenCalled();
  });

  it("PDF linearize success returns linearized buffer", async () => {
    mockLinearize.mockResolvedValue({
      ok: true,
      buffer: Buffer.from("linearized"),
    });
    const f = fakeFile(new Uint8Array([0x25, 0x50]));
    const out = await prepareUploadPayload(f, "doc.pdf", "u1", "path/doc.pdf");
    expect(out).toEqual(Buffer.from("linearized"));
    expect(mockLinearize).toHaveBeenCalledTimes(1);
    expect(mockWarn).not.toHaveBeenCalled();
  });

  it("PDF linearize failure falls back to original buffer and mirrors to Sentry", async () => {
    mockLinearize.mockResolvedValue({
      ok: false,
      reason: "non_zero_exit",
      detail: "exit=2 stderr=...",
    });
    const f = fakeFile(new Uint8Array([0x11, 0x22, 0x33]));
    const out = await prepareUploadPayload(
      f,
      "broken.pdf",
      "u2",
      "path/broken.pdf",
    );
    expect(out).toEqual(Buffer.from([0x11, 0x22, 0x33]));
    expect(mockWarn).toHaveBeenCalledTimes(1);
    expect(mockWarn).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        feature: "kb-upload",
        op: "linearize",
        message: "pdf linearization failed",
        extra: expect.objectContaining({
          reason: "non_zero_exit",
          detail: "exit=2 stderr=...",
          inputSize: 3,
          userId: "u2",
          path: "path/broken.pdf",
          durationMs: expect.any(Number),
        }),
      }),
    );
  });

  it("signed-PDF skip returns raw buffer silently", async () => {
    mockLinearize.mockResolvedValue({ ok: false, reason: "skip_signed" });
    const f = fakeFile(new Uint8Array([0x99]));
    const out = await prepareUploadPayload(
      f,
      "signed.pdf",
      "u1",
      "path/signed.pdf",
    );
    expect(out).toEqual(Buffer.from([0x99]));
    expect(mockWarn).not.toHaveBeenCalled();
  });
});
