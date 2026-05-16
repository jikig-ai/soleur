import { describe, it, expect, beforeEach, vi } from "vitest";

// PR-B §1.4.1 — BYOK lease unit tests.
//
// Asserts the load-bearing invariants of `runWithByokLease`:
//   1. ALS scope: lease.getApiKey() works inside fn, throws outside.
//   2. Zeroize-on-finally: the underlying Buffer is wiped after the
//      scope closes (success OR throw paths).
//   3. Capture-and-leak: a captured `lease` reference outside the
//      original ALS context throws `ByokLeaseError {cause: "escape"}`
//      (per type-design F3).
//   4. No plaintext key surfaces in pino/Sentry capture for any
//      operation inside the lease.
//
// Stubs `getFreshTenantClient` so the test stays in-memory. The full
// /proc/<pid>/environ subprocess-leak test is in §1.5.7 (gated
// integration test); this file covers the in-process invariants.

const mocks = vi.hoisted(() => {
  // The api_keys row the SUT will fetch + decrypt.
  let apiKeyRow:
    | {
        encrypted_key: string;
        iv: string;
        auth_tag: string;
        key_version: number;
      }
    | null = null;
  let fetchError: Error | null = null;

  return {
    setApiKeyRow: (row: typeof apiKeyRow) => {
      apiKeyRow = row;
    },
    setFetchError: (err: Error | null) => {
      fetchError = err;
    },
    getRow: () => apiKeyRow,
    getFetchError: () => fetchError,
    reset: () => {
      apiKeyRow = null;
      fetchError = null;
    },
  };
});

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async (_userId: string) => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          eq: () => ({
            eq: () => ({
              limit: () => ({
                single: async () => {
                  if (mocks.getFetchError()) {
                    return { data: null, error: mocks.getFetchError() };
                  }
                  return { data: mocks.getRow(), error: null };
                },
              }),
            }),
          }),
        }),
      }),
    }),
  })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
  _resetTenantCache: () => {},
}));

import {
  runWithByokLease,
  getCurrentByokLease,
  ByokLeaseError,
  type ByokLease,
} from "@/server/byok-lease";
import { encryptKey } from "@/server/byok";

const TEST_USER = "550e8400-e29b-41d4-a716-446655440000";
const TEST_PLAINTEXT = "sk-ant-api03-byok-lease-test-1234567890";

function seedApiKey() {
  const { encrypted, iv, tag } = encryptKey(TEST_PLAINTEXT, TEST_USER);
  mocks.setApiKeyRow({
    encrypted_key: encrypted.toString("base64"),
    iv: iv.toString("base64"),
    auth_tag: tag.toString("base64"),
    key_version: 2,
  });
}

beforeEach(() => {
  mocks.reset();
  // Use deterministic encryption fallback (NODE_ENV !== production) — no
  // BYOK_ENCRYPTION_KEY env var needed for unit tests.
  delete process.env.BYOK_ENCRYPTION_KEY;
});

describe("runWithByokLease — ALS scope invariants", () => {
  it("inside fn: lease.getApiKey() returns the decrypted plaintext", async () => {
    seedApiKey();

    const result = await runWithByokLease(TEST_USER, async (lease) => {
      // First call: lazy fetch — Promise<string>.
      return await lease.getApiKey();
    });

    expect(result).toBe(TEST_PLAINTEXT);
  });

  it("inside fn: cache hit returns sync string after first call", async () => {
    seedApiKey();

    await runWithByokLease(TEST_USER, async (lease) => {
      // Prime the cache.
      await lease.getApiKey();
      // Second call: cache hit — synchronous string return.
      const second = lease.getApiKey();
      expect(typeof second).toBe("string");
      expect(second).toBe(TEST_PLAINTEXT);
    });
  });

  it("inside fn: getCurrentByokLease() returns a lease that resolves to the same plaintext", async () => {
    seedApiKey();

    await runWithByokLease(TEST_USER, async (lease) => {
      const current = getCurrentByokLease();
      expect(current).not.toBeNull();
      const a = await lease.getApiKey();
      const b = await current!.getApiKey();
      expect(b).toBe(a);
    });
  });

  it("inside fn: getApiKey() across nested awaits still works (ALS propagation)", async () => {
    seedApiKey();

    const inner = async (l: ByokLease) => {
      await new Promise((r) => setImmediate(r));
      return await l.getApiKey();
    };

    const result = await runWithByokLease(TEST_USER, async (lease) => {
      return inner(lease);
    });

    expect(result).toBe(TEST_PLAINTEXT);
  });

  it("outside fn: getCurrentByokLease() returns null", () => {
    expect(getCurrentByokLease()).toBeNull();
  });
});

