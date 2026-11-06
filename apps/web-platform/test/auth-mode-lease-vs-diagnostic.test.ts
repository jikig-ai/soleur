import { describe, it, expect, vi } from "vitest";

import { boundRun, makeTableAwareTenant } from "./helpers/table-aware-tenant";

// AC10 (#11591): the auth-failure diagnostic's `auth_mode` label (makeAuthModeResolver: no run -> null ->
// `unbound`) and the credential lease (makeConversationAuthModeResolver) read the same binding, so they
// agree for a bound run. They differ in exactly two documented cases, both for a conversation with no run.
// Deleted with the temporary diagnostic (see the REMOVAL CHECKLIST in server/agent-auth-mode.ts).

const h = vi.hoisted(() => ({ tenant: null as unknown }));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => (h.tenant as { client: unknown }).client),
}));

import { makeAuthModeResolver } from "@/server/agent-auth-mode";
import { makeConversationAuthModeResolver } from "@/server/engine-binding-auth-mode";

const ME = "11111111-1111-4111-8111-111111111111";
const CONV = "33333333-3333-4333-8333-333333333333";

describe("diagnostic label vs lease resolver", () => {
  it.each(["managed", "api-key"])("bound run (%s): both return the same string", async (mode) => {
    h.tenant = makeTableAwareTenant({ agent_engine_runs: [boundRun({ conversation_id: CONV, created_by: ME, auth_mode: mode })] });
    await expect(makeAuthModeResolver(ME, CONV)()).resolves.toBe(mode);
    await expect(makeConversationAuthModeResolver(ME, CONV)()).resolves.toBe(mode);
  });

  it("no run + legacy: the probe says unbound (null), the lease says managed", async () => {
    h.tenant = makeTableAwareTenant({ conversations: [{ id: CONV, user_id: ME, engine_binding_state: "legacy" }] });
    await expect(makeAuthModeResolver(ME, CONV)()).resolves.toBeNull();
    await expect(makeConversationAuthModeResolver(ME, CONV)()).resolves.toBe("managed");
  });

  it("no run + pending: the probe says unbound (null), the lease fails closed", async () => {
    h.tenant = makeTableAwareTenant({ conversations: [{ id: CONV, user_id: ME, engine_binding_state: "pending" }] });
    await expect(makeAuthModeResolver(ME, CONV)()).resolves.toBeNull();
    await expect(makeConversationAuthModeResolver(ME, CONV)()).rejects.toMatchObject({ reason: "unbound" });
  });
});
