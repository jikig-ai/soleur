// #8211, ADR-323 Decision 9 (2026-11-10 amendment) — the git env of cron-content-vendor-drift is built when git is
// spawned, never from a snapshot taken when the module loaded. index.ts deletes the relay hello keys from process.env
// at boot, AFTER the hoisted imports have evaluated this module, so a module-load snapshot (a `{ ...process.env }`, an
// Object.assign copy, or a cached `gitIsolatedEnv()` result) would still hand them to every git child.
//
// Behavioural: the module is imported with a sentinel variable already in process.env (standing in for a key present
// at module load); the test then deletes it, adds a second one, and drives the handler to its first git spawn (the
// clone). The env that spawn receives must reflect both changes. Separate file because vi.mock is file-wide (the
// sibling suite imports the real module for its source-shape rows).

import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { EventEmitter } from "node:events";
import { afterAll, describe, expect, it, vi } from "vitest";

const SENTINELS = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  const s = { deleted: "R2_VENDOR_DRIFT_ENV_DELETED_AFTER_LOAD", added: "R2_VENDOR_DRIFT_ENV_ADDED_AFTER_LOAD" };
  process.env[s.deleted] = "present-at-module-load";
  delete process.env[s.added];
  return s;
});

const { spawnSpy, state } = vi.hoisted(() => ({
  spawnSpy: vi.fn(),
  state: { workspaceRoot: "" },
}));

vi.mock("node:child_process", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:child_process")>();
  const spawn = (...args: unknown[]) => {
    spawnSpy(...args);
    // A git that fails at once: the clone step throws and the handler unwinds through its catch.
    const child = Object.assign(new EventEmitter(), { stderr: new EventEmitter(), stdout: new EventEmitter() });
    setImmediate(() => {
      child.emit("exit", 128, null);
      child.emit("close", 128);
    });
    return child;
  };
  return { ...actual, spawn, default: { ...actual, spawn } };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));
vi.mock("@/server/inngest/client", () => ({ inngest: { createFunction: vi.fn(), send: vi.fn() } }));
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>();
  return {
    ...actual,
    mintInstallationToken: vi.fn(async () => "ghs_test_token"),
    buildAuthenticatedCloneUrl: vi.fn(() => "file:///nonexistent-fixture-remote"),
    resolveCronWorkspaceRoot: vi.fn(() => state.workspaceRoot),
    warnIfCronWorkspaceLowOnDisk: vi.fn(async () => {}),
    postSentryHeartbeat: vi.fn(async () => {}),
  };
});

import { cronContentVendorDriftHandler } from "@/server/inngest/functions/cron-content-vendor-drift";

afterAll(() => {
  if (state.workspaceRoot) rmSync(state.workspaceRoot, { recursive: true, force: true });
});

describe("cron-content-vendor-drift: the git env is read at spawn time (#8211)", () => {
  it("a variable deleted after the module loaded never reaches git, and one added after it does", async () => {
    state.workspaceRoot = mkdtempSync(join(tmpdir(), "vendor-drift-env-"));
    // The module has loaded (static import above) while the sentinel was set.
    expect(process.env[SENTINELS.deleted]).toBe("present-at-module-load");
    delete process.env[SENTINELS.deleted];
    process.env[SENTINELS.added] = "added-after-module-load";
    try {
      const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
      const step = { run: <T,>(_n: string, cb: () => Promise<T>) => cb() };
      const result = await cronContentVendorDriftHandler({ step, logger } as never);
      expect(result).toMatchObject({ ok: false, status: "error" });
    } finally {
      delete process.env[SENTINELS.added];
    }
    const gitCalls = spawnSpy.mock.calls.filter((c) => c[0] === "git");
    expect(gitCalls.length).toBeGreaterThanOrEqual(1); // vacuity floor: the clone was spawned
    expect((gitCalls[0][1] as string[])[0]).toBe("clone");
    for (const call of gitCalls) {
      const env: Record<string, string | undefined> = (call[2] as { env?: NodeJS.ProcessEnv }).env ?? {};
      expect(SENTINELS.deleted in env).toBe(false);
      expect(env[SENTINELS.added]).toBe("added-after-module-load");
      expect(env.GIT_CONFIG_GLOBAL).toBe("/dev/null"); // the isolated env, not a bare passthrough
    }
  });
});
