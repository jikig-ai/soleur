// pdfjs-mocked tests for `pdf-text-extract.ts` (#3429 + #3438).
//
// Lives in its own file so vitest's per-file module isolation prevents the
// `vi.mock("pdfjs-dist/legacy/build/pdf.mjs", …)` factory from leaking into
// the real-pdfjs tests in `pdf-text-extract.test.ts`. `vi.mock` calls are
// hoisted to the top of THIS file only.
//
// Covers:
//   1. extractPdfText > lazy_import_failed (#3438 fold-in) — when the
//      dynamic `import("pdfjs-dist/...")` rejects, the typed error class
//      surfaces correctly. Previously had no direct test (only an
//      indirect path via runtime engine drift).
//   2. extractPdfMetadata > timeout (#3429) — when `getDocument` exceeds
//      METADATA_READ_TIMEOUT_MS, the function returns the timeout shape
//      and calls `loadingTask.destroy()` once to release the worker.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const { destroySpy, getDocumentSpy } = vi.hoisted(() => ({
  destroySpy: vi.fn(() => Promise.resolve()),
  getDocumentSpy: vi.fn(),
}));

vi.mock("pdfjs-dist/legacy/build/pdf.mjs", () => ({
  getDocument: getDocumentSpy,
}));

import {
  extractPdfText,
  extractPdfMetadata,
  METADATA_READ_TIMEOUT_MS,
} from "@/server/pdf-text-extract";

beforeEach(() => {
  destroySpy.mockClear();
  getDocumentSpy.mockReset();
});

afterEach(() => {
  vi.useRealTimers();
});

// NOTE: this describe block was originally drafted as a `lazy_import_failed`
// fold-in for #3438, but the mock-factory model of `vi.mock` cannot induce
// a true import REJECTION (the factory IS the import — vitest invokes it
// synchronously, errors propagate). The synchronous-throw-at-getDocument
// shape exercised here lands in `extractPdfText`'s outer try/catch
// (parse_error branch), NOT the lazy_import_failed branch above. A real
// lazy_import_failed coverage would require a different mock harness
// (e.g., `vi.doMock` with rejected factory in an isolated test file) and
// remains an open follow-up — see `#3438`. Naming the test honestly here
// to avoid the misleading-coverage signal flagged in PR #3430 review.
describe("extractPdfText post-import getDocument throw (parse_error path)", () => {
  it("returns { error: 'parse_error' } when getDocument throws synchronously at the call site", async () => {
    getDocumentSpy.mockImplementation(() => {
      throw new Error("synthetic-pdfjs-init-failure");
    });
    const buf = Buffer.from("%PDF-1.4\nfake");
    const result = await extractPdfText(buf, 50_000);
    expect(result).not.toBeNull();
    expect(result && "error" in result).toBe(true);
    if (!result || !("error" in result)) return;
    expect(result.error).toBe("parse_error");
  });
});

describe("extractPdfMetadata timeout (#3429)", () => {
  it(
    "returns { ok: false, reason: 'timeout' } when getDocument exceeds METADATA_READ_TIMEOUT_MS, and calls loadingTask.destroy() once",
    { timeout: METADATA_READ_TIMEOUT_MS + 2000 },
    async () => {
      // Mock pdfjs to return a never-resolving loadingTask. The race
      // against METADATA_READ_TIMEOUT_MS (3s real time) must win, the
      // function must return the timeout shape, and loadingTask.destroy()
      // must be invoked once to release the worker + xref allocation.
      //
      // Real timers — vitest fake-timer + dynamic-import interaction is
      // unreliable here (the lazy `await import("pdfjs-dist/...")` in
      // `extractPdfMetadata` defers the setTimeout queue past the
      // advanceTimersByTimeAsync trigger window). Paying 3s once is the
      // cheaper/more-reliable shape than fighting the fake-timer/Promise
      // ordering. Test-level timeout cap above prevents indefinite hang.
      getDocumentSpy.mockImplementation(() => ({
        promise: new Promise(() => {}),
        destroy: destroySpy,
      }));
      const buf = Buffer.from("%PDF-1.4\nfake-but-pdfjs-mocked");
      const result = await extractPdfMetadata(buf);
      expect(result.ok).toBe(false);
      if (result.ok) return;
      expect(result.reason).toBe("timeout");
      expect(destroySpy).toHaveBeenCalledTimes(1);
    },
  );
});
