// Bug A2 regression coverage. The agent's SDK Query is configured with
// `cwd = users.workspace_path`, so any `Read({ file_path: "knowledge-base/foo.pdf" })`
// the agent emits is a workspace-relative path that the SDK interprets
// against the agent's cwd. Our security guards (sandbox-hook + canUseTool)
// resolve via Node's `path.resolve()` which anchors on the Next.js process
// cwd — divergent from the agent's cwd. Pre-fix, this returned false for
// any workspace-relative path even when the file genuinely lived inside
// the workspace, producing the user-facing "outside my workspace
// boundary" reply observed in #3376.
//
// Post-fix, `isPathInWorkspace` resolves a relative `filePath` against the
// caller-provided `workspacePath` BEFORE realpath, so workspace-relative
// reads succeed. Path traversal (`..`) and absolute paths outside the
// workspace continue to be denied — the post-realpath containment check
// is the load-bearing guard against escape.

import fs from "fs";
import os from "os";
import path from "path";
import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { isPathInWorkspace } from "../server/sandbox";

describe("isPathInWorkspace relative-path resolution (Bug A2 fix)", () => {
  let tmpWorkspace: string;

  beforeEach(() => {
    tmpWorkspace = fs.realpathSync(
      fs.mkdtempSync(path.join(os.tmpdir(), "sandbox-rel-")),
    );
    fs.mkdirSync(path.join(tmpWorkspace, "knowledge-base"), { recursive: true });
    fs.writeFileSync(path.join(tmpWorkspace, "knowledge-base", "test.pdf"), "");
  });

  afterEach(() => {
    fs.rmSync(tmpWorkspace, { recursive: true, force: true });
  });

  test("allows workspace-relative path inside workspace (Bug A2)", () => {
    // The fix: resolve relative `filePath` against `workspacePath`, NOT
    // `process.cwd()`. Pre-fix this returned false for any relative path,
    // because Node anchored on the Next.js server's cwd.
    expect(
      isPathInWorkspace("knowledge-base/test.pdf", tmpWorkspace),
    ).toBe(true);
  });

  test("allows workspace-relative path with spaces in filename", () => {
    fs.writeFileSync(
      path.join(tmpWorkspace, "knowledge-base", "Au Chat Potan.pdf"),
      "",
    );
    expect(
      isPathInWorkspace("knowledge-base/Au Chat Potan.pdf", tmpWorkspace),
    ).toBe(true);
  });

  test("denies relative path that escapes workspace via ..", () => {
    // Even with relative-path resolution, traversal must still fail. The
    // post-realpath containment check is the load-bearing guard.
    expect(
      isPathInWorkspace("../escapee.txt", tmpWorkspace),
    ).toBe(false);
  });

  test("denies deeply nested .. escape", () => {
    expect(
      isPathInWorkspace(
        "knowledge-base/../../../etc/passwd",
        tmpWorkspace,
      ),
    ).toBe(false);
  });

  test("absolute path inside workspace still allowed (no regression)", () => {
    // Behavior preservation for existing absolute-path callers.
    expect(
      isPathInWorkspace(
        path.join(tmpWorkspace, "knowledge-base", "test.pdf"),
        tmpWorkspace,
      ),
    ).toBe(true);
  });

  test("absolute path outside workspace still denied (no regression)", () => {
    expect(isPathInWorkspace("/etc/passwd", tmpWorkspace)).toBe(false);
  });

  test("relative path resolving to non-existent file inside workspace allowed", () => {
    // Mirrors the existing "handles non-existent file in real directory"
    // semantics: Write/Edit targets that don't exist yet must pass when
    // the directory is in-workspace.
    expect(
      isPathInWorkspace(
        "knowledge-base/will-be-created.md",
        tmpWorkspace,
      ),
    ).toBe(true);
  });
});
