// #8211: the bounded wait that runs between "abort sessions" and "reap the tree".
import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";
import {
  registerSession,
  unregisterSession,
  setUserWorkspace,
  hasRegisteredSessionForUser,
  hasRegisteredSessionForWorkspace,
  waitForSessionsToDeregister,
  waitForUserSessionsToDeregister,
  waitForWorkspaceSessionsToDeregister,
  SESSION_DRAIN_MAX_MS,
  SESSION_DRAIN_STEP_MS,
  __test_only__,
} from "@/server/agent-session-registry";
import type { AgentSession } from "@/server/review-gate";

const fake = (): AgentSession => ({
  abort: new AbortController(),
  reviewGateResolvers: new Map(),
  sessionId: null,
});

beforeEach(() => vi.useFakeTimers());
afterEach(() => {
  vi.useRealTimers();
  __test_only__.clear();
});

describe("registry predicates", () => {
  it("user: matches only that user's prefix", () => {
    registerSession("u1", "c1", fake());
    expect(hasRegisteredSessionForUser("u1")).toBe(true);
    expect(hasRegisteredSessionForUser("u")).toBe(false); // prefix collision
    expect(hasRegisteredSessionForUser("u2")).toBe(false);
  });

  it("workspace: matches sessions of ANY member bound to it", () => {
    registerSession("u1", "c1", fake());
    registerSession("u2", "c2", fake());
    setUserWorkspace("u1", "ws-A");
    setUserWorkspace("u2", "ws-B");
    expect(hasRegisteredSessionForWorkspace("ws-A")).toBe(true);
    expect(hasRegisteredSessionForWorkspace("ws-C")).toBe(false);
  });
});

describe("waitForSessionsToDeregister", () => {
  it("returns immediately when nothing is registered", async () => {
    await expect(waitForUserSessionsToDeregister("nobody")).resolves.toEqual({ drained: true, waitedMs: 0 });
  });

  it("resolves as soon as the session deregisters, in whole steps", async () => {
    registerSession("u1", "c1", fake());
    const p = waitForUserSessionsToDeregister("u1");
    await vi.advanceTimersByTimeAsync(SESSION_DRAIN_STEP_MS * 2);
    unregisterSession("u1", "c1");
    await vi.advanceTimersByTimeAsync(SESSION_DRAIN_STEP_MS);
    await expect(p).resolves.toEqual({ drained: true, waitedMs: SESSION_DRAIN_STEP_MS * 3 });
  });

  it("is BOUNDED: a session that never deregisters returns drained:false at the bound", async () => {
    registerSession("u1", "c1", fake());
    setUserWorkspace("u1", "ws-A");
    const p = waitForWorkspaceSessionsToDeregister("ws-A");
    await vi.advanceTimersByTimeAsync(SESSION_DRAIN_MAX_MS + SESSION_DRAIN_STEP_MS * 5);
    await expect(p).resolves.toEqual({ drained: false, waitedMs: SESSION_DRAIN_MAX_MS });
  });

  it("honours custom bound and step", async () => {
    let live = true;
    const p = waitForSessionsToDeregister(() => live, { maxMs: 30, stepMs: 10 });
    await vi.advanceTimersByTimeAsync(100);
    await expect(p).resolves.toEqual({ drained: false, waitedMs: 30 });
    live = false;
    await expect(waitForSessionsToDeregister(() => live, { maxMs: 30, stepMs: 10 })).resolves.toEqual({
      drained: true,
      waitedMs: 0,
    });
  });

  it("the defaults are ~5 s in 100 ms steps", () => {
    expect(SESSION_DRAIN_MAX_MS).toBe(5_000);
    expect(SESSION_DRAIN_STEP_MS).toBe(100);
  });
});
