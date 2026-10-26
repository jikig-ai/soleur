// Wire check for #8211 PR-G: every app path that reads one of the three git-data SSH key
// variables hands the transport helper the NORMALISED (multi-line) key when the env holds
// the docker env-file form. Reverting a call site to a bare env read reds the matching row.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";
import { makeMultilineKey, toDockerForm } from "./helpers/git-data-key-fixture";

const TEST_PIN = makeEd25519Pin();
const KEY = makeMultilineKey().trim();
const DOCKER = toDockerForm(KEY);

const gitTransport = vi.fn().mockResolvedValue(Buffer.from(""));
const sshProvision = vi.fn().mockResolvedValue(Buffer.from(""));
const execFileSyncMock = vi.fn((..._args: unknown[]) => Buffer.from(""));
const rpcMock = vi.fn(async () => ({ data: true, error: null }));

vi.mock("@/server/git-auth", () => ({
  gitWithPrivateKeyAuth: (...args: unknown[]) => gitTransport(...args),
  sshWithPrivateKeyAuth: (...args: unknown[]) => sshProvision(...args),
}));
vi.mock("../server/git-auth", () => ({
  gitWithPrivateKeyAuth: (...args: unknown[]) => gitTransport(...args),
  sshWithPrivateKeyAuth: (...args: unknown[]) => sshProvision(...args),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: rpcMock })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("child_process")>()),
  execFileSync: (...args: unknown[]) => execFileSyncMock(...args),
}));

import { fetchFromGitData } from "@/server/git-data-client";
import {
  provisionGitDataRepo,
  removeGitDataRepo,
  replicateToGitData,
} from "@/server/git-data-replication";

const WS = "11111111-1111-1111-1111-111111111111";
const WT = "33333333-3333-3333-3333-333333333333";
const USER = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";

beforeEach(() => {
  gitTransport.mockClear().mockResolvedValue(Buffer.from(""));
  sshProvision.mockClear().mockResolvedValue(Buffer.from(""));
  execFileSyncMock.mockClear().mockReturnValue(Buffer.from(""));
  vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
  vi.stubEnv("GIT_DATA_SSH_HOST_KEY", TEST_PIN);
  vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", DOCKER);
  vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", DOCKER);
  vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", DOCKER);
});
afterEach(() => vi.unstubAllEnvs());

describe("docker-format key env -> the transport helpers receive the multi-line key (#8211 PR-G)", () => {
  it("fixture: the env value really is one line", () => {
    expect(DOCKER.includes("\n")).toBe(false);
    expect(KEY.split("\n").length).toBeGreaterThanOrEqual(3);
  });

  it("fetchFromGitData (git-data-client) passes the normalised TRANSPORT key", async () => {
    await fetchFromGitData({ userId: USER, workspaceId: WS, worktreeId: WT, workspacePath: "/tmp/ws" });
    expect(gitTransport).toHaveBeenCalledTimes(1);
    expect(gitTransport.mock.calls[0][1]).toBe(KEY);
  });

  it("provisionGitDataRepo passes the normalised PROVISION key", async () => {
    await provisionGitDataRepo(WS);
    expect(sshProvision).toHaveBeenCalledTimes(1);
    expect(sshProvision.mock.calls[0][2]).toBe(KEY);
  });

  it("removeGitDataRepo (Art. 17) passes the normalised REMOVE key", async () => {
    await removeGitDataRepo(WS);
    expect(sshProvision).toHaveBeenCalledTimes(1);
    expect(sshProvision.mock.calls[0][2]).toBe(KEY);
  });

  it("replicateToGitData passes the normalised PROVISION key to the provision dial and the normalised TRANSPORT key to the push", async () => {
    await replicateToGitData({
      workspacePath: "/tmp/ws",
      workspaceId: WS,
      worktreeId: WT,
      leaseGeneration: 4,
      userId: USER,
    });
    expect(sshProvision.mock.calls[0][2]).toBe(KEY);
    expect(gitTransport.mock.calls[0][1]).toBe(KEY);
  });

  it("a real-newline key in the env reaches the helpers unchanged", async () => {
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", KEY);
    await removeGitDataRepo(WS);
    expect(sshProvision.mock.calls[0][2]).toBe(KEY);
  });

  it("the armed predicate still reads a docker-format remove key as present (no skipped/unconfigured flip)", async () => {
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "");
    vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", DOCKER);
    await expect(removeGitDataRepo(WS)).resolves.toMatchObject({ status: "unconfigured" });
    expect(sshProvision).not.toHaveBeenCalled();
  });
});
