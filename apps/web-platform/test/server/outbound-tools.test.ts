import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createHash, createHmac } from "node:crypto";

const PEPPER = "test-pepper-0123456789";
// Mirror outbound-compliance.recipientHash: HMAC-SHA-256(pepper, lc+trim(email)).
function expectedRecipientHash(email: string): string {
  return createHmac("sha256", PEPPER).update(email.trim().toLowerCase()).digest("hex");
}

// Mock the chokepoint + tenant client + Sentry mirror. vi.hoisted so the spies
// exist before the hoisted vi.mock factories run.
const { sendCompliantOutboundMock, getFreshTenantClientMock, reportSilentFallbackMock } =
  vi.hoisted(() => ({
    sendCompliantOutboundMock: vi.fn(),
    getFreshTenantClientMock: vi.fn(),
    reportSilentFallbackMock: vi.fn(),
  }));

vi.mock("@/server/email-triage/outbound", async (orig) => {
  const actual = await orig<typeof import("@/server/email-triage/outbound")>();
  return { ...actual, sendCompliantOutbound: sendCompliantOutboundMock };
});
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: getFreshTenantClientMock,
}));
vi.mock("@/server/observability", async (orig) => {
  const actual = await orig<typeof import("@/server/observability")>();
  return { ...actual, reportSilentFallback: reportSilentFallbackMock };
});

import { buildEmailTriageTools } from "@/server/email-triage-tools";

function sha256(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

type ToolDef = {
  name: string;
  handler: (args: Record<string, unknown>, extra: unknown) => Promise<{
    content: Array<{ type: string; text: string }>;
    isError?: true;
  }>;
};

const USER = "user-1";
function tools(): Record<string, ToolDef> {
  const out: Record<string, ToolDef> = {};
  for (const t of buildEmailTriageTools({ userId: USER }) as unknown as ToolDef[]) out[t.name] = t;
  return out;
}

function parse(res: { content: Array<{ type: string; text: string }> }) {
  // Last text block is the JSON payload (untrusted-envelope-prefixed responses
  // carry the envelope first).
  return JSON.parse(res.content[res.content.length - 1]!.text);
}

let tenantRpc: ReturnType<typeof vi.fn>;
let tenantFrom: ReturnType<typeof vi.fn>;

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("EMAIL_HASH_PEPPER", "test-pepper-0123456789");
  tenantRpc = vi.fn(async () => ({ data: "sup-1", error: null }));
  tenantFrom = vi.fn();
  getFreshTenantClientMock.mockResolvedValue({ rpc: tenantRpc, from: tenantFrom });
  sendCompliantOutboundMock.mockResolvedValue({ resendId: "re-1", outboundSendId: "os-1" });
});
afterEach(() => vi.unstubAllEnvs());

const COMPLIANCE = {
  jurisdiction: "us",
  postalAddress: "Jikigai, 1 Test St, DE 19801, USA",
  optOut: "Reply STOP to opt out.",
  ftcDisclosure: "Founder, free access — material connection.",
};

describe("email_send tool", () => {
  it("is registered as a tool", () => {
    expect(tools().email_send).toBeTruthy();
  });

  it("routes through sendCompliantOutbound with the approved body hash", async () => {
    const body = "Hi — relevant tool for your readers.";
    const res = await tools().email_send.handler(
      { to: "journalist@example.com", subject: "Hello", body, ...COMPLIANCE },
      {},
    );
    expect(sendCompliantOutboundMock).toHaveBeenCalledTimes(1);
    const arg = sendCompliantOutboundMock.mock.calls[0]![0];
    expect(arg.ownerId).toBe(USER);
    expect(arg.to).toBe("journalist@example.com");
    expect(arg.bodyText).toBe(body);
    expect(arg.approvedBodySha256).toBe(sha256(body));
    const payload = parse(res);
    expect(payload.resendId).toBe("re-1");
    expect(payload.outboundSendId).toBe("os-1");
  });

  it("returns a generic error (no throw, mirrors Sentry) when the chokepoint refuses", async () => {
    sendCompliantOutboundMock.mockRejectedValue(new Error("c1_postal_address_missing"));
    const res = await tools().email_send.handler(
      { to: "journalist@example.com", subject: "Hi", body: "x", ...COMPLIANCE },
      {},
    );
    expect(res.isError).toBe(true);
    expect(reportSilentFallbackMock).toHaveBeenCalled();
  });
});

describe("email_reply tool — server-side recipient derivation (P0-3)", () => {
  function tenantWithItem(sender: string | null) {
    const maybeSingle = vi.fn(async () => ({
      data: sender === null ? null : { id: "m-1", sender, subject: "Your article" },
      error: null,
    }));
    const chain = {
      select: vi.fn(() => chain),
      eq: vi.fn(() => chain),
      maybeSingle,
    };
    tenantFrom.mockReturnValue(chain);
    return { maybeSingle };
  }

  it("derives the recipient from the inbound message_id, ignoring any agent-supplied recipient", async () => {
    tenantWithItem("Editor <editor@example.com>");
    const body = "Thanks for your note — here's more.";
    await tools().email_reply.handler(
      {
        message_id: "11111111-1111-1111-1111-111111111111",
        subject: "Re: Your article",
        body,
        // An attacker-injected recipient must be IGNORED.
        to: "attacker@evil.com",
        ...COMPLIANCE,
      },
      {},
    );
    expect(sendCompliantOutboundMock).toHaveBeenCalledTimes(1);
    const arg = sendCompliantOutboundMock.mock.calls[0]![0];
    expect(arg.to).toBe("Editor <editor@example.com>");
    expect(arg.to).not.toContain("attacker@evil.com");
    expect(arg.approvedBodySha256).toBe(sha256(body));
  });

  it("refuses (not_found, no send) when the inbound item is missing/foreign", async () => {
    tenantWithItem(null);
    const res = await tools().email_reply.handler(
      {
        message_id: "22222222-2222-2222-2222-222222222222",
        subject: "Re:",
        body: "x",
        ...COMPLIANCE,
      },
      {},
    );
    expect(res.isError).toBe(true);
    expect(sendCompliantOutboundMock).not.toHaveBeenCalled();
  });
});

describe("email_suppress tool", () => {
  it("hashes the recipient and calls suppress_recipient with the reason", async () => {
    const res = await tools().email_suppress.handler(
      { recipient: "Journalist@Example.com", reason: "decline" },
      {},
    );
    expect(tenantRpc).toHaveBeenCalledWith("suppress_recipient", {
      p_recipient_hash: expectedRecipientHash("Journalist@Example.com"),
      p_reason: "decline",
    });
    // The recipient address is hashed (HMAC), never sent in plaintext.
    const callArgs = tenantRpc.mock.calls.find((c) => c[0] === "suppress_recipient")![1];
    expect(JSON.stringify(callArgs)).not.toContain("Journalist@Example.com");
    expect(callArgs.p_recipient_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(parse(res).id).toBe("sup-1");
  });
});
