import { describe, it, expect, vi, beforeEach } from "vitest";

// A refused outbound send must not carry the recipient address into any log
// sink. docs/legal/privacy-policy.md states "the plaintext recipient address is
// never stored"; before this fix a refusal interpolated the address into the
// OutboundComplianceError message, and email-triage-tools' `email_send` catch
// mirrored that error through reportSilentFallback into pino (journald on the
// web host's root disk), Better Stack, and Sentry (as the issue title).
//
// Two layers are pinned here:
//   AC-0a  the throw sites themselves emit no part of the address;
//   AC-0b  the emitter (reportSilentFallback / warn / info) redacts an
//          address-shaped substring from ANY error or message it forwards,
//          so a future throw site cannot reintroduce the class.

vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const { mockCaptureException, mockCaptureMessage, mockLoggerError, mockLoggerWarn, mockLoggerInfo } =
  vi.hoisted(() => ({
    mockCaptureException: vi.fn(),
    mockCaptureMessage: vi.fn(),
    mockLoggerError: vi.fn(),
    mockLoggerWarn: vi.fn(),
    mockLoggerInfo: vi.fn(),
  }));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

vi.mock("@/server/logger", () => ({
  default: { error: mockLoggerError, warn: mockLoggerWarn, info: mockLoggerInfo, debug: vi.fn() },
}));

import {
  OutboundComplianceError,
  assertRecipientAllowed,
  validateEmailHeaders,
} from "../server/email-triage/outbound-compliance";
import {
  infoSilentFallback,
  reportSilentFallback,
  warnSilentFallback,
} from "../server/observability";
import { REDACT_PATHS, SENSITIVE_KEY_NAMES } from "../server/sensitive-keys";

// Synthesized, distinctive tokens: a leak of EITHER half is detectable without
// matching generic words the messages legitimately contain ("address", "to").
const LOCAL = "qzv8tkl";
const DOMAIN = "mailbox-r7x.example";
const DISPLAY = "Wendeline Qorvath";
const FORBIDDEN = [LOCAL, DOMAIN, DISPLAY, "Qorvath"];

/**
 * Every string reachable from `v`: own properties (enumerable or not), so an
 * Error's `message` and `stack` are read even though JSON.stringify drops them.
 */
function allText(v: unknown, seen = new Set<unknown>()): string {
  if (v === null || v === undefined) return "";
  if (typeof v === "string") return v;
  if (typeof v !== "object" && typeof v !== "function") return String(v);
  if (seen.has(v)) return "";
  seen.add(v);
  const parts: string[] = [];
  for (const key of Object.getOwnPropertyNames(v)) {
    parts.push(allText((v as Record<string, unknown>)[key], seen));
  }
  return parts.join("\n");
}

function assertNoAddress(label: string, text: string): void {
  for (const token of FORBIDDEN) {
    expect(text, `${label} leaked "${token}"`).not.toContain(token);
  }
}

function emittedText(): string {
  return allText([
    mockLoggerError.mock.calls,
    mockLoggerWarn.mock.calls,
    mockLoggerInfo.mock.calls,
    mockCaptureException.mock.calls,
    mockCaptureMessage.mock.calls,
  ]);
}

function refusalOf(fn: () => void): OutboundComplianceError {
  try {
    fn();
  } catch (e) {
    expect(e).toBeInstanceOf(OutboundComplianceError);
    return e as OutboundComplianceError;
  }
  throw new Error("expected a refusal, got none");
}

const baseHeaders = {
  from: "Founder <founder@outbound.soleur.ai>",
  subject: "Hello",
};

