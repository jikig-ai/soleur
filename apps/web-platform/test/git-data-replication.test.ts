// Tests for the git-data replication transport (server/git-data-replication.ts,
// #5817 PR B part 2 / ADR-068). Verifies: the lease-gen + worktree-id push-options
// ride the git-data push; the gated-off path issues NO provision/push; a push
// failure (e.g. a fence reject) FAILS LOUD (mirrors to Sentry) and re-throws; and
// an unsafe workspace_id is rejected before any SSH.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const gitPush = vi.fn().mockResolvedValue(Buffer.from(""));
const sshProvision = vi.fn().mockResolvedValue(Buffer.from(""));
const reportSilentFallback = vi.fn();
const execFileSyncMock = vi.fn((..._args: unknown[]) => Buffer.from("")); // local `git remote` calls
// D2 write sentinel (Sub-PR 3.C): replicateToGitData now authorizes membership via
// is_workspace_member through a fresh tenant client BEFORE the push. Default the RPC
// to member=true so these WRITE-transport tests exercise the push; the cross-tenant
// DENY path is covered in git-data-client.test.ts.
const rpcMock = vi.fn(async () => ({ data: true, error: null }));

vi.mock("../server/git-auth", () => ({
  gitWithPrivateKeyAuth: (...args: unknown[]) => gitPush(...args),
  sshWithPrivateKeyAuth: (...args: unknown[]) => sshProvision(...args),
}));
// Partial mock: keep warnSilentFallback + hashUserId REAL — git-data-replication
// now transitively imports git-data-client, which uses them; a wholesale factory
// would drop those exports and crash the sibling at call time.
vi.mock("../server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/observability")>()),
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: rpcMock })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("child_process")>()),
  execFileSync: (...args: unknown[]) => execFileSyncMock(...args),
}));

import {
  replicateToGitData,
  removeGitDataRepo,
  assertSafeWorkspaceId,
  gitDataRemoteUrl,
} from "../server/git-data-replication";

const WS = "ws-uuid-123";
// Per-user worktree id (ADR-068 D0). A UUID in prod; any safe token here.
const WT = "55555555-5555-5555-5555-555555555555";
const USER = "44444444-4444-4444-4444-444444444444";

beforeEach(() => {
  gitPush.mockClear().mockResolvedValue(Buffer.from(""));
  sshProvision.mockClear().mockResolvedValue(Buffer.from(""));
  reportSilentFallback.mockClear();
  execFileSyncMock.mockClear().mockReturnValue(Buffer.from(""));
  rpcMock.mockClear().mockResolvedValue({ data: true, error: null });
  vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", "transport-key");
  vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "provision-key");
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("gitDataRemoteUrl / assertSafeWorkspaceId", () => {
  it("composes an ssh:// URL under the reconciled /repositories path", () => {
    expect(gitDataRemoteUrl(WS)).toBe(`ssh://git@10.0.1.20/repositories/${WS}.git`);
  });

  it("rejects path-traversal / unsafe workspace ids (CWE-22)", () => {
    for (const bad of ["..", ".", "a/b", "a b", "a;rm", ""]) {
      expect(() => assertSafeWorkspaceId(bad)).toThrow();
    }
  });
});

describe("replicateToGitData — gated off (GIT_DATA_STORE_ENABLED unset)", () => {
  it("issues NO provision, no remote config, no push", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "");
    await replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 4 , userId: USER });
    expect(sshProvision).not.toHaveBeenCalled();
    expect(gitPush).not.toHaveBeenCalled();
    expect(execFileSyncMock).not.toHaveBeenCalled();
  });
});

