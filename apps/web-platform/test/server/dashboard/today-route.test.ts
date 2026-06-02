import { describe, test, expect, vi, beforeEach } from "vitest";

// PR-H (#3244) Phase 6 — /api/dashboard/today server route (multi-source).
//
// Returns drafts filtered to status=draft AND tier IN (external_brand_critical,
// external_low_stakes). Inline-ranked + sliced to ≤7 items; remainder in
// `extras`. Cache-Control: private, max-age=60 (Art. 14 minimization).

const { mockGetUser, mockEq, mockIn, mockOrder, mockLimit, mockSelect, mockFrom, mockResolveWorkspace } = vi.hoisted(() => {
  const mockLimit = vi.fn();
  const mockOrder = vi.fn(() => ({ limit: mockLimit }));
  const mockIn = vi.fn(() => ({ eq: mockEq, in: mockIn, order: mockOrder }));
  const mockEq: ReturnType<typeof vi.fn> = vi.fn(() => ({
    eq: mockEq,
    in: mockIn,
    order: mockOrder,
  }));
  const mockSelect = vi.fn(() => ({ eq: mockEq, in: mockIn, order: mockOrder }));
  const mockFrom = vi.fn(() => ({ select: mockSelect }));
  return {
    mockGetUser: vi.fn(),
    mockEq,
    mockIn,
    mockOrder,
    mockLimit,
    mockSelect,
    mockFrom,
    mockResolveWorkspace: vi.fn(),
  };
});

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

// Active-workspace resolver: scope the Today read to the caller's SELECTED
// workspace (claim → solo fallback). Mocked so route tests assert the query
// shape without exercising the user_session_state read path.
vi.mock("@/server/workspace-resolver", () => ({
  resolveCurrentWorkspaceId: mockResolveWorkspace,
}));

import { GET } from "@/app/api/dashboard/today/route";

function makeRequest(): Request {
  return new Request("https://app.soleur.ai/api/dashboard/today");
}

function fixtureRow(overrides: Partial<{ id: string; urgency: string; source: string; sourceRef: string | null; createdAt: string }>) {
  return {
    id: overrides.id ?? "msg-x",
    source: overrides.source ?? "stripe",
    source_ref: overrides.sourceRef ?? null,
    owning_domain: "cfo",
    draft_preview: "hello",
    urgency: overrides.urgency ?? "medium",
    created_at: overrides.createdAt ?? "2026-05-19T12:00:00Z",
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockLimit.mockResolvedValue({ data: [], error: null });
  mockGetUser.mockResolvedValue({
    data: { user: { id: "founder-A" } },
    error: null,
  });
  // Default: solo workspace active (= userId), matching the common case.
  mockResolveWorkspace.mockResolvedValue("founder-A");
});

