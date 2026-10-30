/**
 * #4672: the client-safe wire vocabularies (lib/approval-wire.ts) must equal the server's. This test imports the
 * server modules (client code must not) and derives the expected sets from `APPROVAL_STATUSES` (service.ts) and
 * `DECIDE_OUTCOMES` (decide.ts); the zod schemas must accept exactly those values and nothing else.
 */
import { describe, expect, test } from "vitest";
import { APPROVAL_WIRE_DECIDE_OUTCOMES, APPROVAL_WIRE_STATUSES, isApprovalDecideOutcomeWire, isApprovalWireStatus } from "@/lib/approval-wire";
import { APPROVAL_STATUSES } from "@/server/approval/service";
import { DECIDE_OUTCOMES } from "@/server/approval/decide";
import { parseWSMessage } from "@/lib/ws-zod-schemas";
import { canonicalizeAction } from "@/server/approval/canonical";
import { renderApprovalView } from "@/server/approval/render";
import { SAMPLES } from "./fixtures";

const ID = "00000000-0000-4000-8000-000000000006";
const sorted = (a: readonly string[]) => [...a].sort();

describe("approval wire vocabularies equal the server's", () => {
  test("statuses", () => {
    expect(sorted(APPROVAL_WIRE_STATUSES)).toEqual(sorted(APPROVAL_STATUSES));
  });

  test("decide outcomes (7 values, including revoked and already_decided)", () => {
    expect(sorted(APPROVAL_WIRE_DECIDE_OUTCOMES)).toEqual(sorted(DECIDE_OUTCOMES));
    expect(APPROVAL_WIRE_DECIDE_OUTCOMES).toContain("revoked");
    expect(APPROVAL_WIRE_DECIDE_OUTCOMES).toContain("already_decided");
  });

  test("the guards accept exactly the tuples", () => {
    for (const v of APPROVAL_WIRE_STATUSES) expect(isApprovalWireStatus(v)).toBe(true);
    for (const v of APPROVAL_WIRE_DECIDE_OUTCOMES) expect(isApprovalDecideOutcomeWire(v)).toBe(true);
    for (const v of ["nope", "", null, undefined, 1, "Decided"]) {
      expect(isApprovalWireStatus(v)).toBe(false);
      expect(isApprovalDecideOutcomeWire(v)).toBe(false);
    }
  });

  test("the approval_status zod schema accepts every server status and outcome and rejects others", () => {
    const frame = (status: string, outcome?: string) => ({ type: "approval_status", approvalId: ID, conversationId: "c", status, ...(outcome ? { outcome } : {}) });
    for (const st of APPROVAL_STATUSES) expect(parseWSMessage(frame(st)).ok, st).toBe(true);
    for (const o of DECIDE_OUTCOMES) expect(parseWSMessage(frame("rejected", o)).ok, o).toBe(true);
    expect(parseWSMessage(frame("maybe")).ok).toBe(false);
    expect(parseWSMessage(frame("rejected", "deleted")).ok).toBe(false);
  });
});

describe("the card view carries its own noun", () => {
  test("for every gated tool the view's noun is a non-empty single line (the single-use line may name only what is bound)", () => {
    for (const tool of Object.keys(SAMPLES)) {
      const v = renderApprovalView(canonicalizeAction(tool, SAMPLES[tool].input, SAMPLES[tool].server));
      expect(v.noun.length, tool).toBeGreaterThan(0);
      expect(v.noun, tool).not.toMatch(/[\r\n]/);
      expect(v.singleUse.length, tool).toBeGreaterThan(0);
    }
  });
});
