/**
 * #9776 — protected-branch resolver (the lane's only I/O).
 *
 * Union of (a) the GitHub API default branch (authoritative), (b) the local `refs/remotes/origin/HEAD` (agent-writable:
 * it can ADD a name, never remove one) and (c) the constants `main` / `master`. Failure degrades to
 * `authoritative: false` and is mirrored to Sentry (`default-branch-resolve`). AC-3 and AC-23.
 */
import { vi, describe, test, expect, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, writeFileSync, symlinkSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const { mockReportSilentFallback, mockWarnSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
}));
vi.mock("../server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
}));

import {
  createProtectedBranchResolver,
  readLocalOriginHead,
  POSITIVE_TTL_MS,
  NEGATIVE_TTL_MS,
} from "../server/resolve-protected-branches";

let work: string;
beforeEach(() => {
  vi.clearAllMocks();
  work = mkdtempSync(join(tmpdir(), "rpb-"));
  mkdirSync(join(work, ".git", "refs", "remotes", "origin"), { recursive: true });
});
afterEach(() => rmSync(work, { recursive: true, force: true }));

function writeHead(content: string) {
  writeFileSync(join(work, ".git", "refs", "remotes", "origin", "HEAD"), content);
}
const input = (over: Record<string, unknown> = {}) => ({
  owner: "alice",
  repo: "app",
  installationId: 42 as number | null,
  workspacePath: work,
  ...over,
});

describe("resolveProtectedBranches union rule (AC-3)", () => {
  test("API default branch `develop` joins main and master and is authoritative", async () => {
    const fetchDefaultBranch = vi.fn().mockResolvedValue("develop");
    const r = await createProtectedBranchResolver(input(), { fetchDefaultBranch })();
    expect([...r.names].sort()).toEqual(["develop", "main", "master"]);
    expect(r.authoritative).toBe(true);
    expect(fetchDefaultBranch).toHaveBeenCalledWith(42, "alice", "app", expect.any(AbortSignal));
  });

  test("a tampered local origin/HEAD can ADD a name but never remove main, master or the API name", async () => {
    writeHead("ref: refs/remotes/origin/evil\n");
    const r = await createProtectedBranchResolver(input(), { fetchDefaultBranch: async () => "develop" })();
    expect(r.names.has("evil")).toBe(true);
    for (const keep of ["main", "master", "develop"]) expect(r.names.has(keep)).toBe(true);
  });

  test("API failure: authoritative=false, constants kept, mirrored to Sentry as default-branch-resolve", async () => {
    const r = await createProtectedBranchResolver(input(), {
      fetchDefaultBranch: async () => {
        throw new Error("503");
      },
    })();
    expect(r.authoritative).toBe(false);
    expect([...r.names].sort()).toEqual(["main", "master"]);
    // null first arg, never the Error (#8629: the pino mirror would capture a passed Error first and Sentry would drop
    // the tagged capture); the error class rides in `extra`.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ feature: "cc-permissions", op: "default-branch-resolve", extra: expect.objectContaining({ reason: "api-error", errName: "Error" }) }),
    );
  });

  test("no installation is an expected state: warned, not reported as an error", async () => {
    await createProtectedBranchResolver(input({ installationId: null }), { fetchDefaultBranch: vi.fn() })();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
    expect(mockWarnSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({ op: "default-branch-resolve" }));
  });

  test("no installation id or no connected repo: unresolved, no API call", async () => {
    const fetchDefaultBranch = vi.fn();
    const a = await createProtectedBranchResolver(input({ installationId: null }), { fetchDefaultBranch })();
    const b = await createProtectedBranchResolver(input({ owner: "", repo: "" }), { fetchDefaultBranch })();
    expect(a.authoritative).toBe(false);
    expect(b.authoritative).toBe(false);
    expect(fetchDefaultBranch).not.toHaveBeenCalled();
  });

  test("a timeout counts as failure (3 s bound, aborts the request)", async () => {
    vi.useFakeTimers();
    try {
      const fetchDefaultBranch = vi.fn((_i: number, _o: string, _r: string, signal: AbortSignal) =>
        new Promise<string>((_res, rej) => signal.addEventListener("abort", () => rej(new Error("aborted")))),
      );
      const p = createProtectedBranchResolver(input(), { fetchDefaultBranch, readLocal: async () => null })();
      await vi.advanceTimersByTimeAsync(3_100);
      const r = await p;
      expect(r.authoritative).toBe(false);
    } finally {
      vi.useRealTimers();
    }
  });

  test("an API answer that is not a safe branch name is ignored (and counts as unresolved)", async () => {
    for (const bad of ["", "a b", "x\ny", "../../etc", "a".repeat(300), 5 as unknown as string]) {
      const r = await createProtectedBranchResolver(input(), { fetchDefaultBranch: async () => bad })();
      expect(r.authoritative, JSON.stringify(bad)).toBe(false);
      expect([...r.names].sort()).toEqual(["main", "master"]);
    }
  });
});

