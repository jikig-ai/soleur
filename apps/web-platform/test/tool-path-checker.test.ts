import { describe, test, expect } from "vitest";
import {
  FILE_TOOLS,
  SAFE_TOOLS,
  UNVERIFIED_PARAM_TOOLS,
  extractToolPath,
  isFileTool,
  isSafeTool,
} from "../server/tool-path-checker";
import { isPathInWorkspace } from "../server/sandbox";

const WORKSPACE = "/workspaces/user1";

// ---------------------------------------------------------------------------
// extractToolPath
// ---------------------------------------------------------------------------
describe("extractToolPath", () => {
  test("extracts file_path parameter (Read, Write, Edit, NotebookRead)", () => {
    expect(extractToolPath({ file_path: "/etc/passwd" })).toBe("/etc/passwd");
  });

  test("extracts path parameter (Glob, Grep, LS)", () => {
    expect(extractToolPath({ path: "/etc" })).toBe("/etc");
  });

  test("extracts notebook_path parameter (NotebookEdit)", () => {
    expect(extractToolPath({ notebook_path: "/tmp/evil.ipynb" })).toBe(
      "/tmp/evil.ipynb",
    );
  });

  test("returns empty string when no recognized path parameter exists", () => {
    expect(extractToolPath({ command: "ls -la" })).toBe("");
  });

  test("returns empty string for empty input", () => {
    expect(extractToolPath({})).toBe("");
  });

  test("prefers file_path over path and notebook_path", () => {
    expect(
      extractToolPath({
        file_path: "/a",
        path: "/b",
        notebook_path: "/c",
      }),
    ).toBe("/a");
  });

  test("falls back to path when file_path is absent", () => {
    expect(extractToolPath({ path: "/b", notebook_path: "/c" })).toBe("/b");
  });

  test("handles null/undefined values by falling through", () => {
    expect(extractToolPath({ file_path: null, path: "/fallback" })).toBe("/fallback");
    expect(extractToolPath({ file_path: undefined, path: "/fallback" })).toBe("/fallback");
  });

  test("handles non-string truthy values via || coercion", () => {
    // SDK sends strings, but defense-in-depth: verify non-string values
    // don't produce unexpected results when cast via `as string`
    expect(extractToolPath({ file_path: 0, path: "/fallback" })).toBe("/fallback");
    expect(extractToolPath({ file_path: false, path: "/fallback" })).toBe("/fallback");
  });
});

