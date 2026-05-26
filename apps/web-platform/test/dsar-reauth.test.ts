import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// Phase 3 unit tests for `apps/web-platform/server/dsar-reauth.ts` —
// step-up reauthentication helpers per plan rev-2 FR2 + AC3 + AC21 +
// AC27.
//
// Design (per plan rev-2 + Q1 substrate (b) — single-instance Hetzner
// per `rate-limiter.ts:255-262`):
//   - `issueReauthEvent({userId, sessionId, authTime?})` → { eventId }
//     mints a single-use UUID, stores `{userId, sessionId, authTime,
//     issuedAt}` in an in-process Map. Time-of-issuance is `now()`.
//   - `consumeReauthEvent({eventId, expectedUserId, expectedSessionId})`
//     looks up + validates: present, ≤5min old since issuance, userId
//     match, sessionId match, OAuth `authTime` claim ≤300s old when
//     supplied. Atomically deletes (single-use). Returns the stored
//     event on success; throws `ReauthEventInvalid` on every failure
//     mode with a discriminating `reason`.
//   - `requireFreshReauth(req)` reads `x-reauth-event` header (or body
//     `reauth_event_id` for POST), pulls userId+sessionId from the
//     active Supabase session via `createClient().auth.getUser()`, and
//     consumes. Returns `{userId, sessionId}` on success. Throws
//     `ReauthEventInvalid` on any failure.
//
// AC27: `auth_time` claim ≤300s for OAuth flows. Defends against IdPs
// that silently ignore `prompt=login`. When `authTime` is `undefined`
// (password re-entry — the server just verified the password directly),
// the claim is not validated.

import {
  issueReauthEvent,
  consumeReauthEvent,
  ReauthEventInvalid,
  __resetReauthStoreForTests,
} from "../server/dsar-reauth";

const USER_A = "11111111-1111-1111-1111-111111111111";
const USER_B = "22222222-2222-2222-2222-222222222222";
const SESSION_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const SESSION_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";

describe("issueReauthEvent", () => {
  beforeEach(() => {
    __resetReauthStoreForTests();
  });

  it("returns a UUID-shaped eventId", () => {
    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
    });
    expect(eventId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    );
  });

  it("mints distinct eventIds across calls", () => {
    const a = issueReauthEvent({ userId: USER_A, sessionId: SESSION_A });
    const b = issueReauthEvent({ userId: USER_A, sessionId: SESSION_A });
    expect(a.eventId).not.toBe(b.eventId);
  });
});

describe("consumeReauthEvent — happy path", () => {
  beforeEach(() => {
    __resetReauthStoreForTests();
  });

  it("returns the event when userId + sessionId match and within 5min", () => {
    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
    });
    const consumed = consumeReauthEvent({
      eventId,
      expectedUserId: USER_A,
      expectedSessionId: SESSION_A,
    });
    expect(consumed.userId).toBe(USER_A);
    expect(consumed.sessionId).toBe(SESSION_A);
  });
});

