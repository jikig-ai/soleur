// Prerequisite for the live-verify report-only→blocking deploy-gate flip — unit
// coverage for the two pure helpers that let the harness distinguish a
// SERVER-SIDE SEND REJECTION (rate limit / no active session — environmental,
// CANT-RUN) from a genuine rail regression (FAIL). Without this split a
// rate-limited run false-FAILs; once the gate blocks on FAIL that would block a
// legitimate deploy. Root cause debugged 2026-06-18 via a WS-frame trace of the
// harness against prd (start_session → {errorCode:"rate_limited"} → chat →
// "No active session. Send start_session first." → no conversation persists).
//
// All fixtures are synthesized — never a real token (cq-test-fixtures-synthesized-only).

import { describe, expect, it } from "vitest";

import { classifyDriveResult, parseWsErrorFrame } from "../../scripts/live-verify/run";

describe("parseWsErrorFrame", () => {
  // AC5 — returns ONLY {errorCode,message}; never the raw payload (which can
  // carry a token on adjacent frames — I-ephemerality).
  it("extracts only {errorCode,message} from a type:error frame", () => {
    const frame = parseWsErrorFrame(
      JSON.stringify({
        type: "error",
        errorCode: "rate_limited",
        message: "Rate limited: too many conversations this hour.",
        token: "synthetic-secret-must-not-survive",
      }),
    );
    expect(frame).toEqual({
      errorCode: "rate_limited",
      message: "Rate limited: too many conversations this hour.",
    });
    expect(frame).not.toHaveProperty("token");
    expect(frame).not.toHaveProperty("type");
  });

  it("returns null for non-error frames (auth_ok / chat / acks)", () => {
    expect(parseWsErrorFrame(JSON.stringify({ type: "auth_ok" }))).toBeNull();
    expect(parseWsErrorFrame(JSON.stringify({ type: "chat", content: "hi" }))).toBeNull();
  });

  it("returns null for non-JSON / non-object payloads (Phoenix realtime arrays, bare strings)", () => {
    expect(parseWsErrorFrame("not json at all")).toBeNull();
    expect(
      parseWsErrorFrame(JSON.stringify(["1", "1", "realtime:command-center-own", "phx_reply", {}])),
    ).toBeNull();
    expect(parseWsErrorFrame(JSON.stringify("error"))).toBeNull();
  });
});

describe("classifyDriveResult", () => {
  // AC1
  it("maps a rate_limited error → CANT-RUN:rate-limited", () => {
    const d = classifyDriveResult({
      convId: null,
      wsError: {
        errorCode: "rate_limited",
        message: "Rate limited: too many conversations this hour.",
      },
    });
    expect(d).toEqual({ kind: "CANT-RUN", reason: "rate-limited" });
  });

  // AC2 — the real server text "No active session. Send start_session first."
  it("maps a 'Send start_session first' error → CANT-RUN:session-rejected", () => {
    const d = classifyDriveResult({
      convId: null,
      wsError: { message: "No active session. Send start_session first." },
    });
    expect(d).toEqual({ kind: "CANT-RUN", reason: "session-rejected" });
  });

  // AC2b (negative, P1) — a bare "No active session" (established-session drop,
  // ws-handler 2094/2441/2509) is a genuine FAIL class, NOT session-rejected.
  it("does NOT map a bare 'No active session' (no start_session hint) to session-rejected", () => {
    const d = classifyDriveResult({ convId: null, wsError: { message: "No active session" } });
    expect(d.kind).toBe("FAIL");
  });

  // AC3 — genuine FAIL: no WS error AND no persisted row.
  it("returns FAIL when no row persisted and no WS error was seen", () => {
    const d = classifyDriveResult({ convId: null, wsError: null });
    expect(d.kind).toBe("FAIL");
  });

  // AC4 — a captured rate_limited error wins even if a row id is present.
  it("rate_limited wins over a present convId", () => {
    const d = classifyDriveResult({ convId: "abc", wsError: { errorCode: "rate_limited" } });
    expect(d).toEqual({ kind: "CANT-RUN", reason: "rate-limited" });
  });

  // PROCEED seam — row persisted, no rejection → caller runs the rail assertion.
  it("returns PROCEED with the convId when a row persisted and no rejection error", () => {
    const convId = "11111111-1111-1111-1111-111111111111";
    const d = classifyDriveResult({ convId, wsError: null });
    expect(d).toEqual({ kind: "PROCEED", convId });
  });
});
