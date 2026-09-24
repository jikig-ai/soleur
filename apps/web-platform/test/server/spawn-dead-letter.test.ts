// #8719 — the leader-loop dead-letter must reach Sentry WITH its feature/op/reason
// tags. The Error path of reportSilentFallback loses them in production (the pino
// mirror captures the same Error instance first as `feature=pino-mirror`, and
// @sentry/core drops the second, tagged capture — #8629), so the emitter sends a
// plain object down the message path. Only `@sentry/nextjs` is mocked: the REAL
// logger hook and the REAL reportSilentFallback run, so a change to either that
// re-routes a plain object to captureException reds this suite.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { captureExceptionSpy, captureMessageSpy, addBreadcrumbSpy } = vi.hoisted(() => ({
  captureExceptionSpy: vi.fn(),
  captureMessageSpy: vi.fn(),
  addBreadcrumbSpy: vi.fn(),
}));
vi.mock("@sentry/nextjs", () => ({
  captureException: captureExceptionSpy,
  captureMessage: captureMessageSpy,
  addBreadcrumb: addBreadcrumbSpy,
}));

type Emitter = typeof import("@/server/spawn-dead-letter");
type MessageCtx = {
  level: string;
  tags: Record<string, string>;
  extra: Record<string, unknown> & { err?: Record<string, unknown> };
};

// Synthesized fixture id (cq-test-fixtures-synthesized-only).
const FOUNDER_ID = "0f4c1d2e-3a5b-4c6d-8e9f-a0b1c2d3e4f5";

/**
 * The logger reads LOG_LEVEL and SENTRY_BREADCRUMB_LEVEL at module load, so pin
 * both and import fresh. Without the pin, a high LOG_LEVEL would make "no
 * pino-mirror capture" pass without the hook ever running.
 */
async function load(): Promise<Emitter> {
  vi.stubEnv("LOG_LEVEL", "info");
  vi.stubEnv("SENTRY_BREADCRUMB_LEVEL", "warn");
  vi.resetModules();
  return import("@/server/spawn-dead-letter");
}

function onlyMessage(): [string, MessageCtx] {
  expect(captureMessageSpy).toHaveBeenCalledTimes(1);
  return captureMessageSpy.mock.calls[0] as [string, MessageCtx];
}

beforeEach(() => {
  captureExceptionSpy.mockReset();
  captureMessageSpy.mockReset();
  addBreadcrumbSpy.mockReset();
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.doUnmock("@/server/observability");
});

