import { describe, it, expect, vi, beforeEach } from "vitest";
import type { ClientSession } from "../server/ws-handler";

// feat-session-completion-inline — the `notifyTaskCompleted` suppression seam.
// Operator-confirmed semantics: "inline + notify if unseen" — when the operator
// has the completing conversation OPEN (live socket bound to that
// conversationId), the `task_completed` WS frame renders the completion card
// inline and the push/email nudge is suppressed; any uncertainty (no socket,
// socket bound to another conversation, emit failure) degrades to today's
// full notify path. The inbox_item row is written in BOTH paths — it is the
// durable record; the client marks it read at render time.

const {
  mockFrom,
  mockInsertSingle,
  mockPushSelectEq,
  mockAdminGetUserById,
  mockResendSend,
  mockSendNotification,
  mockSetVapidDetails,
} = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockInsertSingle: vi.fn(),
  mockPushSelectEq: vi.fn(),
  mockAdminGetUserById: vi.fn(),
  mockResendSend: vi.fn(),
  mockSendNotification: vi.fn(),
  mockSetVapidDetails: vi.fn(),
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
  // vitest 4: constructor mocks must use `function` (see dsar-notifications).
  Resend: vi.fn().mockImplementation(function (
    this: Record<string, unknown>,
  ) {
    this.emails = { send: mockResendSend };
  }),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockFrom,
    auth: { admin: { getUserById: mockAdminGetUserById } },
  }),
  serverUrl: () => "https://test.supabase.co",
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
  captureMessage: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  APP_URL_FALLBACK: "https://app.soleur.ai",
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: vi.fn(),
}));

import { notifyTaskCompleted } from "../server/notifications";
import { sessions } from "../server/session-registry";

const USER_ID = "11111111-1111-1111-1111-111111111111";
const CONV_ID = "conv-test-123";
const OTHER_CONV_ID = "conv-other-456";
const INBOX_ITEM_ID = "inbox-item-uuid-1";

function wireSupabase() {
  // inbox_item insert chain → returns the new row id.
  mockInsertSingle.mockResolvedValue({
    data: { id: INBOX_ITEM_ID },
    error: null,
  });
  // push_subscriptions select chain → no registered devices (email fallback).
  mockPushSelectEq.mockResolvedValue({ data: [], error: null });
  mockAdminGetUserById.mockResolvedValue({
    data: { user: { email: "founder@example.com" } },
    error: null,
  });
  mockResendSend.mockResolvedValue({ data: { id: "email-1" }, error: null });

  mockFrom.mockImplementation((table: string) => {
    if (table === "inbox_item") {
      return {
        insert: () => ({
          select: () => ({ single: mockInsertSingle }),
        }),
      };
    }
    if (table === "push_subscriptions") {
      return { select: () => ({ eq: mockPushSelectEq }) };
    }
    throw new Error(`unexpected table: ${table}`);
  });
}

function fakeViewingSession(conversationId: string): ClientSession {
  // WebSocket.OPEN === 1; only the fields the predicate reads are needed.
  return {
    ws: { readyState: 1, send: vi.fn() },
    conversationId,
    lastActivity: Date.now(),
  } as unknown as ClientSession;
}

const baseOpts = () => ({
  userId: USER_ID,
  conversationId: CONV_ID,
  workspaceId: "ws-1",
  title: "Soleur finished your request",
});

beforeEach(() => {
  vi.clearAllMocks();
  sessions.clear();
  wireSupabase();
  vi.stubEnv("VAPID_PUBLIC_KEY", "test");
  vi.stubEnv("VAPID_PRIVATE_KEY", "test");
  vi.stubEnv("RESEND_API_KEY", "re_test");
  vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://app.soleur.ai");
});

describe("notifyTaskCompleted suppression seam", () => {
  it("viewing + frame delivered → inbox row inserted, frame emitted, push/email suppressed", async () => {
    sessions.set(USER_ID, fakeViewingSession(CONV_ID));
    const emit = vi.fn().mockReturnValue(true);

    await notifyTaskCompleted({ ...baseOpts(), emit });

    // Row still written — the durable record exists in both paths.
    expect(mockFrom).toHaveBeenCalledWith("inbox_item");
    // The inline frame was emitted carrying the inserted row id.
    expect(emit).toHaveBeenCalledWith(
      USER_ID,
      expect.objectContaining({
        type: "task_completed",
        conversationId: CONV_ID,
        inboxItemId: INBOX_ITEM_ID,
      }),
    );
    // Suppressed: no push-subscription lookup, no email fallback.
    expect(mockFrom).not.toHaveBeenCalledWith("push_subscriptions");
    expect(mockSendNotification).not.toHaveBeenCalled();
    expect(mockResendSend).not.toHaveBeenCalled();
  });

  it("not viewing → today's full path: row + frame emit + notify dispatch", async () => {
    // No session in the registry — the operator is not on the chat surface.
    const emit = vi.fn().mockReturnValue(false);

    await notifyTaskCompleted({ ...baseOpts(), emit });

    expect(mockFrom).toHaveBeenCalledWith("inbox_item");
    // Dispatch reached the push path, then the email fallback (no devices).
    expect(mockFrom).toHaveBeenCalledWith("push_subscriptions");
    expect(mockResendSend).toHaveBeenCalled();
  });

  it("viewing ANOTHER conversation → notify fires (binding mismatch)", async () => {
    sessions.set(USER_ID, fakeViewingSession(OTHER_CONV_ID));
    const emit = vi.fn().mockReturnValue(false);

    await notifyTaskCompleted({ ...baseOpts(), emit });

    expect(mockFrom).toHaveBeenCalledWith("push_subscriptions");
    expect(mockResendSend).toHaveBeenCalled();
  });

  it("viewing but emit() reports no OPEN socket → notify fires (no silent window)", async () => {
    sessions.set(USER_ID, fakeViewingSession(CONV_ID));
    const emit = vi.fn().mockReturnValue(false);

    await notifyTaskCompleted({ ...baseOpts(), emit });

    expect(mockFrom).toHaveBeenCalledWith("push_subscriptions");
    expect(mockResendSend).toHaveBeenCalled();
  });

  it("socket bound but not OPEN → notify fires", async () => {
    sessions.set(USER_ID, {
      ...fakeViewingSession(CONV_ID),
      ws: { readyState: 3, send: vi.fn() },
    } as unknown as ClientSession);
    const emit = vi.fn().mockReturnValue(false);

    await notifyTaskCompleted({ ...baseOpts(), emit });

    expect(mockFrom).toHaveBeenCalledWith("push_subscriptions");
    expect(mockResendSend).toHaveBeenCalled();
  });
});
