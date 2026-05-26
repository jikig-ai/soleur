import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";

// Phase 4 unit tests for the DSAR-specific notification helpers added
// to `apps/web-platform/server/notifications.ts` per plan rev-2 C2
// (folded from rev-1's separate `dsar-email.ts`).
//
// TR6: Resend inline HTML; PII-free subject + preview text; plain `<a>`
// link, NOT auto-tracked (no Resend tags for individual link tracking).
// RK5: preview-text first body line is the same neutral text as the
// preview, so mobile clients that surface the body's first line cannot
// leak PII either.

const {
  mockResendSend,
  mockAdminGetUserById,
  mockSetVapidDetails,
} = vi.hoisted(() => ({
  mockResendSend: vi.fn(),
  mockAdminGetUserById: vi.fn(),
  mockSetVapidDetails: vi.fn(),
}));

vi.mock("web-push", () => ({
  default: {
    setVapidDetails: mockSetVapidDetails,
    sendNotification: vi.fn(),
  },
  setVapidDetails: mockSetVapidDetails,
  sendNotification: vi.fn(),
}));

vi.mock("resend", () => ({
  Resend: vi.fn().mockImplementation(() => ({
    emails: { send: mockResendSend },
  })),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
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

import {
  sendDsarExportReadyEmail,
  sendDsarExportFailedEmail,
} from "../server/notifications";

const USER_ID = "11111111-1111-1111-1111-111111111111";
const JOB_ID = "22222222-2222-2222-2222-222222222222";
const USER_EMAIL = "alice@example.com";

describe("sendDsarExportReadyEmail", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("VAPID_PUBLIC_KEY", "test");
    vi.stubEnv("VAPID_PRIVATE_KEY", "test");
    vi.stubEnv("RESEND_API_KEY", "re_test");
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://app.soleur.ai");
    mockAdminGetUserById.mockResolvedValue({
      data: { user: { id: USER_ID, email: USER_EMAIL } },
      error: null,
    });
    mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });
  });

  afterEach(() => vi.unstubAllEnvs());

  test("sends to user's email looked up via service-role", async () => {
    await sendDsarExportReadyEmail(
      USER_ID,
      JOB_ID,
      new Date("2026-05-19T12:00:00Z"),
    );

    expect(mockAdminGetUserById).toHaveBeenCalledWith(USER_ID);
    expect(mockResendSend).toHaveBeenCalledTimes(1);
    const call = mockResendSend.mock.calls[0][0];
    expect(call.to).toEqual([USER_EMAIL]);
  });

  test("subject is PII-free (no jobId, no userId, no email)", async () => {
    await sendDsarExportReadyEmail(
      USER_ID,
      JOB_ID,
      new Date("2026-05-19T12:00:00Z"),
    );
    const call = mockResendSend.mock.calls[0][0];
    expect(call.subject).not.toContain(JOB_ID);
    expect(call.subject).not.toContain(USER_ID);
    expect(call.subject).not.toContain(USER_EMAIL);
    expect(call.subject).toMatch(/data export/i);
  });

  test("first 280 chars of body are PII-free (RK5 mobile-preview safety)", async () => {
    await sendDsarExportReadyEmail(
      USER_ID,
      JOB_ID,
      new Date("2026-05-19T12:00:00Z"),
    );
    const call = mockResendSend.mock.calls[0][0];
    // Iterative tag-strip until stable — single-pass `<[^>]+>` regex
    // leaves residual tags on nested-bracket inputs (CodeQL
    // js/incomplete-multi-character-sanitization). For a test fixture
    // this is fine, but the iterative form makes the intent
    // (extract text content) explicit + silences the rule.
    let text: string = call.html;
    let prev = "";
    while (text !== prev) {
      prev = text;
      text = text.replace(/<[^>]+>/g, "");
    }
    const preview = text.trim().slice(0, 280);
    expect(preview).not.toContain(JOB_ID);
    expect(preview).not.toContain(USER_ID);
    expect(preview).not.toContain(USER_EMAIL);
  });

  test("includes a plain `<a>` link to the download endpoint scoped to jobId", async () => {
    await sendDsarExportReadyEmail(
      USER_ID,
      JOB_ID,
      new Date("2026-05-19T12:00:00Z"),
    );
    const call = mockResendSend.mock.calls[0][0];
    expect(call.html).toContain(
      `https://app.soleur.ai/api/account/export/${JOB_ID}/download`,
    );
    expect(call.html).toContain("<a ");
  });

  test("does NOT enable Resend link-tracking tags (TR6 — no auto-tracking)", async () => {
    await sendDsarExportReadyEmail(
      USER_ID,
      JOB_ID,
      new Date("2026-05-19T12:00:00Z"),
    );
    const call = mockResendSend.mock.calls[0][0];
    expect(call.tags).toBeUndefined();
  });

  test("returns false silently when user lookup fails (does not throw)", async () => {
    mockAdminGetUserById.mockResolvedValueOnce({
      data: null,
      error: { message: "user not found" },
    });
    await expect(
      sendDsarExportReadyEmail(USER_ID, JOB_ID, new Date()),
    ).resolves.toBe(false);
    expect(mockResendSend).not.toHaveBeenCalled();
  });

  test("returns false silently when user has no email", async () => {
    mockAdminGetUserById.mockResolvedValueOnce({
      data: { user: { id: USER_ID, email: null } },
      error: null,
    });
    await expect(
      sendDsarExportReadyEmail(USER_ID, JOB_ID, new Date()),
    ).resolves.toBe(false);
  });
});

describe("sendDsarExportFailedEmail", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("VAPID_PUBLIC_KEY", "test");
    vi.stubEnv("VAPID_PRIVATE_KEY", "test");
    vi.stubEnv("RESEND_API_KEY", "re_test");
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://app.soleur.ai");
    mockAdminGetUserById.mockResolvedValue({
      data: { user: { id: USER_ID, email: USER_EMAIL } },
      error: null,
    });
    mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });
  });

  afterEach(() => vi.unstubAllEnvs());

  test("subject is PII-free and indicates failure", async () => {
    await sendDsarExportFailedEmail(USER_ID, JOB_ID, "job_timeout");
    const call = mockResendSend.mock.calls[0][0];
    expect(call.subject).not.toContain(JOB_ID);
    expect(call.subject).not.toContain(USER_EMAIL);
    expect(call.subject).toMatch(/data export/i);
  });

  test("translates internal failure_reason codes to user-facing copy", async () => {
    await sendDsarExportFailedEmail(USER_ID, JOB_ID, "job_timeout");
    const call = mockResendSend.mock.calls[0][0];
    // The internal code itself MUST NOT appear in the body — that
    // would leak implementation detail. The body should have a
    // human-readable explanation.
    expect(call.html).not.toContain("job_timeout");
  });

  test("includes a request-again CTA pointing at /settings/privacy", async () => {
    await sendDsarExportFailedEmail(USER_ID, JOB_ID, "job_timeout");
    const call = mockResendSend.mock.calls[0][0];
    expect(call.html).toContain("/settings/privacy");
  });

  test("returns false silently when user lookup fails", async () => {
    mockAdminGetUserById.mockResolvedValueOnce({
      data: null,
      error: { message: "user not found" },
    });
    await expect(
      sendDsarExportFailedEmail(USER_ID, JOB_ID, "job_timeout"),
    ).resolves.toBe(false);
    expect(mockResendSend).not.toHaveBeenCalled();
  });
});
