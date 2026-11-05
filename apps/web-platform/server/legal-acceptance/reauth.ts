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
import type { LegalReauthSendResult, LegalReauthVerifyResult } from "@/lib/legal-acceptance-wire";
import { reportLegalOp } from "@/server/approval/ops";
import { serverUrl } from "@/lib/supabase/service";
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
    getUser(): PromiseLike<{ data: { user: { id: string; email?: string | null } | null }; error: unknown }>;
    getSession(): PromiseLike<{ data: { session: { access_token: string } | null } }>;
  };
}

export type Identity =
  | { ok: true; userId: string; email: string | null; sessionId: string }
  | { ok: false; status: 401 | 403; error: string };

/**
 * Founder id and email come from `getUser()` (verified by the auth service) on the user-context client only. The web
 * session id comes from the same session's access token. A runtime-audience token is refused: an agent-minted token
 * must never open an intent. An absent session id issues nothing.
 */
export async function resolveIdentity(supabase: IdentityClient, wrapperUserId: string): Promise<Identity> {
  const unauth: Identity = { ok: false, status: 401, error: "Unauthorized" };
  let user: { id: string; email?: string | null } | null;
  try {
    const res = await supabase.auth.getUser();
    user = res.error ? null : res.data.user;
  } catch {
    return unauth;
  }
  if (!user || user.id !== wrapperUserId) return unauth;

  let token: string | undefined;
  try {
    token = (await supabase.auth.getSession()).data.session?.access_token;
  } catch {
    return unauth;
  }
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
 * challenges' worth of attempts, which no honest flow needs. In-process and per host (best effort: a restart or a second
 * host resets it); the database counter stays the hard bound per challenge. The clock and the store are injectable.
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
  return createClient(serverUrl(), process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "", {
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
}

const reportFailed = (stage: string, err: unknown, userId: string): void =>
  reportLegalOp("reauthFailed", null, { userId, extra: { stage, errorClass: errorClass(err) } });

// ── send ─────────────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Open (or reuse) the intent, then email the code. The auth service answers 422 for an address it does not know and 200
 * for one it does; both come back as the identical `{ok:true,state:"sent"}` here. A real failure (network, 5xx, 429) is
 * `unavailable` and is reported with its class only.
 */
export async function sendReauthCode(
  deps: ReauthDeps,
  a: { id: Extract<Identity, { ok: true }>; entry: LegalTextEntry; resend: boolean; now?: Date },
): Promise<LegalReauthSendResult> {
  if (!isCurrent(a.entry, a.now ?? new Date())) return { ok: false, reason: "replaced" };
  const issued = await issueIntent(deps.service, { userId: a.id.userId, entry: a.entry, sessionId: a.id.sessionId, resend: a.resend });
  if (issued.outcome === "already_recorded") return { ok: false, reason: "already_recorded" };
  if (issued.outcome === "rate_limited") return { ok: false, reason: "rate_limited" };

  if (!a.id.email) {
    reportFailed("send_no_address", null, a.id.userId);
    return { ok: false, reason: "unavailable" };
  }
  try {
    const { error } = await deps.authClient().auth.signInWithOtp({ email: a.id.email, options: { shouldCreateUser: false } });
    if (!error || error.status === 422) return { ok: true, state: "sent" };
    reportFailed("send", error, a.id.userId);
    return { ok: false, reason: "unavailable" };
  } catch (err) {
    reportFailed("send", err, a.id.userId);
    return { ok: false, reason: "unavailable" };
  }
}

// ── verify ───────────────────────────────────────────────────────────────────────────────────────────────────────

export const CODE_RE = /^[0-9]{6,8}$/;

/**
 * Verify the emailed code. Order is load-bearing: the attempt is counted in the database BEFORE the auth service is
 * asked, so a locked challenge never reaches the auth service and a guess is never free.
 */
export async function verifyReauthCode(
  deps: ReauthDeps,
  a: { id: Extract<Identity, { ok: true }>; entry: LegalTextEntry; code: string },
): Promise<LegalReauthVerifyResult> {
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

  const client = deps.authClient();
  let error: AuthErrorLike | null;
  try {
    ({ error } = await client.auth.verifyOtp({ email: a.id.email, token: a.code, type: "email" }));
  } catch (err) {
    await discard(client, a.id.userId);
    reportFailed("verify", err, a.id.userId);
    return { ok: false, reason: "unavailable" };
  }
  await discard(client, a.id.userId);

  if (error) {
    // The auth service answers a wrong or expired code with 403 (and 400/422 for a malformed one).
    if (error.status === 400 || error.status === 403 || error.status === 422) return { ok: false, reason: "wrong_code" };
    reportFailed("verify", error, a.id.userId);
    return { ok: false, reason: "unavailable" };
  }

  const marked = await markVerified(deps.service, { userId: a.id.userId, eventId: claim.eventId, entry: a.entry, sessionId: a.id.sessionId });
  if (marked === "verified") return { ok: true };
  if (marked === "not_claimed") {
    reportFailed("mark_not_claimed", null, a.id.userId);
    return { ok: false, reason: "unavailable" };
  }
  return { ok: false, reason: marked === "not_found" ? "replaced" : marked };
}

/** Revoke the session the auth service minted for the throwaway client. Always runs; a failure is reported, never thrown. */
async function discard(client: ThrowawayAuthClient, userId: string): Promise<void> {
  try {
    const { error } = await client.auth.signOut({ scope: "local" });
    if (error) reportFailed("discard", error, userId);
  } catch (err) {
    reportFailed("discard", err, userId);
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

export interface GuardDeps {
  supabase: IdentityClient;
  isEnabled: (userId: string) => Promise<boolean>;
}

/**
 * Everything both routes check before touching a challenge, in this order: flag, key, content type, body, identity.
 * Flag off, a malformed key and an unknown key are all the same 404 (no oracle for which keys exist).
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

  if (!/^application\/json(\s*;|$)/i.test(req.headers.get("content-type") ?? "")) {
    return { ok: false, status: 415, error: "Content-Type must be application/json" };
  }
  const body = (await req.json().catch(() => null)) as unknown;
  if (!body || typeof body !== "object" || Array.isArray(body)) return { ok: false, status: 400, error: "Invalid body" };

  const id = await resolveIdentity(deps.supabase, userId);
  if (!id.ok) return { ok: false, status: id.status, error: id.error };
  return { ok: true, key, entry, body: body as Record<string, unknown>, id };
}
