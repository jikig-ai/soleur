/**
 * #4672 task 3.1: POST /api/approvals/[id]/decide.
 * CSRF covered, cookie-authenticated (401 without a session), the decision runs on the USER client (never the service
 * client), the actor is never a body field, a missing row and a non-owner are the same 404, and the response carries ids
 * and timestamps only (never the action text).
 */
import { beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { APPROVAL_ID, CONVERSATION_ID, USER_ID, WORKSPACE_ID } from "../approval/fixtures";

const h = vi.hoisted(() => ({
  verified: { value: "00000000-0000-4000-8000-000000000007" as string | null },
  rpc: vi.fn(),
  userClient: vi.fn(),
  serviceClient: vi.fn(),
  report: vi.fn(),
  marker: vi.fn(),
}));

vi.mock("@/server/request-auth", () => ({ verifiedUserId: async () => h.verified.value }));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => {
    h.userClient();
    return { rpc: (...a: unknown[]) => h.rpc(...a) };
  },
}));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: (...a: unknown[]) => {
    h.serviceClient(...a);
    throw new Error("the decide route must never build a service client");
  },
}));
vi.mock("@/server/with-user-rate-limit", async () => {
  const { verifiedUserId } = await import("@/server/request-auth");
  return {
    withUserRateLimit: (handler: (req: Request, user: { id: string }) => Promise<Response>) => async (req: Request) => {
      const id = await verifiedUserId(req);
      if (!id) return Response.json({ error: "Unauthorized" }, { status: 401 });
      return handler(req, { id });
    },
  };
});
vi.mock("@/server/approval/ops", async (orig) => ({
  ...(await orig<typeof import("@/server/approval/ops")>()),
  reportApprovalOp: (...a: unknown[]) => h.report(...a),
  logApprovalMarker: (...a: unknown[]) => h.marker(...a),
}));

import { POST } from "@/app/api/approvals/[id]/decide/route";

const row = (over: Record<string, unknown> = {}) => ({
  id: APPROVAL_ID,
  workspace_id: WORKSPACE_ID,
  conversation_id: CONVERSATION_ID,
  tool_name: "mcp__soleur_platform__email_send",
  action_sha256: "a".repeat(64),
  status: "approved",
  expires_at: "2099-01-01T00:00:00Z",
  created_at: "2026-10-28T10:00:00Z",
  decided_at: "2026-10-28T10:02:00Z",
  decided_by: USER_ID,
  consumed_at: null,
  expired_at: null,
  unanswered_flagged_at: null,
  requested_by_user_id: null,
  ...over,
});

function req(body: unknown, opts: { id?: string; origin?: string | null; raw?: string } = {}) {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (opts.origin !== null) headers.origin = opts.origin ?? "http://localhost:3000";
  return new Request(`http://localhost:3000/api/approvals/${opts.id ?? APPROVAL_ID}/decide`, {
    method: "POST",
    headers,
    body: opts.raw ?? JSON.stringify(body),
  });
}

beforeEach(() => {
  vi.stubEnv("NODE_ENV", "development");
  h.verified.value = USER_ID;
  h.rpc.mockReset();
  h.userClient.mockReset();
  h.serviceClient.mockReset();
  h.report.mockReset();
  h.marker.mockReset();
  h.rpc.mockResolvedValue({ data: { outcome: "decided", approval: row() }, error: null });
});

