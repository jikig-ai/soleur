import { describe, it, expect, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

const rpc = vi.fn();
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ rpc }),
}));

const reportSilentFallback = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallback(...a),
}));

import { inboxStateHandler } from "@/server/inbox-state-handler";

const USER = { id: "user-1" } as User;
const ID = "11111111-1111-4111-8111-111111111111";

function req(id: string, body: unknown): Request {
  return new Request(`https://x.test/api/inbox/${id}/state`, {
    method: "POST",
    body: JSON.stringify(body),
  });
}

beforeEach(() => {
  rpc.mockReset();
  reportSilentFallback.mockReset();
});

describe("inboxStateHandler", () => {
  it("applies a valid transition (200) and calls the RPC with the parsed id + action", async () => {
    rpc.mockResolvedValue({ error: null });
    const res = await inboxStateHandler(req(ID, { action: "acted" }), USER);
    expect(res.status).toBe(200);
    expect(rpc).toHaveBeenCalledWith("set_inbox_item_state", {
      p_id: ID,
      p_action: "acted",
    });
  });

  it("rejects a malformed id (400) before touching the DB", async () => {
    const res = await inboxStateHandler(req("not-a-uuid", { action: "read" }), USER);
    expect(res.status).toBe(400);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("rejects an invalid action (400)", async () => {
    const res = await inboxStateHandler(req(ID, { action: "nuke" }), USER);
    expect(res.status).toBe(400);
    expect(rpc).not.toHaveBeenCalled();
  });

  it("maps 42501 (auth pin / missing row) to 404 — no existence oracle", async () => {
    rpc.mockResolvedValue({ error: { code: "42501", message: "not authorized" } });
    const res = await inboxStateHandler(req(ID, { action: "archived" }), USER);
    expect(res.status).toBe(404);
  });

  it("maps P0001 (archive-guard / invalid transition) to 409", async () => {
    rpc.mockResolvedValue({
      error: { code: "P0001", message: "cannot archive an un-acted action_required item" },
    });
    const res = await inboxStateHandler(req(ID, { action: "archived" }), USER);
    expect(res.status).toBe(409);
  });

  it("maps an unexpected error to 500 and mirrors to Sentry (no PII)", async () => {
    rpc.mockResolvedValue({ error: { code: "XX000", message: "boom" } });
    const res = await inboxStateHandler(req(ID, { action: "read" }), USER);
    expect(res.status).toBe(500);
    expect(reportSilentFallback).toHaveBeenCalled();
  });
});
