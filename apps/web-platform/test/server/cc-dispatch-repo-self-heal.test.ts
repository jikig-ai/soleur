import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { existsSync, mkdirSync } from "node:fs";
import { mkdtemp, rm, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  resolveRepoReadinessWithSelfHeal,
  type RepoSelfHealSeams,
} from "@/server/repo-readiness-self-heal";
import { evaluateRepoReadiness } from "@/server/repo-readiness";
import { ensureWorkspaceRepoCloned } from "@/server/ensure-workspace-repo";
import { isValidGitWorkTree } from "@/server/git-worktree-validity";

// FIX 1a (Phase 2): the dispatch self-heal orchestrator. The pure
// `evaluateRepoReadiness` decision is reused as the first seam; the I/O seams
// (`claimCloneLock`, `setRepoStatus`, `ensureWorkspaceRepoCloned`, `gitDirExists`)
// are injected so this decision test stays DB-free (AC4) while still proving the
// gate-reordering correction (short-circuit-guard-must-sit-after-the-recovery).

const INSTALL = 12345;
const REPO = "https://github.com/acme/widgets";
const WS = "11111111-1111-1111-1111-111111111111";
const PATH = "/workspaces/" + WS;
const USER = "22222222-2222-2222-2222-222222222222";

function makeSeams(over: Partial<RepoSelfHealSeams> = {}): RepoSelfHealSeams {
  return {
    evaluateRepoReadiness,
    claimCloneLock: vi.fn(async () => true),
    setRepoStatus: vi.fn(async () => {}),
    ensureWorkspaceRepoCloned: vi.fn(async () => "ok" as const),
    gitDirExists: vi.fn(() => false),
    // Validity (2026-06-19) defaults to false to mirror the absent-`.git`
    // default of `gitDirExists` — the absent/graft paths route correctly. Tests
    // exercising a VALID on-disk `.git` (the AC7 fast path) set this true; the
    // corrupt-worktree tests set it via the real `isValidGitWorkTree`.
    gitDirValid: vi.fn(() => false),
    reportDivergence: vi.fn(),
    ...over,
  };
}

function baseArgs() {
  return {
    userId: USER,
    workspaceId: WS,
    workspacePath: PATH,
    installationId: INSTALL,
    repoUrl: REPO,
    status: "error" as string | null | undefined,
    repoError: null as string | null | undefined,
  };
}

