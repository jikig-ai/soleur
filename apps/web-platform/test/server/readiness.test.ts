import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, rmSync, readdirSync, chmodSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import type { IncomingMessage, ServerResponse } from "http";

// Real filesystem, real temp dirs — the write+unlink probe and the
// populated-count are the whole point of this module, so mocking `fs` would
// make the tests vacuous (a bind-mount over overlay is exactly why the classic
// st_dev check is inert; only a REAL write proves "this host can serve"). Only
// observability is mocked, so the boot-mirror can assert call counts.
const mockReportSilentFallback = vi.fn();
vi.mock("../../server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) => mockReportSilentFallback(...args),
}));

const ORIGINAL_ENV = process.env;
let tmpRoot: string;

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  mockReportSilentFallback.mockReset();
  tmpRoot = mkdtempSync(join(tmpdir(), "readyz-test-"));
});

afterEach(() => {
  process.env = ORIGINAL_ENV;
  try {
    rmSync(tmpRoot, { recursive: true, force: true });
  } catch {
    /* best-effort */
  }
});

function populate(root: string, n: number): void {
  for (let i = 0; i < n; i++) {
    mkdirSync(join(root, `ws-uuid-${i}`));
  }
}

function mockReqRes(remoteAddress: string | undefined, host: string | undefined) {
  const req = {
    socket: { remoteAddress },
    headers: { host },
  } as unknown as IncomingMessage;
  const writeHead = vi.fn();
  const end = vi.fn();
  const res = { writeHead, end } as unknown as ServerResponse;
  return { req, res, writeHead, end };
}

describe("buildReadinessResponse", () => {
  it("writable + populated (count 5) → ready:true, both checks true", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 5);
    const { buildReadinessResponse } = await import("../../server/readiness");
    const r = buildReadinessResponse();
    expect(r.ready).toBe(true);
    expect(r.checks.workspaces_writable).toBe(true);
    expect(r.checks.workspaces_populated).toBe(true);
  });

  it("bare-host simulation: writable but empty → ready:false, workspaces_populated:false", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot; // exists + writable, zero workspace dirs
    const { buildReadinessResponse } = await import("../../server/readiness");
    const r = buildReadinessResponse();
    expect(r.ready).toBe(false);
    expect(r.checks.workspaces_writable).toBe(true);
    expect(r.checks.workspaces_populated).toBe(false);
  });

  it("read-only / unmounted: write-probe throws (ENOENT root) → ready:false, workspaces_writable:false", async () => {
    process.env.WORKSPACES_ROOT = join(tmpRoot, "does-not-exist"); // absent → writeFileSync ENOENT
    const { buildReadinessResponse } = await import("../../server/readiness");
    const r = buildReadinessResponse();
    expect(r.ready).toBe(false);
    expect(r.checks.workspaces_writable).toBe(false);
  });

  it("read-only mount (present dir, chmod 0555 → EACCES on write) → ready:false, workspaces_writable:false", async () => {
    // The module's raison d'être: a PRESENT but non-writable mount (the
    // silent-write-loss mode) — distinct from ENOENT (absent). root bypasses
    // Unix perm bits, so skip under root (CI containers sometimes run as root).
    if (process.getuid?.() === 0) return;
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 2); // populated, so ONLY the writable check can fail
    chmodSync(tmpRoot, 0o555); // read+execute, no write → writeFileSync EACCES
    const { buildReadinessResponse } = await import("../../server/readiness");
    const r = buildReadinessResponse();
    chmodSync(tmpRoot, 0o755); // restore so afterEach rmSync can clean up
    expect(r.ready).toBe(false);
    expect(r.checks.workspaces_writable).toBe(false);
    expect(r.checks.workspaces_populated).toBe(true); // proves ONLY writable failed
  });

  it("fail-closed: never throws even for a pathological root", async () => {
    process.env.WORKSPACES_ROOT = "\0invalid"; // NUL byte → fs throws internally
    const { buildReadinessResponse } = await import("../../server/readiness");
    expect(() => buildReadinessResponse()).not.toThrow();
    expect(buildReadinessResponse().ready).toBe(false);
  });

  it("WORKSPACES_ROOT resolved once and honored by BOTH signals (no split-brain, real count)", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 3);
    const { buildReadinessResponse } = await import("../../server/readiness");
    const r = buildReadinessResponse();
    // populated is derived from the REAL countWorkspaceDirsAt(root) — if the
    // count read a different (cached) root it would be 0 here.
    expect(r.checks.workspaces_populated).toBe(true);
    expect(r.checks.workspaces_writable).toBe(true);
    // the write probe cleaned up after itself — no lingering .readyz-probe file.
    expect(readdirSync(tmpRoot).some((n) => n.startsWith(".readyz-probe-"))).toBe(false);
  });

  it("lost+found at root with zero UUID dirs → workspaces_populated:false", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot;
    mkdirSync(join(tmpRoot, "lost+found"));
    const { buildReadinessResponse } = await import("../../server/readiness");
    const r = buildReadinessResponse();
    expect(r.checks.workspaces_populated).toBe(false);
  });
});

