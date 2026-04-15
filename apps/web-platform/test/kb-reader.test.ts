import fs from "fs";
import os from "os";
import path from "path";
import { describe, test, expect, beforeEach, afterEach } from "vitest";
import {
  buildTree,
  readContent,
  searchKb,
  KbNotFoundError,
  KbAccessDeniedError,
  KbValidationError,
  type TreeNode,
} from "../server/kb-reader";

let tmpWorkspace: string;
let kbRoot: string;

beforeEach(() => {
  tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "kb-reader-test-"));
  kbRoot = path.join(tmpWorkspace, "knowledge-base");
  fs.mkdirSync(kbRoot, { recursive: true });
});

afterEach(() => {
  fs.rmSync(tmpWorkspace, { recursive: true, force: true });
});

describe("buildTree", () => {
  test("returns empty tree for empty directory", async () => {
    const tree = await buildTree(kbRoot);
    expect(tree.name).toBe("knowledge-base");
    expect(tree.type).toBe("directory");
    expect(tree.children).toEqual([]);
  });

  test("includes .md files", async () => {
    fs.writeFileSync(path.join(kbRoot, "readme.md"), "# Hello");
    const tree = await buildTree(kbRoot);
    expect(tree.children).toHaveLength(1);
    expect(tree.children![0]).toMatchObject({
      name: "readme.md",
      type: "file",
      path: "readme.md",
    });
  });

  test("includes all file types, not just .md", async () => {
    fs.writeFileSync(path.join(kbRoot, "test.md"), "# Hello");
    fs.writeFileSync(path.join(kbRoot, "image.png"), "fake-png");
    fs.writeFileSync(path.join(kbRoot, "data.csv"), "a,b,c");
    fs.writeFileSync(path.join(kbRoot, "doc.pdf"), "fake-pdf");
    const tree = await buildTree(kbRoot);
    expect(tree.children).toHaveLength(4);
    const names = tree.children!.map((c) => c.name).sort();
    expect(names).toEqual(["data.csv", "doc.pdf", "image.png", "test.md"]);
    // Each file node should have an extension field
    for (const child of tree.children!) {
      expect(child.extension).toBeDefined();
    }
    const extMap = Object.fromEntries(
      tree.children!.map((c) => [c.name, c.extension]),
    );
    expect(extMap["test.md"]).toBe(".md");
    expect(extMap["image.png"]).toBe(".png");
    expect(extMap["data.csv"]).toBe(".csv");
    expect(extMap["doc.pdf"]).toBe(".pdf");
  });

  test("builds nested directory structure", async () => {
    fs.mkdirSync(path.join(kbRoot, "project", "learnings"), {
      recursive: true,
    });
    fs.writeFileSync(
      path.join(kbRoot, "project", "learnings", "lesson.md"),
      "# Lesson",
    );
    const tree = await buildTree(kbRoot);
    expect(tree.children).toHaveLength(1);
    const project = tree.children![0];
    expect(project.name).toBe("project");
    expect(project.type).toBe("directory");
    expect(project.children).toHaveLength(1);
    const learnings = project.children![0];
    expect(learnings.name).toBe("learnings");
    expect(learnings.children![0].path).toBe("project/learnings/lesson.md");
  });

  test("excludes empty directories", async () => {
    fs.mkdirSync(path.join(kbRoot, "empty-dir"));
    fs.mkdirSync(path.join(kbRoot, "has-files"));
    fs.writeFileSync(path.join(kbRoot, "has-files", "file.md"), "content");
    const tree = await buildTree(kbRoot);
    expect(tree.children).toHaveLength(1);
    expect(tree.children![0].name).toBe("has-files");
  });

  test("sorts directories first, then files, alphabetically", async () => {
    fs.mkdirSync(path.join(kbRoot, "zebra"));
    fs.writeFileSync(path.join(kbRoot, "zebra", "z.md"), "z");
    fs.mkdirSync(path.join(kbRoot, "alpha"));
    fs.writeFileSync(path.join(kbRoot, "alpha", "a.md"), "a");
    fs.writeFileSync(path.join(kbRoot, "beta.md"), "b");
    fs.writeFileSync(path.join(kbRoot, "aaa.md"), "a");
    const tree = await buildTree(kbRoot);
    const names = tree.children!.map((c) => c.name);
    expect(names).toEqual(["alpha", "zebra", "aaa.md", "beta.md"]);
  });

  test("includes modifiedAt ISO timestamp on file nodes", async () => {
    fs.writeFileSync(path.join(kbRoot, "readme.md"), "# Hello");
    const tree = await buildTree(kbRoot);
    const file = tree.children![0];
    expect(file.modifiedAt).toBeDefined();
    expect(typeof file.modifiedAt).toBe("string");
    // Must be valid ISO 8601
    const parsed = new Date(file.modifiedAt!);
    expect(parsed.getTime()).not.toBeNaN();
  });

  test("does not include modifiedAt on directory nodes", async () => {
    fs.mkdirSync(path.join(kbRoot, "project"));
    fs.writeFileSync(path.join(kbRoot, "project", "doc.md"), "# Doc");
    const tree = await buildTree(kbRoot);
    const dir = tree.children![0];
    expect(dir.type).toBe("directory");
    expect(dir.modifiedAt).toBeUndefined();
  });

  test("handles missing knowledge-base directory gracefully", async () => {
    const missingKb = path.join(tmpWorkspace, "nonexistent");
    const tree = await buildTree(missingKb);
    expect(tree.children).toEqual([]);
  });

  test("includes extension field on file nodes", async () => {
    fs.writeFileSync(path.join(kbRoot, "readme.md"), "# Hello");
    fs.writeFileSync(path.join(kbRoot, "photo.png"), "fake-png");
    const tree = await buildTree(kbRoot);
    for (const child of tree.children!) {
      expect(child.type).toBe("file");
      expect(child.extension).toBeDefined();
    }
    const mdNode = tree.children!.find((c) => c.name === "readme.md");
    const pngNode = tree.children!.find((c) => c.name === "photo.png");
    expect(mdNode!.extension).toBe(".md");
    expect(pngNode!.extension).toBe(".png");
  });

  test("does not include extension field on directory nodes", async () => {
    fs.mkdirSync(path.join(kbRoot, "subdir"));
    fs.writeFileSync(path.join(kbRoot, "subdir", "file.md"), "# Doc");
    const tree = await buildTree(kbRoot);
    const dir = tree.children![0];
    expect(dir.type).toBe("directory");
    expect(dir.extension).toBeUndefined();
  });

  test("includes all allowed file types", async () => {
    const extensions = [
      "file.png",
      "file.jpg",
      "file.jpeg",
      "file.gif",
      "file.webp",
      "file.pdf",
      "file.csv",
      "file.txt",
      "file.docx",
    ];
    for (const name of extensions) {
      fs.writeFileSync(path.join(kbRoot, name), "fake-content");
    }
    const tree = await buildTree(kbRoot);
    expect(tree.children).toHaveLength(extensions.length);
    const treeNames = tree.children!.map((c) => c.name).sort();
    expect(treeNames).toEqual([...extensions].sort());
  });
});

