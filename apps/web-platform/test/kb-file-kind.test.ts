import { describe, it, expect } from "vitest";
import {
  classifyByExtension,
  classifyByContentType,
  type FileKind,
} from "@/lib/kb-file-kind";

describe("classifyByExtension", () => {
  it("returns 'markdown' for .md", () => {
    expect(classifyByExtension(".md")).toBe("markdown");
  });

  it("returns 'pdf' for .pdf", () => {
    expect(classifyByExtension(".pdf")).toBe("pdf");
  });

  it.each([".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"])(
    "returns 'image' for %s",
    (ext) => {
      expect(classifyByExtension(ext)).toBe("image");
    },
  );

  it("returns 'text' for .txt", () => {
    expect(classifyByExtension(".txt")).toBe("text");
  });

  it.each([".docx", ".zip", ".csv", ".bashrc", ""])(
    "returns 'download' for %s (non-inline extension)",
    (ext) => {
      expect(classifyByExtension(ext)).toBe("download");
    },
  );
});

describe("classifyByContentType", () => {
  it("returns 'pdf' for application/pdf + inline", () => {
    expect(classifyByContentType("application/pdf", "inline")).toBe("pdf");
  });

  it("returns 'image' for image/* + inline", () => {
    expect(classifyByContentType("image/png", "inline")).toBe("image");
    expect(classifyByContentType("image/svg+xml", "inline")).toBe("image");
  });

  it("returns 'text' for text/plain + inline", () => {
    expect(classifyByContentType("text/plain", "inline")).toBe("text");
  });

  it("returns 'download' when disposition is 'attachment' regardless of content-type", () => {
    expect(
      classifyByContentType(
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "attachment",
      ),
    ).toBe("download");
    // Disposition wins over an otherwise-inline content-type.
    expect(classifyByContentType("image/png", "attachment")).toBe("download");
  });

  it("returns 'download' for unknown content-type + inline", () => {
    expect(classifyByContentType("application/octet-stream", "inline")).toBe(
      "download",
    );
  });
});

describe("parity — owner viewer and shared viewer must agree", () => {
  it("classifyByExtension('.txt') === classifyByContentType('text/plain', 'inline')", () => {
    const byExt: FileKind = classifyByExtension(".txt");
    const byCt: FileKind = classifyByContentType("text/plain", "inline");
    expect(byExt).toBe(byCt);
    expect(byExt).toBe("text");
  });

  it("classifyByExtension('.pdf') === classifyByContentType('application/pdf', 'inline')", () => {
    expect(classifyByExtension(".pdf")).toBe(
      classifyByContentType("application/pdf", "inline"),
    );
  });

  it("classifyByExtension('.png') === classifyByContentType('image/png', 'inline')", () => {
    expect(classifyByExtension(".png")).toBe(
      classifyByContentType("image/png", "inline"),
    );
  });
});