describe("local origin/HEAD read is hardened (AC-23)", () => {
  test("accepts exactly `ref: refs/remotes/origin/<safe>`", async () => {
    writeHead("ref: refs/remotes/origin/trunk\n");
    expect(await readLocalOriginHead(work)).toBe("trunk");
  });

  test.each([
    ["no prefix", "trunk\n"],
    ["wrong remote", "ref: refs/remotes/upstream/trunk\n"],
    ["traversal", "ref: refs/remotes/origin/../../x\n"],
    ["space in name", "ref: refs/remotes/origin/a b\n"],
    ["extra lines", "ref: refs/remotes/origin/x\nref: refs/remotes/origin/y\n"],
    ["empty", ""],
  ])("ignores a malformed file (%s)", async (_label, content) => {
    writeHead(content);
    expect(await readLocalOriginHead(work)).toBeNull();
  });

  test("ignores an oversize file", async () => {
    writeHead(`ref: refs/remotes/origin/${"a".repeat(10_000)}\n`);
    expect(await readLocalOriginHead(work)).toBeNull();
  });

  test("refuses a symlink", async () => {
    const real = join(work, "real-head");
    writeFileSync(real, "ref: refs/remotes/origin/evil\n");
    const link = join(work, ".git", "refs", "remotes", "origin", "HEAD");
    symlinkSync(real, link);
    expect(await readLocalOriginHead(work)).toBeNull();
  });

  test("refuses a FIFO without blocking", async () => {
    const link = join(work, ".git", "refs", "remotes", "origin", "HEAD");
    execFileSync("mkfifo", [link]);
    expect(await readLocalOriginHead(work)).toBeNull();
  });

  test("a missing file or directory is null, not a throw", async () => {
    expect(await readLocalOriginHead(join(work, "nope"))).toBeNull();
  });
});

describe("memoisation (AC-23)", () => {
  test("the TTLs are the ruled values: 10 minutes positive, 30 seconds negative, 3 seconds lookup", async () => {
    const mod = await import("../server/resolve-protected-branches");
    expect(POSITIVE_TTL_MS).toBe(600_000);
    expect(NEGATIVE_TTL_MS).toBe(30_000);
    expect(mod.RESOLVE_TIMEOUT_MS).toBe(3_000);
  });

  test("a positive result is memoised for the TTL and re-resolved after it (a rename must not stay stale)", async () => {
    let t = 1_000;
    const fetchDefaultBranch = vi.fn().mockResolvedValueOnce("main").mockResolvedValueOnce("develop");
    const resolve = createProtectedBranchResolver(input(), { fetchDefaultBranch, now: () => t });
    await resolve();
    await resolve();
    expect(fetchDefaultBranch).toHaveBeenCalledTimes(1);
    t += POSITIVE_TTL_MS + 1;
    const after = await resolve();
    expect(fetchDefaultBranch).toHaveBeenCalledTimes(2);
    expect(after.names.has("develop")).toBe(true);
  });

  test("a negative result is cached for 30 s only", async () => {
    let t = 1_000;
    const fetchDefaultBranch = vi.fn().mockRejectedValueOnce(new Error("x")).mockResolvedValueOnce("develop");
    const resolve = createProtectedBranchResolver(input(), { fetchDefaultBranch, now: () => t });
    await resolve();
    await resolve();
    expect(fetchDefaultBranch).toHaveBeenCalledTimes(1);
    t += NEGATIVE_TTL_MS + 1;
    const after = await resolve();
    expect(fetchDefaultBranch).toHaveBeenCalledTimes(2);
    expect(after.authoritative).toBe(true);
  });

  test("concurrent callers share one in-flight lookup", async () => {
    const fetchDefaultBranch = vi.fn().mockResolvedValue("main");
    const resolve = createProtectedBranchResolver(input(), { fetchDefaultBranch });
    await Promise.all([resolve(), resolve(), resolve()]);
    expect(fetchDefaultBranch).toHaveBeenCalledTimes(1);
  });
});

describe("telemetry hygiene", () => {
  test("a failure report never carries a branch name or a path from the agent-writable file", async () => {
    writeHead("ref: refs/remotes/origin/secret-branch-name\n");
    await createProtectedBranchResolver(input(), {
      fetchDefaultBranch: async () => {
        throw new Error("503");
      },
    })();
    expect(JSON.stringify(mockReportSilentFallback.mock.calls)).not.toContain("secret-branch-name");
  });
});
