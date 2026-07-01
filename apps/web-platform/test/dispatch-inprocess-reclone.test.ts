import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtemp, rm, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readFileSync } from "node:fs";

// #5733 D0 — consume the EXISTING cc-dispatcher:1987 in-process clone outcome
// (previously DISCARDED) loudly + F4-safely. Seams under test:
//   1. `consumeDispatchCloneOutcome` — the F4-gated CAS status write + honest
//      `"block"` verdict (no second clone site; no service-role read).
//   2. `reportRepoCloneFailed` — the distinct, SANITIZED, pseudonymized
//      `repo_clone_failed` emit (no token, no absolute path/repo-url, no raw
//      workspace id). The ensure-workspace-repo wiring is asserted in
//      test/ensure-workspace-repo.test.ts.

const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", async (orig) => {
  const actual = (await orig()) as Record<string, unknown>;
  return { ...actual, reportSilentFallback: mockReportSilentFallback };
});

describe("consumeDispatchCloneOutcome (#5733 D0 — F4 + CAS verdict)", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "d0-consume-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  const USER = "22222222-2222-2222-2222-222222222222";
  const TEAM_WS = "11111111-1111-1111-1111-111111111111";

  async function absentWs(name: string): Promise<string> {
    const p = join(dir, name);
    await mkdir(p, { recursive: true }); // no `.git`
    return p;
  }
  async function withGitWs(name: string): Promise<string> {
    const p = join(dir, name);
    await mkdir(join(p, ".git"), { recursive: true });
    return p;
  }

  async function load() {
    return await import("@/server/cc-dispatch-clone-consume");
  }

  it("AC0a: outcome `ok` → `proceed`, no status write", async () => {
    const { consumeDispatchCloneOutcome } = await load();
    const setRepoStatus = vi.fn(async () => {});
    const ws = await absentWs("ok");
    const verdict = await consumeDispatchCloneOutcome(
      { outcome: "ok", userId: USER, activeWorkspaceId: USER, workspacePath: ws },
      { setRepoStatus },
    );
    expect(verdict).toBe("proceed");
    expect(setRepoStatus).not.toHaveBeenCalled();
  });

  it("AC0a/AC0c: outcome `failed` + `.git` absent on SOLO/OWNER (ws===user) → block + setRepoStatus(error)", async () => {
    const { consumeDispatchCloneOutcome } = await load();
    const setRepoStatus = vi.fn(async () => {});
    const ws = await absentWs("solo");
    const verdict = await consumeDispatchCloneOutcome(
      { outcome: "failed", userId: USER, activeWorkspaceId: USER, workspacePath: ws },
      { setRepoStatus },
    );
    expect(verdict).toBe("block");
    expect(setRepoStatus).toHaveBeenCalledTimes(1);
    expect(setRepoStatus).toHaveBeenCalledWith("error", expect.any(String));
  });

  it("AC0c: outcome `failed` + `.git` absent on TEAM/MEMBER (ws!==user) → block + EMIT-ONLY, NO setRepoStatus", async () => {
    const { consumeDispatchCloneOutcome } = await load();
    const setRepoStatus = vi.fn(async () => {});
    const ws = await absentWs("team");
    const verdict = await consumeDispatchCloneOutcome(
      { outcome: "failed", userId: USER, activeWorkspaceId: TEAM_WS, workspacePath: ws },
      { setRepoStatus },
    );
    expect(verdict).toBe("block");
    expect(setRepoStatus).not.toHaveBeenCalled();
  });

  it("AC0d: outcome `failed` but `.git` PRESENT after the attempt (concurrent winner) → proceed, NO setRepoStatus even on solo/owner (CAS)", async () => {
    const { consumeDispatchCloneOutcome } = await load();
    const setRepoStatus = vi.fn(async () => {});
    const ws = await withGitWs("winner");
    const verdict = await consumeDispatchCloneOutcome(
      { outcome: "failed", userId: USER, activeWorkspaceId: USER, workspacePath: ws },
      { setRepoStatus },
    );
    expect(verdict).toBe("proceed");
    expect(setRepoStatus).not.toHaveBeenCalled();
  });

  it("AC0b: the status-write reason is sanitized — no token, no absolute path", async () => {
    const { consumeDispatchCloneOutcome } = await load();
    let written: string | undefined;
    const setRepoStatus = vi.fn(async (_s: "error", reason: string) => {
      written = reason;
    });
    const ws = await absentWs("sanitize");
    await consumeDispatchCloneOutcome(
      { outcome: "failed", userId: USER, activeWorkspaceId: USER, workspacePath: ws },
      { setRepoStatus },
    );
    expect(written).toBeDefined();
    expect(written).not.toMatch(/ghs_/); // no installation token
    expect(written).not.toMatch(/\/workspaces\//); // no absolute workspace path
  });

  it("AC0e: cc-dispatcher consumes the EXISTING clone — no SECOND ensureWorkspaceRepoCloned call + no service-role read at the D0 site", () => {
    const src = readFileSync(
      join(__dirname, "..", "server", "cc-dispatcher.ts"),
      "utf8",
    );
    // Exactly one dispatch-time clone call (the existing :1987 site, now captured).
    const cloneCalls = src.match(/await ensureWorkspaceRepoCloned\(/g) ?? [];
    expect(cloneCalls.length).toBe(1);
    // The D0 consume must NOT introduce a service-role client into cc-dispatcher.
    expect(src).not.toMatch(/getServiceRoleClient|service_role|createServiceClient/);
  });
});

describe("reportRepoCloneFailed (#5733 D0 — sanitized + pseudonymized emit)", () => {
  beforeEach(() => mockReportSilentFallback.mockReset());

  const USER = "22222222-2222-2222-2222-222222222222";
  const SOLO_WS = USER; // solo: workspace_id == user_id
  const tokenPart = "ghs_" + "A".repeat(36);
  // The raw reason carries BOTH the repo URL and the absolute /workspaces/<uuid>
  // path (PII-equivalent for a solo workspace) AND a token-shaped secret — the
  // exact shapes the reporter's sanitizer must strip from the value that reaches
  // captureException.
  const rawReason =
    `Command failed: git clone --depth 1 -- https://github.com/acme/widgets /workspaces/${SOLO_WS}/.ensure-repo-tmp-x\n` +
    `remote: token ${tokenPart} rejected\nfatal: could not read Username for 'https://github.com'`;

  async function reporter() {
    const mod = await import("@/server/repo-resolver-divergence");
    mod._resetResolverDivergenceDedupeForTests();
    return mod.reportRepoCloneFailed;
  }

  it("AC0a/AC0b: emits a distinct repo_clone_failed event; the sanitized reason has NO token and NO absolute /workspaces path or repo URL", async () => {
    const reportRepoCloneFailed = await reporter();
    reportRepoCloneFailed({ userId: USER, activeWorkspaceId: SOLO_WS, reason: rawReason });

    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = mockReportSilentFallback.mock.calls[0];
    // Distinct issue group — its own Error message + feature/op.
    expect((err as Error).message).toBe("repo_clone_failed");
    expect(opts.feature).toBe("repo-clone-failed");
    expect(opts.op).toBe("repo-clone-failed");

    const reason: string = opts.extra.reason;
    expect(reason).not.toContain(tokenPart); // token stripped
    expect(reason).not.toMatch(/\/workspaces\//); // absolute path stripped
    expect(reason).not.toContain("github.com/acme/widgets"); // repo url stripped
  });

  it("AC0b: extra excludes repoUrl/installationId and pre-hashes the workspace id (never the raw id/path)", async () => {
    const reportRepoCloneFailed = await reporter();
    reportRepoCloneFailed({ userId: USER, activeWorkspaceId: SOLO_WS, reason: rawReason });
    const [, opts] = mockReportSilentFallback.mock.calls[0];
    expect(opts.extra).not.toHaveProperty("repoUrl");
    expect(opts.extra).not.toHaveProperty("installationId");
    // activeWorkspaceIdHash is a hash, NOT the raw id (== raw userId for a solo ws).
    expect(opts.extra.activeWorkspaceIdHash).toBeDefined();
    expect(opts.extra.activeWorkspaceIdHash).not.toBe(SOLO_WS);
    // userId stays as the `userId` key → renamed to userIdHash at the emit boundary.
    expect(opts.extra.userId).toBe(USER);
  });

  it("dedupes by (userId, workspaceId) — a recurring failure emits once per process", async () => {
    const reportRepoCloneFailed = await reporter();
    reportRepoCloneFailed({ userId: USER, activeWorkspaceId: SOLO_WS, reason: rawReason });
    reportRepoCloneFailed({ userId: USER, activeWorkspaceId: SOLO_WS, reason: rawReason });
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });
});