describe("/api/dashboard/today (PR-H)", () => {
  test("returns 401 when no authenticated user", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
    const res = await GET(makeRequest());
    expect(res.status).toBe(401);
    expect(mockFrom).not.toHaveBeenCalled();
  });

  test("queries messages with tier IN (external_brand_critical, external_low_stakes) AND status=draft", async () => {
    await GET(makeRequest());
    expect(mockFrom).toHaveBeenCalledWith("messages");
    expect(mockIn).toHaveBeenCalledWith("tier", [
      "external_brand_critical",
      "external_low_stakes",
    ]);
    expect(mockEq).toHaveBeenCalledWith("user_id", "founder-A");
    expect(mockEq).toHaveBeenCalledWith("status", "draft");
  });

  // ── Workspace-scoping leak fix (knowledge-drift cross-workspace) ──────────
  // An owner of two workspaces saw a solo-pinned KB-drift card on BOTH. The
  // read must scope to the ACTIVE workspace, not just user_id. See plan
  // 2026-06-02-fix-workspace-scoping-leak; root cause: today/route had no
  // workspace_id filter and messages RLS (is_workspace_member) passes for an
  // owner across ALL their workspaces.

  test("AC1: scopes the read to the ACTIVE workspace (resolveCurrentWorkspaceId)", async () => {
    // Owner is currently on their SECOND workspace, not the solo one.
    mockResolveWorkspace.mockResolvedValue("workspace-B");
    await GET(makeRequest());
    expect(mockResolveWorkspace).toHaveBeenCalledWith(
      "founder-A",
      expect.anything(),
    );
    // The select chain MUST filter by the active workspace — without this the
    // solo-pinned card leaks onto every workspace the owner switches to.
    expect(mockEq).toHaveBeenCalledWith("workspace_id", "workspace-B");
  });

  test("AC1: workspace_id filter is ADDITIVE to user_id (exactly one, = active id)", async () => {
    // Distinct from the test above: prove the active-workspace filter does not
    // REPLACE the existing user_id scope (belt-and-suspenders), and that exactly
    // ONE workspace_id predicate is emitted carrying the resolved active id — no
    // stray/duplicate filter that could pair a wrong workspace.
    mockResolveWorkspace.mockResolvedValue("workspace-B");
    await GET(makeRequest());
    const wsCalls = mockEq.mock.calls.filter((c) => c[0] === "workspace_id");
    expect(wsCalls).toEqual([["workspace_id", "workspace-B"]]);
    // user_id scope still present alongside it (not replaced by the new filter).
    expect(mockEq).toHaveBeenCalledWith("user_id", "founder-A");
  });

  test("returns { items: [], extras: [] } on empty result", async () => {
    mockLimit.mockResolvedValue({ data: [], error: null });
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { items: unknown[]; extras: unknown[] };
    expect(body.items).toEqual([]);
    expect(body.extras).toEqual([]);
  });

  test("returns the disclosure constant alongside items (agent-parity)", async () => {
    const res = await GET(makeRequest());
    const body = (await res.json()) as { disclosure: string };
    expect(body.disclosure).toMatch(/disclaims warranty for runtime cost/);
  });

  test("AC7: 30 mock items → items.length === 7 AND extras.length === 23", async () => {
    const rows = Array.from({ length: 30 }, (_, i) =>
      fixtureRow({
        id: `msg-${i}`,
        urgency: "normal",
        createdAt: new Date(2026, 4, 19, 12, i).toISOString(),
      }),
    );
    mockLimit.mockResolvedValue({ data: rows, error: null });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: unknown[]; extras: unknown[] };
    expect(body.items).toHaveLength(7);
    expect(body.extras).toHaveLength(23);
  });

  test("strict-tier ordering: critical → high → medium → normal → low", async () => {
    mockLimit.mockResolvedValue({
      data: [
        fixtureRow({ id: "low-1", urgency: "low" }),
        fixtureRow({ id: "critical-1", urgency: "critical" }),
        fixtureRow({ id: "normal-1", urgency: "normal" }),
        fixtureRow({ id: "high-1", urgency: "high" }),
        fixtureRow({ id: "medium-1", urgency: "medium" }),
      ],
      error: null,
    });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: { id: string; urgency: string }[] };
    expect(body.items.map((i) => i.id)).toEqual([
      "critical-1",
      "high-1",
      "medium-1",
      "normal-1",
      "low-1",
    ]);
  });

  test("returns Cache-Control: private, max-age=60 (Art. 14 minimization)", async () => {
    const res = await GET(makeRequest());
    expect(res.headers.get("cache-control")).toBe("private, max-age=60");
  });

  test("returns 500 on DB read error", async () => {
    mockLimit.mockResolvedValue({ data: null, error: { message: "boom" } });
    const res = await GET(makeRequest());
    expect(res.status).toBe(500);
  });

  test("masks CVE draft_preview body server-side (keeps `<id> (<sev>)` header only)", async () => {
    mockLimit.mockResolvedValue({
      data: [
        {
          ...fixtureRow({
            id: "msg-cve-1",
            source: "github",
            sourceRef: "cve-GHSA-aaaa-bbbb-cccc",
            urgency: "high",
          }),
          draft_preview: "GHSA-aaaa-bbbb-cccc (high): malicious payload details — proprietary-internal-account-12345",
        },
      ],
      error: null,
    });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: { draftPreview: string }[] };
    // Header retained (ID + severity render path) but summary stripped from the wire.
    expect(body.items[0].draftPreview).toBe("GHSA-aaaa-bbbb-cccc (high)");
    expect(body.items[0].draftPreview).not.toContain("malicious payload");
    expect(body.items[0].draftPreview).not.toContain("proprietary-internal-account");
  });

  test("does NOT mask secret-scan draft_preview (secret_type is a public enum)", async () => {
    mockLimit.mockResolvedValue({
      data: [
        {
          ...fixtureRow({
            id: "msg-scan-1",
            source: "github",
            sourceRef: "secret-scan-jikig-ai:soleur:42",
            urgency: "high",
          }),
          draft_preview: "Secret scan alert #42: aws_access_key_id",
        },
      ],
      error: null,
    });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: { draftPreview: string }[] };
    expect(body.items[0].draftPreview).toBe("Secret scan alert #42: aws_access_key_id");
  });

  test("does NOT mask non-CVE github rows (PR/CI/issue keep full body)", async () => {
    mockLimit.mockResolvedValue({
      data: [
        {
          ...fixtureRow({
            id: "msg-pr-2",
            source: "github",
            sourceRef: "pr-jikig-ai:soleur:4066",
            urgency: "normal",
          }),
          draft_preview: "feat(pr-h): inline review fixes (https://github.com/jikig-ai/soleur/pull/4066)",
        },
      ],
      error: null,
    });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: { draftPreview: string }[] };
    expect(body.items[0].draftPreview).toContain("feat(pr-h)");
  });

  test("widens response item to include sourceRef (camelCase)", async () => {
    mockLimit.mockResolvedValue({
      data: [
        fixtureRow({
          id: "msg-pr-1",
          source: "github",
          sourceRef: "pr-jikig-ai-soleur-4066",
          urgency: "normal",
        }),
      ],
      error: null,
    });
    const res = await GET(makeRequest());
    const body = (await res.json()) as { items: { sourceRef: string; source: string }[] };
    expect(body.items[0].source).toBe("github");
    expect(body.items[0].sourceRef).toBe("pr-jikig-ai-soleur-4066");
  });
});
