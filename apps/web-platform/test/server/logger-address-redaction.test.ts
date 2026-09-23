import { describe, it, expect, vi, beforeEach } from "vitest";
import { Writable } from "node:stream";
import pino from "pino";

// Drives the REAL logger.ts hook (only Sentry is mocked): an address inside a
// logged value must not reach Sentry through mirrorToSentry, and the args the
// hook forwards to pino must be the redacted ones (#8532 PR-0).
const { mockCaptureException, mockAddBreadcrumb } = vi.hoisted(() => ({
  mockCaptureException: vi.fn(),
  mockAddBreadcrumb: vi.fn(),
}));
vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  addBreadcrumb: mockAddBreadcrumb,
}));

import logger, { REDACT_PATHS, createChildLogger, redactLogArgs } from "@/server/logger";

const LOCAL = "qzv8tkl";
const DOMAIN = "mailbox-r7x.example";
const LEAK = `${LOCAL}@${DOMAIN}`;

function sinkText(): string {
  return JSON.stringify([mockCaptureException.mock.calls, mockAddBreadcrumb.mock.calls], (_k, v) =>
    v instanceof Error ? { message: v.message, stack: v.stack } : v,
  );
}

beforeEach(() => {
  mockCaptureException.mockReset();
  mockAddBreadcrumb.mockReset();
});

describe("logger hook — value redaction before mirrorToSentry", () => {
  it("instrument: an unredacted capture is visible to sinkText()", () => {
    mockCaptureException(new Error(LEAK));
    expect(sinkText()).toContain(LOCAL);
  });

  it("logger.error({ err }) with an address in err.message reaches Sentry redacted", () => {
    logger.error({ err: new Error(`Resend rejected ${LEAK}`) }, "send failed");
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    expect(sinkText()).not.toContain(LOCAL);
  });

  it("a createChildLogger child is covered too (it inherits the hook)", () => {
    createChildLogger("notifications").error({ err: new Error(LEAK) }, `failed for ${LEAK}`);
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    expect(sinkText()).not.toContain(LOCAL);
  });
});

describe("redactLogArgs — what the hook hands to pino", () => {
  it("redacts the message string, the err key and top-level string values", () => {
    const out = redactLogArgs([{ err: new Error(LEAK), note: `to ${LEAK}`, n: 1 }, `msg ${LEAK}`]);
    const text = JSON.stringify(out, (_k, v) => (v instanceof Error ? v.message : v));
    expect(text).not.toContain(LOCAL);
    expect(text).toContain('"n":1');
  });

  it("returns the caller's object untouched when there is nothing to redact", () => {
    const obj = { conversationId: "c1" };
    expect(redactLogArgs([obj, "ok"])[0]).toBe(obj);
  });
});

describe("REDACT_PATHS on a real pino instance", () => {
  it("drops the address under the email / inviteeEmail / recipient keys", () => {
    let captured = "";
    const sink = new Writable({
      write(chunk, _enc, cb) {
        captured += chunk.toString();
        cb();
      },
    });
    const p = pino({ redact: [...REDACT_PATHS] }, sink);
    p.info({ email: LEAK, inviteeEmail: LEAK, recipient: LEAK, nested: { email: LEAK } }, "x");
    expect(captured).toContain('"email"');
    expect(captured).not.toContain(LOCAL);
  });
});
