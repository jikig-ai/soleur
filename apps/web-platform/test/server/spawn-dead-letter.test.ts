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

// Synthesized fixture ids (cq-test-fixtures-synthesized-only).
const FOUNDER_ID = "0f4c1d2e-3a5b-4c6d-8e9f-a0b1c2d3e4f5";
const CLASS = "engineering.pr_review_pending";

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
  it("sends exactly one tagged error-level message event and no exception event", async () => {
    const { reportSpawnDeadLetter, SPAWN_DEAD_LETTER_FEATURE, SPAWN_DEAD_LETTER_OP } = await load();
    const err = new Error("tool addLabels not in allowlist for engineering.pr_review_pending");

    reportSpawnDeadLetter({
      reason: "leader_tool_invalid",
      actionClass: CLASS,
      err,
      extra: { founderId: FOUNDER_ID, turn: 1 },
    });

    expect(captureExceptionSpy).not.toHaveBeenCalled();
    const [message, ctx] = onlyMessage();
    // Reason AND class in the grouping text: one Sentry issue per (reason, class).
    expect(message).toBe(`agent-on-spawn deadlettered: leader_tool_invalid [${CLASS}]`);
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
    expect(ctx.extra.actionClass).toBe(CLASS);
    expect(ctx.extra.reason).toBe("leader_tool_invalid");
  });

  it("a non-paged reason is a warning-level event with the same tags", async () => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({ reason: "anthropic_rate_limited", actionClass: CLASS, err: new Error("429"), extra: {} });

    expect(captureExceptionSpy).not.toHaveBeenCalled();
    const [message, ctx] = onlyMessage();
    expect(message).toBe(`agent-on-spawn deadlettered: anthropic_rate_limited [${CLASS}]`);
    expect(ctx.level).toBe("warning");
    expect(ctx.tags.reason).toBe("anthropic_rate_limited");
  });

  it("the pino hook ran (positive control) and did not capture the dead-letter itself", async () => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({ reason: "leader_refused", actionClass: CLASS, err: new Error("declined"), extra: {} });

    expect(addBreadcrumbSpy).toHaveBeenCalledWith(
      expect.objectContaining({
        category: "pino",
        message: `agent-on-spawn deadlettered: leader_refused [${CLASS}]`,
      }),
    );
    expect(captureExceptionSpy).not.toHaveBeenCalled();
  });

  it("pseudonymizes the founder id: userIdHash present, raw id nowhere in the event", async () => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({
      reason: "anthropic_request_rejected",
      actionClass: CLASS,
      err: new Error("400 x"),
      extra: { founderId: FOUNDER_ID },
    });

    const [, ctx] = onlyMessage();
    expect(typeof ctx.extra.userIdHash).toBe("string");
    expect(ctx.extra.founderId).toBeUndefined();
    expect(JSON.stringify([captureMessageSpy.mock.calls, addBreadcrumbSpy.mock.calls])).not.toContain(
      FOUNDER_ID,
    );
  });

  it("never spreads the SDK error: headers and the structured vendor body reach no sink", async () => {
    const { reportSpawnDeadLetter } = await load();
    const sdkErr = Object.assign(new Error("400 bad request"), {
      status: 400,
      headers: { "request-id": "req_synthetic_8719" },
      error: { type: "error", error: { type: "invalid_request_error_8719" } },
    });
    reportSpawnDeadLetter({ reason: "anthropic_request_rejected", actionClass: CLASS, err: sdkErr, extra: {} });

    const [, ctx] = onlyMessage();
    expect(Object.keys(ctx.extra.err ?? {}).sort()).toEqual(["message", "name", "stack"]);
    // Every sink the event touches, not one key.
    const everything = JSON.stringify([captureMessageSpy.mock.calls, addBreadcrumbSpy.mock.calls]);
    expect(everything).not.toContain("req_synthetic_8719");
    expect(everything).not.toContain("invalid_request_error_8719");
  });

  it("a direct PostgREST-shaped error keeps its SQLSTATE as the pg_code tag", async () => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({
      reason: "acknowledgment_persist_failed",
      actionClass: CLASS,
      err: { code: "42501", message: "permission denied for table action_sends", details: "row x" },
      extra: {},
    });

    const [, ctx] = onlyMessage();
    expect(ctx.tags.pg_code).toBe("42501");
    expect(ctx.extra.err?.message).toBe("permission denied for table action_sends");
    expect(ctx.extra.err?.details).toBeUndefined();
  });

  it.each<[string, unknown, { name: string; message: string }]>([
    ["a string", "plain string failure", { name: "Error", message: "plain string failure" }],
    ["null", null, { name: "Error", message: "null" }],
    ["undefined", undefined, { name: "Error", message: "undefined" }],
    ["a number", 413, { name: "Error", message: "413" }],
    ["a prototype-less object", Object.create(null), { name: "Error", message: "" }],
    [
      "a StepError-shaped object",
      { name: "Error", message: "step failed", stack: "Error: step failed\n    at x", cause: "fetch_failed" },
      { name: "Error", message: "step failed" },
    ],
    ["a PostgREST-shaped object", { code: "PGRST116", message: "no rows", details: "0 rows" }, { name: "Error", message: "no rows" }],
    [
      "an Error subclass with status",
      Object.assign(new TypeError("413 too large"), { status: 413 }),
      { name: "TypeError", message: "413 too large" },
    ],
  ])("%s yields one tagged message event carrying its own name and message", async (_label, err, want) => {
    const { reportSpawnDeadLetter } = await load();
    reportSpawnDeadLetter({ reason: "leader_response_truncated", actionClass: CLASS, err, extra: {} });

    expect(captureExceptionSpy).not.toHaveBeenCalled();
    const [message, ctx] = onlyMessage();
    expect(message).toBe(`agent-on-spawn deadlettered: leader_response_truncated [${CLASS}]`);
    expect(ctx.tags.reason).toBe("leader_response_truncated");
    expect(ctx.extra.err).not.toBeInstanceOf(Error);
    expect(ctx.extra.err).toMatchObject(want);
  });
});

