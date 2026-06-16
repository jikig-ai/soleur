import { describe, it, expect, vi, beforeEach } from "vitest";

// Route-gate tests for PUT /api/kb/c4/[...path] — the LOAD-BEARING security
// boundary (AC5–AC8). Hiding the client Code tab is cosmetic; this route is
// reachable via curl/devtools/stale-tab, so it must fail CLOSED (403) when
// `c4-edit` is OFF.
//
// Strategy: mock auth/path resolution, the writer, the supabase client, and
// identity resolution — but leave `@/lib/feature-flags/server` REAL so the gate
// runs the actual `getRuntimeFlag` env-fallback path. With FLAGSMITH unset, the
// snapshot comes from `FLAG_C4_EDIT` (0/1), which is exactly the prod
// outage-fallback fidelity the gate depends on.

const mocks = vi.hoisted(() => ({
  mockAuthResolve: vi.fn(),
  mockWriteC4Diagram: vi.fn(),
  mockResolveIdentity: vi.fn(),
  mockCreateClient: vi.fn(),
}));

vi.mock("@/server/kb-route-helpers", () => ({
  authenticateAndResolveKbPath: mocks.mockAuthResolve,
}));

vi.mock("@/server/c4-writer", () => ({
  writeC4Diagram: mocks.mockWriteC4Diagram,
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: mocks.mockCreateClient,
}));

vi.mock("@/lib/feature-flags/identity", () => ({
  resolveIdentity: mocks.mockResolveIdentity,
}));

import { PUT } from "@/app/api/kb/c4/[...path]/route";
import { __resetFeatureFlagsForTests } from "@/lib/feature-flags/server";

const OK_CTX = {
  ok: true as const,
  ctx: {
    user: { id: "user-1" },
    userData: {
      workspace_path: "/workspaces/ws-1",
      repo_url: "https://github.com/jikig-ai/soleur",
      github_installation_id: 42,
    },
    owner: "jikig-ai",
    repo: "soleur",
    relativePath: "engineering/architecture/diagrams/model.c4",
    filePath: "knowledge-base/engineering/architecture/diagrams/model.c4",
    kbRoot: "/workspaces/ws-1/knowledge-base",
    fullPath: "/workspaces/ws-1/knowledge-base/engineering/architecture/diagrams/model.c4",
    ext: ".c4",
  },
};

const PRD_IDENTITY = { userId: "user-1", role: "prd" as const, orgId: null };

function putRequest(content = "model {}") {
  return new Request("http://localhost:3000/api/kb/c4/engineering/architecture/diagrams/model.c4", {
    method: "PUT",
    headers: { "content-type": "application/json", origin: "http://localhost:3000" },
    body: JSON.stringify({ content }),
  });
}

const PARAMS = Promise.resolve({
  path: ["engineering", "architecture", "diagrams", "model.c4"],
});

beforeEach(() => {
  vi.clearAllMocks();
  // Force the env-fallback (Flagsmith-outage) path so the gate reads FLAG_C4_EDIT.
  delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
  __resetFeatureFlagsForTests();
  mocks.mockAuthResolve.mockResolvedValue(OK_CTX);
  mocks.mockCreateClient.mockResolvedValue({ __supabase: true });
  mocks.mockResolveIdentity.mockResolvedValue(PRD_IDENTITY);
  mocks.mockWriteC4Diagram.mockResolvedValue({
    ok: true,
    commitSha: "abc123",
    rerendered: true,
  });
});

describe("PUT /api/kb/c4/[...path] — c4-edit gate (security boundary)", () => {
  it("AC5 — flag OFF ⇒ 403 with a human-readable body, writeC4Diagram NOT called", async () => {
    process.env.FLAG_C4_EDIT = "0";
    const res = await PUT(putRequest(), { params: PARAMS });
    expect(res.status).toBe(403);
    const body = await res.json();
    expect(typeof body.error).toBe("string");
    expect(body.error.length).toBeGreaterThan(0);
    expect(body.error.toLowerCase()).toContain("concierge");
    expect(mocks.mockWriteC4Diagram).not.toHaveBeenCalled();
  });

  it("AC6 — Flagsmith outage + FLAG_C4_EDIT unset ⇒ fail-closed 403", async () => {
    delete process.env.FLAG_C4_EDIT; // env mirror absent ⇒ envIsOn → false
    const res = await PUT(putRequest(), { params: PARAMS });
    expect(res.status).toBe(403);
    expect(mocks.mockWriteC4Diagram).not.toHaveBeenCalled();
  });

  it("AC7 — flag ON ⇒ route proceeds to writeC4Diagram and returns 200", async () => {
    process.env.FLAG_C4_EDIT = "1";
    const res = await PUT(putRequest(), { params: PARAMS });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.commitSha).toBe("abc123");
    expect(mocks.mockWriteC4Diagram).toHaveBeenCalledTimes(1);
  });

  it("AC8 — resolves the REAL identity (createClient → resolveIdentity) before the gate", async () => {
    process.env.FLAG_C4_EDIT = "0";
    await PUT(putRequest(), { params: PARAMS });
    expect(mocks.mockCreateClient).toHaveBeenCalledTimes(1);
    expect(mocks.mockResolveIdentity).toHaveBeenCalledWith({ __supabase: true });
  });

  it("AC8b — identity resolves to prd on read error ⇒ still gated (fail-closed)", async () => {
    // resolveIdentity already swallows errors internally and returns ANON (prd);
    // a prd identity with the flag OFF must 403, never fall through to a write.
    process.env.FLAG_C4_EDIT = "0";
    mocks.mockResolveIdentity.mockResolvedValue({ userId: null, role: "prd", orgId: null });
    const res = await PUT(putRequest(), { params: PARAMS });
    expect(res.status).toBe(403);
    expect(mocks.mockWriteC4Diagram).not.toHaveBeenCalled();
  });

  it("auth/path failure short-circuits before the gate (unchanged behavior)", async () => {
    mocks.mockAuthResolve.mockResolvedValue({
      ok: false,
      response: new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 }),
    });
    const res = await PUT(putRequest(), { params: PARAMS });
    expect(res.status).toBe(401);
    expect(mocks.mockResolveIdentity).not.toHaveBeenCalled();
    expect(mocks.mockWriteC4Diagram).not.toHaveBeenCalled();
  });
});
