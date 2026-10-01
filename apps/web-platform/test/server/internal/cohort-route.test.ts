import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Capture the inherited value so afterEach restores it — INNGEST_MANUAL_TRIGGER_SECRET
// is security-relevant; never leak a stub/delete to a sibling file in the worker.
const ORIG_SECRET = process.env.INNGEST_MANUAL_TRIGGER_SECRET;

const { mockReportSilentFallback, mockUpdate, mockEq, mockSelect } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockUpdate: vi.fn(),
  mockEq: vi.fn(),
  mockSelect: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: () => ({ update: mockUpdate }),
  }),
}));

import { PATCH } from "@/app/api/internal/cohort/route";

const SECRET = "cohort-route-test-secret";
const USER_ID = "3f9a2b1c-1234-4abc-8def-0123456789ab";

function makeRequest(
  body: object | string,
  opts: { authorization?: string | null } = {},
): Request {
  const raw = typeof body === "string" ? body : JSON.stringify(body);
  const headers = new Headers({ "content-type": "application/json" });
  const auth =
    "authorization" in opts ? opts.authorization : `Bearer ${SECRET}`;
  if (auth !== null && auth !== undefined) headers.set("authorization", auth);
  return new Request("https://soleur.ai/api/internal/cohort", {
    method: "PATCH",
    headers,
    body: raw,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  process.env.INNGEST_MANUAL_TRIGGER_SECRET = SECRET;
  // update() returns a query builder: .eq returns the builder, .select resolves
  // to the matched rows — the route treats an empty data array as a no-op write.
  mockUpdate.mockReturnValue({ eq: mockEq });
  mockEq.mockReturnValue({ select: mockSelect });
  mockSelect.mockResolvedValue({ data: [{ id: USER_ID }], error: null });
});

afterEach(() => {
  if (ORIG_SECRET === undefined) delete process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  else process.env.INNGEST_MANUAL_TRIGGER_SECRET = ORIG_SECRET;
});

describe("PATCH /api/internal/cohort — auth / fail-closed", () => {
  it("returns 503 (fail-closed) when the secret is unset", async () => {
    delete process.env.INNGEST_MANUAL_TRIGGER_SECRET;
    const res = await PATCH(makeRequest({ userId: USER_ID, cohort_key: "alpha" }));
    expect(res.status).toBe(503);
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  it("returns 401 on a missing Authorization header", async () => {
    const res = await PATCH(
      makeRequest({ userId: USER_ID, cohort_key: "alpha" }, { authorization: null }),
    );
    expect(res.status).toBe(401);
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  it("returns 401 on a wrong bearer", async () => {
    const res = await PATCH(
      makeRequest(
        { userId: USER_ID, cohort_key: "alpha" },
        { authorization: "Bearer wrong" },
      ),
    );
    expect(res.status).toBe(401);
    expect(mockUpdate).not.toHaveBeenCalled();
  });
});

describe("PATCH /api/internal/cohort — validation", () => {
  it("rejects malformed JSON", async () => {
    const res = await PATCH(makeRequest("{not json"));
    expect(res.status).toBe(400);
  });

  it("rejects missing userId", async () => {
    const res = await PATCH(makeRequest({ cohort_key: "alpha" }));
    expect(res.status).toBe(400);
  });

  it("rejects a non-UUID userId before touching the DB", async () => {
    const res = await PATCH(makeRequest({ userId: "u1", cohort_key: "alpha" }));
    expect(res.status).toBe(400);
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  it("rejects a cohort_key outside ^[a-z0-9-]+$", async () => {
    const res = await PATCH(
      makeRequest({ userId: USER_ID, cohort_key: "Alpha_01!" }),
    );
    expect(res.status).toBe(400);
    expect(mockUpdate).not.toHaveBeenCalled();
  });

  it("normalizes case and whitespace before writing", async () => {
    const res = await PATCH(
      makeRequest({ userId: USER_ID, cohort_key: "  Alpha-01 " }),
    );
    expect(res.status).toBe(200);
    expect(mockUpdate).toHaveBeenCalledWith({ cohort_key: "alpha-01" });
    expect(mockEq).toHaveBeenCalledWith("id", USER_ID);
  });
});

describe("PATCH /api/internal/cohort — write", () => {
  it("updates users.cohort_key via the service client", async () => {
    const res = await PATCH(makeRequest({ userId: USER_ID, cohort_key: "alpha" }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.cohort_key).toBe("alpha");
  });

  it("reports and 500s when the update errors", async () => {
    mockSelect.mockResolvedValueOnce({ data: null, error: { message: "boom" } });
    const res = await PATCH(makeRequest({ userId: USER_ID, cohort_key: "alpha" }));
    expect(res.status).toBe(500);
    expect(mockReportSilentFallback).toHaveBeenCalled();
  });

  it("returns 404 when zero rows match — a mistyped userId is never a silent ok", async () => {
    mockSelect.mockResolvedValueOnce({ data: [], error: null });
    const res = await PATCH(makeRequest({ userId: USER_ID, cohort_key: "alpha" }));
    expect(res.status).toBe(404);
    const json = await res.json();
    expect(json.error).toBe("user_not_found");
  });
});
