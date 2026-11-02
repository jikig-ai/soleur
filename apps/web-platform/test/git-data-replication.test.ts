// Tests for the git-data replication transport (server/git-data-replication.ts,
// #5817 PR B part 2 / ADR-068). Verifies: the lease-gen + worktree-id push-options
// ride the git-data push; the gated-off path issues NO provision/push; a push
// failure (e.g. a fence reject) FAILS LOUD (mirrors to Sentry) and re-throws; and
// an unsafe workspace_id is rejected before any SSH.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const TEST_PIN = makeEd25519Pin();

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
  gitDataPushRefspecs,
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
  // #7226: a valid generated pin, so the store-enabled paths resolve one (never a real key).
  vi.stubEnv("GIT_DATA_SSH_HOST_KEY", TEST_PIN);
});

afterEach(() => {
  vi.unstubAllEnvs();
});

// A fake local git for the rescue listing / delete, backed by the execFileSync mock. It honours what a
// real `git -C <cwd> for-each-ref <pattern>` would: a listing that does not carry `-C /tmp/ws` AND the
// rescue pattern returns nothing, so dropping either from production makes the rows go red.
const SHA_A = "0123456789abcdef0123456789abcdef01234567";
const SHA_B = "fedcba9876543210fedcba9876543210fedcba98";
const RESCUE_PATTERN = "refs/heads/soleur-store-tip-*";
function fakeLocalGit(opts: {
  refs?: Array<[sha: string, ref: string]>;
  listingThrows?: Error;
  failDelete?: boolean;
}) {
  execFileSyncMock.mockImplementation((...a: unknown[]) => {
    const args = a[1] as string[];
    if (args[2] === "for-each-ref") {
      if (opts.listingThrows) throw opts.listingThrows;
      const honoured = args[0] === "-C" && args[1] === "/tmp/ws" && args.includes(RESCUE_PATTERN);
      return Buffer.from(honoured ? (opts.refs ?? []).map(([sha, ref]) => `${sha} ${ref}\n`).join("") : "");
    }
    if (args[2] === "update-ref" && opts.failDelete) throw new Error("fatal: cannot lock ref");
    return Buffer.from("");
  });
}
const listingCalls = () => execFileSyncMock.mock.calls.filter((c) => (c[1] as string[])[2] === "for-each-ref");
const deleteCalls = () => execFileSyncMock.mock.calls.filter((c) => (c[1] as string[])[2] === "update-ref");

