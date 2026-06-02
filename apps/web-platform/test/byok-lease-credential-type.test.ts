import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// feat-operator-cc-oauth Phase 2 — two-row-by-provider credential model.
//
// Structural boundary invariants:
//   - getRestApiKey() queries ONLY provider='anthropic' and can therefore
//     NEVER return an oauth_token by construction (AC: raw-REST cannot read
//     oauth).
//   - getAgentCredential() prefers provider='anthropic_oauth' (gated), falls
//     back to provider='anthropic'. Returns { value, scheme }.
//   - The date (AC3), owner (AC4), and kill-switch (AC8) gates fire ONLY on
//     the oauth read.
//
// Provider-aware mock: the chain records the `provider` passed to `.eq()` so
// maybeSingle() can return the row for the specific provider queried — this is
// what lets the test prove getRestApiKey() never sees the oauth row.

const mocks = vi.hoisted(() => {
  let rows: Record<string, Record<string, unknown> | null> = {};
  let fetchError: Error | null = null;
  return {
    setRow: (provider: string, row: Record<string, unknown> | null) => {
      rows[provider] = row;
    },
    getRows: () => rows,
    getFetchError: () => fetchError,
    setFetchError: (e: Error | null) => {
      fetchError = e;
    },
    reset: () => {
      rows = {};
      fetchError = null;
    },
  };
});

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async (_userId: string) => ({
    from: () => {
      const ctx: { provider?: string } = {};
      // biome-ignore lint/suspicious/noExplicitAny: test mock chain
      const chain: any = {
        select: () => chain,
        eq: (col: string, val: string) => {
          if (col === "provider") ctx.provider = val;
          return chain;
        },
        limit: () => chain,
        maybeSingle: async () => {
          if (mocks.getFetchError()) {
            return { data: null, error: mocks.getFetchError() };
          }
          return { data: mocks.getRows()[ctx.provider ?? ""] ?? null, error: null };
        },
      };
      return chain;
    },
  })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
  _resetTenantCache: () => {},
}));

import {
  runWithByokLease,
  CC_OAUTH_EFFECTIVE_DATE,
  OauthNotYetPermittedError,
  OauthDelegationForbiddenError,
} from "@/server/byok-lease";
import { encryptKey } from "@/server/byok";

const OPERATOR = "550e8400-e29b-41d4-a716-446655440000";
const OTHER = "660e8400-e29b-41d4-a716-446655440111";
const REST_PLAINTEXT = "sk-ant-api03-rest-key-1234567890";
const OAUTH_PLAINTEXT = "sk-ant-oat01-subscription-token-abcdef";

const BEFORE_DATE = CC_OAUTH_EFFECTIVE_DATE - 1; // 2026-06-14T23:59:59.999Z
const AFTER_DATE = CC_OAUTH_EFFECTIVE_DATE + 86_400_000; // 2026-06-16

function seedProvider(provider: string, plaintext: string, owner: string) {
  const { encrypted, iv, tag } = encryptKey(plaintext, owner);
  mocks.setRow(provider, {
    encrypted_key: encrypted.toString("base64"),
    iv: iv.toString("base64"),
    auth_tag: tag.toString("base64"),
    key_version: 2,
  });
}

let savedEnabled: string | undefined;

beforeEach(() => {
  mocks.reset();
  delete process.env.BYOK_ENCRYPTION_KEY;
  savedEnabled = process.env.CC_OAUTH_ENABLED;
});

afterEach(() => {
  vi.restoreAllMocks();
  if (savedEnabled === undefined) delete process.env.CC_OAUTH_ENABLED;
  else process.env.CC_OAUTH_ENABLED = savedEnabled;
});

describe("getRestApiKey — structural raw-REST boundary", () => {
  it("returns the provider='anthropic' plaintext", async () => {
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    const result = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
      (lease) => Promise.resolve(lease.getRestApiKey()),
    );
    expect(result).toBe(REST_PLAINTEXT);
  });

  it("NEVER returns the oauth token even when one exists, kill-switch on, date passed", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    const result = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
      (lease) => Promise.resolve(lease.getRestApiKey()),
    );
    // Construction guarantee: getRestApiKey queries provider='anthropic'.
    expect(result).toBe(REST_PLAINTEXT);
    expect(result).not.toBe(OAUTH_PLAINTEXT);
  });
});

describe("getAgentCredential — oauth preference + gates", () => {
  it("prefers oauth_token when enabled + date passed + owner matches", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    const cred = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
      (lease) => Promise.resolve(lease.getAgentCredential()),
    );
    expect(cred).toEqual({ value: OAUTH_PLAINTEXT, scheme: "oauth_token" });
  });

  it("AC3: date gate throws OauthNotYetPermittedError before the effective date", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(BEFORE_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    await expect(
      runWithByokLease(
        { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
        (lease) => Promise.resolve(lease.getAgentCredential()),
      ),
    ).rejects.toBeInstanceOf(OauthNotYetPermittedError);
  });

  it("AC4: owner mismatch on the oauth read throws OauthDelegationForbiddenError", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OTHER);

    await expect(
      runWithByokLease(
        { workspaceContextUserId: OPERATOR, keyOwnerUserId: OTHER },
        (lease) => Promise.resolve(lease.getAgentCredential()),
      ),
    ).rejects.toBeInstanceOf(OauthDelegationForbiddenError);
  });

  it("AC4: a delegated lease on the oauth read throws OauthDelegationForbiddenError", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    await expect(
      runWithByokLease(
        {
          workspaceContextUserId: OPERATOR,
          keyOwnerUserId: OPERATOR,
          delegationId: "11111111-1111-1111-1111-111111111111",
        },
        (lease) => Promise.resolve(lease.getAgentCredential()),
      ),
    ).rejects.toBeInstanceOf(OauthDelegationForbiddenError);
  });

  it("AC8: kill-switch off ⇒ falls back to api_key (oauth row ignored, no throw)", async () => {
    delete process.env.CC_OAUTH_ENABLED;
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);
    seedProvider("anthropic_oauth", OAUTH_PLAINTEXT, OPERATOR);

    const cred = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
      (lease) => Promise.resolve(lease.getAgentCredential()),
    );
    expect(cred).toEqual({ value: REST_PLAINTEXT, scheme: "api_key" });
  });

  it("falls back to api_key when no oauth row exists (enabled + date passed)", async () => {
    process.env.CC_OAUTH_ENABLED = "1";
    vi.spyOn(Date, "now").mockReturnValue(AFTER_DATE);
    seedProvider("anthropic", REST_PLAINTEXT, OPERATOR);

    const cred = await runWithByokLease(
      { workspaceContextUserId: OPERATOR, keyOwnerUserId: OPERATOR },
      (lease) => Promise.resolve(lease.getAgentCredential()),
    );
    expect(cred).toEqual({ value: REST_PLAINTEXT, scheme: "api_key" });
  });
});
