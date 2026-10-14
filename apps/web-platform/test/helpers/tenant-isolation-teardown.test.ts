/**
 * Unit coverage for tearDownTenantUser's fatality-class decision logic.
 *
 * The integration suites exercise this helper under their own env gates
 * (SUPABASE_DEV_INTEGRATION / BYOK_INTEGRATION_TEST / TENANT_INTEGRATION_TEST)
 * against dev Supabase. This file gives ALWAYS-ON coverage of the core #5582
 * invariant — a RESTRICT-class anonymise failure must THROW before
 * auth.admin.deleteUser (so a future regression is a red test, not a
 * withGoTrueRetry-masked 500) — by injecting a mock service client (the helper
 * already takes `service` as a parameter, so no refactor is needed).
 */

import { describe, expect, test, vi } from "vitest";
import {
  SYNTHETIC_PREFIXES,
  tearDownTenantUser,
  tearDownTenantUsers,
} from "./tenant-isolation-teardown";

const SYNTHETIC_EMAIL = "tenant-isolation-0123456789abcdef@soleur.test";

type RpcError = { code?: string; message: string } | null;

/**
 * Build a minimal mock SupabaseClient whose `.rpc()` returns an error only for
 * the named RPC(s), and a spy `deleteUser` that records whether it was reached.
 */
