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

import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { reportSilentFallback } from "@/server/observability";
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

function readSecret(): string | null {
  const v = process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  return v && v.length > 0 ? v : null;
}

// Cutover quiesce (#5450, Phase 2.1): during the SQLite→Postgres+Redis cutover
// window the operator sets INNGEST_CUTOVER_QUIESCE=1 in Doppler prd so NO new
// reminder is armed into the doomed old SQLite mid-cutover (spec-flow P0-2).
// Authenticated callers get a 503 + Retry-After and retry after the window;
// the operator unsets the flag in Phase 2.6. Strict truthy check ("1"/"true").
function isCutoverQuiesced(): boolean {
  const v = process.env.INNGEST_CUTOVER_QUIESCE;
  return v === "1" || v === "true";
}

function bearerMatches(header: string | null, secret: string): boolean {
  if (!header) return false;
  const token = header.startsWith("Bearer ")
    ? header.slice("Bearer ".length)
    : header;
  const a = Buffer.from(token, "utf8");
  const b = Buffer.from(secret, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export async function POST(request: Request) {
  const secret = readSecret();
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
      { status: 503, headers: { "Retry-After": "120" } },
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
    return NextResponse.json({ error: "Dispatch failed" }, { status: 502 });
  }

  return NextResponse.json(
    { scheduled: reminderId, fire_at: fireAt },
    { status: 202 },
  );
}
