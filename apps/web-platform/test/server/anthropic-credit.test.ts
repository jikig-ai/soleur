// #8505 — named operator-credit-exhaustion marker.
//
// The marker must reach Sentry WITH its feature/op/source tags. The Error path of
// reportSilentFallback loses them in production (the pino mirror captures the same
// Error instance first as `feature=pino-mirror`, and @sentry/core drops the second,
// tagged capture), so the reporter uses the message path. The last describe block
// wires the REAL logger + REAL observability to prove no pre-empting capture fires.

import { beforeEach, describe, expect, it, vi } from "vitest";

const { captureExceptionSpy, captureMessageSpy } = vi.hoisted(() => ({
  captureExceptionSpy: vi.fn(),
  captureMessageSpy: vi.fn(),
}));
vi.mock("@sentry/nextjs", () => ({
  captureException: captureExceptionSpy,
  captureMessage: captureMessageSpy,
  addBreadcrumb: vi.fn(),
}));

import {
  ANTHROPIC_CREDIT_EXHAUSTED_FEATURE,
  ANTHROPIC_CREDIT_EXHAUSTED_OP,
  isAnthropicCreditExhausted,
  reportAnthropicCreditExhausted,
} from "@/server/anthropic-credit";

// Real body shapes (synthesized from the observed vendor text, no real ids).
const SDK_CREDIT_MESSAGE =
  '400 {"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."}}';
const TRANSPORT_CREDIT_EXCERPT =
  '{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}';

beforeEach(() => {
  captureExceptionSpy.mockReset();
  captureMessageSpy.mockReset();
});

describe("isAnthropicCreditExhausted", () => {
  it("matches the SDK APIError message and the transport body excerpt", () => {
    expect(isAnthropicCreditExhausted(SDK_CREDIT_MESSAGE)).toBe(true);
    expect(isAnthropicCreditExhausted(TRANSPORT_CREDIT_EXCERPT)).toBe(true);
  });

  it("does not match a non-credit 400, transient statuses, or a spend-limit cap", () => {
    expect(
      isAnthropicCreditExhausted(
        '{"type":"error","error":{"type":"invalid_request_error","message":"max_tokens: must be positive"}}',
      ),
    ).toBe(false);
    expect(isAnthropicCreditExhausted("429 rate_limit_error")).toBe(false);
    expect(isAnthropicCreditExhausted("529 overloaded_error")).toBe(false);
    // A workspace/org spend cap is NOT an empty wallet — the CI key hitting its
    // cap is intended behavior and must never page as operator exhaustion.
    expect(
      isAnthropicCreditExhausted(
        "You have reached your specified API usage limits. You will regain access on 2026-10-01.",
      ),
    ).toBe(false);
    expect(isAnthropicCreditExhausted(undefined)).toBe(false);
    expect(isAnthropicCreditExhausted("")).toBe(false);
  });
});

describe("reportAnthropicCreditExhausted (real logger + real observability)", () => {
  it("emits exactly one tagged captureMessage and never captureException", () => {
    reportAnthropicCreditExhausted({ source: "cron:cron-anthropic-credit-probe", status: 400 });

    expect(captureExceptionSpy).not.toHaveBeenCalled();
    expect(captureMessageSpy).toHaveBeenCalledTimes(1);
    const [message, ctx] = captureMessageSpy.mock.calls[0] as [
      string,
      { tags: Record<string, string>; extra: Record<string, unknown> },
    ];
    expect(message).toBe("Anthropic credit balance is too low — operator key exhausted");
    expect(ctx.tags).toMatchObject({
      feature: ANTHROPIC_CREDIT_EXHAUSTED_FEATURE,
      op: ANTHROPIC_CREDIT_EXHAUSTED_OP,
      source: "cron:cron-anthropic-credit-probe",
    });
    expect(ctx.extra.status).toBe(400);
  });

  it("carries the exact literals the Sentry alert filters on", () => {
    expect(ANTHROPIC_CREDIT_EXHAUSTED_FEATURE).toBe("anthropic-credit");
    expect(ANTHROPIC_CREDIT_EXHAUSTED_OP).toBe("anthropic-credit-exhausted");
  });

  it("never forwards a vendor body into the event", () => {
    reportAnthropicCreditExhausted({ source: "email-triage", status: 400 });
    const serialized = JSON.stringify(captureMessageSpy.mock.calls);
    expect(serialized).not.toContain("credit balance is too low to access");
    expect(serialized).not.toContain("sk-ant-");
  });
});
