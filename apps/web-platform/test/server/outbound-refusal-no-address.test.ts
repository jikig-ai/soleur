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
} from "../../server/email-triage/outbound-compliance";
import {
  __resetMirrorP0DedupForTests,
  infoSilentFallback,
  mirrorP0Deduped,
  reportSilentFallback,
  warnSilentFallback,
} from "../../server/observability";
import { scrubSentryEvent } from "../../server/sentry-scrub";
import {
  buildGateMessage,
  buildOfflineGateMessage,
  summarizeOutboundEmailInput,
} from "../../server/tool-tiers";
import { REDACT_PATHS, SENSITIVE_KEY_NAMES } from "../../server/sensitive-keys";

// Synthesized, distinctive tokens: a leak of EITHER half is detectable without
// matching generic words the messages legitimately contain ("address", "to").
const LOCAL = "qzv8tkl";
const DOMAIN = "mailbox-r7x.example";
const DISPLAY = "Wendeline Qorvath";
// The display name is fixtured at the throw sites (AC-0a), where
// `extractAddrSpec` strips it; the emitter cannot recognise a bare display
// name by shape, so the emitter rows below assert only LOCAL and DOMAIN.
const FORBIDDEN = [LOCAL, DOMAIN, DISPLAY, "Qorvath"];
const EMITTER_FORBIDDEN = [LOCAL, DOMAIN];

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

function assertNoAddress(label: string, text: string, tokens: readonly string[] = FORBIDDEN): void {
  for (const token of tokens) {
    expect(text, `${label} leaked "${token}"`).not.toContain(token);
  }
}
const assertEmitterClean = (label: string, text: string) =>
  assertNoAddress(label, text, EMITTER_FORBIDDEN);

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

  // INSTRUMENT SELF-TEST: every sink emittedText() reads must be able to
  // show a leak, or each emitter row below passes without checking anything.
  it("instrument: a leak planted in each sink is detected", () => {
    const leak = `${LOCAL}@${DOMAIN}`;
    for (const sink of [mockLoggerError, mockLoggerWarn, mockLoggerInfo, mockCaptureException, mockCaptureMessage]) {
      sink.mockReset();
      sink({ err: new Error(leak) });
      expect(() => assertEmitterClean("planted", emittedText())).toThrow();
      sink.mockReset();
    }
  });

  // Restates AC-0a at the email_send catch's call shape; the emitter-layer
  // guarantee is the vendor-error rows below.
  it("the refusal from the throw site stays clean through reportSilentFallback", () => {
    const err = refusalOf(REFUSALS[0]!.run);
    reportSilentFallback(err, { feature: "email-triage-tools", op: "email_send", extra: { userId: "u1" } });
    expect(mockLoggerError).toHaveBeenCalledTimes(1);
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    assertNoAddress("emitted record", emittedText());
  });

  it("a string err reaches both sinks redacted", () => {
    reportSilentFallback(`resend said no to ${LOCAL}@${DOMAIN}`, { feature: "t" });
    assertEmitterClean("string err", emittedText());
  });

  it("a plain-object vendor error reaches both sinks redacted", () => {
    reportSilentFallback({ name: "validation_error", message: `Invalid to: ${LOCAL}@${DOMAIN}` }, { feature: "t" });
    assertEmitterClean("plain-object err", emittedText());
  });

  it("mirrorP0Deduped redacts the error it forwards", () => {
    __resetMirrorP0DedupForTests();
    mirrorP0Deduped(new Error(`p0 for ${LOCAL}@${DOMAIN}`), { op: "o", userId: "u1", conversationId: "c1" });
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    assertEmitterClean("p0 mirror", emittedText());
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
      assertEmitterClean(`${name} emitted record`, emittedText());
      // The caller's error object is not mutated — the redaction is a copy.
      expect(original.message).toContain(LOCAL);
      const captured = mockCaptureException.mock.calls[0]?.[0] as (Error & { code?: string }) | undefined;
      expect(captured).toBeInstanceOf(Error);
      expect(captured?.code).toBe("validation_error");
      expect(captured?.message).toContain("mailbox unavailable");
    });

    it(`${name} redacts an address in a non-Error message`, () => {
      emit(null, { feature: "t", message: `could not deliver to ${LOCAL}@${DOMAIN}` });
      assertEmitterClean(`${name} emitted record`, emittedText());
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

describe("Sentry value-layer: every capture path, not only the emitters", () => {
  it("scrubSentryEvent redacts an address in the exception value, the message and a breadcrumb", () => {
    const leak = `${LOCAL}@${DOMAIN}`;
    const out = scrubSentryEvent({
      message: `failed for ${leak}`,
      exception: { values: [{ type: "Error", value: `Resend rejected ${leak}` }] },
      breadcrumbs: [{ category: "pino", message: `send to ${leak}` }],
    });
    assertEmitterClean("scrubbed event", JSON.stringify(out));
  });
});

describe("the refusal names the field, never the value", () => {
  it("a bad replyTo is reported as field=replyTo, a bad to as field=to", () => {
    expect(refusalOf(REFUSALS[2]!.run).field).toBe("replyTo");
    expect(refusalOf(REFUSALS[0]!.run).field).toBe("to");
    expect(refusalOf(REFUSALS[5]!.run).field).toBe("to");
  });
});

describe("stores outside the log sinks (#8532 review)", () => {
  const input = { to: `${DISPLAY} <${LOCAL}@${DOMAIN}>`, subject: "Hello", body: `Hi ${DISPLAY}` };

  it("the offline approval notification for an outbound email carries no recipient or body", () => {
    for (const tool of ["email_send", "email_reply", "email_suppress"]) {
      const q = buildOfflineGateMessage(`mcp__soleur_platform__${tool}`, { ...input, recipient: input.to });
      assertNoAddress(`${tool} offline gate`, q);
    }
  });

  it("the in-app gate still shows the operator the exact recipient", () => {
    expect(buildGateMessage("mcp__soleur_platform__email_send", input)).toContain(LOCAL);
  });

  it("other tools keep their full gate text offline", () => {
    const i = { title: "T" };
    expect(buildOfflineGateMessage("mcp__soleur_platform__create_issue", i)).toBe(
      buildGateMessage("mcp__soleur_platform__create_issue", i),
    );
  });

  it("an aborted turn's summary of an outbound-email call names fields only", () => {
    const summary = summarizeOutboundEmailInput("mcp__soleur_platform__email_send", input);
    expect(summary).toContain("body, subject, to");
    assertNoAddress("completed_actions summary", summary ?? "");
    expect(summarizeOutboundEmailInput("mcp__soleur_platform__create_issue", input)).toBeNull();
  });
});
