/**
 * The in-place email-code check for a founder legal acceptance (#12011 PR-C, ADR-319), plus the request guard both
 * legal-acceptance routes share. No Next.js imports: the routes wrap the plain `{status, body}` shapes returned here.
 *
 * The check proves the person at the keyboard can read the founder's mailbox right now. The code is sent and verified on
 * a THROWAWAY auth client (no cookies, no persisted session): verifying a code makes the auth service mint a session, and
 * the intent is bound to the founder's OWN web session id, so the minted one must never replace it. It is discarded and
 * revoked (`signOut({scope: "local"})`: the default scope is global and would end the founder's real sessions).
 *
 * Never logged or reported: the address, the code, the note, the text. Provider errors contribute a class only.
 */

import { createClient } from "@supabase/supabase-js";
import {
  isLegalCode,
  type LegalReauthSendResult,
  type LegalReauthVerifyResult,
} from "@/lib/legal-acceptance-wire";
import { reportLegalOp } from "@/server/approval/ops";
import { serverUrl } from "@/lib/supabase/service";
import { legalKindCopy } from "@/lib/legal-acceptance-copy";
import { boundedAuthGetSession, boundedAuthGetUser } from "@/server/request-auth";
import { isCurrent, KEY_RE, getLegalText, LegalTextError, type LegalTextEntry } from "./canonical";
import { claimAttempt, issueIntent, markVerified, type LegalRpcClient } from "./service";

// ── identity ─────────────────────────────────────────────────────────────────────────────────────────────────────

/** Decode the payload of a JWT that `getUser()` has ALREADY verified. Never used to establish identity on its own. */
function decodePayload(jwt: string): Record<string, unknown> | null {
  const parts = jwt.split(".");
  if (parts.length !== 3) return null;
  try {
    const padded = parts[1].replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - (parts[1].length % 4)) % 4);
    const v = JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
    return v && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

export interface TokenFacts {
  sub: string | null;
  /** Exactly what the SQL reads: `NULLIF(COALESCE(jwt->>'session_id', jwt->>'ses_id'), '')`. Null means absent. */
  sessionId: string | null;
  /** The audience claim when it is a plain string; anything else (an array, a missing claim) is null. */
  aud: string | null;
}

/**
 * `session_id`, else `ses_id` (a JSON null or a missing claim falls through; an empty string does NOT fall through, it
 * means absent, exactly like COALESCE then NULLIF). A number or boolean is its text, as `->>` returns it; an object or
 * array is treated as absent (the safe side: nothing is issued).
 */
export function tokenFacts(accessToken: string): TokenFacts {
  const p = decodePayload(accessToken);
  if (!p) return { sub: null, sessionId: null, aud: null };
  const raw = p.session_id ?? p.ses_id;
  let sessionId: string | null = null;
  if (typeof raw === "string") sessionId = raw === "" ? null : raw;
  else if (typeof raw === "number" || typeof raw === "boolean") sessionId = String(raw);
  return {
    sub: typeof p.sub === "string" ? p.sub : null,
    sessionId,
    aud: typeof p.aud === "string" ? p.aud : null,
  };
}

/** The slice of the user-context Supabase client the identity step uses. */
export interface IdentityClient {
  auth: {
    getUser(): Promise<{ data: { user: { id: string; email?: string | null } | null }; error: unknown }>;
    getSession(): Promise<{ data: { session: { access_token: string } | null }; error: unknown }>;
  };
}

export type Identity =
  | { ok: true; userId: string; email: string | null; sessionId: string }
  | { ok: false; status: 401 | 403; error: string };

/**
 * Founder id and email come from `getUser()` (checked by the auth service) on the user-context client only. The web
 * session id comes from the same session's access token. A runtime-audience token is refused: an agent-minted token
 * must never open an intent. An absent session id issues nothing.
 */
