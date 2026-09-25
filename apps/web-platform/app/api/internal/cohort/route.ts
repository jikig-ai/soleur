// Cohort-tag write route — sets users.cohort_key for a cohort member.
//
// PATCH /api/internal/cohort { userId, cohort_key } — the ONLY writer of the
// cohort_key column (migration 141; write is service-role). The operator runs
// this from a shell during onboarding right after the tester signs up, pairing
// it with the runbook-row record so the tag is never server-only.
//
// Authentication: the SAME fail-closed shared secret as trigger-cron /
// schedule-reminder (INNGEST_MANUAL_TRIGGER_SECRET, length-guarded
// timingSafeEqual). Lives under /api/internal/, NOT /api/admin/: the
// cookie-session admin auth on /api/admin/analytics cannot be curled by the
// operator at all — the internal shared-secret shape is the established
// operator-curl pattern for admin-class mutations.
//
// Registered as a NARROW exact path in lib/routes.ts PUBLIC_PATHS — without
// it, Supabase middleware 307s the cookie-less caller before this gate runs.

import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { reportSilentFallback } from "@/server/observability";
import { createServiceClient } from "@/lib/supabase/service";

const MAX_BODY_BYTES = 4 * 1024;
const COHORT_KEY_RE = /^[a-z0-9-]+$/;

function readSecret(): string | null {
  const v = process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  return v && v.length > 0 ? v : null;
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

export async function PATCH(request: Request) {
  const secret = readSecret();
  if (!secret) {
    return NextResponse.json({ error: "Not available" }, { status: 503 });
  }
  if (!bearerMatches(request.headers.get("authorization"), secret)) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
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
  const userId = b?.userId;
  if (typeof userId !== "string" || userId.length === 0) {
    return NextResponse.json({ error: "userId required" }, { status: 400 });
  }

  // Normalize before the shape check so `Alpha-01` and `alpha-01` land on the
  // same key — free-text cohort tags fragment otherwise (spec-flow finding).
  const cohortKey =
    typeof b?.cohort_key === "string" ? b.cohort_key.trim().toLowerCase() : null;
  if (!cohortKey || !COHORT_KEY_RE.test(cohortKey)) {
    return NextResponse.json(
      { error: "cohort_key must match ^[a-z0-9-]+$" },
      { status: 400 },
    );
  }

  try {
    const service = createServiceClient();
    const { error } = await service
      .from("users")
      .update({ cohort_key: cohortKey })
      .eq("id", userId);
    if (error) {
      reportSilentFallback(new Error(`cohort PATCH failed: ${error.message}`), {
        feature: "internal-cohort",
        op: "update",
        extra: { userId },
      });
      return NextResponse.json({ error: "update_failed" }, { status: 500 });
    }
    return NextResponse.json({ ok: true, userId, cohort_key: cohortKey });
  } catch (err) {
    reportSilentFallback(err instanceof Error ? err : new Error(String(err)), {
      feature: "internal-cohort",
      op: "update",
      extra: { userId },
    });
    return NextResponse.json({ error: "update_failed" }, { status: 500 });
  }
}
