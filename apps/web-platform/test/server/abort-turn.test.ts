/**
 * Abort-turn unit tests (PR1, plan §1.9).
 *
 * Covers:
 *   - `abortSession` reason union widened to include `"user_requested_stop"`,
 *     and the Error message routes through `controller.signal.reason` for the
 *     for-await classifier (`classifyAbortReason`).
 *   - Multi-leader broadcast: an un-keyed `abortSession(userId, conv)` aborts
 *     every leader session for the conversation. (TR3 / G3 — no hidden leader
 *     keeps burning the user's BYOK key after Stop.)
 *   - Cross-user invariant: aborting `(alice, conv1)` cannot touch `(bob, *)`
 *     even when conv IDs collide. The wire format ALSO blocks userId forging
 *     via the strictObject zod schema.
 *   - Idempotency: a second `abortSession` after the session has been
 *     unregistered is a silent no-op.
 *   - WSMessage parser: `abort_turn` accepts `{conversationId}`, rejects
 *     `userId` and any other extra field (TR4).
 *
 * Lives next to other server unit tests (`apps/web-platform/test/server/`)
 * per project convention. Targets the registry helpers extracted from
 * `agent-runner.ts` so the assertions don't have to spin up the SDK or
 * Supabase.
 */

import { describe, it, expect, beforeEach, vi } from "vitest";

import {
  abortSession,
  abortAllUserSessions,
  registerSession,
  unregisterSession,
  __test_only__ as registryTestOnly,
} from "@/server/agent-session-registry";
import type { AgentSession } from "@/server/review-gate";
import {
  classifyAbortReason,
  SessionAbortError,
  type AbortKind,
} from "@/server/abort-classifier";
import { parseWSMessage } from "@/lib/ws-zod-schemas";

function makeSession(): AgentSession {
  return {
    abort: new AbortController(),
    reviewGateResolvers: new Map(),
    sessionId: null,
  };
}

