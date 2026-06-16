import { describe, it, expect, vi, beforeEach } from "vitest";

// feat-reasoning-chat-boxes (#5370) — column-contract + solo-pin + redaction
// gate for the turn_summary write choke point. Mirrors insert-draft-card.test.ts.
const {
  mockInsert,
  mockGetFreshTenantClient,
  mockResolveCurrentWorkspaceId,
  mockReportSilentFallback,
} = vi.hoisted(() => ({
  mockInsert: vi.fn(),
  mockGetFreshTenantClient: vi.fn(),
  mockResolveCurrentWorkspaceId: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
}));

// Must NEVER be consulted — the solo-pin is structural (no selection semantics).
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveCurrentWorkspaceId,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

// formatAssistantText is intentionally NOT mocked — assert real path scrubbing.

import { insertTurnSummary } from "@/server/messages/insert-turn-summary";

const FOUNDER = "52af49c2-d68e-477b-ba76-129e41807c7c";
const CONV = "9c1d2e3f-4a5b-6c7d-8e9f-0a1b2c3d4e5f";

beforeEach(() => {
  vi.clearAllMocks();
  mockGetFreshTenantClient.mockResolvedValue({
    from: () => ({ insert: mockInsert }),
  });
  mockInsert.mockResolvedValue({ error: null });
  mockResolveCurrentWorkspaceId.mockResolvedValue("SHOULD-NEVER-BE-USED");
});

describe("insertTurnSummary — full NOT-NULL column contract (P0-1)", () => {
  it("sets conversation_id, workspace_id=founderId, template_id, user_id=founderId, role, message_kind", async () => {
    const r = await insertTurnSummary({
      founderId: FOUNDER,
      conversationId: CONV,
      content: "Fixed the side panel so it stays open on mobile.",
    });
    expect(r).toEqual({ status: "inserted", id: expect.any(String) });
    expect(mockGetFreshTenantClient).toHaveBeenCalledWith(FOUNDER);
    const row = mockInsert.mock.calls[0][0];
    expect(row.conversation_id).toBe(CONV); // messages_row_kind_chk chat-row branch
    expect(row.workspace_id).toBe(FOUNDER); // solo-pin (ADR-038 N2) — RLS member gate
    expect(row.template_id).toBe("default_legacy"); // mig 053 NOT NULL + regex
    expect(row.user_id).toBe(FOUNDER); // Art-15(4) un-redacted DSAR export
    expect(row.role).toBe("assistant"); // mig 105 messages_message_kind_chk
    expect(row.message_kind).toBe("turn_summary");
    expect(typeof row.content).toBe("string");
    expect(row.content.length).toBeGreaterThan(0);
  });

  it("NEVER consults resolveCurrentWorkspaceId (solo-pin is structural)", async () => {
    await insertTurnSummary({ founderId: FOUNDER, conversationId: CONV, content: "done" });
    expect(mockResolveCurrentWorkspaceId).not.toHaveBeenCalled();
  });
});

describe("insertTurnSummary — redaction choke point (P2)", () => {
  it("scrubs a host/sandbox path prefix from content before insert", async () => {
    await insertTurnSummary({
      founderId: FOUNDER,
      conversationId: CONV,
      content: "Saved the file at /workspaces/11111111-1111-1111-1111-111111111111/notes.md ok",
    });
    const row = mockInsert.mock.calls[0][0];
    expect(row.content).not.toContain("/workspaces/11111111-1111-1111-1111-111111111111/");
  });
});

describe("insertTurnSummary — failure handling", () => {
  it("mirrors to Sentry and throws on a DB error (never swallows)", async () => {
    mockInsert.mockResolvedValue({ error: { code: "23502", message: "null value" } });
    await expect(
      insertTurnSummary({ founderId: FOUNDER, conversationId: CONV, content: "x" }),
    ).rejects.toThrow(/insertTurnSummary failed \(23502\)/);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
  });
});