// ---------------------------------------------------------------------------
// isFileTool / isSafeTool classification
// ---------------------------------------------------------------------------
describe("tool classification", () => {
  test("LS is a file tool", () => {
    expect(isFileTool("LS")).toBe(true);
  });

  test("NotebookRead is a file tool", () => {
    expect(isFileTool("NotebookRead")).toBe(true);
  });

  test("NotebookEdit is a file tool", () => {
    expect(isFileTool("NotebookEdit")).toBe(true);
  });

  test("Read, Write, Edit, Glob, Grep are file tools", () => {
    for (const tool of ["Read", "Write", "Edit", "Glob", "Grep"]) {
      expect(isFileTool(tool), `${tool} should be a file tool`).toBe(true);
    }
  });

  test("Agent is not a file tool", () => {
    expect(isFileTool("Agent")).toBe(false);
  });

  test("LS is NOT a safe tool", () => {
    expect(isSafeTool("LS")).toBe(false);
  });

  test("NotebookRead is NOT a safe tool", () => {
    expect(isSafeTool("NotebookRead")).toBe(false);
  });

  test("Skill, TodoRead, TodoWrite are safe tools", () => {
    for (const tool of ["Skill", "TodoRead", "TodoWrite"]) {
      expect(isSafeTool(tool), `${tool} should be a safe tool`).toBe(true);
    }
  });

  test("Agent is NOT a safe tool (#910 -- handled explicitly in canUseTool)", () => {
    expect(isSafeTool("Agent")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Negative-space test: no tool is both safe AND a file tool
// ---------------------------------------------------------------------------
describe("negative-space: SAFE_TOOLS and FILE_TOOLS are disjoint", () => {
  test("no tool appears in both SAFE_TOOLS and FILE_TOOLS", () => {
    const safeSet = new Set<string>(SAFE_TOOLS);
    const fileSet = new Set<string>(FILE_TOOLS);
    const overlap = [...safeSet].filter((t) => fileSet.has(t));
    expect(overlap).toEqual([]);
  });

  test("SAFE_TOOLS have no file_path, path, or notebook_path parameters by convention", () => {
    const safeToolNames = new Set<string>(SAFE_TOOLS);
    expect(safeToolNames.has("LS")).toBe(false);
    expect(safeToolNames.has("NotebookRead")).toBe(false);
    expect(safeToolNames.has("NotebookEdit")).toBe(false);
  });

  test("FILE_TOOLS contains exactly the expected tools (completeness guard)", () => {
    // This test fails loudly when a tool is added or removed,
    // preventing silent coverage gaps.
    expect([...FILE_TOOLS]).toEqual([
      "Read", "Write", "Edit", "Glob", "Grep",
      "LS", "NotebookRead", "NotebookEdit",
    ]);
  });

  test("SAFE_TOOLS contains exactly the expected tools (completeness guard)", () => {
    // Agent removed in #910 -- now handled by explicit block in canUseTool
    expect([...SAFE_TOOLS]).toEqual(["Skill", "TodoRead", "TodoWrite"]);
  });

  test("UNVERIFIED_PARAM_TOOLS is a subset of FILE_TOOLS", () => {
    const fileSet = new Set<string>(FILE_TOOLS);
    for (const tool of UNVERIFIED_PARAM_TOOLS) {
      expect(fileSet.has(tool), `${tool} should be in FILE_TOOLS`).toBe(true);
    }
  });
});

// ---------------------------------------------------------------------------
// Integration: LS path validation through isPathInWorkspace
// ---------------------------------------------------------------------------
describe("LS path validation", () => {
  test("denies LS with path outside workspace", () => {
    const toolInput = { path: "/etc" };
    const filePath = extractToolPath(toolInput);
    expect(isFileTool("LS")).toBe(true);
    expect(filePath).toBe("/etc");
    expect(isPathInWorkspace(filePath, WORKSPACE)).toBe(false);
  });

  test("allows LS with path inside workspace", () => {
    const toolInput = { path: `${WORKSPACE}/subdir` };
    const filePath = extractToolPath(toolInput);
    expect(isFileTool("LS")).toBe(true);
    expect(isPathInWorkspace(filePath, WORKSPACE)).toBe(true);
  });

  test("denies LS with path traversal", () => {
    const toolInput = { path: `${WORKSPACE}/../other-user/dir` };
    const filePath = extractToolPath(toolInput);
    expect(isFileTool("LS")).toBe(true);
    expect(isPathInWorkspace(filePath, WORKSPACE)).toBe(false);
  });

  test("allows LS with no path parameter (defaults to empty = cwd)", () => {
    const toolInput = {};
    const filePath = extractToolPath(toolInput);
    expect(filePath).toBe("");
    // Empty path should not trigger denial -- tool defaults to cwd
  });
});

// ---------------------------------------------------------------------------
// Integration: NotebookRead path validation through isPathInWorkspace
// ---------------------------------------------------------------------------
describe("NotebookRead path validation", () => {
  test("denies NotebookRead with file_path outside workspace", () => {
    const toolInput = { file_path: "/etc/shadow" };
    const filePath = extractToolPath(toolInput);
    expect(isFileTool("NotebookRead")).toBe(true);
    expect(filePath).toBe("/etc/shadow");
    expect(isPathInWorkspace(filePath, WORKSPACE)).toBe(false);
  });

  test("allows NotebookRead with file_path inside workspace", () => {
    const toolInput = { file_path: `${WORKSPACE}/notebook.ipynb` };
    const filePath = extractToolPath(toolInput);
    expect(isFileTool("NotebookRead")).toBe(true);
    expect(isPathInWorkspace(filePath, WORKSPACE)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Integration: NotebookEdit path validation through isPathInWorkspace
// ---------------------------------------------------------------------------
describe("NotebookEdit path validation", () => {
  test("denies NotebookEdit with notebook_path outside workspace", () => {
    const toolInput = { notebook_path: "/tmp/evil.ipynb" };
    const filePath = extractToolPath(toolInput);
    expect(isFileTool("NotebookEdit")).toBe(true);
    expect(filePath).toBe("/tmp/evil.ipynb");
    expect(isPathInWorkspace(filePath, WORKSPACE)).toBe(false);
  });

  test("allows NotebookEdit with notebook_path inside workspace", () => {
    const toolInput = { notebook_path: `${WORKSPACE}/notebook.ipynb` };
    const filePath = extractToolPath(toolInput);
    expect(isFileTool("NotebookEdit")).toBe(true);
    expect(isPathInWorkspace(filePath, WORKSPACE)).toBe(true);
  });
});
