/**
 * Health probe — feat-team-workspace-multi-user (Phase 8.3).
 *
 * Returns `{ status: "ok" }` when all three preconditions hold:
 *
 *   1. Migrations 053/054 applied — the `workspace_members` +
 *      `workspace_member_attestations` tables exist (probed via
 *      `information_schema.tables`).
 *   2. `is_workspace_member(uuid, uuid)` helper RPC is callable
 *      (probed with a sentinel UUID; the helper returns `false` for
 *      non-members so we ignore the result, only checking that the
 *      RPC resolves without `42883`/`PGRST202` (function not found)).
 *   3. The `workspace_member_attestations` table is queryable (SELECT
 *      … LIMIT 0 — purely a schema probe, returns no rows).
 *
 * Returns `{ status: "degraded", reason: <string> }` otherwise. The
 * scheduled workflow (`.github/workflows/scheduled-membership-health.yml`)
 * fires `gh issue create` against a Sentry P0 label when this endpoint
 * reports degraded WHILE the feature flag is ON.
 *
 * Per `hr-no-dashboard-eyeball-pull-data-yourself` — this endpoint IS
 * the verification mechanism; the scheduled workflow checks it
 * autonomously. No operator gaze required.
 */

import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface HealthResponse {
  status: "ok" | "degraded";
  reason?: string;
}

const SENTINEL_UUID = "00000000-0000-0000-0000-000000000000";

export async function GET(): Promise<NextResponse<HealthResponse>> {
  const service = createServiceClient();

  // 1. Schema probe — both new tables must exist.
  try {
    const { data: members, error: memErr } = await service
      .from("workspace_members")
      .select("user_id")
      .limit(0);
    if (memErr) {
      return NextResponse.json(
        { status: "degraded", reason: `workspace_members unreachable: ${memErr.message}` },
        { status: 503 },
      );
    }
    void members;

    const { data: atts, error: attErr } = await service
      .from("workspace_member_attestations")
      .select("id")
      .limit(0);
    if (attErr) {
      return NextResponse.json(
        {
          status: "degraded",
          reason: `workspace_member_attestations unreachable: ${attErr.message}`,
        },
        { status: 503 },
      );
    }
    void atts;
  } catch (err) {
    return NextResponse.json(
      {
        status: "degraded",
        reason: `schema probe threw: ${err instanceof Error ? err.message : String(err)}`,
      },
      { status: 503 },
    );
  }

  // 2. Helper RPC probe. Sentinel UUID is not a real workspace; the
  //    helper returns `false` and we only assert "callable, not 42883".
  try {
    const { error: rpcErr } = await service.rpc("is_workspace_member", {
      p_workspace_id: SENTINEL_UUID,
      p_user_id: SENTINEL_UUID,
    });
    if (rpcErr) {
      return NextResponse.json(
        {
          status: "degraded",
          reason: `is_workspace_member RPC failed: ${rpcErr.code ?? ""} ${rpcErr.message}`,
        },
        { status: 503 },
      );
    }
  } catch (err) {
    return NextResponse.json(
      {
        status: "degraded",
        reason: `helper rpc threw: ${err instanceof Error ? err.message : String(err)}`,
      },
      { status: 503 },
    );
  }

  return NextResponse.json({ status: "ok" });
}