describe("gitDataRemoteUrl / assertSafeWorkspaceId", () => {
  it("composes an absolute ssh:// URL under the git-data store bare-repo root", () => {
    expect(gitDataRemoteUrl(WS)).toBe(`ssh://git@10.0.1.20/mnt/git-data/repositories/${WS}.git`);
  });

  it("rejects path-traversal / unsafe workspace ids (CWE-22)", () => {
    for (const bad of ["..", ".", "a/b", "a b", "a;rm", "", "a..b", "..a", "a..", "a."]) {
      expect(() => assertSafeWorkspaceId(bad)).toThrow();
    }
  });

  it("still accepts single-dot ids (positive control for the '..' rule)", () => {
    for (const ok of ["a.b", ".a", "ws-uuid-123", "11111111-1111-4111-8111-111111111111"]) {
      expect(() => assertSafeWorkspaceId(ok)).not.toThrow();
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
    // CTO F20: the main push is PER-REF, not atomic. Under --atomic one stale store head plus a later
    // local ref that refname-conflicts with it (store `heads/fix/x`, local `fix`) rejected every ref of
    // every later push forever; rescue-first already protects the old tip, so atomicity here is
    // redundant. (--atomic lives on the rescue step only: see the two-step rows below.)
    expect(pushArgs).not.toContain("--atomic");
    expect(pushArgs.indexOf("--force")).toBeLessThan(pushArgs.indexOf("git-data"));
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

  // CTO T1b (amends F12), F19, F20, F21: rescue-first two-step push. `--atomic` only protects a ref
  // REJECTED inside the ref transaction; in the shallow `remote failure` class (measured, file:// store)
  // `main` was still forced with the rescue ref left out. Pushing the rescue ref ALONE first (atomic),
  // and throwing if that fails before `main` is touched, is what keeps the old store tip referenced.
  // The main push is per-ref (F20). After step 1 is confirmed the pushed local rescue branches are
  // deleted best-effort (F21).
  describe("rescue-first two-step push (T1b, F20, F21)", () => {
    const RESCUE_SPEC = `refs/heads/soleur-store-tip-*:refs/soleur/worktrees/${WT}/heads/soleur-store-tip-*`;
    const MAIN_SPEC = `refs/heads/*:refs/soleur/worktrees/${WT}/heads/*`;
    const RESCUE_A = "refs/heads/soleur-store-tip-0123456789ab";
    const RESCUE_B = "refs/heads/soleur-store-tip-fedcba987654";
    const hasRescueBranch = () => fakeLocalGit({ refs: [[SHA_A, RESCUE_A]] });
    const argsOf = (i: number) => gitPush.mock.calls[i][0] as string[];
    const go = () =>
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 7, userId: USER });

    it("the production refspec builder yields exactly the strings these rows pin (parity)", () => {
      expect(gitDataPushRefspecs(WT)).toEqual({
        heads: MAIN_SPEC,
        tags: `refs/tags/*:refs/soleur/worktrees/${WT}/tags/*`,
        rescue: RESCUE_SPEC,
      });
    });

    it("with a local rescue branch: the rescue-only push comes FIRST, then the main push; same generation and options", async () => {
      hasRescueBranch();
      await go();

      expect(gitPush).toHaveBeenCalledTimes(2);
      // step 1 keeps --atomic (F12/F20)
      expect(argsOf(0)).toEqual([
        "push", "--force", "--atomic", "git-data", RESCUE_SPEC,
        "--push-option=lease-gen=7", `--push-option=worktree-id=${WT}`,
      ]);
      // step 2 is per-ref: NO --atomic (F20)
      expect(argsOf(1)).not.toContain("--atomic");
      expect(argsOf(1)).toContain(MAIN_SPEC);
      expect(argsOf(1)).toContain("--push-option=lease-gen=7");
      expect(argsOf(1)).not.toContain(RESCUE_SPEC);
      // both steps use the transport key in the workspace
      for (const c of gitPush.mock.calls) {
        expect(c[1]).toBe("transport-key");
        expect(c[3]).toMatchObject({ cwd: "/tmp/ws" });
      }
    });

    it("the rescue listing is `for-each-ref` over the rescue pattern in the workspace: -C <cwd>, full-sha format, no --count, 5 s timeout", async () => {
      hasRescueBranch();
      await go();
      const [lookup] = listingCalls();
      expect(lookup[1]).toEqual(["-C", "/tmp/ws", "for-each-ref", "--format=%(objectname) %(refname)", "refs/heads/soleur-store-tip-*"]);
      expect(lookup[2]).toMatchObject({ cwd: "/tmp/ws", timeout: 5000 });
    });

    it("with NO local rescue branch: exactly one push (the main push), and the listing was issued before it", async () => {
      await go();
      expect(listingCalls()).toHaveLength(1);
      expect(gitPush).toHaveBeenCalledTimes(1);
      expect(argsOf(0)).toContain(MAIN_SPEC);
      expect(argsOf(0)).not.toContain(RESCUE_SPEC);
      expect(argsOf(0)).not.toContain("--atomic");
      expect(deleteCalls()).toHaveLength(0);
      expect(execFileSyncMock.mock.invocationCallOrder[execFileSyncMock.mock.calls.indexOf(listingCalls()[0])]).toBeLessThan(
        gitPush.mock.invocationCallOrder[0],
      );
    });

    it("ordering by invocation: listing, then the rescue push, then the local delete; the main push comes last", async () => {
      hasRescueBranch();
      await go();
      const orderOf = (call: unknown[]) => execFileSyncMock.mock.invocationCallOrder[execFileSyncMock.mock.calls.indexOf(call)];
      const listing = orderOf(listingCalls()[0]);
      const del = orderOf(deleteCalls()[0]);
      const [rescuePush, mainPush] = gitPush.mock.invocationCallOrder;
      expect(listing).toBeLessThan(rescuePush);
      expect(rescuePush).toBeLessThan(del); // never deleted before the push is confirmed
      expect(del).toBeLessThan(mainPush);
    });

    it("rescue push fails (non-transient): rejects, the main push is NEVER attempted, nothing is deleted, reported once", async () => {
      hasRescueBranch();
      gitPush.mockRejectedValueOnce(
        Object.assign(new Error("Command failed: git push"), { stderr: "remote: git-data fence: stale lease generation 3 < stored max 5" }),
      );
      await expect(
        replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 3, userId: USER }),
      ).rejects.toThrow(/Command failed: git push/);
      expect(gitPush).toHaveBeenCalledTimes(1);
      expect(argsOf(0)).toContain(RESCUE_SPEC);
      expect(deleteCalls()).toHaveLength(0); // F21: a failed step 1 keeps the local branch
      expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    });

    it("a transient failure on EACH step retries that step once (4 pushes, order rescue, rescue, main, main)", async () => {
      hasRescueBranch();
      const transientErr = () => Object.assign(new Error("Command failed: git push"), { stderr: "error: remote failure" });
      gitPush
        .mockRejectedValueOnce(transientErr())
        .mockResolvedValueOnce(Buffer.from(""))
        .mockRejectedValueOnce(transientErr())
        .mockResolvedValueOnce(Buffer.from(""));
      await expect(go()).resolves.toEqual({ status: "replicated" });
      expect(gitPush).toHaveBeenCalledTimes(4);
      expect([0, 1, 2, 3].map((i) => argsOf(i).includes(RESCUE_SPEC))).toEqual([true, true, false, false]);
      expect([0, 1, 2, 3].map((i) => argsOf(i).includes("--atomic"))).toEqual([true, true, false, false]);
      expect(deleteCalls()).toHaveLength(1); // deleted once, after the confirmed (retried) step 1
      expect(reportSilentFallback).not.toHaveBeenCalled();
    });

    it("the rescue step retries only ONCE: two transient failures there throw before main is touched, nothing deleted", async () => {
      hasRescueBranch();
      gitPush.mockRejectedValue(Object.assign(new Error("Command failed: git push"), { stderr: "failed to report status" }));
      await expect(go()).rejects.toThrow(/git push/);
      expect(gitPush).toHaveBeenCalledTimes(2);
      for (let i = 0; i < 2; i++) {
        expect(argsOf(i)).toContain(RESCUE_SPEC);
        expect(argsOf(i)).toContain("--atomic");
      }
      expect(deleteCalls()).toHaveLength(0);
      expect(reportSilentFallback).toHaveBeenCalledTimes(1);
      gitPush.mockResolvedValue(Buffer.from(""));
    });

    it("a listing that returns nothing printable (whitespace) is treated as no rescue branch", async () => {
      execFileSyncMock.mockImplementation((...a: unknown[]) =>
        (a[1] as string[]).includes("for-each-ref") ? Buffer.from("  \n") : Buffer.from(""),
      );
      await go();
      expect(gitPush).toHaveBeenCalledTimes(1);
    });

    it("a listing failure is NOT swallowed: replicate rejects, no push is attempted, reported once", async () => {
      fakeLocalGit({ listingThrows: new Error("git for-each-ref timed out") });
      await expect(go()).rejects.toThrow(/for-each-ref timed out/);
      expect(gitPush).not.toHaveBeenCalled();
      expect(deleteCalls()).toHaveLength(0);
      expect(reportSilentFallback).toHaveBeenCalledTimes(1);
      expect(reportSilentFallback.mock.calls[0][1]).toMatchObject({ op: "git_data_replication_push" });
    });

    // F21: after step 1 is confirmed, every pushed local rescue branch is deleted with a
    // compare-and-delete (`update-ref -d <ref> <sha>`), so a branch that moved since the listing survives.
    it("after a confirmed step 1 each listed rescue branch is deleted with update-ref -d <ref> <sha> (compare-and-delete)", async () => {
      fakeLocalGit({ refs: [[SHA_A, RESCUE_A], [SHA_B, RESCUE_B]] });
      await expect(go()).resolves.toEqual({ status: "replicated" });
      const dels = deleteCalls();
      expect(dels.map((c) => c[1])).toEqual([
        ["-C", "/tmp/ws", "update-ref", "-d", RESCUE_A, SHA_A],
        ["-C", "/tmp/ws", "update-ref", "-d", RESCUE_B, SHA_B],
      ]);
      for (const c of dels) expect(c[2]).toMatchObject({ cwd: "/tmp/ws", timeout: 5000 });
    });

    it("a listing line that is not `<full sha> <rescue ref>` is never passed to update-ref", async () => {
      execFileSyncMock.mockImplementation((...a: unknown[]) => {
        const args = a[1] as string[];
        if (args[2] === "for-each-ref") {
          return Buffer.from(`${SHA_A} ${RESCUE_A}\nzzzz ${RESCUE_B}\n${SHA_B} refs/heads/main\n`);
        }
        return Buffer.from("");
      });
      await go();
      expect(deleteCalls().map((c) => (c[1] as string[])[4])).toEqual([RESCUE_A]);
    });

    it("a failing local delete is best-effort: both refs are still attempted, main is pushed, replication succeeds", async () => {
      fakeLocalGit({ refs: [[SHA_A, RESCUE_A], [SHA_B, RESCUE_B]], failDelete: true });
      await expect(go()).resolves.toEqual({ status: "replicated" });
      expect(deleteCalls()).toHaveLength(2);
      expect(gitPush).toHaveBeenCalledTimes(2);
      expect(reportSilentFallback).not.toHaveBeenCalled();
    });
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

  // (#8211 fix-forward 2) ONE retry, on a POSITIVE-MATCH transient class only. The
  // first push of 2+ refs from a shallow clone can hit `remote failure` /
  // `failed to report status`; the fence accepts an equal lease-gen so the resent
  // push is idempotent. Deterministic refusals (shallow reject, fence reject)
  // are never retried — the match list is positive, so they fall through to the
  // existing loud path. The classifier reads `err.stderr` — the surface the
  // execFile rejection actually carries — so the fixtures put the trigger text
  // there, not only in the message (the 2026-09-21 retry-flag learning).
  it("retries the push ONCE on a transient remote failure (stderr), then reports replicated", async () => {
    gitPush
      .mockRejectedValueOnce(
        Object.assign(new Error("Command failed: git push"), {
          stderr: "error: remote failure\nerror: failed to report status",
        }),
      )
      .mockResolvedValueOnce(Buffer.from(""));

    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 9 , userId: USER }),
    ).resolves.toEqual({ status: "replicated" });

    expect(gitPush).toHaveBeenCalledTimes(2);
    // The retry re-issues the IDENTICAL argv — the same lease-gen fence option
    // is what makes the resent push idempotent.
    expect(gitPush.mock.calls[1][0]).toEqual(gitPush.mock.calls[0][0]);
  });

  it("does NOT retry on `shallow update not allowed` — a deterministic refusal", async () => {
    gitPush.mockRejectedValueOnce(
      Object.assign(
        new Error(
          "! [remote rejected] main -> refs/soleur/worktrees/wt/heads/main (shallow update not allowed)",
        ),
        {
          stderr:
            "! [remote rejected] main -> refs/soleur/worktrees/wt/heads/main (shallow update not allowed)",
        },
      ),
    );

    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 1 , userId: USER }),
    ).rejects.toThrow(/shallow update not allowed/);
    expect(gitPush).toHaveBeenCalledTimes(1);
  });

  it("does NOT retry on a fence reject (stale lease generation)", async () => {
    gitPush.mockRejectedValueOnce(
      Object.assign(
        new Error("remote: git-data fence: stale lease generation 3 < stored max 5 — rejected"),
        { stderr: "remote: git-data fence: stale lease generation 3 < stored max 5 — rejected" },
      ),
    );

    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 3 , userId: USER }),
    ).rejects.toThrow(/stale lease generation/);
    expect(gitPush).toHaveBeenCalledTimes(1);
  });

  it("still fails after two consecutive transients — at most one retry", async () => {
    gitPush.mockRejectedValue(
      Object.assign(new Error("Command failed: git push"), { stderr: "remote failure" }),
    );

    await expect(
      replicateToGitData({ workspacePath: "/tmp/ws", workspaceId: WS, worktreeId: WT, leaseGeneration: 1 , userId: USER }),
    ).rejects.toThrow(/git push/);
    expect(gitPush).toHaveBeenCalledTimes(2);
    // The second failure takes the existing loud path.
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
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
    // A genuinely non-git-data env has NO git-data inputs at all. The suite arms the
    // provision key globally in beforeEach, so it must be cleared here — otherwise this
    // fixture describes a partial birth (provision armed, remove key missing) and the
    // honest answer to it is `unconfigured`, not `skipped`.
    vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "");
    vi.stubEnv("GIT_DATA_SSH_HOST", "");
    // `skipped` is a MEASURED outcome, not an absent one. It used to resolve undefined,
    // which the caller could not tell from a completed erasure — the #8094 defect one
    // level down: "nothing to erase here" and "erased" both read as success.
    await expect(removeGitDataRepo(WS)).resolves.toEqual({ status: "skipped" });
    expect(sshProvision).not.toHaveBeenCalled();
  });

  // ------------------------------------------------------------------------------
  // (#8094) THE REFUSAL MUST SURVIVE THE RETURN. After #8043 F8 the host-side
  // `git-data-remove.sh` REFUSES (named message, non-zero exit) on an unmounted store
  // instead of reporting a no-op. The app kept lying anyway: `removeGitDataRepo` was
  // `Promise<void>`, so a refusal and a completed erasure were indistinguishable to the
  // caller, and `sshWithPrivateKeyAuth` returns stdout only — no rc, no stderr.
  //
  // The discriminator is ssh's own convention: 255 is ssh failing to establish the
  // session (unreachable — say nothing about the store), any other non-zero is the
  // REMOTE forced command's exit status (refused — the host looked and said no).
  const sshErr = (code: number, stderr: string) =>
    Object.assign(new Error(`Command failed with exit code ${code}`), { code, stderr });

  it("host REFUSES the erasure (non-zero, not 255): reports refused with the remote's rc + stderr — never a silent success", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    sshProvision.mockRejectedValueOnce(sshErr(3, "git-data-remove: /mnt/git-data is not mounted; refusing\n"));
    const outcome = await removeGitDataRepo(WS);
    expect(outcome.status).toBe("refused");
    if (outcome.status !== "refused") throw new Error("unreachable");
    expect(outcome.exitCode).toBe(3);
    // The remote's OWN words reach the caller. Without this the operator sweeping an
    // un-erased repo has an exit code and no reason.
    expect(outcome.detail).toContain("not mounted");
  });

  // (#8211, ADR-239) The store assertion (C1) refuses through the wrapper's `reject`, which is
  // exit 1 — the code git-data-remove.test.sh pins. This row pins that exit 1 maps to
  // `refused` (an existing mapping), so a refused store is never read as erased or unreachable.
  it("the store assertion refuses (exit 1, store not verified): reports refused with exitCode 1", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    sshProvision.mockRejectedValueOnce(
      sshErr(1, "remote: git-data remove: store not verified: /etc/git-data/store-verified absent or not bound to this volume (fail-closed)\n"),
    );
    const outcome = await removeGitDataRepo(WS);
    expect(outcome.status).toBe("refused");
    if (outcome.status !== "refused") throw new Error("unreachable");
    expect(outcome.exitCode).toBe(1);
    expect(outcome.detail).toContain("store not verified");
  });

  it("ssh cannot establish the session (rc 255): reports unreachable — a blip is NOT evidence the store refused", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    sshProvision.mockRejectedValueOnce(sshErr(255, "ssh: connect to host 10.0.1.20 port 22: Connection refused\n"));
    const outcome = await removeGitDataRepo(WS);
    // Deliberately NOT "refused": nothing here says the host looked at the repo. The two
    // need different operator responses, so collapsing them is the measured/could-not-
    // measure collapse in the erasure path.
    expect(outcome.status).toBe("unreachable");
  });

  it("the REMOVE key is REJECTED by the host (255 + publickey): reports unauthorized, NOT unreachable", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    sshProvision.mockRejectedValueOnce(
      sshErr(255, "git@10.0.1.20: Permission denied (publickey).\n"),
    );
    const outcome = await removeGitDataRepo(WS);
    // The host ANSWERED and refused the credential. That is not "we never got an answer":
    // the REMOVE public key is baked into cloud-init authorized_keys and user_data is
    // ForceNew, so a Doppler-side rotation without a host replace fails this way on EVERY
    // deletion, permanently, fleet-wide — with every repo definitively un-erased. Reading
    // it as a transient blip is the exact collapse this module exists to prevent.
    expect(outcome.status).toBe("unauthorized");
  });

  it("a malformed REMOVE key (255 + invalid format): also unauthorized", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    sshProvision.mockRejectedValueOnce(
      sshErr(255, 'Load key "/tmp/.git-provision-x.key": invalid format\n'),
    );
    expect((await removeGitDataRepo(WS)).status).toBe("unauthorized");
  });

  it("a 255 with NO auth signature stays unreachable (a genuine transport failure)", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    sshProvision.mockRejectedValueOnce(
      sshErr(255, "ssh: connect to host 10.0.1.20 port 22: Connection refused\n"),
    );
    expect((await removeGitDataRepo(WS)).status).toBe("unreachable");
  });

  it("the 30s ssh TIMEOUT (code null) reports unreachable — the arm the comment calls out and nothing exercised", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    // execFileAsync's timeout rejects with a `killed` error whose `code` is null, not a
    // number. A hung git-data host is the scenario this whole feature exists for, and it
    // was the one classifier arm with no test.
    sshProvision.mockRejectedValueOnce(
      Object.assign(new Error("Command failed: ssh ..."), { killed: true, code: null, signal: "SIGTERM" }),
    );
    expect((await removeGitDataRepo(WS)).status).toBe("unreachable");
  });

  it("scrubs the workspace UUID out of detail — it is auth.users.id and must not ship raw", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    sshProvision.mockRejectedValueOnce(
      sshErr(1, `git-data-remove: could not acquire init lock for '${WS}'\n`),
    );
    const outcome = await removeGitDataRepo(WS);
    if (outcome.status !== "refused") throw new Error("expected refused");
    // workspace_id === auth.users.id (mig-053 N2). reportSilentFallback pseudonymizes
    // extra.userId two lines from where this detail is attached; shipping the same id raw
    // in detail would route around that contract while looking compliant.
    expect(outcome.detail).not.toContain(WS);
    expect(outcome.detail).toContain("WORKSPACE_ID_REDACTED");
  });

  it("remove key absent BUT git-data otherwise armed: unconfigured, not skipped", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "");
    vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "provision-key");
    const outcome = await removeGitDataRepo(WS);
    // A partial birth or a half-applied rotation. Reporting `skipped` here would tell the
    // user their data is gone while a host that is actively provisioning repos keeps theirs.
    expect(outcome.status).toBe("unconfigured");
    if (outcome.status !== "unconfigured") throw new Error("narrow");
    // Fixed reason word, distinct from the pin faults (#7226): pin_invalid / pin_absent.
    expect(outcome.detail).toMatch(/^remove_key_absent: /);
    expect(sshProvision).not.toHaveBeenCalled();
  });

  it("erasure succeeds: reports erased", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    const outcome = await removeGitDataRepo(WS);
    expect(outcome).toEqual({ status: "erased" });
  });

  it("an unsafe workspace_id still THROWS rather than returning an outcome (CWE-22 is a bug, not a result)", async () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    await expect(removeGitDataRepo("../evil")).rejects.toThrow();
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

  it("SHEDS on queue timeout: resolves with a shed outcome, reports the shed, and consumes no slot", async () => {
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
    // session end must never block on it. And it must SAY it shed — B13 (#6982 review):
    // returning bare `void` made a shed indistinguishable from a completed push at the call
    // site, on a path where a shed delta is never replicated later.
    await expect(call(mod, "ws-shed")).resolves.toEqual({
      status: "shed",
      slotsBusy: expect.any(Number),
      queueTimeoutMs: expect.any(Number),
    });

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
    await expect(call(mod, "ws-after")).resolves.toEqual({ status: "replicated" });
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

type LogCall = { level: string; args: unknown[] };

// `log` is created at module init, so the logger mock must be installed BEFORE the dynamic import.
async function loadWithLogger() {
  vi.resetModules();
  const logCalls: LogCall[] = [];
  const rec = (level: string) => (...a: unknown[]) => {
    logCalls.push({ level, args: a });
  };
  vi.doMock("../server/logger", async (importOriginal) => ({
    ...(await importOriginal<typeof import("../server/logger")>()),
    createChildLogger: () => ({
      info: rec("info"),
      warn: rec("warn"),
      error: rec("error"),
      debug: rec("debug"),
    }),
  }));
  vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
  const mod = await import("../server/git-data-replication");
  return { mod, logCalls };
}

const markerCalls = (calls: LogCall[]) =>
  calls.filter((c) => typeof c.args[1] === "string" && (c.args[1] as string).includes("git_data_replication_success="));

// Replication-success marker (#11704 item 6 / CTO F6, capped by F15). A successful push emits a
// warn-level, closed-grammar, counts-only line so a success reaches Better Stack (info never
// ships), at most once per 60 s per process per transient_retried value. The read side
// (scripts/followthroughs/git-data-replication-signal.sh) matches it with the regex MARKER_RE
// (a parity row below extracts that regex from the script and runs it against what is emitted),
// so the phrase must exist on the success branch only and carry no identifier.
describe("replicateToGitData — replication-success marker (#11704)", () => {
  const MARKER_PREFIX = "git_data_replication_success=1 transient_retried=";
  const SIGNAL_SCRIPT = path.resolve(__dirname, "../../../scripts/followthroughs/git-data-replication-signal.sh");
  const REAL_WS = "3f2504e0-4f89-11d3-9a0c-0305e82c3301";

  const run = (mod: typeof import("../server/git-data-replication"), leaseGeneration = 12) =>
    mod.replicateToGitData({
      workspacePath: "/tmp/ws",
      workspaceId: REAL_WS,
      worktreeId: WT,
      leaseGeneration,
      userId: USER,
    });

  afterEach(() => {
    vi.useRealTimers();
    vi.doUnmock("../server/logger");
  });

  it("emits exactly one warn marker with the closed-grammar message and counts-only fields on success", async () => {
    const { mod, logCalls } = await loadWithLogger();
    await expect(run(mod)).resolves.toEqual({ status: "replicated" });

    const markers = markerCalls(logCalls);
    expect(markers).toHaveLength(1);
    expect(markers[0].level).toBe("warn");
    expect(markers[0].args[1]).toBe(`${MARKER_PREFIX}0`);
    expect(markers[0].args[0]).toEqual({ gitDataReplicationSuccess: 1, transientRetried: 0 });
  });

  // N6: the read side matches with a REGEX (MARKER_RE inside the script's SQL match()), not a
  // substring. Extract it from the script and run it against what the TS actually emits for both
  // retried bits, so a grammar change on either side fails here.
  it("parity: MARKER_RE extracted from the signal script matches the exact message emitted for retried 0 and 1", async () => {
    const src = fs.readFileSync(SIGNAL_SCRIPT, "utf8");
    const m = /^MARKER_RE='([^']+)'$/m.exec(src);
    expect(m).not.toBeNull();
    const markerRe = new RegExp(m![1]);

    const first = await loadWithLogger();
    await run(first.mod);
    const retried0 = markerCalls(first.logCalls)[0].args[1] as string;

    const second = await loadWithLogger();
    gitPush
      .mockRejectedValueOnce(Object.assign(new Error("Command failed: git push"), { stderr: "error: remote failure" }))
      .mockResolvedValueOnce(Buffer.from(""));
    await run(second.mod);
    const retried1 = markerCalls(second.logCalls)[0].args[1] as string;

    expect(retried0).toBe(`${MARKER_PREFIX}0`);
    expect(retried1).toBe(`${MARKER_PREFIX}1`);
    expect(markerRe.test(retried0)).toBe(true);
    expect(markerRe.test(retried1)).toBe(true);
    // the regex is not vacuous: it does not match a different grammar
    expect(markerRe.test(`${MARKER_PREFIX}2`)).toBe(false);
    expect(markerRe.test("git_data_replication_success=0 transient_retried=0")).toBe(false);
  });

  // CTO F15 (T4): at most ONE marker per 60 s per process per transient_retried value. The first
  // success after idle always emits, so a `markers > 0` read stays valid; the marker is presence
  // evidence, not a count. Date is faked (not the timers) so the push queue is unaffected.
  describe("volume cap (one per 60 s per transient_retried value)", () => {
    const T0 = Date.parse("2026-10-31T00:00:00Z");
    const at = (ms: number) => vi.setSystemTime(T0 + ms);
    const transient = () =>
      gitPush
        .mockRejectedValueOnce(Object.assign(new Error("Command failed: git push"), { stderr: "error: remote failure" }))
        .mockResolvedValueOnce(Buffer.from(""));

    beforeEach(() => {
      vi.useFakeTimers({ toFake: ["Date"] });
      at(0);
    });

    it("two successes inside the window emit ONE marker; both still replicate and log the info line", async () => {
      const { mod, logCalls } = await loadWithLogger();
      await expect(run(mod)).resolves.toEqual({ status: "replicated" });
      at(30_000);
      await expect(run(mod)).resolves.toEqual({ status: "replicated" });
      expect(gitPush).toHaveBeenCalledTimes(2);
      expect(markerCalls(logCalls)).toHaveLength(1);
      expect(logCalls.filter((c) => c.args[1] === "git-data replication push complete")).toHaveLength(2);
    });

    it("the window is exactly 60 s from the last EMITTED marker: 59.999 s suppressed, 60 s emits", async () => {
      const { mod, logCalls } = await loadWithLogger();
      await run(mod); // emits at t0
      at(59_999);
      await run(mod);
      expect(markerCalls(logCalls)).toHaveLength(1);
      at(60_000);
      await run(mod);
      expect(markerCalls(logCalls)).toHaveLength(2);
    });

    it("a success after 61 s emits a second marker; the window restarts from that emission", async () => {
      const { mod, logCalls } = await loadWithLogger();
      await run(mod);
      at(61_000);
      await run(mod);
      expect(markerCalls(logCalls)).toHaveLength(2);
      at(61_000 + 59_000); // inside the NEW window, though > 60 s after the first marker
      await run(mod);
      expect(markerCalls(logCalls)).toHaveLength(2);
    });

    it("transient_retried=1 keeps its own slot: it emits inside the retried=0 window, then is capped itself", async () => {
      const { mod, logCalls } = await loadWithLogger();
      await run(mod); // retried=0 at t0
      at(10_000);
      transient();
      await run(mod); // retried=1, first of its kind
      at(20_000);
      transient();
      await run(mod); // retried=1 again inside ITS window
      at(25_000);
      await run(mod); // retried=0 again inside ITS window
      const msgs = markerCalls(logCalls).map((c) => c.args[1]);
      expect(msgs).toEqual([`${MARKER_PREFIX}0`, `${MARKER_PREFIX}1`]);
    });

    it("a failed replication neither emits nor consumes the window", async () => {
      const { mod, logCalls } = await loadWithLogger();
      gitPush.mockRejectedValueOnce(Object.assign(new Error("fence"), { stderr: "remote: git-data fence: stale lease generation 1 < 2" }));
      await expect(run(mod)).rejects.toThrow();
      at(1_000);
      await run(mod); // first SUCCESS, one second after a failure: emits
      expect(markerCalls(logCalls)).toHaveLength(1);
    });

    it("the exported reset clears the window (test seam)", async () => {
      const { mod, logCalls } = await loadWithLogger();
      await run(mod);
      mod.__resetGitDataSuccessMarkerCapForTest();
      await run(mod); // same instant, would be capped without the reset
      expect(markerCalls(logCalls)).toHaveLength(2);
    });

    it("a clock that steps backwards does not silence the marker for the rest of the process", async () => {
      const { mod, logCalls } = await loadWithLogger();
      await run(mod);
      at(-3_600_000); // wall clock stepped back an hour
      await run(mod);
      expect(markerCalls(logCalls)).toHaveLength(2);
    });
  });

  it("flags the single transient retry: transient_retried=1 and exactly one marker", async () => {
    const { mod, logCalls } = await loadWithLogger();
    gitPush
      .mockRejectedValueOnce(
        Object.assign(new Error("Command failed: git push"), { stderr: "error: remote failure" }),
      )
      .mockResolvedValueOnce(Buffer.from(""));
    await expect(run(mod)).resolves.toEqual({ status: "replicated" });

    expect(gitPush).toHaveBeenCalledTimes(2);
    const markers = markerCalls(logCalls);
    expect(markers).toHaveLength(1);
    expect(markers[0].args[1]).toBe(`${MARKER_PREFIX}1`);
    expect(markers[0].args[0]).toEqual({ gitDataReplicationSuccess: 1, transientRetried: 1 });
  });

  // T1b: with a local rescue branch the replication is two pushes; `transient_retried` is true if
  // EITHER step retried, and there is still exactly one marker for the whole replication.
  describe("with a local rescue branch (two-step push)", () => {
    const withRescue = () => fakeLocalGit({ refs: [[SHA_A, "refs/heads/soleur-store-tip-0123456789ab"]] });
    const transientErr = () => Object.assign(new Error("Command failed: git push"), { stderr: "error: remote failure" });

    it("a retry on the RESCUE step only → one marker, transient_retried=1", async () => {
      const { mod, logCalls } = await loadWithLogger();
      withRescue();
      gitPush.mockRejectedValueOnce(transientErr()).mockResolvedValue(Buffer.from(""));
      await run(mod);
      expect(gitPush).toHaveBeenCalledTimes(3);
      const markers = markerCalls(logCalls);
      expect(markers).toHaveLength(1);
      expect(markers[0].args[1]).toBe(`${MARKER_PREFIX}1`);
    });

    it("a retry on the MAIN step only → one marker, transient_retried=1", async () => {
      const { mod, logCalls } = await loadWithLogger();
      withRescue();
      gitPush
        .mockResolvedValueOnce(Buffer.from(""))
        .mockRejectedValueOnce(transientErr())
        .mockResolvedValue(Buffer.from(""));
      await run(mod);
      expect(gitPush).toHaveBeenCalledTimes(3);
      expect(markerCalls(logCalls).map((c) => c.args[1])).toEqual([`${MARKER_PREFIX}1`]);
    });

    it("no retry on either step → one marker, transient_retried=0", async () => {
      const { mod, logCalls } = await loadWithLogger();
      withRescue();
      await run(mod);
      expect(gitPush).toHaveBeenCalledTimes(2);
      expect(markerCalls(logCalls).map((c) => c.args[1])).toEqual([`${MARKER_PREFIX}0`]);
    });

    it("a failing local delete after step 1 logs a warn without identifiers and does not stop the marker", async () => {
      const { mod, logCalls } = await loadWithLogger();
      fakeLocalGit({ refs: [[SHA_A, "refs/heads/soleur-store-tip-0123456789ab"]], failDelete: true });
      await expect(run(mod)).resolves.toEqual({ status: "replicated" });
      const warns = logCalls.filter((c) => c.level === "warn" && String(c.args[1]).includes("could not delete a pushed local rescue branch"));
      expect(warns).toHaveLength(1);
      expect(JSON.stringify(warns)).not.toContain(REAL_WS);
      expect(JSON.stringify(warns)).not.toContain("soleur-store-tip-0123456789ab");
      expect(markerCalls(logCalls)).toHaveLength(1);
    });

    it("emits NO marker when the rescue push fails, and the main push is never attempted", async () => {
      const { mod, logCalls } = await loadWithLogger();
      withRescue();
      gitPush.mockRejectedValueOnce(
        Object.assign(new Error("fence"), { stderr: "remote: git-data fence: stale lease generation 3 < stored max 5" }),
      );
      await expect(run(mod)).rejects.toThrow();
      expect(gitPush).toHaveBeenCalledTimes(1);
      expect(markerCalls(logCalls)).toHaveLength(0);
      expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    });
  });

  it("emits NO marker when the push fails (fence reject)", async () => {
    const { mod, logCalls } = await loadWithLogger();
    gitPush.mockRejectedValueOnce(
      Object.assign(new Error("remote: git-data fence: stale lease generation 3 < stored max 5 — rejected"), {
        stderr: "remote: git-data fence: stale lease generation 3 < stored max 5 — rejected",
      }),
    );
    await expect(run(mod)).rejects.toThrow(/stale lease generation/);
    expect(markerCalls(logCalls)).toHaveLength(0);
  });

  it("emits NO marker when both attempts fail (retry exhausted)", async () => {
    const { mod, logCalls } = await loadWithLogger();
    gitPush.mockRejectedValue(
      Object.assign(new Error("Command failed: git push"), { stderr: "remote failure" }),
    );
    await expect(run(mod)).rejects.toThrow(/git push/);
    expect(gitPush).toHaveBeenCalledTimes(2);
    expect(markerCalls(logCalls)).toHaveLength(0);
    // N26: the failure is reported ONCE (not per attempt). With no local rescue branch both attempts
    // are the main push, which is per-ref and carries NO --atomic (F20); --atomic is on the rescue
    // step only (asserted in the two-step rows). Whether the old store tip is still referenced after
    // two failed attempts is a property of the store, not of this mock-level row.
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(reportSilentFallback.mock.calls[0][1]).toMatchObject({ op: "git_data_replication_push" });
    for (const call of gitPush.mock.calls) expect(call[0] as string[]).not.toContain("--atomic");
    gitPush.mockResolvedValue(Buffer.from(""));
  });

  it("emits NO marker on a pin fault (no valid host-key pin, nothing pushed)", async () => {
    const { mod, logCalls } = await loadWithLogger();
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", "");
    await expect(run(mod)).rejects.toThrow();
    expect(gitPush).not.toHaveBeenCalled();
    expect(markerCalls(logCalls)).toHaveLength(0);
  });

  it("emits NO marker when the replication is shed", async () => {
    vi.stubEnv("GIT_DATA_MAX_CONCURRENT", "1");
    vi.stubEnv("GIT_DATA_QUEUE_TIMEOUT_MS", "0");
    const { mod, logCalls } = await loadWithLogger();
    let releasePush: () => void = () => {};
    const pushGate = new Promise<Buffer>((res) => {
      releasePush = () => res(Buffer.from(""));
    });
    gitPush.mockImplementation(() => pushGate);

    const held = run(mod);
    await vi.waitFor(() => expect(mod.__gitDataInFlightForTest()).toBe(1));
    const before = markerCalls(logCalls).length;
    await expect(run(mod)).resolves.toMatchObject({ status: "shed" });
    expect(markerCalls(logCalls)).toHaveLength(before); // the shed added none

    releasePush();
    await held;
    gitPush.mockResolvedValue(Buffer.from(""));
  });

  it("the marker phrase occurs exactly once in the server tree (the signal script's MARKER_RE counts every occurrence in the window)", () => {
    const serverDir = path.resolve(__dirname, "../server");
    const hits: string[] = [];
    const walk = (dir: string) => {
      for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, ent.name);
        if (ent.isDirectory()) {
          if (ent.name !== "node_modules") walk(p);
        } else if (/\.(ts|tsx|js|mjs|cjs|sh)$/.test(ent.name)) {
          const n = fs.readFileSync(p, "utf8").split("git_data_replication_success=1").length - 1;
          for (let i = 0; i < n; i++) hits.push(p);
        }
      }
    };
    walk(serverDir);
    expect(hits).toHaveLength(1);
    expect(hits[0]).toMatch(/git-data-replication\.ts$/);
  });
});