export async function resolveIdentity(supabase: IdentityClient, wrapperUserId: string): Promise<Identity> {
  const unauth: Identity = { ok: false, status: 401, error: "Unauthorized" };
  // Both reads are remote-capable legs of the auth service: the bounded helpers turn a stall or a throw into null (a 401).
  const user = (await boundedAuthGetUser(supabase))?.user ?? null;
  if (!user || user.id !== wrapperUserId) return unauth;

  const token = (await boundedAuthGetSession(supabase))?.session?.access_token;
  if (!token) return unauth;
  const facts = tokenFacts(token);
  if (facts.sub !== user.id) return unauth;
  if (facts.aud !== "authenticated") return { ok: false, status: 403, error: "Forbidden" };
  if (!facts.sessionId) return unauth;
  return { ok: true, userId: user.id, email: user.email ?? null, sessionId: facts.sessionId };
}

// ── per-user verify ceiling ──────────────────────────────────────────────────────────────────────────────────────

/**
 * Per-USER ceiling on code-verify calls, in addition to the 5 per challenge the database enforces. Without it a founder
 * (or a stolen session) could open challenges on many keys and multiply the guesses. 10 per 15 minutes per user: two full
 * challenges' worth of attempts, which no honest flow needs.
 *
 * IN-PROCESS and PER HOST: a restart, a deploy or a second host resets it, so it is a best-effort second fence. The
 * database counter (5 per challenge, claimed before the auth service is asked) stays the hard bound. Kept as its own
 * small class rather than `SlidingWindowCounter` (server/rate-limiter.ts) because that one reads `Date.now()` directly,
 * so the window could not be tested on an injected clock (it does have its own `prune()`). The clock and the store are
 * injectable here.
 */
export const VERIFY_CEILING_MAX = 10;
export const VERIFY_CEILING_WINDOW_MS = 15 * 60_000;

export class AttemptCeiling {
  private readonly hits: Map<string, number[]>;
  constructor(
    private readonly max: number = VERIFY_CEILING_MAX,
    private readonly windowMs: number = VERIFY_CEILING_WINDOW_MS,
    private readonly now: () => number = Date.now,
    store: Map<string, number[]> = new Map(),
  ) {
    this.hits = store;
  }

  /** Counts one attempt for `userId`; false (and not counted) once the ceiling is reached inside the window. */
  consume(userId: string): boolean {
    const t = this.now();
    const live = (this.hits.get(userId) ?? []).filter((x) => x > t - this.windowMs);
    if (live.length >= this.max) {
      this.hits.set(userId, live);
      return false;
    }
    live.push(t);
    this.hits.set(userId, live);
    if (this.hits.size > 5_000) this.sweep(t);
    return true;
  }

  private sweep(t: number): void {
    for (const [k, v] of this.hits) if (!v.some((x) => x > t - this.windowMs)) this.hits.delete(k);
  }
}

export const defaultVerifyCeiling = new AttemptCeiling();

// ── failed-send memory ───────────────────────────────────────────────────────────────────────────────────────────

/** How long a failed send is remembered: the life of the intent the database opened for it (30 minutes). */
export const SEND_FAILURE_TTL_MS = 30 * 60_000;

/**
 * Remembers, per user and key, that the last attempt to EMAIL the code failed after the intent was opened. The intent
 * stays live in the database, so a plain retry comes back `reused`, and a reused intent normally means "the earlier code
 * is still valid, send nothing". After a failed send no code exists, so that skip would claim a mail that never left.
 * While a failure is remembered a plain send mails again; a successful send forgets it.
 *
 * IN-PROCESS and PER HOST, like the ceiling: another host or a restart forgets it, and the dialog covers that case by
 * sending `resend:true` after any failed send. Both halves together make the false "sent" impossible in practice.
 */
export class SendFailureMemory {
  private readonly until = new Map<string, number>();
  constructor(private readonly now: () => number = Date.now) {}

  private k(userId: string, key: string): string {
    return `${userId}\u0000${key}`;
  }
  mark(userId: string, key: string): void {
    const t = this.now();
    this.until.set(this.k(userId, key), t + SEND_FAILURE_TTL_MS);
    if (this.until.size > 5_000) for (const [k, v] of this.until) if (v <= t) this.until.delete(k);
  }
  has(userId: string, key: string): boolean {
    const k = this.k(userId, key);
    const v = this.until.get(k);
    if (v === undefined) return false;
    if (v <= this.now()) {
      this.until.delete(k);
      return false;
    }
    return true;
  }
  clear(userId: string, key: string): void {
    this.until.delete(this.k(userId, key));
  }
}

