// cron-workspace-gc — reclaims leaked ephemeral cron-clone dirs off the shared
// /workspaces volume so a bypassed `finally { rm }` (OOM/ENOSPC/SIGKILL) can no
// longer wedge the persistent KB-workspace volume (the 2026-06-02 freeze, #4882).
//
// The destructive guard is the load-bearing test: the sweep MUST match only the
// `soleur-` prefix, maxdepth 1, age-gated > 1h — a 36-char UUID workspace dir
// must NEVER be swept even when it is old. Pure helpers (freeMb, isSweepable) are
// unit-tested without fs; the handler is driven against a fully mocked
// node:fs/promises. Mirrors cron-supabase-disk-io.test.ts.

import { describe, expect, it, vi, beforeEach } from "vitest";

// vi.hoisted runs BEFORE the ES-module imports below — sets NEXT_PHASE so the
// inngest client's startup-key check short-circuits. Mirrors disk-io test.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

vi.mock("node:fs/promises", () => ({
  statfs: vi.fn(),
  readdir: vi.fn(),
  stat: vi.fn(),
  rm: vi.fn(),
}));

vi.mock("@/server/inngest/functions/_cron-shared", () => ({
  resolveCronWorkspaceRoot: vi.fn(() => "/workspaces"),
  postSentryHeartbeat: vi.fn(async () => {}),
  DEFAULT_CRON_WORKSPACE_MIN_FREE_MB: 256,
  // freeMb now lives in _cron-shared (single source of truth) and is re-exported
  // by cron-workspace-gc; provide the real arithmetic so the handler + the
  // re-exported pure-helper test both compute correctly under the mock.
  freeMb: (s: { bavail: number; bsize: number }) =>
    Math.floor((s.bavail * s.bsize) / (1024 * 1024)),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

import { statfs, readdir, stat, rm } from "node:fs/promises";
import { postSentryHeartbeat } from "@/server/inngest/functions/_cron-shared";
import {
  reportSilentFallback,
  warnSilentFallback,
  infoSilentFallback,
} from "@/server/observability";
import {
  cronWorkspaceGc,
  cronWorkspaceGcHandler,
  freeMb,
  isSweepable,
  SENTRY_MONITOR_SLUG,
  CRON_DIR_PREFIX,
  DEFAULT_MAX_AGE_MS,
} from "@/server/inngest/functions/cron-workspace-gc";

const MIB = 1024 * 1024;
const UUID_DIR = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"; // 36 chars, never soleur-*

// A fake step that just runs each callback inline; a logger that records nothing.
const fakeStep = { run: async <T>(_name: string, cb: () => Promise<T>): Promise<T> => cb() };
const fakeLogger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

function statfsFor(freeMbValue: number) {
  return { bavail: freeMbValue, bsize: MIB } as unknown as Awaited<ReturnType<typeof statfs>>;
}

function dirStat(mtimeMs: number) {
  return { isDirectory: () => true, mtimeMs } as unknown as Awaited<ReturnType<typeof stat>>;
}

beforeEach(() => {
  vi.clearAllMocks();
  delete process.env.CRON_WORKSPACE_GC_MAX_AGE_MS;
  delete process.env.CRON_WORKSPACE_MIN_FREE_MB;
});

describe("freeMb — bavail arithmetic (not bfree)", () => {
  it("floors bavail*bsize to whole MB", () => {
    expect(freeMb({ bavail: 100, bsize: MIB })).toBe(100);
    expect(freeMb({ bavail: 3, bsize: MIB + 1 })).toBe(3); // floors the remainder
  });
});

describe("isSweepable — prefix + age guard", () => {
  it("aged soleur- dir is sweepable", () => {
    expect(isSweepable("soleur-cron-bug-fixer-abc", DEFAULT_MAX_AGE_MS + 1, DEFAULT_MAX_AGE_MS)).toBe(true);
  });
  it("fresh soleur- dir (within maxAge) is NOT sweepable", () => {
    expect(isSweepable("soleur-cron-bug-fixer-abc", 30 * 60 * 1000, DEFAULT_MAX_AGE_MS)).toBe(false);
  });
  it("a 36-char UUID workspace dir is NEVER sweepable even when old (load-bearing)", () => {
    expect(isSweepable(UUID_DIR, DEFAULT_MAX_AGE_MS * 10, DEFAULT_MAX_AGE_MS)).toBe(false);
  });
  it("CRON_DIR_PREFIX is the soleur- prefix setupEphemeralWorkspace mkdtemps", () => {
    expect(CRON_DIR_PREFIX).toBe("soleur-");
  });
});

describe("cronWorkspaceGcHandler — sweep semantics", () => {
  it("removes only aged soleur-* dirs, leaving UUID + fresh cron dirs", async () => {
    const now = Date.now();
    (statfs as unknown as ReturnType<typeof vi.fn>)
      .mockResolvedValueOnce(statfsFor(500)) // before
      .mockResolvedValueOnce(statfsFor(600)); // after (freed 100, both > floor)
    (readdir as unknown as ReturnType<typeof vi.fn>).mockResolvedValue([
      "soleur-old",
      "soleur-fresh",
      UUID_DIR,
    ]);
    (stat as unknown as ReturnType<typeof vi.fn>).mockImplementation(async (p: string) => {
      if (p.endsWith("soleur-old")) return dirStat(now - 2 * 60 * 60 * 1000); // 2h old
      if (p.endsWith("soleur-fresh")) return dirStat(now - 60 * 1000); // 1m old
      return dirStat(now - 99 * 60 * 60 * 1000); // UUID very old — must still be spared
    });
    (rm as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(undefined);

    const result = await cronWorkspaceGcHandler({ step: fakeStep, logger: fakeLogger });

    expect(rm).toHaveBeenCalledTimes(1);
    expect(rm).toHaveBeenCalledWith(expect.stringContaining("soleur-old"), expect.anything());
    expect(rm).not.toHaveBeenCalledWith(expect.stringContaining(UUID_DIR), expect.anything());
    expect(rm).not.toHaveBeenCalledWith(expect.stringContaining("soleur-fresh"), expect.anything());
    expect(result.sweptCount).toBe(1);
    expect(result.freedMb).toBe(100);
    expect(result.root).toBe("/workspaces");
    expect(postSentryHeartbeat).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG }),
    );
    expect(warnSilentFallback).not.toHaveBeenCalled();

    // AC4 — every-run reclaim signal fires on the HEALTHY path (the case that
    // was previously Sentry-silent: logger.info only). This is the no-SSH
    // reclaim-verification signal the issue (#4897) exists for.
    expect(infoSilentFallback).toHaveBeenCalledTimes(1);
    const infoCall = (infoSilentFallback as unknown as ReturnType<typeof vi.fn>).mock.calls[0];
    expect(infoCall[1].feature).toBe("cron-workspace-gc");
    expect(infoCall[1].extra).toMatchObject({
      freeMbBefore: 500,
      freeMbAfter: 600,
      freedMb: 100,
      sweptCount: 1,
      root: "/workspaces",
    });
  });

  it("emits a warn with the before/after payload when the volume is still under floor after sweeping", async () => {
    const now = Date.now();
    (statfs as unknown as ReturnType<typeof vi.fn>)
      .mockResolvedValueOnce(statfsFor(50)) // before
      .mockResolvedValueOnce(statfsFor(100)); // after — still < 256 floor
    (readdir as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(["soleur-old"]);
    (stat as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(dirStat(now - 2 * 60 * 60 * 1000));
    (rm as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(undefined);

    await cronWorkspaceGcHandler({ step: fakeStep, logger: fakeLogger });

    expect(warnSilentFallback).toHaveBeenCalledTimes(1);
    const extra = (warnSilentFallback as unknown as ReturnType<typeof vi.fn>).mock.calls[0][1].extra;
    expect(extra).toMatchObject({
      freeMbBefore: 50,
      freeMbAfter: 100,
      freedMb: 50,
      sweptCount: 1,
      root: "/workspaces",
    });

    // AC5 — info fires on EVERY run, independent of the low-disk warn. Both the
    // informational (every-run) and actionable (low-disk) signals are emitted at
    // distinct Sentry levels so on-call can filter them apart.
    expect(infoSilentFallback).toHaveBeenCalledTimes(1);
    expect(
      (infoSilentFallback as unknown as ReturnType<typeof vi.fn>).mock.calls[0][1].extra,
    ).toMatchObject({
      freeMbBefore: 50,
      freeMbAfter: 100,
      freedMb: 50,
      sweptCount: 1,
      root: "/workspaces",
    });
  });

  it("skips a non-directory soleur-* entry (a stray clone leftover file) — never rm'd", async () => {
    // A crashed clone can leave a stray `soleur-*.log`/lockfile under the root.
    // It matches the prefix but is NOT a directory, so the isDirectory() guard
    // must skip it — rm({recursive}) on a misclassified entry is exactly the
    // destructive-safety surface this cron exists to protect.
    const now = Date.now();
    (statfs as unknown as ReturnType<typeof vi.fn>)
      .mockResolvedValueOnce(statfsFor(500))
      .mockResolvedValueOnce(statfsFor(500));
    (readdir as unknown as ReturnType<typeof vi.fn>).mockResolvedValue([
      "soleur-stale.log",
    ]);
    (stat as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
      isDirectory: () => false,
      mtimeMs: now - 99 * 60 * 60 * 1000, // very old — age alone would sweep a dir
    } as unknown as Awaited<ReturnType<typeof stat>>);

    const result = await cronWorkspaceGcHandler({ step: fakeStep, logger: fakeLogger });

    expect(rm).not.toHaveBeenCalled();
    expect(result.sweptCount).toBe(0);
  });

  it("freedMb falls back to 0 (no NaN/negative) when the after-sweep statfs fails", async () => {
    const now = Date.now();
    const eio = Object.assign(new Error("EIO"), { code: "EIO" });
    (statfs as unknown as ReturnType<typeof vi.fn>)
      .mockResolvedValueOnce(statfsFor(500)) // before — ok
      .mockRejectedValueOnce(eio); // after — fails (non-ENOENT)
    (readdir as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(["soleur-old"]);
    (stat as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(dirStat(now - 2 * 60 * 60 * 1000));
    (rm as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(undefined);

    const result = await cronWorkspaceGcHandler({ step: fakeStep, logger: fakeLogger });

    expect(result.sweptCount).toBe(1); // sweep still happened
    expect(result.freedMb).toBe(0); // graceful degrade — no NaN, no negative
    expect(reportSilentFallback).toHaveBeenCalledTimes(1); // the statfs-after failure

    // Test Scenario 4 — the every-run info event still fires with freedMb: 0
    // (no NaN) even when the after-sweep statfs degraded.
    expect(infoSilentFallback).toHaveBeenCalledTimes(1);
    expect(
      (infoSilentFallback as unknown as ReturnType<typeof vi.fn>).mock.calls[0][1].extra,
    ).toMatchObject({ freedMb: 0, sweptCount: 1 });
    expect(postSentryHeartbeat).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
  });

  it("tolerates an ENOENT root (no mounted volume) — no throw, no rm, heartbeat ok, no page", async () => {
    const enoent = Object.assign(new Error("ENOENT"), { code: "ENOENT" });
    (statfs as unknown as ReturnType<typeof vi.fn>).mockRejectedValue(enoent);

    const result = await cronWorkspaceGcHandler({ step: fakeStep, logger: fakeLogger });

    expect(result.sweptCount).toBe(0);
    expect(rm).not.toHaveBeenCalled();
    expect(reportSilentFallback).not.toHaveBeenCalled();
    // AC6 — the absent-volume short-circuit returns before the emit; an absent
    // volume has nothing to report, so the info channel stays quiet.
    expect(infoSilentFallback).not.toHaveBeenCalled();
    expect(postSentryHeartbeat).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG }),
    );
  });

  it("readdir ENOENT (statfs ok, root vanished before listing) also stays info-silent — no emit", async () => {
    // The SECOND ENOENT short-circuit: statfs-before succeeds but the root is
    // gone by the time we readdir it (a racing unmount). It returns before the
    // every-run emit too (cron-workspace-gc.ts:138-144), so the info channel
    // must stay quiet on this degraded sub-path just like the statfs-before one.
    const enoent = Object.assign(new Error("ENOENT"), { code: "ENOENT" });
    (statfs as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(statfsFor(500));
    (readdir as unknown as ReturnType<typeof vi.fn>).mockRejectedValue(enoent);

    const result = await cronWorkspaceGcHandler({ step: fakeStep, logger: fakeLogger });

    expect(result.sweptCount).toBe(0);
    expect(rm).not.toHaveBeenCalled();
    expect(reportSilentFallback).not.toHaveBeenCalled();
    expect(infoSilentFallback).not.toHaveBeenCalled();
    expect(postSentryHeartbeat).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG }),
    );
  });

  it("a single rm EACCES does not abort the loop — other dirs still swept, failure reported once", async () => {
    const now = Date.now();
    (statfs as unknown as ReturnType<typeof vi.fn>)
      .mockResolvedValueOnce(statfsFor(500))
      .mockResolvedValueOnce(statfsFor(500));
    (readdir as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(["soleur-a", "soleur-b"]);
    (stat as unknown as ReturnType<typeof vi.fn>).mockResolvedValue(dirStat(now - 2 * 60 * 60 * 1000));
    const eacces = Object.assign(new Error("EACCES"), { code: "EACCES" });
    (rm as unknown as ReturnType<typeof vi.fn>)
      .mockRejectedValueOnce(eacces) // soleur-a fails
      .mockResolvedValueOnce(undefined); // soleur-b succeeds

    const result = await cronWorkspaceGcHandler({ step: fakeStep, logger: fakeLogger });

    expect(rm).toHaveBeenCalledTimes(2);
    expect(result.sweptCount).toBe(1);
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(postSentryHeartbeat).toHaveBeenCalledWith(
      expect.objectContaining({ ok: true }),
    );
  });
});

describe("cronWorkspaceGc — registration shape", () => {
  it("loads without throwing and exposes the monitor slug", () => {
    expect(cronWorkspaceGc).toBeDefined();
    expect(SENTRY_MONITOR_SLUG).toBe("scheduled-workspace-gc");
  });
});