describe("readContent", () => {
  test("returns parsed frontmatter and raw content", async () => {
    const content = `---
category: security
tags:
  - cwe-22
---

# Path Traversal

Never use startsWith.`;
    fs.writeFileSync(path.join(kbRoot, "doc.md"), content);
    const result = await readContent(kbRoot, "doc.md");
    expect(result.path).toBe("doc.md");
    expect(result.frontmatter).toEqual({
      category: "security",
      tags: ["cwe-22"],
    });
    expect(result.content).toContain("# Path Traversal");
    expect(result.content).not.toContain("---");
  });

  test("returns empty frontmatter for files without it", async () => {
    fs.writeFileSync(path.join(kbRoot, "plain.md"), "# Just Markdown");
    const result = await readContent(kbRoot, "plain.md");
    expect(result.frontmatter).toEqual({});
    expect(result.content).toBe("# Just Markdown");
  });

  test("returns empty frontmatter on malformed YAML", async () => {
    const content = `---
broken: [unclosed
---

# Content`;
    fs.writeFileSync(path.join(kbRoot, "bad.md"), content);
    const result = await readContent(kbRoot, "bad.md");
    expect(result.frontmatter).toEqual({});
    expect(result.content).toContain("# Content");
  });

  test("throws KbNotFoundError for non-existent file", async () => {
    await expect(readContent(kbRoot, "missing.md")).rejects.toThrow(KbNotFoundError);
  });

  test("throws KbNotFoundError for non-.md file", async () => {
    fs.writeFileSync(path.join(kbRoot, "data.json"), "{}");
    await expect(readContent(kbRoot, "data.json")).rejects.toThrow(KbNotFoundError);
  });

  test("throws KbAccessDeniedError for path traversal attempt", async () => {
    // Use a .md extension so it passes the extension check and hits the path validation
    await expect(readContent(kbRoot, "../../etc/passwd.md")).rejects.toThrow(KbAccessDeniedError);
  });

  test("throws KbAccessDeniedError for path with null bytes", async () => {
    await expect(readContent(kbRoot, "file\0.md")).rejects.toThrow(KbAccessDeniedError);
  });

  test("throws KbNotFoundError for directory path without extension", async () => {
    fs.mkdirSync(path.join(kbRoot, "project"), { recursive: true });
    await expect(readContent(kbRoot, "project")).rejects.toThrow(KbNotFoundError);
  });

  test("throws KbValidationError for file over 1MB", async () => {
    const bigContent = "x".repeat(1024 * 1024 + 1);
    fs.writeFileSync(path.join(kbRoot, "big.md"), bigContent);
    await expect(readContent(kbRoot, "big.md")).rejects.toThrow(KbValidationError);
  });

  test("reads nested file paths", async () => {
    fs.mkdirSync(path.join(kbRoot, "project", "plans"), { recursive: true });
    fs.writeFileSync(
      path.join(kbRoot, "project", "plans", "plan.md"),
      "# Plan",
    );
    const result = await readContent(kbRoot, "project/plans/plan.md");
    expect(result.path).toBe("project/plans/plan.md");
    expect(result.content).toBe("# Plan");
  });
});

