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

/**
 * Pull the html of the single resend.emails.send() call. Asserts exactly one
 * send fired to the expected recipient — guards against a sender early-returning
 * without sending (vacuous pass) AND against a duplicate/extra send.
 */
function sentHtml(expectedTo: string): string {
  const calls = mockResendSend.mock.calls;
  expect(mockResendSend).toHaveBeenCalledTimes(1);
  expect(calls[0][0].to).toContain(expectedTo);
  return calls[0][0].html as string;
}

/**
 * Assert the branded CTA contract on a rendered email. `ctaName` labels the
 * failing assertion so a regression points at the specific sender + marker
 * rather than an opaque helper line. `ctaLabel` pins the assertion to this
 * sender's own button text so the 5 senders are not just re-testing the shared
 * EMAIL_CTA_STYLE constant.
 */
function assertBrandedCta(html: string, ctaName: string, ctaLabel: string) {
  expect(html, `${ctaName}: CTA label "${ctaLabel}" missing`).toContain(ctaLabel);
  expect(html.toLowerCase(), `${ctaName}: gold base missing`).toContain(GOLD.toLowerCase());
  expect(html.toLowerCase(), `${ctaName}: forge-ink text missing`).toContain(FORGE_INK.toLowerCase());
  expect(html, `${ctaName}: corners not sharp (0px)`).toMatch(/border-radius:\s*0(px)?\b/);
  expect(html, `${ctaName}: CTA not centered`).toMatch(/text-align:\s*center/);
  expect(html.toLowerCase(), `${ctaName}: off-brand blue present`).not.toContain(
    OFF_BRAND_BLUE.toLowerCase(),
  );
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
    assertBrandedCta(sentHtml("a@example.com"), "agent-needs-input", "Open conversation");
  });

  test("DSAR export-ready CTA is branded", async () => {
    await sendDsarExportReadyEmail("user-1", "job-1", new Date("2026-06-05T00:00:00Z"));
    assertBrandedCta(sentHtml("user@example.com"), "dsar-ready", "Download my data");
  });

  test("DSAR export-failed CTA is branded", async () => {
    await sendDsarExportFailedEmail("user-1", "job-1", "timeout");
    assertBrandedCta(sentHtml("user@example.com"), "dsar-failed", "Go to /settings/privacy");
  });

  test("invite CTA is branded (originally-reported case)", async () => {
    await sendInviteEmail("invitee@example.com", "Ada", "Workspace", "tok-1");
    assertBrandedCta(sentHtml("invitee@example.com"), "invite", "Accept invitation");
  });

  test("invite-accepted CTA is branded", async () => {
    await sendInviteAcceptedEmail("inviter-1", "Grace", "Workspace");
    assertBrandedCta(sentHtml("user@example.com"), "invite-accepted", "View team");
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
