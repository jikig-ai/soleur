// #11599 — the unresolved-authentication-mode refusal: cause classification, the lease->WS code equivalence, the
// "already reported by the lease" predicate (Guard 2), the typed frames and their copy, the logger, and the zod contract.
import { describe, expect, it, vi } from "vitest";

import { ByokLeaseError, mapByokLeaseCauseToErrorCode } from "@/server/byok-lease";
import {
  AUTH_MODE_ERROR_REASONS,
  TRANSIENT_AUTH_MODE_REASONS,
  classifyAuthModeReason,
} from "@/server/auth-mode-error";
import {
  authFailureFrameFromLeaseError,
  authModeUnresolvedFrame,
  isLeaseRefusalReported,
  logSessionFailure,
} from "@/server/agent-auth-user-message";
import { wsMessageSchema } from "@/lib/ws-zod-schemas";

const DETERMINISTIC_COPY =
  "We couldn't confirm which authentication mode this conversation uses, so your message was not processed. Start a new conversation to continue.";
const TRANSIENT_COPY =
  "We couldn't check which authentication mode this conversation uses just now, so your message was not processed. Please send it again in a moment.";

// A name-and-cause look-alike, as the existing oauth_unusable tests use: the predicate must never key on `instanceof`.
const lookAlike = (cause: string) => Object.assign(new Error("x"), { name: "ByokLeaseError", cause });

describe("classifyAuthModeReason", () => {
  it.each([
    ["unbound", "auth_mode_unresolved"],
    ["invalid_value", "auth_mode_unresolved"],
    ["no_resolver", "auth_mode_unresolved"],
    ["workspace_mismatch", "auth_mode_unresolved"],
    ["read_failed", "auth_mode_unavailable"],
    ["resolver_failed", "auth_mode_unavailable"],
    // Fail-safe: a reason added later is deterministic (not auto-retried) until someone decides otherwise.
    ["some_future_reason", "auth_mode_unresolved"],
  ])("%s -> %s", (reason, cause) => {
    expect(classifyAuthModeReason(reason)).toBe(cause);
  });

  it("the transient set is exactly read_failed and resolver_failed; every resolver-thrown reason is classified", () => {
    expect([...TRANSIENT_AUTH_MODE_REASONS].sort()).toEqual(["read_failed", "resolver_failed"]);
    for (const r of AUTH_MODE_ERROR_REASONS) expect(["auth_mode_unresolved", "auth_mode_unavailable"]).toContain(classifyAuthModeReason(r));
  });
});

describe("mapper / frame equivalence", () => {
  it.each(["auth_mode_unresolved", "auth_mode_unavailable"] as const)("the frame's code for %s equals the mapper's", (cause) => {
    const frame = authModeUnresolvedFrame(cause);
    expect(frame.errorCode).toBe(mapByokLeaseCauseToErrorCode(cause));
    expect(frame.errorCode).toBe(cause);
  });
});

describe("isLeaseRefusalReported (Guard 2)", () => {
  it.each(["oauth_unusable", "auth_mode_unresolved", "auth_mode_unavailable"])("%s is reported by the lease (look-alike and real instance)", (cause) => {
    expect(isLeaseRefusalReported(lookAlike(cause))).toBe(true);
    expect(isLeaseRefusalReported(new ByokLeaseError(cause as ByokLeaseError["cause"], "m"))).toBe(true);
  });

  it.each(["fetch_failed", "escape", "decrypt_failed", "subscription_limit"])("%s is NOT reported by the lease: it is still mirrored", (cause) => {
    expect(isLeaseRefusalReported(lookAlike(cause))).toBe(false);
    expect(isLeaseRefusalReported(new ByokLeaseError(cause as ByokLeaseError["cause"], "m"))).toBe(false);
  });

  it("is false for non-lease errors and non-errors", () => {
    expect(isLeaseRefusalReported(new Error("x"))).toBe(false);
    expect(isLeaseRefusalReported(Object.assign(new Error("x"), { cause: "auth_mode_unresolved" }))).toBe(false);
    expect(isLeaseRefusalReported(null)).toBe(false);
    expect(isLeaseRefusalReported({ name: "ByokLeaseError", cause: "auth_mode_unresolved" })).toBe(false);
    expect(isLeaseRefusalReported("auth_mode_unresolved")).toBe(false);
  });
});

