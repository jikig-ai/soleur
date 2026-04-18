import { describe, it, expect } from "vitest";
import {
  classifyByExtension,
  classifyByContentType,
  type FileKind,
} from "@/lib/kb-file-kind";
import { CONTENT_TYPE_MAP } from "@/server/kb-limits";

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

describe("parity — CONTENT_TYPE_MAP ↔ classifyByContentType", () => {
  // Every extension in CONTENT_TYPE_MAP must have an explicit expected kind.
  // Adding a new entry to CONTENT_TYPE_MAP without updating this table fails
  // the "covers every entry" assertion below — preventing silent drift where
  // a new inline Content-Type quietly falls through to "download".
  const EXPECTED_KIND_BY_EXT: Record<string, Exclude<FileKind, "markdown">> = {
    ".png": "image",
    ".jpg": "image",
    ".jpeg": "image",
    ".gif": "image",
    ".webp": "image",
    ".svg": "image",
    ".pdf": "pdf",
    ".csv": "download",
    ".txt": "text",
    ".docx": "download",
  };

  it("every CONTENT_TYPE_MAP entry has an expected kind in the parity table", () => {
    const mapExts = Object.keys(CONTENT_TYPE_MAP).sort();
    const tableExts = Object.keys(EXPECTED_KIND_BY_EXT).sort();
    expect(mapExts).toEqual(tableExts);
  });

  it.each(Object.entries(EXPECTED_KIND_BY_EXT))(
    "classifyByContentType for %s maps to the expected kind",
    (ext, expected) => {
      const contentType = CONTENT_TYPE_MAP[ext];
      // Use the disposition the serving layer applies: .docx is
      // attachment-forced; everything else is inline.
      const disposition = ext === ".docx" ? "attachment" : "inline";
      expect(classifyByContentType(contentType, disposition)).toBe(expected);
    },
  );
});
