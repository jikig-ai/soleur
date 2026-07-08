// Unit tests for atomicGitConfig — the lock-free TS git-config writer that routes
// workspace.ts's host-side owner-identity seed (#6191, ADR-099 §Known latent surfaces).
// Design: cp-p current .git/config → same-dir temp → `git config --file <tmp> …` →
// renameSync(tmp, config). Atomic by rename(2), never touches `.git/config.lock`.
//
// The masked-target branch (a non-regular node at the config target — must never occur
// host-side) is the sole loud signal: it fires a CAPTURED reportSilentFallback event
// (cq-silent-fallback-must-mirror-to-sentry) and aborts WITHOUT the rename, never throws.
import { describe, test, expect, afterEach, beforeEach, vi } from "vitest";
import { execFileSync } from "child_process";
import {
  mkdtempSync,
  rmSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  statSync,
} from "fs";
import { tmpdir } from "os";
import { join } from "path";

// Spy on the captured-Sentry-event path. Partial mock (importOriginal) so no sibling
// observability export is dropped — mirrors git-data-replication.test.ts.
const reportSilentFallback = vi.fn();
vi.mock("../server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/observability")>()),
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
}));

import { atomicGitConfig } from "../server/git-config-atomic";

const made: string[] = [];
function freshRepo(): string {
  const dir = mkdtempSync(join(tmpdir(), "gitcfg-atomic-"));
  made.push(dir);
  execFileSync("git", ["init", "-q"], { cwd: dir, stdio: "pipe" });
  return dir;
}
function cfg(dir: string, key: string): string | null {
  try {
    return execFileSync("git", ["config", "--get", key], { cwd: dir, stdio: "pipe" })
      .toString()
      .trim();
  } catch {
    return null; // git config --get exits non-zero when the key is absent
  }
}

beforeEach(() => {
  reportSilentFallback.mockClear();
});

afterEach(() => {
  for (const d of made.splice(0)) {
    try {
      rmSync(d, { recursive: true, force: true });
    } catch {
      /* best-effort */
    }
  }
});

describe("atomicGitConfig", () => {
  test("clean write — value lands and is readable via git config --get", () => {
    const dir = freshRepo();
    atomicGitConfig(dir, ["config", "user.email", "owner@example.com"]);
    expect(cfg(dir, "user.email")).toBe("owner@example.com");
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  test("other pre-existing config keys survive the write (cp-first invariant)", () => {
    const dir = freshRepo();
    // Pre-seed an unrelated key; the empty-temp bug would drop it.
    execFileSync("git", ["config", "core.someflag", "sentinel-x"], { cwd: dir, stdio: "pipe" });
    atomicGitConfig(dir, ["config", "user.email", "owner@example.com"]);
    expect(cfg(dir, "user.email")).toBe("owner@example.com");
    expect(cfg(dir, "core.someflag")).toBe("sentinel-x"); // NOT dropped
  });

  test("pre-existing regular config.lock does not block the write and is not deleted", () => {
    const dir = freshRepo();
    const lock = join(dir, ".git", "config.lock");
    writeFileSync(lock, "stale-lock-from-another-writer\n");
    atomicGitConfig(dir, ["config", "user.name", "Owner Name"]);
    expect(cfg(dir, "user.name")).toBe("Owner Name"); // rename is lock-independent
    expect(existsSync(lock)).toBe(true); // we never touch someone else's lock
  });

  test("non-regular config target is refused: no throw, fires reportSilentFallback, config not renamed over", () => {
    const dir = freshRepo();
    const config = join(dir, ".git", "config");
    // Simulate a masked / anomalous target: replace the regular config with a directory
    // (a non-regular node, the host-side proxy for the sandbox char-device wedge).
    rmSync(config, { force: true });
    mkdirSync(config);
    expect(() => atomicGitConfig(dir, ["config", "user.email", "owner@example.com"])).not.toThrow();
    // The captured Sentry event is the sole loud signal for an unseeded-identity workspace.
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [, opts] = reportSilentFallback.mock.calls[0] as [unknown, { feature?: string; op?: string }];
    expect(opts?.feature).toBe("git-config-atomic");
    expect(opts?.op).toBe("masked-target");
    // Target untouched (still the non-regular node we planted — no rename over it).
    expect(statSync(config).isDirectory()).toBe(true);
  });
});
