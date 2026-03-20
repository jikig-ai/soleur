import fs from "fs";
import os from "os";
import path from "path";
import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { isPathInWorkspace } from "../server/sandbox";

const WORKSPACE = "/workspaces/user1";

describe("isPathInWorkspace", () => {
  test("allows path inside workspace", () => {
    expect(isPathInWorkspace("/workspaces/user1/file.md", WORKSPACE)).toBe(
      true,
    );
  });

  test("allows workspace root itself", () => {
    expect(isPathInWorkspace("/workspaces/user1", WORKSPACE)).toBe(true);
  });

  test("allows nested subdirectory", () => {
    expect(
      isPathInWorkspace(
        "/workspaces/user1/knowledge-base/plans/plan.md",
        WORKSPACE,
      ),
    ).toBe(true);
  });

  test("denies path traversal via ../", () => {
    expect(
      isPathInWorkspace("/workspaces/user1/../user2/secret.md", WORKSPACE),
    ).toBe(false);
  });

  test("denies deeply nested traversal", () => {
    expect(
      isPathInWorkspace(
        "/workspaces/user1/a/b/../../../../etc/passwd",
        WORKSPACE,
      ),
    ).toBe(false);
  });

  test("denies prefix collision (user1 vs user10)", () => {
    expect(isPathInWorkspace("/workspaces/user10/file.txt", WORKSPACE)).toBe(
      false,
    );
  });

  test("denies path outside workspace", () => {
    expect(isPathInWorkspace("/etc/passwd", WORKSPACE)).toBe(false);
  });

  test("denies root path", () => {
    expect(isPathInWorkspace("/", WORKSPACE)).toBe(false);
  });

  test("denies empty string input", () => {
    expect(isPathInWorkspace("", WORKSPACE)).toBe(false);
  });

  test("handles trailing slash on workspace path", () => {
    expect(isPathInWorkspace("/workspaces/user1/file.md", "/workspaces/user1/")).toBe(true);
  });

  test("normalizes dot segments", () => {
    expect(isPathInWorkspace("/workspaces/user1/./file.md", WORKSPACE)).toBe(true);
  });
});

describe("isPathInWorkspace symlink defense", () => {
  let tmpWorkspace: string;

  beforeEach(() => {
    tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "sandbox-test-"));
    fs.mkdirSync(path.join(tmpWorkspace, "subdir"), { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(tmpWorkspace, { recursive: true, force: true });
  });

  test("denies symlink pointing outside workspace", () => {
    const linkPath = path.join(tmpWorkspace, "escape-link");
    fs.symlinkSync("/etc", linkPath);
    expect(
      isPathInWorkspace(path.join(linkPath, "passwd"), tmpWorkspace),
    ).toBe(false);
  });

  test("denies relative symlink pointing outside workspace", () => {
    const linkPath = path.join(tmpWorkspace, "rel-escape");
    fs.symlinkSync("../../../etc", linkPath);
    expect(
      isPathInWorkspace(path.join(linkPath, "passwd"), tmpWorkspace),
    ).toBe(false);
  });

  test("allows symlink pointing inside workspace", () => {
    const target = path.join(tmpWorkspace, "subdir");
    const linkPath = path.join(tmpWorkspace, "internal-link");
    fs.symlinkSync(target, linkPath);
    expect(
      isPathInWorkspace(path.join(linkPath, "file.md"), tmpWorkspace),
    ).toBe(true);
  });

  test("denies write through symlinked parent directory", () => {
    const linkPath = path.join(tmpWorkspace, "outside");
    fs.symlinkSync("/tmp", linkPath);
    expect(
      isPathInWorkspace(path.join(linkPath, "evil.sh"), tmpWorkspace),
    ).toBe(false);
  });

  test("denies circular symlinks (ELOOP)", () => {
    const link1 = path.join(tmpWorkspace, "loop1");
    const link2 = path.join(tmpWorkspace, "loop2");
    fs.symlinkSync(link2, link1);
    fs.symlinkSync(link1, link2);
    expect(
      isPathInWorkspace(path.join(link1, "file"), tmpWorkspace),
    ).toBe(false);
  });

  test("denies chained symlinks escaping workspace", () => {
    const link1 = path.join(tmpWorkspace, "chain-a");
    const link2 = path.join(tmpWorkspace, "chain-b");
    fs.symlinkSync(link2, link1);
    fs.symlinkSync("/tmp", link2);
    expect(
      isPathInWorkspace(path.join(link1, "file"), tmpWorkspace),
    ).toBe(false);
  });

  test("handles non-existent file in real directory", () => {
    expect(
      isPathInWorkspace(
        path.join(tmpWorkspace, "subdir", "nonexistent.md"),
        tmpWorkspace,
      ),
    ).toBe(true);
  });

  test("handles deeply nested non-existent path", () => {
    expect(
      isPathInWorkspace(
        path.join(tmpWorkspace, "subdir", "a", "b", "c", "file.md"),
        tmpWorkspace,
      ),
    ).toBe(true);
  });

  test("denies dangling symlink pointing outside workspace", () => {
    const linkPath = path.join(tmpWorkspace, "dangling");
    fs.symlinkSync("/nonexistent/outside/target", linkPath);
    expect(
      isPathInWorkspace(path.join(linkPath, "file.txt"), tmpWorkspace),
    ).toBe(false);
  });

  test("resolves workspace path accessed through a symlink", () => {
    const workspaceAlias = fs.mkdtempSync(path.join(os.tmpdir(), "ws-alias-"));
    const aliasLink = path.join(workspaceAlias, "link");
    fs.symlinkSync(tmpWorkspace, aliasLink);
    try {
      expect(
        isPathInWorkspace(
          path.join(tmpWorkspace, "subdir", "file.md"),
          aliasLink,
        ),
      ).toBe(true);
    } finally {
      fs.rmSync(workspaceAlias, { recursive: true, force: true });
    }
  });
});
