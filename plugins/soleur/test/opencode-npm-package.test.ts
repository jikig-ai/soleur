import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { spawnSync } from "child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync } from "fs";
import { tmpdir } from "os";
import { dirname, join, resolve } from "path";
import { installProblems } from "../scripts/install-opencode-adapter";
import { PACKAGE_SOURCE_FILES, expectedPackage, packageProblems, writePackage } from "../scripts/sync-npm-package";

const REPO_ROOT = resolve(dirname(import.meta.filename), "..", "..", "..");
const COMMITTED_PACKAGE_ROOT = join(REPO_ROOT, "packages", "opencode-plugin");

describe("@soleur/opencode npm package", () => {
  let tempRoot = "";
  let tempPkg = "";

  beforeAll(() => {
    tempRoot = mkdtempSync(join(tmpdir(), "soleur-opencode-pkg-"));
    tempPkg = join(tempRoot, "opencode-plugin");
    mkdirSync(tempPkg, { recursive: true });
    for (const source of PACKAGE_SOURCE_FILES) {
      cpSync(join(COMMITTED_PACKAGE_ROOT, source), join(tempPkg, source), { recursive: true });
    }
    expect(writePackage(REPO_ROOT, tempPkg)).toEqual([]);
  });

  afterAll(() => {
    if (tempRoot !== "") rmSync(tempRoot, { recursive: true, force: true });
  });

  test("materialized package matches the canonical plugin tree with zero drift", () => {
    expect(packageProblems(REPO_ROOT, tempPkg)).toEqual([]);
    expect(expectedPackage(REPO_ROOT).size).toBeGreaterThan(750);
    // Executable scripts must retain their +x bit in the materialized package.
    const mode = statSync(join(tempPkg, "scripts", "admin-merge-ready.sh")).mode;
    expect(mode & 0o111).toBeGreaterThan(0);
  });

  test("bin/soleur-opencode.js installs a durable vendored payload that preserves +x and survives source removal", () => {
    const target = join(tempRoot, "config");
    mkdirSync(target, { recursive: true });
    const cli = join(tempPkg, "bin", "soleur-opencode.js");
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
    expect(statSync(join(vendoredRoot, "scripts", "admin-merge-ready.sh")).mode & 0o111).toBeGreaterThan(0);

    const config = JSON.parse(readFileSync(join(target, "opencode.json"), "utf-8"));
    expect(config.skills).toEqual([join(vendoredRoot, "skills")]);
    expect(config.instructions).toEqual([join(vendoredRoot, "INSTRUCTIONS.md")]);
  });
});
