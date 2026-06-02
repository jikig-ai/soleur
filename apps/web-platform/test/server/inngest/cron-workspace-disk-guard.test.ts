// #4684/#4689 — the pre-clone free-space guard is the observability fold-in that
// closes the blind spot that let the cron ENOSPC class run 6× silently. Its
// load-bearing contract is "MUST NEVER throw" — a wrong floor or a statfs probe
// error must warn-and-continue, never block a clone that would otherwise
// succeed. This file pins that contract (a future edit that lets the guard
// throw would re-break ENOSPC-avoidance). Separate file from the real-spawn
// substrate tests because it vi.mocks node:fs/promises + observability, which
// hoist file-wide and would clobber the real spawnSimple calls there.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const statfsMock = vi.fn();
vi.mock("node:fs/promises", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:fs/promises")>();
  return { ...actual, statfs: (...args: unknown[]) => statfsMock(...args) };
});

const warnSilentFallback = vi.fn();
const reportSilentFallback = vi.fn();
vi.mock("@/server/observability", () => ({
  warnSilentFallback: (...a: unknown[]) => warnSilentFallback(...a),
  reportSilentFallback: (...a: unknown[]) => reportSilentFallback(...a),
}));

import { warnIfCronWorkspaceLowOnDisk } from "@/server/inngest/functions/_cron-shared";

const ORIGINAL_MIN_FREE = process.env.CRON_WORKSPACE_MIN_FREE_MB;

// bsize 4096; pick bavail so freeMb lands below/above a given MB threshold.
const blocksFor = (mb: number) => Math.ceil((mb * 1024 * 1024) / 4096);

describe("warnIfCronWorkspaceLowOnDisk", () => {
  beforeEach(() => {
    statfsMock.mockReset();
    warnSilentFallback.mockReset();
    reportSilentFallback.mockReset();
    delete process.env.CRON_WORKSPACE_MIN_FREE_MB;
  });

  afterEach(() => {
    if (ORIGINAL_MIN_FREE === undefined)
      delete process.env.CRON_WORKSPACE_MIN_FREE_MB;
    else process.env.CRON_WORKSPACE_MIN_FREE_MB = ORIGINAL_MIN_FREE;
  });

  it("warns (op=cron-workspace-low-disk) when free space is below the floor, and does not throw", async () => {
    statfsMock.mockResolvedValue({ bavail: blocksFor(100), bsize: 4096 });
    await expect(
      warnIfCronWorkspaceLowOnDisk("/workspaces/soleur-cron-x-abc", "cron-x"),
    ).resolves.toBeUndefined();
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
    expect(warnSilentFallback.mock.calls[0][1]).toMatchObject({
      op: "cron-workspace-low-disk",
      feature: "cron-x",
    });
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("does NOT warn when free space is at or above the floor", async () => {
    statfsMock.mockResolvedValue({ bavail: blocksFor(1024), bsize: 4096 });
    await warnIfCronWorkspaceLowOnDisk("/workspaces/x", "cron-x");
    expect(warnSilentFallback).not.toHaveBeenCalled();
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("reports (op=cron-workspace-statfs-failed) and does NOT throw when statfs rejects", async () => {
    statfsMock.mockRejectedValue(new Error("EACCES"));
    await expect(
      warnIfCronWorkspaceLowOnDisk("/workspaces/x", "cron-x"),
    ).resolves.toBeUndefined();
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(reportSilentFallback.mock.calls[0][1]).toMatchObject({
      op: "cron-workspace-statfs-failed",
      feature: "cron-x",
    });
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("honors a CRON_WORKSPACE_MIN_FREE_MB override below the actual free space (no warn)", async () => {
    process.env.CRON_WORKSPACE_MIN_FREE_MB = "50";
    statfsMock.mockResolvedValue({ bavail: blocksFor(100), bsize: 4096 });
    await warnIfCronWorkspaceLowOnDisk("/workspaces/x", "cron-x");
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  it("coerces a 0/NaN override back to the 256 MB default floor", async () => {
    process.env.CRON_WORKSPACE_MIN_FREE_MB = "0"; // falsy → default 256
    statfsMock.mockResolvedValue({ bavail: blocksFor(100), bsize: 4096 });
    await warnIfCronWorkspaceLowOnDisk("/workspaces/x", "cron-x");
    // 100 MB free < 256 MB default → warns
    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
  });
});
