import { describe, it, expect, beforeEach } from "vitest";
import {
  __test_only__,
  registerSession,
  setUserWorkspace,
  clearUserWorkspace,
  getUserWorkspace,
  abortAllWorkspaceMemberSessions,
  abortAllSessionsForWorkspace,
} from "@/server/agent-session-registry";
import type { AgentSession } from "@/server/review-gate";
import { classifyAbortReason } from "@/server/abort-classifier";

function makeSession(): AgentSession & { reasonReceived?: unknown } {
  const ctrl = new AbortController();
  const session: AgentSession & { reasonReceived?: unknown } = {
    abort: ctrl,
    reviewGateResolvers: new Map(),
    sessionId: null,
  };
  ctrl.signal.addEventListener("abort", () => {
    session.reasonReceived = ctrl.signal.reason;
  });
  return session;
}

const JIKIGAI = "ws-jikigai";
const PERSONAL = "ws-personal";
const HARRY = "user-harry";
const JEAN = "user-jean";

describe("abortAllWorkspaceMemberSessions", () => {
  beforeEach(() => {
    __test_only__.clear();
  });

  it("aborts only sessions of the given user in the given workspace", () => {
    const harrySession = makeSession();
    registerSession(HARRY, "conv-1", harrySession);
    setUserWorkspace(HARRY, JIKIGAI);

    const jeanSession = makeSession();
    registerSession(JEAN, "conv-2", jeanSession);
    setUserWorkspace(JEAN, JIKIGAI);

    abortAllWorkspaceMemberSessions(JIKIGAI, HARRY);

    expect(harrySession.abort.signal.aborted).toBe(true);
    expect(jeanSession.abort.signal.aborted).toBe(false);
  });

  it("Kieran C5: does NOT abort when user's workspace binding doesn't match", () => {
    const session = makeSession();
    registerSession(HARRY, "conv-1", session);
    // Harry's current workspace is PERSONAL, not JIKIGAI
    setUserWorkspace(HARRY, PERSONAL);

    abortAllWorkspaceMemberSessions(JIKIGAI, HARRY);

    expect(session.abort.signal.aborted).toBe(false);
  });

  it("no-op when user has no workspace binding", () => {
    const session = makeSession();
    registerSession(HARRY, "conv-1", session);
    // No setUserWorkspace call — pre-Phase-5.5 session shape

    abortAllWorkspaceMemberSessions(JIKIGAI, HARRY);

    expect(session.abort.signal.aborted).toBe(false);
  });

  it("aborts ALL sessions for the matching user (multi-leader, multi-conversation)", () => {
    const s1 = makeSession();
    const s2 = makeSession();
    const s3 = makeSession();
    registerSession(HARRY, "conv-1", s1);
    registerSession(HARRY, "conv-2", s2);
    registerSession(HARRY, "conv-1", s3, "cmo");
    setUserWorkspace(HARRY, JIKIGAI);

    abortAllWorkspaceMemberSessions(JIKIGAI, HARRY);

    expect(s1.abort.signal.aborted).toBe(true);
    expect(s2.abort.signal.aborted).toBe(true);
    expect(s3.abort.signal.aborted).toBe(true);
  });

  it("aborted sessions carry the workspace_membership_revoked AbortKind", () => {
    const session = makeSession();
    registerSession(HARRY, "conv-1", session);
    setUserWorkspace(HARRY, JIKIGAI);

    abortAllWorkspaceMemberSessions(JIKIGAI, HARRY);

    const classified = classifyAbortReason(session.abort.signal.reason);
    expect(classified.kind).toBe("workspace_membership_revoked");
  });

  it("clearUserWorkspace removes the binding (subsequent abort calls are no-ops)", () => {
    const session = makeSession();
    registerSession(HARRY, "conv-1", session);
    setUserWorkspace(HARRY, JIKIGAI);
    expect(getUserWorkspace(HARRY)).toBe(JIKIGAI);

    clearUserWorkspace(HARRY);
    expect(getUserWorkspace(HARRY)).toBeUndefined();

    abortAllWorkspaceMemberSessions(JIKIGAI, HARRY);
    expect(session.abort.signal.aborted).toBe(false);
  });

  it("setUserWorkspace ignores empty/undefined values (defensive)", () => {
    setUserWorkspace(HARRY, "");
    expect(getUserWorkspace(HARRY)).toBeUndefined();
  });
});

describe("abortAllSessionsForWorkspace (ADR-044 PR-2 — shared team-dir teardown)", () => {
  beforeEach(() => {
    __test_only__.clear();
  });

  it("aborts EVERY member's session bound to the workspace (not just the caller)", () => {
    // The distinction from abortAllWorkspaceMemberSessions: a disconnect tears
    // down the SHARED clone, so BOTH members in the team workspace must abort —
    // a per-caller abort (the sibling fn) would leave JEAN mid-write → ENOENT.
    const harry = makeSession();
    const jean = makeSession();
    registerSession(HARRY, "conv-1", harry);
    setUserWorkspace(HARRY, JIKIGAI);
    registerSession(JEAN, "conv-2", jean);
    setUserWorkspace(JEAN, JIKIGAI);

    abortAllSessionsForWorkspace(JIKIGAI);

    expect(harry.abort.signal.aborted).toBe(true);
    expect(jean.abort.signal.aborted).toBe(true);
  });

  it("leaves sessions bound to a DIFFERENT workspace untouched", () => {
    const teamSession = makeSession();
    const personalSession = makeSession();
    registerSession(HARRY, "conv-1", teamSession);
    setUserWorkspace(HARRY, JIKIGAI);
    registerSession(JEAN, "conv-2", personalSession);
    setUserWorkspace(JEAN, PERSONAL);

    abortAllSessionsForWorkspace(JIKIGAI);

    expect(teamSession.abort.signal.aborted).toBe(true);
    expect(personalSession.abort.signal.aborted).toBe(false);
  });

  it("no-op when no session is bound to the workspace (e.g. solo with no live turn)", () => {
    const session = makeSession();
    registerSession(JEAN, "conv-2", session);
    setUserWorkspace(JEAN, PERSONAL);

    abortAllSessionsForWorkspace(JIKIGAI);

    expect(session.abort.signal.aborted).toBe(false);
  });
});
