import { describe, expect, it, vi } from "vitest";
import { randomUUID } from "crypto";
import { resolveActiveWorkspace } from "@/server/workspace-resolver";
import { mockQueryChain, type MockQueryChain } from "../helpers/mock-supabase";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { reportSilentFallback } from "@/server/observability";

/**
 * Per-table supabase stub (mirrors kb-active-workspace-scoping.test.ts). The
 * resolver reads `user_session_state` → `workspace_members`; a solo claim must
 * NOT touch `workspace_members` (the stub throws on any unstubbed table, which
 * proves the no-probe-on-solo invariant).
 */
function supabaseMulti(byTable: Record<string, MockQueryChain>) {
  const from = vi.fn((table: string) => {
    const chain = byTable[table];
    if (!chain) {
      throw new Error(
        `unexpected .from("${table}") — resolver queried a table the test did not stub`,
      );
    }
    return chain;
  });
  return { from } as unknown as Parameters<typeof resolveActiveWorkspace>[1];
}

describe("resolveActiveWorkspace — membership-verified active workspace (ADR-044 PR-1, TR1)", () => {
  it("genuine solo (claim === userId) → ok(userId); never probes membership", async () => {
    const userId = randomUUID();
    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: userId }),
      // No workspace_members stub — a solo claim must not query it.
    });

    const result = await resolveActiveWorkspace(userId, supabase);

    expect(result).toEqual({ ok: true, workspaceId: userId });
  });

  it("unbound (null claim) → ok(userId); never probes membership", async () => {
    const userId = randomUUID();
    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: null }),
    });

    const result = await resolveActiveWorkspace(userId, supabase);

    expect(result).toEqual({ ok: true, workspaceId: userId });
  });

  it("member of the claimed team → ok(team); no reset", async () => {
    const userId = randomUUID();
    const team = randomUUID();
    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: team }),
      workspace_members: mockQueryChain({ user_id: userId }), // is a member
    });

    const result = await resolveActiveWorkspace(userId, supabase);

    expect(result).toEqual({ ok: true, workspaceId: team });
  });

  it("non-member team claim (removed/stale) → ok(userId, resetFromClaim=team)", async () => {
    const userId = randomUUID();
    const team = randomUUID();
    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: team }),
      workspace_members: mockQueryChain(null), // NOT a member
    });

    const result = await resolveActiveWorkspace(userId, supabase);

    expect(result).toEqual({
      ok: true,
      workspaceId: userId,
      resetFromClaim: team,
    });
  });

  it("TR1: membership probe DB error → {ok:false, db-error}; NEVER the claim id, never a reset", async () => {
    const userId = randomUUID();
    const team = randomUUID();
    const supabase = supabaseMulti({
      user_session_state: mockQueryChain({ current_workspace_id: team }),
      workspace_members: mockQueryChain(null, { message: "probe failed" }),
    });

    const result = await resolveActiveWorkspace(userId, supabase);

    expect(result).toEqual({ ok: false, reason: "db-error" });
    // It must NOT have leaked the unverified claim id as a workspaceId.
    if (result.ok) throw new Error("must not be ok on probe error");
    expect(reportSilentFallback).toHaveBeenCalled();
  });
});