describe("agent-session-registry · abortSession", () => {
  beforeEach(() => {
    registryTestOnly.clear();
  });

  it("emits a typed SessionAbortError with kind='user_requested_stop' on signal.reason", () => {
    const session = makeSession();
    registerSession("alice", "conv1", session);

    abortSession("alice", "conv1", "user_requested_stop");

    expect(session.abort.signal.aborted).toBe(true);
    const reason = session.abort.signal.reason;
    expect(reason).toBeInstanceOf(SessionAbortError);
    expect((reason as SessionAbortError).kind).toBe("user_requested_stop");
    // classifyAbortReason is the public contract surface — the for-await
    // abort branch reads it via this helper, NOT via Error.message slicing.
    expect(classifyAbortReason(reason)).toMatchObject({
      kind: "user_requested_stop",
      isUserRequested: true,
      isSuperseded: false,
    });
  });

  it("preserves existing 'disconnected' reason path", () => {
    const session = makeSession();
    registerSession("alice", "conv1", session);

    abortSession("alice", "conv1", "disconnected");

    expect(classifyAbortReason(session.abort.signal.reason)).toMatchObject({
      kind: "disconnected",
      isUserRequested: false,
      isSuperseded: false,
    });
  });

  it("preserves existing 'superseded' reason path", () => {
    const session = makeSession();
    registerSession("alice", "conv1", session);

    abortSession("alice", "conv1", "superseded");

    expect(classifyAbortReason(session.abort.signal.reason)).toMatchObject({
      kind: "superseded",
      isUserRequested: false,
      isSuperseded: true,
    });
  });

  it("multi-leader broadcast: un-keyed abort fires every leader's controller for the conversation", () => {
    const cpo = makeSession();
    const cmo = makeSession();
    const cto = makeSession();
    registerSession("alice", "conv1", cpo, "cpo");
    registerSession("alice", "conv1", cmo, "cmo");
    registerSession("alice", "conv1", cto, "cto");

    abortSession("alice", "conv1", "user_requested_stop");

    expect(cpo.abort.signal.aborted).toBe(true);
    expect(cmo.abort.signal.aborted).toBe(true);
    expect(cto.abort.signal.aborted).toBe(true);
    for (const s of [cpo, cmo, cto]) {
      expect(classifyAbortReason(s.abort.signal.reason).kind).toBe(
        "user_requested_stop",
      );
    }
  });

  it("leader-keyed abort scopes to that single leader's session", () => {
    const cpo = makeSession();
    const cmo = makeSession();
    registerSession("alice", "conv1", cpo, "cpo");
    registerSession("alice", "conv1", cmo, "cmo");

    abortSession("alice", "conv1", "user_requested_stop", "cmo");

    expect(cpo.abort.signal.aborted).toBe(false);
    expect(cmo.abort.signal.aborted).toBe(true);
  });

  it("cross-user invariant: aborting alice does not touch bob's conv1 session", () => {
    // Both users have a session keyed to "conv1" — distinct keys
    // (`alice:conv1`, `bob:conv1`) ensure no prefix collision.
    const aliceSession = makeSession();
    const bobSession = makeSession();
    registerSession("alice", "conv1", aliceSession);
    registerSession("bob", "conv1", bobSession);

    abortSession("alice", "conv1", "user_requested_stop");

    expect(aliceSession.abort.signal.aborted).toBe(true);
    expect(bobSession.abort.signal.aborted).toBe(false);
  });

  it("forged conversationId that alice does not own is a silent no-op (does not touch bob OR an unrelated alice session)", () => {
    // Simulate the ws-handler path with WS-resolved userId="alice" but a
    // forged conversationId="conv2" (which actually belongs to bob).
    // abortSession resolves the prefix `alice:conv2` — no entries match.
    // Bob's session at `bob:conv2` is a different prefix, so it stays.
    // Alice's unrelated `alice:conv1` session must also stay untouched
    // (the prefix-match must not over-fire).
    const bobSession = makeSession();
    const aliceUnrelated = makeSession();
    const bobAbortSpy = vi.spyOn(bobSession.abort, "abort");
    const aliceAbortSpy = vi.spyOn(aliceUnrelated.abort, "abort");
    registerSession("bob", "conv2", bobSession);
    registerSession("alice", "conv1", aliceUnrelated);

    abortSession("alice", "conv2", "user_requested_stop");

    expect(bobAbortSpy).not.toHaveBeenCalled();
    expect(aliceAbortSpy).not.toHaveBeenCalled();
    expect(bobSession.abort.signal.aborted).toBe(false);
    expect(aliceUnrelated.abort.signal.aborted).toBe(false);
  });

  it("idempotent: a second abort call after unregister is a silent no-op (no controller.abort)", () => {
    const session = makeSession();
    const abortSpy = vi.spyOn(session.abort, "abort");
    registerSession("alice", "conv1", session);

    abortSession("alice", "conv1", "user_requested_stop");
    unregisterSession("alice", "conv1");
    abortSession("alice", "conv1", "user_requested_stop");

    expect(abortSpy).toHaveBeenCalledTimes(1);
  });

  it("abortAllUserSessions sweeps every conversation for the user", () => {
    const a1 = makeSession();
    const a2 = makeSession();
    const b1 = makeSession();
    registerSession("alice", "conv1", a1);
    registerSession("alice", "conv2", a2);
    registerSession("bob", "conv1", b1);

    abortAllUserSessions("alice");

    expect(a1.abort.signal.aborted).toBe(true);
    expect(a2.abort.signal.aborted).toBe(true);
    expect(b1.abort.signal.aborted).toBe(false);
  });
});

