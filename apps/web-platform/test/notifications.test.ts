import { describe, test, expect, vi, beforeEach } from "vitest";

const {
  mockSendNotification,
  mockSetVapidDetails,
  mockResendSend,
  mockFrom,
  mockAdminGetUserById,
} = vi.hoisted(() => ({
  mockSendNotification: vi.fn(),
  mockSetVapidDetails: vi.fn(),
  mockResendSend: vi.fn(),
  mockFrom: vi.fn(),
  mockAdminGetUserById: vi.fn(),
}));

vi.mock("web-push", () => ({
  default: {
    setVapidDetails: mockSetVapidDetails,
    sendNotification: mockSendNotification,
  },
  setVapidDetails: mockSetVapidDetails,
  sendNotification: mockSendNotification,
}));

vi.mock("resend", () => ({
  Resend: vi.fn().mockImplementation(() => ({
    emails: { send: mockResendSend },
  })),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockFrom,
    auth: { admin: { getUserById: mockAdminGetUserById } },
  }),
  serverUrl: () => "https://test.supabase.co",
}));

vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

// Import after mocks
import {
  notifyOfflineUser,
  sendPushNotifications,
  sendEmailNotification,
} from "../server/notifications";

describe("notifications", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset env vars
    process.env.VAPID_PUBLIC_KEY = "test-public-key";
    process.env.VAPID_PRIVATE_KEY = "test-private-key";
    process.env.RESEND_API_KEY = "re_test_key";
  });

  describe("notifyOfflineUser", () => {
    test("sends push notification when subscriptions exist", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
      ];
      mockFrom.mockReturnValue({
        select: () => ({
          eq: () => ({ data: subscriptions, error: null }),
        }),
      });
      mockSendNotification.mockResolvedValue({});

      await notifyOfflineUser("user-1", {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockSendNotification).toHaveBeenCalledTimes(1);
      expect(mockResendSend).not.toHaveBeenCalled();
    });

    test("sends email when zero push subscriptions exist", async () => {
      mockFrom.mockReturnValue({
        select: () => ({
          eq: () => ({ data: [], error: null }),
        }),
      });
      mockAdminGetUserById.mockResolvedValue({
        data: { user: { email: "test@example.com" } },
        error: null,
      });
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await notifyOfflineUser("user-1", {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockSendNotification).not.toHaveBeenCalled();
      expect(mockResendSend).toHaveBeenCalledTimes(1);
    });
  });

  describe("sendPushNotifications", () => {
    test("sends to all subscriptions", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
        { id: "sub-2", endpoint: "https://push.example.com/2", p256dh: "key2", auth: "auth2" },
      ];
      mockSendNotification.mockResolvedValue({});

      await sendPushNotifications(subscriptions, {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockSendNotification).toHaveBeenCalledTimes(2);
    });

    test("deletes subscription on 410 Gone response", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
      ];
      const gone = new Error("410 Gone");
      (gone as unknown as Record<string, number>).statusCode = 410;
      mockSendNotification.mockRejectedValue(gone);
      mockFrom.mockReturnValue({
        delete: () => ({
          eq: () => ({ error: null }),
        }),
      });

      await sendPushNotifications(subscriptions, {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockFrom).toHaveBeenCalledWith("push_subscriptions");
    });

    test("does not delete subscription on non-410 errors", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
      ];
      mockSendNotification.mockRejectedValue(new Error("Network error"));

      await sendPushNotifications(subscriptions, {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      // mockFrom should not have been called for deletion
      expect(mockFrom).not.toHaveBeenCalledWith("push_subscriptions");
    });
  });

  describe("sendEmailNotification", () => {
    test("sends email with correct payload", async () => {
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("test@example.com", {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockResendSend).toHaveBeenCalledTimes(1);
      const call = mockResendSend.mock.calls[0][0];
      expect(call.to).toContain("test@example.com");
      expect(call.subject).toContain("CEO");
    });

    test("includes deep link to conversation in email", async () => {
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("test@example.com", {
        type: "review_gate",
        conversationId: "conv-123",
        agentName: "CEO",
        question: "Approve budget?",
      });

      const call = mockResendSend.mock.calls[0][0];
      expect(call.html).toContain("/dashboard/chat/conv-123");
    });
  });
});
