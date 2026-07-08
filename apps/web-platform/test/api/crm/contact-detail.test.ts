import { describe, test, expect, vi, beforeEach } from "vitest";

// GET /api/crm/contacts/[id] (feat-beta-crm-ui #6172) — the atomic detail read
// via crm_get_contact_detail RPC:
//  - 401 unauthenticated
//  - 404 { error: "not_found" }, BYTE-IDENTICAL for never-existed / erased /
//    cross-owner (RPC 42501) and malformed uuid (22P02) — no existence oracle,
//    no Sentry (AC2)
//  - 5xx PII-free (NOT 200-with-data) on any OTHER RPC error — the fail-closed
//    accountability-gap signal, mirrored to Sentry with no PII (AC3/AC5)
//  - 200 { contact, notes, transitions } on success

const { mockGetUser, mockRpc, mockCaptureException } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockRpc: vi.fn(),
  mockCaptureException: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
  })),
}));

vi.mock("@sentry/nextjs", () => ({ captureException: mockCaptureException }));

import { GET } from "@/app/api/crm/contacts/[id]/route";

const call = (id: string) =>
  GET(new Request(`http://x/api/crm/contacts/${id}`), {
    params: Promise.resolve({ id }),
  });

beforeEach(() => {
  mockGetUser.mockReset();
  mockRpc.mockReset();
  mockCaptureException.mockReset();
  mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
});

describe("GET /api/crm/contacts/[id]", () => {
  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await call("c1");
    expect(res.status).toBe(401);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  test("200 returns the RPC jsonb { contact, notes, transitions }", async () => {
    const detail = {
      contact: { id: "c1", company: "Bright Ledger", stage: "qualified" },
      notes: [{ id: "n1", body: "hi", lens: ["sales"] }],
      transitions: [{ id: "t1", to_stage: "qualified" }],
    };
    mockRpc.mockResolvedValue({ data: detail, error: null });
    const res = await call("c1");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual(detail);
    expect(mockRpc).toHaveBeenCalledWith("crm_get_contact_detail", {
      p_contact_id: "c1",
    });
  });

  test("no existence oracle: never-existed / erased / foreign (42501) and malformed uuid (22P02) all return a byte-identical 404", async () => {
    const bodies: string[] = [];
    const statuses: number[] = [];
    for (const err of [
      { code: "42501", message: "not authorized" }, // missing / erased / foreign
      { code: "42501", message: "not authorized" }, // (2nd instance — must match)
      { code: "22P02", message: "invalid input syntax for type uuid" }, // malformed
    ]) {
      mockRpc.mockResolvedValueOnce({ data: null, error: err });
      const res = await call("whatever");
      statuses.push(res.status);
      bodies.push(await res.text());
    }
    expect(statuses).toEqual([404, 404, 404]);
    expect(new Set(bodies).size).toBe(1); // byte-identical
    expect(JSON.parse(bodies[0])).toEqual({ error: "not_found" });
    // Expected-safe probe — never paged.
    expect(mockCaptureException).not.toHaveBeenCalled();
  });

  test("a THROWN rpc rejection (network/driver) is mirrored PII-free with the surface tag, not left untagged", async () => {
    mockRpc.mockRejectedValue(
      Object.assign(new Error("fetch failed for Marco Ruiz"), { code: "ECONN" }),
    );
    const res = await call("c1");
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "detail_query_error" });
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    const [errArg, ctxArg] = mockCaptureException.mock.calls[0];
    expect(JSON.stringify({ m: (errArg as Error).message, c: ctxArg })).not.toMatch(/Marco|fetch failed/);
    expect((errArg as Error).message).toBe("crm-contact-detail:ECONN");
    expect(ctxArg).toEqual({
      tags: { surface: "crm-contact-detail" },
      extra: { op: "detail", userId: "u1", code: "ECONN" },
    });
  });

  test("5xx PII-free (NOT 200-with-data) + PII-free Sentry mirror on a non-authz RPC error (AC3)", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: {
        code: "40001", // serialization / infra failure — the audit write failed
        message: "audit insert failed for Marco Ruiz",
        details: "Failing row contains (Bright Ledger, private note body)",
      },
    });
    const res = await call("c1");
    expect(res.status).toBe(502);
    const body = await res.json();
    expect(body).toEqual({ error: "detail_query_error" });
    expect(body).not.toHaveProperty("contact"); // never data-without-audit

    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    const [errArg, ctxArg] = mockCaptureException.mock.calls[0];
    const serialized = JSON.stringify({
      msg: (errArg as Error).message,
      ctx: ctxArg,
    });
    expect(serialized).not.toMatch(/Marco|Bright Ledger|Failing row|private note/);
    expect((errArg as Error).message).toBe("crm-contact-detail:40001");
    expect(ctxArg).toEqual({
      tags: { surface: "crm-contact-detail" },
      extra: { op: "detail", userId: "u1", code: "40001" },
    });
  });
});
