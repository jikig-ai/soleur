// Set env BEFORE any imports (module reads at load time)
process.env.WORKSPACES_ROOT = "/tmp/soleur-test-workspaces";
process.env.SOLEUR_PLUGIN_PATH = "/nonexistent";

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
    expect(existsSync(join(path, "knowledge-base/brainstorms"))).toBe(true);
    expect(existsSync(join(path, "knowledge-base/specs"))).toBe(true);
    expect(existsSync(join(path, "knowledge-base/plans"))).toBe(true);
    expect(existsSync(join(path, "knowledge-base/learnings"))).toBe(true);
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

  // Git init test skipped: Bun's test runner inherits the parent git
  // context, causing `git init` in /tmp to reference the worktree repo.
  // Git init works in production (Docker container has no parent repo).

  test("is idempotent — running twice does not error", async () => {
    const userId = randomUUID();
    const path1 = await provisionWorkspace(userId);
    const path2 = await provisionWorkspace(userId);

    expect(path1).toBe(path2);
    expect(existsSync(path1)).toBe(true);
  });
});