describe("searchKb", () => {
  beforeEach(() => {
    fs.writeFileSync(
      path.join(kbRoot, "doc1.md"),
      "# Security\n\nPath traversal is dangerous.\nAlways validate paths.",
    );
    fs.writeFileSync(
      path.join(kbRoot, "doc2.md"),
      "# Testing\n\nWrite tests for path validation.",
    );
    fs.mkdirSync(path.join(kbRoot, "sub"));
    fs.writeFileSync(
      path.join(kbRoot, "sub", "doc3.md"),
      "# Other\n\nNo matches here.",
    );
  });

  test("finds matches across files", async () => {
    const result = await searchKb(kbRoot, "path");
    expect(result.results.length).toBeGreaterThanOrEqual(2);
    expect(result.total).toBeGreaterThanOrEqual(2);
  });

  test("search is case-insensitive", async () => {
    const result = await searchKb(kbRoot, "PATH");
    expect(result.results.length).toBeGreaterThanOrEqual(2);
  });

  test("returns highlight offsets as character indices", async () => {
    const result = await searchKb(kbRoot, "traversal");
    const doc1 = result.results.find((r) => r.path === "doc1.md");
    expect(doc1).toBeDefined();
    expect(doc1!.matches.length).toBeGreaterThanOrEqual(1);
    const match = doc1!.matches[0];
    expect(match.line).toBeGreaterThan(0);
    expect(match.text).toContain("traversal");
    expect(match.highlight).toHaveLength(2);
    const [start, end] = match.highlight;
    expect(match.text.substring(start, end).toLowerCase()).toBe("traversal");
  });

  test("sorts results by match count descending", async () => {
    const result = await searchKb(kbRoot, "path");
    if (result.results.length >= 2) {
      const counts = result.results.map((r) => r.matches.length);
      for (let i = 1; i < counts.length; i++) {
        expect(counts[i]).toBeLessThanOrEqual(counts[i - 1]);
      }
    }
  });

  test("caps results at 100", async () => {
    // Create 101 files each with a match
    for (let i = 0; i < 101; i++) {
      fs.writeFileSync(
        path.join(kbRoot, `generated-${i}.md`),
        `matchme content ${i}`,
      );
    }
    const result = await searchKb(kbRoot, "matchme");
    expect(result.results.length).toBeLessThanOrEqual(100);
    expect(result.total).toBe(101);
  });

  test("escapes special regex characters in query", async () => {
    fs.writeFileSync(path.join(kbRoot, "special.md"), "array[0] is first");
    const result = await searchKb(kbRoot, "array[0]");
    expect(result.results.length).toBeGreaterThanOrEqual(1);
  });

  test("returns empty results for no matches", async () => {
    const result = await searchKb(kbRoot, "xyznonexistent");
    expect(result.results).toEqual([]);
    expect(result.total).toBe(0);
  });

  test("throws KbValidationError for empty query", async () => {
    await expect(searchKb(kbRoot, "")).rejects.toThrow(KbValidationError);
  });

  test("throws KbValidationError for query exceeding 200 characters", async () => {
    const longQuery = "a".repeat(201);
    await expect(searchKb(kbRoot, longQuery)).rejects.toThrow(KbValidationError);
  });

  test("includes frontmatter in results", async () => {
    fs.writeFileSync(
      path.join(kbRoot, "with-fm.md"),
      "---\ncategory: test\n---\n\nSearchable content here.",
    );
    const result = await searchKb(kbRoot, "Searchable");
    const match = result.results.find((r) => r.path === "with-fm.md");
    expect(match).toBeDefined();
    expect(match!.frontmatter).toEqual({ category: "test" });
  });

  test("finds binary files by filename match", async () => {
    fs.writeFileSync(path.join(kbRoot, "invoice-q1.pdf"), "fake-pdf-bytes");
    fs.writeFileSync(path.join(kbRoot, "diagram.png"), "fake-png-bytes");
    const pdfHit = await searchKb(kbRoot, "invoice");
    const pdfRow = pdfHit.results.find((r) => r.path === "invoice-q1.pdf");
    expect(pdfRow).toBeDefined();
    expect(pdfRow!.kind).toBe("filename");
    const pngHit = await searchKb(kbRoot, "diagram");
    expect(pngHit.results.some((r) => r.path === "diagram.png")).toBe(true);
  });

  test("collectSearchableFiles returns all allowed extensions", async () => {
    fs.writeFileSync(path.join(kbRoot, "doc.md"), "markdown");
    fs.writeFileSync(path.join(kbRoot, "image.png"), "png");
    fs.writeFileSync(path.join(kbRoot, "data.csv"), "csv,row");
    fs.writeFileSync(path.join(kbRoot, "spec.pdf"), "fake-pdf");
    fs.writeFileSync(path.join(kbRoot, "report.docx"), "fake-docx");
    // Filename match across all allowed extensions
    const docResult = await searchKb(kbRoot, "doc");
    const docPaths = new Set(docResult.results.map((r) => r.path));
    expect(docPaths.has("doc.md")).toBe(true);
    expect(docPaths.has("spec.pdf")).toBe(false); // "doc" not in "spec.pdf"
    const imgResult = await searchKb(kbRoot, "image");
    expect(imgResult.results.some((r) => r.path === "image.png")).toBe(true);
    const reportResult = await searchKb(kbRoot, "report");
    expect(reportResult.results.some((r) => r.path === "report.docx")).toBe(true);
  });

  test("content-searches .txt and .csv files", async () => {
    fs.writeFileSync(path.join(kbRoot, "notes.txt"), "the quick brown fox");
    fs.writeFileSync(path.join(kbRoot, "data.csv"), "id,name\n1,widget");
    const txtHit = await searchKb(kbRoot, "brown");
    const txtRow = txtHit.results.find((r) => r.path === "notes.txt");
    expect(txtRow).toBeDefined();
    expect(txtRow!.kind).toBe("content");
    const csvHit = await searchKb(kbRoot, "widget");
    const csvRow = csvHit.results.find((r) => r.path === "data.csv");
    expect(csvRow).toBeDefined();
    expect(csvRow!.kind).toBe("content");
  });

  test("does not read binary file bytes for content match", async () => {
    // Bytes that would match "body" if scanned — must not surface
    fs.writeFileSync(path.join(kbRoot, "a.pdf"), "header PDF body PDF");
    const hit = await searchKb(kbRoot, "body");
    expect(hit.results.find((r) => r.path === "a.pdf")).toBeUndefined();
  });

  test("content matches rank above pure filename matches", async () => {
    fs.writeFileSync(path.join(kbRoot, "widget-spec.pdf"), "bytes");
    fs.writeFileSync(path.join(kbRoot, "widget-notes.md"), "widget widget widget");
    const hit = await searchKb(kbRoot, "widget");
    expect(hit.results[0].path).toBe("widget-notes.md");
    expect(hit.results[0].kind).toBe("content");
    const last = hit.results[hit.results.length - 1];
    expect(last.path).toBe("widget-spec.pdf");
    expect(last.kind).toBe("filename");
  });

  test("filename match is case-insensitive on extension", async () => {
    fs.writeFileSync(path.join(kbRoot, "Q1-Invoice.PDF"), "bytes");
    const hit = await searchKb(kbRoot, "invoice");
    expect(hit.results.some((r) => r.path === "Q1-Invoice.PDF")).toBe(true);
  });
});
