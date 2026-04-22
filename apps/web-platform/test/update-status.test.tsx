import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import type { ConversationStatus } from "@/lib/types";
import { buildSupabaseQueryBuilder } from "./mocks/supabase-query-builder";

// Mock Supabase channel
const mockSubscribe = vi.fn().mockReturnValue({ unsubscribe: vi.fn() });
const mockOn = vi.fn().mockReturnValue({ subscribe: mockSubscribe });
const mockChannel = vi.fn().mockReturnValue({ on: mockOn });

// Track update calls
const mockUpdate = vi.fn();

// Wrapper over the shared helper that also records update() args — this
// site needs observation of the UPDATE payload, not just the return value.
const createUpdateObservingBuilder = (
  data: unknown[],
  error: { message: string } | null = null,
  singleRow: unknown = null,
) => {
  const builder = buildSupabaseQueryBuilder({
    data,
    error,
    singleRow,
  });
  // Overwrite update() so this test can assert the UPDATE payload via
  // the module-scoped `mockUpdate` spy.
  builder.update = vi.fn((...args: unknown[]) => {
    mockUpdate(...args);
    return builder;
  });
  return builder;
};

const mockConversation = {
  id: "conv-1",
  user_id: "user-1",
  domain_leader: "cto",
  session_id: null,
  status: "failed" as ConversationStatus,
  total_cost_usd: 0,
  input_tokens: 0,
  output_tokens: 0,
  last_active: new Date().toISOString(),
  created_at: new Date().toISOString(),
};

const mockMessages = [
  {
    conversation_id: "conv-1",
    role: "user",
    content: "Test message",
    leader_id: null,
    created_at: new Date().toISOString(),
  },
];

let conversationBuilder: ReturnType<typeof createUpdateObservingBuilder>;
let messageBuilder: ReturnType<typeof createUpdateObservingBuilder>;
let updateBuilder: ReturnType<typeof createUpdateObservingBuilder>;

vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
    from: (table: string) => {
      if (table === "conversations") {
        // Return update builder for update operations (when .update is called)
        const builder = conversationBuilder;
        // Override update to return the updateBuilder
        builder.update = vi.fn((...args: unknown[]) => {
          mockUpdate(...args);
          return updateBuilder;
        });
        return builder;
      }
      if (table === "messages") return messageBuilder;
      if (table === "users")
        return createUpdateObservingBuilder([], null, {
          repo_url: "https://github.com/acme/repo",
        });
      return createUpdateObservingBuilder([]);
    },
    channel: mockChannel,
    removeChannel: vi.fn(),
  }),
}));

describe("useConversations.updateStatus", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    conversationBuilder = createUpdateObservingBuilder([mockConversation]);
    messageBuilder = createUpdateObservingBuilder(mockMessages);
    updateBuilder = createUpdateObservingBuilder([], null);
  });

  it("optimistically updates conversation status in local state", async () => {
    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    // Wait for initial fetch
    await waitFor(() => {
      expect(result.current.conversations).toHaveLength(1);
    });
    expect(result.current.conversations[0].status).toBe("failed");

    // Call updateStatus
    await act(async () => {
      await result.current.updateStatus("conv-1", "completed");
    });

    // Status should be updated optimistically
    expect(result.current.conversations[0].status).toBe("completed");
  });

  it("calls Supabase update with correct parameters", async () => {
    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => {
      expect(result.current.conversations).toHaveLength(1);
    });

    await act(async () => {
      await result.current.updateStatus("conv-1", "completed");
    });

    expect(mockUpdate).toHaveBeenCalledWith({ status: "completed" });
  });

  it("reverts optimistic update on Supabase error", async () => {
    // Set up update to fail
    updateBuilder = createUpdateObservingBuilder([], { message: "RLS policy violation" });

    const { useConversations } = await import("@/hooks/use-conversations");
    const { result } = renderHook(() => useConversations());

    await waitFor(() => {
      expect(result.current.conversations).toHaveLength(1);
    });

    await act(async () => {
      await result.current.updateStatus("conv-1", "completed");
    });

    // Should revert to original status
    expect(result.current.conversations[0].status).toBe("failed");
    expect(result.current.error).toBeTruthy();
  });
});
