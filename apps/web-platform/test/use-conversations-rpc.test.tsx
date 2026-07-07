import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";

// Phase 1 of plan 2026-07-07-perf-dashboard-load-and-conversation-list.
//
// Contract: useConversations must fetch the list via ONE RLS-respecting RPC
// `list_conversations_enriched(...)` that returns per-conversation message
// SNIPPETS, and must NOT issue the old unbounded `.from("messages").in(ids)`
// fan-out. Title/preview are still derived client-side from the snippets by the
// unchanged deriveTitle/derivePreview logic.

const rpcSpy = vi.fn();

function buildEnrichedRows() {
  return [
    {
      id: "conv-1",
      user_id: "u1",
      domain_leader: null,
      session_id: null,
      status: "active",
      total_cost_usd: 0,
      input_tokens: 0,
      output_tokens: 0,
      last_active: new Date("2026-07-07T10:00:00Z").toISOString(),
      created_at: new Date("2026-07-07T09:00:00Z").toISOString(),
      archived_at: null,
      context_path: null,
      repo_url: "https://github.com/acme/repo",
      active_workflow: null,
      workflow_ended_at: null,
      workspace_id: "ws-1",
      visibility: "private",
      first_user_content: "@cmo Design the brand identity",
      first_assistant_content: "Sure, here is the brand plan.",
      last_content: "Final brand summary delivered.",
      last_leader: "cmo",
    },
  ];
}

function buildSupabaseClient(rows: ReturnType<typeof buildEnrichedRows>) {
  return {
    auth: {
      getUser: vi.fn(() =>
        Promise.resolve({ data: { user: { id: "u1" } }, error: null }),
      ),
    },
    rpc: vi.fn((name: string, args: Record<string, unknown>) => {
      rpcSpy(name, args);
      return Promise.resolve({ data: rows, error: null });
    }),
    // The list read must NOT touch messages/conversations tables directly.
    from: vi.fn((table: string) => {
      throw new Error(`unexpected .from("${table}") during list fetch`);
    }),
    channel: vi.fn(() => {
      const ch: Record<string, unknown> = {};
      Object.assign(ch, {
        on: vi.fn(() => ch),
        subscribe: vi.fn(() => ch),
      });
      return ch;
    }),
    removeChannel: vi.fn(),
  };
}

const { createClientMock } = vi.hoisted(() => ({ createClientMock: vi.fn() }));
vi.mock("@/lib/supabase/client", () => ({ createClient: createClientMock }));

describe("useConversations — enriched RPC fetch", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    rpcSpy.mockClear();
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve({
            workspaceId: "ws-1",
            repoUrl: "https://github.com/acme/repo",
            repoName: "acme/repo",
            repoStatus: "connected",
            fellBackToSolo: false,
          }),
      }),
    );
  });

  it("issues one list_conversations_enriched RPC (no messages fan-out)", async () => {
    createClientMock.mockImplementation(() =>
      buildSupabaseClient(buildEnrichedRows()),
    );

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations({ limit: 15 }));

    await waitFor(() => expect(result.current.loading).toBe(false));

    // Every list read goes through the enriched RPC (the initial fetch plus any
    // scope-resolve backfill refetch); NONE fall back to a messages fan-out.
    expect(rpcSpy).toHaveBeenCalled();
    for (const [name] of rpcSpy.mock.calls) {
      expect(name).toBe("list_conversations_enriched");
    }
    const [, args] = rpcSpy.mock.calls[0]!;
    expect(args).toMatchObject({
      p_repo_url: "https://github.com/acme/repo",
      p_workspace_id: "ws-1",
      p_archive: "active",
      p_limit: 15,
    });
  });

  it("derives title from first_user_content and preview from last_content", async () => {
    createClientMock.mockImplementation(() =>
      buildSupabaseClient(buildEnrichedRows()),
    );

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => expect(result.current.loading).toBe(false));

    const conv = result.current.conversations[0]!;
    // @-mentions stripped by deriveTitle → "Design the brand identity"
    expect(conv.title).toBe("Design the brand identity");
    // preview from the last message content, markdown-stripped
    expect(conv.preview).toBe("Final brand summary delivered.");
    expect(conv.lastMessageLeader).toBe("cmo");
  });

  it("threads the domain 'general' sentinel and status filter into RPC args", async () => {
    createClientMock.mockImplementation(() =>
      buildSupabaseClient(buildEnrichedRows()),
    );

    const { useConversations } = await import("@/hooks/use-conversations");
    renderHook(() =>
      useConversations({ domainFilter: "general", statusFilter: "active" }),
    );

    await waitFor(() => expect(rpcSpy).toHaveBeenCalled());
    const [, args] = rpcSpy.mock.calls[0]!;
    expect(args).toMatchObject({ p_domain: "general", p_status: "active" });
  });
});
