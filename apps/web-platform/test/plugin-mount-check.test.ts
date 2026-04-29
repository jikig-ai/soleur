import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import { reportSilentFallback } from "../server/observability";
import {
  verifyPluginMountOnce,
  _resetForTesting,
} from "../server/plugin-mount-check";

const FEATURE = "plugin-mount";
const OP = "discovery";

function makeTempDir(): string {
  return mkdtempSync(join(tmpdir(), "plugin-mount-test-"));
}

function seedManifest(dir: string): void {
  const inner = join(dir, ".claude-plugin");
  mkdirSync(inner, { recursive: true });
  writeFileSync(join(inner, "plugin.json"), '{"name":"soleur"}', "utf8");
}

describe("verifyPluginMountOnce", () => {
  const originalEnv = process.env.SOLEUR_PLUGIN_PATH;
  let tmpDirs: string[] = [];

  beforeEach(() => {
    vi.clearAllMocks();
    _resetForTesting();
    tmpDirs = [];
  });

  afterEach(() => {
    if (originalEnv === undefined) delete process.env.SOLEUR_PLUGIN_PATH;
    else process.env.SOLEUR_PLUGIN_PATH = originalEnv;
    for (const d of tmpDirs) {
      try {
        rmSync(d, { recursive: true, force: true });
      } catch {
        // Best effort cleanup; sweep on fixture-collision.
      }
    }
  });

  test("Scenario A: path missing fires reportSilentFallback with 'plugin-mount path missing'", () => {
    process.env.SOLEUR_PLUGIN_PATH = "/nonexistent-plugin-mount-test-path-3045";

    verifyPluginMountOnce();

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = vi.mocked(reportSilentFallback).mock.calls[0];
    expect(opts.feature).toBe(FEATURE);
    expect(opts.op).toBe(OP);
    expect(opts.message).toBe("plugin-mount path missing");
    expect(opts.extra).toMatchObject({
      path: "/nonexistent-plugin-mount-test-path-3045",
    });
  });

  test("Scenario B: empty mount fires 'plugin-mount empty'", () => {
    const dir = makeTempDir();
    tmpDirs.push(dir);
    process.env.SOLEUR_PLUGIN_PATH = dir;

    verifyPluginMountOnce();

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = vi.mocked(reportSilentFallback).mock.calls[0];
    expect(opts.feature).toBe(FEATURE);
    expect(opts.op).toBe(OP);
    expect(opts.message).toBe("plugin-mount empty");
    expect(opts.extra).toMatchObject({ path: dir });
  });

  test("Scenario C: manifest missing fires 'plugin-mount manifest missing'", () => {
    const dir = makeTempDir();
    tmpDirs.push(dir);
    writeFileSync(join(dir, "stray.txt"), "stub", "utf8");
    process.env.SOLEUR_PLUGIN_PATH = dir;

    verifyPluginMountOnce();

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = vi.mocked(reportSilentFallback).mock.calls[0];
    expect(opts.feature).toBe(FEATURE);
    expect(opts.op).toBe(OP);
    expect(opts.message).toBe("plugin-mount manifest missing");
    expect(opts.extra).toMatchObject({
      path: dir,
      manifest: join(dir, ".claude-plugin", "plugin.json"),
    });
  });

  test("Scenario D: populated mount is silent", () => {
    const dir = makeTempDir();
    tmpDirs.push(dir);
    seedManifest(dir);
    process.env.SOLEUR_PLUGIN_PATH = dir;

    verifyPluginMountOnce();

    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  test("Scenario E: memoization — second call is a no-op", () => {
    const dir = makeTempDir();
    tmpDirs.push(dir);
    process.env.SOLEUR_PLUGIN_PATH = dir;

    verifyPluginMountOnce();
    verifyPluginMountOnce();
    verifyPluginMountOnce();

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
  });
});
