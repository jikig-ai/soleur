// Agent auth-failure diagnostic: the pure matcher (positive family, negative near-misses, forgery, text-first ordering,
// timing, no-leak). Plan: knowledge-base/project/plans/2026-10-25-feat-agent-auth-failure-diagnostic-plan.md (Phase 1, item 1;
// Guard 2 rows 2, 5, 8d). Fixtures are SYNTHESIZED (cq-test-fixtures-synthesized-only): the CLI wording is public product text,
// the ids are fake. The separator is written as the \u00B7 escape (cq-regex-unicode-separators-escape-only).
import { beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({ log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } }));
vi.mock("@/server/logger", () => ({ default: h.log, createChildLogger: vi.fn(() => h.log) }));

import type { ApiKeySource } from "@anthropic-ai/claude-agent-sdk";

import {
  CLI_AUTH_FAILURE_REPLIES,
  SDK_API_KEY_SOURCES,
  SDK_AUTHENTICATION_FAILED,
} from "@/server/claude-error-signatures";
import type { AgentAuthMode, AgentAuthRunner } from "@/server/agent-auth-failure";
import {
  __resetAgentAuthMatcherWarnForTests,
  buildAgentAuthPayload,
  deriveAgentAuthContext,
  matchAgentAuthFailure,
} from "@/server/agent-auth-failure";

// Compile-time parity with the SDK's `ApiKeySource` union, both directions: a value added or removed by an SDK bump
// reds `tsc --noEmit` here instead of silently falling out of the closed `cli_key_source` list.
type Mirrored = (typeof SDK_API_KEY_SOURCES)[number];
type Equal<A, B> = (<T>() => T extends A ? 1 : 2) extends <T>() => T extends B ? 1 : 2 ? true : false;
const _sdkParity: Equal<Mirrored, ApiKeySource> = true;
void _sdkParity;

// Both directions for the payload's own closed lists as well: a union member missing from (or extra in) `ENUMS` reds tsc here.
// `buildAgentAuthPayload` echoes a value only when it is a member of the list, so a member round-trips iff it is listed.
const RUNNERS = { legacy: 0, "cc-soleur-go": 0 } satisfies Record<AgentAuthRunner, 0>;
const AUTH_MODES = { managed: 0, "api-key": 0, unbound: 0, unknown: 0 } satisfies Record<AgentAuthMode, 0>;

const SEP = "\u00B7";
const KINDS = ["not_logged_in", "invalid_api_key", "oauth_token_revoked", "session_expired", "structured"] as const;

/** The CLI-authored shape: `<synthetic>` model, one text block (measured from the real binary, see the plan). */
const synthetic = (text: string, extra: Record<string, unknown> = {}) => ({
  type: "assistant",
  message: { model: "<synthetic>", content: [{ type: "text", text }] },
  session_id: "fake-session",
  uuid: "00000000-0000-4000-8000-000000000001",
  ...extra,
});

const FAMILY: Array<[string, string]> = [
  ["not_logged_in", `Not logged in ${SEP} Please run /login`],
  ["not_logged_in", "Not logged in. Run claude auth login to authenticate."],
  ["invalid_api_key", `API Error: 401 Invalid API key ${SEP} Please run /login`],
  ["invalid_api_key", `Invalid API key ${SEP} Please run /login`],
  ["oauth_token_revoked", `OAuth token revoked ${SEP} Please run /login`],
  ["session_expired", "Session expired. Please run /login to sign in again."],
  ["session_expired", "Your session has expired. Please run /login to sign in again."],
];

beforeEach(() => {
  vi.clearAllMocks();
  __resetAgentAuthMatcherWarnForTests();
});