describe("resolveRepoReadinessWithSelfHeal (FIX 1a — AC1)", () => {
  it("error + installation + repoUrl + .git-absent + lock won → clones, sets ready, returns ok", async () => {
    const seams = makeSeams();
    const r = await resolveRepoReadinessWithSelfHeal(baseArgs(), seams);

    expect(r).toEqual({ ok: true });
    expect(seams.claimCloneLock).toHaveBeenCalledWith(WS);
    expect(seams.ensureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
    // AC6: reuses the (effective) installationId passed in, not a raw stored one.
    expect(seams.ensureWorkspaceRepoCloned).toHaveBeenCalledWith(
      expect.objectContaining({ installationId: INSTALL, repoUrl: REPO, workspacePath: PATH }),
    );
    expect(seams.setRepoStatus).toHaveBeenCalledWith(WS, "ready", null);
  });

  it("AC7: ready + .git PRESENT → { ok:true }, no seam touched (zero-await fast path)", async () => {
    // The COMMON case: a ready workspace whose clone is already on disk. The
    // ONLY permitted cost here is the local gitDirExists (existsSync) probe — no
    // clone, no lock, no status write (and, in cc-dispatcher, no getFreshTenantClient).
    const seams = makeSeams({
      gitDirExists: vi.fn(() => true),
      gitDirValid: vi.fn(() => true),
    });
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "ready" },
      seams,
    );
    expect(r).toEqual({ ok: true });
    expect(seams.claimCloneLock).not.toHaveBeenCalled();
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
    expect(seams.reportDivergence).not.toHaveBeenCalled();
  });

  it("AC6: ready + .git ABSENT + install + repoUrl → LOCK-FREE clone, .git materializes, returns ok WITHOUT setRepoStatus", async () => {
    // Bug 2 core: a DB-ready workspace whose physical clone is gone must be
    // deterministically (re-)cloned. The ready entry is LOCK-FREE
    // (claim_repo_clone_lock cannot acquire a ready row by construction — its
    // WHERE matches only error/stale-cloning, migration 108:97-110). On SUCCESS
    // the row is ALREADY repo_status='ready', so setRepoStatus is SKIPPED (no-op
    // + avoids a spurious member-row write + RPC round-trip).
    const seams = makeSeams({ gitDirExists: vi.fn(() => false) });
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "ready" },
      seams,
    );
    expect(r).toEqual({ ok: true });
    expect(seams.claimCloneLock).not.toHaveBeenCalled(); // lock-free for ready
    expect(seams.ensureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
    expect(seams.ensureWorkspaceRepoCloned).toHaveBeenCalledWith(
      expect.objectContaining({ installationId: INSTALL, repoUrl: REPO, workspacePath: PATH }),
    );
    // SUCCESS on the ready entry MUST NOT write status (already ready).
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
  });

  it("AC6 invariant: ready + .git ABSENT, clone genuinely lands .git (false → true), returns ok", async () => {
    // Assert the INVARIANT (gitDirExists false → true), not the 5-way-overloaded
    // proxy "ensureWorkspaceRepoCloned returned ok". A mutable disk-flag seam
    // models the real landing.
    let onDisk = false;
    const seams = makeSeams({
      gitDirExists: vi.fn(() => onDisk),
      ensureWorkspaceRepoCloned: vi.fn(async () => {
        onDisk = true; // the clone lands .git
        return "ok" as const;
      }),
    });
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "ready" },
      seams,
    );
    expect(r).toEqual({ ok: true });
    expect(onDisk).toBe(true); // .git materialized
  });

  it("#5733 AC0f: ready + .git ABSENT + clone FAILED on a TEAM workspace (WS!==USER) → honest block + EMIT-ONLY, ZERO setRepoStatus (F4: a member must not flip a co-owned shared status)", async () => {
    // baseArgs() has WS !== USER (a member dispatching into a co-owned/team
    // workspace). The clone genuinely failed, but flipping the shared
    // repo_status→error here would corrupt the workspace for its Owners — so the
    // ready-but-absent sibling now matches graftCorruptWorktree's emit-only TEAM
    // posture (the pre-existing F4 inconsistency this PR fixes). Still an honest
    // block; the Sentry mirror fires.
    const seams = makeSeams({
      gitDirExists: vi.fn(() => false),
      ensureWorkspaceRepoCloned: vi.fn(async () => "failed" as const),
    });
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "ready" },
      seams,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("error");
    expect(seams.ensureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
  });

  it("#5733 AC0c/AC0f: ready + .git ABSENT + clone FAILED on a SOLO/OWNER workspace (WS===USER) → setRepoStatus(error) IS written + honest block", async () => {
    // On the solo/owner path the dispatching user OWNS the workspace, so writing
    // the honest error reason (read back by the gate next dispatch) is safe.
    const seams = makeSeams({
      gitDirExists: vi.fn(() => false),
      ensureWorkspaceRepoCloned: vi.fn(async () => "failed" as const),
    });
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), workspaceId: USER, status: "ready" },
      seams,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("error");
    expect(seams.setRepoStatus).toHaveBeenCalledWith(USER, "error", expect.any(String));
  });

  it("#5733 AC0d: ready + .git ABSENT at routing but PRESENT at the post-clone CAS re-check (concurrent winner) → NO setRepoStatus even on solo/owner (never clobber a fresh ready)", async () => {
    // .git is absent when the gate routes to the ready-but-absent graft, but a
    // concurrent winner (reconcile / another tab) lands .git before the failure's
    // CAS re-check fires → the error write must be suppressed.
    const gitDirExists = vi.fn();
    gitDirExists.mockReturnValueOnce(false).mockReturnValue(true);
    const seams = makeSeams({
      gitDirExists,
      ensureWorkspaceRepoCloned: vi.fn(async () => "failed" as const),
    });
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), workspaceId: USER, status: "ready" },
      seams,
    );
    expect(r.ok).toBe(false); // still honest-blocks this dispatch
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
  });

  // AC1/AC1b/T1 — the headline divergence case (was previously the BUG: this
  // input fast-path-returned { ok:true } and spawned a repo-less agent). A
  // `repo_status='ready'` workspace with a PRESENT repoUrl but a NULL
  // installationId (the credential RPC denied/blipped — `repoUrl` is the
  // non-credential honest signal that a connection exists) must fail honestly,
  // emit the divergence op, and perform ZERO workspaces writes + NO clone.
  it("ready + .git ABSENT + install NULL + repoUrl PRESENT → divergence: NO spawn, { ok:false, errorCode:'repo_setup_failed' }, emits divergence, ZERO writes/clone", async () => {
    const seams = makeSeams({ gitDirExists: vi.fn(() => false) });
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "ready", installationId: null, repoUrl: REPO },
      seams,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.code).toBe("error");
      expect(r.errorCode).toBe("repo_setup_failed");
      // Membership-deny-aware copy — and it must NOT carry the unactionable
      // "Reconnect in Settings → Repository" CTA (a member denied by a
      // membership-gated credential read cannot fix it by reconnecting). This is
      // the whole point of the divergence path; guard against a future refactor
      // re-routing the message through `repoErrorMsg`.
      expect(r.message).toContain("ask the workspace owner");
      expect(r.message).not.toContain("Reconnect in Settings");
    }
    expect(seams.reportDivergence).toHaveBeenCalledTimes(1);
    // AC1b — zero workspaces writes (a removed/transient member must not corrupt
    // a healthy team workspace's repo_status for its Owners), and no clone
    // attempted (we have no install to clone with).
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
    expect(seams.claimCloneLock).not.toHaveBeenCalled();
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
  });

  // AC2/T2 — the must-not-over-fire control: genuinely not connected (repoUrl
  // empty, repo_status not_connected) still fast-path-returns ok and emits NO
  // divergence op.
  it("not_connected + .git ABSENT + install NULL + repoUrl EMPTY → genuinely not connected: { ok:true }, NO divergence emit", async () => {
    const seams = makeSeams({ gitDirExists: vi.fn(() => false) });
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "not_connected", installationId: null, repoUrl: "" },
      seams,
    );
    expect(r).toEqual({ ok: true });
    expect(seams.reportDivergence).not.toHaveBeenCalled();
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
  });

  // T5 — a recoverable-error workspace whose install is null + repoUrl present
  // still honest-blocks (it cannot recover without an install) but the cause is
  // now QUERYABLE via the divergence emit. Still ZERO workspaces writes.
  it("error + .git ABSENT + install NULL + repoUrl PRESENT → honest block { ok:false } + divergence emit, ZERO setRepoStatus", async () => {
    const seams = makeSeams({ gitDirExists: vi.fn(() => false) });
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "error", installationId: null, repoUrl: REPO },
      seams,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("error");
    expect(seams.reportDivergence).toHaveBeenCalledTimes(1);
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
  });

  it("AC7b regression: error entry STILL acquires claim_repo_clone_lock (herd guard not relaxed)", async () => {
    const seams = makeSeams({ gitDirExists: vi.fn(() => false) });
    await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "error" },
      seams,
    );
    expect(seams.claimCloneLock).toHaveBeenCalledWith(WS);
  });

  it("not_connected → { ok:true } fast path, no seam touched", async () => {
    const seams = makeSeams();
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "not_connected" },
      seams,
    );
    expect(r).toEqual({ ok: true });
    expect(seams.claimCloneLock).not.toHaveBeenCalled();
  });

  it("self-heal failed → setRepoStatus(error) + honest block { ok:false, code:'error' }", async () => {
    const seams = makeSeams({
      ensureWorkspaceRepoCloned: vi.fn(async () => "failed" as const),
    });
    const r = await resolveRepoReadinessWithSelfHeal(baseArgs(), seams);

    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("error");
    expect(seams.ensureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
    expect(seams.setRepoStatus).toHaveBeenCalledWith(WS, "error", expect.any(String));
  });

  it("no installation → honest block, NO clone attempt", async () => {
    const seams = makeSeams();
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), installationId: null },
      seams,
    );
    expect(r.ok).toBe(false);
    expect(seams.claimCloneLock).not.toHaveBeenCalled();
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
  });

  it("no repoUrl → honest block, NO clone attempt", async () => {
    const seams = makeSeams();
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), repoUrl: null },
      seams,
    );
    expect(r.ok).toBe(false);
    expect(seams.claimCloneLock).not.toHaveBeenCalled();
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
  });

  it(".git present → honest block, NO clone (cannot recover a .git-present workspace)", async () => {
    const seams = makeSeams({ gitDirExists: vi.fn(() => true) });
    const r = await resolveRepoReadinessWithSelfHeal(baseArgs(), seams);
    expect(r.ok).toBe(false);
    expect(seams.claimCloneLock).not.toHaveBeenCalled();
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
  });

  it("lock loser → { ok:false, code:'cloning' } honest-wait, NO ensureWorkspaceRepoCloned", async () => {
    const seams = makeSeams({ claimCloneLock: vi.fn(async () => false) });
    const r = await resolveRepoReadinessWithSelfHeal(baseArgs(), seams);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("cloning");
    expect(seams.claimCloneLock).toHaveBeenCalledTimes(1);
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
  });

  it("fresh cloning (not stale) → honest-wait unchanged, no lock attempt", async () => {
    const seams = makeSeams();
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "cloning" },
      seams,
    );
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("cloning");
    expect(seams.claimCloneLock).not.toHaveBeenCalled();
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
  });
});