export const defaultSendFailures = new SendFailureMemory();

// ── throwaway auth client ────────────────────────────────────────────────────────────────────────────────────────

export interface AuthErrorLike {
  status?: number;
  code?: string;
  name?: string;
}
/** The slice of a throwaway anon client the check uses. */
export interface ThrowawayAuthClient {
  auth: {
    signInWithOtp(a: { email: string; options: { shouldCreateUser: false } }): PromiseLike<{ error: AuthErrorLike | null }>;
    verifyOtp(a: { email: string; token: string; type: "email" }): PromiseLike<{ error: AuthErrorLike | null }>;
    signOut(a: { scope: "local" }): PromiseLike<{ error: AuthErrorLike | null }>;
  };
}

/** A fresh anon client with no cookies and no session persistence: nothing it does can touch the founder's session. */
export function createThrowawayAuthClient(): ThrowawayAuthClient {
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  // No empty-key fallback: a missing key must fail loudly into `unavailable` (reported), never build a half-configured client.
  if (!anonKey) throw new Error("auth anon key is not configured");
  return createClient(serverUrl(), anonKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  }) as unknown as ThrowawayAuthClient;
}

/** A class for Sentry: never a message (it can echo the address). */
function errorClass(err: unknown): string {
  if (!err || typeof err !== "object") return typeof err;
  const e = err as AuthErrorLike;
  return [e.name || "Error", e.status ?? "nostatus", e.code ?? "nocode"].join(":");
}

export interface ReauthDeps {
  service: LegalRpcClient;
  authClient: () => ThrowawayAuthClient;
  ceiling?: AttemptCeiling;
  sendFailures?: SendFailureMemory;
}

/**
 * Report one failed step: the stage and the error CLASS only (never a message, the address or the code). `warn` is for
 * states that are abnormal but not a failed founder action. `thrown` hands the caught value to the helper, which keeps
 * only its code, fn and class name.
 */
const reportFailed = (stage: string, err: unknown, userId: string, o: { level?: "warn"; thrown?: boolean } = {}): void =>
  reportLegalOp("reauthFailed", o.thrown ? err : null, {
    userId,
    ...(o.level ? { level: o.level } : {}),
    extra: { stage, errorClass: errorClass(err) },
  });

// ── send ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Open (or reuse) the intent, then email the code.
 *
 * - A REUSED intent without a resend means the earlier code is still valid: answer `sent` and send nothing (a second send
 *   inside the auth service's window would only trip its 429). EXCEPT when the earlier send FAILED (remembered in
 *   `SendFailureMemory`): then no code exists and the mail is attempted again.
 * - The auth service answers 422 `otp_disabled` for an address it does not know and 200 for one it does; both come back as
 *   the identical `{ok:true,state:"sent"}`. For a signed-in founder that 422 is abnormal, so it is reported at warn level
 *   (class only). Any OTHER 422 is a real failure.
 * - The auth service's 429 is `rate_limited` (the founder asked again too soon): not a fault, not reported.
 * - Anything else (network, 5xx) is `unavailable`, reported with its class only.
 */