describe("matchAgentAuthFailure: positive family", () => {
  it("the family covers every CLI_AUTH_FAILURE_REPLIES kind (a new kind must get a fixture here)", () => {
    const covered = new Set(FAMILY.map(([k]) => k));
    for (const { kind } of CLI_AUTH_FAILURE_REPLIES) expect(covered.has(kind), kind).toBe(true);
    expect(CLI_AUTH_FAILURE_REPLIES.length).toBeGreaterThanOrEqual(4);
  });

  it.each(FAMILY)("%s: %j", (kind, text) => {
    expect(matchAgentAuthFailure(synthetic(text))).toBe(kind);
    // The other CLI-set field is enough as well.
    const viaFlag = {
      type: "assistant",
      is_api_error_message: true,
      message: { model: "claude-sonnet-5-5", content: [{ type: "text", text }] },
    };
    expect(matchAgentAuthFailure(viaFlag)).toBe(kind);
  });

  it("a result with is_error true carrying the text matches", () => {
    expect(matchAgentAuthFailure({ type: "result", subtype: "success", is_error: true, result: `Not logged in ${SEP} Please run /login` })).toBe(
      "not_logged_in",
    );
  });

  it("the structured code alone is sufficient, with arbitrary or no text", () => {
    expect(SDK_AUTHENTICATION_FAILED).toBe("authentication_failed");
    expect(
      matchAgentAuthFailure({ type: "assistant", error: "authentication_failed", message: { content: [{ type: "text", text: "anything at all" }] } }),
    ).toBe("structured");
    expect(matchAgentAuthFailure({ type: "assistant", error: "authentication_failed", message: { content: [] } })).toBe("structured");
    expect(matchAgentAuthFailure({ type: "assistant", error: "authentication_failed" })).toBe("structured");
  });

  it("text is classified FIRST: the real stream message (text AND the structured code) reports the text variant, not structured", () => {
    const real = synthetic(`Not logged in ${SEP} Please run /login`, { error: "authentication_failed", is_api_error_message: true });
    expect(matchAgentAuthFailure(real)).toBe("not_logged_in");
  });

  it("every reply kind survives the payload's closed match_kind list (a new kind cannot be matched and then reported as unknown)", () => {
    const context = deriveAgentAuthContext("legacy", "api_key", {});
    for (const { kind } of CLI_AUTH_FAILURE_REPLIES) {
      expect(buildAgentAuthPayload({ context, authMode: "managed", cliKeySource: "none", matchKind: kind }).match_kind).toBe(kind);
    }
    expect(buildAgentAuthPayload({ context, authMode: "managed", cliKeySource: "none", matchKind: "structured" }).match_kind).toBe("structured");
  });

  it("every runner and auth_mode union member round-trips through the payload (an unlisted member would be reported as unknown)", () => {
    const context = deriveAgentAuthContext("legacy", "api_key", {});
    for (const runner of Object.keys(RUNNERS)) {
      const payload = buildAgentAuthPayload({ context: { ...context, runner }, authMode: "managed", cliKeySource: "none", matchKind: "structured" });
      expect(payload.runner, runner).toBe(runner);
    }
    for (const authMode of Object.keys(AUTH_MODES)) {
      expect(buildAgentAuthPayload({ context, authMode, cliKeySource: "none", matchKind: "structured" }).auth_mode, authMode).toBe(authMode);
    }
  });

  it("other structured codes are out of the family", () => {
    for (const code of ["billing_error", "rate_limit", "oauth_org_not_allowed", "account_on_hold", "verification_required", "unknown"]) {
      expect(matchAgentAuthFailure({ type: "assistant", error: code, message: { content: [] } }), code).toBeNull();
    }
  });
});

