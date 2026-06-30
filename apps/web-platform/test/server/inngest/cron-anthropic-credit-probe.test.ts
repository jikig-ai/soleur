// #5674 — cron-anthropic-credit-probe canary tests (AC5 + AC10).
//
// The probe pings the operator Anthropic key once an hour. A CLASSIFIED fatal
// body pages (credit exhausted / auth revoked); a transient/unclassified error
// RE-THROWS so Inngest retries (NO false page); a clean reply is green.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// inngest client throws on missing INNGEST_SIGNING_KEY at module load — set the
// build-phase bypass BEFORE the handler import chain runs.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: vi.fn(),
}));

const postAnthropicMessageSpy = vi.fn();
const postSentryHeartbeatSpy = vi.fn();
vi.mock("@/server/inngest/functions/_cron-shared", async (importActual) => {
  const actual = (await importActual()) as Record<string, unknown>;
  return {
    ...actual,
    postAnthropicMessage: (...a: unknown[]) => postAnthropicMessageSpy(...a),
    postSentryHeartbeat: (...a: unknown[]) => postSentryHeartbeatSpy(...a),
  };
});

import { AnthropicApiError } from "@/server/inngest/functions/_cron-shared";
import { cronAnthropicCreditProbeHandler } from "@/server/inngest/functions/cron-anthropic-credit-probe";

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
const makeStep = () => ({
  run: vi.fn(async (_id: string, fn: () => Promise<unknown>) => fn()),
});

function lastHeartbeatOk(): boolean | undefined {
  const calls = postSentryHeartbeatSpy.mock.calls;
  if (calls.length === 0) return undefined;
  return (calls[calls.length - 1][0] as { ok: boolean }).ok;
}

beforeEach(() => {
  reportSilentFallbackSpy.mockReset();
  postAnthropicMessageSpy.mockReset();
  postSentryHeartbeatSpy.mockReset().mockResolvedValue(undefined);
  process.env.ANTHROPIC_API_KEY = "sk-ant-" + "synthetic-operator-key";
});

afterEach(() => {
  delete process.env.ANTHROPIC_API_KEY;
});

describe("cron-anthropic-credit-probe — canary classification (AC5)", () => {
  it("credit-balance 400 → pages (op=anthropic-credit-exhausted) + monitor red", async () => {
    postAnthropicMessageSpy.mockRejectedValue(
      new AnthropicApiError(400, "Credit balance is too low"),
    );
    const result = await cronAnthropicCreditProbeHandler({ step: makeStep() as never, logger });
    expect(result.ok).toBe(false);
    expect(lastHeartbeatOk()).toBe(false);
    const page = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string }).op === "anthropic-credit-exhausted",
    );
    expect(page).toBeDefined();
  });

  it("401 / auth → pages (op=anthropic-key-invalid) + monitor red", async () => {
    postAnthropicMessageSpy.mockRejectedValue(
      new AnthropicApiError(401, "invalid x-api-key"),
    );
    const result = await cronAnthropicCreditProbeHandler({ step: makeStep() as never, logger });
    expect(result.ok).toBe(false);
    expect(lastHeartbeatOk()).toBe(false);
    const page = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string }).op === "anthropic-key-invalid",
    );
    expect(page).toBeDefined();
  });

  it("529 overloaded (transient) → RE-THROWS (Inngest retry) — NO page, NO red heartbeat", async () => {
    postAnthropicMessageSpy.mockRejectedValue(
      new AnthropicApiError(529, "overloaded_error"),
    );
    await expect(
      cronAnthropicCreditProbeHandler({ step: makeStep() as never, logger }),
    ).rejects.toThrow();
    // No credit/key page; no heartbeat at all (the throw happened before it).
    const page = reportSilentFallbackSpy.mock.calls.find(([, ctx]) =>
      ["anthropic-credit-exhausted", "anthropic-key-invalid"].includes(
        (ctx as { op?: string }).op ?? "",
      ),
    );
    expect(page).toBeUndefined();
    expect(postSentryHeartbeatSpy).not.toHaveBeenCalled();
  });

  it("429 rate-limit (transient) → RE-THROWS — NO page", async () => {
    postAnthropicMessageSpy.mockRejectedValue(new AnthropicApiError(429, "rate_limit"));
    await expect(
      cronAnthropicCreditProbeHandler({ step: makeStep() as never, logger }),
    ).rejects.toThrow();
    expect(postSentryHeartbeatSpy).not.toHaveBeenCalled();
  });

  it("network/DNS error (non-typed) → RE-THROWS — NO page", async () => {
    postAnthropicMessageSpy.mockRejectedValue(
      new Error("Anthropic API request failed (TypeError)"),
    );
    await expect(
      cronAnthropicCreditProbeHandler({ step: makeStep() as never, logger }),
    ).rejects.toThrow();
    expect(postSentryHeartbeatSpy).not.toHaveBeenCalled();
  });

  it("clean 1-token reply → ok:true (monitor green, liveness AND success)", async () => {
    postAnthropicMessageSpy.mockResolvedValue({ text: "ok", stopReason: "end_turn" });
    const result = await cronAnthropicCreditProbeHandler({ step: makeStep() as never, logger });
    expect(result.ok).toBe(true);
    expect(lastHeartbeatOk()).toBe(true);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("missing ANTHROPIC_API_KEY → red (env misconfig, not credit)", async () => {
    delete process.env.ANTHROPIC_API_KEY;
    const result = await cronAnthropicCreditProbeHandler({ step: makeStep() as never, logger });
    expect(result.ok).toBe(false);
    expect(lastHeartbeatOk()).toBe(false);
    expect(postAnthropicMessageSpy).not.toHaveBeenCalled();
  });
});

describe("cron-anthropic-credit-probe — ADR-033 I2 (AC10)", () => {
  it("does NOT import runWithByokLease (uses the operator key only)", () => {
    const src = readFileSync(
      resolve(__dirname, "../../../server/inngest/functions/cron-anthropic-credit-probe.ts"),
      "utf8",
    );
    expect(src).not.toContain("runWithByokLease");
    expect(src).toContain("ANTHROPIC_API_KEY");
  });
});
