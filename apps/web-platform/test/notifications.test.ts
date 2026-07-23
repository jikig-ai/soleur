import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

const {
  mockSendNotification,
  mockSetVapidDetails,
  mockResendSend,
  mockFrom,
  mockAdminGetUserById,
  mockCaptureException,
  mockCaptureMessage,
} = vi.hoisted(() => ({
  mockSendNotification: vi.fn(),
  mockSetVapidDetails: vi.fn(),
  mockResendSend: vi.fn(),
  mockFrom: vi.fn(),
  mockAdminGetUserById: vi.fn(),
  mockCaptureException: vi.fn(),
  mockCaptureMessage: vi.fn(),
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
  Resend: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
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
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

// Import after mocks
import {
  notifyOfflineUser,
  notifyInboxItem,
  sendPushNotifications,
  sendEmailNotification,
} from "../server/notifications";

describe("notifications", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    // Reset env vars
    vi.stubEnv("VAPID_PUBLIC_KEY", "test-public-key");
    vi.stubEnv("VAPID_PRIVATE_KEY", "test-private-key");
    vi.stubEnv("RESEND_API_KEY", "re_test_key");
    // Default for existing tests — degraded-path test unsets below
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://test.example");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
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
        update: () => ({ in: () => ({ error: null }) }),
      });
      mockSendNotification.mockResolvedValue({});

      await notifyOfflineUser("user-1", {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockSendNotification).toHaveBeenCalledTimes(1);
      expect(mockSendNotification).toHaveBeenCalledWith(
        { endpoint: "https://push.example.com/1", keys: { p256dh: "key1", auth: "auth1" } },
        expect.stringContaining('"conversationId":"conv-1"'),
        // Bounded send (#5046 PR-2): a firewall DROP must not hang the
        // dispatcher on SYN retransmit.
        { timeout: 10_000 },
      );
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
      const emailCall = mockResendSend.mock.calls[0][0];
      expect(emailCall.to).toContain("test@example.com");
      expect(emailCall.html).toContain("/dashboard/chat/conv-1");
    });

    // #6802 delivery contract (D4/M3/M18). notifyOfflineUser returns whether the
    // notification was delivered, and a partial/zero push on a must-not-fail
    // class falls back to email.
    const statPayload = {
      type: "email_triage" as const,
      emailId: "stat-1",
      title: "Statutory deadline (computed) approaching",
      isStatutory: true,
      statutoryExcerpt: "within one calendar month of receipt (GDPR Art. 12(3)).",
    };

    function twoSubsThenUser() {
      mockFrom.mockReturnValue({
        select: () => ({
          eq: () => ({
            data: [
              { id: "sub-1", endpoint: "https://p/1", p256dh: "k1", auth: "a1" },
              { id: "sub-2", endpoint: "https://p/2", p256dh: "k2", auth: "a2" },
            ],
            error: null,
          }),
        }),
        update: () => ({ in: () => ({ error: null }) }),
        delete: () => ({ eq: () => ({ error: null }) }),
      });
      mockAdminGetUserById.mockResolvedValue({
        data: { user: { email: "founder@example.com" } },
        error: null,
      });
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });
    }

    test("T17: a non-410 push rejection (zero delivery) on a statutory item falls back to email + returns true", async () => {
      twoSubsThenUser();
      // Both pushes reject with a non-410 (the egress-DROP shape).
      mockSendNotification.mockRejectedValue({ statusCode: 500 });

      const delivered = await notifyOfflineUser("user-1", statPayload);

      expect(mockResendSend).toHaveBeenCalledTimes(1); // email fallback fired
      expect(delivered).toBe(true); // email landed
      // Zero-delivery incident signal fired.
      expect(mockCaptureMessage).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          tags: expect.objectContaining({ op: "statutory-notify-zero-delivery" }),
        }),
      );
    });

    test("T18: full push delivery on a statutory item sends NO email (no double-notify)", async () => {
      twoSubsThenUser();
      mockSendNotification.mockResolvedValue({}); // both fulfil

      const delivered = await notifyOfflineUser("user-1", statPayload);

      expect(mockResendSend).not.toHaveBeenCalled();
      expect(delivered).toBe(true);
    });

    test("T18b: PARTIAL push delivery on a statutory item STILL falls back to email (M18)", async () => {
      twoSubsThenUser();
      // sub-1 fulfils, sub-2 rejects → delivered 1 of 2.
      mockSendNotification
        .mockResolvedValueOnce({})
        .mockRejectedValueOnce({ statusCode: 500 });

      const delivered = await notifyOfflineUser("user-1", statPayload);

      expect(mockResendSend).toHaveBeenCalledTimes(1); // partial → email fires
      expect(delivered).toBe(true);
      // The zero-delivery INCIDENT signal must NOT fire on a partial delivery
      // (only on true zero) — otherwise dropping the `delivered === 0` conjunct
      // would page on every partial delivery and stay green (review finding).
      expect(mockCaptureMessage).not.toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          tags: expect.objectContaining({ op: "statutory-notify-zero-delivery" }),
        }),
      );
    });

    test("T21: a review_gate payload with zero delivery does NOT fall back (class scope)", async () => {
      twoSubsThenUser();
      mockSendNotification.mockRejectedValue({ statusCode: 500 });

      const delivered = await notifyOfflineUser("user-1", {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockResendSend).not.toHaveBeenCalled(); // out of the must-not-fail class
      expect(delivered).toBe(false);
    });
  });

  describe("sendPushNotifications", () => {
    test("sends to all subscriptions", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
        { id: "sub-2", endpoint: "https://push.example.com/2", p256dh: "key2", auth: "auth2" },
      ];
      mockSendNotification.mockResolvedValue({});
      mockFrom.mockReturnValue({
        update: () => ({ in: () => ({ error: null }) }),
      });

      await sendPushNotifications(subscriptions, {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockSendNotification).toHaveBeenCalledTimes(2);
      expect(mockSendNotification).toHaveBeenCalledWith(
        { endpoint: "https://push.example.com/1", keys: { p256dh: "key1", auth: "auth1" } },
        expect.any(String),
        { timeout: 10_000 },
      );
      expect(mockSendNotification).toHaveBeenCalledWith(
        { endpoint: "https://push.example.com/2", keys: { p256dh: "key2", auth: "auth2" } },
        expect.any(String),
        { timeout: 10_000 },
      );
    });

    test("deletes subscription on 410 Gone response", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
      ];
      const gone = new Error("410 Gone");
      (gone as unknown as Record<string, number>).statusCode = 410;
      mockSendNotification.mockRejectedValue(gone);
      const mockDelete = vi.fn(() => ({
        eq: vi.fn(() => ({ error: null })),
      }));
      const mockUpdate = vi.fn(() => ({
        in: vi.fn(() => ({ error: null })),
      }));
      mockFrom.mockReturnValue({
        delete: mockDelete,
        update: mockUpdate,
      });

      await sendPushNotifications(subscriptions, {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockFrom).toHaveBeenCalledWith("push_subscriptions");
      expect(mockDelete).toHaveBeenCalled();
    });

    test("updates last_used_at after successful delivery", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
        { id: "sub-2", endpoint: "https://push.example.com/2", p256dh: "key2", auth: "auth2" },
      ];
      mockSendNotification.mockResolvedValue({});
      const mockIn = vi.fn(() => ({ error: null }));
      const mockUpdate = vi.fn(() => ({ in: mockIn }));
      mockFrom.mockReturnValue({ update: mockUpdate });

      await sendPushNotifications(subscriptions, {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      expect(mockFrom).toHaveBeenCalledWith("push_subscriptions");
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ last_used_at: expect.any(String) }),
      );
      expect(mockIn).toHaveBeenCalledWith("id", ["sub-1", "sub-2"]);
    });

    test("does not delete subscription on non-410 errors", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
      ];
      mockSendNotification.mockRejectedValue(new Error("Network error"));
      mockFrom.mockReturnValue({
        update: vi.fn(() => ({ in: vi.fn(() => ({ error: null })) })),
      });

      await sendPushNotifications(subscriptions, {
        type: "review_gate",
        conversationId: "conv-1",
        agentName: "CEO",
        question: "Approve budget?",
      });

      // mockFrom should have been called for last_used_at update (0 delivered ids → no update call)
      // but NOT for deletion
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

    test("happy: NEXT_PUBLIC_APP_URL set appears in deep link and Sentry stays silent", async () => {
      vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://test.example");
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("test@example.com", {
        type: "review_gate",
        conversationId: "conv-happy",
        agentName: "CEO",
        question: "Approve budget?",
      });

      const call = mockResendSend.mock.calls[0][0];
      expect(call.html).toContain("https://test.example/dashboard/chat/conv-happy");
      expect(mockCaptureException).not.toHaveBeenCalled();
      expect(mockCaptureMessage).not.toHaveBeenCalled();
    });

    test("degraded: NEXT_PUBLIC_APP_URL unset fires Sentry and uses literal fallback", async () => {
      vi.stubEnv("NEXT_PUBLIC_APP_URL", undefined);
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("test@example.com", {
        type: "review_gate",
        conversationId: "conv-degraded",
        agentName: "CEO",
        question: "Approve budget?",
      });

      const call = mockResendSend.mock.calls[0][0];
      expect(call.html).toContain("https://app.soleur.ai/dashboard/chat/conv-degraded");
      expect(mockCaptureMessage).toHaveBeenCalledWith(
        expect.stringContaining("NEXT_PUBLIC_APP_URL unset"),
        expect.objectContaining({
          level: "error",
          tags: expect.objectContaining({ feature: "notifications", op: "app-url" }),
        }),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // email_triage variant (feat-operator-inbox-delegation Phase 4).
  // review_gate cases above are unchanged — behavior is byte-identical.
  // ---------------------------------------------------------------------------
  describe("email_triage variant", () => {
    test("push: data carries emailId + /dashboard/inbox/email/<uuid> deep link", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
      ];
      mockSendNotification.mockResolvedValue({});
      mockFrom.mockReturnValue({
        update: () => ({ in: () => ({ error: null }) }),
      });

      await sendPushNotifications(subscriptions, {
        type: "email_triage",
        emailId: "item-uuid-9",
        title: "Vendor invoice",
        isStatutory: false,
      });

      expect(mockSendNotification).toHaveBeenCalledTimes(1);
      const body = JSON.parse(mockSendNotification.mock.calls[0][1] as string);
      expect(body.data.emailId).toBe("item-uuid-9");
      expect(body.data.url).toBe(
        "https://test.example/dashboard/inbox/email/item-uuid-9",
      );
      expect(body.title).toBe("Vendor invoice");
    });

    test("push: title is display-sanitized (bidi/control strip + cap)", async () => {
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "key1", auth: "auth1" },
      ];
      mockSendNotification.mockResolvedValue({});
      mockFrom.mockReturnValue({
        update: () => ({ in: () => ({ error: null }) }),
      });

      await sendPushNotifications(subscriptions, {
        type: "email_triage",
        emailId: "item-uuid-10",
        title: "Invoice\u202Eevil\r\n" + "x".repeat(300),
        isStatutory: true,
      });

      const body = JSON.parse(mockSendNotification.mock.calls[0][1] as string);
      expect(body.title).not.toContain("\u202E");
      expect(body.title).not.toContain("\r");
      expect(body.title.length).toBeLessThanOrEqual(200);
    });

    test("email: deep link uses the DB uuid; static subject header", async () => {
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("test@example.com", {
        type: "email_triage",
        emailId: "item-uuid-1",
        title: "Vendor invoice",
        isStatutory: false,
      });

      const call = mockResendSend.mock.calls[0][0];
      expect(call.html).toContain(
        "https://test.example/dashboard/inbox/email/item-uuid-1",
      );
      // Static subject — third-party content never reaches the header.
      expect(call.subject).not.toContain("Vendor invoice");
    });

    test("email: title passes escapeHtml at the HTML sink", async () => {
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("test@example.com", {
        type: "email_triage",
        emailId: "item-uuid-2",
        title: '<script>alert("x")</script> & more',
        isStatutory: true,
      });

      const call = mockResendSend.mock.calls[0][0];
      expect(call.html).not.toContain("<script>");
      expect(call.html).toContain("&lt;script&gt;");
      expect(call.html).toContain("&amp; more");
    });

    // #6798 (M1): the statutory EMAIL carries the standing not-legal-advice
    // framing AND the rule's own clock-origin excerpt, so the operator does not
    // treat the computed date as THE authoritative deadline.
    test("email(statutory): carries not-legal-advice framing + the rule excerpt", async () => {
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("test@example.com", {
        type: "email_triage",
        emailId: "item-uuid-stat",
        title: "Data breach notification",
        isStatutory: true,
        statutoryExcerpt:
          "A personal data breach must be notified ... within 72 hours of becoming aware of it (GDPR Art. 33).",
      });

      const call = mockResendSend.mock.calls[0][0];
      expect(call.html).toContain("not legal advice");
      // The rule's own clock-origin prose is rendered (awareness-clock case).
      expect(call.html).toContain("becoming aware of it");
    });

    test("email(NON-statutory): does NOT carry the not-legal-advice framing", async () => {
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("test@example.com", {
        type: "email_triage",
        emailId: "item-uuid-non",
        title: "Newsletter",
        isStatutory: false,
      });

      const call = mockResendSend.mock.calls[0][0];
      expect(call.html).not.toContain("not legal advice");
    });

    test("statutory notify failure mirrors to Sentry.captureException", async () => {
      mockFrom.mockImplementation(() => {
        throw new Error("db down");
      });

      await notifyOfflineUser("user-1", {
        type: "email_triage",
        emailId: "item-uuid-3",
        title: "Subject access request",
        isStatutory: true,
      });

      expect(mockCaptureException).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          tags: expect.objectContaining({
            feature: "email-triage",
            op: "statutory-notify-failed",
          }),
        }),
      );
    });

    test("NON-statutory notify failure keeps existing behavior (no Sentry mirror)", async () => {
      mockFrom.mockImplementation(() => {
        throw new Error("db down");
      });

      await notifyOfflineUser("user-1", {
        type: "email_triage",
        emailId: "item-uuid-4",
        title: "Newsletter",
        isStatutory: false,
      });

      expect(mockCaptureException).not.toHaveBeenCalled();
    });
  });

  // cost_breaker_tripped variant (feat-l5-runaway-guard PR-A). Honest,
  // dollar-denominated halt notification. AC4: dollars (not tokens),
  // amount-vs-ceiling, which_window, never implies the run completed.
  describe("cost_breaker_tripped variant", () => {
    const costPayload = {
      type: "cost_breaker_tripped" as const,
      reason: "byok_cap_exceeded" as const,
      which_window: "cap-1h" as const,
      context: { cumulativeCents: 2014, ceilingCents: 2000 },
    };

    test("push body carries dollars, window, and never implies completion", async () => {
      mockSendNotification.mockResolvedValue({});
      mockFrom.mockReturnValue({ update: () => ({ in: () => ({ error: null }) }) });
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "k", auth: "a" },
      ];

      await sendPushNotifications(subscriptions, costPayload);

      const body = JSON.parse(mockSendNotification.mock.calls[0][1] as string);
      // Dollars, not tokens.
      expect(body.body).toContain("$20.14");
      expect(body.body).toContain("$20.00");
      expect(body.body).not.toMatch(/token/i);
      // Never implies the run finished.
      expect(body.body).not.toMatch(/completed|finished successfully|shipped/i);
      expect(body.body).toContain("no pull request");
      // Deep link routes to the halt banner surface.
      expect(body.data.url).toContain("/dashboard");
    });

    test("email carries amount-vs-ceiling and an honest subject", async () => {
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("founder@example.com", costPayload);

      const call = mockResendSend.mock.calls[0][0];
      expect(call.to).toContain("founder@example.com");
      expect(call.html).toContain("$20.14");
      expect(call.html).toContain("$20.00");
      expect(call.html).not.toMatch(/completed|finished successfully/i);
      expect(call.subject).toMatch(/spending cap|stopped/i);
    });

    test("leader_max_turns_exceeded carries no fabricated dollar figure", async () => {
      mockSendNotification.mockResolvedValue({});
      mockFrom.mockReturnValue({ update: () => ({ in: () => ({ error: null }) }) });
      const subscriptions = [
        { id: "sub-1", endpoint: "https://push.example.com/1", p256dh: "k", auth: "a" },
      ];

      await sendPushNotifications(subscriptions, {
        type: "cost_breaker_tripped",
        reason: "leader_max_turns_exceeded",
        which_window: "spawn",
        context: { cumulativeCents: null, ceilingCents: null },
      });

      const body = JSON.parse(mockSendNotification.mock.calls[0][1] as string);
      // No fabricated dollar amount when we have no figure (turn-count halt).
      expect(body.body).not.toMatch(/\$\d/);
      expect(body.body).not.toMatch(/completed|finished successfully/i);
    });

    test("cap_check_unavailable does not claim the budget was exceeded or paused", async () => {
      mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });

      await sendEmailNotification("founder@example.com", {
        type: "cost_breaker_tripped",
        reason: "cap_check_unavailable",
        which_window: "cap-1h",
        context: { cumulativeCents: null, ceilingCents: null },
      });

      const call = mockResendSend.mock.calls[0][0];
      // A transient DB error must NOT read as "you overspent".
      expect(call.html).not.toMatch(/exceeded your|over your (limit|cap|budget)/i);
      // Nor as "paused" — cap_check_unavailable sets no runtime_paused_at and
      // renders no Resume affordance (F6: don't send the founder hunting).
      expect(call.html).not.toMatch(/paused/i);
      // Apostrophes are HTML-entity-escaped at the sink (couldn&#39;t).
      expect(call.html).toMatch(/couldn(&#39;|')t (verify|check)/i);
    });
  });

  describe("notifyInboxItem", () => {
    // Route from() by table so the insert (inbox_item), the push-subscription
    // read/update (push_subscriptions), and the broadcast owner lookup
    // (workspace_members) each get the right chain shape.
    function routeFrom(opts: {
      insert?: { data: unknown; error: unknown };
      subscriptions?: unknown[];
      owners?: unknown[];
      ownersError?: unknown;
    }) {
      mockFrom.mockImplementation((table: string) => {
        if (table === "inbox_item") {
          return {
            insert: () => ({
              select: () => ({
                single: () =>
                  opts.insert ?? { data: { id: "ii-1" }, error: null },
              }),
            }),
          };
        }
        if (table === "push_subscriptions") {
          return {
            select: () => ({
              eq: () => ({ data: opts.subscriptions ?? [], error: null }),
            }),
            update: () => ({ in: () => ({ error: null }) }),
            delete: () => ({ eq: () => ({ error: null }) }),
          };
        }
        if (table === "workspace_members") {
          return {
            select: () => ({
              eq: () => ({
                eq: () => ({
                  data: opts.owners ?? [],
                  error: opts.ownersError ?? null,
                }),
              }),
            }),
          };
        }
        throw new Error(`unexpected table ${table}`);
      });
    }

    test("inserts the row once then dispatches a push (targeted)", async () => {
      routeFrom({
        subscriptions: [
          { id: "sub-1", endpoint: "https://push.example/1", p256dh: "k", auth: "a" },
        ],
      });
      mockSendNotification.mockResolvedValue({});

      await notifyInboxItem({
        workspaceId: "ws-1",
        userId: "user-1",
        severity: "info",
        source: "task_completed",
        title: "Chief Legal Officer finished",
        sourceRef: { conversationId: "conv-9" },
        deepLinkPath: "/dashboard/chat/conv-9",
      });

      // Push body carries the per-item tag key + the server-built deep link.
      expect(mockSendNotification).toHaveBeenCalledTimes(1);
      const body = mockSendNotification.mock.calls[0][1] as string;
      expect(body).toContain('"inboxItemId":"ii-1"');
      expect(body).toContain("/dashboard/chat/conv-9");
      expect(mockResendSend).not.toHaveBeenCalled();
    });

    test("deduped insert (23505) dispatches NO push", async () => {
      routeFrom({
        insert: { data: null, error: { code: "23505", message: "dup" } },
        subscriptions: [
          { id: "sub-1", endpoint: "https://push.example/1", p256dh: "k", auth: "a" },
        ],
      });

      await notifyInboxItem({
        workspaceId: "ws-1",
        userId: "user-1",
        severity: "info",
        source: "task_completed",
        title: "Chief Legal Officer finished",
        deepLinkPath: "/dashboard/chat/conv-9",
      });

      // Retry re-insert is a no-op → no re-push, no email.
      expect(mockSendNotification).not.toHaveBeenCalled();
      expect(mockResendSend).not.toHaveBeenCalled();
    });

    test("action_required insert failure mirrors to Sentry op=notify-inbox-action-required and pushes nothing", async () => {
      routeFrom({
        insert: { data: null, error: { code: "23502", message: "not null" } },
      });

      await notifyInboxItem({
        workspaceId: "ws-1",
        userId: "user-1",
        severity: "action_required",
        source: "system",
        title: "From Soleur: billing failed",
        deepLinkPath: "/dashboard",
      });

      expect(mockSendNotification).not.toHaveBeenCalled();
      // A non-Error supabase failure routes through captureMessage; the op tag
      // is what the Sentry alert rule keys on.
      const mirrored =
        mockCaptureMessage.mock.calls.some(
          (c) => (c[1] as { tags?: { op?: string } })?.tags?.op === "notify-inbox-action-required",
        ) ||
        mockCaptureException.mock.calls.some(
          (c) => (c[1] as { tags?: { op?: string } })?.tags?.op === "notify-inbox-action-required",
        );
      expect(mirrored).toBe(true);
    });

    test("broadcast (userId null) dispatches to every workspace Owner", async () => {
      routeFrom({
        owners: [{ user_id: "owner-a" }, { user_id: "owner-b" }],
        subscriptions: [
          { id: "sub-1", endpoint: "https://push.example/1", p256dh: "k", auth: "a" },
        ],
      });
      mockSendNotification.mockResolvedValue({});

      await notifyInboxItem({
        workspaceId: "ws-1",
        userId: null,
        severity: "info",
        source: "system",
        title: "From Soleur: update",
        deepLinkPath: "/dashboard",
      });

      // One push per Owner (each Owner has one subscription in this fixture).
      expect(mockSendNotification).toHaveBeenCalledTimes(2);
    });
  });
});
