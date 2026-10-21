// Schedule-reminder emit route — arms the generic reminder primitive.
//
// POST /api/internal/schedule-reminder validates an allowlisted reminder
// `action` and emits a `reminder.scheduled` event with a FUTURE delivery `ts`
// (Date.parse(fire_at)) via the app's already-wired Inngest client. The
// event-scheduled-reminder.ts handler fires at `ts`. This is what lets a
// future-dated comment / registered check schedule WITHOUT a per-reminder
// deploy — only the one-time function deploy.
//
// Authentication: the SAME fail-closed shared secret as trigger-cron
// (INNGEST_MANUAL_TRIGGER_SECRET, Doppler-provisioned, length-guarded
// constant-time timingSafeEqual). The secret IS the trust boundary; a
// secret-holder gains the same capability the operator already has via
// `gh issue comment` / a registered check — time-delayed. The allowlist
// (validateReminderAction) bounds the action to issue-comment | named-check;
// no issue close/edit/label mutation in v1. Same CSRF-exempt class as
// trigger-cron / kb-drift-ingest (cookieless, not browser-reachable).

import { NextResponse } from "next/server";
import { reportSilentFallback } from "@/server/observability";
import {
  readInternalBearerSecret,
  bearerMatches,
} from "@/lib/internal-auth";
import { sendInngestWithRetry } from "@/server/inngest/send-with-retry";
import {
  validateReminderAction,
  isValidIsoInstant,
} from "@/lib/inngest/scheduled-reminder-action";

// NOTE: the Inngest client is imported DYNAMICALLY inside POST (mirrors
// trigger-cron/route.ts) — defers the client's fail-closed throw (missing
// INNGEST_SIGNING_KEY) to request time and keeps the route importable during
// `next build` page-data collection.

const MAX_BODY_BYTES = 64 * 1024;

// Cutover quiesce (#5450, Phase 2.1): during the SQLite→Postgres+Redis cutover
// window the operator sets INNGEST_CUTOVER_QUIESCE=1 in Doppler prd so NO new
// reminder is armed into the doomed old SQLite mid-cutover (spec-flow P0-2).
// Authenticated callers get a 503 + Retry-After and retry after the window;
// the operator unsets the flag in Phase 2.6. Strict truthy check ("1"/"true").
function isCutoverQuiesced(): boolean {
  const v = process.env.INNGEST_CUTOVER_QUIESCE;
  return v === "1" || v === "true";
}

// Both 503s carry X-Soleur-Unavailable so a consumer (inngest-rearm-reminders.sh) can tell
// "operator paused arming" from "the backend is not listening". Retry-After is a poll hint,
// not the window length.
const RETRY_AFTER_S = "120";

// inngest.send surfaces a transport failure as TypeError("fetch failed") with the errno/TLS code on
// `cause` (refusal measured on inngest 3.54.2; TLS codes surface the same way from undici) — match the
// code, never message text. Every code here means "the scheduler is not reachable / not verifiable right
// now", so the caller must re-arm (inngest-rearm-reminders.sh aborts on the `backend-refused` 503 instead
// of continuing past a lost arm). The event carries `id: reminderId`, so a re-arm after an ambiguous failure
// (a reset or timeout AFTER the request left may have been persisted) is deduplicated by Inngest rather than
// armed twice. The set:
//   ECONNREFUSED                  the cutover window after op=quiesce-web, or a restart;
//   ETIMEDOUT, UND_ERR_CONNECT_TIMEOUT, ECONNRESET, UND_ERR_SOCKET   a host replace / restart, or a listener
//                                 or pooled socket that dropped the connection;
//   EHOSTUNREACH, ENETUNREACH     the private-net peer gone while a replaced host comes up;
//   ERR_TLS_*, and the certificate-verification codes (DEPTH_ZERO_SELF_SIGNED_CERT, SELF_SIGNED_CERT_IN_CHAIN,
//   UNABLE_TO_VERIFY_LEAF_SIGNATURE, UNABLE_TO_GET_ISSUER_CERT_LOCALLY, CERT_HAS_EXPIRED)   the verified-TLS
//                                 link (#10136) failing verification (pinned CA missing, wrong or expired).
// The verification codes are the SAME list the host canary's negative control accepts as "verification failed"
// (INNGEST_LINK_CANARY_NEG in apps/web-platform/infra/ci-deploy.sh); the route test derives them from that
// regex, so the two cannot drift. Only a FAILURE changes behaviour here; a successful send is untouched.
const UNAVAILABLE_CAUSE_CODES = new Set([
  "ECONNREFUSED",
  "ETIMEDOUT",
  "ECONNRESET",
  "UND_ERR_CONNECT_TIMEOUT",
  "UND_ERR_SOCKET",
  "EHOSTUNREACH",
  "ENETUNREACH",
  "DEPTH_ZERO_SELF_SIGNED_CERT",
  "SELF_SIGNED_CERT_IN_CHAIN",
  "UNABLE_TO_VERIFY_LEAF_SIGNATURE",
  "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
  "CERT_HAS_EXPIRED",
]);
function isBackendUnavailable(err: unknown): boolean {
  if (!(err instanceof TypeError)) return false;
  const cause = (err as { cause?: unknown }).cause;
  if (typeof cause !== "object" || cause === null) return false;
  const code = (cause as { code?: unknown }).code;
  if (typeof code !== "string") return false;
  return UNAVAILABLE_CAUSE_CODES.has(code) || code.startsWith("ERR_TLS_");
}

