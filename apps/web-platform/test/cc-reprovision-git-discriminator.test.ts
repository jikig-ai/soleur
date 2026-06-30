// #5715 / ADR-044 2026-06-19 — GENUINE unmocked `.git` VALIDITY discriminator
// (honors plan AC2/AC4 intent).
//
// The sibling `cc-reprovision.test.ts` mocks `node:fs` wholesale (vitest hoists
// `vi.mock("node:fs", …)` to file top), so its mock is a stand-in — nothing in
// that file exercises the REAL `isValidGitWorkTree(workspacePath)` short-circuit.
// This file mocks ONLY the resolver inputs that feed
// `reprovisionWorkspaceOnDispatch` and points them at a REAL tmpdir, leaving
// `node:fs` REAL so the production validity probe is the actual discriminator
// under test (validity-not-presence):
//   (a) tmpdir WITH a VALID `<dir>/.git/` (HEAD + objects/) → valid → early-return
//                                     "ok", `ensureWorkspaceRepoCloned` NOT called.
//   (b) tmpdir WITHOUT `.git`      → not valid → fall through to
//                                     `ensureWorkspaceRepoCloned`.
//   (c) tmpdir WITH a CORRUPT `.git/` (bare dir, no HEAD/objects) → not valid →
//                                     fall through to `ensureWorkspaceRepoCloned`
//                                     (the warm-path fix: a corrupt `.git` no
//                                     longer short-circuits "ok").
// Non-vacuity: if the short-circuit were removed, case (a) would call
// `ensureWorkspaceRepoCloned` and the assertion would fail; if validity collapsed
// back to mere presence, case (c) would short-circuit and ITS assertion fails.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";

const {
  mockFetchUserWorkspacePath,
  mockResolveInstallationId,
  mockGetCurrentRepoUrl,
  mockResolveEffectiveInstallationId,
  mockEnsureWorkspaceRepoCloned,
  mockReportSilentFallback,
  mockGetFreshTenantClient,
  mockResolveActiveWorkspace,
} = vi.hoisted(() => ({
  mockFetchUserWorkspacePath: vi.fn(),
  mockResolveInstallationId: vi.fn(),
  mockGetCurrentRepoUrl: vi.fn(),
  mockResolveEffectiveInstallationId: vi.fn(),
  mockEnsureWorkspaceRepoCloned: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockGetFreshTenantClient: vi.fn(),
  mockResolveActiveWorkspace: vi.fn(),
}));

// NOTE: `node:fs` is DELIBERATELY left REAL — the whole point of this file is
// the genuine `existsSync` stat. Only the resolver seams are mocked.
vi.mock("@/server/kb-document-resolver", () => ({
  fetchUserWorkspacePath: mockFetchUserWorkspacePath,
}));
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));
vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: mockGetCurrentRepoUrl,
}));
vi.mock("@/server/cc-effective-installation", () => ({
  resolveEffectiveInstallationId: mockResolveEffectiveInstallationId,
}));
vi.mock("@/server/ensure-workspace-repo", () => ({
  ensureWorkspaceRepoCloned: mockEnsureWorkspaceRepoCloned,
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
}));
vi.mock("@/server/workspace-resolver", () => ({
  resolveActiveWorkspace: mockResolveActiveWorkspace,
}));

import { reprovisionWorkspaceOnDispatch } from "@/server/cc-reprovision";

const USER = "user-1";
const ACTIVE = "ws-active-id";
const REPO = "https://github.com/acme/widget";
const INSTALL = 4242;

const createdDirs: string[] = [];

/**
 * A real tmpdir under os.tmpdir(); `git` controls the on-disk `.git` shape:
 *   - "valid"   → `.git/` dir with BOTH `HEAD` and `objects/` (isValidGitWorkTree
 *                 returns true — an ordinary repo / Start-Fresh `git init`).
 *   - "corrupt" → bare `mkdir .git` (no HEAD/objects → isValidGitWorkTree false).
 *   - "none"    → no `.git` at all.
 */