// Real git against a real bare store (F20, F21). The mocked rows above prove the argv; these prove what
// git DOES with it. Only the authenticated transport is replaced: `gitWithPrivateKeyAuth` runs the very
// argv production built through real `git`, with the `git-data` ssh URL rewritten onto a local bare repo
// (`url.<base>.insteadOf`). The rescue listing, the compare-and-delete and `ensureGitDataRemote` run
// unmocked. The store accepts push options, as the git-data host does.
describe("replicateToGitData — real git store (F20 per-ref main push, F21 rescue-branch delete)", () => {
  let root = "";
  let ws = "";
  let store = "";
  let realExec: typeof import("node:child_process").execFileSync;
  const storeRef = (b: string) => `refs/soleur/worktrees/${WT}/heads/${b}`;
  const git = (cwd: string, args: string[]): string =>
    realExec("git", args, { cwd, env: gitFixtureEnv(root), encoding: "utf8", stdio: "pipe" }).trim();
  const commit = (file: string): string => {
    fs.writeFileSync(path.join(ws, file), `${file}\n`);
    git(ws, ["add", "--", file]);
    git(ws, ["commit", "-q", "-m", `add ${file}`]);
    return git(ws, ["rev-parse", "HEAD"]);
  };

  beforeEach(async () => {
    realExec = (await vi.importActual<typeof import("node:child_process")>("node:child_process")).execFileSync;
    root = fs.mkdtempSync(path.join(os.tmpdir(), "replicate-real-git-"));
    fs.mkdirSync(path.join(root, "stores"));
    store = path.join(root, "stores", `${WS}.git`);
    ws = path.join(root, "ws");
    fs.mkdirSync(ws);
    git(root, ["init", "-q", "--bare", store]);
    git(store, ["config", "receive.advertisePushOptions", "true"]);
    git(ws, ["init", "-q", "-b", "main"]);
    commit("a.txt");
    // the local git calls of production (remote config, rescue listing, delete) run for real
    execFileSyncMock.mockImplementation((...a: unknown[]) =>
      realExec(a[0] as string, a[1] as string[], { ...(a[2] as object), env: gitFixtureEnv(root) }),
    );
    // the authenticated transport: the production push argv, run by real git against the local store
    gitPush.mockImplementation(async (...a: unknown[]) => {
      const [args, , , opts] = a as [string[], string, string, { cwd: string }];
      try {
        realExec(
          "git",
          ["-c", `url.file://${root}/stores/.insteadOf=ssh://git@10.0.1.20/mnt/git-data/repositories/`, ...args],
          { cwd: opts.cwd, env: gitFixtureEnv(root), stdio: "pipe" },
        );
      } catch (e) {
        const stderr = String((e as { stderr?: unknown }).stderr ?? "");
        throw Object.assign(new Error(`Command failed: git push\n${stderr}`), { stderr });
      }
      return Buffer.from("");
    });
  });

  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
    vi.doUnmock("../server/logger");
  });

  const replicate = async () => {
    const { mod, logCalls } = await loadWithLogger();
    mod.__resetGitDataSuccessMarkerCapForTest();
    const out = mod.replicateToGitData({ workspacePath: ws, workspaceId: WS, worktreeId: WT, leaseGeneration: 1, userId: USER });
    return { out, logCalls };
  };

  it("positive control: a clean store takes every ref and the success marker fires", async () => {
    git(ws, ["branch", "fix"]);
    const { out, logCalls } = await replicate();
    await expect(out).resolves.toEqual({ status: "replicated" });
    expect(git(store, ["rev-parse", storeRef("main")])).toBe(git(ws, ["rev-parse", "main"]));
    expect(git(store, ["rev-parse", storeRef("fix")])).toBe(git(ws, ["rev-parse", "fix"]));
    expect(markerCalls(logCalls)).toHaveLength(1);
  });

  // F20: the stale store head `heads/fix/x` blocks the new local ref `fix` (refname conflict). The main
  // push is per-ref, so `main` still lands; git exits non-zero for the rejected ref, the call reports
  // failure loudly, and NO success marker fires. Under --atomic the same push left `main` stale forever.
  it("F20: store holds heads/fix/x, local has branch fix → main lands, the call FAILS loudly, no success marker", async () => {
    git(ws, ["branch", "fix/x"]);
    git(ws, ["push", "-q", "--force", `file://${store}`, `refs/heads/fix/x:${storeRef("fix/x")}`]);
    git(ws, ["branch", "-D", "fix/x"]);
    git(ws, ["branch", "fix"]);
    const tip = commit("b.txt");
    expect(() => git(store, ["rev-parse", storeRef("main")])).toThrow(); // main is not in the store yet

    const { out, logCalls } = await replicate();
    await expect(out).rejects.toThrow(/Command failed: git push/);

    expect(git(store, ["rev-parse", storeRef("main")])).toBe(tip); // the per-ref push landed main
    expect(git(store, ["rev-parse", storeRef("fix/x")])).toBeTruthy(); // the stale head is untouched
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(reportSilentFallback.mock.calls[0][1]).toMatchObject({ op: "git_data_replication_push" });
    expect(markerCalls(logCalls)).toHaveLength(0);
    // and it is the production main push that ran: no --atomic on it
    expect(gitPush).toHaveBeenCalledTimes(1);
    expect(gitPush.mock.calls[0][0] as string[]).not.toContain("--atomic");
  });

  // F21: after step 1 is confirmed the pushed local rescue branch is gone, the store copy remains, and
  // the next replication issues no rescue push.
  it("F21: the local rescue branch is deleted after the confirmed push, the store ref remains, a second replicate pushes no rescue", async () => {
    const old = git(ws, ["rev-parse", "HEAD"]);
    const rescue = `soleur-store-tip-${old.slice(0, 12)}`;
    git(ws, ["branch", rescue, old]);
    commit("b.txt"); // main moves past the rescued tip

    const first = await replicate();
    await expect(first.out).resolves.toEqual({ status: "replicated" });
    expect(gitPush).toHaveBeenCalledTimes(2); // rescue step, then main
    expect(gitPush.mock.calls[0][0] as string[]).toContain(gitDataPushRefspecs(WT).rescue);
    expect(git(ws, ["for-each-ref", "refs/heads/soleur-store-tip-*"])).toBe(""); // local branch gone
    expect(git(store, ["rev-parse", storeRef(rescue)])).toBe(old); // store copy remains
    expect(git(store, ["rev-parse", storeRef("main")])).toBe(git(ws, ["rev-parse", "main"]));

    gitPush.mockClear();
    const second = await replicate();
    await expect(second.out).resolves.toEqual({ status: "replicated" });
    expect(gitPush).toHaveBeenCalledTimes(1); // no rescue push this time
    expect(gitPush.mock.calls[0][0] as string[]).not.toContain(gitDataPushRefspecs(WT).rescue);
    expect(git(store, ["rev-parse", storeRef(rescue)])).toBe(old);
  });

  it("F21: a rescue branch that moved since the listing is NOT deleted (compare-and-delete)", async () => {
    const old = git(ws, ["rev-parse", "HEAD"]);
    const rescue = `soleur-store-tip-${old.slice(0, 12)}`;
    git(ws, ["branch", rescue, old]);
    const moved = commit("b.txt");
    // Move the rescue branch to a different commit the instant the (single) rescue push is confirmed.
    const realPush = gitPush.getMockImplementation()!;
    let calls = 0;
    gitPush.mockImplementation(async (...a: unknown[]) => {
      const r = await realPush(...a);
      if (++calls === 1) git(ws, ["update-ref", `refs/heads/${rescue}`, moved]);
      return r;
    });
    const { out } = await replicate();
    await expect(out).resolves.toEqual({ status: "replicated" });
    expect(git(ws, ["rev-parse", `refs/heads/${rescue}`])).toBe(moved); // survived: sha no longer matched
  });
});
