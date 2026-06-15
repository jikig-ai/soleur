import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";

// Resend is obtained via getResend() (exported from notifications.ts); stub it
// so no real send fires. vi.hoisted so the mock fns exist before the hoisted
// vi.mock factories run. Spread the actual module so other exports survive.
const { sendMock, reportSilentFallbackMock } = vi.hoisted(() => ({
  sendMock: vi.fn(),
  reportSilentFallbackMock: vi.fn(),
}));
vi.mock("@/server/notifications", async (orig) => {
  const actual = await orig<typeof import("@/server/notifications")>();
  return { ...actual, getResend: () => ({ emails: { send: sendMock } }) };
});
vi.mock("@/server/observability", async (orig) => {
  const actual = await orig<typeof import("@/server/observability")>();
  return { ...actual, reportSilentFallback: reportSilentFallbackMock };
});

import {
  sendCompliantOutbound,
  OUTBOUND_FROM,
} from "@/server/email-triage/outbound";

function sha256(s: string): string {
  return createHash("sha256").update(s).digest("hex");
}

interface RpcCall {
  name: string;
  args: Record<string, unknown>;
}

function makeSupabase(opts?: { suppressed?: boolean; recordId?: string; alreadySent?: boolean }) {
  const calls: RpcCall[] = [];
  const rpc = vi.fn(async (name: string, args: Record<string, unknown>) => {
    calls.push({ name, args });
    if (name === "is_recipient_suppressed") {
      return { data: opts?.suppressed ?? false, error: null };
    }
    if (name === "outbound_send_exists") {
      return { data: opts?.alreadySent ?? false, error: null };
    }
    if (name === "record_outbound_send") {
      return { data: opts?.recordId ?? "os-1", error: null };
    }
    return { data: null, error: null };
  });
  return { rpc, calls } as const;
}

const BODY = "Hi — I read your listicle and built something relevant.";

function validArgs(overrides: Record<string, unknown> = {}) {
  return {
    supabase: makeSupabase(),
    ownerId: "user-1",
    to: "journalist@example.com",
    subject: "Your piece on solo-founder tooling",
    bodyText: BODY,
    jurisdiction: "us" as const,
    postalAddress: "Jikigai, 1 Test St, Wilmington DE 19801, USA",
    optOut: "Reply STOP to opt out.",
    ftcDisclosure: "Founder offering free access — material connection.",
    approvedBodySha256: sha256(BODY),
    ...overrides,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubEnv("EMAIL_HASH_PEPPER", "test-pepper-0123456789");
  vi.stubEnv("OUTBOUND_SENDING_DOMAIN_VERIFIED", "true");
  sendMock.mockResolvedValue({ data: { id: "resend-1" }, error: null });
});
afterEach(() => {
  vi.unstubAllEnvs();
});

describe("sendCompliantOutbound — happy path", () => {
  it("sends via Resend from mail.soleur.ai and records the WORM row", async () => {
    const sb = makeSupabase({ recordId: "os-42" });
    const res = await sendCompliantOutbound({ ...validArgs(), supabase: sb });
    expect(res).toEqual({ resendId: "resend-1", outboundSendId: "os-42" });

    expect(sendMock).toHaveBeenCalledTimes(1);
    const sent = sendMock.mock.calls[0]![0];
    expect(sent.from).toBe(OUTBOUND_FROM);
    expect(sent.to).toEqual(["journalist@example.com"]);
    expect(sent.text).toBe(BODY);

    // record_outbound_send called AFTER the send, with both body hashes equal.
    const rec = sb.calls.find((c) => c.name === "record_outbound_send");
    expect(rec).toBeTruthy();
    expect(rec!.args.p_approved_body_sha256).toBe(sha256(BODY));
    expect(rec!.args.p_per_send_body_sha256).toBe(sha256(BODY));
    expect(rec!.args.p_resend_id).toBe("resend-1");
    // recipient persisted only as a hash, never plaintext.
    expect(JSON.stringify(rec!.args)).not.toContain("journalist@example.com");
  });

  it("OUTBOUND_FROM is on the mail.soleur.ai sending subdomain", () => {
    expect(OUTBOUND_FROM).toContain("mail.soleur.ai");
  });
});

