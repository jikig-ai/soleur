import { describe, test, expect } from "vitest";
import { reasonToMessage } from "@/app/(public)/invite/[token]/invite-reason-messages";

const GENERIC = "Something went wrong. Please try again.";

describe("reasonToMessage", () => {
  test("revoked maps to a distinguishable, non-generic message", () => {
    const msg = reasonToMessage("revoked");
    expect(msg).not.toBe(GENERIC);
    expect(msg.toLowerCase()).toContain("cancelled");
  });

  test("rpc_failed and unknown map to a transient-flavored message (retry is meaningful)", () => {
    // Tighter than /try again/ — the generic default also contains "try again",
    // so the assertion must key on the transient-specific phrasing.
    for (const code of ["rpc_failed", "unknown"]) {
      const msg = reasonToMessage(code);
      expect(msg).not.toBe(GENERIC);
      expect(msg.toLowerCase()).toMatch(/our end|in a moment/);
    }
  });

  test("unauthorized / caller_not_authenticated → session-expired copy", () => {
    expect(reasonToMessage("unauthorized").toLowerCase()).toContain("session");
    expect(reasonToMessage("caller_not_authenticated").toLowerCase()).toContain("session");
  });

  test("existing terminal states keep their friendly copy", () => {
    expect(reasonToMessage("expired")).toContain("expired");
    expect(reasonToMessage("already_accepted")).toContain("already joined");
    expect(reasonToMessage("already_member")).toContain("already joined");
    expect(reasonToMessage("already_declined")).toContain("declined");
    expect(reasonToMessage("invitation_not_found")).toContain("no longer available");
    expect(reasonToMessage("not_intended_invitee")).toContain("addressed to your account");
  });

  test("empty/undefined reason yields empty string (no error box)", () => {
    expect(reasonToMessage(undefined)).toBe("");
    expect(reasonToMessage("")).toBe("");
  });

  // Negative-space: no code the accept/decline route + RPC can emit should
  // silently hit the generic default UNLESS it is a true client bug
  // (invalid_body/invalid_json). The two regression codes (revoked, rpc_failed)
  // that caused the "Something went wrong" report MUST be mapped away from it.
  test("no route/RPC-emitted state code falls through to the generic default", () => {
    const emitted = [
      "invitation_not_found",
      "already_accepted",
      "already_declined",
      "revoked",
      "expired",
      "already_member",
      "not_intended_invitee",
      "rpc_failed",
      "unknown",
      "caller_not_authenticated",
      "unauthorized",
    ];
    for (const code of emitted) {
      expect(reasonToMessage(code)).not.toBe(GENERIC);
    }
  });
});
