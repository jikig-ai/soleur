import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { resolveIdentity } from "@/lib/feature-flags/identity";
import { isEngineRolloutEnabled } from "@/lib/feature-flags/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { readWorkspaceIdFromDb } from "@/server/workspace-resolver";
import { AgentEnginePersistenceRepository, type PersistenceClient } from "@/server/agent-engine-persistence";
import { listReviewedEngineDefinitions, reviewedEngineRegistry } from "@/server/agent-engine-reviewed-definitions";
import { DEFAULT_AGENT_ENGINE_ID, type EngineSettingsMetadata } from "@/server/agent-engine-contract";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

async function context() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { response: NextResponse.json({ error: "unauthorized" }, { status: 401 }) } as const;
  let workspaceId: string | null;
  let identity: Awaited<ReturnType<typeof resolveIdentity>>;
  try {
    workspaceId = await readWorkspaceIdFromDb(user.id, supabase);
    identity = await resolveIdentity(supabase);
  } catch (error) {
    reportSilentFallback(error, { feature: "agent-engine-settings", op: "workspace-resolve" });
    return { response: NextResponse.json({ error: "settings_unavailable" }, { status: 503 }) } as const;
  }
  if (!workspaceId) return { response: NextResponse.json({ error: "workspace_unbound" }, { status: 503 }) } as const;
  return { supabase, user, workspaceId, identity } as const;
}

export async function GET() {
  const resolved = await context();
  if ("response" in resolved) return resolved.response;
  try {
    const repository = new AgentEnginePersistenceRepository(resolved.supabase as unknown as PersistenceClient);
    return NextResponse.json({
      workspaceId: resolved.workspaceId,
      defaultEngineId: await repository.getDefaultEngine(resolved.workspaceId) ?? DEFAULT_AGENT_ENGINE_ID,
      defaultAuthMode: await repository.getDefaultAuthMode(resolved.workspaceId) ?? "managed",
      engines: await Promise.all(listReviewedEngineDefinitions().map(async ({ id, version, transport, authModes, enabledForNewRuns }): Promise<EngineSettingsMetadata> =>
        ({ id, version, transport, authModes, enabledForNewRuns, rolloutEnabled: await isEngineRolloutEnabled(id, resolved.identity.orgId, resolved.identity) }))),
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
  let body: { engineId?: unknown; authMode?: unknown };
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
    if (!(await isEngineRolloutEnabled(definition.id, resolved.identity.orgId, resolved.identity))) {
      return NextResponse.json({ error: "engine_rollout_disabled" }, { status: 409 });
    }
    const authMode = body.authMode === undefined ? undefined : body.authMode;
    if (authMode !== undefined && (typeof authMode !== "string" || !definition.authModes.includes(authMode))) {
      return NextResponse.json({ error: "auth_mode_unsupported" }, { status: 400 });
    }
    const repository = new AgentEnginePersistenceRepository(resolved.supabase as unknown as PersistenceClient);
    if (authMode === undefined) await repository.setDefaultEngine(resolved.workspaceId, definition.id);
    else await repository.setDefaultEngine(resolved.workspaceId, definition.id, authMode);
    return NextResponse.json({ defaultEngineId: definition.id, ...(authMode ? { defaultAuthMode: authMode } : {}) });
  } catch (error) {
    if (error instanceof Error && error.message === "engine_unknown") {
      return NextResponse.json({ error: "engine_unknown" }, { status: 400 });
    }
    if (error instanceof Error && "code" in error && error.code === "workspace_owner_required") {
      return NextResponse.json({ error: "workspace_owner_required" }, { status: 403 });
    }
    reportSilentFallback(error, { feature: "agent-engine-settings", op: "write" });
    return NextResponse.json({ error: "settings_update_failed" }, { status: 503 });
  }
}
