// RED tests for #2919 — replace lazy v1→v2 BYOK UPDATE in
// `getUserApiKey` and `getUserServiceTokens` with predicate-locked
// Postgres RPC `migrate_api_key_to_v2`.
//
// T1: when key_version === 1 is read, helper calls
//     `supabase().rpc("migrate_api_key_to_v2", {...})` exactly once with
//     the encrypted/iv/tag tuple.
// T1b: same for getUserServiceTokens (folds in #2919-bis).
// T2: when the RPC returns `{ data: { rows_affected: 0 } }` (second
//     concurrent caller), helper still returns plaintext (re-encryption
//     deterministic on plaintext + userId; the first caller's stored
//     ciphertext decrypts to the same plaintext).
// T3: when key_version === 2, no RPC is called.

import { describe, it, expect, vi, beforeEach } from "vitest";

const {
  mockSupabaseFrom,
  mockSupabaseRpc,
  mockDecryptKeyLegacy,
  mockDecryptKey,
  mockEncryptKey,
  mockReportSilentFallback,
} = vi.hoisted(() => ({
  mockSupabaseFrom: vi.fn(),
  mockSupabaseRpc: vi.fn(),
  mockDecryptKeyLegacy: vi.fn(),
  mockDecryptKey: vi.fn(),
  mockEncryptKey: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockSupabaseFrom,
    rpc: mockSupabaseRpc,
  }),
}));

vi.mock("@/server/byok", () => ({
  decryptKey: mockDecryptKey,
  decryptKeyLegacy: mockDecryptKeyLegacy,
  encryptKey: mockEncryptKey,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));

// Avoid pulling in the full SDK chain (some sibling modules import it
// transitively); these are unused for byok-only tests.
vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  query: vi.fn(),
  tool: vi.fn(),
  createSdkMcpServer: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

import { getUserApiKey, getUserServiceTokens } from "@/server/agent-runner";

const ENCRYPTED_B64 = Buffer.from("ciphertext").toString("base64");
const IV_B64 = Buffer.from("ivivivivivivivivi").toString("base64");
const TAG_B64 = Buffer.from("tagtagtagtagtag").toString("base64");

function setupSelectChain(rows: Record<string, unknown>[]) {
  // Chainable mock for both shapes:
  //   .select().eq().eq().eq().limit().single() -> { data: rows[0], error: null }  (anthropic)
  //   .select().eq().eq()                       -> { data: rows, error: null }     (services)
  const chain: Record<string, unknown> = {
    data: rows,
    error: null,
  };
  // biome-ignore lint/suspicious/noExplicitAny: dynamic chain object
  (chain as any).eq = () => chain;
  // biome-ignore lint/suspicious/noExplicitAny: dynamic chain object
  (chain as any).limit = () => ({
    single: () => ({ data: rows[0] ?? null, error: rows[0] ? null : new Error("not found") }),
  });
  // biome-ignore lint/suspicious/noExplicitAny: thenable for `await select().eq().eq()`
  (chain as any).then = (resolve: (v: unknown) => void) =>
    resolve({ data: rows, error: null });
  return { select: () => chain };
}

describe("getUserApiKey — v1 → v2 RPC migration (#2919)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockDecryptKeyLegacy.mockReturnValue("plaintext-key");
    mockDecryptKey.mockReturnValue("plaintext-key");
    mockEncryptKey.mockReturnValue({
      encrypted: Buffer.from("re-encrypted"),
      iv: Buffer.from("new-iv"),
      tag: Buffer.from("new-tag"),
    });
  });

  it("T1: v1 row triggers ONE RPC call with the re-encrypted tuple", async () => {
    mockSupabaseFrom.mockImplementation((table: string) => {
      if (table === "api_keys") {
        return setupSelectChain([
          {
            id: "key-1",
            encrypted_key: ENCRYPTED_B64,
            iv: IV_B64,
            auth_tag: TAG_B64,
            key_version: 1,
          },
        ]);
      }
      return setupSelectChain([]);
    });
    mockSupabaseRpc.mockResolvedValue({
      data: [{ rows_affected: 1 }],
      error: null,
    });

    const plaintext = await getUserApiKey("user-1");

    expect(plaintext).toBe("plaintext-key");
    expect(mockSupabaseRpc).toHaveBeenCalledTimes(1);
    const [fnName, payload] = mockSupabaseRpc.mock.calls[0];
    expect(fnName).toBe("migrate_api_key_to_v2");
    // payload includes id, user_id, provider, encrypted, iv, tag
    expect(payload).toMatchObject({
      p_id: "key-1",
      p_user_id: "user-1",
      p_provider: "anthropic",
    });
    expect(typeof (payload as Record<string, unknown>).p_encrypted).toBe("string");
    expect(typeof (payload as Record<string, unknown>).p_iv).toBe("string");
    expect(typeof (payload as Record<string, unknown>).p_tag).toBe("string");
  });

  it("T2: rows_affected=0 (concurrent caller raced first) returns plaintext anyway", async () => {
    mockSupabaseFrom.mockImplementation((table: string) => {
      if (table === "api_keys") {
        return setupSelectChain([
          {
            id: "key-1",
            encrypted_key: ENCRYPTED_B64,
            iv: IV_B64,
            auth_tag: TAG_B64,
            key_version: 1,
          },
        ]);
      }
      return setupSelectChain([]);
    });
    // First-caller already migrated the row; this caller's UPDATE no-ops.
    mockSupabaseRpc.mockResolvedValue({
      data: [{ rows_affected: 0 }],
      error: null,
    });

    const plaintext = await getUserApiKey("user-1");

    expect(plaintext).toBe("plaintext-key");
    expect(mockSupabaseRpc).toHaveBeenCalledTimes(1);
  });

  it("T2-mirror: RPC error mirrors to Sentry under feature=byok-migration (review fix-inline #2954)", async () => {
    mockSupabaseFrom.mockImplementation((table: string) => {
      if (table === "api_keys") {
        return setupSelectChain([
          {
            id: "key-1",
            encrypted_key: ENCRYPTED_B64,
            iv: IV_B64,
            auth_tag: TAG_B64,
            key_version: 1,
          },
        ]);
      }
      return setupSelectChain([]);
    });
    mockSupabaseRpc.mockResolvedValue({
      data: null,
      error: { message: "permission denied for function migrate_api_key_to_v2" },
    });

    // Caller still gets plaintext (the migration is fire-and-forget).
    const plaintext = await getUserApiKey("user-1");
    expect(plaintext).toBe("plaintext-key");

    // Filter by feature tag per SDK exit-tag pattern; module init can
    // fire other features.
    const calls = mockReportSilentFallback.mock.calls.filter(
      ([, opts]) => opts?.feature === "byok-migration",
    );
    expect(calls).toHaveLength(1);
    expect(calls[0][1].op).toBe("migrate_api_key_to_v2");
    expect(calls[0][1].extra).toMatchObject({
      userId: "user-1",
      provider: "anthropic",
      keyId: "key-1",
    });
  });

  it("T3: v2 row does NOT call the RPC", async () => {
    mockSupabaseFrom.mockImplementation((table: string) => {
      if (table === "api_keys") {
        return setupSelectChain([
          {
            id: "key-1",
            encrypted_key: ENCRYPTED_B64,
            iv: IV_B64,
            auth_tag: TAG_B64,
            key_version: 2,
          },
        ]);
      }
      return setupSelectChain([]);
    });

    await getUserApiKey("user-1");
    expect(mockSupabaseRpc).not.toHaveBeenCalled();
    expect(mockDecryptKey).toHaveBeenCalledTimes(1);
  });
});

