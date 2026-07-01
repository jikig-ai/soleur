// Focused tests for `enumerateSiblingDenyPaths` — the per-sibling sandbox
// deny-list computed at dispatch (#5733 follow-up to PR #5848). The security
// contract: the agent's OWN workspace is never denied (stays read+write),
// every sibling IS denied, and enumeration failure fails CLOSED to a broad
// parent deny (strand-over-leak) with a Sentry mirror. Kept in a separate file
// from `agent-runner-helpers.test.ts` because the fail-closed test mocks
// `@/server/observability` (vi.mock hoists file-wide).

import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Partial mock so the other named exports of observability survive
// (wholesale-mock-drops-named-exports trap); only spy reportSilentFallback.
vi.mock("@/server/observability", async (importOriginal) => {
  const actual =
    await importOriginal<typeof import("@/server/observability")>();
  return { ...actual, reportSilentFallback: vi.fn() };
});

import { enumerateSiblingDenyPaths } from "@/server/agent-runner-sandbox-config";
import { reportSilentFallback } from "@/server/observability";

describe("enumerateSiblingDenyPaths", () => {
  let root: string;
  let own: string;

  beforeEach(() => {
    vi.clearAllMocks();
    root = mkdtempSync(join(tmpdir(), "sbx-enum-"));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    mkdirSync(own);
    vi.stubEnv("WORKSPACES_ROOT", root);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
  });

  it("denies every sibling (incl. infra dirs) + /proc, excludes own; not degraded", () => {
    const sibA = join(root, "00000000-0000-0000-0000-0000000000a1");
    const sibB = join(root, "00000000-0000-0000-0000-0000000000b2");
    const cron = join(root, ".cron"); // infra sibling — the agent must not read it
    mkdirSync(sibA);
    mkdirSync(sibB);
    mkdirSync(cron);

    const { denyRead, degraded } = enumerateSiblingDenyPaths(own);

    expect(degraded).toBe(false);
    expect(denyRead).toContain(sibA);
    expect(denyRead).toContain(sibB);
    expect(denyRead).toContain(cron);
    expect(denyRead).toContain("/proc");
    expect(denyRead).not.toContain(own);
    // Exactly 3 siblings + /proc.
    expect(denyRead).toHaveLength(4);
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("excludes own by CANONICAL path even when passed a symlink (symlink-safe)", () => {
    const sibA = join(root, "00000000-0000-0000-0000-0000000000a1");
    mkdirSync(sibA);
    // A symlink INTO the root pointing at own — passing the link path must
    // still exclude the real own dir (never deny the agent its own repo).
    const ownLink = join(root, "own-link");
    symlinkSync(own, ownLink);

    const { denyRead } = enumerateSiblingDenyPaths(ownLink);
    expect(denyRead).not.toContain(own);
    expect(denyRead).toContain(sibA);
  });

  it("empty root → only /proc denied, own writable, not degraded", () => {
    // own is the only entry; remove it so the root is empty.
    rmSync(own, { recursive: true, force: true });
    const { denyRead, degraded } = enumerateSiblingDenyPaths(own);
    expect(degraded).toBe(false);
    expect(denyRead).toEqual(["/proc"]);
  });

  it("ENOENT root (no mounted volume) → broad deny, NOT degraded, no Sentry page", () => {
    vi.stubEnv("WORKSPACES_ROOT", join(root, "does-not-exist"));
    const { denyRead, degraded } = enumerateSiblingDenyPaths(own);
    expect(degraded).toBe(false);
    expect(denyRead).toEqual([join(root, "does-not-exist"), "/proc"]);
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  // The security drift-guard: on a REAL enumeration failure (root is a file →
  // readdirSync throws ENOTDIR, a non-ENOENT error) the function MUST fail
  // closed to the broad parent deny (workspace read-only → agent strands) and
  // MUST mirror to Sentry. This locks in strand-over-leak — a sibling must
  // never become readable because enumeration hiccuped.
  it("fail-closed: non-ENOENT enumeration error → broad deny + degraded + Sentry mirror", () => {
    const asFile = join(root, "root-is-a-file");
    writeFileSync(asFile, "not a directory");
    vi.stubEnv("WORKSPACES_ROOT", asFile);

    const { denyRead, degraded } = enumerateSiblingDenyPaths(
      join(asFile, "own"),
    );

    expect(degraded).toBe(true);
    expect(denyRead).toEqual([asFile, "/proc"]);
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const call = (reportSilentFallback as unknown as ReturnType<typeof vi.fn>)
      .mock.calls[0];
    expect(call[1]).toMatchObject({
      feature: "agent-sandbox",
      op: "enumerateSiblingDenyPaths",
    });
    // The own-workspace UUID is threaded as the join key back to the strand
    // telemetry so the degraded event is attributable to a session.
    expect(call[1].extra).toMatchObject({ workspace: "own" });
  });

  it("denies a SIBLING that is itself a symlink to a different real dir (not mis-excluded)", () => {
    // A sibling entry whose realpath resolves ELSEWHERE (not to own) must still
    // be denied — the realpath filter excludes ONLY entries that resolve to own.
    const realTarget = mkdtempSync(join(tmpdir(), "sbx-target-"));
    const sibLink = join(root, "sib-link");
    symlinkSync(realTarget, sibLink);
    try {
      const { denyRead } = enumerateSiblingDenyPaths(own);
      expect(denyRead).toContain(sibLink); // stored path is the link, denied
      expect(denyRead).not.toContain(own);
    } finally {
      rmSync(realTarget, { recursive: true, force: true });
    }
  });

  it("workspacePath not under root (own absent) → every entry denied, nothing wrongly excluded", () => {
    const sibA = join(root, "00000000-0000-0000-0000-0000000000a1");
    const sibB = join(root, "00000000-0000-0000-0000-0000000000b2");
    mkdirSync(sibA);
    mkdirSync(sibB);
    // own lives elsewhere, so it is not one of the root's entries — the
    // own-exclusion is a no-op and EVERY root entry (incl. the beforeEach
    // `own` dir) is denied (safe superset — nothing wrongly excluded).
    const elsewhere = join(mkdtempSync(join(tmpdir(), "sbx-elsewhere-")), "own");
    const { denyRead, degraded } = enumerateSiblingDenyPaths(elsewhere);
    expect(degraded).toBe(false);
    expect([...denyRead].sort()).toEqual([own, sibA, sibB, "/proc"].sort());
  });

  it("denies a plain FILE sibling entry (files are denied, harmless)", () => {
    const fileSib = join(root, "stray.txt");
    writeFileSync(fileSib, "not a dir");
    const { denyRead } = enumerateSiblingDenyPaths(own);
    expect(denyRead).toContain(fileSib);
  });

  it("ENOENT root in PRODUCTION (vanished bind-mount) → broad deny + degraded + Sentry page", () => {
    // In prod the volume is bind-mounted at boot, so an ENOENT on the root is a
    // real fault (the mount vanished), NOT the benign local/CI absence.
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("WORKSPACES_ROOT", join(root, "vanished"));
    const { denyRead, degraded } = enumerateSiblingDenyPaths(own);
    expect(degraded).toBe(true);
    expect(denyRead).toEqual([join(root, "vanished"), "/proc"]);
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(
      (reportSilentFallback as unknown as ReturnType<typeof vi.fn>).mock
        .calls[0][1],
    ).toMatchObject({ feature: "agent-sandbox", op: "enumerateSiblingDenyPaths" });
  });
});