describe("authModeUnresolvedFrame / authFailureFrameFromLeaseError", () => {
  it("builds the exact deterministic and transient frames, with plain text only", () => {
    expect(authModeUnresolvedFrame("auth_mode_unresolved")).toEqual({
      type: "error",
      message: DETERMINISTIC_COPY,
      errorCode: "auth_mode_unresolved",
    });
    expect(authModeUnresolvedFrame("auth_mode_unavailable")).toEqual({
      type: "error",
      message: TRANSIENT_COPY,
      errorCode: "auth_mode_unavailable",
    });
    for (const c of ["auth_mode_unresolved", "auth_mode_unavailable"] as const) {
      expect(authModeUnresolvedFrame(c).message).not.toMatch(/`|·|API key|subscription|invalid/i);
    }
  });

  it.each(["auth_mode_unresolved", "auth_mode_unavailable"] as const)("a %s lease error yields the typed frame", (cause) => {
    expect(authFailureFrameFromLeaseError(lookAlike(cause))).toEqual(authModeUnresolvedFrame(cause));
  });

  it("oauth_unusable keeps its recovery frame; a real fetch_failed and other errors yield null", () => {
    expect(authFailureFrameFromLeaseError(lookAlike("oauth_unusable"))).toMatchObject({ errorCode: "key_invalid", credentialScheme: "oauth_token" });
    expect(authFailureFrameFromLeaseError(lookAlike("fetch_failed"))).toBeNull();
    expect(authFailureFrameFromLeaseError(lookAlike("escape"))).toBeNull();
    expect(authFailureFrameFromLeaseError(new Error("x"))).toBeNull();
  });
});

describe("logSessionFailure for the new causes", () => {
  const mk = () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() });
  const messages = { refused: "refused", failed: "Session error" };

  // WARN, not INFO: INFO never leaves the host (the log shipper forwards WARN and above), and this line is the only one
  // tying the refusal to a conversation. Never ERROR: that would reach the error tracker a second time.
  it.each(["auth_mode_unresolved", "auth_mode_unavailable"])("%s logs at WARN with the context, never at ERROR or INFO", (cause) => {
    const log = mk();
    logSessionFailure(log, lookAlike(cause), { conversationId: "c" }, messages);
    expect(log.error).not.toHaveBeenCalled();
    expect(log.info).not.toHaveBeenCalled();
    expect(log.warn).toHaveBeenCalledTimes(1);
    expect(log.warn.mock.calls[0][0]).toEqual({ conversationId: "c" });
    // The refusal message is derived from the call site's own `failed` string.
    expect(log.warn.mock.calls[0][1]).toContain("Session error");
  });

  it("oauth_unusable keeps the call site's own refused message; fetch_failed stays an ERROR", () => {
    const a = mk();
    logSessionFailure(a, lookAlike("oauth_unusable"), {}, messages);
    expect(a.info).toHaveBeenCalledWith({}, "refused");
    expect(a.warn).not.toHaveBeenCalled();
    const b = mk();
    const err = lookAlike("fetch_failed");
    logSessionFailure(b, err, {}, messages);
    expect(b.error).toHaveBeenCalledWith({ err }, "Session error");
    expect(b.info).not.toHaveBeenCalled();
    expect(b.warn).not.toHaveBeenCalled();
  });
});

describe("the WS error contract", () => {
  const parse = (errorCode: string) =>
    wsMessageSchema.safeParse({ type: "error", message: "m", errorCode }).success;

  it("the zod schema accepts both new codes and still rejects an unknown one", () => {
    expect(parse("auth_mode_unresolved")).toBe(true);
    expect(parse("auth_mode_unavailable")).toBe(true);
    expect(parse("auth_mode_unknown")).toBe(false);
  });
});
