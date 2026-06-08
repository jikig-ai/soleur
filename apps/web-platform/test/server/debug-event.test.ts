/**
 * feat-debug-mode-stream — Phase 5.1 deterministic tests for the server-side
 * gated debug-event emit. The LLM is OUT of the assertion path: we drive
 * `buildDebugEvent` / `emitDebugEvent` directly and assert the WIRE BYTES of
 * the serialized frame, not "the redactor was called".
 *
 * Four describe blocks (plan §Phase 5):
 *   (a) gate              — nothing emits unless `enabled` (AC6)
 *   (b) redaction + wire  — planted secrets never reach the serialized frame;
 *       probe-trip drops the input and emits the buildToolLabel placeholder
 *       (human label, NOT the raw tool name) (AC4)
 *   (c) probe-superset    — every redactor `[redacted-*]` kind has a probe (AC4b)
 *   (d) ephemeral / catch — catch logs only {userId, conversationId, kind} (AC7)
 *
 * Fixtures are synthesized SHAPES only (cq-test-fixtures-synthesized-only) —
 * no real credential value is committed.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) => reportSilentFallbackSpy(...args),
  warnSilentFallback: vi.fn(),
}));

import {
  buildDebugEvent,
  emitDebugEvent,
  type DebugEventFrame,
} from "@/server/debug-event";
import { DEBUG_REDACTION_PROBES } from "@/server/debug-probes";

// --- synthesized secret SHAPES (never real values) -------------------------
// Split across concatenation so GitHub secret-scanning push-protection does not
// flag the (fake) tokens, while the runtime value still has the exact shape the
// redactor regex matches (cq-test-fixtures-synthesized-only).
const ANTHROPIC = "sk-" + "ant-api03AAAABBBBCCCCDDDDEEEEFFFF1111";
const AKIA = "AKIA" + "IOSFODNN7EXAMPLE";
const STRIPE = "sk_" + "live_0123456789abcdefABCD1234";
const GITHUB = "ghp_" + "0123456789abcdefghij0123456789abcd";
const JWT =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.s1gn4tur3abcdef";
const GENERIC_BEARER = "abcDEF123456ghiJKL789mnoPQR";
const GENERIC_NO_SENTINEL = "9f3a7c1e8b2d4f6a0c5e7d9b1a3f5c7e9d1b3a5f";

beforeEach(() => {
  reportSilentFallbackSpy.mockClear();
});

function serialize(frame: DebugEventFrame | null): string {
  return frame ? JSON.stringify(frame) : "";
}

describe("(a) gate — emit produces nothing unless debugPosture && debugEligible (AC6)", () => {
  it("enabled=false → send is never called", () => {
    const send = vi.fn();
    emitDebugEvent({
      enabled: false,
      kind: "tool_use",
      rawValue: { command: "ls" },
      toolName: "Bash",
      userId: "u1",
      conversationId: "c1",
      send,
    });
    expect(send).not.toHaveBeenCalled();
  });

  it("enabled=true → send receives the frame", () => {
    const send = vi.fn();
    emitDebugEvent({
      enabled: true,
      kind: "reasoning",
      rawValue: "thinking about the next step",
      userId: "u1",
      conversationId: "c1",
      send,
    });
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0]![0]).toMatchObject({
      type: "debug_event",
      kind: "reasoning",
    });
  });
});

describe("(b) redaction + wire-bytes invariant (AC4)", () => {
  it("sentinel values under a tool_input → no secret substring on the wire", () => {
    const frame = buildDebugEvent({
      kind: "tool_use",
      toolName: "Bash",
      rawValue: {
        command: `deploy with ${ANTHROPIC} and ${GITHUB}`,
        note: STRIPE,
        region: AKIA,
        jwt: JWT,
      },
    });
    const wire = serialize(frame);
    for (const secret of [ANTHROPIC, GITHUB, STRIPE, AKIA, JWT]) {
      expect(wire).not.toContain(secret);
    }
    expect(wire).toContain("[redacted-");
  });

  it("structured {env:{X_TOKEN}} + {headers:{Authorization}} → values redacted via key context", () => {
    const frame = buildDebugEvent({
      kind: "tool_use",
      toolName: "Bash",
      rawValue: {
        env: { X_TOKEN: GENERIC_NO_SENTINEL },
        headers: { Authorization: `Bearer ${GENERIC_BEARER}` },
        args: { API_SECRET: GENERIC_NO_SENTINEL },
      },
    });
    const wire = serialize(frame);
    expect(wire).not.toContain(GENERIC_NO_SENTINEL);
    expect(wire).not.toContain(GENERIC_BEARER);
  });

  it("reasoning prose quoting sk-ant-/AKIA → sentinel never reaches the wire", () => {
    for (const secret of [ANTHROPIC, AKIA]) {
      const frame = buildDebugEvent({
        kind: "reasoning",
        rawValue: `the operator pasted ${secret} into the prompt`,
      });
      // Sentinel-anchored prose is redacted (not dropped) — but never leaks.
      expect(serialize(frame)).not.toContain(secret);
    }
  });

  it("probe trip (redactor miss) → DROP placeholder + human label, NOT the raw tool name (P0-7)", async () => {
    // Simulate a redactor coverage gap by stubbing the redactor to identity:
    // the sentinel then SURVIVES into the body, the probe trips, and the
    // tool_use frame DROPs the input while keeping a human label.
    vi.resetModules();
    vi.doMock("@/lib/safety/redaction-allowlist", () => ({
      redactCommandForDisplay: (s: string) => s, // identity → redaction "miss"
      redactGithubSourcedText: (s: string) => s,
    }));
    const { buildDebugEvent: build } = await import("@/server/debug-event");
    const rawToolName = "mcp__soleur_platform__edit_c4_diagram";
    const frame = build({
      kind: "tool_use",
      toolName: rawToolName,
      rawValue: { blob: `leak ${ANTHROPIC}` },
    });
    const wire = JSON.stringify(frame);
    expect(frame?.body).toBe("[input withheld: failed redaction probe]");
    expect(wire).not.toContain(ANTHROPIC); // input withheld
    expect(wire).not.toContain(rawToolName); // raw SDK tool name never on wire (#2138)
    expect(frame?.label).toBeDefined();
    vi.doUnmock("@/lib/safety/redaction-allowlist");
    vi.resetModules();
  });

  it("reasoning/result whose redacted output still trips the probe → frame dropped (null)", async () => {
    vi.resetModules();
    vi.doMock("@/lib/safety/redaction-allowlist", () => ({
      redactCommandForDisplay: (s: string) => s, // identity → "miss"
      redactGithubSourcedText: (s: string) => s,
    }));
    const { buildDebugEvent: build } = await import("@/server/debug-event");
    const frame = build({ kind: "reasoning", rawValue: `secret ${GITHUB}` });
    expect(frame).toBeNull();
    vi.doUnmock("@/lib/safety/redaction-allowlist");
    vi.resetModules();
  });
});

describe("(c) probe-superset coverage — every redactor [redacted-*] kind has a probe (AC4b)", () => {
  it("DEBUG_REDACTION_PROBES covers every [redacted-*] kind the redactor emits", () => {
    const src = readFileSync(
      join(__dirname, "..", "..", "lib", "safety", "redaction-allowlist.ts"),
      "utf8",
    );
    const redactorKinds = new Set(
      [...src.matchAll(/\[redacted-([a-z]+)\]/g)].map((m) => `[redacted-${m[1]}]`),
    );
    expect(redactorKinds.size).toBeGreaterThanOrEqual(6);
    const probeKinds = new Set(DEBUG_REDACTION_PROBES.map((p) => p.redactedKind));
    for (const kind of redactorKinds) {
      expect(probeKinds).toContain(kind);
    }
  });
});

describe("(d) ephemeral / catch — catch logs only {userId, conversationId, kind} (AC7)", () => {
  it("a throwing send is caught; the report carries no body/rawValue/secret", () => {
    const send = vi.fn(() => {
      throw new Error("ws closed");
    });
    emitDebugEvent({
      enabled: true,
      kind: "tool_use",
      toolName: "Bash",
      rawValue: { command: `echo ${ANTHROPIC}` },
      userId: "u-42",
      conversationId: "c-99",
      send,
    });
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const ctx = reportSilentFallbackSpy.mock.calls[0]![1] as {
      extra: Record<string, unknown>;
    };
    expect(ctx.extra).toEqual({ userId: "u-42", conversationId: "c-99", kind: "tool_use" });
    // No part of the report serialization may carry the secret or the raw value.
    const blob = JSON.stringify(reportSilentFallbackSpy.mock.calls[0]);
    expect(blob).not.toContain(ANTHROPIC);
    expect(blob).not.toContain("body");
    expect(blob).not.toContain("rawValue");
  });
});
