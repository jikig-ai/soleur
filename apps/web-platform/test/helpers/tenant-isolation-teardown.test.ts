/**
 * Unit coverage for tearDownTenantUser's fatality-class decision logic.
 *
 * The integration suites exercise this helper only under TENANT_INTEGRATION_TEST
 * against dev Supabase. This file gives ALWAYS-ON coverage of the core #5582
 * invariant — a RESTRICT-class anonymise failure must THROW before
 * auth.admin.deleteUser (so a future regression is a red test, not a
 * withGoTrueRetry-masked 500) — by injecting a mock service client (the helper
 * already takes `service` as a parameter, so no refactor is needed).
 */

import { describe, expect, test, vi } from "vitest";
import { tearDownTenantUser } from "./tenant-isolation-teardown";

const SYNTHETIC_EMAIL = "tenant-isolation-0123456789abcdef@soleur.test";

type RpcError = { code?: string; message: string } | null;

/**
 * Build a minimal mock SupabaseClient whose `.rpc()` returns an error only for
 * the named RPC(s), and a spy `deleteUser` that records whether it was reached.
 */
function mockService(rpcErrors: Record<string, RpcError>) {
  const deleteUser = vi.fn(async () => ({ error: null }));
  const rpc = vi.fn(async (name: string) => ({
    error: rpcErrors[name] ?? null,
  }));
  // Cast through unknown — we only implement the surface tearDownTenantUser uses.
  const service = {
    rpc,
    auth: { admin: { deleteUser } },
  } as unknown as Parameters<typeof tearDownTenantUser>[0];
  return { service, rpc, deleteUser };
}

describe("tearDownTenantUser fatality classes", () => {
  test("RESTRICT-class anonymise error THROWS before deleteUser", async () => {
    // anonymise_email_triage_items is a RESTRICT-class RPC (mig 102 FK).
    const { service, deleteUser } = mockService({
      anonymise_email_triage_items: { code: "P0001", message: "FK block" },
    });
    await expect(
      tearDownTenantUser(service, {
        id: "user-1",
        email: SYNTHETIC_EMAIL,
      }),
    ).rejects.toThrow(/RESTRICT-class anonymise failure/);
    // The throw must happen BEFORE the auth delete (the whole point of #5582:
    // surface the FK block as a red test, not a deleteUser 500 retry storm).
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test("PGRST202 (arg-name typo) on a RESTRICT-class RPC is FATAL", async () => {
    const { service, deleteUser } = mockService({
      anonymise_scope_grants: {
        code: "PGRST202",
        message: "function not found",
      },
    });
    await expect(
      tearDownTenantUser(service, { id: "user-1", email: SYNTHETIC_EMAIL }),
    ).rejects.toThrow(/RESTRICT-class anonymise failure/);
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test("SET-NULL-class anonymise error warns and proceeds to deleteUser", async () => {
    // anonymise_workspace_activity is SET-NULL (mig 076 FK) — non-fatal.
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { service, deleteUser } = mockService({
      anonymise_workspace_activity: { code: "XX000", message: "transient" },
    });
    await expect(
      tearDownTenantUser(service, { id: "user-1", email: SYNTHETIC_EMAIL }),
    ).resolves.toBeUndefined();
    expect(deleteUser).toHaveBeenCalledOnce();
    warn.mockRestore();
  });

  test("graceful missing-function (workspace_invitations) is tolerated", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const { service, deleteUser } = mockService({
      anonymise_workspace_invitations: {
        code: "PGRST202",
        message: "function not found",
      },
    });
    await expect(
      tearDownTenantUser(service, { id: "user-1", email: SYNTHETIC_EMAIL }),
    ).resolves.toBeUndefined();
    expect(deleteUser).toHaveBeenCalledOnce();
    warn.mockRestore();
  });

  test("all anonymise RPCs clean → deleteUser called once", async () => {
    const { service, deleteUser, rpc } = mockService({});
    await tearDownTenantUser(service, {
      id: "user-1",
      email: SYNTHETIC_EMAIL,
    });
    // 21 anonymise RPCs run, then exactly one deleteUser.
    expect(rpc.mock.calls.length).toBe(21);
    expect(deleteUser).toHaveBeenCalledOnce();
  });

  test("non-synthetic email is refused before any RPC", async () => {
    const { service, rpc, deleteUser } = mockService({});
    await expect(
      tearDownTenantUser(service, { id: "user-1", email: "real@example.com" }),
    ).rejects.toThrow(/refusing non-synthetic email/);
    expect(rpc).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });
});
