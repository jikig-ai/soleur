// Set env BEFORE any imports (module reads at load time)
import { tmpdir } from "os";
process.env.WORKSPACES_ROOT = "/tmp/soleur-test-workspaces-symlink";
process.env.SOLEUR_PLUGIN_PATH = "/nonexistent";
process.env.GIT_CEILING_DIRECTORIES = tmpdir();
delete process.env.GIT_DIR;
delete process.env.GIT_INDEX_FILE;
delete process.env.GIT_WORK_TREE;

import { describe, test, expect, afterEach } from "vitest";
import {
  existsSync,
  mkdirSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import { join } from "path";
import { randomUUID } from "crypto";
import { scaffoldWorkspaceDefaults } from "../server/workspace";

const TEST_WORKSPACES = "/tmp/soleur-test-workspaces-symlink";

afterEach(() => {
  try {
    rmSync(TEST_WORKSPACES, { recursive: true, force: true });
  } catch {}
});

describe("workspace scaffolding — symlink hardening (#2333)", () => {
  test("rejects a symlink at knowledge-base/overview pointing outside the workspace", () => {
    // Seed a workspace that *looks* like a freshly-cloned repo whose checkout
    // committed a symlink at knowledge-base/overview pointing to an external
    // location. This is the #2333 threat: a user clones their repo, a symlink
    // at an expected-to-be-a-directory path leaks write access outside the
    // workspace during scaffolding.
    const userId = randomUUID();
    const workspacePath = join(TEST_WORKSPACES, userId);
    const externalTarget = join(tmpdir(), `outside-${randomUUID()}`);
    writeFileSync(externalTarget, "external-sensitive-data");

    try {
      mkdirSync(join(workspacePath, "knowledge-base"), { recursive: true });
      symlinkSync(externalTarget, join(workspacePath, "knowledge-base", "overview"));

      expect(() => scaffoldWorkspaceDefaults(workspacePath)).toThrow(
        /Refusing to scaffold over non-directory/,
      );

      // The external file must not have been modified by scaffolding.
      const { readFileSync } = require("fs") as typeof import("fs");
      expect(readFileSync(externalTarget, "utf8")).toBe("external-sensitive-data");
    } finally {
      try {
        rmSync(externalTarget, { force: true });
      } catch {}
    }
  });

  test("rejects a symlink at knowledge-base/project/specs pointing to a regular file", () => {
    // Second variant: deeper path. Whichever scaffolder layer hits the
    // bogus symlink must throw before mkdirSync follows it.
    const userId = randomUUID();
    const workspacePath = join(TEST_WORKSPACES, userId);
    const externalTarget = join(tmpdir(), `file-target-${randomUUID()}`);
    writeFileSync(externalTarget, "victim");

    try {
      mkdirSync(join(workspacePath, "knowledge-base", "project"), { recursive: true });
      symlinkSync(
        externalTarget,
        join(workspacePath, "knowledge-base", "project", "specs"),
      );

      expect(() => scaffoldWorkspaceDefaults(workspacePath)).toThrow(
        /Refusing to scaffold over non-directory/,
      );
    } finally {
      try {
        rmSync(externalTarget, { force: true });
      } catch {}
    }
  });

  test("scaffolds cleanly on a fresh workspace (no symlinks, no existing dirs)", () => {
    const userId = randomUUID();
    const workspacePath = join(TEST_WORKSPACES, userId);
    mkdirSync(workspacePath, { recursive: true });

    scaffoldWorkspaceDefaults(workspacePath);

    expect(existsSync(join(workspacePath, "knowledge-base"))).toBe(true);
    expect(existsSync(join(workspacePath, "knowledge-base", "overview"))).toBe(true);
    expect(existsSync(join(workspacePath, "knowledge-base", "project"))).toBe(true);
    expect(existsSync(join(workspacePath, "knowledge-base", "project", "specs"))).toBe(true);
    expect(existsSync(join(workspacePath, ".claude", "settings.json"))).toBe(true);
  });

  test("suppressWelcomeHook option writes the welcome sentinel", () => {
    const userId = randomUUID();
    const workspacePath = join(TEST_WORKSPACES, userId);
    mkdirSync(workspacePath, { recursive: true });

    scaffoldWorkspaceDefaults(workspacePath, { suppressWelcomeHook: true });

    expect(existsSync(join(workspacePath, ".claude", "soleur-welcomed.local"))).toBe(true);
  });

  test("suppressWelcomeHook=false does not write the welcome sentinel", () => {
    const userId = randomUUID();
    const workspacePath = join(TEST_WORKSPACES, userId);
    mkdirSync(workspacePath, { recursive: true });

    scaffoldWorkspaceDefaults(workspacePath, { suppressWelcomeHook: false });

    expect(existsSync(join(workspacePath, ".claude", "soleur-welcomed.local"))).toBe(false);
  });
});
