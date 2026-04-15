// Set env BEFORE any imports (module reads at load time)
import { tmpdir } from "os";
process.env.WORKSPACES_ROOT = "/tmp/soleur-test-workspaces";
process.env.SOLEUR_PLUGIN_PATH = "/nonexistent";
// Isolate git: ceiling prevents upward traversal, and deleting GIT_DIR/
// GIT_INDEX_FILE/GIT_WORK_TREE prevents git hook env from overriding discovery.
process.env.GIT_CEILING_DIRECTORIES = tmpdir();
delete process.env.GIT_DIR;
delete process.env.GIT_INDEX_FILE;
delete process.env.GIT_WORK_TREE;

import { describe, test, expect, afterEach } from "vitest";
import { existsSync, readFileSync, rmSync } from "fs";
import { join } from "path";
import { randomUUID } from "crypto";
import { provisionWorkspace } from "../server/workspace";

const TEST_WORKSPACES = "/tmp/soleur-test-workspaces";

afterEach(() => {
  try {
    rmSync(TEST_WORKSPACES, { recursive: true, force: true });
  } catch {}
});

describe("workspace provisioning", () => {
  test("creates workspace directory structure", async () => {
    const userId = randomUUID();
    const path = await provisionWorkspace(userId);

    expect(path).toBe(join(TEST_WORKSPACES, userId));
    expect(existsSync(path)).toBe(true);
    expect(existsSync(join(path, "knowledge-base"))).toBe(true);
    expect(existsSync(join(path, "knowledge-base/project"))).toBe(true);
    expect(existsSync(join(path, "knowledge-base/project/brainstorms"))).toBe(true);
    expect(existsSync(join(path, "knowledge-base/project/specs"))).toBe(true);
    expect(existsSync(join(path, "knowledge-base/project/plans"))).toBe(true);
    expect(existsSync(join(path, "knowledge-base/project/learnings"))).toBe(true);
    // knowledge-base/overview/ must exist so the first Write targeting
    // vision.md never hits a non-existent ancestor during path validation.
    expect(existsSync(join(path, "knowledge-base/overview"))).toBe(true);
  });

  test("creates .claude/settings.json with empty permissions for canUseTool routing", async () => {
    const userId = randomUUID();
    const path = await provisionWorkspace(userId);

    const settingsPath = join(path, ".claude/settings.json");
    expect(existsSync(settingsPath)).toBe(true);

    const settings = JSON.parse(readFileSync(settingsPath, "utf8"));
    expect(settings.permissions.allow).toEqual([]);
  });

  test("creates .claude/settings.json with sandbox enabled", async () => {
    const userId = randomUUID();
    const path = await provisionWorkspace(userId);

    const settingsPath = join(path, ".claude/settings.json");
    const settings = JSON.parse(readFileSync(settingsPath, "utf8"));
    expect(settings.sandbox.enabled).toBe(true);
  });

  // Git init isolation: GIT_CEILING_DIRECTORIES (set at top of file)
  // prevents git from discovering the parent worktree's .git directory.
  // Git init works in production (Docker container has no parent repo).

  test("is idempotent — running twice does not error", async () => {
    const userId = randomUUID();
    const path1 = await provisionWorkspace(userId);
    const path2 = await provisionWorkspace(userId);

    expect(path1).toBe(path2);
    expect(existsSync(path1)).toBe(true);
  });
});