describe("POST /api/approvals/[id]/decide", () => {
  it("rejects a cross-origin request (CSRF) before anything else, with no database call", async () => {
    const res = await POST(req({ decision: "approve" }, { origin: "https://evil.example" }));
    expect(res.status).toBe(403);
    expect(h.rpc).not.toHaveBeenCalled();
    expect(h.userClient).not.toHaveBeenCalled();
  });

  it("is cookie-authenticated: 401 without a verified session, no database call", async () => {
    h.verified.value = null;
    const res = await POST(req({ decision: "approve" }));
    expect(res.status).toBe(401);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("calls decide_approval on the USER client with the id and the decision, never the service client", async () => {
    const res = await POST(req({ decision: "approve" }));
    expect(res.status).toBe(200);
    expect(h.userClient).toHaveBeenCalledTimes(1);
    expect(h.serviceClient).not.toHaveBeenCalled();
    expect(h.rpc).toHaveBeenCalledWith("decide_approval", { p_id: APPROVAL_ID, p_decision: "approve" });
  });

  it("ignores any actor smuggled into the body: the RPC args are exactly id and decision", async () => {
    await POST(req({ decision: "deny", userId: "00000000-0000-4000-8000-0000000000ff", decided_by: "x", p_actor: "y" }));
    expect(h.rpc).toHaveBeenCalledWith("decide_approval", { p_id: APPROVAL_ID, p_decision: "deny" });
  });

  it("answers with ids, status and timestamps only: never the action text", async () => {
    h.rpc.mockResolvedValue({ data: { outcome: "decided", approval: row({ canonical_action: { body: "SECRET BODY" } }) }, error: null });
    const body = await (await POST(req({ decision: "approve" }))).json();
    expect(body.outcome).toBe("decided");
    expect(Object.keys(body.approval).sort()).toEqual(["created_at", "decided_at", "decided_by", "expires_at", "id", "status"]);
    expect(JSON.stringify(body)).not.toContain("SECRET BODY");
  });

  it("passes the non-decided outcomes through (conflict, expired, closed)", async () => {
    for (const outcome of ["conflict", "expired", "closed", "unchanged"]) {
      h.rpc.mockResolvedValue({ data: { outcome, approval: row() }, error: null });
      expect((await (await POST(req({ decision: "approve" }))).json()).outcome).toBe(outcome);
    }
  });

  it("a missing row and a non-owner are the SAME 404 (the RPC raises 42501 for both): no existence oracle", async () => {
    h.rpc.mockResolvedValue({ data: null, error: { message: "approval: not authorized", code: "42501" } });
    const res = await POST(req({ decision: "approve" }));
    expect(res.status).toBe(404);
    expect(await res.json()).toEqual({ error: "Not found" });
    expect(h.report).not.toHaveBeenCalled();
  });

  it("any other database error is a 500 with its own op and no database text", async () => {
    h.rpc.mockResolvedValue({ data: null, error: { message: "deadlock detected on row with secret", code: "40P01" } });
    const res = await POST(req({ decision: "approve" }));
    expect(res.status).toBe(500);
    expect(JSON.stringify(await res.json())).not.toContain("secret");
    expect(h.report).toHaveBeenCalledWith("decideFailed", expect.anything(), expect.objectContaining({ approvalId: APPROVAL_ID }));
  });

  it("validates the id and the decision before touching the database", async () => {
    expect((await POST(req({ decision: "approve" }, { id: "nope" }))).status).toBe(400);
    for (const decision of ["approve all", "APPROVE", "", 1, null, undefined]) {
      expect((await POST(req({ decision }))).status).toBe(400);
    }
    expect((await POST(req(null, { raw: "{not json" }))).status).toBe(400);
    expect(h.rpc).not.toHaveBeenCalled();
  });

  it("logs the decision marker (lifecycle reconstructable from one grep)", async () => {
    await POST(req({ decision: "approve" }));
    expect(h.marker).toHaveBeenCalledWith("SOLEUR_APPROVAL_DECIDED", expect.objectContaining({ approval_id: APPROVAL_ID, decision: "approve", outcome: "decided", path: "http" }));
  });
});

describe("route file conventions", () => {
  const src = readFileSync(join(__dirname, "../../app/api/approvals/[id]/decide/route.ts"), "utf8");
  it("exports only HTTP methods and route config (cq-nextjs-route-files-http-only-exports)", () => {
    const names = [...src.matchAll(/^export\s+(?:async\s+)?(?:function|const)\s+(\w+)/gm)].map((m) => m[1]);
    expect(names.sort()).toEqual(["POST", "dynamic"]);
  });
  it("calls validateOrigin inline and never references the service client", () => {
    expect(src).toContain("validateOrigin");
    expect(src).not.toMatch(/createServiceClient|service-role|supabase\/service/);
  });
  it("is not a PUBLIC_PATHS entry (cookie-authenticated)", async () => {
    const { PUBLIC_PATHS } = await import("@/lib/routes");
    expect(PUBLIC_PATHS.some((p: string) => "/api/approvals".startsWith(p) || p.startsWith("/api/approvals") || p.startsWith("/dashboard/approvals"))).toBe(false);
  });
});