describe("consumeReauthEvent — failure modes", () => {
  beforeEach(() => {
    __resetReauthStoreForTests();
    vi.useRealTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("throws when eventId is unknown", () => {
    expect(() =>
      consumeReauthEvent({
        eventId: "ffffffff-ffff-ffff-ffff-ffffffffffff",
        expectedUserId: USER_A,
        expectedSessionId: SESSION_A,
      }),
    ).toThrow(ReauthEventInvalid);
    try {
      consumeReauthEvent({
        eventId: "ffffffff-ffff-ffff-ffff-ffffffffffff",
        expectedUserId: USER_A,
        expectedSessionId: SESSION_A,
      });
    } catch (err) {
      expect(err).toBeInstanceOf(ReauthEventInvalid);
      expect((err as ReauthEventInvalid).reason).toBe("not_found");
    }
  });

  it("throws when userId mismatches", () => {
    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
    });
    try {
      consumeReauthEvent({
        eventId,
        expectedUserId: USER_B,
        expectedSessionId: SESSION_A,
      });
      throw new Error("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ReauthEventInvalid);
      expect((err as ReauthEventInvalid).reason).toBe("user_mismatch");
    }
  });

  it("throws when sessionId mismatches", () => {
    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
    });
    try {
      consumeReauthEvent({
        eventId,
        expectedUserId: USER_A,
        expectedSessionId: SESSION_B,
      });
      throw new Error("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ReauthEventInvalid);
      expect((err as ReauthEventInvalid).reason).toBe("session_mismatch");
    }
  });

  it("is single-use — second consume throws not_found", () => {
    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
    });
    consumeReauthEvent({
      eventId,
      expectedUserId: USER_A,
      expectedSessionId: SESSION_A,
    });
    try {
      consumeReauthEvent({
        eventId,
        expectedUserId: USER_A,
        expectedSessionId: SESSION_A,
      });
      throw new Error("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ReauthEventInvalid);
      expect((err as ReauthEventInvalid).reason).toBe("not_found");
    }
  });

  it("throws expired when event is older than 5 min", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-05-12T10:00:00Z"));

    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
    });

    // 5 min + 1 sec later
    vi.setSystemTime(new Date("2026-05-12T10:05:01Z"));

    try {
      consumeReauthEvent({
        eventId,
        expectedUserId: USER_A,
        expectedSessionId: SESSION_A,
      });
      throw new Error("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ReauthEventInvalid);
      expect((err as ReauthEventInvalid).reason).toBe("expired");
    }
  });

  // AC27 — OAuth `auth_time` claim validation.
  // Defends against IdPs that silently ignore `prompt=login`. The
  // `authTime` is the JWT `auth_time` claim captured at issuance from
  // the IdP; a stale value indicates the IdP did not honour the
  // re-auth request.
  it("throws auth_time_stale when OAuth authTime is older than 300s", () => {
    vi.useFakeTimers();
    const now = new Date("2026-05-12T10:00:00Z");
    vi.setSystemTime(now);

    // authTime is 301s in the past — IdP returned a stale claim.
    const stale = Math.floor(now.getTime() / 1000) - 301;
    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
      authTime: stale,
    });

    try {
      consumeReauthEvent({
        eventId,
        expectedUserId: USER_A,
        expectedSessionId: SESSION_A,
      });
      throw new Error("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ReauthEventInvalid);
      expect((err as ReauthEventInvalid).reason).toBe("auth_time_stale");
    }
  });

  it("accepts a fresh OAuth authTime within 300s", () => {
    vi.useFakeTimers();
    const now = new Date("2026-05-12T10:00:00Z");
    vi.setSystemTime(now);

    const fresh = Math.floor(now.getTime() / 1000) - 60;
    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
      authTime: fresh,
    });

    const consumed = consumeReauthEvent({
      eventId,
      expectedUserId: USER_A,
      expectedSessionId: SESSION_A,
    });
    expect(consumed.userId).toBe(USER_A);
  });

  it("does not validate authTime when undefined (password re-entry path)", () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-05-12T10:00:00Z"));

    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
      // no authTime supplied — server just verified the password
    });

    const consumed = consumeReauthEvent({
      eventId,
      expectedUserId: USER_A,
      expectedSessionId: SESSION_A,
    });
    expect(consumed.userId).toBe(USER_A);
  });
});

describe("consumeReauthEvent — drop on failed consume", () => {
  beforeEach(() => {
    __resetReauthStoreForTests();
  });

  // Single-use is the security primitive; a mismatched-but-known-eventId
  // attempt MUST burn the event so the attacker cannot brute-force the
  // session binding by retrying with different session/user IDs.
  it("burns the event on user_mismatch (no retry possible)", () => {
    const { eventId } = issueReauthEvent({
      userId: USER_A,
      sessionId: SESSION_A,
    });

    try {
      consumeReauthEvent({
        eventId,
        expectedUserId: USER_B, // wrong
        expectedSessionId: SESSION_A,
      });
    } catch {
      // expected
    }

    // Even with the correct expectedUserId, the event is gone.
    try {
      consumeReauthEvent({
        eventId,
        expectedUserId: USER_A,
        expectedSessionId: SESSION_A,
      });
      throw new Error("should have thrown");
    } catch (err) {
      expect(err).toBeInstanceOf(ReauthEventInvalid);
      expect((err as ReauthEventInvalid).reason).toBe("not_found");
    }
  });
});