describe("replicateToGitData — gated on", () => {
  beforeEach(() => vi.stubEnv("GIT_DATA_STORE_ENABLED", "true"));

  it("pushes to the PER-USER namespaced refspec (D0-ref) carrying lease-gen + per-user worktree-id", async () => {
    await replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 7 , userId: USER });

    // Provision ran first (idempotent init before the first push).
    expect(sshProvision).toHaveBeenCalledTimes(1);
    expect(sshProvision.mock.calls[0][1]).toBe(WS); // opaque remote arg = workspace_id

    expect(gitPush).toHaveBeenCalledTimes(1);
    const pushArgs = gitPush.mock.calls[0][0] as string[];
    expect(pushArgs).toContain("push");
    expect(pushArgs).toContain("git-data");
    // Fence push-options ride this push — worktree-id is now PER-USER, not "primary".
    expect(pushArgs).toContain("--push-option=lease-gen=7");
    expect(pushArgs).toContain(`--push-option=worktree-id=${WT}`);
    expect(pushArgs).not.toContain("--push-option=worktree-id=primary");
    // Heads + tags land under refs/soleur/worktrees/<worktreeId>/ — this user is
    // the SOLE writer of its namespace, so --force stays safe under a 2nd writer.
    expect(pushArgs).toContain(`refs/heads/*:refs/soleur/worktrees/${WT}/heads/*`);
    expect(pushArgs).toContain(`refs/tags/*:refs/soleur/worktrees/${WT}/tags/*`);
    // D0-ref NEGATIVE: the clobbering shared-ref refspec MUST be gone — under a
    // 2nd writer `refs/heads/*:refs/heads/*` --force silently overwrites a peer's
    // commits (the whole reason 3.B must land before the flag flip).
    expect(pushArgs).not.toContain("refs/heads/*:refs/heads/*");
    // The push uses the TRANSPORT key, not the provision key.
    expect(gitPush.mock.calls[0][1]).toBe("transport-key");
  });

  it("rejects an unsafe worktree_id BEFORE any provision/push (CWE-22)", async () => {
    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: "../evil", leaseGeneration: 1 , userId: USER }),
    ).rejects.toThrow(/worktree.?id/i);
    expect(sshProvision).not.toHaveBeenCalled();
    expect(gitPush).not.toHaveBeenCalled();
  });

  it("FAILS LOUD on a push failure (fence reject): mirrors to Sentry + re-throws", async () => {
    gitPush.mockRejectedValueOnce(
      new Error("remote: git-data fence: stale lease generation 3 < stored max 5 — rejected"),
    );

    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 3 , userId: USER }),
    ).rejects.toThrow(/stale lease generation/);

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const opts = reportSilentFallback.mock.calls[0][1] as { feature: string; op: string };
    expect(opts.feature).toBe("worktree_lease");
    expect(opts.op).toBe("git_data_replication_push");
  });

  it("rejects an unsafe workspace_id BEFORE any provision/push", async () => {
    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: "../evil", worktreeId: WT, leaseGeneration: 1 , userId: USER }),
    ).rejects.toThrow();
    expect(sshProvision).not.toHaveBeenCalled();
    expect(gitPush).not.toHaveBeenCalled();
  });
});

