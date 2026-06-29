// #5715 — GENUINE unmocked `existsSync` `.git` discriminator (honors plan
// AC2/AC4 intent).
//
// The sibling `cc-reprovision.test.ts` mocks `node:fs` wholesale (vitest hoists
// `vi.mock("node:fs", …)` to file top), so its `mockExistsSync` is a stand-in —
// nothing in that file exercises the REAL
// `existsSync(join(workspacePath, ".git"))` short-circuit. This file mocks ONLY
// the resolver inputs that feed `reprovisionWorkspaceOnDispatch` and points them
// at a REAL tmpdir, leaving `node:fs` REAL so the production `existsSync` stat
// is the actual discriminator under test:
//   (a) tmpdir WITH `<dir>/.git/`  → real `existsSync` true  → early-return "ok",
//                                     `ensureWorkspaceRepoCloned` NOT called.
//   (b) tmpdir WITHOUT `.git`      → real `existsSync` false → fall through to
//                                     `ensureWorkspaceRepoCloned`.
// Non-vacuity: if the short-circuit were removed, case (a) would call
// `ensureWorkspaceRepoCloned` and the assertion would fail.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, mkdirSync, rmSync } from "node:fs";
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

/** A real tmpdir under os.tmpdir(); optionally with a real `.git/` subdir. */
function realWorkspace({ withGit }: { withGit: boolean }): string {
  const dir = mkdtempSync(join(tmpdir(), "cc-reprovision-discriminator-"));
  createdDirs.push(dir);
  if (withGit) mkdirSync(join(dir, ".git"));
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

describe("reprovisionWorkspaceOnDispatch — genuine unmocked `.git` discriminator (#5715)", () => {
  it("(a) real tmpdir WITH `.git/` → real existsSync short-circuits to 'ok', NO clone", async () => {
    const ws = realWorkspace({ withGit: true });
    mockFetchUserWorkspacePath.mockResolvedValue(ws);

    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");

    // The REAL `existsSync(join(ws, ".git"))` fired and short-circuited the heavy
    // resolves + the clone. Non-vacuous: removing the short-circuit would call
    // ensureWorkspaceRepoCloned here.
    expect(mockEnsureWorkspaceRepoCloned).not.toHaveBeenCalled();
    expect(mockResolveInstallationId).not.toHaveBeenCalled();
    expect(mockGetCurrentRepoUrl).not.toHaveBeenCalled();
    expect(mockResolveEffectiveInstallationId).not.toHaveBeenCalled();
  });

  it("(b) real tmpdir WITHOUT `.git` → real existsSync false → falls through to clone", async () => {
    const ws = realWorkspace({ withGit: false });
    mockFetchUserWorkspacePath.mockResolvedValue(ws);

    await expect(reprovisionWorkspaceOnDispatch(USER)).resolves.toBe("ok");

    // No `.git` on disk → the real stat returns false → the recovery proceeds to
    // the clone with the resolved/promoted inputs.
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledTimes(1);
    expect(mockEnsureWorkspaceRepoCloned).toHaveBeenCalledWith({
      userId: USER,
      workspacePath: ws,
      installationId: INSTALL,
      repoUrl: REPO,
    });
  });
});