describe("reportSpawnDeadLetter — a failure inside the report never escapes", () => {
  it("a throwing reporter: swallowed, cause sent to pino, one tagged 'report failed' message", async () => {
    vi.doMock("@/server/observability", () => ({
      reportSilentFallback: () => {
        throw new Error("synthetic reporter failure");
      },
      warnSilentFallback: () => {
        throw new Error("synthetic reporter failure");
      },
    }));
    const { reportSpawnDeadLetter, SPAWN_DEAD_LETTER_FEATURE, SPAWN_DEAD_LETTER_OP } = await load();

    expect(() =>
      reportSpawnDeadLetter({ reason: "leader_class_disabled", actionClass: CLASS, err: new Error("disabled"), extra: {} }),
    ).not.toThrow();

    expect(captureMessageSpy).toHaveBeenCalledTimes(1);
    expect(captureMessageSpy).toHaveBeenCalledWith(
      `agent-on-spawn deadlettered: report failed: leader_class_disabled [${CLASS}]`,
      expect.objectContaining({
        level: "error",
        tags: { feature: SPAWN_DEAD_LETTER_FEATURE, op: SPAWN_DEAD_LETTER_OP, reason: "leader_class_disabled" },
      }),
    );
    // The cause reaches Sentry through the pino mirror (fail_loud in the plan).
    expect(captureExceptionSpy).toHaveBeenCalledWith(
      expect.objectContaining({ message: "synthetic reporter failure" }),
      expect.objectContaining({ tags: { feature: "pino-mirror" } }),
    );
  });

  it("an err whose getter throws: swallowed, and the tagged 'report failed' message still goes out", async () => {
    const { reportSpawnDeadLetter } = await load();
    const hostile = {
      get message(): string {
        throw new Error("hostile getter");
      },
    };

    expect(() =>
      reportSpawnDeadLetter({ reason: "anthropic_request_rejected", actionClass: CLASS, err: hostile, extra: {} }),
    ).not.toThrow();
    expect(captureMessageSpy).toHaveBeenCalledWith(
      `agent-on-spawn deadlettered: report failed: anthropic_request_rejected [${CLASS}]`,
      expect.objectContaining({ tags: expect.objectContaining({ reason: "anthropic_request_rejected" }) }),
    );
  });
});

describe("reportSpawnPersistFailed", () => {
  it("reports the failed terminal write on the message path with a hashed founder id", async () => {
    const { reportSpawnPersistFailed, SPAWN_DEAD_LETTER_FEATURE } = await load();
    reportSpawnPersistFailed({
      reason: "leader_refused",
      actionSendId: "11111111-1111-1111-1111-111111111111",
      founderId: FOUNDER_ID,
      err: { code: "57014", message: "canceling statement due to statement timeout" },
    });

    expect(captureExceptionSpy).not.toHaveBeenCalled();
    const [message, ctx] = onlyMessage();
    expect(message).toBe("agent-on-spawn: persist-failure UPDATE failed; terminal state not recorded");
    expect(ctx.tags).toMatchObject({ feature: SPAWN_DEAD_LETTER_FEATURE, op: "persist-failure", reason: "leader_refused", pg_code: "57014" });
    expect(ctx.extra.actionSendId).toBe("11111111-1111-1111-1111-111111111111");
    expect(typeof ctx.extra.userIdHash).toBe("string");
    expect(JSON.stringify(captureMessageSpy.mock.calls)).not.toContain(FOUNDER_ID);
  });
});