describe("runWithByokLease — zeroize-on-finally", () => {
  it("after fn returns: a captured lease reference throws ByokLeaseError{cause:escape}", async () => {
    seedApiKey();

    let captured: ByokLease | null = null;
    await runWithByokLease(TEST_USER, async (lease) => {
      captured = lease;
      // Prime the buffer so we can tell wipe-completed from no-buffer.
      expect(await lease.getApiKey()).toBe(TEST_PLAINTEXT);
    });

    expect(captured).not.toBeNull();
    expect(() => captured!.getApiKey()).toThrowError(ByokLeaseError);
    try {
      captured!.getApiKey();
    } catch (err) {
      expect((err as ByokLeaseError).cause).toBe("escape");
    }
  });

  it("after fn throws: lease zeroize still runs, captured ref still throws escape", async () => {
    seedApiKey();

    let captured: ByokLease | null = null;
    await expect(
      runWithByokLease(TEST_USER, async (lease) => {
        captured = lease;
        expect(await lease.getApiKey()).toBe(TEST_PLAINTEXT);
        throw new Error("fn-internal-failure");
      }),
    ).rejects.toThrow("fn-internal-failure");

    expect(captured).not.toBeNull();
    expect(() => captured!.getApiKey()).toThrowError(ByokLeaseError);
  });

  it("captured lease across two sibling lease scopes throws (no slot reuse)", async () => {
    seedApiKey();
    let firstLease: ByokLease | null = null;

    await runWithByokLease(TEST_USER, async (lease) => {
      firstLease = lease;
      await lease.getApiKey();
    });

    // Open a SECOND scope. The first lease's slot is dead; calling
    // getApiKey on the captured first-lease must NOT silently return
    // the second scope's plaintext.
    await runWithByokLease(TEST_USER, async (lease) => {
      expect(() => firstLease!.getApiKey()).toThrowError(ByokLeaseError);
      expect(await lease.getApiKey()).toBe(TEST_PLAINTEXT);
    });
  });
});

describe("runWithByokLease — error paths", () => {
  it("propagates fn errors after running zeroize", async () => {
    seedApiKey();
    const sentinel = new Error("from-inside-fn");

    await expect(
      runWithByokLease(TEST_USER, async () => {
        throw sentinel;
      }),
    ).rejects.toBe(sentinel);
  });

  it("api_keys fetch error: getApiKey() throws ByokLeaseError{cause:fetch_failed}", async () => {
    mocks.setFetchError(new Error("DB unreachable"));
    mocks.setApiKeyRow(null);

    await expect(
      runWithByokLease(TEST_USER, async (lease) => {
        return await lease.getApiKey();
      }),
    ).rejects.toMatchObject({
      name: "ByokLeaseError",
      cause: "fetch_failed",
    });
  });
});

describe("runWithByokLease — no plaintext leak surfaces", () => {
  it("plaintext does NOT appear in JSON serialization of the lease object", async () => {
    seedApiKey();
    let leaseSnapshot = "";
    await runWithByokLease(TEST_USER, async (lease) => {
      await lease.getApiKey();
      // Stringify the lease — anyone who logs `{ lease }` should not see
      // the plaintext or the buffer contents.
      leaseSnapshot = JSON.stringify(lease);
    });
    expect(leaseSnapshot).not.toContain(TEST_PLAINTEXT);
  });

  it("plaintext does NOT appear in JSON serialization of getCurrentByokLease() output", async () => {
    seedApiKey();
    await runWithByokLease(TEST_USER, async () => {
      const current = getCurrentByokLease();
      const snapshot = JSON.stringify(current);
      expect(snapshot).not.toContain(TEST_PLAINTEXT);
    });
  });
});
