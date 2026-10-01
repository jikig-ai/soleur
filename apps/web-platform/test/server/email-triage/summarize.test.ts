// #8505 — the email-triage summarizer is the only SDK caller of the operator
// Anthropic key, so it is the second credit-marker chokepoint (the first is the
// shared HTTP transport in _cron-shared.ts). A credit 400 must be reported with
// source=email-triage and rethrown unchanged, so the caller's retries stay intact.

import { beforeEach, describe, expect, it, vi } from "vitest";

const { createSpy, reportSilentFallbackSpy } = vi.hoisted(() => ({
  createSpy: vi.fn(),
  reportSilentFallbackSpy: vi.fn(),
}));

vi.mock("@anthropic-ai/sdk", async (importOriginal) => {
  const actual = (await importOriginal()) as Record<string, unknown>;
  class FakeAnthropic {
    messages = { create: createSpy };
  }
  return { ...actual, default: FakeAnthropic };
});
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: vi.fn(),
}));

import { APIError, BadRequestError } from "@anthropic-ai/sdk";
import { ANTHROPIC_CREDIT_EXHAUSTED_OP } from "@/server/anthropic-credit";
import { summarizeEmail } from "@/server/email-triage/summarize";

const input = { subject: "Invoice", sender: "billing@example.test", bodyText: "Hello" };
const creditReports = () =>
  reportSilentFallbackSpy.mock.calls.filter(
    ([, ctx]) => (ctx as { op?: string }).op === ANTHROPIC_CREDIT_EXHAUSTED_OP,
  );

beforeEach(() => {
  createSpy.mockReset();
  reportSilentFallbackSpy.mockReset();
  process.env.ANTHROPIC_API_KEY = "sk-ant-" + "synthetic-operator-key";
});

describe("summarizeEmail — credit exhaustion (#8505)", () => {
  it("reports source=email-triage on a credit BadRequestError and rethrows the same error", async () => {
    const err = new BadRequestError(
      400,
      {
        type: "error",
        error: {
          type: "invalid_request_error",
          message: "Your credit balance is too low to access the Anthropic API.",
        },
      },
      undefined,
      new Headers(),
    );
    // Precondition: the SDK's own message carries the vendor text (the classifier input).
    expect(err.message).toMatch(/credit balance is too low/i);
    createSpy.mockRejectedValue(err);

    const thrown = await summarizeEmail(input).catch((e: unknown) => e);
    expect(thrown).toBe(err);

    const reports = creditReports();
    expect(reports).toHaveLength(1);
    const [errArg, ctx] = reports[0] as [
      unknown,
      { tags: Record<string, string>; extra: Record<string, unknown> },
    ];
    expect(errArg).toBeNull();
    expect(ctx.tags.source).toBe("email-triage");
    expect(ctx.extra.status).toBe(400);
    // TR3: neither the vendor text nor any email content leaves this module.
    const serialized = JSON.stringify(reports[0]);
    expect(serialized).not.toContain("credit balance is too low to access");
    expect(serialized).not.toContain("billing@example.test");
  });

  it("does not report on a non-credit 400, and still rethrows", async () => {
    const err = new BadRequestError(
      400,
      { type: "error", error: { type: "invalid_request_error", message: "max_tokens: must be positive" } },
      undefined,
      new Headers(),
    );
    createSpy.mockRejectedValue(err);
    await expect(summarizeEmail(input)).rejects.toBe(err);
    expect(creditReports()).toHaveLength(0);
  });

  it("does not report on a non-APIError throw", async () => {
    const err = new Error("Your credit balance is too low (not from the SDK)");
    createSpy.mockRejectedValue(err);
    await expect(summarizeEmail(input)).rejects.toBe(err);
    expect(creditReports()).toHaveLength(0);
    // Sanity: the discriminator is the SDK error class, not the text alone.
    expect(err).not.toBeInstanceOf(APIError);
  });

  it("returns the summary on success without reporting", async () => {
    createSpy.mockResolvedValue({
      content: [{ type: "text", text: '{"summary":"An invoice.","mail_class":"billing"}' }],
    });
    await expect(summarizeEmail(input)).resolves.toEqual({
      summary: "An invoice.",
      mailClass: "billing",
    });
    expect(creditReports()).toHaveLength(0);
  });
});