// Art. 17 app-side erasure (Sub-PR 3.D, CLO DL-1 / Kieran P0-1 / AC9). The 3.A
// cloud-init `git-data-remove.sh` forced command tears down the per-workspace bare
// repo; the app must call it over the private net with the dedicated REMOVE key —
// distinct authority from provision/transport. Mirrors provisionGitDataRepo shape.
describe("removeGitDataRepo — Art. 17 erasure of the git-data bare repo (AC9)", () => {
  beforeEach(() => vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "remove-key"));

  it("flag OFF but REMOVE key present (rollback/dual-existence window): STILL erases (Art. 17, not gated on the live flag)", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", ""); // flag off (post-rollback)
    await removeGitDataRepo(WS);
    // A repo provisioned during a flag-on window must still be erasable after a
    // rollback flips the flag off — erasure keys on the REMOVE key, not the flag.
    expect(sshProvision).toHaveBeenCalledTimes(1);
    const [host, remoteCmd, key] = sshProvision.mock.calls[0] as [string, string, string, unknown];
    expect(host).toBe("10.0.1.20");
    expect(remoteCmd).toBe(WS);
    expect(key).toBe("remove-key");
  });

  it("flag ON: dials the git-data host with the REMOVE key (not provision/transport) + the workspaceId as SSH_ORIGINAL_COMMAND", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    await removeGitDataRepo(WS);
    expect(sshProvision).toHaveBeenCalledTimes(1);
    const [host, remoteCmd, key] = sshProvision.mock.calls[0] as [string, string, string, unknown];
    expect(host).toBe("10.0.1.20");
    expect(remoteCmd).toBe(WS); // opaque workspace_id, not a shell string (CWE-22 host-side)
    expect(key).toBe("remove-key"); // the dedicated GIT_REMOVE_SSH_PRIVATE_KEY authority
  });

  it("no REMOVE key configured (env never had git-data): skips silently — no ssh, no throw (avoids Sentry noise)", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "");
    await expect(removeGitDataRepo(WS)).resolves.toBeUndefined();
    expect(sshProvision).not.toHaveBeenCalled();
  });

  it("rejects an unsafe workspace_id BEFORE any ssh (CWE-22)", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    await expect(removeGitDataRepo("../evil")).rejects.toThrow();
    expect(sshProvision).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------------
// (#6982, W6 / AC18) The client-side concurrency limiter.
//
// The limiter reads its bounds from env AT MODULE LOAD, so these tests re-import the
// module under `vi.resetModules()` with small bounds. Importing once at the top of the
// file would pin the production defaults and make the assertions untestable.
//
// The property under test is a GATE, so a final-state assertion is not enough: a test
// that only checked "all N+1 eventually settle" passes identically with the semaphore
// DELETED. Each case therefore asserts an INTERMEDIATE state — the live in-flight count
// while calls are held open — which is the thing only the gate can produce.
// ---------------------------------------------------------------------------------
describe("replicateToGitData — concurrency limiter (#6982 W6)", () => {
  async function loadWithLimits(max: string, timeoutMs: string) {
    vi.resetModules();
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", "transport-key");
    vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "provision-key");
    vi.stubEnv("GIT_DATA_MAX_CONCURRENT", max);
    vi.stubEnv("GIT_DATA_QUEUE_TIMEOUT_MS", timeoutMs);
    return await import("../server/git-data-replication");
  }

  const call = (mod: typeof import("../server/git-data-replication"), id: string) =>
    mod.replicateToGitData({
      workspacePath: `/tmp/${id}`,
      workspaceId: id,
      worktreeId: "wt-1",
      leaseGeneration: 1,
      userId: "user-1",
    });

  it("holds concurrent replications at or below the limit", async () => {
    const mod = await loadWithLimits("2", "10000");

    // Block the push so slots stay held while we observe the counter. Resolving these is
    // what lets the queued caller through.
    let releasePush: () => void = () => {};
    const pushGate = new Promise<Buffer>((res) => {
      releasePush = () => res(Buffer.from(""));
    });
    gitPush.mockImplementation(() => pushGate);

    const a = call(mod, "ws-a");
    const b = call(mod, "ws-b");
    const c = call(mod, "ws-c"); // third — must WAIT, not run

    // Let the two admitted calls reach their (blocked) push.
    await vi.waitFor(() => expect(mod.__gitDataInFlightForTest()).toBe(2));

    // THE INTERMEDIATE ASSERTION. Without the semaphore this reads 3.
    expect(mod.__gitDataInFlightForTest()).toBe(2);

    releasePush();
    await Promise.all([a, b, c]);
    expect(mod.__gitDataInFlightForTest()).toBe(0);
    gitPush.mockResolvedValue(Buffer.from(""));
  });

  it("SHEDS on queue timeout without blocking, and reports the shed", async () => {
    // Zero-length queue window: the third caller gives up immediately rather than the
    // test waiting out a real timeout.
    const mod = await loadWithLimits("1", "0");

    let releasePush: () => void = () => {};
    const pushGate = new Promise<Buffer>((res) => {
      releasePush = () => res(Buffer.from(""));
    });
    gitPush.mockImplementation(() => pushGate);
    reportSilentFallback.mockClear();

    const held = call(mod, "ws-held");
    await vi.waitFor(() => expect(mod.__gitDataInFlightForTest()).toBe(1));

    // The shed caller must RESOLVE (not hang, not throw): git-data is an overlay and
    // session end must never block on it.
    await expect(call(mod, "ws-shed")).resolves.toBeUndefined();

    // ...and the shed must be OBSERVABLE. A silent shed is indistinguishable from a bug.
    expect(reportSilentFallback).toHaveBeenCalled();
    const opts = reportSilentFallback.mock.calls.at(-1)?.[1] as {
      feature?: string;
      op?: string;
    };
    expect(opts?.feature).toBe("git_data_replication");
    expect(opts?.op).toBe("queue_shed");

    // The shed must NOT have consumed a slot.
    expect(mod.__gitDataInFlightForTest()).toBe(1);

    releasePush();
    await held;
    gitPush.mockResolvedValue(Buffer.from(""));
  });

  it("releases the slot when the push THROWS (no leak)", async () => {
    // The leak this guards: replicateToGitData re-throws on a fence reject, so a slot
    // released only at the end of `try` would shrink the pool by one per failure until
    // replication silently stopped.
    const mod = await loadWithLimits("1", "0");
    gitPush.mockRejectedValueOnce(new Error("fence reject: stale lease-gen"));

    await expect(call(mod, "ws-boom")).rejects.toThrow(/fence reject/);
    expect(mod.__gitDataInFlightForTest()).toBe(0);

    // Proof the pool still works afterwards — the assertion above would also hold if the
    // counter were merely reset rather than properly released.
    gitPush.mockResolvedValue(Buffer.from(""));
    await expect(call(mod, "ws-after")).resolves.toBeUndefined();
  });
});

