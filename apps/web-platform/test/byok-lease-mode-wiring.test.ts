import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// #11591 Guard 1 wiring pins. The type (`LeaseModeOpts` is required) forces every caller to choose, but a
// caller can legitimately choose `{ restOnly: true }` — so the two Agent-SDK call sites are pinned by exact
// count, and the credential scheme that reaches the UI frame and the cost-cap bridge must come from the LEASED
// credential, never from the mode (AC9). Counted with a global match (no pipe into `grep -q`).

const root = join(__dirname, "..", "server");
// Whole-line `//` comments are dropped so prose that quotes a pinned token cannot satisfy (or inflate) a pin.
const src = (f: string) =>
  readFileSync(join(root, f), "utf8")
    .split("\n")
    .filter((l) => !/^\s*\/\//.test(l))
    .join("\n");
const count = (text: string, needle: string) => text.split(needle).length - 1;

describe("Agent-SDK call sites hand the lease a binding-backed mode resolver", () => {
  // The ARGUMENTS are pinned too: swapping (userId, conversationId) type-checks (both are strings) and would
  // mint a tenant client for the wrong id, failing every subscription holder closed.
  it.each([
    ["agent-runner.ts", "resolveAuthMode: makeConversationAuthModeResolver(userId, conversationId)"],
    ["cc-dispatcher.ts", "resolveAuthMode: makeConversationAuthModeResolver(args.userId, args.conversationId)"],
  ])("%s passes the conversation resolver, with (user, conversation) in that order, exactly once", (file, call) => {
    expect(count(src(file), call)).toBe(1);
    expect(count(src(file), "resolveAuthMode: makeConversationAuthModeResolver(")).toBe(1);
  });

  it("every resolveKeyOwnerThenLease call site passes a LeaseModeOpts (resolver or restOnly)", () => {
    const sites: Array<[string, number]> = [
      ["agent-runner.ts", 2],
      ["cc-dispatcher.ts", 1],
      ["inngest/functions/cfo-on-payment-failed.ts", 1],
      ["inngest/functions/github-on-event.ts", 1],
    ];
    let optsFound = 0;
    for (const [file, calls] of sites) {
      const text = src(file);
      expect(count(text, "resolveKeyOwnerThenLease(")).toBe(calls);
      optsFound += count(text, "resolveAuthMode: makeConversationAuthModeResolver(") + count(text, "{ restOnly: true }");
    }
    expect(optsFound).toBe(5);
  });

  it("byok-resolver has a single runWithByokLease chokepoint for all five lease branches", () => {
    expect(count(src("byok-resolver.ts"), "runWithByokLease(")).toBe(1);
  });
});

describe("the UI scheme comes from the leased credential, not the mode (AC9)", () => {
  it("credentialScheme and the cost-cap bridge read credential.scheme", () => {
    expect(count(src("agent-runner.ts"), "credentialScheme: credential.scheme")).toBe(1);
    expect(count(src("cc-dispatcher.ts"), "credentialScheme: credential.scheme")).toBe(1);
    expect(count(src("cc-dispatcher.ts"), "setAuthScheme?.(credential.scheme)")).toBe(1);
  });

  it("the friendly-error modules stay untouched by the mode: they never name a binding or an auth mode", () => {
    for (const f of ["agent-auth-user-message.ts", "agent-auth-match.ts"]) {
      const text = src(f);
      expect(count(text, "engine-binding-auth-mode")).toBe(0);
      expect(count(text, "resolveAuthMode")).toBe(0);
    }
  });
});

describe("the other lease users and the mode vocabulary", () => {
  it("the one direct runWithByokLease caller (agent-on-spawn-requested) is REST-only: it never asks for an Agent-SDK credential", () => {
    const text = src("inngest/functions/agent-on-spawn-requested.ts");
    expect(count(text, "runWithByokLease(")).toBeGreaterThan(0);
    expect(count(text, "getAgentCredential(")).toBe(0);
  });

  it("the settings registry's claude-code auth modes are exactly the modes the lease accepts", async () => {
    const { reviewedEngineRegistry } = await import("@/server/agent-engine-reviewed-definitions");
    expect([...reviewedEngineRegistry.get("claude-code").authModes].sort()).toEqual(["api-key", "managed"]);
  });
});

