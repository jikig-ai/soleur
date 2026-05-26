/**
 * sandbox.isPathInWorkspace — symlink-chain containment.
 *
 * feat-team-workspace-multi-user Phase 2.3.2: after the filesystem migration,
 * `/workspaces/<userId>` is a symlink that resolves to `/workspaces/<workspaceId>`.
 * The sandbox containment check must accept BOTH forms for the same workspace
 * (i.e., realpath both sides). This is already the design of the existing
 * `resolveRealPath` + `startsWith` pair (sandbox.ts:90-148) — the test below
 * pins that behavior so a future refactor cannot regress it.
 */

import { describe, expect, it, beforeEach, afterEach } from "vitest";
import {
  mkdtempSync,
  mkdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { randomUUID } from "crypto";
import { isPathInWorkspace } from "@/server/sandbox";

let root = "";

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "soleur-sandbox-symlink-"));
});

afterEach(() => {
  rmSync(root, { recursive: true, force: true });
});

describe("isPathInWorkspace with userId→workspaceId symlink chain", () => {
  it("accepts /workspaces/<userId>/file when workspacePath is the symlinked legacy path", () => {
    const userId = randomUUID();
    const workspaceId = randomUUID();
    const canonical = join(root, workspaceId);
    const legacy = join(root, userId);
    mkdirSync(canonical, { recursive: true });
    writeFileSync(join(canonical, "marker.txt"), "hi");
    symlinkSync(canonical, legacy);

    // File path expressed under legacy, workspace expressed as canonical.
    expect(isPathInWorkspace(join(legacy, "marker.txt"), canonical)).toBe(
      true,
    );
    // Symmetric: file under canonical, workspace expressed as legacy.
    expect(isPathInWorkspace(join(canonical, "marker.txt"), legacy)).toBe(
      true,
    );
    // Both under legacy.
    expect(isPathInWorkspace(join(legacy, "marker.txt"), legacy)).toBe(true);
    // Both under canonical.
    expect(isPathInWorkspace(join(canonical, "marker.txt"), canonical)).toBe(
      true,
    );
  });

  it("rejects a sibling workspace accessed through its own symlink", () => {
    const userIdA = randomUUID();
    const workspaceIdA = randomUUID();
    const userIdB = randomUUID();
    const workspaceIdB = randomUUID();
    const canonicalA = join(root, workspaceIdA);
    const canonicalB = join(root, workspaceIdB);
    mkdirSync(canonicalA, { recursive: true });
    mkdirSync(canonicalB, { recursive: true });
    writeFileSync(join(canonicalB, "secret.txt"), "hi");
    symlinkSync(canonicalA, join(root, userIdA));
    symlinkSync(canonicalB, join(root, userIdB));

    // User A's sandbox should reject access to user B's file via either form.
    expect(
      isPathInWorkspace(join(canonicalB, "secret.txt"), canonicalA),
    ).toBe(false);
    expect(
      isPathInWorkspace(join(canonicalB, "secret.txt"), join(root, userIdA)),
    ).toBe(false);
    expect(
      isPathInWorkspace(join(root, userIdB, "secret.txt"), canonicalA),
    ).toBe(false);
  });

  it("rejects a relative `..`-traversal that escapes the workspace", () => {
    const userId = randomUUID();
    const workspaceId = randomUUID();
    const canonical = join(root, workspaceId);
    const legacy = join(root, userId);
    mkdirSync(canonical, { recursive: true });
    mkdirSync(join(root, "siblings"), { recursive: true });
    writeFileSync(join(root, "siblings", "outside.txt"), "x");
    symlinkSync(canonical, legacy);

    expect(
      isPathInWorkspace("../siblings/outside.txt", canonical),
    ).toBe(false);
    expect(
      isPathInWorkspace("../siblings/outside.txt", legacy),
    ).toBe(false);
  });
});
