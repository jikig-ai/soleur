import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import type { ConversationStatus } from "@/lib/types";

// Mock Supabase channel
const mockSubscribe = vi.fn().mockReturnValue({ unsubscribe: vi.fn() });
const mockOn = vi.fn().mockReturnValue({ subscribe: mockSubscribe });
const mockChannel = vi.fn().mockReturnValue({ on: mockOn });

// Track update calls
const mockUpdate = vi.fn();

function createQueryBuilder(data: unknown[], error: { message: string } | null = null) {
  const result = { data, error };
  const builder = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    in: vi.fn().mockReturnThis(),
    is: vi.fn().mockReturnThis(),
    order: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    single: vi.fn().mockReturnThis(),
    update: vi.fn((...args: unknown[]) => {
      mockUpdate(...args);
      return builder;
    }),
    then: (onfulfilled: (value: unknown) => unknown) =>
      Promise.resolve(result).then(onfulfilled),
  };
  return builder;
}

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

let conversationBuilder: ReturnType<typeof createQueryBuilder>;
let messageBuilder: ReturnType<typeof createQueryBuilder>;
let updateBuilder: ReturnType<typeof createQueryBuilder>;

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
      return createQueryBuilder([]);
    },
    channel: mockChannel,
    removeChannel: vi.fn(),
  }),
}));

describe("useConversations.updateStatus", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    conversationBuilder = createQueryBuilder([mockConversation]);
    messageBuilder = createQueryBuilder(mockMessages);
    updateBuilder = createQueryBuilder([], null);
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
    updateBuilder = createQueryBuilder([], { message: "RLS policy violation" });

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
