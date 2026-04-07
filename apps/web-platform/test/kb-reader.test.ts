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
    expect(tree.children![0]).toEqual({
      name: "readme.md",
      type: "file",
      path: "readme.md",
    });
  });

  test("excludes non-.md files", async () => {
    fs.writeFileSync(path.join(kbRoot, "data.json"), "{}");
    fs.writeFileSync(path.join(kbRoot, "readme.md"), "# Hello");
    const tree = await buildTree(kbRoot);
    expect(tree.children).toHaveLength(1);
    expect(tree.children![0].name).toBe("readme.md");
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

  test("handles missing knowledge-base directory gracefully", async () => {
    const missingKb = path.join(tmpWorkspace, "nonexistent");
    const tree = await buildTree(missingKb);
    expect(tree.children).toEqual([]);
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
});