describe("reportSpawnDeadLetter (real logger + real observability)", () => {
  it("sends exactly one tagged message event and no exception event", async () => {
    const { reportSpawnDeadLetter, SPAWN_DEAD_LETTER_FEATURE, SPAWN_DEAD_LETTER_OP } = await load();
    const err = new Error("tool addLabels not in allowlist for engineering.pr_review_pending");

    reportSpawnDeadLetter({
      reason: "leader_tool_invalid",
      err,
      extra: { founderId: FOUNDER_ID, actionClass: "engineering.pr_review_pending", turn: 1 },
    });

    expect(captureExceptionSpy).not.toHaveBeenCalled();
    const [message, ctx] = onlyMessage();
    expect(message).toBe("agent-on-spawn deadlettered: leader_tool_invalid");
    expect(ctx.level).toBe("error");
    expect(ctx.tags).toEqual({
      feature: SPAWN_DEAD_LETTER_FEATURE,
      op: SPAWN_DEAD_LETTER_OP,
      reason: "leader_tool_invalid",
    });
    // The SDK's message and stack survive for triage, as a plain object.
    expect(ctx.extra.err).not.toBeInstanceOf(Error);
    expect(ctx.extra.err?.message).toBe(err.message);
    expect(ctx.extra.err?.stack).toBe(err.stack);
    expect(ctx.extra.actionClass).toBe("engineering.pr_review_pending");
    expect(ctx.extra.reason).toBe("leader_tool_invalid");
  });

  it("the pino hook ran (positive control) and did not capture the dead-letter itself", async () => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({ reason: "leader_refused", err: new Error("declined"), extra: {} });

    expect(addBreadcrumbSpy).toHaveBeenCalledWith(
      expect.objectContaining({ category: "pino", message: "agent-on-spawn deadlettered: leader_refused" }),
    );
    expect(captureExceptionSpy).not.toHaveBeenCalled();
  });

  it("pseudonymizes the founder id: userIdHash present, raw id nowhere in the event", async () => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({ reason: "anthropic_request_rejected", err: new Error("400 x"), extra: { founderId: FOUNDER_ID } });

    const [, ctx] = onlyMessage();
    expect(typeof ctx.extra.userIdHash).toBe("string");
    expect(ctx.extra.founderId).toBeUndefined();
    expect(JSON.stringify(captureMessageSpy.mock.calls[0])).not.toContain(FOUNDER_ID);
  });

  it("never spreads the SDK error: headers and the vendor body do not reach extra.err", async () => {
    const { reportSpawnDeadLetter } = await load();
    const sdkErr = Object.assign(new Error("400 {\"type\":\"error\"}"), {
      status: 400,
      headers: { "request-id": "req_synthetic" },
      error: { type: "error", error: { type: "invalid_request_error" } },
    });
    reportSpawnDeadLetter({ reason: "anthropic_request_rejected", err: sdkErr, extra: {} });

    const [, ctx] = onlyMessage();
    expect(Object.keys(ctx.extra.err ?? {}).sort()).toEqual(["message", "name", "stack"]);
  });

  it("a direct PostgREST-shaped error keeps its SQLSTATE as the pg_code tag", async () => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({
      reason: "acknowledgment_persist_failed",
      err: { code: "42501", message: "permission denied for table action_sends", details: "row x" },
      extra: {},
    });

    const [, ctx] = onlyMessage();
    expect(ctx.tags.pg_code).toBe("42501");
    expect(ctx.extra.err?.message).toBe("permission denied for table action_sends");
    expect(ctx.extra.err?.details).toBeUndefined();
  });

  it.each<[string, unknown]>([
    ["a string", "plain string failure"],
    ["null", null],
    ["undefined", undefined],
    ["a prototype-less object", Object.create(null)],
    ["a StepError-shaped object", { name: "Error", message: "step failed", stack: "Error: step failed\n    at x", cause: "fetch_failed" }],
    ["a PostgREST-shaped object", { code: "PGRST116", message: "no rows", details: "0 rows" }],
    ["an Error subclass with status", Object.assign(new TypeError("413 too large"), { status: 413 })],
  ])("%s yields one tagged message event, never the report-failed fallback", async (_label, err) => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({ reason: "leader_response_truncated", err, extra: {} });

    expect(captureExceptionSpy).not.toHaveBeenCalled();
    const [message, ctx] = onlyMessage();
    expect(message).toBe("agent-on-spawn deadlettered: leader_response_truncated");
    expect(ctx.tags.reason).toBe("leader_response_truncated");
    expect(ctx.extra.err).not.toBeInstanceOf(Error);
    expect(typeof ctx.extra.err?.message).toBe("string");
  });

  it("the PostgREST-shaped object's message survives (not '[object Object]')", async () => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({ reason: "github_api_error", err: { code: "PGRST116", message: "no rows" }, extra: {} });
    expect(onlyMessage()[1].extra.err?.message).toBe("no rows");
  });
});

describe("reportSpawnDeadLetter — a throwing reporter never escapes", () => {
  it("swallows the throw and sends a tagged 'report failed' message the rule still matches", async () => {
    vi.doMock("@/server/observability", () => ({
      reportSilentFallback: () => {
        throw new Error("synthetic reporter failure");
      },
    }));
    const { reportSpawnDeadLetter, SPAWN_DEAD_LETTER_FEATURE, SPAWN_DEAD_LETTER_OP } = await load();

    expect(() =>
      reportSpawnDeadLetter({ reason: "leader_class_disabled", err: new Error("disabled"), extra: {} }),
    ).not.toThrow();

    expect(captureMessageSpy).toHaveBeenCalledWith(
      "agent-on-spawn deadlettered: report failed",
      expect.objectContaining({
        level: "error",
        tags: { feature: SPAWN_DEAD_LETTER_FEATURE, op: SPAWN_DEAD_LETTER_OP, reason: "leader_class_disabled" },
      }),
    );
  });
});

describe("safeToolName", () => {
  it("keeps an allowlist-shaped name and replaces anything else", async () => {
    const { safeToolName } = await load();
    expect(safeToolName("github_comment")).toBe("github_comment");
    expect(safeToolName("createPullRequestReviewComment")).toBe("createPullRequestReviewComment");
    expect(safeToolName("x y")).toBe("[invalid]");
    expect(safeToolName("a".repeat(65))).toBe("[invalid]");
    expect(safeToolName("bad name")).toBe("[invalid]");
    expect(safeToolName("")).toBe("[invalid]");
  });
});
