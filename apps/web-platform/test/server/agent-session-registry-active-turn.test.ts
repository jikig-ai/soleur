/**
 * feat-stream-since-disconnect (#5273) — `activeTurnConversations` binding.
 *
 * The replay write-hook keys gap-emitted frames (which carry no wire
 * `conversationId`) on this `userId → conversationId` binding, which must
 * survive socket close and be reclaimed at turn teardown. Multi-leader
 * dispatch shares one conversationId, so unregistering one leader while
 * another streams must keep the binding (repointed at the survivor). See
 * ADR-059.
 */
import { describe, it, expect, afterEach } from "vitest";
import {
  registerSession,
  unregisterSession,
  getActiveTurnConversation,
  __test_only__,
} from "@/server/agent-session-registry";
import type { AgentSession } from "@/server/review-gate";

function fakeSession(): AgentSession {
  return {
    abort: new AbortController(),
    reviewGateResolvers: new Map(),
    sessionId: null,
  };
}

const USER = "user-binding-A";

describe("agent-session-registry — activeTurnConversations binding", () => {
  afterEach(() => __test_only__.clear());

  it("binds on register and is readable while the turn runs", () => {
    expect(getActiveTurnConversation(USER)).toBeUndefined();
    registerSession(USER, "conv-1", fakeSession(), "cto");
    expect(getActiveTurnConversation(USER)).toBe("conv-1");
  });

  it("drops the binding when the last session for the user unregisters", () => {
    registerSession(USER, "conv-1", fakeSession(), "cto");
    unregisterSession(USER, "conv-1", "cto");
    expect(getActiveTurnConversation(USER)).toBeUndefined();
  });

  it("keeps the binding (repointed at the survivor) when one of several leaders unregisters", () => {
    registerSession(USER, "conv-1", fakeSession(), "cto");
    registerSession(USER, "conv-1", fakeSession(), "cmo");
    unregisterSession(USER, "conv-1", "cto");
    // Sibling leader still streaming conv-1 → binding must persist.
    expect(getActiveTurnConversation(USER)).toBe("conv-1");
    unregisterSession(USER, "conv-1", "cmo");
    expect(getActiveTurnConversation(USER)).toBeUndefined();
  });

  it("is per-user (no cross-user leakage)", () => {
    registerSession(USER, "conv-1", fakeSession(), "cto");
    registerSession("user-binding-B", "conv-2", fakeSession(), "cto");
    expect(getActiveTurnConversation(USER)).toBe("conv-1");
    expect(getActiveTurnConversation("user-binding-B")).toBe("conv-2");
  });
});
