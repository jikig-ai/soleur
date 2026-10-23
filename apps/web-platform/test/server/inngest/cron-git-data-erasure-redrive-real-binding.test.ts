// The cron's production seams, UNMOCKED: the real removeGitDataRepo and the real ledger helpers are
// bound (only the Supabase client and the Sentry/heartbeat sinks are faked). A handler whose default
// binding were swapped for a stub that reports `erased` would resolve the row here; the real wrapper,
// with the remove key absent and a sibling git-data input set, reports `unconfigured` and never dials.

import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const mockRpc = vi.fn();
vi.mock("@/lib/supabase/service", () => ({ createServiceClient: () => ({ rpc: mockRpc }) }));
vi.mock("@/server/inngest/functions/_cron-shared", () => ({ postSentryHeartbeat: vi.fn(async () => {}) }));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

import { cronGitDataErasureRedriveHandler } from "@/server/inngest/functions/cron-git-data-erasure-redrive";
import { removeGitDataRepo } from "@/server/git-data-replication";

const A = "3f2504e0-4f89-41d3-9a0c-0305e82c3301";
const fakeStep = { run: async <T>(_n: string, cb: () => Promise<T>): Promise<T> => cb() };
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

const SAVED = ["GIT_REMOVE_SSH_PRIVATE_KEY", "GIT_PROVISION_SSH_PRIVATE_KEY", "GIT_DATA_SSH_HOST"].map((k) => [k, process.env[k]] as const);
beforeEach(() => {
  vi.clearAllMocks();
  delete process.env.GIT_REMOVE_SSH_PRIVATE_KEY;
  process.env.GIT_PROVISION_SSH_PRIVATE_KEY = "synthetic-provision-key-not-real";
  let claimed = false;
  mockRpc.mockImplementation(async (name: string) => {
    if (name === "claim_git_data_erasure_pending") {
      if (claimed) return { data: [], error: null };
      claimed = true;
      return { data: [{ workspace_id: A }], error: null };
    }
    if (name === "git_data_erasure_owner_gone") return { data: true, error: null };
    return { data: null, error: null };
  });
});
afterEach(() => {
  for (const [k, v] of SAVED) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
});

describe("cron-git-data-erasure-redrive default bindings", () => {
  it("the fixture really exercises the real wrapper: remove key absent + a sibling input => unconfigured, nothing dialed", async () => {
    await expect(removeGitDataRepo(A)).resolves.toMatchObject({ status: "unconfigured", detail: expect.stringMatching(/^remove_key_absent: /) });
  });

  it("drives the REAL removeGitDataRepo and the REAL ledger helper: the row is kept and last_outcome becomes 'unconfigured'", async () => {
    const out = await cronGitDataErasureRedriveHandler({ step: fakeStep, logger });
    expect(out).toMatchObject({ claimed: 1, erased: 0, pending: 1 });
    const names = mockRpc.mock.calls.map((c) => c[0]);
    expect(names).not.toContain("resolve_git_data_erasure_pending");
    expect(mockRpc).toHaveBeenCalledWith("record_git_data_erasure_pending", { p_workspace_id: A, p_outcome: "unconfigured" });
    // the owner check precedes the wrapper
    expect(names.indexOf("git_data_erasure_owner_gone")).toBeLessThan(names.indexOf("record_git_data_erasure_pending"));
  });
});
