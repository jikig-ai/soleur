import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";

// #8211 PR-B2, CTO ruling: the erasure-ledger write is gated on ARMING (GIT_REMOVE_SSH_PRIVATE_KEY,
// or the provision key / GIT_DATA_SSH_HOST when the remove key is absent), NOT on
// GIT_DATA_STORE_ENABLED. This is intended design: a bare repo provisioned in a flag-on window
// persists after a rollback, so an armed env at flag-off must still erase and, on any non-erased
// outcome, ledger the owed erasure for the re-drive.
//
// Unlike account-delete-git-data-ledger.test.ts (which mocks removeGitDataRepo to pin the write
// matrix per outcome), this file runs the REAL removeGitDataRepo behind deleteAccount and only fakes
// the ssh transport, so the arming decision itself is under test: dropping the "not gated on the
// flag" behaviour, or adding a flag gate to the ledger write, turns these red.

const TEST_PIN = makeEd25519Pin();
const mockFrom = vi.fn();
const mockRpc = vi.fn();
const mockAuth = { admin: { getUserById: vi.fn(), deleteUser: vi.fn() } };
const mockStorageFrom = vi.fn();
const sshRemote = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: mockFrom, rpc: mockRpc, auth: mockAuth, storage: { from: mockStorageFrom } }),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: vi.fn() })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("@/server/agent-runner", () => ({ abortAllUserSessions: vi.fn() }));
vi.mock("@/server/workspace", () => ({
  deleteWorkspace: vi.fn().mockResolvedValue(undefined),
  purgeWorkspaceLogoObjects: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("../server/git-auth", () => ({
  gitWithPrivateKeyAuth: vi.fn(),
  sshWithPrivateKeyAuth: (...args: unknown[]) => sshRemote(...args),
}));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));

import { deleteAccount } from "../server/account-delete";

const UID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const LEDGER_RPC = "record_git_data_erasure_pending";
const ledgerCalls = () => mockRpc.mock.calls.filter((c) => c[0] === LEDGER_RPC);

function setup() {
  mockAuth.admin.getUserById.mockResolvedValue({ data: { user: { id: UID, email: "t@example.test" } }, error: null });
  mockAuth.admin.deleteUser.mockResolvedValue({ data: {}, error: null });
  mockStorageFrom.mockReturnValue({
    list: vi.fn().mockResolvedValue({ data: [], error: null }),
    remove: vi.fn().mockResolvedValue({ data: [], error: null }),
  });
  mockFrom.mockImplementation(() => ({
    update: () => ({ eq: () => ({ in: () => Promise.resolve({ error: null }) }) }),
    delete: () => ({ eq: () => Promise.resolve({ error: null }) }),
    select: () => ({ eq: () => Promise.resolve({ count: 1, data: [], error: null }) }),
  }));
  mockRpc.mockResolvedValue({ data: 0, error: null });
}

// ssh exit 255 with no recognised stderr: the host did not answer => `unreachable`.
const sshUnreachable = () =>
  Object.assign(new Error("Command failed with exit code 255"), { code: 255, stderr: "ssh: connect to host: Connection timed out" });

describe("deleteAccount ledger write is gated on arming, not on GIT_DATA_STORE_ENABLED (#8211, CTO ruling)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    setup();
    sshRemote.mockReset().mockResolvedValue(Buffer.from(""));
    vi.stubEnv("GIT_DATA_STORE_ENABLED", ""); // flag OFF in every row
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", TEST_PIN);
  });
  afterEach(() => vi.unstubAllEnvs());

  it("flag OFF + armed (REMOVE key) + unreachable: the erase is attempted and a ledger row is written", async () => {
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "remove-key");
    sshRemote.mockRejectedValue(sshUnreachable());
    const result = await deleteAccount(UID, "t@example.test");
    expect(sshRemote).toHaveBeenCalledTimes(1);
    expect(result).toEqual({ success: true, gitDataErasurePending: true });
    expect(ledgerCalls()).toEqual([[LEDGER_RPC, { p_workspace_id: UID, p_outcome: "unreachable" }]]);
  });

  it("flag OFF + armed + ssh client absent (`unconfigured`): still ledgered", async () => {
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "remove-key");
    sshRemote.mockRejectedValue(Object.assign(new Error("spawn ssh ENOENT"), { code: "ENOENT", syscall: "spawn ssh" }));
    await deleteAccount(UID, "t@example.test");
    expect(ledgerCalls()).toEqual([[LEDGER_RPC, { p_workspace_id: UID, p_outcome: "unconfigured" }]]);
  });

  it("flag OFF + armed by the PROVISION key only (REMOVE key absent): `unconfigured` remove_key_absent is ledgered, nothing dialed", async () => {
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "");
    vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "provision-key");
    await deleteAccount(UID, "t@example.test");
    expect(sshRemote).not.toHaveBeenCalled();
    expect(ledgerCalls()).toEqual([[LEDGER_RPC, { p_workspace_id: UID, p_outcome: "unconfigured" }]]);
  });

  it("flag OFF + unarmed (no REMOVE key, no provision key, no host): `skipped` writes NO ledger row and dials nothing", async () => {
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "");
    vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "");
    vi.stubEnv("GIT_DATA_SSH_HOST", "");
    const result = await deleteAccount(UID, "t@example.test");
    expect(sshRemote).not.toHaveBeenCalled();
    expect(result).toEqual({ success: true });
    expect(ledgerCalls()).toHaveLength(0);
  });

  it("flag OFF + armed + erased: the repo is erased and NO ledger row is written", async () => {
    vi.stubEnv("GIT_REMOVE_SSH_PRIVATE_KEY", "remove-key");
    const result = await deleteAccount(UID, "t@example.test");
    expect(sshRemote).toHaveBeenCalledTimes(1);
    expect(result).toEqual({ success: true });
    expect(ledgerCalls()).toHaveLength(0);
  });
});