export async function sendReauthCode(
  deps: ReauthDeps,
  a: { id: Extract<Identity, { ok: true }>; entry: LegalTextEntry; resend: boolean; now?: Date },
): Promise<LegalReauthSendResult> {
  if (!isCurrent(a.entry, a.now ?? new Date())) return { ok: false, reason: "replaced" };
  const issued = await issueIntent(deps.service, { userId: a.id.userId, entry: a.entry, sessionId: a.id.sessionId, resend: a.resend });
  if (issued.outcome === "already_recorded") return { ok: false, reason: "already_recorded" };
  if (issued.outcome === "rate_limited") return { ok: false, reason: "rate_limited" };
  const memory = deps.sendFailures ?? defaultSendFailures;
  const failedBefore = memory.has(a.id.userId, a.entry.key);
  if (issued.reused && !a.resend && !failedBefore) return { ok: true, state: "sent" };

  // Any failure from here on leaves a live intent with no code behind it: remember it so a plain retry mails again.
  const fail = (reason: "unavailable" | "rate_limited"): LegalReauthSendResult => {
    memory.mark(a.id.userId, a.entry.key);
    return { ok: false, reason };
  };
  const sent = (): LegalReauthSendResult => {
    memory.clear(a.id.userId, a.entry.key);
    return { ok: true, state: "sent" };
  };

  if (!a.id.email) {
    reportFailed("send_no_address", null, a.id.userId);
    return fail("unavailable");
  }
  try {
    const { error } = await deps.authClient().auth.signInWithOtp({ email: a.id.email, options: { shouldCreateUser: false } });
    if (!error) return sent();
    if (error.status === 429) return fail("rate_limited");
    if (error.status === 422) {
      if (error.code === OTP_DISABLED_CODE) {
        reportFailed("send_422", error, a.id.userId, { level: "warn" });
        return sent();
      }
      reportFailed("send", error, a.id.userId);
      return fail("unavailable");
    }
    reportFailed("send", error, a.id.userId);
    return fail("unavailable");
  } catch (err) {
    reportFailed("send", err, a.id.userId, { thrown: true });
    return fail("unavailable");
  }
}

/** The auth service's error code for "no such user / signups not allowed for otp" (`shouldCreateUser: false`). */
const OTP_DISABLED_CODE = "otp_disabled";

// ── verify ───────────────────────────────────────────────────────────────────────────────────────────────────────

/** ASCII digits only; the range is defined once in the wire module (6 in production, up to 8 in dev). */
export const CODE_RE = { test: isLegalCode };

/**
 * Verify the emailed code. Order is load-bearing: the attempt is counted in the database BEFORE the auth service is
 * asked, so a locked challenge never reaches the auth service and a guess is never free.
 */
export async function verifyReauthCode(
  deps: ReauthDeps,
  a: { id: Extract<Identity, { ok: true }>; entry: LegalTextEntry; code: string },
): Promise<LegalReauthVerifyResult> {
  // The client is built FIRST: a missing key fails into `unavailable` before an attempt is counted or claimed, so a
  // configuration fault never burns a founder's guesses.
  let client: ThrowawayAuthClient;
  try {
    client = deps.authClient();
  } catch (err) {
    reportFailed("verify_client", err, a.id.userId, { thrown: true });
    return { ok: false, reason: "unavailable" };
  }

  const ceiling = deps.ceiling ?? defaultVerifyCeiling;
  if (!ceiling.consume(a.id.userId)) return { ok: false, reason: "locked" };

  const claim = await claimAttempt(deps.service, { userId: a.id.userId, entry: a.entry, sessionId: a.id.sessionId });
  if (claim.outcome !== "allowed") {
    // not_found: no live intent for this session (reload, other browser): the card must be reopened, like a replaced one.
    return { ok: false, reason: claim.outcome === "not_found" ? "replaced" : claim.outcome };
  }

  if (!a.id.email) {
    reportFailed("verify_no_address", null, a.id.userId);
    return { ok: false, reason: "unavailable" };
  }

  let error: AuthErrorLike | null;
  try {
    ({ error } = await client.auth.verifyOtp({ email: a.id.email, token: a.code, type: "email" }));
  } catch (err) {
    await discard(client, a.id.userId);
    reportFailed("verify", err, a.id.userId, { thrown: true });
    return { ok: false, reason: "unavailable" };
  }

  if (error) {
    await discard(client, a.id.userId);
    // The auth service answers a wrong or expired code with 403. A 400/422 means the code was not even well formed for
    // it (our own check passed): the founder is told it was wrong, and the event shows the budget is being spent on it.
    if (error.status === 403) return { ok: false, reason: "wrong_code" };
    if (error.status === 400 || error.status === 422) {
      reportFailed("verify_rejected", error, a.id.userId, { level: "warn" });
      return { ok: false, reason: "wrong_code" };
    }
    reportFailed("verify", error, a.id.userId);
    return { ok: false, reason: "unavailable" };
  }

  // The throwaway session is revoked in parallel with the mark. `discard` never throws, so a failed revoke cannot turn a
  // good check into an error, and a throwing mark still leaves the revoke running.
  const [, marked] = await Promise.all([
    discard(client, a.id.userId),
    markVerified(deps.service, { userId: a.id.userId, eventId: claim.eventId, entry: a.entry, sessionId: a.id.sessionId }),
  ]);
  if (marked === "verified") return { ok: true };
  if (marked === "not_claimed") {
    reportFailed("mark_not_claimed", null, a.id.userId);
    return { ok: false, reason: "unavailable" };
  }
  return { ok: false, reason: marked === "not_found" ? "replaced" : marked };
}