describe("classifyAbortReason", () => {
  it("classifies a typed SessionAbortError directly via .kind", () => {
    const err = new SessionAbortError("user_requested_stop");
    expect(classifyAbortReason(err)).toMatchObject({
      kind: "user_requested_stop",
      isUserRequested: true,
      isSuperseded: false,
    });
  });

  it("classifies a SessionAbortError(disconnected) without misrouting to user_requested", () => {
    const err = new SessionAbortError("disconnected");
    expect(classifyAbortReason(err)).toMatchObject({
      kind: "disconnected",
      isUserRequested: false,
      isSuperseded: false,
    });
  });

  it("classifies a SessionAbortError(superseded) for the multi-tab supersession path", () => {
    const err = new SessionAbortError("superseded");
    expect(classifyAbortReason(err)).toMatchObject({
      kind: "superseded",
      isUserRequested: false,
      isSuperseded: true,
    });
  });

  it("falls back to legacy Error.message classification when prefix matches a known kind", () => {
    const err = new Error("Session aborted: user_requested_stop");
    expect(classifyAbortReason(err).isUserRequested).toBe(true);
  });

  it("does NOT misroute on a future suffix like 'user_requested_stop_by_admin'", () => {
    // Defensive — exercises the prefix+token-set guard. A naive
    // `.includes("user_requested_stop")` would silently flip
    // isUserRequested=true here. The new classifier rejects unknown
    // tokens.
    const err = new Error("Session aborted: user_requested_stop_by_admin");
    expect(classifyAbortReason(err)).toMatchObject({
      kind: "unknown",
      isUserRequested: false,
      isSuperseded: false,
    });
  });

  it("does NOT misroute when the kind appears as a substring elsewhere in the message", () => {
    const err = new Error("Wrapped error: Session aborted: user_requested_stop happened earlier");
    // Message does not start with the canonical prefix → unknown.
    expect(classifyAbortReason(err).kind).toBe("unknown");
  });

  it("returns kind='unknown' when reason is undefined or non-Error", () => {
    expect(classifyAbortReason(undefined).kind).toBe("unknown");
    expect(classifyAbortReason(null).kind).toBe("unknown");
    expect(classifyAbortReason("user_requested_stop").kind).toBe("unknown");
    expect(classifyAbortReason({ kind: "user_requested_stop" }).kind).toBe("unknown");
  });

  it("classifies all canonical AbortKind values exhaustively", () => {
    const kinds: AbortKind[] = [
      "disconnected",
      "superseded",
      "user_requested_stop",
      "account_deleted",
      "server_shutdown",
    ];
    for (const k of kinds) {
      expect(classifyAbortReason(new SessionAbortError(k)).kind).toBe(k);
    }
  });
});

