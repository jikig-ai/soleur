import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

vi.mock("../server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

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

function writeSentinel(dir: string): void {
  writeFileSync(join(dir, ".seed-complete"), "seeded test\n", "utf8");
}

// Re-imports the module after vi.resetModules() so the latched _checked flag
// starts false for each test. This replaces a `_resetForTesting()` export from
// the production module — keeping the prod surface free of test-only hooks.
async function loadModule() {
  vi.resetModules();
  return await import("../server/plugin-mount-check");
}

async function loadObservability() {
  return await import("../server/observability");
}

describe("verifyPluginMountOnce", () => {
  const originalEnv = process.env.SOLEUR_PLUGIN_PATH;
  let tmpDirs: string[] = [];

  beforeEach(() => {
    vi.clearAllMocks();
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

  test("Scenario A: path missing fires reportSilentFallback with 'plugin-mount path missing'", async () => {
    process.env.SOLEUR_PLUGIN_PATH = "/nonexistent-plugin-mount-test-path-3045";
    const { verifyPluginMountOnce } = await loadModule();
    const { reportSilentFallback } = await loadObservability();

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

  test("Scenario B: empty mount fires 'plugin-mount empty'", async () => {
    const dir = makeTempDir();
    tmpDirs.push(dir);
    process.env.SOLEUR_PLUGIN_PATH = dir;
    const { verifyPluginMountOnce } = await loadModule();
    const { reportSilentFallback } = await loadObservability();

    verifyPluginMountOnce();

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = vi.mocked(reportSilentFallback).mock.calls[0];
    expect(opts.message).toBe("plugin-mount empty");
    expect(opts.extra).toMatchObject({ path: dir });
  });

  test("Scenario C: manifest missing fires 'plugin-mount manifest missing'", async () => {
    const dir = makeTempDir();
    tmpDirs.push(dir);
    writeFileSync(join(dir, "stray.txt"), "stub", "utf8");
    process.env.SOLEUR_PLUGIN_PATH = dir;
    const { verifyPluginMountOnce } = await loadModule();
    const { reportSilentFallback } = await loadObservability();

    verifyPluginMountOnce();

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = vi.mocked(reportSilentFallback).mock.calls[0];
    expect(opts.message).toBe("plugin-mount manifest missing");
    expect(opts.extra).toMatchObject({
      path: dir,
      manifest: join(dir, ".claude-plugin", "plugin.json"),
    });
  });

  test("Scenario D: manifest present but sentinel missing fires 'plugin-mount partial seed'", async () => {
    const dir = makeTempDir();
    tmpDirs.push(dir);
    seedManifest(dir);
    // Intentionally NOT writing .seed-complete — simulates a docker cp that
    // extracted .claude-plugin/ early in the tar but was SIGKILLed before
    // the sentinel was written.
    process.env.SOLEUR_PLUGIN_PATH = dir;
    const { verifyPluginMountOnce } = await loadModule();
    const { reportSilentFallback } = await loadObservability();

    verifyPluginMountOnce();

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = vi.mocked(reportSilentFallback).mock.calls[0];
    expect(opts.message).toBe("plugin-mount partial seed");
    expect(opts.extra).toMatchObject({
      path: dir,
      sentinel: join(dir, ".seed-complete"),
    });
  });

  test("Scenario E: fully-seeded mount is silent", async () => {
    const dir = makeTempDir();
    tmpDirs.push(dir);
    seedManifest(dir);
    writeSentinel(dir);
    process.env.SOLEUR_PLUGIN_PATH = dir;
    const { verifyPluginMountOnce } = await loadModule();
    const { reportSilentFallback } = await loadObservability();

    verifyPluginMountOnce();

    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  test("Scenario F: memoization survives env-var change between calls", async () => {
    const dir = makeTempDir();
    tmpDirs.push(dir);
    process.env.SOLEUR_PLUGIN_PATH = dir;
    const { verifyPluginMountOnce } = await loadModule();
    const { reportSilentFallback } = await loadObservability();

    // First call against an empty mount fires once.
    verifyPluginMountOnce();
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);

    // Now seed the dir AND change env to a fully-populated path. A regression
    // that re-evaluated state per call (instead of memoizing) would either
    // re-fire (against the still-empty original path) or stay silent (against
    // the new populated path) — both would diverge from "called exactly once".
    seedManifest(dir);
    writeSentinel(dir);
    const populated = makeTempDir();
    tmpDirs.push(populated);
    seedManifest(populated);
    writeSentinel(populated);
    process.env.SOLEUR_PLUGIN_PATH = populated;

    verifyPluginMountOnce();
    verifyPluginMountOnce();

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
  });
});
