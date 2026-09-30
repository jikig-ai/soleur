import { describe, it, expect } from "vitest";
import { attachmentErrorCopy } from "@/lib/attachment-error-copy";

// Every error code `app/api/attachments/presign/route.ts` can return.
const PRESIGN_CODES = [
  "invalid_request",
  "unauthorized",
  "unsupported_file_type",
  "file_too_large",
  "conversation_not_found",
  "not_a_workspace_member",
  "upload_failed",
] as const;

const SPECIFIC_CODES = [
  "file_too_large",
  "unsupported_file_type",
  "conversation_not_found",
  "not_a_workspace_member",
  "unauthorized",
] as const;

const GENERIC = "Upload failed. Check your connection and try again.";

describe("attachmentErrorCopy", () => {
  it.each(PRESIGN_CODES)("maps %s to human copy, never the raw code", (code) => {
    const copy = attachmentErrorCopy(code);
    expect(copy.length).toBeGreaterThan(0);
    expect(copy).not.toBe(code);
    expect(copy).not.toContain("_");
  });

  it("falls back to the generic copy for undefined, empty and unknown input", () => {
    for (const input of [undefined, "", "some_future_code", "constructor", "toString", "__proto__", "Presign failed", "Upload to storage failed: 403"]) {
      expect(attachmentErrorCopy(input)).toBe(GENERIC);
    }
  });

  it("uses the generic copy for the non-actionable codes", () => {
    expect(attachmentErrorCopy("invalid_request")).toBe(GENERIC);
    expect(attachmentErrorCopy("upload_failed")).toBe(GENERIC);
  });

  it("gives the five specific codes pairwise-distinct copy that differs from the generic", () => {
    const copies = SPECIFIC_CODES.map((c) => attachmentErrorCopy(c));
    expect(new Set(copies).size).toBe(SPECIFIC_CODES.length);
    for (const copy of copies) expect(copy).not.toBe(GENERIC);
  });

  it("names the limit and the supported types where relevant", () => {
    expect(attachmentErrorCopy("file_too_large")).toContain("20 MB");
    expect(attachmentErrorCopy("unsupported_file_type")).toContain(".md");
  });
});
