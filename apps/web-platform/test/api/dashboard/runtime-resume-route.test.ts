/**
 * feat-l5-runaway-guard PR-A — POST /api/dashboard/runtime/resume
 *
 * The operator-resume clearer: the ONLY code path that sets
 * users.runtime_paused_at = NULL (AC2, set-never-clear contract). Covers the
 * happy path, missing-session 401, CSRF rejection, a 0-row read-back guard,
 * and a source-scan proving no other clearer exists.
 */

import { describe, test, it, expect, vi, beforeEach } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

const {
  mockGetUser,
  mockServiceFrom,
  mockValidateOrigin,
  mockReportSilentFallback,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
}));

vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: vi.fn(() => ({ from: mockServiceFrom })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

const FOUNDER_ID = "founder-123";

// Service-role chain: .from("users").update({runtime_paused_at:null}).eq("id",…).select("id")
function setupServiceChain(result: { rows?: Array<{ id: string }>; error?: unknown }) {
  const captured = { patches: [] as Array<{ table: string; patch: unknown; eqArgs: unknown[] }> };
  const chain = {
    table: "",
    patch: undefined as unknown,
    eqArgs: [] as unknown[],
    from(table: string) {
      this.table = table;
      this.patch = undefined;
      this.eqArgs = [];
      return chain;
    },
    update(patch: unknown) {
      this.patch = patch;
      return chain;
    },
    eq(col: string, val: unknown) {
      this.eqArgs.push({ col, val });
      return chain;
    },
    select(_cols: string) {
      captured.patches.push({ table: this.table, patch: this.patch, eqArgs: [...this.eqArgs] });
      return Promise.resolve({
        data: result.error ? null : (result.rows ?? [{ id: FOUNDER_ID }]),
        error: result.error ?? null,
      });
    },
  };
  (mockServiceFrom as unknown as { mockImplementation: (impl: (t: string) => unknown) => void }).mockImplementation(
    (table: string) => chain.from(table),
  );
  return captured;
}

function makeRequest() {
  return new Request("https://app.soleur.ai/api/dashboard/runtime/resume", {
    method: "POST",
    headers: { Origin: "https://app.soleur.ai" },
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  mockGetUser.mockResolvedValue({ data: { user: { id: FOUNDER_ID } } });
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
});

describe("POST /api/dashboard/runtime/resume", () => {
  test("happy path: clears runtime_paused_at=NULL for the caller's own id", async () => {
    const captured = setupServiceChain({ rows: [{ id: FOUNDER_ID }] });
    const { POST } = await import("@/app/api/dashboard/runtime/resume/route");
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean };
    expect(body.ok).toBe(true);
    expect(captured.patches).toHaveLength(1);
    const update = captured.patches[0];
    expect(update.table).toBe("users");
    const patch = update.patch as Record<string, unknown>;
    expect(patch.runtime_paused_at).toBeNull();
    // Scoped to the caller's OWN server-derived id — no cross-tenant surface.
    expect(update.eqArgs).toEqual([{ col: "id", val: FOUNDER_ID }]);
  });

  test("no auth session → 401 (no write)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const captured = setupServiceChain({});
    const { POST } = await import("@/app/api/dashboard/runtime/resume/route");
    const res = await POST(makeRequest());
    expect(res.status).toBe(401);
    expect(captured.patches).toHaveLength(0);
  });

  test("CSRF rejection → 403", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "evil.example" });
    const { POST } = await import("@/app/api/dashboard/runtime/resume/route");
    const res = await POST(makeRequest());
    expect(res.status).toBe(403);
  });

  test("0-row read-back fails loud (missing user row) instead of false 200", async () => {
    setupServiceChain({ rows: [] });
    const { POST } = await import("@/app/api/dashboard/runtime/resume/route");
    const res = await POST(makeRequest());
    expect(res.status).toBe(500);
    expect(mockReportSilentFallback).toHaveBeenCalled();
  });
});

// AC2: the resume route is the ONLY code path that sets runtime_paused_at =
// NULL. Scan the server + app TS surface for any null-assignment; the sole
// permitted writer is the resume route.
describe("AC2 — set-never-clear: resume route is the only clearer", () => {
  const APP_ROOT = path.join(__dirname, "../../..");

  function walk(dir: string): string[] {
    const out: string[] = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === "node_modules" || entry.name === ".next" || entry.name === "test") continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) out.push(...walk(full));
      else if (/\.tsx?$/.test(entry.name)) out.push(full);
    }
    return out;
  }

  it("no TS module other than the resume route assigns runtime_paused_at = null", () => {
    // Match a null assignment in either object-literal (`runtime_paused_at: null`)
    // or query-builder-arg form. Comments are stripped first so a doc mention
    // of "clears runtime_paused_at" cannot false-match.
    const NULL_ASSIGN = /runtime_paused_at\s*:\s*null/;
    const clearers: string[] = [];
    for (const dir of ["server", "app", "lib"]) {
      for (const file of walk(path.join(APP_ROOT, dir))) {
        const src = readFileSync(file, "utf8")
          .replace(/\/\*[\s\S]*?\*\//g, "")
          .replace(/(^|\n)\s*\/\/[^\n]*/g, "$1");
        if (NULL_ASSIGN.test(src)) clearers.push(path.relative(APP_ROOT, file));
      }
    }
    expect(clearers).toEqual(["app/api/dashboard/runtime/resume/route.ts"]);
  });
});