describe("resolveRepoReadinessWithSelfHeal — AC1b (.git actually lands)", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "selfheal-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("AC1b — returns ok ONLY when a real .git actually lands on disk (not a stub)", async () => {
    // Genuine success-landing invariant: drive the orchestrator from a
    // .git-ABSENT workspace through a seam that performs a real on-disk landing
    // (mkdir .git, the same success sentinel the production
    // ensureWorkspaceRepoCloned renames into place), with gitDirExists reading
    // REAL disk. This proves r.ok is gated on .git genuinely existing — a stub
    // that returned "ok" while leaving .git absent would FAIL the final
    // existsSync assertion. Closes the proxy-vs-invariant gap: no network /
    // GitHub auth needed because the seam IS the landing.
    const wsPath = join(dir, "ws-heal");
    await mkdir(wsPath, { recursive: true });
    expect(existsSync(join(wsPath, ".git"))).toBe(false); // precondition

    const landingClone = vi.fn(async (a: { workspacePath: string }) => {
      await mkdir(join(a.workspacePath, ".git"), { recursive: true });
      return "ok" as const;
    });
    const seams = makeSeams({
      ensureWorkspaceRepoCloned: landingClone,
      gitDirExists: (p: string) => existsSync(join(p, ".git")), // real disk
    });

    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), workspacePath: wsPath },
      seams,
    );

    expect(landingClone).toHaveBeenCalledTimes(1);
    expect(seams.setRepoStatus).toHaveBeenCalledWith(WS, "ready", null);
    expect(r.ok).toBe(true); // dispatch proceeds
    // The load-bearing invariant: .git is REALLY on disk now (false → true).
    expect(existsSync(join(wsPath, ".git"))).toBe(true);
  });

  it("AC6b concurrency: two ready+.git-absent dispatches → at most one .git materializes AND the loser also ends ready (never {ok:true} with .git absent)", async () => {
    // Both cold dispatches pass existsSync→false and enter the LOCK-FREE graft.
    // The real ensureWorkspaceRepoCloned's .git-sentinel re-check
    // (ensure-workspace-repo.ts:239) guarantees at most one .git materializes;
    // the loser observes the winner's .git via the same sentinel and returns ok.
    // We model the landing with a shared seam that emulates the sentinel: the
    // first caller to find .git absent creates it; a later caller no-ops but the
    // .git the winner created is observed by gitDirExists → both return ok with
    // .git PRESENT. The invariant under test: neither returns {ok:true} while
    // .git is still absent.
    const wsPath = join(dir, "ws-race");
    await mkdir(wsPath, { recursive: true });
    expect(existsSync(join(wsPath, ".git"))).toBe(false);

    let landings = 0;
    const sentinelClone = vi.fn(async (a: { workspacePath: string }) => {
      // Emulate the per-attempt sentinel re-check with an ATOMIC create — the
      // real guarantee is ensure-workspace-repo.ts:239's randomUUID-temp-dir +
      // atomic rename, NOT an existsSync→await mkdir pair (that pair has a
      // TOCTOU window: under Promise.all the await yields, both callers observe
      // .git absent, and both increment `landings` → flaky `2`, seen in CI but
      // not locally). `mkdirSync` (no recursive) is atomic: exactly one caller
      // creates .git, the loser throws EEXIST and observes the winner's .git.
      try {
        mkdirSync(join(a.workspacePath, ".git"));
        landings += 1;
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code !== "EEXIST") throw err;
      }
      return "ok" as const;
    });
    const mkSeams = () =>
      makeSeams({
        ensureWorkspaceRepoCloned: sentinelClone,
        gitDirExists: (p: string) => existsSync(join(p, ".git")),
      });

    const [a, b] = await Promise.all([
      resolveRepoReadinessWithSelfHeal(
        { ...baseArgs(), status: "ready", workspacePath: wsPath },
        mkSeams(),
      ),
      resolveRepoReadinessWithSelfHeal(
        { ...baseArgs(), status: "ready", workspacePath: wsPath },
        mkSeams(),
      ),
    ]);

    // At most one .git materialization (winner).
    expect(landings).toBe(1);
    // Both terminate ready WITH .git present — never {ok:true} with .git absent.
    expect(a).toEqual({ ok: true });
    expect(b).toEqual({ ok: true });
    expect(existsSync(join(wsPath, ".git"))).toBe(true);
  });

  it("AC8: corrupt .git (existsSync true, NOT a valid work tree) + ready → routes to corrupt recovery, re-clone SUCCEEDS → { ok:true } + recovered emit (NOT silent over a corrupt tree)", async () => {
    // FLIPPED RESIDUAL (2026-06-19): a directory named .git that is NOT a valid
    // git work tree (bare `mkdir .git`, no HEAD/objects) used to read `true` from
    // the presence-only `existsSync` gate → fast-path `{ok:true}` over a corrupt
    // tree → repo-less agent spawn. Now the VALIDITY gate (`gitDirValid` real)
    // classifies it invalid → corrupt-worktree graft. The clone seam emulates a
    // successful rm+reclone landing a valid tree.
    const wsPath = join(dir, "ws-stale-git");
    await mkdir(join(wsPath, ".git"), { recursive: true }); // present but INVALID (no HEAD/objects)
    expect(isValidGitWorkTree(wsPath)).toBe(false); // precondition: structurally invalid

    const landingClone = vi.fn(async (a: { workspacePath: string }) => {
      // Emulate ensureWorkspaceRepoCloned's rm-corrupt + re-clone landing a valid tree.
      await rm(join(a.workspacePath, ".git"), { recursive: true, force: true });
      await mkdir(join(a.workspacePath, ".git", "objects"), { recursive: true });
      await mkdir(join(a.workspacePath, ".git"), { recursive: true });
      // write a HEAD so the result is structurally valid
      await import("node:fs/promises").then((fs) =>
        fs.writeFile(join(a.workspacePath, ".git", "HEAD"), "ref: refs/heads/main\n"),
      );
      return "ok" as const;
    });
    const seams = makeSeams({
      ensureWorkspaceRepoCloned: landingClone,
      gitDirExists: (p: string) => existsSync(join(p, ".git")),
      gitDirValid: (p: string) => isValidGitWorkTree(p),
    });

    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "ready", workspacePath: wsPath },
      seams,
    );
    // Corrupt → recovery attempted (NOT silent fast-path), re-clone succeeded.
    expect(landingClone).toHaveBeenCalledTimes(1);
    expect(r).toEqual({ ok: true });
    expect(isValidGitWorkTree(wsPath)).toBe(true); // a VALID tree now on disk
    // F4: the ready entry never writes status (no member-row corruption).
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
    // F5/F7: emitted the corrupt op as recovered.
    expect(seams.reportDivergence).toHaveBeenCalledWith(
      "corrupt-worktree-at-dispatch",
      USER,
      WS,
      true,
    );
  });

  it("AC8/AC14: corrupt .git + ready, re-clone FAILS → honest block { ok:false } + unrecovered (paging) emit, ZERO setRepoStatus (member-safe)", async () => {
    const wsPath = join(dir, "ws-corrupt-fail");
    await mkdir(join(wsPath, ".git"), { recursive: true });
    const failClone = vi.fn(async () => "failed" as const);
    const seams = makeSeams({
      ensureWorkspaceRepoCloned: failClone,
      gitDirExists: (p: string) => existsSync(join(p, ".git")),
      gitDirValid: (p: string) => isValidGitWorkTree(p),
    });

    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "ready", workspacePath: wsPath },
      seams,
    );
    expect(failClone).toHaveBeenCalledTimes(1);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.code).toBe("error");
    // F4: a member-triggered corrupt recovery FAILURE must NOT write the owner's
    // repo_status (emit-only honest block).
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
    expect(seams.reportDivergence).toHaveBeenCalledWith(
      "corrupt-worktree-at-dispatch",
      USER,
      WS,
      false,
    );
  });

  it(".git-present guard reads real disk → honest block, no clone attempted", async () => {
    // Complementary to AC1b: a workspace that ALREADY has a real .git must NOT
    // be re-cloned — the orchestrator honest-blocks via the .git-present guard
    // (ensure-workspace-repo.ts:142). Proves gitDirExists observes real disk.
    const wsPath = join(dir, "ws-present");
    await mkdir(join(wsPath, ".git"), { recursive: true });

    const seams = makeSeams({
      ensureWorkspaceRepoCloned,
      gitDirExists: (p: string) => existsSync(join(p, ".git")),
    });

    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), workspacePath: wsPath },
      seams,
    );
    expect(r.ok).toBe(false); // .git present → cannot self-heal, honest block
    expect(existsSync(join(wsPath, ".git"))).toBe(true);
  });
});