function mockService(
  rpcErrors: Record<string, RpcError>,
  opts: { authEmail?: string | null; authError?: string } = {},
) {
  const deleteUser = vi.fn(async () => ({ error: null }));
  const rpc = vi.fn(async (name: string) => ({
    error: rpcErrors[name] ?? null,
  }));
  // Default: the auth row exists and its email matches whatever the test
  // declares via the `email` arg's SYNTHETIC_EMAIL — bound by the helper's
  // new id<->email check. Pass opts.authEmail to diverge, null for
  // not-found, or opts.authError for a GoTrue failure.
  const getUserById = vi.fn(async () => ({
    data: {
      user:
        opts.authEmail === null
          ? null
          : { email: opts.authEmail ?? SYNTHETIC_EMAIL },
    },
    error: opts.authError ? { message: opts.authError } : null,
  }));
  // Cast through unknown — we only implement the surface tearDownTenantUser uses.
  const service = {
    rpc,
    auth: { admin: { deleteUser, getUserById } },
  } as unknown as Parameters<typeof tearDownTenantUser>[0];
  return { service, rpc, deleteUser, getUserById };
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
    ).rejects.toThrow(/anonymise failure/);
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
    ).rejects.toThrow(/anonymise failure/);
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

  test("all anonymise RPCs clean → deleteUser called once, AFTER the RPCs", async () => {
    const { service, deleteUser, rpc } = mockService({});
    await tearDownTenantUser(service, {
      id: "user-1",
      email: SYNTHETIC_EMAIL,
    });
    // 22 anonymise RPCs run, then exactly one deleteUser — and ordering is
    // load-bearing: a regression that deletes first still satisfies a bare
    // call-count assertion.
    expect(rpc.mock.calls.length).toBe(22);
    expect(deleteUser).toHaveBeenCalledOnce();
    const lastRpcOrder = Math.max(...rpc.mock.invocationCallOrder);
    expect(deleteUser.mock.invocationCallOrder[0]).toBeGreaterThan(
      lastRpcOrder,
    );
  });

  test("graceful-class RPC with a REAL error is FATAL before deleteUser", async () => {
    // anonymise_workspace_invitations is the only `graceful` entry — it
    // tolerates a missing-function (PGRST202/42883) but a genuine error
    // (P0001) is contractually fatal, not tolerable.
    const { service, deleteUser } = mockService({
      anonymise_workspace_invitations: { code: "P0001", message: "boom" },
    });
    await expect(
      tearDownTenantUser(service, { id: "user-1", email: SYNTHETIC_EMAIL }),
    ).rejects.toThrow(/anonymise failure/);
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test("id↔email mismatch is refused before any RPC", async () => {
    // The sentinel gates on email but every op acts on user.id — a caller
    // passing a real user's id under a synthetic-looking email must be
    // refused at the binding check.
    const { service, rpc, deleteUser } = mockService(
      {},
      { authEmail: "real-user@example.com" },
    );
    await expect(
      tearDownTenantUser(service, { id: "user-1", email: SYNTHETIC_EMAIL }),
    ).rejects.toThrow(/id\/email mismatch/);
    expect(rpc).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test("getUserById failure is fail-closed (binding unverifiable)", async () => {
    // A transient GoTrue error must not read as "no auth row" and silently
    // skip the binding — refuse before any RPC. ("boom" is non-retryable
    // so withGoTrueRetry returns immediately — same fail-closed assertion.)
    const { service, rpc, deleteUser } = mockService(
      {},
      { authEmail: null, authError: "boom" },
    );
    await expect(
      tearDownTenantUser(service, { id: "user-1", email: SYNTHETIC_EMAIL }),
    ).rejects.toThrow(/binding unverifiable/);
    expect(rpc).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test("id↔email check tolerates an already-gone auth row", async () => {
    // not-found is the idempotent exit — a second teardown call must not
    // throw on the binding check.
    const { service, deleteUser } = mockService({}, { authEmail: null });
    await expect(
      tearDownTenantUser(service, { id: "user-1", email: SYNTHETIC_EMAIL }),
    ).resolves.toBeUndefined();
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

describe("synthetic prefix allowlist (#9994)", () => {
  // Deliberate independent copy of the helper's list — importing it for the
  // positive loop would mask a dropped prefix in the SUT. The set-equality
  // census below is what pins the two lists together: a prefix added to the
  // helper without a test edit goes RED here, never silently untested.
  const EXPECTED_PREFIXES = [
    "tenant-isolation-",
    "byok-isolation-",
    "beta-crm-",
    "cc-cross-tenant-",
    "conv-rail-cross-tenant-",
    "dsar-cross-tenant-",
    "workspace-fixture-",
    "workspace-backfill-parity-",
    "mu1-integration-",
  ];

  test("allowlist census: SYNTHETIC_PREFIXES === the reviewed prefix set", () => {
    expect([...SYNTHETIC_PREFIXES].sort()).toEqual(
      [...EXPECTED_PREFIXES].sort(),
    );
  });

  for (const prefix of SYNTHETIC_PREFIXES) {
    test(`accepts ${prefix}<hex>@soleur.test`, async () => {
      const { service, deleteUser } = mockService({}, {
        authEmail: `${prefix}0123456789abcdef@soleur.test`,
      });
      await expect(
        tearDownTenantUser(service, {
          id: "user-1",
          email: `${prefix}0123456789abcdef@soleur.test`,
        }),
      ).resolves.toBeUndefined();
      expect(deleteUser).toHaveBeenCalledOnce();
    });
  }

  test("non-allowlisted prefix is refused even with the exact suffix shape", async () => {
    const { service, rpc, deleteUser } = mockService({});
    await expect(
      tearDownTenantUser(service, {
        id: "user-1",
        email: "unlisted-suite-0123456789abcdef@soleur.test",
      }),
    ).rejects.toThrow(/refusing non-synthetic email/);
    expect(rpc).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  test("non-soleur.test domain is refused even with an allowlisted prefix", async () => {
    const { service, rpc, deleteUser } = mockService({});
    await expect(
      tearDownTenantUser(service, {
        id: "user-1",
        email: "tenant-isolation-0123456789abcdef@example.com",
      }),
    ).rejects.toThrow(/refusing non-synthetic email/);
    expect(rpc).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });

  // The {16} pin is load-bearing (PR #2597 permissive-regex incident class):
  // cover the off-by-one boundaries and the non-hex class, not just "wrong".
  for (const [label, suffix] of [
    ["15-hex (one short)", "0123456789abcde"],
    ["17-hex (one long)", "0123456789abcdef0"],
    ["16 with a non-hex char (g)", "0123456789abcdeg"],
    ["uppercase hex", "0123456789ABCDEF"],
    ["prefix glued to another word", "extra-0123456789abcdef"],
  ] as const) {
    test(`refuses tenant-isolation-${label}`, async () => {
      const { service, rpc, deleteUser } = mockService({});
      await expect(
        tearDownTenantUser(service, {
          id: "user-1",
          email: `tenant-isolation-${suffix}@soleur.test`,
        }),
      ).rejects.toThrow(/refusing non-synthetic email/);
      expect(rpc).not.toHaveBeenCalled();
      expect(deleteUser).not.toHaveBeenCalled();
    });
  }
});

describe("tearDownTenantUsers (plural, #10249)", () => {
  const EMAIL_A = "tenant-isolation-aaaaaaaaaaaaaaaa@soleur.test";
  const EMAIL_B = "tenant-isolation-bbbbbbbbbbbbbbbb@soleur.test";

  /**
   * Per-user mock: getUserById resolves the auth email by id so each
   * user binds to its own synthetic address (the shared mockService
   * returns one email for every id, which would trip the id↔email
   * binding for user B).
   */
  function mockServicePerUser(opts: {
    failDeleteForId?: string;
    emails?: Record<string, string>;
  }) {
    // Failure message is deliberately NOT retryable ("Database error
    // deleting user" / rate-limit shapes would make withGoTrueRetry burn
    // its 5-attempt backoff against the real setTimeout).
    const deleteUser = vi.fn(async (id: string) => ({
      error:
        opts.failDeleteForId === id
          ? { message: "permanent delete failure" }
          : null,
    }));
    const rpc = vi.fn(async () => ({ error: null }));
    const getUserById = vi.fn(async (id: string) => ({
      data: {
        user: { email: opts.emails?.[id] ?? "unknown@soleur.test" },
      },
      error: null,
    }));
    const service = {
      rpc,
      auth: { admin: { deleteUser, getUserById } },
    } as unknown as Parameters<typeof tearDownTenantUser>[0];
    return { service, rpc, deleteUser, getUserById };
  }

  const USERS = [
    { id: "user-a", email: EMAIL_A },
    { id: "user-b", email: EMAIL_B },
  ];
  const EMAILS = { "user-a": EMAIL_A, "user-b": EMAIL_B };

  test("all-clean batch deletes every user and resolves", async () => {
    const { service, deleteUser } = mockServicePerUser({ emails: EMAILS });
    await expect(tearDownTenantUsers(service, USERS)).resolves.toBeUndefined();
    expect(deleteUser).toHaveBeenCalledTimes(2);
    expect(deleteUser.mock.calls.map((c) => c[0])).toEqual([
      "user-a",
      "user-b",
    ]);
  });

  test("first user's failure does NOT abandon the second — both attempted, then throws", async () => {
    const err = vi.spyOn(console, "error").mockImplementation(() => {});
    const { service, deleteUser } = mockServicePerUser({
      emails: EMAILS,
      failDeleteForId: "user-a",
    });
    await expect(tearDownTenantUsers(service, USERS)).rejects.toThrow(
      /1 of 2 teardown\(s\) failed/,
    );
    // The whole point of #10249: user-b is still torn down after
    // user-a's deleteUser failure.
    expect(deleteUser.mock.calls.map((c) => c[0])).toEqual([
      "user-a",
      "user-b",
    ]);
    err.mockRestore();
  });

  test("non-synthetic email mid-batch still attempts the rest, then throws", async () => {
    const err = vi.spyOn(console, "error").mockImplementation(() => {});
    const { service, deleteUser } = mockServicePerUser({ emails: EMAILS });
    await expect(
      tearDownTenantUsers(service, [
        { id: "user-a", email: "real@example.com" },
        USERS[1],
      ]),
    ).rejects.toThrow(/refusing non-synthetic email/);
    expect(deleteUser).toHaveBeenCalledTimes(1);
    expect(deleteUser).toHaveBeenCalledWith("user-b");
    err.mockRestore();
  });

  test("tolerate predicate suppresses only confirmed failures", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const err = vi.spyOn(console, "error").mockImplementation(() => {});
    const { service, deleteUser } = mockServicePerUser({
      emails: EMAILS,
      failDeleteForId: "user-a",
    });
    // Predicate confirms user-a's failure → tolerated; user-b clean.
    await expect(
      tearDownTenantUsers(service, USERS, {
        tolerate: (_e, u) => u.id === "user-a",
      }),
    ).resolves.toBeUndefined();
    expect(deleteUser).toHaveBeenCalledTimes(2);

    // Predicate rejects the failure → aggregates and throws.
    await expect(
      tearDownTenantUsers(service, USERS, { tolerate: () => false }),
    ).rejects.toThrow(/1 of 2 teardown\(s\) failed/);
    warn.mockRestore();
    err.mockRestore();
  });

  test("empty batch resolves without touching the service", async () => {
    const { service, deleteUser, rpc } = mockServicePerUser({});
    await expect(tearDownTenantUsers(service, [])).resolves.toBeUndefined();
    expect(rpc).not.toHaveBeenCalled();
    expect(deleteUser).not.toHaveBeenCalled();
  });
});
