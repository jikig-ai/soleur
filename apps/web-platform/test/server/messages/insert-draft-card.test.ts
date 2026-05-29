import { describe, it, expect, vi, beforeEach } from "vitest";

// The helper writes via getFreshTenantClient; capture the inserted row.
const { mockInsert, mockGetFreshTenantClient, mockResolveCurrentWorkspaceId, mockReportSilentFallback } =
  vi.hoisted(() => ({
    mockInsert: vi.fn(),
    mockGetFreshTenantClient: vi.fn(),
    mockResolveCurrentWorkspaceId: vi.fn(),
    mockReportSilentFallback: vi.fn(),
  }));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
}));

// If the helper ever (re)introduced selection semantics, this mock would be
// invoked — we assert it is NEVER called (solo-pin is structural).
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveCurrentWorkspaceId,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

// NOTE: redactGithubSourcedText is intentionally NOT mocked — we assert real
// redaction is applied to draft_preview.

import { insertDraftCard } from "@/server/messages/insert-draft-card";

const FOUNDER = "52af49c2-d68e-477b-ba76-129e41807c7c";

function baseInput() {
  return {
    founderId: FOUNDER,
    source: "kb-drift" as const,
    owning_domain: "knowledge",
    draft_preview: "1 KB-drift findings — review",
    tier: "external_low_stakes",
    urgency: "low",
    trust_tier: "internal_infra_auto",
    source_ref: "digest-abc",
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockGetFreshTenantClient.mockResolvedValue({
    from: () => ({ insert: mockInsert }),
  });
  mockInsert.mockResolvedValue({ error: null });
  mockResolveCurrentWorkspaceId.mockResolvedValue("SHOULD-NEVER-BE-USED");
});

describe("insertDraftCard — solo-pin (cross-tenant guard)", () => {
  it("pins workspace_id to founderId and NEVER consults resolveCurrentWorkspaceId", async () => {
    const r = await insertDraftCard(baseInput());
    expect(r).toEqual({ status: "inserted", id: expect.any(String) });
    expect(mockGetFreshTenantClient).toHaveBeenCalledWith(FOUNDER);
    expect(mockResolveCurrentWorkspaceId).not.toHaveBeenCalled(); // selection semantics never used
    const row = mockInsert.mock.calls[0][0];
    expect(row.workspace_id).toBe(FOUNDER); // solo workspace (ADR-038 N2)
    expect(row.user_id).toBe(FOUNDER);
  });
});

describe("insertDraftCard — row shape (Decision A)", () => {
  it("supplies template_id='default_legacy' and status='draft'", async () => {
    await insertDraftCard(baseInput());
    const row = mockInsert.mock.calls[0][0];
    expect(row.template_id).toBe("default_legacy");
    expect(row.status).toBe("draft");
    expect(row.source).toBe("kb-drift");
  });

  it("redacts draft_preview (FR5 single choke point)", async () => {
    await insertDraftCard({ ...baseInput(), draft_preview: "broken link → mailto leak: a@b.com here" });
    const row = mockInsert.mock.calls[0][0];
    expect(row.draft_preview).not.toContain("a@b.com");
  });

  it("omits action_class and source_ref from the row when absent", async () => {
    const { source_ref: _sr, ...noRef } = baseInput();
    void _sr;
    await insertDraftCard(noRef);
    const row = mockInsert.mock.calls[0][0];
    expect(row).not.toHaveProperty("action_class");
    expect(row.source_ref).toBeNull();
  });

  it("includes action_class when provided", async () => {
    await insertDraftCard({ ...baseInput(), action_class: "knowledge.kb_drift" });
    const row = mockInsert.mock.calls[0][0];
    expect(row.action_class).toBe("knowledge.kb_drift");
  });
});

describe("insertDraftCard — error mapping", () => {
  it("maps 23505 → deduped (no throw, no Sentry)", async () => {
    mockInsert.mockResolvedValueOnce({ error: { code: "23505", message: "dup" } });
    const r = await insertDraftCard(baseInput());
    expect(r).toEqual({ status: "deduped" });
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("mirrors and throws on a non-dedup error (incl. 23514 CHECK)", async () => {
    mockInsert.mockResolvedValueOnce({ error: { code: "23514", message: "check violation" } });
    await expect(insertDraftCard(baseInput())).rejects.toThrow(/23514/);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.objectContaining({ code: "23514" }),
      expect.objectContaining({ feature: "insert-draft-card", op: "persist" }),
    );
  });
});
