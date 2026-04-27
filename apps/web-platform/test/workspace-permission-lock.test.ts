// Contract tests for workspace-permission-lock (#2918).
//
// T1 — same-path serialization: two concurrent withWorkspacePermissionLock
//      calls on the SAME canonicalized path serialize.
// T2 — different-path concurrency: distinct paths run concurrently (no
//      false serialization).
// T3 — atomicWriteJson: write goes through a tmp file then renames; on
//      throw, the tmp file is cleaned up and no partial file lands at
//      the target path.
// T4 — lock release on `fn` throw: lock entry is freed so a subsequent
//      call resolves rather than dead-locking.
//
// The helper is in-process (single Next.js worker per container —
// out-of-scope for multi-process coordination per plan §Risks).

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, existsSync, readFileSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import path from "path";

import {
  withWorkspacePermissionLock,
  atomicWriteJson,
} from "@/server/workspace-permission-lock";

let tmpRoot: string;

beforeEach(() => {
  tmpRoot = mkdtempSync(path.join(tmpdir(), "wpl-"));
});

afterEach(() => {
  try {
    rmSync(tmpRoot, { recursive: true, force: true });
  } catch {
    // best-effort cleanup
  }
});

describe("withWorkspacePermissionLock", () => {
  // T1: same-path serialization
  it("T1: serializes concurrent fns on the same canonicalized path", async () => {
    const order: string[] = [];
    const ws = path.join(tmpRoot, "ws-a");

    let releaseFirst!: () => void;
    const firstStarted = new Promise<void>((resolveStarted) => {
      const firstPromise = withWorkspacePermissionLock(ws, async () => {
        order.push("first-start");
        resolveStarted();
        await new Promise<void>((r) => {
          releaseFirst = r;
        });
        order.push("first-end");
      });
      void firstPromise;
    });

    await firstStarted;

    // Second fn starts immediately, must serialize after first completes.
    let secondRan = false;
    const secondPromise = withWorkspacePermissionLock(ws, async () => {
      order.push("second-start");
      secondRan = true;
      order.push("second-end");
    });

    // Give the event loop a chance — second must NOT have run yet.
    await new Promise((r) => setTimeout(r, 10));
    expect(secondRan).toBe(false);
    // Pin the EXACT intermediate state — distinguishes "lock works" from
    // "second is in microtask wait but flagged via secondRan". The lock
    // must hold first inside the critical section; nothing else has run.
    expect(order).toEqual(["first-start"]);

    // Release first; then second runs.
    releaseFirst();
    await secondPromise;

    expect(order).toEqual([
      "first-start",
      "first-end",
      "second-start",
      "second-end",
    ]);
  });

  // T2: different-path concurrency
  it("T2: different paths do NOT serialize (concurrent execution)", async () => {
    const wsA = path.join(tmpRoot, "ws-a");
    const wsB = path.join(tmpRoot, "ws-b");

    const order: string[] = [];
    let releaseA!: () => void;

    const aPromise = withWorkspacePermissionLock(wsA, async () => {
      order.push("a-start");
      await new Promise<void>((r) => {
        releaseA = r;
      });
      order.push("a-end");
    });

    // Give A a tick to enter its critical section
    await new Promise((r) => setTimeout(r, 5));

    // B should run concurrently (NOT block on A)
    const bPromise = withWorkspacePermissionLock(wsB, async () => {
      order.push("b-start");
      order.push("b-end");
    });

    await bPromise;
    expect(order).toContain("b-end");
    // A still suspended
    expect(order).not.toContain("a-end");

    releaseA();
    await aPromise;
    expect(order).toContain("a-end");
  });

  // T4: lock release on fn throw
  it("T4: lock releases when fn throws, allowing the next caller to proceed", async () => {
    const ws = path.join(tmpRoot, "ws-throw");

    await expect(
      withWorkspacePermissionLock(ws, async () => {
        throw new Error("boom");
      }),
    ).rejects.toThrow("boom");

    // Subsequent call must resolve.
    let secondRan = false;
    await withWorkspacePermissionLock(ws, async () => {
      secondRan = true;
    });
    expect(secondRan).toBe(true);
  });
});

describe("atomicWriteJson", () => {
  // T3: tmp + rename, no partial file on throw
  it("T3: writes JSON atomically (tmp → rename)", () => {
    const target = path.join(tmpRoot, "settings.json");
    atomicWriteJson(target, { permissions: { allow: ["Read"] } });

    expect(existsSync(target)).toBe(true);
    const parsed = JSON.parse(readFileSync(target, "utf8"));
    expect(parsed).toEqual({ permissions: { allow: ["Read"] } });

    // No tmp leaks at canonical suffix. Filter-and-equal so a failure
    // surfaces the leaked filename in the diff.
    const dirEntries = require("fs").readdirSync(tmpRoot) as string[];
    const tmps = dirEntries.filter(
      (e) => e.startsWith("settings.json.") && e.endsWith(".tmp"),
    );
    expect(tmps).toEqual([]);
  });

  it("T3b: leaves no partial file when JSON encoding throws", () => {
    const target = path.join(tmpRoot, "settings-bad.json");

    // Pre-existing content must remain unchanged on failed write.
    writeFileSync(target, '{"original":true}\n');

    // Cyclic object → JSON.stringify throws TypeError.
    const cyclic: Record<string, unknown> = {};
    cyclic.self = cyclic;
    expect(() => atomicWriteJson(target, cyclic)).toThrow();

    // Original file content preserved.
    const content = readFileSync(target, "utf8");
    expect(content).toBe('{"original":true}\n');

    // No leftover *.tmp siblings. Filter-and-equal so a failure surfaces
    // the leaked filename in the diff.
    const dirEntries = require("fs").readdirSync(tmpRoot) as string[];
    const tmps = dirEntries.filter(
      (e) => e.startsWith("settings-bad.json.") && e.endsWith(".tmp"),
    );
    expect(tmps).toEqual([]);
  });
});
