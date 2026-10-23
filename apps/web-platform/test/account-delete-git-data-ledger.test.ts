import { describe, test, expect, vi, beforeEach } from "vitest";

// #8211 PR-B2: account deletion records every non-erased git-data erasure outcome in the durable
// pending ledger (record_git_data_erasure_pending), so the re-drive cron can finish the erasure.
// Pins: which outcomes write; that a failing ledger write NEVER changes the response or the
// existing Sentry report (the `art17_erasure_incomplete` rule filters on feature/op/tags).

const mockFrom = vi.fn();
const mockRpc = vi.fn();
const mockAuth = { admin: { getUserById: vi.fn(), deleteUser: vi.fn() } };
const mockStorageFrom = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ from: mockFrom, rpc: mockRpc, auth: mockAuth, storage: { from: mockStorageFrom } }),
}));
vi.mock("@/server/agent-runner", () => ({ abortAllUserSessions: vi.fn() }));
vi.mock("@/server/workspace", () => ({
  deleteWorkspace: vi.fn().mockResolvedValue(undefined),
  purgeWorkspaceLogoObjects: vi.fn().mockResolvedValue(undefined),
}));
const mockRemoveGitDataRepo = vi.fn();
vi.mock("@/server/git-data-replication", () => ({
  removeGitDataRepo: (...args: unknown[]) => mockRemoveGitDataRepo(...args),
}));
const mockReport = vi.fn();
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: (...args: unknown[]) => mockReport(...args),
}));

import { ART17_ERASURE_FEATURE, ART17_ERASURE_OP, deleteAccount } from "../server/account-delete";
import type { GitDataErasureOutcome } from "../server/git-data-replication";

const UID = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const LEDGER_RPC = "record_git_data_erasure_pending";

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

const ledgerCalls = () => mockRpc.mock.calls.filter((c) => c[0] === LEDGER_RPC);
const art17Calls = () =>
  mockReport.mock.calls.filter((c) => (c[1] as { op?: string }).op === ART17_ERASURE_OP);

const NON_ERASED: Record<string, GitDataErasureOutcome> = {
  refused: { status: "refused", exitCode: 3, detail: "refusing" },
  unreachable: { status: "unreachable", detail: "no route" },
  unauthorized: { status: "unauthorized", detail: "Permission denied (publickey)" },
  unconfigured: { status: "unconfigured", detail: "pin_absent: unset" },
  host_key_mismatch: { status: "host_key_mismatch", detail: "changed key" },
};

