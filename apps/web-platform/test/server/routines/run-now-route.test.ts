import { beforeEach, describe, expect, it, vi } from "vitest";

const { mockGetUser, mockRunRoutine } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockRunRoutine: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser: mockGetUser } }),
}));
vi.mock("@/server/routines/run-routine", () => ({
  runRoutine: mockRunRoutine,
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

import { POST } from "@/app/api/dashboard/routines/run/route";

function req(body: unknown, origin?: string) {
  return new Request("https://soleur.ai/api/dashboard/routines/run", {
    method: "POST",
    headers: origin ? { origin } : undefined,
    body: JSON.stringify(body),
  });
}

beforeEach(() => {
  mockGetUser.mockReset();
  mockRunRoutine.mockReset();
  mockGetUser.mockResolvedValue({ data: { user: { id: "op-1" } } });
});

describe("POST /api/dashboard/routines/run", () => {
  it("403 on a forged cross-origin request (CSRF), before auth or dispatch", async () => {
    const res = await POST(req({ fnId: "cron-daily-triage" }, "https://evil.example"));
    expect(res.status).toBe(403);
    expect(mockGetUser).not.toHaveBeenCalled();
    expect(mockRunRoutine).not.toHaveBeenCalled();
  });

  it("401 without a session", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(req({ fnId: "cron-daily-triage" }));
    expect(res.status).toBe(401);
    expect(mockRunRoutine).not.toHaveBeenCalled();
  });

  it("400 when fnId missing", async () => {
    const res = await POST(req({}));
    expect(res.status).toBe(400);
  });

  it("202 + dispatches as human for an allowed routine", async () => {
    mockRunRoutine.mockResolvedValue({ ok: true, event: "cron/daily-triage.manual-trigger" });
    const res = await POST(req({ fnId: "cron-daily-triage" }));
    expect(res.status).toBe(202);
    expect(mockRunRoutine).toHaveBeenCalledWith(
      expect.objectContaining({ fnId: "cron-daily-triage", actorClass: "human", actorId: "op-1", confirmed: false }),
    );
  });

  it("409 confirmation_required for a protected routine without confirmed", async () => {
    mockRunRoutine.mockResolvedValue({ ok: false, code: "confirmation_required", status: 409 });
    const res = await POST(req({ fnId: "cron-content-publisher" }));
    expect(res.status).toBe(409);
    const json = await res.json();
    expect(json.error).toBe("confirmation_required");
  });

  it("passes confirmed:true through", async () => {
    mockRunRoutine.mockResolvedValue({ ok: true, event: "cron/content-publisher.manual-trigger" });
    await POST(req({ fnId: "cron-content-publisher", confirmed: true }));
    expect(mockRunRoutine).toHaveBeenCalledWith(
      expect.objectContaining({ confirmed: true }),
    );
  });
});
