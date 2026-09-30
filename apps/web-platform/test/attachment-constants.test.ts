import { describe, it, expect } from "vitest";
import {
  ALLOWED_ATTACHMENT_TYPES,
  ATTACHMENT_ACCEPT,
  ATTACHMENT_EXTENSION_BY_TYPE,
  fileExtension,
  resolveAttachmentContentType,
} from "@/lib/attachment-constants";

const resolve = (contentType: string, filename: string) =>
  resolveAttachmentContentType({ contentType, filename });

describe("fileExtension", () => {
  it.each([
    ["notes.md", "md"],
    ["NOTES.MD", "md"],
    ["a.b.c.txt", "txt"],
    ["dir/sub.name/file.md", "md"],
  ])("%s -> %s", (name, ext) => {
    expect(fileExtension(name)).toBe(ext);
  });

  it.each(["md", ".md", "notes", "notes.md ", "notes.md.", "", ".gitignore"])(
    "%j has no extension the allowlist can use",
    (name) => {
      expect(["md", "txt"]).not.toContain(fileExtension(name));
    },
  );

  it("does not throw on non-string input", () => {
    expect(fileExtension(undefined as unknown as string)).toBe("");
    expect(fileExtension(42 as unknown as string)).toBe("");
  });
});

describe("resolveAttachmentContentType — markdown", () => {
  it.each([
    "",
    "text/markdown",
    "text/x-markdown",
    "text/x-web-markdown",
    "Text/Markdown",
    "text/markdown;charset=utf-8",
    "text/markdown; charset=UTF-8",
    "application/octet-stream",
    "application/x-genesis-rom",
    "application/x-markdown",
    "text/plain",
  ])(".md typed %j resolves to text/markdown", (reported) => {
    expect(resolve(reported, "2026-01-01-onboarding-notes.md")).toBe(
      "text/markdown",
    );
  });

  it("is case-insensitive on the extension", () => {
    expect(resolve("", "NOTES.MD")).toBe("text/markdown");
  });

  it("keeps multi-dot names", () => {
    expect(resolve("text/markdown;charset=utf-8", "a.b.md")).toBe(
      "text/markdown",
    );
  });
});

describe("resolveAttachmentContentType — plain text", () => {
  it.each(["", "text/plain", "application/octet-stream", "text/x-log"])(
    ".txt typed %j resolves to text/plain",
    (reported) => {
      expect(resolve(reported, "notes.txt")).toBe("text/plain");
    },
  );

  it("is case-insensitive on the extension", () => {
    expect(resolve("", "NOTES.TXT")).toBe("text/plain");
  });
});

describe("resolveAttachmentContentType — rejections", () => {
  it.each([
    ["application/x-msdownload", "evil.md"],
    ["text/html", "x.md"],
    ["text/html", "x.txt"],
    ["text/plain", "x.py"],
    ["text/plain", "notes"],
    ["text/plain", "md"],
    ["text/plain", ".md"],
    ["", "a.md "],
    ["", "a.md."],
    ["", "a.md‮"],
    ["application/octet-stream", "virus.exe"],
    ["application/octet-stream", "doc.pdf"],
  ])("%j + %j -> null", (reported, filename) => {
    expect(resolve(reported, filename)).toBeNull();
  });

  it("does not throw on a non-string filename", () => {
    expect(
      resolveAttachmentContentType({
        contentType: "text/plain",
        filename: undefined as unknown as string,
      }),
    ).toBeNull();
  });
});

describe("resolveAttachmentContentType — binary types are unchanged", () => {
  it.each([
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
    "application/pdf",
  ])("%s passes through", (type) => {
    expect(resolve(type, "file.bin")).toBe(type);
  });

  it("does not let an .md name relabel an image", () => {
    expect(resolve("image/png", "x.md")).toBe("image/png");
  });
});

describe("allowlist <-> extension map parity", () => {
  it("has an extension for every allowed type, and nothing extra", () => {
    // Anti-vacuity: the set must actually contain the seven types.
    expect(ALLOWED_ATTACHMENT_TYPES.size).toBeGreaterThanOrEqual(7);
    expect(Object.keys(ATTACHMENT_EXTENSION_BY_TYPE).length).toBe(
      ALLOWED_ATTACHMENT_TYPES.size,
    );
    for (const type of ALLOWED_ATTACHMENT_TYPES) {
      expect(ATTACHMENT_EXTENSION_BY_TYPE[type]).toMatch(/^[a-z0-9]+$/);
    }
  });

  it("maps the two new types", () => {
    expect(ATTACHMENT_EXTENSION_BY_TYPE["text/markdown"]).toBe("md");
    expect(ATTACHMENT_EXTENSION_BY_TYPE["text/plain"]).toBe("txt");
  });
});

describe("ATTACHMENT_ACCEPT", () => {
  it("offers md and txt in the picker, without generic text/plain", () => {
    const parts = ATTACHMENT_ACCEPT.split(",");
    expect(parts).toContain(".md");
    expect(parts).toContain(".txt");
    expect(parts).toContain("text/markdown");
    expect(parts).toContain("application/pdf");
    // text/plain would make the picker offer every .log/.py only to reject it.
    expect(parts).not.toContain("text/plain");
  });
});
