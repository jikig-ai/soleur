import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "fs";
import { join } from "path";

// ---------------------------------------------------------------------------
// ADR-044 PR-2b — `users.workspace_path` write-removal regression guards.
//
// PR-2b stops writing `workspace_path` to the `users` column (it is derived now;
// `workspace_status` stays). These tests fail if a future change RE-ADDS
// `workspace_path` to, or DROPS `workspace_status` from, the two write sites:
//   1. app/api/workspace/route.ts            — behavioral (route is invocable)
//   2. app/(auth)/callback/route.ts          — source-regression (success-path
//      mock harness is disproportionately heavy; see note on that block)
// ---------------------------------------------------------------------------

const USER_ID = "11111111-1111-1111-1111-111111111111";

// ---------------------------------------------------------------------------
// 1) app/api/workspace/route.ts — behavioral payload assertion.
//    Captures the `users` UPDATE payload (ready transition) and the JSON body.
// ---------------------------------------------------------------------------

// Capture every users.update() payload the route issues. The route does two
// updates (provisioning, then ready) — we assert against the LAST one.
const updatePayloads: Record<string, unknown>[] = [];

vi.mock("@/lib/supabase/server", () => {
  const serviceFrom = vi.fn((table: string) => {
    if (table !== "users") throw new Error(`unexpected table ${table}`);
    const chain = {
      select: () => chain,
      eq: () => chain,
      single: async () => ({ data: { workspace_status: "pending" }, error: null }),
      update: (payload: Record<string, unknown>) => {
        updatePayloads.push(payload);
        return { eq: async () => ({ error: null }) };
      },
    } as Record<string, unknown>;
    return chain;
  });
  return {
    createClient: async () => ({
      auth: { getUser: async () => ({ data: { user: { id: USER_ID } }, error: null }) },
    }),
    createServiceClient: () => ({ from: serviceFrom }),
  };
});

vi.mock("@/server/workspace", () => ({
  provisionWorkspace: vi.fn(async (id: string) => `/workspaces/${id}`),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: () => ({ valid: true, origin: "https://app.soleur.ai" }),
  rejectCsrf: () => new Response("csrf", { status: 403 }),
}));

vi.mock("@sentry/nextjs", () => ({
  withIsolationScope: (cb: () => void) => cb(),
  getCurrentScope: () => ({ setUser: () => {} }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/userid-pseudonymize", () => ({
  hashUserIdValue: (s: string) => `hash-${s}`,
}));

describe("POST /api/workspace — ready UPDATE payload (PR-2b workspace_path removal)", () => {
  beforeEach(() => {
    updatePayloads.length = 0;
  });

  it("writes workspace_status:'ready' and NOT workspace_path; response still returns workspace_path", async () => {
    const { POST } = await import("@/app/api/workspace/route");
    const res = await POST(
      new Request("https://app.soleur.ai/api/workspace", { method: "POST" }),
    );

    // The READY transition is the last users.update() the route performs.
    const readyPayload = updatePayloads.at(-1);
    expect(readyPayload).toBeDefined();
    expect(readyPayload).toMatchObject({ workspace_status: "ready" });
    // Regression guard: workspace_path must NOT be written to the users column.
    expect(readyPayload).not.toHaveProperty("workspace_path");

    // The path is still a caller-facing response contract (derived, not stored).
    const body = (await res.json()) as { status: string; workspace_path: string };
    expect(body.status).toBe("ready");
    expect(body.workspace_path).toBe(`/workspaces/${USER_ID}`);
  });
});

// ---------------------------------------------------------------------------
// 2) app/(auth)/callback/route.ts — source-regression assertion.
//    The success path (upsert + update) is reached only deep inside GET after a
//    full session exchange; standing up that mock harness is disproportionately
//    heavy (much more than ~40 lines). Per the review's explicit escape hatch, we
//    guard the two callback write payloads at the SOURCE: they must contain
//    `workspace_status` and must NOT contain `workspace_path`. LIMITATION: this is
//    a textual guard, not a runtime assertion — it catches a re-added
//    `workspace_path` literal but not a dynamically-injected one. Acceptable: the
//    write sites are static object literals.
// ---------------------------------------------------------------------------

describe("app/(auth)/callback/route.ts — workspace write payloads (source regression)", () => {
  const src = readFileSync(
    join(__dirname, "../app/(auth)/callback/route.ts"),
    "utf8",
  );

  it("never writes workspace_path to users in the callback provisioning path", () => {
    // No `workspace_path:` key anywhere in the callback source (the upsert and
    // the update both dropped it in PR-2b).
    expect(src).not.toMatch(/workspace_path\s*:/);
  });

  it("still writes workspace_status:'ready' on both the upsert and the update", () => {
    const readyWrites = src.match(/workspace_status:\s*"ready"/g) ?? [];
    // One in the fallback upsert, one in the existing-row update.
    expect(readyWrites.length).toBeGreaterThanOrEqual(2);
  });
});
