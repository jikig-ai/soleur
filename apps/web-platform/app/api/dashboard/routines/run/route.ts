// POST /api/dashboard/routines/run (#5345) — session-gated debug "Run now".
// Body: { fnId: string, confirmed?: boolean }. Dispatches via the runRoutine
// chokepoint as actorClass="human". Returns 409 confirmation_required for a
// protected routine without `confirmed` (UI shows the confirm modal).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { runRoutine } from "@/server/routines/run-routine";
import { readWorkspaceIdFromDb } from "@/server/workspace-resolver";
import { AgentEnginePersistenceRepository, type PersistenceClient } from "@/server/agent-engine-persistence";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/dashboard/routines/run", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: { fnId?: unknown; confirmed?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "malformed_json" }, { status: 400 });
  }
  const fnId = typeof body.fnId === "string" ? body.fnId : "";
  if (!fnId) {
    return NextResponse.json({ error: "fnId required" }, { status: 400 });
  }
  const confirmed = body.confirmed === true;

  try {
    const workspaceId = await readWorkspaceIdFromDb(user.id, supabase);
    if (!workspaceId) {
      return NextResponse.json({ error: "workspace_unbound" }, { status: 503 });
    }
    const repository = new AgentEnginePersistenceRepository(
      supabase as unknown as PersistenceClient,
    );
    const result = await runRoutine({
      fnId,
      actorClass: "human",
      actorId: user.id,
      confirmed,
      feature: "routines-run-now",
      workspaceId,
      bindRun: (binding) => repository.bind(binding),
    });
    if (!result.ok) {
      return NextResponse.json({ error: result.code }, { status: result.status });
    }
    return NextResponse.json({ dispatched: result.event }, { status: 202 });
  } catch (e) {
    Sentry.captureException(e, { tags: { surface: "routines-run-now" } });
    return NextResponse.json({ error: "dispatch_failed" }, { status: 502 });
  }
}
