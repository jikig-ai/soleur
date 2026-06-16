import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { existsSync } from "node:fs";
import { mkdtemp, rm, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  resolveRepoReadinessWithSelfHeal,
  type RepoSelfHealSeams,
} from "@/server/repo-readiness-self-heal";
import { evaluateRepoReadiness } from "@/server/repo-readiness";
import { ensureWorkspaceRepoCloned } from "@/server/ensure-workspace-repo";

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

  it("ready → { ok:true }, no seam touched (unchanged happy path)", async () => {
    const seams = makeSeams();
    const r = await resolveRepoReadinessWithSelfHeal(
      { ...baseArgs(), status: "ready" },
      seams,
    );
    expect(r).toEqual({ ok: true });
    expect(seams.claimCloneLock).not.toHaveBeenCalled();
    expect(seams.ensureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(seams.setRepoStatus).not.toHaveBeenCalled();
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
