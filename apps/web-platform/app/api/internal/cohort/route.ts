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

import { NextResponse } from "next/server";
import { reportSilentFallback } from "@/server/observability";
import { createServiceClient } from "@/lib/supabase/service";
import {
  readInternalBearerSecret,
  bearerMatches,
} from "@/lib/internal-auth";

const MAX_BODY_BYTES = 4 * 1024;
const COHORT_KEY_RE = /^[a-z0-9-]+$/;

export async function PATCH(request: Request) {
  const secret = readInternalBearerSecret();
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
  if (
    typeof userId !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId)
  ) {
    return NextResponse.json(
      { error: "userId must be a UUID" },
      { status: 400 },
    );
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
    const { data, error } = await service
      .from("users")
      .update({ cohort_key: cohortKey })
      .eq("id", userId)
      .select("id");
    if (error) {
      reportSilentFallback(new Error(`cohort PATCH failed: ${error.message}`), {
        feature: "internal-cohort",
        op: "update",
        extra: { userId },
      });
      return NextResponse.json({ error: "update_failed" }, { status: 500 });
    }
    if (!data || data.length === 0) {
      // Zero matched rows — a silent ok:true here would let a typo'd userId read
      // as a successful tag while the tester stays invisible to cohort metrics.
      return NextResponse.json({ error: "user_not_found" }, { status: 404 });
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
