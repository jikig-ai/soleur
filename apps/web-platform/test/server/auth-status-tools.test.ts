import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";

// Unit tests for the `auth_revocation_status` MCP tool (#4440 follow-up
// to #4418). Covers the three documented response branches:
//   (a) un-denied caller → {revoked: false, deniedAt: null, reason: null}
//   (b) denied caller    → {revoked: true,  deniedAt, reason}
//   (c) RPC error        → null (fail-open per `getMyRevocationStatus`)
//
// Mocks via the `_setRevocationStatusTenantFnForTest` seam from PR #4418
// (sibling pattern to `_setMintFnForTest`). The seam substitutes the
// inner `getFreshTenantClient(userId)` mint so the test never boots the
// real precheck-mint pipeline.
//
// References:
// - Plan: knowledge-base/project/plans/2026-05-25-feat-jti-revoke-followups-plan.md §Item 2
// - Sibling: test/lib/tenant-revocation-status.test.ts (helper-level coverage)

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn(
    (name: string, description: string, schema: unknown, handler: Function) => ({
      name,
      description,
      schema,
      handler,
    }),
  ),
}));

// `getMyRevocationStatus` mirrors via `mirrorWithDebounce` on RPC error.
// Stub the observability module to keep the test silent + assert no
// stray mirror calls on the happy paths.
const mockMirror = vi.fn();
vi.mock("@/server/observability", () => ({
  mirrorWithDebounce: (...args: unknown[]) => mockMirror(...args),
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

import {
  _setRevocationStatusTenantFnForTest,
} from "@/lib/supabase/tenant";
import { buildAuthStatusTools } from "@/server/auth-status-tools";

type ToolHandler = (args: Record<string, unknown>) => Promise<{
  content: Array<{ type: "text"; text: string }>;
  isError?: boolean;
}>;

function findTool(
  tools: ReturnType<typeof buildAuthStatusTools>,
  name: string,
): { name: string; handler: ToolHandler } {
  const t = (tools as unknown as Array<{ name: string; handler: ToolHandler }>).find(
    (x) => x.name === name,
  );
  if (!t) throw new Error(`tool ${name} not registered`);
  return t;
}

function fakeTenant(rpcReturn: unknown, throwInstead = false): SupabaseClient {
  return {
    rpc: async () => {
      if (throwInstead) throw rpcReturn;
      return rpcReturn;
    },
  } as unknown as SupabaseClient;
}

describe("buildAuthStatusTools — registration", () => {
  it("returns exactly one tool: auth_revocation_status", () => {
    const tools = buildAuthStatusTools({ userId: "user-1" });
    const names = (tools as unknown as Array<{ name: string }>).map((t) => t.name);
    expect(names).toEqual(["auth_revocation_status"]);
  });

  it("captures userId in closure (does not surface in schema)", () => {
    const tools = buildAuthStatusTools({ userId: "user-1" });
    const tool = (tools as unknown as Array<{ schema: Record<string, unknown> }>)[0];
    // Empty zod schema — agent caller passes no args; userId is closure-bound.
    expect(tool.schema).toEqual({});
  });
});

describe("auth_revocation_status handler", () => {
  beforeEach(() => {
    mockMirror.mockReset();
  });

  afterEach(() => {
    _setRevocationStatusTenantFnForTest(null);
    vi.restoreAllMocks();
  });

  it("returns {revoked: false, deniedAt: null, reason: null} for un-denied caller", async () => {
    _setRevocationStatusTenantFnForTest(async () =>
      fakeTenant({
        data: [{ revoked: false, denied_at: null, reason: null }],
        error: null,
      }),
    );
    const tools = buildAuthStatusTools({ userId: "user-A" });
    const tool = findTool(tools, "auth_revocation_status");
    const result = await tool.handler({});
    expect(result.isError).toBeUndefined();
    const payload = JSON.parse(result.content[0].text);
    expect(payload).toEqual({
      revoked: false,
      deniedAt: null,
      reason: null,
    });
    expect(mockMirror).not.toHaveBeenCalled();
  });

  it("returns {revoked: true, deniedAt, reason} for denied caller", async () => {
    _setRevocationStatusTenantFnForTest(async () =>
      fakeTenant({
        data: [
          {
            revoked: true,
            denied_at: "2026-05-25T10:00:00.000Z",
            reason: "operator-revoked-stolen-jwt",
          },
        ],
        error: null,
      }),
    );
    const tools = buildAuthStatusTools({ userId: "user-A" });
    const tool = findTool(tools, "auth_revocation_status");
    const result = await tool.handler({});
    expect(result.isError).toBeUndefined();
    const payload = JSON.parse(result.content[0].text);
    expect(payload).toEqual({
      revoked: true,
      deniedAt: "2026-05-25T10:00:00.000Z",
      reason: "operator-revoked-stolen-jwt",
    });
  });

  it("returns null on RPC error (fail-open semantics)", async () => {
    _setRevocationStatusTenantFnForTest(async () =>
      fakeTenant({
        data: null,
        error: { code: "42P01", message: "relation does not exist" },
      }),
    );
    const tools = buildAuthStatusTools({ userId: "user-A" });
    const tool = findTool(tools, "auth_revocation_status");
    const result = await tool.handler({});
    // Fail-open: not flagged as isError — the helper already mirrored
    // to Sentry. The tool response is `null` (transient hint to caller).
    expect(result.isError).toBeUndefined();
    const payload = JSON.parse(result.content[0].text);
    expect(payload).toBeNull();
    // Helper mirrored the RPC error to Sentry — assert once so a future
    // helper refactor that swallows the error fails this test.
    expect(mockMirror).toHaveBeenCalledTimes(1);
  });
});