describe("matchAgentAuthFailure: negative near-misses and the forgery row", () => {
  const TEXT = `Not logged in ${SEP} Please run /login`;
  const NEGATIVES: Array<[string, unknown]> = [
    ["API key format sentence", synthetic("Invalid API key format. API key must contain only alphanumeric characters, dashes, and underscores.")],
    ["model prose", synthetic("You are not logged in to GitHub; run gh auth login")],
    ["lower-case variant", synthetic(`not logged in ${SEP} please run /login`)],
    ["ASCII middle dot substitute", synthetic("Not logged in . Please run /login")],
    ["text with a prefix", synthetic(`Sorry. ${TEXT}`)],
    ["text with a suffix", synthetic(`${TEXT} and more`)],
    ["bare phrase", synthetic("Not logged in")],
    ["two text blocks", { type: "assistant", message: { model: "<synthetic>", content: [{ type: "text", text: TEXT }, { type: "text", text: "x" }] } }],
    [
      "text beside a tool_use",
      { type: "assistant", message: { model: "<synthetic>", content: [{ type: "text", text: TEXT }, { type: "tool_use", id: "t", name: "Bash", input: {} }] } },
    ],
    ["a tool_use only", { type: "assistant", message: { model: "<synthetic>", content: [{ type: "tool_use", id: "t", name: "Bash", input: {} }] } }],
    ["text over 200 chars", synthetic(`Not logged in ${SEP} Please run /login${" x".repeat(120)}`)],
    ["successful result quoting the text", { type: "result", subtype: "success", is_error: false, result: TEXT }],
    ["result without is_error", { type: "result", subtype: "success", result: TEXT }],
    ["stream_event partial", { type: "stream_event", event: { type: "content_block_delta", delta: { type: "text_delta", text: TEXT } } }],
    ["user message echoing the text", { type: "user", message: { role: "user", content: [{ type: "text", text: TEXT }] } }],
    ["system init", { type: "system", subtype: "init", apiKeySource: "none" }],
    ["content as a bare string", { type: "assistant", message: { model: "<synthetic>", content: TEXT } }],
    ["text that is not a string", synthetic(42 as unknown as string)],
    ["null", null],
    ["undefined", undefined],
    ["number", 42],
    ["string", TEXT],
    ["array", [synthetic(TEXT)]],
    ["empty object", {}],
  ];

  it("the negative corpus has a floor (a matcher that returns a kind for everything cannot hide behind an empty list)", () => {
    expect(NEGATIVES.length).toBeGreaterThanOrEqual(20);
  });

  it.each(NEGATIVES)("%s -> null", (_name, input) => {
    expect(matchAgentAuthFailure(input)).toBeNull();
  });

  it("FORGERY: a plain assistant block with a real model id, no is_api_error_message, carrying the exact CLI text, is null", () => {
    const forged = { type: "assistant", message: { model: "claude-sonnet-5-5", content: [{ type: "text", text: TEXT }] } };
    expect(matchAgentAuthFailure(forged)).toBeNull();
    expect(matchAgentAuthFailure({ ...forged, is_api_error_message: false })).toBeNull();
    // ... and the same block with either CLI-set field matches.
    expect(matchAgentAuthFailure({ ...forged, message: { ...forged.message, model: "<synthetic>" } })).toBe("not_logged_in");
    expect(matchAgentAuthFailure({ ...forged, is_api_error_message: true })).toBe("not_logged_in");
  });

  it("the length gate and the trim are observable: padded text over 200 chars is null, padded text under 200 matches", () => {
    expect(matchAgentAuthFailure(synthetic(`${TEXT}${" ".repeat(200)}`))).toBeNull();
    expect(matchAgentAuthFailure(synthetic(`  ${TEXT}\n `))).toBe("not_logged_in");
  });

  it("the CLI-set flag must be exactly true and the model exactly <synthetic>: truthy look-alikes do not unlock the text arm", () => {
    const real = { type: "assistant", message: { model: "claude-sonnet-5-5", content: [{ type: "text", text: TEXT }] } };
    for (const flag of ["true", 1, {}, [true]]) {
      expect(matchAgentAuthFailure({ ...real, is_api_error_message: flag }), String(flag)).toBeNull();
    }
    for (const model of ["<other>", "<synthetic> ", "synthetic", "<SYNTHETIC>"]) {
      expect(matchAgentAuthFailure({ ...real, message: { ...real.message, model } }), model).toBeNull();
    }
  });

  it("a throwing getter on the input yields null instead of an exception", () => {
    const hostile = {
      type: "assistant",
      get message(): never {
        throw new Error("boom");
      },
    };
    expect(() => matchAgentAuthFailure(hostile)).not.toThrow();
    expect(matchAgentAuthFailure(hostile)).toBeNull();
  });

  it("the swallowed fault is visible: ONE constant-text warn per process, no payload, never an event", () => {
    const hostile = {
      type: "assistant",
      get message(): never {
        throw new Error("CANARY-GETTER-7f3a");
      },
    };
    matchAgentAuthFailure(hostile);
    matchAgentAuthFailure(hostile);
    expect(h.log.warn).toHaveBeenCalledTimes(1);
    expect(h.log.warn.mock.calls[0]).toHaveLength(1);
    expect(JSON.stringify(h.log.warn.mock.calls)).not.toContain("CANARY");
  });
});

describe("matchAgentAuthFailure: cost and leakage", () => {
  it("a 200-character adversarial-whitespace message is rejected in bounded time", () => {
    const adversarial = synthetic(`Not logged in${" ".repeat(150)}\u00B7${" ".repeat(34)}!`);
    const start = performance.now();
    for (let i = 0; i < 2000; i++) expect(matchAgentAuthFailure(adversarial)).toBeNull();
    expect(performance.now() - start).toBeLessThan(500);
  });

  it("the returned value is always a member of the closed enum or null, never a substring of the input", () => {
    const canary = "CANARY-BODY-7f3a-not-a-secret";
    const inputs: unknown[] = [
      synthetic(`Not logged in ${SEP} Please run /login`),
      synthetic(canary),
      { type: "assistant", error: "authentication_failed", message: { content: [{ type: "text", text: canary }] } },
      { type: "result", is_error: true, result: canary },
      { type: "assistant", error: canary },
    ];
    for (const input of inputs) {
      const out = matchAgentAuthFailure(input);
      expect(out === null || (KINDS as readonly string[]).includes(out)).toBe(true);
      if (out !== null) expect(out).not.toContain(canary);
    }
    expect(matchAgentAuthFailure({ type: "assistant", error: "authentication_failed", message: { content: [{ type: "text", text: canary }] } })).toBe(
      "structured",
    );
  });
});
