/**
 * #4672 observability (ADR-309): an approval op reaches the REAL Sentry sink with its `feature`/`op` tags and a
 * static message, and the thrown value contributes only `{code, fn, errName}`.
 *
 * Unlike ops.test.ts this does not mock the observability module: it runs the real `reportSilentFallback` /
 * `warnSilentFallback` against a spied Sentry and a spied pino logger. That is the only way to prove the regression the
 * ruling is about: handing the helper an Error lets the pino mirror capture it first, without the tags.
 */
import { beforeEach, describe, expect, test, vi } from "vitest";

const h = vi.hoisted(() => ({
  captureException: vi.fn(),
  captureMessage: vi.fn(),
  loggerError: vi.fn(),
  loggerWarn: vi.fn(),
}));
vi.mock("@sentry/nextjs", () => ({ captureException: h.captureException, captureMessage: h.captureMessage }));
vi.mock("@/server/logger", () => {
  const log = { info: vi.fn(), warn: h.loggerWarn, error: h.loggerError, debug: vi.fn() };
  return { default: log, createChildLogger: () => log };
});

import { APPROVAL_OPS, reportApprovalOp, type ApprovalOpKey } from "@/server/approval/ops";
import { ApprovalServiceError } from "@/server/approval/service";
import { ApprovalCanonicalError } from "@/server/approval/canonical";
import { APPROVAL_ID, WORKSPACE_ID } from "./fixtures";

beforeEach(() => vi.clearAllMocks());

const keys = Object.keys(APPROVAL_OPS) as ApprovalOpKey[];
const errorKeys = keys.filter((k) => APPROVAL_OPS[k].level === "error");
const warnKeys = keys.filter((k) => APPROVAL_OPS[k].level === "warn");

describe("every error-level op reaches Sentry tagged, as a message, never an Error object", () => {
  test("there are error-level ops to cover", () => {
    expect(errorKeys.length).toBeGreaterThanOrEqual(6);
  });

  test.each(errorKeys)("%s: captureMessage with feature/op tags, the static message, error level and the approval id", (key) => {
    reportApprovalOp(key, new ApprovalServiceError("create_approval_request", "XX000"), { approvalId: APPROVAL_ID, workspaceId: WORKSPACE_ID });
    // The Error never reaches the helper, so there is no captureException (which would carry no feature/op tags via pino).
    expect(h.captureException).not.toHaveBeenCalled();
    expect(h.captureMessage).toHaveBeenCalledTimes(1);
    const [message, ctx] = h.captureMessage.mock.calls[0] as [string, { level: string; tags: Record<string, string>; extra: Record<string, unknown> }];
    expect(message).toBe(APPROVAL_OPS[key].message);
    expect(ctx.level).toBe("error");
    expect(ctx.tags).toMatchObject({ feature: "approval-queue", op: APPROVAL_OPS[key].op, approval_id: APPROVAL_ID });
    expect(ctx.extra).toMatchObject({ code: "XX000", fn: "create_approval_request", errName: "ApprovalServiceError", workspaceId: WORKSPACE_ID });
  });

  test.each(errorKeys)("%s: the pino mirror line carries feature/op and no err object (nothing for the pino integration to capture)", (key) => {
    reportApprovalOp(key, new Error("db text that must never surface"), { approvalId: APPROVAL_ID });
    expect(h.loggerError).toHaveBeenCalledTimes(1);
    const [fields, msg] = h.loggerError.mock.calls[0] as [Record<string, unknown>, string];
    expect(fields).toMatchObject({ feature: "approval-queue", op: APPROVAL_OPS[key].op });
    expect(fields.err).toBeNull();
    expect(JSON.stringify([fields, msg])).not.toContain("db text that must never surface");
  });

  test("a plain Error contributes its class name only; a canonical error contributes its code", () => {
    reportApprovalOp("gateFailed", new TypeError("secret"), {});
    expect((h.captureMessage.mock.calls[0][1] as { extra: Record<string, unknown> }).extra).toMatchObject({ errName: "TypeError" });
    expect(JSON.stringify(h.captureMessage.mock.calls[0])).not.toContain("secret");
    h.captureMessage.mockClear();
    reportApprovalOp("gateFailed", new ApprovalCanonicalError("key_unavailable"), {});
    expect((h.captureMessage.mock.calls[0][1] as { extra: Record<string, unknown> }).extra).toMatchObject({ code: "key_unavailable", errName: "ApprovalCanonicalError" });
  });

  test("no error: the static message alone is the event, with the tags", () => {
    reportApprovalOp("gateFailed", null, { approvalId: APPROVAL_ID });
    const [message, ctx] = h.captureMessage.mock.calls[0] as [string, { tags: Record<string, string> }];
    expect(message).toBe(APPROVAL_OPS.gateFailed.message);
    expect(ctx.tags).toMatchObject({ feature: "approval-queue", op: "approval-gate-failed" });
  });
});

describe("every warn-level op reaches Sentry tagged at warning level", () => {
  test.each(warnKeys)("%s", (key) => {
    reportApprovalOp(key, new ApprovalServiceError("get_approval_status", "XX000"), { approvalId: APPROVAL_ID });
    expect(h.captureException).not.toHaveBeenCalled();
    const [message, ctx] = h.captureMessage.mock.calls[0] as [string, { level: string; tags: Record<string, string> }];
    expect(message).toBe(APPROVAL_OPS[key].message);
    expect(ctx.level).toBe("warning");
    expect(ctx.tags).toMatchObject({ feature: "approval-queue", op: APPROVAL_OPS[key].op });
    expect(h.loggerWarn).toHaveBeenCalledTimes(1);
  });
});

describe("a cap hit and the other new silent-path ops are registered once with their own message", () => {
  test.each(["capReached", "invalidInput", "consumedAborted", "waitReadFailed", "viewerRoleFailed"] as const)("%s", (key) => {
    expect(APPROVAL_OPS[key].level).toBe("warn");
    expect(keys.filter((k) => APPROVAL_OPS[k].op === APPROVAL_OPS[key].op)).toHaveLength(1);
  });
});
