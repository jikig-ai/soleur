import { describe, it, expect } from "vitest";
import { validateFiles } from "@/lib/validate-files";
import {
  MAX_ATTACHMENT_SIZE,
  MAX_ATTACHMENTS_PER_MESSAGE,
} from "@/lib/attachment-constants";

function file(name: string, type: string, body: BlobPart = "# notes") {
  return new File([body], name, { type, lastModified: 1_700_000_000_000 });
}

describe("validateFiles — markdown / plain text", () => {
  it.each([
    "",
    "text/markdown",
    "text/x-markdown",
    "text/markdown;charset=utf-8",
    "application/octet-stream",
    "application/x-genesis-rom",
  ])("accepts an .md reported as %j and canonicalizes it to text/markdown", (type) => {
    const { valid, error } = validateFiles(
      [file("2026-01-01-onboarding-notes.md", type)],
      0,
    );
    expect(error).toBeUndefined();
    expect(valid).toHaveLength(1);
    // Every downstream `file.type` read (presign body, Storage PUT header,
    // AttachmentRef) must see the canonical type.
    expect(valid[0]!.type).toBe("text/markdown");
    expect(valid[0]!.name).toBe("2026-01-01-onboarding-notes.md");
    expect(valid[0]!.lastModified).toBe(1_700_000_000_000);
  });

  it("accepts a .txt reported as empty and canonicalizes it to text/plain", () => {
    const { valid, error } = validateFiles([file("notes.txt", "")], 0);
    expect(error).toBeUndefined();
    expect(valid[0]!.type).toBe("text/plain");
  });

  it("does not re-wrap a file whose type is already canonical", () => {
    const f = file("notes.txt", "text/plain");
    const { valid } = validateFiles([f], 0);
    expect(valid[0]).toBe(f);
  });

  it.each([
    ["evil.md", "application/x-msdownload"],
    ["x.md", "text/html"],
    ["x.py", "text/plain"],
    ["notes", "text/plain"],
    ["virus.exe", "application/octet-stream"],
  ])("rejects %j reported as %j with the unsupported-type message", (name, type) => {
    const { valid, error } = validateFiles([file(name, type)], 0);
    expect(valid).toHaveLength(0);
    expect(error).toBe(`"${name}" is not a supported file type.`);
  });

  it("rejects a 0-byte file with an 'is empty' message", () => {
    const { valid, error } = validateFiles([file("empty.md", "", "")], 0);
    expect(valid).toHaveLength(0);
    expect(error).toBe('"empty.md" is empty.');
  });

  it("keeps a mixed batch's rejection message next to the valid file", () => {
    const { valid, error } = validateFiles(
      [file("ok.md", ""), file("bad.exe", "application/octet-stream")],
      0,
    );
    expect(valid).toHaveLength(1);
    expect(error).toBe('"bad.exe" is not a supported file type.');
  });
});

describe("validateFiles — several rejections in one batch", () => {
  it("names every skipped file instead of only the last", () => {
    const { valid, error } = validateFiles(
      [file("a.exe", "application/octet-stream"), file("ok.md", ""), file("b.py", "text/plain")],
      0,
    );
    expect(valid).toHaveLength(1);
    expect(error).toMatch(/^2 files skipped:/);
    expect(error).toContain('"a.exe" is not a supported file type.');
    expect(error).toContain('"b.py" is not a supported file type.');
  });

  it("keeps the single-file message unchanged", () => {
    const { error } = validateFiles([file("a.exe", "application/octet-stream")], 0);
    expect(error).toBe('"a.exe" is not a supported file type.');
  });
});

describe("validateFiles — unchanged behavior", () => {
  it("still accepts images and PDFs by reported type", () => {
    const { valid, error } = validateFiles(
      [file("a.png", "image/png"), file("b.pdf", "application/pdf")],
      0,
    );
    expect(error).toBeUndefined();
    expect(valid).toHaveLength(2);
  });

  it("does not let an .md name relabel an image", () => {
    const { valid } = validateFiles([file("x.md", "image/png")], 0);
    expect(valid[0]!.type).toBe("image/png");
  });

  it("enforces the per-message file cap", () => {
    const { valid, error } = validateFiles(
      [file("a.md", ""), file("b.md", "")],
      MAX_ATTACHMENTS_PER_MESSAGE - 1,
    );
    expect(valid).toHaveLength(1);
    expect(error).toMatch(/Maximum \d+ files per message/);
  });

  it("enforces the 20 MB size cap for text files too", () => {
    const big = file("big.txt", "text/plain", "x");
    Object.defineProperty(big, "size", { value: MAX_ATTACHMENT_SIZE + 1 });
    const { valid, error } = validateFiles([big], 0);
    expect(valid).toHaveLength(0);
    expect(error).toMatch(/exceeds the 20 MB size limit/);
  });
});
