import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { readWorkspaceIdFromDb } from "@/server/workspace-resolver";
import { AgentEnginePersistenceRepository, type PersistenceClient } from "@/server/agent-engine-persistence";
import { listReviewedEngineDefinitions, reviewedEngineRegistry } from "@/server/agent-engine-reviewed-definitions";
import { DEFAULT_AGENT_ENGINE_ID } from "@/server/agent-engine-contract";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

async function context() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { response: NextResponse.json({ error: "unauthorized" }, { status: 401 }) } as const;
  let workspaceId: string | null;
  try {
    workspaceId = await readWorkspaceIdFromDb(user.id, supabase);
  } catch (error) {
    reportSilentFallback(error, { feature: "agent-engine-settings", op: "workspace-resolve" });
    return { response: NextResponse.json({ error: "settings_unavailable" }, { status: 503 }) } as const;
  }
  if (!workspaceId) return { response: NextResponse.json({ error: "workspace_unbound" }, { status: 503 }) } as const;
  return { supabase, user, workspaceId } as const;
}

export async function GET() {
  const resolved = await context();
  if ("response" in resolved) return resolved.response;
  try {
    const repository = new AgentEnginePersistenceRepository(resolved.supabase as unknown as PersistenceClient);
    return NextResponse.json({
      workspaceId: resolved.workspaceId,
      defaultEngineId: await repository.getDefaultEngine(resolved.workspaceId) ?? DEFAULT_AGENT_ENGINE_ID,
      engines: listReviewedEngineDefinitions().map(({ id, version, transport, authModes, enabledForNewRuns }) =>
        ({ id, version, transport, authModes, enabledForNewRuns })),
    });
  } catch (error) {
    reportSilentFallback(error, { feature: "agent-engine-settings", op: "read" });
    return NextResponse.json({ error: "settings_unavailable" }, { status: 503 });
  }
}

export async function PUT(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/dashboard/settings/agent-engine", origin);
  const resolved = await context();
  if ("response" in resolved) return resolved.response;
  let body: { engineId?: unknown };
  try { body = (await request.json()) as typeof body; } catch {
    return NextResponse.json({ error: "malformed_json" }, { status: 400 });
  }
  if (typeof body.engineId !== "string") {
    return NextResponse.json({ error: "engineId required" }, { status: 400 });
  }
  try {
    const definition = reviewedEngineRegistry.get(body.engineId);
    if (!definition.enabledForNewRuns) {
      return NextResponse.json({ error: "engine_disabled" }, { status: 409 });
    }
    const repository = new AgentEnginePersistenceRepository(resolved.supabase as unknown as PersistenceClient);
    await repository.setDefaultEngine(resolved.workspaceId, definition.id);
    return NextResponse.json({ defaultEngineId: definition.id });
  } catch (error) {
    if (error instanceof Error && error.message === "engine_unknown") {
      return NextResponse.json({ error: "engine_unknown" }, { status: 400 });
    }
    reportSilentFallback(error, { feature: "agent-engine-settings", op: "write" });
    return NextResponse.json({ error: "settings_update_failed" }, { status: 503 });
  }
}
