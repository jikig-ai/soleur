// #11086: the closed copy table and the rewrite helper. The helper must be total over (kind x scheme), never mutate the SDK
// message, rewrite only a single-text-block message, and never surface raw CLI text or subscription wording to a tenant.
import { describe, expect, it, vi } from "vitest";

import {
  authFailureCopy,
  buildAuthFailureFrame,
  logSessionFailure,
  rewriteAgentAuthFailure,
  type AuthFailureKind,
} from "@/server/agent-auth-user-message";

const KINDS: AuthFailureKind[] = [
  "not_logged_in",
  "invalid_api_key",
  "oauth_token_revoked",
  "session_expired",
  "structured",
  "oauth_unusable",
];

const CLI_TEXT = "Not logged in · Please run /login";

function deepFreeze<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const v of Object.values(value as Record<string, unknown>)) deepFreeze(v);
  }
  return value;
}

function cliMessage(text: string, extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    type: "assistant",
    error: "authentication_failed",
    is_api_error_message: true,
    message: { model: "<synthetic>", content: [{ type: "text", text }] },
    ...extra,
  };
}

describe("copy table", () => {
  it("never names a subscription token to a tenant (api_key scheme) or to an unknown scheme", () => {
    for (const kind of KINDS) {
      expect(authFailureCopy(kind, "api_key")).not.toMatch(/subscription|setup-token|oauth|claude max|claude pro|plan|claude\.ai/i);
      // An unknown scheme (null, undefined, an unrecognised string) gets the neutral cell: no tenant sees operator wording.
      for (const unknown of [null, undefined, "weird"]) {
        expect(authFailureCopy(kind, unknown as never)).not.toMatch(/subscription|setup-token|oauth|claude max|claude pro|plan|claude\.ai|API key/i);
      }
      // Every cell is non-empty plain text with no CLI residue (a deny-regex alone is satisfied by an empty string).
      for (const scheme of ["api_key", "oauth_token", null, undefined, "weird"]) {
        const text = authFailureCopy(kind, scheme as never);
        expect(text.length, `${kind} x ${String(scheme)}`).toBeGreaterThan(20);
        expect(text).not.toMatch(/`|\u00B7|\/login/);
      }
    }
  });

  it("names the recovery in words for the operator scheme", () => {
    for (const kind of KINDS) {
      if (kind === "session_expired") continue;
      expect(authFailureCopy(kind, "oauth_token")).toMatch(/claude setup-token/);
    }
    expect(authFailureCopy("oauth_unusable", "oauth_token")).toContain("Nothing was billed to your API key.");
  });
});

// #11599 — the operator-only sign-in copy gains ONE recovery sentence. The quoted label matches the Settings control
// (`authModeLabel` in components/settings/agent-engine-settings.tsx); the lead-in covers an owner with no key saved.
const RECOVERY =
  'If you have an Anthropic API key saved, you can instead choose "My API key" in Settings, then start a new conversation (a conversation keeps the mode it started with).';

// The pre-#11599 oauth_token cells, verbatim: the sentence is APPENDED, nothing before it changes.
const OLD_OAUTH_TOKEN: Partial<Record<AuthFailureKind, string>> = {
  not_logged_in:
    "We couldn't sign in to Claude with your saved subscription token, so nothing ran. Generate a new token with claude setup-token, save it in Settings, then try again.",
  invalid_api_key:
    "Anthropic rejected your saved credential. Generate a new token with claude setup-token and save it in Settings.",
  oauth_token_revoked:
    "Your subscription token has been revoked or has expired. Generate a new one with claude setup-token and save it in Settings.",
  structured:
    "Claude couldn't authenticate your request. Save a fresh token from claude setup-token in Settings and try again.",
  oauth_unusable:
    "We couldn't sign in to Claude with your saved subscription token, so nothing ran. Generate a new token with claude setup-token, save it in Settings, then try again. Nothing was billed to your API key.",
};

describe("recovery sentence (#11599)", () => {
  it.each(Object.keys(OLD_OAUTH_TOKEN) as AuthFailureKind[])("%s: the operator cell is the old text plus the single recovery sentence", (kind) => {
    expect(authFailureCopy(kind, "oauth_token")).toBe(`${OLD_OAUTH_TOKEN[kind]} ${RECOVERY}`);
  });

  it("session_expired (a bubble-only 'start a new message' cell) does not get it", () => {
    expect(authFailureCopy("session_expired", "oauth_token")).not.toContain("My API key");
  });

  it("no tenant (api_key) or neutral cell ever carries it, and the sentence is plain text", () => {
    for (const kind of KINDS) {
      for (const scheme of ["api_key", null, "weird"]) {
        expect(authFailureCopy(kind, scheme as never)).not.toContain("My API key");
      }
    }
    expect(RECOVERY).not.toMatch(/`|\u00B7/);
  });
});

describe("buildAuthFailureFrame", () => {
  it("is a key_invalid error frame carrying the scheme only when it is known", () => {
    expect(buildAuthFailureFrame("not_logged_in", "oauth_token")).toEqual({
      type: "error",
      message: authFailureCopy("not_logged_in", "oauth_token"),
      errorCode: "key_invalid",
      credentialScheme: "oauth_token",
    });
    const neutral = buildAuthFailureFrame("not_logged_in", null);
    expect(neutral.errorCode).toBe("key_invalid");
    expect("credentialScheme" in neutral).toBe(false);
    expect("credentialScheme" in buildAuthFailureFrame("structured", "garbage")).toBe(false);
  });
});

describe("rewriteAgentAuthFailure", () => {
  it("rewrites a CLI reply to the friendly copy and builds a NEW content array", () => {
    const raw = deepFreeze(cliMessage(CLI_TEXT));
    const out = rewriteAgentAuthFailure(raw, "api_key");
    expect(out).not.toBeNull();
    expect(out!.kind).toBe("not_logged_in");
    expect(out!.content).toEqual([{ type: "text", text: authFailureCopy("not_logged_in", "api_key") }]);
    expect(out!.frame?.credentialScheme).toBe("api_key");
    // The input was deep-frozen: any in-place mutation would have thrown in strict mode. It is also unchanged.
    expect((raw.message as { content: Array<{ text: string }> }).content[0].text).toBe(CLI_TEXT);
    expect(out!.content).not.toBe((raw.message as { content: unknown }).content);
  });

  it("classifies each text kind", () => {
    const cases: Array<[string, AuthFailureKind]> = [
      ["Invalid API key · Please run /login", "invalid_api_key"],
      ["OAuth token revoked · Please run /login", "oauth_token_revoked"],
      ["Session expired. Please run /login to sign in again.", "session_expired"],
    ];
    for (const [text, kind] of cases) {
      const out = rewriteAgentAuthFailure(cliMessage(text), "oauth_token");
      expect(out?.kind).toBe(kind);
    }
    // session_expired is bubble-only: it carries no recovery frame; every other kind carries one.
    expect(rewriteAgentAuthFailure(cliMessage("Session expired. Please run /login to sign in again."), "api_key")!.frame).toBeNull();
    for (const text of [CLI_TEXT, "Invalid API key \u00B7 Please run /login", "OAuth token revoked \u00B7 Please run /login"]) {
      expect(rewriteAgentAuthFailure(cliMessage(text), "api_key")!.frame).not.toBeNull();
    }
  });

  it("rewrites a structured-only hit (authentication_failed, unrecognised wording)", () => {
    const out = rewriteAgentAuthFailure(cliMessage("Failed to authenticate. API Error: 401 Invalid bearer token."), "oauth_token");
    expect(out?.kind).toBe("structured");
    expect(out?.content[0].text).toBe(authFailureCopy("structured", "oauth_token"));
  });

  it("uses the neutral cell and no scheme in the frame for an unknown scheme", () => {
    const out = rewriteAgentAuthFailure(cliMessage(CLI_TEXT), null);
    expect(out?.content[0].text).toBe(authFailureCopy("not_logged_in", null));
    expect("credentialScheme" in out!.frame!).toBe(false);
  });

  it("leaves a multi-block or tool-bearing authentication_failed message raw", () => {
    const multi = cliMessage(CLI_TEXT);
    (multi.message as { content: unknown[] }).content.push({ type: "text", text: "more" });
    expect(rewriteAgentAuthFailure(multi, "api_key")).toBeNull();

    const tool = cliMessage(CLI_TEXT);
    (tool.message as { content: unknown[] }).content = [{ type: "tool_use", id: "t", name: "Bash", input: {} }];
    expect(rewriteAgentAuthFailure(tool, "api_key")).toBeNull();
  });

  it("does not rewrite a forged reply (non-synthetic model, no CLI flag, no structured code)", () => {
    const forged = {
      type: "assistant",
      message: { model: "claude-sonnet-4", content: [{ type: "text", text: CLI_TEXT }] },
    };
    expect(rewriteAgentAuthFailure(forged, "api_key")).toBeNull();
  });

  it("returns null for non-matching and malformed input, and never throws on a hostile getter", () => {
    expect(rewriteAgentAuthFailure(null, "api_key")).toBeNull();
    expect(rewriteAgentAuthFailure("string", "api_key")).toBeNull();
    expect(rewriteAgentAuthFailure({ type: "assistant", message: { content: [{ type: "text", text: "hello" }] } }, "api_key")).toBeNull();
    const hostile = {
      type: "assistant",
      get message(): never {
        throw new Error("boom");
      },
    };
    expect(() => rewriteAgentAuthFailure(hostile, "api_key")).not.toThrow();
    expect(rewriteAgentAuthFailure(hostile, "api_key")).toBeNull();
  });

  it("never carries any raw CLI text in its output", () => {
    const out = rewriteAgentAuthFailure(cliMessage(CLI_TEXT), "api_key")!;
    expect(JSON.stringify(out)).not.toContain("Please run /login");
  });
});

describe("logSessionFailure", () => {
  const messages = { refused: "refused", failed: "failed" };
  const mkLog = () => ({ info: vi.fn(), error: vi.fn() });
  const refusal = Object.assign(new Error("x"), { name: "ByokLeaseError", cause: "oauth_unusable" });

  it("logs an unusable-credential refusal at INFO, never ERROR, and keeps the context", () => {
    const log = mkLog();
    logSessionFailure(log, refusal, { userId: "u", conversationId: "c" }, messages);
    expect(log.info).toHaveBeenCalledWith({ userId: "u", conversationId: "c" }, "refused");
    expect(log.error).not.toHaveBeenCalled();
  });

  it("logs anything else at ERROR with the error attached and the context spread at the top level", () => {
    const log = mkLog();
    const other = new Error("boom");
    logSessionFailure(log, other, { userId: "u" }, messages);
    expect(log.error).toHaveBeenCalledWith({ err: other, userId: "u" }, "failed");
    expect(log.info).not.toHaveBeenCalled();
  });
});