describe("getUserServiceTokens — v1 → v2 RPC migration (#2919-bis)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockDecryptKeyLegacy.mockReturnValue("plaintext-token");
    mockDecryptKey.mockReturnValue("plaintext-token");
    mockEncryptKey.mockReturnValue({
      encrypted: Buffer.from("re-encrypted"),
      iv: Buffer.from("new-iv"),
      tag: Buffer.from("new-tag"),
    });
  });

  it("T1b: v1 service-token row also routes through the RPC", async () => {
    mockSupabaseFrom.mockImplementation((table: string) => {
      if (table === "api_keys") {
        return setupSelectChain([
          {
            id: "svc-1",
            provider: "plausible",
            encrypted_key: ENCRYPTED_B64,
            iv: IV_B64,
            auth_tag: TAG_B64,
            key_version: 1,
          },
        ]);
      }
      return setupSelectChain([]);
    });
    mockSupabaseRpc.mockResolvedValue({
      data: [{ rows_affected: 1 }],
      error: null,
    });

    const tokens = await getUserServiceTokens("user-1");

    expect(mockSupabaseRpc).toHaveBeenCalledTimes(1);
    const [fnName, payload] = mockSupabaseRpc.mock.calls[0];
    expect(fnName).toBe("migrate_api_key_to_v2");
    expect(payload).toMatchObject({
      p_id: "svc-1",
      p_user_id: "user-1",
      p_provider: "plausible",
    });
    // Plausible env var carries the plaintext.
    expect(tokens).toMatchObject({});
    // Token presence depends on PROVIDER_CONFIG — we only assert RPC was called.
  });
});