export async function POST(request: Request) {
  const secret = readInternalBearerSecret();
  if (!secret) {
    // Fail-closed: 503 (server misconfigured), distinct from 401 (wrong Bearer).
    return NextResponse.json({ error: "Not available" }, { status: 503 });
  }
  if (!bearerMatches(request.headers.get("authorization"), secret)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Cutover quiesce gate (#5450): refuse to arm during the migration window so
  // a reminder is not lost into the old SQLite mid-cutover. Retry-After lets
  // callers re-arm once the operator clears the flag (Phase 2.6).
  if (isCutoverQuiesced()) {
    return NextResponse.json(
      { error: "Reminder arming temporarily paused (Inngest backend cutover in progress)" },
      { status: 503, headers: { "Retry-After": RETRY_AFTER_S, "X-Soleur-Unavailable": "cutover-quiesce" } },
    );
  }

  let raw: string;
  try {
    raw = await request.text();
  } catch {
    return NextResponse.json({ error: "Malformed JSON" }, { status: 400 });
  }
  if (raw.length > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Payload too large" }, { status: 413 });
  }
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    return NextResponse.json({ error: "Malformed JSON" }, { status: 400 });
  }

  const b = body as Record<string, unknown> | null;
  const reminderId = b?.reminder_id;
  const fireAt = b?.fire_at;
  if (typeof reminderId !== "string" || reminderId.length === 0) {
    return NextResponse.json({ error: "reminder_id required" }, { status: 400 });
  }
  if (!isValidIsoInstant(fireAt)) {
    return NextResponse.json({ error: "fire_at must be a real ISO instant" }, { status: 400 });
  }
  if (b?.actor !== "platform") {
    return NextResponse.json({ error: "actor must be 'platform'" }, { status: 400 });
  }
  // Defense-in-depth: validate the action against the SAME allowlist the handler
  // uses. The route does NOT check CHECK_REGISTRY membership (server-only) — it
  // confirms `check` is a non-empty string; the handler owns the registry reject.
  const validated = validateReminderAction(b?.action);
  if (!validated.ok) {
    return NextResponse.json({ error: `Invalid action: ${validated.reason}` }, { status: 400 });
  }

  const data = {
    reminder_id: reminderId,
    fire_at: fireAt,
    actor: "platform" as const,
    action: validated.action,
  };

  try {
    const { inngest } = await import("@/server/inngest/client");
    await sendInngestWithRetry(
      () =>
        inngest.send({
          name: "reminder.scheduled",
          id: reminderId,
          ts: Date.parse(fireAt),
          data,
        }),
      { feature: "schedule-reminder", eventId: reminderId },
    );
  } catch (err) {
    reportSilentFallback(err, {
      feature: "schedule-reminder",
      op: "dispatch",
      extra: { reminder_id: reminderId },
    });
    // An unreachable or unverifiable scheduler (refused, timed out, reset, unreachable, or failing
    // TLS verification) — the cutover window after op=quiesce-web, a restart or replace, or a
    // link misconfiguration. Answer like the quiesce gate (retry later) instead of a terminal-looking
    // 502. The send may or may not have been persisted (a reset after the request left is ambiguous), and
    // that is safe: the caller re-arms and the event id (= reminderId, above) deduplicates a repeat.
    if (isBackendUnavailable(err)) {
      return NextResponse.json(
        { error: "Reminder arming temporarily unavailable (Inngest backend not accepting connections)" },
        { status: 503, headers: { "Retry-After": RETRY_AFTER_S, "X-Soleur-Unavailable": "backend-refused" } },
      );
    }
    return NextResponse.json({ error: "Dispatch failed" }, { status: 502 });
  }

  return NextResponse.json(
    { scheduled: reminderId, fire_at: fireAt },
    { status: 202 },
  );
}