describe("handleReadyzRequest", () => {
  it("loopback peer + ready host → 200 with readiness body", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 2);
    const { handleReadyzRequest } = await import("../../server/readiness");
    const { req, res, writeHead, end } = mockReqRes("127.0.0.1", "127.0.0.1:3000");
    handleReadyzRequest(req, res);
    expect(writeHead).toHaveBeenCalledWith(200, expect.any(Object));
    expect(end).toHaveBeenCalledWith(expect.stringContaining('"ready":true'));
  });

  it("loopback peer + not-ready host (empty) → 503 with full checks body", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot; // writable but empty
    const { handleReadyzRequest } = await import("../../server/readiness");
    const { req, res, writeHead, end } = mockReqRes("::1", "localhost:3000");
    handleReadyzRequest(req, res);
    expect(writeHead).toHaveBeenCalledWith(503, expect.any(Object));
    // parse the body (not substring) and pin the 503 contract symmetrically
    const body = JSON.parse(end.mock.calls[0][0] as string);
    expect(body.ready).toBe(false);
    expect(body.checks.workspaces_populated).toBe(false);
    expect(body.checks.workspaces_writable).toBe(true);
  });

  it("IPv4-mapped-IPv6 loopback peer (::ffff:127.0.0.1) + ready host → 200", async () => {
    // exercises the isLoopbackPeer mapped-form branch; a regression removing it
    // would 403 this same-host caller and ship green without this case.
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 2);
    const { handleReadyzRequest } = await import("../../server/readiness");
    const { req, res, writeHead } = mockReqRes("::ffff:127.0.0.1", "127.0.0.1:3000");
    handleReadyzRequest(req, res);
    expect(writeHead).toHaveBeenCalledWith(200, expect.any(Object));
  });

  it("non-loopback peer → 403, no readiness body", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 5);
    const { handleReadyzRequest } = await import("../../server/readiness");
    const { req, res, writeHead, end } = mockReqRes("203.0.113.5", "127.0.0.1");
    handleReadyzRequest(req, res);
    expect(writeHead).toHaveBeenCalledWith(403, expect.any(Object));
    expect(end).toHaveBeenCalledWith(expect.stringContaining("forbidden"));
    // body must NOT leak topology signals
    expect(end).not.toHaveBeenCalledWith(expect.stringContaining("workspaces_"));
  });

  it("loopback peer but non-loopback Host header → 403 (secondary gate)", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 5);
    const { handleReadyzRequest } = await import("../../server/readiness");
    const { req, res, writeHead } = mockReqRes("127.0.0.1", "app.example.com");
    handleReadyzRequest(req, res);
    expect(writeHead).toHaveBeenCalledWith(403, expect.any(Object));
  });

  // Container-networking regression lock (readyz peer-gate 403 fix). A host-side
  // `curl 127.0.0.1:3000` reaches the bridge-networked prod container with the
  // docker bridge gateway (172.17.0.1) as the socket peer — NOT loopback — so it
  // MUST 403. The fix is to run the probe INSIDE the container (docker exec), where
  // the peer is a genuine 127.0.0.1; it does NOT widen isLoopbackPeer to the
  // gateway. These cases fail if a future editor "simplifies" by accepting the
  // bridge gateway, which under docker userland-proxy is indistinguishable from
  // off-host traffic and would collapse the boundary to the attacker-set Host header.
  it("docker bridge gateway peer (172.17.0.1) + loopback Host → 403 (do NOT widen the peer gate)", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 5);
    const { handleReadyzRequest } = await import("../../server/readiness");
    const { req, res, writeHead, end } = mockReqRes("172.17.0.1", "127.0.0.1:3000");
    handleReadyzRequest(req, res);
    expect(writeHead).toHaveBeenCalledWith(403, expect.any(Object));
    expect(end).not.toHaveBeenCalledWith(expect.stringContaining("workspaces_"));
  });

  it("IPv4-mapped bridge gateway peer (::ffff:172.17.0.1) + loopback Host → 403", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 5);
    const { handleReadyzRequest } = await import("../../server/readiness");
    const { req, res, writeHead } = mockReqRes("::ffff:172.17.0.1", "127.0.0.1:3000");
    handleReadyzRequest(req, res);
    expect(writeHead).toHaveBeenCalledWith(403, expect.any(Object));
  });

  it("route try/catch → 503 (never propagates a throw to the crash handlers)", async () => {
    const { handleReadyzRequest } = await import("../../server/readiness");
    const { req, res, writeHead, end } = mockReqRes("127.0.0.1", "127.0.0.1");
    // Inject a builder that throws — proves the handler's try/catch converts it
    // to a 503 rather than an unhandled rejection (→ process.exit(1) restart).
    handleReadyzRequest(req, res, () => {
      throw new Error("boom");
    });
    expect(writeHead).toHaveBeenCalledWith(503, expect.any(Object));
    expect(end).toHaveBeenCalledWith(expect.stringContaining('"ready":false'));
  });
});

describe("verifyWorkspacesMountOnce", () => {
  it("mirrors ONE reportSilentFallback on a not-ready boot", async () => {
    process.env.WORKSPACES_ROOT = join(tmpRoot, "absent"); // not ready
    vi.resetModules();
    const { verifyWorkspacesMountOnce } = await import("../../server/readiness");
    verifyWorkspacesMountOnce();
    verifyWorkspacesMountOnce(); // latched — must not fire twice
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ feature: "workspaces-mount", op: "boot-readiness" }),
    );
  });

  it("does NOT report on a ready boot", async () => {
    process.env.WORKSPACES_ROOT = tmpRoot;
    populate(tmpRoot, 1);
    vi.resetModules();
    const { verifyWorkspacesMountOnce } = await import("../../server/readiness");
    verifyWorkspacesMountOnce();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });
});
