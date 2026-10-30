import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

import { boundRun, makeTableAwareTenant, type TableAwareTenant } from "./helpers/table-aware-tenant";

// #11591 AC7/AC16 — the REAL lease driven by the REAL binding resolver over a table-aware tenant client.
// Nothing here mocks the mode: the leased scheme follows the persisted binding, and flipping the binding
// between two leases flips the scheme, so the test cannot pass against a constant.

const h = vi.hoisted(() => ({ tenant: null as unknown }));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => (h.tenant as { client: unknown }).client),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
  _resetTenantCache: () => {},
}));
vi.mock("@/server/logger", () => {
  const rec = () => {};
  const logger: Record<string, unknown> = { error: rec, warn: rec, info: rec, debug: rec, trace: rec, fatal: rec };
  logger.child = () => logger;
  return { default: logger, createChildLogger: () => logger };
});
vi.mock("@sentry/nextjs", () => ({
  captureMessage: vi.fn(),
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
}));

import { runWithByokLease, ByokLeaseError, CC_OAUTH_EFFECTIVE_DATE, OauthDelegationForbiddenError } from "@/server/byok-lease";
import { makeConversationAuthModeResolver } from "@/server/engine-binding-auth-mode";
import { encryptKey } from "@/server/byok";

const OWNER = "550e8400-e29b-41d4-a716-446655440000";
const MEMBER = "660e8400-e29b-41d4-a716-446655440111";
const CONV = "33333333-3333-4333-8333-333333333333";
const DECOY_CONV = "44444444-4444-4444-8444-444444444444";
const API_KEY = "sk-ant-api03-rest-key-1234567890";
const OAUTH = "sk-ant-oat01-FAKEvalid_0123-abc";

function keyRow(owner: string, provider: string, plaintext: string) {
  const { encrypted, iv, tag } = encryptKey(plaintext, owner);
  return {
    user_id: owner,
    provider,
    is_valid: true,
    encrypted_key: encrypted.toString("base64"),
    iv: iv.toString("base64"),
    auth_tag: tag.toString("base64"),
    key_version: 2,
  };
}

let tenant: TableAwareTenant;
let saved: string | undefined;

beforeEach(() => {
  saved = process.env.CC_OAUTH_ENABLED;
  process.env.CC_OAUTH_ENABLED = "1";
  vi.spyOn(Date, "now").mockReturnValue(CC_OAUTH_EFFECTIVE_DATE + 86_400_000);
  delete process.env.BYOK_ENCRYPTION_KEY;
  tenant = makeTableAwareTenant({
    api_keys: [keyRow(OWNER, "anthropic", API_KEY), keyRow(OWNER, "anthropic_oauth", OAUTH)],
    agent_engine_runs: [
      boundRun({ id: "decoy", conversation_id: DECOY_CONV, created_by: OWNER, auth_mode: "api-key" }),
      boundRun({ id: "mine", conversation_id: CONV, created_by: OWNER, auth_mode: "managed" }),
    ],
    conversations: [{ id: CONV, user_id: OWNER, engine_binding_state: "bound" }],
  });
  h.tenant = tenant;
});

afterEach(() => {
  vi.restoreAllMocks();
  if (saved === undefined) delete process.env.CC_OAUTH_ENABLED;
  else process.env.CC_OAUTH_ENABLED = saved;
});

const scheme = (args: { keyOwnerUserId?: string; userId?: string; conversationId?: string; delegationId?: string } = {}) =>
  runWithByokLease(
    {
      workspaceContextUserId: OWNER,
      keyOwnerUserId: args.keyOwnerUserId ?? OWNER,
      delegationId: args.delegationId,
      resolveAuthMode: makeConversationAuthModeResolver(args.userId ?? OWNER, args.conversationId ?? CONV),
    },
    async (lease) => (await lease.getAgentCredential()).scheme,
  );

function setMode(mode: string) {
  const run = tenant.tables.agent_engine_runs.find((r) => r.id === "mine")!;
  run.auth_mode = mode;
}

describe("the lease follows the persisted binding", () => {
  it("managed binding leases the subscription token; the decoy api-key run for another conversation is never served", async () => {
    await expect(scheme()).resolves.toBe("oauth_token");
  });

  it("flipping the persisted binding between two leases flips the leased scheme", async () => {
    await expect(scheme()).resolves.toBe("oauth_token");
    setMode("api-key");
    await expect(scheme()).resolves.toBe("api_key");
    setMode("managed");
    await expect(scheme()).resolves.toBe("oauth_token");
  });

  it("no run + legacy leases per managed", async () => {
    tenant.tables.agent_engine_runs = [];
    tenant.tables.conversations = [{ id: CONV, user_id: OWNER, engine_binding_state: "legacy" }];
    await expect(scheme()).resolves.toBe("oauth_token");
  });

  it.each(["pending", "bound"])("no run + %s fails closed with fetch_failed and serves nothing", async (state) => {
    tenant.tables.agent_engine_runs = [];
    tenant.tables.conversations = [{ id: CONV, user_id: OWNER, engine_binding_state: state }];
    const err = await scheme().catch((e) => e);
    expect(err).toBeInstanceOf(ByokLeaseError);
    expect((err as ByokLeaseError).cause).toBe("fetch_failed");
  });

  it("a read error on the binding fails closed", async () => {
    tenant.failTables.add("agent_engine_runs");
    const err = await scheme().catch((e) => e);
    expect(err).toBeInstanceOf(ByokLeaseError);
    expect((err as ByokLeaseError).cause).toBe("fetch_failed");
  });

  it("AC16 a run bound by another member does not lend its mode: the caller's own conversation id resolves unbound", async () => {
    tenant.tables.agent_engine_runs = [boundRun({ id: "theirs", conversation_id: CONV, created_by: MEMBER, auth_mode: "api-key" })];
    tenant.tables.conversations = [{ id: CONV, user_id: MEMBER, engine_binding_state: "bound" }];
    const err = await scheme().catch((e) => e);
    expect((err as ByokLeaseError).cause).toBe("fetch_failed");
  });

  it("AC16 a delegated lease is refused by the owner gate before any binding read", async () => {
    const reads = () => tenant.eqs.filter(([t]) => t === "agent_engine_runs").length;
    const before = reads();
    await expect(scheme({ delegationId: "11111111-1111-1111-1111-111111111111" })).rejects.toBeInstanceOf(OauthDelegationForbiddenError);
    expect(reads()).toBe(before);
  });

  it("a key owner with no subscription row never reads the binding at all (no new round trip for non-subscribers)", async () => {
    tenant.tables.api_keys = [keyRow(MEMBER, "anthropic", API_KEY)];
    tenant.tables.agent_engine_runs = [boundRun({ id: "m", conversation_id: CONV, created_by: MEMBER, auth_mode: "api-key" })];
    const out = await runWithByokLease(
      {
        workspaceContextUserId: MEMBER,
        keyOwnerUserId: MEMBER,
        resolveAuthMode: makeConversationAuthModeResolver(MEMBER, CONV),
      },
      async (lease) => (await lease.getAgentCredential()).scheme,
    );
    expect(out).toBe("api_key");
    // No subscription row, so the mode was never even read (no new round trip for non-subscribers).
    expect(tenant.eqs.filter(([t]) => t === "agent_engine_runs")).toHaveLength(0);
  });
});
