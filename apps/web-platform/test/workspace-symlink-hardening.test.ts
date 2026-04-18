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
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "fs";
import { join } from "path";
import { randomUUID } from "crypto";
import { scaffoldWorkspaceDefaults } from "../server/workspace";

const TEST_WORKSPACES = "/tmp/soleur-test-workspaces-symlink";
// All external symlink targets are written under TEST_WORKSPACES/external/ so
// a single afterEach rm recovers state even when a test throws between
// `writeFileSync` and the per-test `finally` cleanup.
const EXTERNAL_ROOT = join(TEST_WORKSPACES, "external");

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
    mkdirSync(EXTERNAL_ROOT, { recursive: true });
    const externalTarget = join(EXTERNAL_ROOT, `outside-${randomUUID()}`);
    writeFileSync(externalTarget, "external-sensitive-data");

    mkdirSync(join(workspacePath, "knowledge-base"), { recursive: true });
    symlinkSync(externalTarget, join(workspacePath, "knowledge-base", "overview"));

    expect(() => scaffoldWorkspaceDefaults(workspacePath)).toThrow(
      /Refusing to scaffold over non-directory/,
    );

    // The external file must not have been modified by scaffolding.
    expect(readFileSync(externalTarget, "utf8")).toBe("external-sensitive-data");
  });

  test("rejects a symlink at knowledge-base/project/specs pointing to a regular file", () => {
    // Second variant: deeper path. Whichever scaffolder layer hits the
    // bogus symlink must throw before mkdirSync follows it.
    const userId = randomUUID();
    const workspacePath = join(TEST_WORKSPACES, userId);
    mkdirSync(EXTERNAL_ROOT, { recursive: true });
    const externalTarget = join(EXTERNAL_ROOT, `file-target-${randomUUID()}`);
    writeFileSync(externalTarget, "victim");

    mkdirSync(join(workspacePath, "knowledge-base", "project"), { recursive: true });
    symlinkSync(
      externalTarget,
      join(workspacePath, "knowledge-base", "project", "specs"),
    );

    expect(() => scaffoldWorkspaceDefaults(workspacePath)).toThrow(
      /Refusing to scaffold over non-directory/,
    );
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
