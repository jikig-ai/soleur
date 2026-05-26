import { describe, expect, it, beforeEach, afterEach } from "vitest";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import { join } from "path";
import { tmpdir } from "os";
import { randomUUID } from "crypto";
import {
  migrateAllUserWorkspaces,
  migrateUserWorkspace,
} from "@/server/workspace-fs-migrate";

// Per-test tmp root. Each test gets a fresh /tmp/soleur-fs-migrate-<rand>/
// so concurrent vitest workers do not collide.
let root = "";

beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), "soleur-fs-migrate-"));
});

afterEach(() => {
  rmSync(root, { recursive: true, force: true });
});

function makeDir(path: string, file = "marker.txt", contents = "hello") {
  mkdirSync(path, { recursive: true });
  writeFileSync(join(path, file), contents);
}

describe("migrateUserWorkspace", () => {
  it("is a no-op when userId === workspaceId (solo N2 case)", () => {
    const userId = randomUUID();
    const legacy = join(root, userId);
    makeDir(legacy);

    // workspaceId === userId; nothing should move and no symlink should be
    // created (the dir is already at its canonical path).
    migrateUserWorkspace({ userId, workspaceId: userId, root });

    expect(existsSync(legacy)).toBe(true);
    expect(lstatSync(legacy).isDirectory()).toBe(true);
    // No nested symlink-of-self.
    expect(lstatSync(legacy).isSymbolicLink()).toBe(false);
  });

  it("renames legacy /workspaces/<userId> to /workspaces/<workspaceId> and creates a symlink", () => {
    const userId = randomUUID();
    const workspaceId = randomUUID();
    const legacy = join(root, userId);
    const canonical = join(root, workspaceId);
    makeDir(legacy);

    migrateUserWorkspace({ userId, workspaceId, root });

    // Canonical directory exists and holds the original contents.
    expect(lstatSync(canonical).isDirectory()).toBe(true);
    expect(readFileSync(join(canonical, "marker.txt"), "utf8")).toBe("hello");

    // Legacy path is now a symlink → canonical.
    expect(lstatSync(legacy).isSymbolicLink()).toBe(true);
    expect(realpathSync(legacy)).toBe(realpathSync(canonical));
  });

  it("is idempotent: re-running after migration is a no-op", () => {
    const userId = randomUUID();
    const workspaceId = randomUUID();
    const legacy = join(root, userId);
    const canonical = join(root, workspaceId);
    makeDir(legacy);

    migrateUserWorkspace({ userId, workspaceId, root });
    // Second invocation must not throw and must preserve the post-state.
    migrateUserWorkspace({ userId, workspaceId, root });

    expect(lstatSync(canonical).isDirectory()).toBe(true);
    expect(lstatSync(legacy).isSymbolicLink()).toBe(true);
    expect(realpathSync(legacy)).toBe(realpathSync(canonical));
    expect(readFileSync(join(canonical, "marker.txt"), "utf8")).toBe("hello");
  });

  it("throws when the legacy symlink resolves to an unexpected target (CWE-59)", () => {
    const userId = randomUUID();
    const workspaceId = randomUUID();
    const otherWorkspaceId = randomUUID();
    const legacy = join(root, userId);
    const other = join(root, otherWorkspaceId);
    makeDir(other);
    // The legacy path is a symlink to a DIFFERENT workspace — possible
    // attacker-controlled or operator-mistake state. Migration must refuse.
    symlinkSync(other, legacy);

    expect(() =>
      migrateUserWorkspace({ userId, workspaceId, root }),
    ).toThrow(/symlink|realpath|target/i);
  });

  it("throws when the legacy path is a dangling symlink", () => {
    const userId = randomUUID();
    const workspaceId = randomUUID();
    const legacy = join(root, userId);
    // Symlink to a path that does not exist.
    symlinkSync(join(root, "nonexistent-target"), legacy);

    expect(() =>
      migrateUserWorkspace({ userId, workspaceId, root }),
    ).toThrow(/dangling|nonexistent|symlink|realpath|target/i);
  });

  it("is a no-op when the legacy path does not exist (user never logged in)", () => {
    const userId = randomUUID();
    const workspaceId = randomUUID();
    // Neither legacy nor canonical exists.

    // Should not throw; user has no on-disk workspace yet.
    expect(() =>
      migrateUserWorkspace({ userId, workspaceId, root }),
    ).not.toThrow();

    expect(existsSync(join(root, userId))).toBe(false);
    expect(existsSync(join(root, workspaceId))).toBe(false);
  });
});

describe("migrateAllUserWorkspaces (batch)", () => {
  it("counts solo rows as 'skipped' and team rows as 'migrated'", () => {
    const soloId = randomUUID();
    const teamUserId = randomUUID();
    const teamWorkspaceId = randomUUID();
    makeDir(join(root, soloId));
    makeDir(join(root, teamUserId));

    const result = migrateAllUserWorkspaces(
      [
        { userId: soloId, workspaceId: soloId },
        { userId: teamUserId, workspaceId: teamWorkspaceId },
      ],
      root,
    );

    expect(result).toEqual({ migrated: 1, skipped: 1, failed: 0 });
    expect(lstatSync(join(root, teamWorkspaceId)).isDirectory()).toBe(true);
    expect(lstatSync(join(root, teamUserId)).isSymbolicLink()).toBe(true);
  });

  it("continues the batch when one row fails (does not abort on partial failure)", () => {
    const badUserId = randomUUID();
    const badWorkspaceId = randomUUID();
    const otherWorkspaceId = randomUUID();
    // Bad row: legacy symlink points to an unrelated target (will throw).
    makeDir(join(root, otherWorkspaceId));
    symlinkSync(join(root, otherWorkspaceId), join(root, badUserId));

    const goodUserId = randomUUID();
    const goodWorkspaceId = randomUUID();
    makeDir(join(root, goodUserId));

    const result = migrateAllUserWorkspaces(
      [
        { userId: badUserId, workspaceId: badWorkspaceId },
        { userId: goodUserId, workspaceId: goodWorkspaceId },
      ],
      root,
    );

    expect(result).toEqual({ migrated: 1, skipped: 0, failed: 1 });
    // The good row landed despite the bad one failing.
    expect(lstatSync(join(root, goodWorkspaceId)).isDirectory()).toBe(true);
  });
});
