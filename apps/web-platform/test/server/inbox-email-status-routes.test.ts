import { describe, it, expect, vi, beforeEach } from "vitest";

// Phase 5a RED — POST /api/inbox/emails/[id]/acknowledge + .../archive.
// Contract (plan row `app/api/inbox/emails/[id]/acknowledge/route.ts`):
//   - POST verb-subresources (lifecycle-transition family precedent:
//     dashboard/today/[id]/cancel — POST-on-verb, never PATCH /status).
//   - withUserRateLimit (401 unauth at the wrapper) + user-context client.
//   - Each calls the `set_email_triage_status` SECURITY DEFINER RPC — the
//     one-way transition matrix and ownership pin live IN the DB.
//   - RPC error mapping: 42501 (ownership/not-found collapse — no existence
//     oracle) → 404; P0001 (invalid transition) → 409; else → 500.
//   - HTTP-only exports: POST is the only verb exported.

// withUserRateLimit hashes the user id for Sentry scoping; the hasher
// throws when the pepper env is unset (precedent: with-user-rate-limit.test.ts).
vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const { mockGetUser, mockRpc } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockRpc: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
  })),
  createServiceClient: vi.fn(() => {
    throw new Error("service client must never be used by these routes (RLS bypass)");
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  // userid-pseudonymize re-exports the hasher from observability; the
  // rate-limit wrapper calls it for Sentry scoping.
  hashUserId: vi.fn((v: string) => `hashed-${v}`),
}));

async function importAcknowledge() {
  return await import("@/app/api/inbox/emails/[id]/acknowledge/route");
}
async function importArchive() {
  return await import("@/app/api/inbox/emails/[id]/archive/route");
}

const EMAIL_ID = "7f1e6a52-9d34-4c6a-9b1e-0a2f3b4c5d6e";

function post(url: string): Request {
  return new Request(url, { method: "POST" });
}

function urlFor(verb: "acknowledge" | "archive", id: string = EMAIL_ID): string {
  return `https://app.soleur.ai/api/inbox/emails/${id}/${verb}`;
}

describe("POST /api/inbox/emails/[id]/{acknowledge,archive}", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockRpc.mockResolvedValue({ data: null, error: null });
  });

  it("acknowledge calls the RPC with p_status='acknowledged' and returns 200", async () => {
    const { POST } = await importAcknowledge();
    const res = await POST(post(urlFor("acknowledge")));
    expect(res.status).toBe(200);
    expect(mockRpc).toHaveBeenCalledWith("set_email_triage_status", {
      p_id: EMAIL_ID,
      p_status: "acknowledged",
    });
  });

  it("archive calls the RPC with p_status='archived' and returns 200", async () => {
    const { POST } = await importArchive();
    const res = await POST(post(urlFor("archive")));
    expect(res.status).toBe(200);
    expect(mockRpc).toHaveBeenCalledWith("set_email_triage_status", {
      p_id: EMAIL_ID,
      p_status: "archived",
    });
  });

  it("returns 401 when unauthenticated and never invokes the RPC", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const { POST } = await importAcknowledge();
    const res = await POST(post(urlFor("acknowledge")));
    expect(res.status).toBe(401);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("maps RPC ownership/not-found error (42501) to 404", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { code: "42501", message: "set_email_triage_status: not authorized" },
    });
    const { POST } = await importAcknowledge();
    const res = await POST(post(urlFor("acknowledge")));
    expect(res.status).toBe(404);
  });

  it("maps RPC invalid-transition error (P0001) to 409", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: {
        code: "P0001",
        message: "set_email_triage_status: transition from archived rejected",
      },
    });
    const { POST } = await importArchive();
    const res = await POST(post(urlFor("archive")));
    expect(res.status).toBe(409);
  });

  it("maps any other RPC error to 500", async () => {
    mockRpc.mockResolvedValue({
      data: null,
      error: { code: "XX000", message: "internal" },
    });
    const { POST } = await importArchive();
    const res = await POST(post(urlFor("archive")));
    expect(res.status).toBe(500);
  });

  it("rejects a non-uuid id segment with 400 before the RPC", async () => {
    const { POST } = await importAcknowledge();
    const res = await POST(post(urlFor("acknowledge", "not-a-uuid")));
    expect(res.status).toBe(400);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("exports POST as the only HTTP verb on both routes (cq-nextjs-route-files-http-only-exports)", async () => {
    for (const mod of [await importAcknowledge(), await importArchive()]) {
      expect(mod.POST).toBeTypeOf("function");
      for (const verb of ["GET", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]) {
        expect((mod as Record<string, unknown>)[verb]).toBeUndefined();
      }
    }
  });
});
