// DSAR step-up reauthentication helpers — Phase 3 of
// feat-dsar-art15-export-endpoint (issue #3637, plan rev-2).
//
// Plan FR2 + AC3 + AC21 + AC27. Greenfield per R9.
//
// In-process Map storage matches Q1 substrate (b) — single-instance
// Hetzner per `rate-limiter.ts:255-262`. The same single-instance
// constraint that bounds the DSAR worker poller and the
// SlidingWindowCounter rate-limiter applies here; all three migrate
// together when infrastructure scales.
//
// Defense-in-depth properties:
//   - Single-use: every consume() deletes the event regardless of
//     mismatch outcome. Mismatched-userId/sessionId attempts BURN the
//     event so an attacker holding a known eventId cannot brute-force
//     the session/user binding.
//   - 5-min issuance TTL: bounds the window between reauth and
//     downstream POST.
//   - OAuth `auth_time` claim ≤300s: AC27 — defends against IdPs that
//     silently ignore `prompt=login`. Captured at issuance from the
//     Supabase JWT and re-checked at consume against `now()`.

import { randomUUID } from "node:crypto";
import { createClient } from "@/lib/supabase/server";

const REAUTH_TTL_MS = 5 * 60 * 1000; // 5 min — issuance-to-consume window
const OAUTH_AUTH_TIME_MAX_AGE_S = 300; // AC27 — IdP auth_time claim ceiling

interface StoredReauthEvent {
  userId: string;
  sessionId: string;
  authTime?: number; // epoch seconds, OAuth path only
  issuedAt: number; // epoch ms (Date.now())
}

interface IssueReauthEventInput {
  userId: string;
  sessionId: string;
  /**
   * OAuth `auth_time` claim from the JWT — epoch seconds. Omit for
   * password re-entry (server just verified the password directly,
   * AC27 only applies to OAuth flows that may silently ignore
   * `prompt=login`).
   */
  authTime?: number;
}

interface ConsumeReauthEventInput {
  eventId: string;
  expectedUserId: string;
  expectedSessionId: string;
}

export interface ReauthEvent {
  userId: string;
  sessionId: string;
  authTime?: number;
}

export type ReauthInvalidReason =
  | "not_found"
  | "expired"
  | "user_mismatch"
  | "session_mismatch"
  | "auth_time_stale";

export class ReauthEventInvalid extends Error {
  readonly name = "ReauthEventInvalid";
  readonly reason: ReauthInvalidReason;

  constructor(reason: ReauthInvalidReason, message?: string) {
    super(message ?? `reauth event invalid: ${reason}`);
    this.reason = reason;
  }
}

const store = new Map<string, StoredReauthEvent>();

export function issueReauthEvent(input: IssueReauthEventInput): {
  eventId: string;
} {
  const eventId = randomUUID();
  store.set(eventId, {
    userId: input.userId,
    sessionId: input.sessionId,
    authTime: input.authTime,
    issuedAt: Date.now(),
  });
  return { eventId };
}

export function consumeReauthEvent(
  input: ConsumeReauthEventInput,
): ReauthEvent {
  const event = store.get(input.eventId);
  if (!event) {
    throw new ReauthEventInvalid("not_found");
  }

  // Burn the event FIRST. Single-use is the security primitive — a
  // mismatched-but-known-eventId attempt MUST burn so the attacker
  // cannot brute-force session/user binding by retrying.
  store.delete(input.eventId);

  const ageMs = Date.now() - event.issuedAt;
  if (ageMs > REAUTH_TTL_MS) {
    throw new ReauthEventInvalid("expired");
  }

  if (event.userId !== input.expectedUserId) {
    throw new ReauthEventInvalid("user_mismatch");
  }

  if (event.sessionId !== input.expectedSessionId) {
    throw new ReauthEventInvalid("session_mismatch");
  }

  if (event.authTime !== undefined) {
    const nowS = Math.floor(Date.now() / 1000);
    if (nowS - event.authTime > OAUTH_AUTH_TIME_MAX_AGE_S) {
      throw new ReauthEventInvalid("auth_time_stale");
    }
  }

  return {
    userId: event.userId,
    sessionId: event.sessionId,
    authTime: event.authTime,
  };
}

/**
 * Route helper: extract the reauth event id from a request, resolve
 * the active Supabase user + session, and consume.
 *
 * Per AC21 — auth-gate enumeration tests recognise this primitive so
 * a future route under `app/api/account/export/*` that omits it is
 * caught by CI.
 *
 * Throws `ReauthEventInvalid` on any failure mode (missing event id,
 * missing session, mismatch, expired). Caller is responsible for
 * mapping to a 401/403 response.
 */
export async function requireFreshReauth(req: Request): Promise<{
  userId: string;
  sessionId: string;
}> {
  const headerEventId = req.headers.get("x-reauth-event");
  let eventId = headerEventId ?? "";

  if (!eventId && req.method !== "GET" && req.method !== "HEAD") {
    // Fall back to JSON body { reauth_event_id }.
    try {
      const cloned = req.clone();
      const body = (await cloned.json()) as { reauth_event_id?: unknown };
      if (typeof body?.reauth_event_id === "string") {
        eventId = body.reauth_event_id;
      }
    } catch {
      // Body is not JSON — leave eventId empty; will throw below.
    }
  }

  if (!eventId) {
    throw new ReauthEventInvalid("not_found");
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data?.user) {
    throw new ReauthEventInvalid("not_found");
  }

  const { data: sessionData } = await supabase.auth.getSession();
  const sessionId = sessionData?.session?.user?.id
    ? // The Supabase session object has no first-class session id; we
      // bind to the access-token's `session_id` claim as Supabase
      // documents it. When unavailable, fall back to the user id so
      // the binding is at least scoped to the user (not anyone with
      // the eventId).
      (sessionData.session as unknown as { session_id?: string }).session_id ??
      data.user.id
    : data.user.id;

  return consumeReauthEvent({
    eventId,
    expectedUserId: data.user.id,
    expectedSessionId: sessionId,
  });
}

/**
 * Test-only escape hatch: clears the in-process store between unit
 * tests so cross-test contamination cannot occur. Underscore-prefixed
 * + `ForTests` suffix per house convention; intentionally exported so
 * the test file can call it without the test reaching into module
 * internals.
 */
export function __resetReauthStoreForTests(): void {
  store.clear();
}