/** Revoke the session the auth service minted for the throwaway client. Always runs; a failure is reported, NEVER thrown. */
async function discard(client: ThrowawayAuthClient, userId: string): Promise<void> {
  try {
    const { error } = await client.auth.signOut({ scope: "local" });
    if (error) reportFailed("discard", error, userId);
  } catch (err) {
    try {
      reportFailed("discard", err, userId, { thrown: true });
    } catch {
      // Observability must never turn a good check into a throw.
    }
  }
}

// ── request guard shared by both routes ──────────────────────────────────────────────────────────────────────────

export type Guarded =
  | { ok: true; key: string; entry: LegalTextEntry; body: Record<string, unknown>; id: Extract<Identity, { ok: true }> }
  | { ok: false; status: number; error: string };

/** The key segment of `/api/legal-acceptance/<key>/<action>` (the rate-limit wrapper does not thread Next's params). */
export function keyFromUrl(url: string): string {
  return new URL(url).pathname.split("/").filter(Boolean).at(-2) ?? "";
}

/** Largest request body either route reads: a note is at most 1000 characters, so 8 KiB is generous. */
export const MAX_BODY_BYTES = 8 * 1024;

/**
 * The request body as text, or null when it is over `max` bytes. A declared Content-Length over the cap is refused without
 * reading; otherwise the stream is read chunk by chunk and cancelled the moment the cap is crossed, so an undeclared
 * (chunked) body cannot be buffered whole before the check.
 */
export async function readCappedBody(req: Request, max: number): Promise<string | null> {
  const declared = Number(req.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > max) return null;
  if (!req.body) return "";
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel().catch(() => undefined);
      return null;
    }
    chunks.push(value);
  }
  return Buffer.concat(chunks).toString("utf8");
}

export interface GuardDeps {
  supabase: IdentityClient;
  isEnabled: (userId: string) => Promise<boolean>;
}

/**
 * Everything both routes check before touching a challenge, in this order: surface (founder id), key, content type, body, identity.
 * Surface off (founder id unset or malformed, or not the founder), a malformed key, an unknown key and a key with no declared card kind are all the same 404 (no oracle for which keys exist).
 */
export async function guardLegalRequest(req: Request, userId: string, deps: GuardDeps): Promise<Guarded> {
  if (!(await deps.isEnabled(userId))) return { ok: false, status: 404, error: "Not found" };

  const key = keyFromUrl(req.url);
  if (!KEY_RE.test(key)) return { ok: false, status: 404, error: "Not found" };
  let entry: LegalTextEntry;
  try {
    entry = getLegalText(key);
  } catch (err) {
    if (err instanceof LegalTextError && err.code === "unknown_key") return { ok: false, status: 404, error: "Not found" };
    throw err;
  }
  // A registered text with no declared card kind has no wording and no card (CTO ruling 2026-11-07, no default): the same
  // oracle-free 404. No Sentry here; the page reports it (kind_undeclared) once the surface gate has passed.
  if (legalKindCopy(key) === null) return { ok: false, status: 404, error: "Not found" };

  if (!/^application\/json(\s*;|$)/i.test(req.headers.get("content-type") ?? "")) {
    return { ok: false, status: 415, error: "Content-Type must be application/json" };
  }
  const text = await readCappedBody(req, MAX_BODY_BYTES);
  if (text === null) return { ok: false, status: 413, error: "Payload too large" };
  let body: unknown = null;
  try {
    body = JSON.parse(text);
  } catch {
    body = null;
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) return { ok: false, status: 400, error: "Invalid body" };

  const id = await resolveIdentity(deps.supabase, userId);
  if (!id.ok) return { ok: false, status: id.status, error: id.error };
  return { ok: true, key, entry, body: body as Record<string, unknown>, id };
}