// Every refusal reachable with a caller-supplied recipient. Each entry names
// the code it must produce, so a row that stops reaching its throw site fails
// loudly instead of silently testing a different branch.
const REFUSALS: Array<{ name: string; code: string; run: () => void }> = [
  {
    name: "validateEmailHeaders: display-name + malformed addr-spec",
    code: "invalid_address",
    run: () => validateEmailHeaders({ ...baseHeaders, to: `${DISPLAY} <${LOCAL}@@${DOMAIN}>` }),
  },
  {
    name: "validateEmailHeaders: bare malformed address",
    code: "invalid_address",
    run: () => validateEmailHeaders({ ...baseHeaders, to: `${LOCAL} at ${DOMAIN}` }),
  },
  {
    name: "validateEmailHeaders: malformed replyTo",
    code: "invalid_address",
    run: () =>
      validateEmailHeaders({ ...baseHeaders, to: "ok@example.com", replyTo: `${LOCAL}@${DOMAIN}@` }),
  },
  {
    name: "validateEmailHeaders: header injection in to",
    code: "header_injection",
    run: () => validateEmailHeaders({ ...baseHeaders, to: `${LOCAL}@${DOMAIN}\r\nBcc: x@y.z` }),
  },
  {
    name: "validateEmailHeaders: multiple recipients",
    code: "recipient_count",
    run: () => validateEmailHeaders({ ...baseHeaders, to: `${LOCAL}@${DOMAIN}, other@${DOMAIN}` }),
  },
  {
    name: "assertRecipientAllowed: display-name with no @",
    code: "invalid_address",
    run: () => assertRecipientAllowed(`${DISPLAY} <${LOCAL}.${DOMAIN}>`),
  },
];

describe("AC-0a — refusal messages carry no part of the recipient address", () => {
  for (const r of REFUSALS) {
    it(r.name, () => {
      const err = refusalOf(r.run);
      expect(err.code).toBe(r.code);
      assertNoAddress(`${r.name} message`, err.message);
      assertNoAddress(`${r.name} stack`, err.stack ?? "");
    });
  }
});

describe("AC-0b — a refused send mirrored through the emitter carries no address", () => {
  beforeEach(() => {
    mockCaptureException.mockReset();
    mockCaptureMessage.mockReset();
    mockLoggerError.mockReset();
    mockLoggerWarn.mockReset();
    mockLoggerInfo.mockReset();
  });

  it("the email_send catch shape: reportSilentFallback(refusal) reaches pino and Sentry clean", () => {
    const err = refusalOf(REFUSALS[0]!.run);
    reportSilentFallback(err, { feature: "email-triage-tools", op: "email_send", extra: { userId: "u1" } });
    expect(mockLoggerError).toHaveBeenCalledTimes(1);
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    assertNoAddress("emitted record", emittedText());
  });

  // The class fix: an error from ANY source (a vendor SDK, a future throw site)
  // whose message embeds an address is redacted at the emitter.
  const vendorError = () => {
    const e = new Error(`Resend rejected recipient ${LOCAL}@${DOMAIN}: mailbox unavailable`) as Error & {
      code?: string;
    };
    e.code = "validation_error";
    return e;
  };

  for (const [name, emit] of [
    ["reportSilentFallback", reportSilentFallback],
    ["warnSilentFallback", warnSilentFallback],
    ["infoSilentFallback", infoSilentFallback],
  ] as const) {
    it(`${name} redacts an address inside an arbitrary Error, keeping class and code`, () => {
      const original = vendorError();
      emit(original, { feature: "t", op: "o" });
      assertNoAddress(`${name} emitted record`, emittedText());
      // The caller's error object is not mutated — the redaction is a copy.
      expect(original.message).toContain(LOCAL);
      const captured = mockCaptureException.mock.calls[0]?.[0] as (Error & { code?: string }) | undefined;
      expect(captured).toBeInstanceOf(Error);
      expect(captured?.code).toBe("validation_error");
      expect(captured?.message).toContain("mailbox unavailable");
    });

    it(`${name} redacts an address in a non-Error message`, () => {
      emit(null, { feature: "t", message: `could not deliver to ${LOCAL}@${DOMAIN}` });
      assertNoAddress(`${name} emitted record`, emittedText());
    });
  }

  it("an error with no address is forwarded as the SAME object (Sentry dedupe identity preserved)", () => {
    const e = new Error("plain failure");
    reportSilentFallback(e, { feature: "t" });
    expect(mockCaptureException.mock.calls[0]?.[0]).toBe(e);
  });
});

describe("key-name redaction covers the address-bearing log keys", () => {
  for (const key of ["email", "inviteeEmail", "recipient"]) {
    it(`${key} is a sensitive key at top level and one level deep`, () => {
      expect(SENSITIVE_KEY_NAMES).toContain(key);
      expect(REDACT_PATHS).toContain(key);
      expect(REDACT_PATHS).toContain(`*.${key}`);
    });
  }
});
