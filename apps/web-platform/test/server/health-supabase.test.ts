import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://test.supabase.co",
}));

// session-metrics pulls in ws-handler which calls createServiceClient() at
// module load. Stub both so the supabase-checker test file only exercises
// checkSupabase without booting unrelated server subsystems.
vi.mock("../../server/session-metrics", () => ({
  getActiveSessionCount: () => 0,
  getActiveWorkspaceCount: () => 0,
}));

describe("checkSupabase URL", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "test-anon-key";
  });

  it("fetches users table query, not schema listing", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockResolvedValue(new Response("[]", { status: 200 }));

    const { buildHealthResponse } = await import("../../server/health");
    await buildHealthResponse();

    expect(fetchSpy).toHaveBeenCalledOnce();
    const url = fetchSpy.mock.calls[0][0] as string;
    expect(url).toBe(
      "https://test.supabase.co/rest/v1/users?select=id&limit=1",
    );
  });

  it("returns connected when table query returns 200", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("[]", { status: 200 }),
    );

    const { buildHealthResponse } = await import("../../server/health");
    const response = await buildHealthResponse();
    expect(response.supabase).toBe("connected");
  });

  it("returns error when table query returns non-200", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("Unauthorized", { status: 401 }),
    );

    const { buildHealthResponse } = await import("../../server/health");
    const response = await buildHealthResponse();
    expect(response.supabase).toBe("error");
  });

  it("returns error when fetch throws (network error)", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(
      new Error("Network error"),
    );

    const { buildHealthResponse } = await import("../../server/health");
    const response = await buildHealthResponse();
    expect(response.supabase).toBe("error");
  });
});
