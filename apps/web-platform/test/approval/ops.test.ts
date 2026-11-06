/**
 * #4672 observability contract: every Sentry op has its own static message and carries the approval id tag; the
 * lifecycle markers are admitted by the Vector allowlist (read from the real config, not assumed); and the markers carry
 * no user content.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { beforeEach, describe, expect, test, vi } from "vitest";

const { log, mockWarn, mockReport } = vi.hoisted(() => ({
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockWarn: vi.fn(),
  mockReport: vi.fn(),
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => log, default: log }));
vi.mock("@/server/observability", () => ({ warnSilentFallback: mockWarn, reportSilentFallback: mockReport }));

import { APPROVAL_MARKERS, APPROVAL_OPS, logApprovalMarker, reportApprovalOp } from "@/server/approval/ops";
import { APPROVAL_ID } from "./fixtures";

beforeEach(() => vi.clearAllMocks());

describe("Sentry ops", () => {
  const defs = Object.values(APPROVAL_OPS);

  test("AC8: no two ops share a message string or an op name", () => {
    expect(new Set(defs.map((d) => d.message)).size).toBe(defs.length);
    expect(new Set(defs.map((d) => d.op)).size).toBe(defs.length);
  });

  test("every message is static prose: no interpolation placeholders, no tool input, non-trivial", () => {
    for (const d of defs) {
      expect(d.message.length, d.op).toBeGreaterThan(20);
      expect(d.message, d.op).not.toMatch(/[${}]|%s|undefined|\[object/);
    }
  });

  test("the plan's fault ops all exist", () => {
    const ops = defs.map((d) => d.op);
    for (const required of ["gate_unanswered", "approval-expired", "approval-consume-rejected", "approval-notify-failed", "approval-reproposed"]) {
      expect(ops).toContain(required);
    }
  });

  test("an op is reported with its own static message and the approval id as a tag, at its level", () => {
    reportApprovalOp("consumeRejected", null, { approvalId: APPROVAL_ID, toolName: "t", extra: { reason: "expired" } });
    expect(mockWarn).toHaveBeenCalledTimes(1);
    expect(mockWarn.mock.calls[0][1]).toMatchObject({
      feature: "approval-queue",
      op: "approval-consume-rejected",
      message: APPROVAL_OPS.consumeRejected.message,
      tags: { approval_id: APPROVAL_ID },
    });
    reportApprovalOp("createFailed", new Error("x"), { approvalId: APPROVAL_ID });
    expect(mockReport).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.calls[0][1]).toMatchObject({ op: "approval-create-failed", message: APPROVAL_OPS.createFailed.message });
  });

  test("reporting never throws, even when the Sentry mirror does", () => {
    mockWarn.mockImplementationOnce(() => {
      throw new Error("sentry down");
    });
    expect(() => reportApprovalOp("waitTimeout", null, { approvalId: APPROVAL_ID })).not.toThrow();
  });
});

describe("markers and the Vector allowlist", () => {
  const vector = readFileSync(join(__dirname, "../../infra/vector.toml"), "utf8");
  const block = (name: string) => {
    const start = vector.indexOf(`[transforms.${name}]`);
    expect(start, `${name} block present in infra/vector.toml`).toBeGreaterThan(-1);
    const next = vector.indexOf("\n[", start + 1);
    return vector.slice(start, next === -1 ? undefined : next);
  };

  test("the app-container source ships every pino line at level >= 40, so a marker logged at warn is admitted", () => {
    expect(block("app_container_warn_filter")).toMatch(/level_int >= 40/);
    logApprovalMarker("SOLEUR_APPROVAL_REQUESTED", { approval_id: APPROVAL_ID, tool: "t" });
    expect(log.warn).toHaveBeenCalledTimes(1);
    expect(log.info).not.toHaveBeenCalled(); // info (30) would be dropped at the source
  });

  test("no per-message allowlist exists in the pipeline that could reject the SOLEUR_APPROVAL_ family", () => {
    const filter = block("app_container_warn_filter");
    expect(filter).not.toMatch(/SOLEUR_[A-Z_]+/);
    expect(block("pii_scrub_drop_userdata")).not.toMatch(/SOLEUR_APPROVAL/);
  });

  test("marker field names never collide with the Art-9 user-content keys the pipeline drops", () => {
    const dropped = ["body", "content", "message", "userMessage", "prompt", "chat_message", "userInput", "user_input"];
    for (const k of dropped) expect(block("pii_scrub_drop_userdata")).toContain(`parsed_obj.${k}`);
    logApprovalMarker("SOLEUR_APPROVAL_CONSUMED", { approval_id: APPROVAL_ID, tool: "t", conversation_id: "c", path: "live" });
    const fields = Object.keys(log.warn.mock.calls[0][0] as object);
    for (const k of fields) expect(dropped).not.toContain(k);
  });

  test("the marker line is `<MARKER> key=value ...` so one grep rebuilds the lifecycle", () => {
    logApprovalMarker("SOLEUR_APPROVAL_DECIDED", { approval_id: APPROVAL_ID, decision: "approve", skipped: undefined });
    expect(log.warn.mock.calls[0][1]).toBe(`SOLEUR_APPROVAL_DECIDED approval_id=${APPROVAL_ID} decision=approve`);
    expect([...APPROVAL_MARKERS]).toEqual([
      "SOLEUR_APPROVAL_REQUESTED",
      "SOLEUR_APPROVAL_DECIDED",
      "SOLEUR_APPROVAL_CONSUMED",
      "SOLEUR_APPROVAL_EXPIRED",
      "SOLEUR_APPROVAL_SWEEP",
    ]);
  });
});
