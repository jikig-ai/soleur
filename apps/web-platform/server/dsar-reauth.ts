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
import type { SupabaseClient } from "@supabase/supabase-js";

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
 * Returns the consumed event PLUS the eventId itself so downstream
 * callers (e.g., `enqueueExport`) can persist the actual UUID rather
 * than a placeholder string (fixes a P1 from security-sentinel review
 * where `"consumed-via-body"` was passed through to a `uuid` column
 * and threw on every body-mode reauth call).
 *
 * Throws `ReauthEventInvalid` on any failure mode (missing event id,
 * missing session, mismatch, expired). Caller is responsible for
 * mapping to a 401/403 response.
 */
export async function requireFreshReauth(req: Request): Promise<{
  userId: string;
  sessionId: string;
  eventId: string;
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
  const { userId, sessionId } = await getActiveSessionId(supabase);

  const consumed = consumeReauthEvent({
    eventId,
    expectedUserId: userId,
    expectedSessionId: sessionId,
  });

  return { userId: consumed.userId, sessionId: consumed.sessionId, eventId };
}

/**
 * Resolve the active Supabase session's `session_id` claim from the
 * access token's JWT payload. The Supabase JS Session object does NOT
 * expose `session_id` as a top-level field — the value lives inside
 * the JWT claims (`session_id` / `ses_id`). Earlier code cast the
 * Session object to `{ session_id?: string }` and silently fell back
 * to `user.id` when the cast resolved to `undefined`, defeating the
 * AC5 session-bind defence (per code-review P1 from security-sentinel
 * on PR #3634).
 *
 * Throws `ReauthEventInvalid("not_found")` when no session is active
 * OR the JWT is missing the claim — fail-loud rather than degrade to
 * user-bind.
 */
export async function getActiveSessionId(
  supabase: SupabaseClient,
): Promise<{ userId: string; sessionId: string }> {
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) {
    throw new ReauthEventInvalid("not_found");
  }
  const { data: sessionData } = await supabase.auth.getSession();
  const accessToken = sessionData?.session?.access_token;
  if (!accessToken) {
    throw new ReauthEventInvalid("not_found");
  }
  const claims = decodeAccessTokenClaims(accessToken);
  const sessionId = claims?.session_id ?? claims?.ses_id;
  if (!sessionId || typeof sessionId !== "string") {
    throw new ReauthEventInvalid("not_found");
  }
  return { userId: userData.user.id, sessionId };
}

interface AccessTokenSessionClaims {
  session_id?: string;
  ses_id?: string;
}

function decodeAccessTokenClaims(jwt: string): AccessTokenSessionClaims | null {
  try {
    const payload = jwt.split(".")[1];
    if (!payload) return null;
    const decoded = Buffer.from(
      payload.replace(/-/g, "+").replace(/_/g, "/"),
      "base64",
    ).toString("utf-8");
    return JSON.parse(decoded) as AccessTokenSessionClaims;
  } catch {
    return null;
  }
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