describe("deleteAccount -> git-data erasure pending ledger (#8211)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockReport.mockReset();
    setup();
  });

  for (const [word, outcome] of Object.entries(NON_ERASED)) {
    test(`${word}: records the id with outcome '${word}' and the response stays pending`, async () => {
      mockRemoveGitDataRepo.mockResolvedValue(outcome);
      const result = await deleteAccount(UID, "t@example.test");
      expect(result).toEqual({ success: true, gitDataErasurePending: true });
      expect(ledgerCalls()).toEqual([[LEDGER_RPC, { p_workspace_id: UID, p_outcome: word }]]);
    });
  }

  test("the ledger write comes AFTER the art17 Sentry report (a ledger fault can never precede or alter it)", async () => {
    const order: string[] = [];
    mockReport.mockImplementation((_e: unknown, opts: { op?: string }) => {
      order.push(`report:${opts.op}`);
    });
    mockRpc.mockImplementation(async (name: string) => {
      order.push(`rpc:${name}`);
      return { data: 0, error: null };
    });
    mockRemoveGitDataRepo.mockResolvedValue(NON_ERASED.refused);
    await deleteAccount(UID, "t@example.test");
    expect(order.indexOf(`report:${ART17_ERASURE_OP}`)).toBeGreaterThan(-1);
    expect(order.indexOf(`rpc:${LEDGER_RPC}`)).toBeGreaterThan(order.indexOf(`report:${ART17_ERASURE_OP}`));
  });

  test("a thrown removeGitDataRepo records outcome 'threw' (the spelling of its erasure_outcome tag)", async () => {
    mockRemoveGitDataRepo.mockRejectedValue(new Error("boom"));
    const result = await deleteAccount(UID, "t@example.test");
    expect(result).toEqual({ success: true, gitDataErasurePending: true });
    expect(ledgerCalls()).toEqual([[LEDGER_RPC, { p_workspace_id: UID, p_outcome: "threw" }]]);
  });

  test.each([["erased", { status: "erased" }], ["skipped", { status: "skipped" }]] as const)(
    "%s: nothing is recorded",
    async (_n, outcome) => {
      mockRemoveGitDataRepo.mockResolvedValue(outcome);
      const result = await deleteAccount(UID, "t@example.test");
      expect(result).toEqual({ success: true });
      expect(ledgerCalls()).toHaveLength(0);
    },
  );

  for (const mode of ["rpc-error", "rpc-throws", "rpc-rejects-non-error"] as const) {
    test(`ledger write failure (${mode}) changes neither the response, the cascade nor the art17 Sentry report`, async () => {
      mockRemoveGitDataRepo.mockResolvedValue(NON_ERASED.refused);
      await deleteAccount(UID, "t@example.test");
      const baselineArt17 = JSON.stringify(art17Calls());
      expect(art17Calls()).toHaveLength(1);

      vi.clearAllMocks();
      setup();
      mockRemoveGitDataRepo.mockResolvedValue(NON_ERASED.refused);
      mockRpc.mockImplementation(async (name: string) => {
        if (name !== LEDGER_RPC) return { data: 0, error: null };
        if (mode === "rpc-error") return { data: null, error: { message: "db down", code: "08006" } };
        if (mode === "rpc-throws") throw new Error("socket hang up");
        throw "weird";
      });
      const result = await deleteAccount(UID, "t@example.test");

      expect(result).toEqual({ success: true, gitDataErasurePending: true });
      expect(mockAuth.admin.deleteUser).toHaveBeenCalledTimes(1); // the cascade ran to the end
      expect(JSON.stringify(art17Calls())).toBe(baselineArt17); // byte-identical feature/op/tags/extra/message
      expect(art17Calls()[0][1]).toMatchObject({
        feature: ART17_ERASURE_FEATURE,
        op: ART17_ERASURE_OP,
        tags: { erasure_outcome: "refused" },
      });
      // the failed write is itself reported, under a DIFFERENT feature/op, carrying the id only
      // as gitDataRepoId (never as userId)
      const ledgerReport = mockReport.mock.calls.find((c) => (c[1] as { op?: string }).op === "record-pending");
      expect(ledgerReport).toBeDefined();
      expect((ledgerReport![1] as { feature: string }).feature).toBe("git-data-erasure-ledger");
      expect((ledgerReport![1] as { extra: Record<string, unknown> }).extra).toMatchObject({ gitDataRepoId: UID });
      expect((ledgerReport![1] as { extra: Record<string, unknown> }).extra).not.toHaveProperty("userId");
    });
  }

  test("the thrown arm's failing ledger write also leaves the art17 report untouched", async () => {
    mockRemoveGitDataRepo.mockRejectedValue(new Error("boom"));
    mockRpc.mockImplementation(async (name: string) => {
      if (name === LEDGER_RPC) throw new Error("db down");
      return { data: 0, error: null };
    });
    const result = await deleteAccount(UID, "t@example.test");
    expect(result).toEqual({ success: true, gitDataErasurePending: true });
    // the FULL option bag, byte for byte (toMatchObject would let an added/renamed tag through)
    expect(art17Calls()[0][1]).toEqual({
      feature: ART17_ERASURE_FEATURE,
      op: ART17_ERASURE_OP,
      tags: { erasure_outcome: "threw" },
      extra: { userId: UID, gitDataRepoId: UID, errorName: "Error" },
      message:
        "git-data erasure threw: removeGitDataRepo threw during Art. 17 deletion — bare repo may " +
        "persist on the git-data host",
    });
  });

  test("the 'unconfigured' arm keeps its full tag set (erasure_reason) byte for byte when the ledger write fails", async () => {
    mockRemoveGitDataRepo.mockResolvedValue({ status: "unconfigured", detail: "pin_absent: GIT_DATA_SSH_HOST_KEY is unset" });
    mockRpc.mockImplementation(async (name: string) => {
      if (name === LEDGER_RPC) throw new Error("db down");
      return { data: 0, error: null };
    });
    await deleteAccount(UID, "t@example.test");
    expect(art17Calls()).toHaveLength(1);
    expect(art17Calls()[0][1]).toEqual({
      feature: ART17_ERASURE_FEATURE,
      op: ART17_ERASURE_OP,
      tags: { erasure_outcome: "unconfigured", erasure_reason: "pin_absent" },
      extra: { userId: UID, gitDataRepoId: UID, detail: "pin_absent: GIT_DATA_SSH_HOST_KEY is unset" },
      message:
        "git-data erasure unconfigured (pin_absent): bare-repo erasure did not complete during Art. 17 deletion — the repo may persist on the git-data host",
    });
    expect(ledgerCalls()).toEqual([[LEDGER_RPC, { p_workspace_id: UID, p_outcome: "unconfigured" }]]);
  });

  test("the Sentry report of a failed ledger write may itself throw without reaching the caller", async () => {
    mockRemoveGitDataRepo.mockResolvedValue(NON_ERASED.refused);
    mockRpc.mockImplementation(async (name: string) => {
      if (name === LEDGER_RPC) throw new Error("db down");
      return { data: 0, error: null };
    });
    let armed = true;
    mockReport.mockImplementation((_e: unknown, opts: { op?: string }) => {
      if (armed && opts.op === "record-pending") {
        armed = false;
        throw new Error("sentry transport exploded");
      }
    });
    const result = await deleteAccount(UID, "t@example.test");
    expect(result).toEqual({ success: true, gitDataErasurePending: true });
    expect(armed).toBe(false); // the throwing path really ran
    expect(mockAuth.admin.deleteUser).toHaveBeenCalledTimes(1);
    // The ledger write sits INSIDE the arm's try: a leaked rejection would be caught by the throw arm
    // and mint a SECOND, wrong art17 event (erasure_outcome=threw). Exactly one event, the refusal.
    expect(art17Calls()).toHaveLength(1);
    expect((art17Calls()[0][1] as { tags: Record<string, string> }).tags).toEqual({ erasure_outcome: "refused" });
  });

  test("a HUNG ledger RPC cannot stall the cascade: after 5 s the write is abandoned, reported, and the response is unchanged", async () => {
    vi.useFakeTimers();
    try {
      mockRemoveGitDataRepo.mockResolvedValue(NON_ERASED.refused);
      mockRpc.mockImplementation((name: string) =>
        name === LEDGER_RPC ? new Promise(() => {}) : Promise.resolve({ data: 0, error: null }),
      );
      const pending = deleteAccount(UID, "t@example.test");
      await vi.advanceTimersByTimeAsync(4_999);
      expect(mockAuth.admin.deleteUser).not.toHaveBeenCalled(); // still waiting inside the bound
      await vi.advanceTimersByTimeAsync(2);
      const result = await pending;
      expect(result).toEqual({ success: true, gitDataErasurePending: true });
      expect(mockAuth.admin.deleteUser).toHaveBeenCalledTimes(1);
      const ledgerReport = mockReport.mock.calls.find((c) => (c[1] as { op?: string }).op === "record-pending");
      expect(ledgerReport).toBeDefined();
      expect((ledgerReport![0] as Error).message).toMatch(/exceeded 5000 ms/);
    } finally {
      vi.useRealTimers();
    }
  });

  test("a non-UUID id is never sent to the ledger RPC (the column is uuid); it is reported instead", async () => {
    mockAuth.admin.getUserById.mockResolvedValue({ data: { user: { id: "user-123", email: "t@example.test" } }, error: null });
    mockRemoveGitDataRepo.mockResolvedValue(NON_ERASED.refused);
    const result = await deleteAccount("user-123", "t@example.test");
    expect(result).toEqual({ success: true, gitDataErasurePending: true });
    expect(ledgerCalls()).toHaveLength(0);
    expect(mockReport.mock.calls.some((c) => (c[1] as { op?: string }).op === "record-pending")).toBe(true);
  });
});