describe("sendCompliantOutbound — refuse-to-send gates (throw BEFORE Resend)", () => {
  it("throws when the sending domain is not verified", async () => {
    vi.stubEnv("OUTBOUND_SENDING_DOMAIN_VERIFIED", "");
    await expect(sendCompliantOutbound(validArgs())).rejects.toThrow(/domain|verif/i);
    expect(sendMock).not.toHaveBeenCalled();
  });

  it("throws on a missing compliance condition (C1 postal address)", async () => {
    await expect(
      sendCompliantOutbound(validArgs({ postalAddress: undefined })),
    ).rejects.toThrow(/c1/i);
    expect(sendMock).not.toHaveBeenCalled();
  });

  it("throws on header injection in the subject", async () => {
    await expect(
      sendCompliantOutbound(validArgs({ subject: "Hi\r\nBcc: evil@x.com" })),
    ).rejects.toThrow();
    expect(sendMock).not.toHaveBeenCalled();
  });

  it("throws on an internal/own-domain recipient", async () => {
    await expect(
      sendCompliantOutbound(validArgs({ to: "ops@jikigai.com" })),
    ).rejects.toThrow();
    expect(sendMock).not.toHaveBeenCalled();
  });

  it("throws when the body hash does not match the approved hash (mutation)", async () => {
    await expect(
      sendCompliantOutbound(validArgs({ approvedBodySha256: sha256("a DIFFERENT body") })),
    ).rejects.toThrow(/approv|hash|mismatch/i);
    expect(sendMock).not.toHaveBeenCalled();
  });

  it("throws when the recipient is suppressed (in-txn recheck, C5) and does not send", async () => {
    const sb = makeSupabase({ suppressed: true });
    await expect(
      sendCompliantOutbound({ ...validArgs(), supabase: sb }),
    ).rejects.toThrow(/suppress/i);
    expect(sb.calls.some((c) => c.name === "is_recipient_suppressed")).toBe(true);
    expect(sendMock).not.toHaveBeenCalled();
    expect(sb.calls.some((c) => c.name === "record_outbound_send")).toBe(false);
  });

  it("throws on a duplicate send (same approved body to same recipient) and does not send", async () => {
    const sb = makeSupabase({ alreadySent: true });
    await expect(
      sendCompliantOutbound({ ...validArgs(), supabase: sb }),
    ).rejects.toThrow(/duplicate|already/i);
    expect(sb.calls.some((c) => c.name === "outbound_send_exists")).toBe(true);
    expect(sendMock).not.toHaveBeenCalled();
    expect(sb.calls.some((c) => c.name === "record_outbound_send")).toBe(false);
  });

  it("defaults unknown jurisdiction to EU/UK-strict (Art.14 required)", async () => {
    await expect(
      sendCompliantOutbound(validArgs({ jurisdiction: "unknown" })),
    ).rejects.toThrow(/c3/i);
    expect(sendMock).not.toHaveBeenCalled();
  });
});

describe("sendCompliantOutbound — Resend failure", () => {
  it("throws + mirrors to Sentry (PII-free) and does NOT record a send row", async () => {
    sendMock.mockResolvedValue({ data: null, error: { message: "rejected: journalist@example.com bounced" } });
    const sb = makeSupabase();
    await expect(
      sendCompliantOutbound({ ...validArgs(), supabase: sb }),
    ).rejects.toThrow();
    expect(reportSilentFallbackMock).toHaveBeenCalled();
    // The Sentry mirror must not carry the recipient address.
    const mirrorArgs = JSON.stringify(reportSilentFallbackMock.mock.calls);
    expect(mirrorArgs).not.toContain("journalist@example.com");
    expect(sb.calls.some((c) => c.name === "record_outbound_send")).toBe(false);
  });
});

// ───────────────────────────────────────────────────────────────────────────
// Sentinel (plan §2.4 / FR write-boundary): the cold-outbound FROM literal and
// the Resend caller set are pinned so a future transactional caller cannot
// silently send cold mail (or send transactional mail from the cold subdomain).
// ───────────────────────────────────────────────────────────────────────────
const SERVER_DIR = path.join(__dirname, "../../server");

function walkServerTs(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === "node_modules") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walkServerTs(full));
    else if (entry.name.endsWith(".ts") && !entry.name.endsWith(".test.ts")) out.push(full);
  }
  return out;
}

const SERVER_FILES = walkServerTs(SERVER_DIR);
// The cold SENDING IDENTITY (any address ON the cold subdomain). This is the
// thing that must be unique to outbound.ts — a transactional caller sending
// FROM mail.soleur.ai would carry this. Distinct from the BARE domain string
// `mail.soleur.ai`, which outbound-compliance.ts legitimately lists in its
// recipient-block set (rejecting sends TO our own subdomain — the opposite,
// defensive concern). So the sentinel pins the `@`-prefixed sending form.
const COLD_FROM_ADDR = "@mail.soleur.ai";
const RESEND_SEND_ALLOWLIST = new Set([
  "notifications.ts",
  "cron-email-ingress-probe.ts",
  "outbound.ts",
]);

describe("outbound sentinel — cold-send FROM + Resend caller boundary", () => {
  it("(a) the cold sending identity (@mail.soleur.ai) lives in exactly one file (outbound.ts)", () => {
    const hits = SERVER_FILES.filter((f) =>
      readFileSync(f, "utf8").includes(COLD_FROM_ADDR),
    );
    expect(hits.map((f) => path.basename(f)).sort()).toEqual(["outbound.ts"]);
  });

  it("(b) resend.emails.send callers are limited to the allowlist", () => {
    const callers = SERVER_FILES.filter((f) =>
      /\.emails\.send\s*\(/.test(readFileSync(f, "utf8")),
    ).map((f) => path.basename(f));
    for (const caller of callers) {
      expect(RESEND_SEND_ALLOWLIST.has(caller), `unexpected resend.emails.send caller: ${caller}`).toBe(true);
    }
    // outbound.ts MUST be among them (the chokepoint sends).
    expect(callers).toContain("outbound.ts");
  });

  it("(c) no file other than outbound.ts sends FROM the cold subdomain", () => {
    const offenders = SERVER_FILES.filter(
      (f) =>
        path.basename(f) !== "outbound.ts" &&
        readFileSync(f, "utf8").includes(COLD_FROM_ADDR),
    ).map((f) => path.basename(f));
    expect(offenders).toEqual([]);
  });
});
