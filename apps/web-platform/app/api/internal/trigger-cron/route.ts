// On-demand cron trigger route (#4734).
//
// POST /api/internal/trigger-cron dispatches a whitelisted
// `cron/<name>.manual-trigger` event via the app's already-wired Inngest
// client, so a cron can be fired on demand WITHOUT SSH-ing to the Hetzner box
// and curling the loopback Inngest event endpoint (a forbidden manual prod op).
//
// Authentication: a fail-closed shared secret (INNGEST_MANUAL_TRIGGER_SECRET,
// Doppler-provisioned, TF-generated random) compared via a length-guarded
// constant-time `timingSafeEqual`. This reuses the PRIMITIVE shape from
// app/api/internal/kb-drift-ingest/route.ts (fail-closed readSecret +
// timingSafeEqual + length-guard) but is a Bearer shared-secret compare, NOT
// HMAC — the body is a single allowlisted event name with no replay-sensitive
// payload (see #4734 design / security Open Questions).
//
// Abuse surface (brand-survival threshold = single-user incident): several
// allowlisted crons mutate state or spend money (cron/bug-fixer opens PRs;
// content-generator / competitive-analysis / growth-execution / daily-triage
// spend Anthropic/API budget). The secret IS the trust boundary; the allowlist
// (derived from EXPECTED_CRON_FUNCTIONS, drift-guarded) bounds the blast radius
// to known cron events. The mutating crons additionally carry account-scoped
// Inngest concurrency caps (limit 1, key "cron-platform"), so a replay flood
// collapses to one extra in-flight run rather than unbounded parallelism.

import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { reportSilentFallback } from "@/server/observability";
import { isAllowlistedManualTrigger } from "@/lib/inngest/manual-trigger-allowlist";

// NOTE: the Inngest client is imported DYNAMICALLY inside POST (see below),
// mirroring the dynamic `@/server/inngest/client` import in
// app/api/webhooks/github/route.ts — this defers the client's load-time
// fail-closed throw (missing INNGEST_SIGNING_KEY) to request time and keeps
// the route module importable during `next build` page-data collection.

// Body cap: the request is a single allowlisted event name (~60 bytes). Cap
// well above that so a credential-holder cannot use the parse as a memory-amp
// DoS primitive against the Next.js worker — mirrors the 413-before-parse
// guard in kb-drift-ingest/route.ts and webhooks/github/route.ts.
const MAX_BODY_BYTES = 64 * 1024;

function readSecret(): string | null {
  const v = process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  return v && v.length > 0 ? v : null;
}

function bearerMatches(header: string | null, secret: string): boolean {
  if (!header) return false;
  // Accept either a bare token or a `Bearer <token>` header — both feed the
  // same length-guarded constant-time compare, so the lenient fallthrough is
  // harmless (a non-`Bearer ` header compares verbatim).
  const token = header.startsWith("Bearer ")
    ? header.slice("Bearer ".length)
    : header;
  const a = Buffer.from(token, "utf8");
  const b = Buffer.from(secret, "utf8");
  // Length-guard before timingSafeEqual (it throws on unequal-length buffers).
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export async function POST(request: Request) {
  const secret = readSecret();
  if (!secret) {
    // Fail-closed: indistinguishable-from-absent. 503 (server misconfigured),
    // NOT 401 — distinct from "secret set but Bearer wrong".
    return NextResponse.json({ error: "Not available" }, { status: 503 });
  }
  if (!bearerMatches(request.headers.get("authorization"), secret)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: unknown;
  let raw: string;
  try {
    raw = await request.text();
  } catch {
    return NextResponse.json({ error: "Malformed JSON" }, { status: 400 });
  }
  if (raw.length > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "Payload too large" }, { status: 413 });
  }
  try {
    body = JSON.parse(raw);
  } catch {
    return NextResponse.json({ error: "Malformed JSON" }, { status: 400 });
  }
  const name = (body as { event?: unknown } | null)?.event;
  if (!isAllowlistedManualTrigger(name)) {
    return NextResponse.json({ error: "Event not allowlisted" }, { status: 400 });
  }

  // Optional per-cron event `data` pass-through (#4742). The route is a dumb
  // forwarder: each consuming cron validates its own fields (e.g.
  // cron-bug-fixer.ts validates event.data.issue_number is a positive integer
  // and Sentry-reports on invalid). We only enforce that `data`, when present,
  // is a PLAIN object — a non-plain-object spread is either a silent no-op
  // (`...42`, `...null`) or injects index keys (`...["a"]`), so reject it
  // explicitly before merge. `null`/absent are treated as no-data.
  const rawData = (body as { data?: unknown } | null)?.data;
  const hasData = rawData !== undefined && rawData !== null;
  if (
    hasData &&
    (typeof rawData !== "object" || Array.isArray(rawData))
  ) {
    return NextResponse.json({ error: "data must be a plain object" }, { status: 400 });
  }
  const callerData = hasData ? (rawData as Record<string, unknown>) : {};

  // Dispatch through the runRoutine chokepoint (#5345) so manualTrigger policy
  // + actor attribution are centralized at ONE inngest.send site. The secret is
  // a higher trust tier: actorClass="system" + confirmed=true is the explicit,
  // documented exemption from the per-routine confirm gate. `name` is an
  // allowlisted `cron/<short>.manual-trigger` event ⇒ fnId = `cron-${short}`.
  const fnId = `cron-${name.slice("cron/".length, -".manual-trigger".length)}`;
  try {
    const { runRoutine } = await import("@/server/routines/run-routine");
    const result = await runRoutine({
      fnId,
      actorClass: "system",
      confirmed: true,
      data: callerData,
      feature: "trigger-cron",
    });
    if (!result.ok) {
      // Unreachable (allowlist already validated `name`), but fail explicitly
      // rather than silently 202 on a policy reject.
      return NextResponse.json(
        { error: result.code },
        { status: result.status },
      );
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "trigger-cron",
      op: "dispatch",
      extra: { event: name },
    });
    return NextResponse.json({ error: "Dispatch failed" }, { status: 502 });
  }

  return NextResponse.json(
    { dispatched: name, trigger: "manual-api" },
    { status: 202 },
  );
}
