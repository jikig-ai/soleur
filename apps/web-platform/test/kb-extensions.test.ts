import { describe, it, expect } from "vitest";
import { getKbExtension, isMarkdownKbPath } from "@/lib/kb-extensions";

describe("getKbExtension", () => {
  it("returns lowercased extension with leading dot", () => {
    expect(getKbExtension("foo.md")).toBe(".md");
  });

  it("case-folds uppercase extensions", () => {
    expect(getKbExtension("FOO.MD")).toBe(".md");
  });

  it("handles nested paths", () => {
    expect(getKbExtension("notes/doc.PDF")).toBe(".pdf");
  });

  it("returns empty for extensionless paths", () => {
    expect(getKbExtension("noext")).toBe("");
    expect(getKbExtension("notes/readme")).toBe("");
  });

  it("treats leading-dot-only filenames as no extension (unix hidden files)", () => {
    expect(getKbExtension(".hidden")).toBe("");
    expect(getKbExtension("dir/.config")).toBe("");
  });

  it("returns only the last segment for multi-dot filenames", () => {
    expect(getKbExtension("a/b/c.tar.gz")).toBe(".gz");
    expect(getKbExtension("archive.tar.bz2")).toBe(".bz2");
  });

  it("returns empty for empty string", () => {
    expect(getKbExtension("")).toBe("");
  });

  it("ignores dots in directory segments", () => {
    expect(getKbExtension("v1.2/readme")).toBe("");
  });
});

describe("isMarkdownKbPath", () => {
  it("treats .md as markdown", () => {
    expect(isMarkdownKbPath("foo.md")).toBe(true);
  });

  it("treats uppercase .MD as markdown (regression for #2317)", () => {
    expect(isMarkdownKbPath("NOTES.MD")).toBe(true);
    expect(isMarkdownKbPath("dir/NOTES.Md")).toBe(true);
  });

  it("treats extensionless paths as markdown", () => {
    expect(isMarkdownKbPath("foo")).toBe(true);
    expect(isMarkdownKbPath("notes/readme")).toBe(true);
    expect(isMarkdownKbPath("")).toBe(true);
  });

  it("treats binary extensions as non-markdown", () => {
    expect(isMarkdownKbPath("foo.pdf")).toBe(false);
    expect(isMarkdownKbPath("foo.PDF")).toBe(false);
    expect(isMarkdownKbPath("images/logo.png")).toBe(false);
    expect(isMarkdownKbPath("data.csv")).toBe(false);
  });

  it("treats hidden files (leading dot only) as markdown (no extension)", () => {
    expect(isMarkdownKbPath(".gitignore")).toBe(true);
  });
});
