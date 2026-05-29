import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const {
  mockResendSend,
  mockFrom,
  mockAdminGetUserById,
} = vi.hoisted(() => ({
  mockResendSend: vi.fn(),
  mockFrom: vi.fn(),
  mockAdminGetUserById: vi.fn(),
}));

vi.mock("web-push", () => ({
  default: { setVapidDetails: vi.fn(), sendNotification: vi.fn() },
  setVapidDetails: vi.fn(),
  sendNotification: vi.fn(),
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
  sendEmailNotification,
  sendDsarExportReadyEmail,
  sendDsarExportFailedEmail,
  sendInviteEmail,
  sendInviteAcceptedEmail,
} from "../server/notifications";

const GOLD = "#C9A962";
const FORGE_INK = "#1A1612";
const OFF_BRAND_BLUE = "#2563eb";

/** Pull the html of the most recent resend.emails.send() call. */
function lastHtml(): string {
  const calls = mockResendSend.mock.calls;
  expect(calls.length).toBeGreaterThan(0);
  return calls[calls.length - 1][0].html as string;
}

function assertBrandedCta(html: string) {
  // gold solid base + forge-ink text (case-insensitive — clients/authors vary)
  expect(html.toLowerCase()).toContain(GOLD.toLowerCase());
  expect(html.toLowerCase()).toContain(FORGE_INK.toLowerCase());
  // sharp corners
  expect(html).toMatch(/border-radius:\s*0(px)?\b/);
  // centered CTA wrapper
  expect(html).toMatch(/text-align:\s*center/);
  // no off-brand blue
  expect(html.toLowerCase()).not.toContain(OFF_BRAND_BLUE.toLowerCase());
}

describe("email brand compliance — notifications.ts CTAs", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("RESEND_API_KEY", "re_test_key");
    vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://test.example");
    mockResendSend.mockResolvedValue({ data: { id: "msg-1" }, error: null });
    mockAdminGetUserById.mockResolvedValue({
      data: { user: { email: "user@example.com" } },
      error: null,
    });
  });

  afterEach(() => vi.unstubAllEnvs());

  test("agent-needs-input CTA is branded", async () => {
    await sendEmailNotification("a@example.com", {
      type: "review_gate",
      conversationId: "conv-1",
      agentName: "CEO",
      question: "Approve budget?",
    });
    assertBrandedCta(lastHtml());
  });

  test("DSAR export-ready CTA is branded", async () => {
    await sendDsarExportReadyEmail("user-1", "job-1", new Date("2026-06-05T00:00:00Z"));
    assertBrandedCta(lastHtml());
  });

  test("DSAR export-failed CTA is branded", async () => {
    await sendDsarExportFailedEmail("user-1", "job-1", "timeout");
    assertBrandedCta(lastHtml());
  });

  test("invite CTA is branded (originally-reported case)", async () => {
    await sendInviteEmail("invitee@example.com", "Ada", "Workspace", "tok-1");
    const html = lastHtml();
    assertBrandedCta(html);
    expect(html).toContain("Accept invitation");
  });

  test("invite-accepted CTA is branded", async () => {
    await sendInviteAcceptedEmail("inviter-1", "Grace", "Workspace");
    assertBrandedCta(lastHtml());
  });
});

describe("email brand compliance — Supabase auth .html templates", () => {
  const templatesDir = join(__dirname, "..", "supabase", "templates");

  test("magic-link.html token box is gold-on-forge-ink + sharp corners, no white/charcoal box", () => {
    const html = readFileSync(join(templatesDir, "magic-link.html"), "utf8");
    expect(html.toLowerCase()).toContain(GOLD.toLowerCase());
    expect(html.toLowerCase()).toContain(FORGE_INK.toLowerCase());
    // off-brand charcoal CTA-box fill + white CTA text removed (the footer
    // border-top legitimately keeps #262626 as a dark divider — assert on the
    // box's background-color specifically, not the whole file).
    expect(html).not.toMatch(/background-color:\s*#262626/i);
    expect(html).not.toMatch(/background-color:\s*#ffffff/i);
    expect(html).toMatch(/border-radius:\s*0(px)?\b/);
  });

  test("confirmation.html exists, branded gold CTA wrapping {{ .ConfirmationURL }}", () => {
    const html = readFileSync(join(templatesDir, "confirmation.html"), "utf8");
    expect(html).toContain("{{ .ConfirmationURL }}");
    expect(html.toLowerCase()).toContain(GOLD.toLowerCase());
    expect(html.toLowerCase()).toContain(FORGE_INK.toLowerCase());
    expect(html).toMatch(/border-radius:\s*0(px)?\b/);
    expect(html.toLowerCase()).not.toContain(OFF_BRAND_BLUE.toLowerCase());
  });
});
