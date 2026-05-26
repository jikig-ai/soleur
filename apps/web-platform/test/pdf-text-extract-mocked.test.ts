// pdfjs-mocked tests for `pdf-text-extract.ts` (#3429).
//
// Lives in its own file so vitest's per-file module isolation prevents the
// `vi.mock("pdfjs-dist/legacy/build/pdf.mjs", …)` factory from leaking into
// the real-pdfjs tests in `pdf-text-extract.test.ts`. `vi.mock` calls are
// hoisted to the top of THIS file only.
//
// Covers:
//   - extractPdfMetadata > timeout (#3429) — when `getDocument` exceeds
//     METADATA_READ_TIMEOUT_MS, the function returns the timeout shape
//     and calls `loadingTask.destroy()` once to release the worker.
//
// Note: `lazy_import_failed` direct coverage (#3438) lives in
// `pdf-text-extract.test.ts` using the `vi.doMock` + `vi.resetModules`
// pattern at test scope, which is the only shape that can induce a true
// import REJECTION (vitest's per-file `vi.mock` cannot — the factory IS
// the import).

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const { destroySpy, getDocumentSpy } = vi.hoisted(() => ({
  destroySpy: vi.fn(() => Promise.resolve()),
  getDocumentSpy: vi.fn(),
}));

vi.mock("pdfjs-dist/legacy/build/pdf.mjs", () => ({
  getDocument: getDocumentSpy,
}));

import {
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
