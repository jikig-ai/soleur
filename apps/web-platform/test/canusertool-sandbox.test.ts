import { describe, test, expect } from "vitest";
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