// #6982 review P3 — the replication logger must not ship a BARE workspace UUID.
//
// workspace_id === auth.users.id (mig-053 N2), so a bare workspaceId in a log line is a
// raw user identifier on the app log sink — and Vector's `pii_scrub_string` does NOT
// scrub a bare UUID in free text. That is the same reasoning that put a UUID redactor in
// the git-data host emitter in this very PR; the app side was the outlier. The sibling
// module git-data-client.ts already pseudonymises via hashUserId(workspaceId).
describe("replicateToGitData — workspace id is pseudonymised in logs (#6982)", () => {
  const REAL_WS = "3f2504e0-4f89-11d3-9a0c-0305e82c3301";
  const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

  it("logs a hash, never the raw workspace id, on a successful push", async () => {
    vi.resetModules();
    const logCalls: unknown[][] = [];
    vi.doMock("../server/logger", async (importOriginal) => ({
      ...(await importOriginal<typeof import("../server/logger")>()),
      createChildLogger: () => ({
        info: (...a: unknown[]) => logCalls.push(a),
        warn: (...a: unknown[]) => logCalls.push(a),
        error: (...a: unknown[]) => logCalls.push(a),
        debug: (...a: unknown[]) => logCalls.push(a),
      }),
    }));
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    const mod = await import("../server/git-data-replication");
    await mod.replicateToGitData({
      workspacePath: "/tmp/ws",
      workspaceId: REAL_WS,
      worktreeId: WT,
      leaseGeneration: 1,
      userId: USER,
    });

    expect(logCalls.length).toBeGreaterThan(0);
    const serialized = JSON.stringify(logCalls);
    // The raw id must not be present in ANY form.
    expect(serialized).not.toContain(REAL_WS);
    // ...and not merely absent because nothing was logged about the workspace: a
    // pseudonymous handle must be there instead.
    expect(serialized).toMatch(/workspaceIdHash/);
    // No OTHER bare UUID may ride either (worktreeId is one).
    const structured = logCalls.map((c) => c[0]);
    for (const obj of structured) {
      for (const v of Object.values((obj ?? {}) as Record<string, unknown>)) {
        if (typeof v === "string" && UUID_RE.test(v)) {
          throw new Error(`bare UUID reached the log sink: ${String(v)}`);
        }
      }
    }
    vi.doUnmock("../server/logger");
  });
});
