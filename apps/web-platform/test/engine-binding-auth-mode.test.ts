import { describe, it, expect, vi, beforeEach } from "vitest";

import { boundRun, makeTableAwareTenant } from "./helpers/table-aware-tenant";

const h = vi.hoisted(() => ({ tenant: null as unknown }));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => (h.tenant as { client: unknown }).client),
}));

import { makeConversationAuthModeResolver, readConversationBindingAuthMode } from "@/server/engine-binding-auth-mode";
import { ConversationAuthModeError } from "@/server/auth-mode-error";

const ME = "11111111-1111-4111-8111-111111111111";
const PEER = "22222222-2222-4222-8222-222222222222";
const CONV = "33333333-3333-4333-8333-333333333333";
const OTHER_CONV = "44444444-4444-4444-8444-444444444444";

function use(tables: Record<string, Record<string, unknown>[]>) {
  const t = makeTableAwareTenant(tables);
  h.tenant = t;
  return t;
}

beforeEach(() => {
  h.tenant = null;
});

describe("makeConversationAuthModeResolver", () => {
  it("returns the bound run's auth mode", async () => {
    use({ agent_engine_runs: [boundRun({ conversation_id: CONV, created_by: ME, auth_mode: "api-key" })] });
    await expect(makeConversationAuthModeResolver(ME, CONV)()).resolves.toBe("api-key");
  });

  it("never serves a decoy run: another conversation, or another member's run on the same conversation", async () => {
    const t = use({
      agent_engine_runs: [
        boundRun({ id: "r2", conversation_id: OTHER_CONV, created_by: ME, auth_mode: "api-key" }),
        boundRun({ id: "r3", conversation_id: CONV, created_by: PEER, auth_mode: "api-key" }),
      ],
      conversations: [{ id: CONV, user_id: ME, engine_binding_state: "pending" }],
    });
    const err = await makeConversationAuthModeResolver(ME, CONV)().catch((e) => e);
    expect(err).toBeInstanceOf(ConversationAuthModeError);
    expect((err as ConversationAuthModeError).reason).toBe("unbound");
    // The reads were scoped to the caller.
    expect(t.eqs).toContainEqual(["agent_engine_runs", "created_by", ME]);
    expect(t.eqs).toContainEqual(["conversations", "user_id", ME]);
  });

  it("no run + legacy resolves to managed", async () => {
    use({ conversations: [{ id: CONV, user_id: ME, engine_binding_state: "legacy" }] });
    await expect(makeConversationAuthModeResolver(ME, CONV)()).resolves.toBe("managed");
  });

  it("no run + legacy owned by another member does not lend the caller a mode", async () => {
    use({ conversations: [{ id: CONV, user_id: PEER, engine_binding_state: "legacy" }] });
    await expect(makeConversationAuthModeResolver(ME, CONV)()).rejects.toMatchObject({ reason: "unbound" });
  });

  it.each(["pending", "bound", null])("no run + state %s throws unbound", async (state) => {
    use({ conversations: [{ id: CONV, user_id: ME, engine_binding_state: state }] });
    await expect(makeConversationAuthModeResolver(ME, CONV)()).rejects.toMatchObject({ reason: "unbound" });
  });

  it("no conversation row at all throws unbound", async () => {
    use({});
    await expect(makeConversationAuthModeResolver(ME, CONV)()).rejects.toMatchObject({ reason: "unbound" });
  });

  it.each(["agent_engine_runs", "conversations"])("a read error on %s throws read_failed with no database text", async (table) => {
    const t = use({ conversations: [{ id: CONV, user_id: ME, engine_binding_state: "legacy" }] });
    t.failTables.add(table);
    const err = await makeConversationAuthModeResolver(ME, CONV)().catch((e) => e);
    expect(err).toBeInstanceOf(ConversationAuthModeError);
    expect((err as ConversationAuthModeError).reason).toBe("read_failed");
    expect(JSON.stringify(err)).not.toContain("SECRETROW");
    expect((err as Error).message).not.toContain("SECRETROW");
  });

  it.each([["", CONV], [ME, ""]])("an empty id (%j, %j) is unbound before any read: the scope arguments are optional by design", async (u, c) => {
    const t = use({ agent_engine_runs: [boundRun({ conversation_id: CONV, created_by: ME, auth_mode: "api-key" })] });
    await expect(makeConversationAuthModeResolver(u, c)()).rejects.toMatchObject({ reason: "unbound" });
    expect(t.eqs).toHaveLength(0);
  });

  it("a tenant-client failure throws read_failed", async () => {
    h.tenant = { get client(): never { throw new Error("jwt mint failed"); } };
    await expect(makeConversationAuthModeResolver(ME, CONV)()).rejects.toMatchObject({ reason: "read_failed" });
  });
});

describe("readConversationBindingAuthMode (diagnostic contract)", () => {
  it("returns null when there is no run bound by the caller, the raw mode otherwise, and rejects on error", async () => {
    use({ agent_engine_runs: [boundRun({ conversation_id: CONV, created_by: PEER, auth_mode: "managed" })] });
    await expect(readConversationBindingAuthMode(ME, CONV)).resolves.toBeNull();
    use({ agent_engine_runs: [boundRun({ conversation_id: CONV, created_by: ME, auth_mode: "managed" })] });
    await expect(readConversationBindingAuthMode(ME, CONV)).resolves.toBe("managed");
    const t = use({});
    t.failTables.add("agent_engine_runs");
    await expect(readConversationBindingAuthMode(ME, CONV)).rejects.toThrow();
  });
});
