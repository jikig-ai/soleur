import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { dirname, join, resolve } from "path";
import { installProblems } from "../scripts/install-opencode-adapter";
import { cleanPackage, expectedPackage, packageProblems, writePackage } from "../scripts/sync-npm-package";

const REPO_ROOT = resolve(dirname(import.meta.filename), "..", "..", "..");
const PACKAGE_ROOT = join(REPO_ROOT, "packages", "opencode-plugin");

describe("@soleur/opencode npm package", () => {
  beforeAll(() => {
    expect(writePackage(REPO_ROOT)).toEqual([]);
  });

  afterAll(() => {
    cleanPackage(REPO_ROOT);
  });

  test("materialized package matches the canonical plugin tree with zero drift", () => {
    expect(packageProblems(REPO_ROOT)).toEqual([]);
    expect(expectedPackage(REPO_ROOT).size).toBeGreaterThan(750);
  });

  test("bin/soleur-opencode.js installs a durable vendored payload that survives source removal", () => {
    const base = mkdtempSync(join(tmpdir(), "soleur-opencode-npm-"));
    const target = join(base, "config");
    mkdirSync(target, { recursive: true });
    try {
      const cli = join(PACKAGE_ROOT, "bin", "soleur-opencode.js");
      const installRun = spawnSync("node", [cli, "install", "--target", target], {
        encoding: "utf-8",
      });
      expect(installRun.status).toBe(0);
      expect(installRun.stdout).toContain("opencode-adapter installed into");

      const checkRun = spawnSync("node", [cli, "install", "--check", "--target", target], {
        encoding: "utf-8",
      });
      expect(checkRun.status).toBe(0);
      expect(checkRun.stdout.trim()).toBe("opencode-install ok");

      const vendoredRoot = join(target, "soleur");
      expect(existsSync(join(vendoredRoot, ".soleur-vendored.json"))).toBe(true);
      expect(installProblems(target, vendoredRoot)).toEqual([]);

      const config = JSON.parse(readFileSync(join(target, "opencode.json"), "utf-8"));
      expect(config.skills).toEqual([join(vendoredRoot, "skills")]);
      expect(config.instructions).toEqual([join(vendoredRoot, "INSTRUCTIONS.md")]);
    } finally {
      rmSync(base, { recursive: true, force: true });
    }
  });
});