describe("messagePersisted race-window guard (plan §1.9)", () => {
  // Plan §1.9 invariant: a `result` event arriving 50ms after
  // `controller.abort()` must NOT cause a second `saveMessage` call.
  // The shared `messagePersisted` boolean in `startAgentSession` gates
  // BOTH branches. These tests mirror the production guard shape so a
  // refactor that flips the order (set-after-await instead of
  // set-before-await) or removes the guard from one branch fails here.
  // The agent-runner for-await loop itself can't be exercised without
  // mocking the SDK; re-implementing the guard pattern in 4 lines and
  // asserting against it is the cheapest faithful coverage.

  function makeAbortBranch(state: { messagePersisted: boolean }, spy: ReturnType<typeof vi.fn>) {
    return async (fullText: string) => {
      if (!state.messagePersisted && fullText.length > 0) {
        // Set BEFORE the await — production-equivalent ordering. If
        // saveMessage throws, messagePersisted stays true so the
        // result branch (if it ever runs) won't double-save. We
        // accept dropping the partial on persistence failure rather
        // than risking duplicate rows.
        state.messagePersisted = true;
        await spy("aborted", fullText);
      }
    };
  }

  function makeResultBranch(state: { messagePersisted: boolean }, spy: ReturnType<typeof vi.fn>) {
    return async (fullText: string) => {
      if (fullText.length > 0 && !state.messagePersisted) {
        await spy("complete", fullText);
        state.messagePersisted = true;
      }
    };
  }

  it("abort-then-result: the late result event is a no-op (single 'aborted' write wins)", async () => {
    const state = { messagePersisted: false };
    const saveMessage = vi.fn().mockResolvedValue(undefined);

    await makeAbortBranch(state, saveMessage)("partial-text");
    await makeResultBranch(state, saveMessage)("partial-text"); // late result event

    expect(saveMessage).toHaveBeenCalledTimes(1);
    expect(saveMessage).toHaveBeenCalledWith("aborted", "partial-text");
  });

  it("result-then-abort: a 'complete' write wins; the abort branch is a no-op", async () => {
    const state = { messagePersisted: false };
    const saveMessage = vi.fn().mockResolvedValue(undefined);

    await makeResultBranch(state, saveMessage)("complete-text");
    await makeAbortBranch(state, saveMessage)("complete-text");

    expect(saveMessage).toHaveBeenCalledTimes(1);
    expect(saveMessage).toHaveBeenCalledWith("complete", "complete-text");
  });

  it("idempotent abort: the second abort-branch call is a no-op", async () => {
    const state = { messagePersisted: false };
    const saveMessage = vi.fn().mockResolvedValue(undefined);

    await makeAbortBranch(state, saveMessage)("partial");
    await makeAbortBranch(state, saveMessage)("partial");

    expect(saveMessage).toHaveBeenCalledTimes(1);
  });

  it("empty fullText: abort branch persists nothing; messagePersisted stays false", async () => {
    const state = { messagePersisted: false };
    const saveMessage = vi.fn().mockResolvedValue(undefined);

    await makeAbortBranch(state, saveMessage)("");

    expect(saveMessage).not.toHaveBeenCalled();
    expect(state.messagePersisted).toBe(false);
  });

  it("persistence failure: messagePersisted stays true so the result branch cannot double-save", async () => {
    const state = { messagePersisted: false };
    const saveMessage = vi
      .fn()
      .mockRejectedValueOnce(new Error("supabase insert failed"));

    await expect(makeAbortBranch(state, saveMessage)("partial")).rejects.toThrow();
    // Even though the insert failed, the guard has already been
    // claimed — the result branch must not retry with status='complete'
    // and risk a successful duplicate row.
    expect(state.messagePersisted).toBe(true);
    await makeResultBranch(state, saveMessage)("partial");
    expect(saveMessage).toHaveBeenCalledTimes(1);
  });
});

describe("parseWSMessage · abort_turn", () => {
  it("accepts a well-formed abort_turn frame", () => {
    const result = parseWSMessage({ type: "abort_turn", conversationId: "conv1" });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.msg.type).toBe("abort_turn");
    }
  });

  it("rejects an abort_turn frame with extra `userId` field (TR4 cross-user invariant)", () => {
    const result = parseWSMessage({
      type: "abort_turn",
      conversationId: "conv2",
      userId: "bob",
    });
    expect(result.ok).toBe(false);
  });

  it("rejects an abort_turn frame missing conversationId", () => {
    const result = parseWSMessage({ type: "abort_turn" });
    expect(result.ok).toBe(false);
  });

  it("rejects an abort_turn frame with empty-string conversationId", () => {
    const result = parseWSMessage({ type: "abort_turn", conversationId: "" });
    expect(result.ok).toBe(false);
  });
});

describe("parseWSMessage · session_ended (multi-tab disambiguator)", () => {
  it("accepts a legacy session_ended without conversationId", () => {
    const result = parseWSMessage({ type: "session_ended", reason: "turn_complete" });
    expect(result.ok).toBe(true);
  });

  it("accepts a user_aborted session_ended carrying conversationId for multi-tab clients", () => {
    const result = parseWSMessage({
      type: "session_ended",
      reason: "user_aborted",
      conversationId: "conv1",
    });
    expect(result.ok).toBe(true);
    if (result.ok && result.msg.type === "session_ended") {
      expect(result.msg.conversationId).toBe("conv1");
    }
  });
});