function realWorkspace({ git }: { git: "valid" | "corrupt" | "none" }): string {
  const dir = mkdtempSync(join(tmpdir(), "cc-reprovision-discriminator-"));
  createdDirs.push(dir);
  if (git !== "none") {
    const gitDir = join(dir, ".git");
    mkdirSync(gitDir);
    if (git === "valid") {
      // A REAL `git init` repo (HEAD+objects) so isValidGitWorkTree passes AND the
      // #5733 host `git rev-parse --is-inside-work-tree` confirm deterministically
      // returns "worktree" → the warm gate short-circuits "ok" (a synthetic
      // HEAD+objects-but-no-refs `.git` would be git-version-dependent).
      execFileSync("git", ["-C", dir, "init", "-q"]);
    }
  }
  return dir;
}

beforeEach(() => {
  vi.clearAllMocks();
  mockGetFreshTenantClient.mockResolvedValue({});
  mockResolveActiveWorkspace.mockResolvedValue({ ok: true, workspaceId: ACTIVE });
  mockResolveInstallationId.mockResolvedValue(INSTALL);
  mockGetCurrentRepoUrl.mockResolvedValue(REPO);
  mockResolveEffectiveInstallationId.mockImplementation(
    async ({ installationId }: { installationId: number | null }) => installationId,
  );
  mockEnsureWorkspaceRepoCloned.mockResolvedValue("ok");
});

afterEach(() => {
  for (const dir of createdDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

describe("reprovisionWorkspaceOnDispatch — genuine unmocked `.git` validity discriminator (#5715 / ADR-044)", () => {
  it("(a) real tmpdir WITH a VALID `.git/` (HEAD+objects) → isValidGitWorkTree short-circuits to 'ok', NO clone", async () => {
    const ws = realWorkspace({ git: "valid" });
    mockFetchUserWorkspacePath.mockResolvedValue(ws);

    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");

    // The REAL `isValidGitWorkTree(ws)` fired and short-circuited the heavy
    // resolves + the clone. Non-vacuous: removing the short-circuit would call
    // ensureWorkspaceRepoCloned here.
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(mockResolveInstallationId).not.toHaveBeenCalled();
    expect(mockResolveEffectiveInstallationId).not.toHaveBeenCalled();
    // #5733 — the lstat-ready branch now resolves repoUrl to SCOPE the host
    // `rev-parse` confirm to connected workspaces, so getCurrentRepoUrl IS called;
    // the real confirm returned "worktree" so the turn still short-circuits "ok".
    expect(mockGetCurrentRepoUrl).toHaveBeenCalledTimes(1);
  });

  it("(b) real tmpdir WITHOUT `.git` → not valid → falls through to clone", async () => {
    const ws = realWorkspace({ git: "none" });
    mockFetchUserWorkspacePath.mockResolvedValue(ws);

    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");

    // No `.git` on disk → the real validity probe returns false → the recovery
    // proceeds to the clone with the resolved/promoted inputs.
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith({
      userId: USER,
      workspacePath: ws,
      installationId: INSTALL,
      repoUrl: REPO,
    });
  });

  it("(c) real tmpdir WITH a CORRUPT `.git/` (no HEAD/objects) → not valid → falls through to clone (warm-path fix)", async () => {
    const ws = realWorkspace({ git: "corrupt" });
    mockFetchUserWorkspacePath.mockResolvedValue(ws);

    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");

    // A corrupt `.git` is PRESENT but NOT a valid work tree. The old presence
    // short-circuit would have returned "ok" and stranded the agent in a corrupt
    // repo; validity-not-presence routes it to the (validity-aware) clone instead.
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith({
      userId: USER,
      workspacePath: ws,
      installationId: INSTALL,
      repoUrl: REPO,
    });
  });
});
