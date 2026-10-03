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
import { verifiedUserId } from "@/server/request-auth";

export const dynamic = "force-dynamic";

async function context(req: Request) {
  const supabase = await createClient();
  const userId = await verifiedUserId(req);
  if (!userId) return { response: NextResponse.json({ error: "unauthorized" }, { status: 401 }) } as const;
  let workspaceId: string | null;
  let identity: Awaited<ReturnType<typeof resolveIdentity>>;
  try {
    workspaceId = await readWorkspaceIdFromDb(userId, supabase);
    identity = await resolveIdentity(supabase);
  } catch (error) {
    reportSilentFallback(error, { feature: "agent-engine-settings", op: "workspace-resolve" });
    return { response: NextResponse.json({ error: "settings_unavailable" }, { status: 503 }) } as const;
  }
  if (!workspaceId) return { response: NextResponse.json({ error: "workspace_unbound" }, { status: 503 }) } as const;
  return { supabase, userId, workspaceId, identity } as const;
}

export async function GET(request: Request) {
  const resolved = await context(request);
  if ("response" in resolved) return resolved.response;
  try {
    const repository = new AgentEnginePersistenceRepository(resolved.supabase as unknown as PersistenceClient);
    const previewAuthMode = request ? new URL(request.url).searchParams.get("previewAuthMode") : null;
    if (previewAuthMode !== null && previewAuthMode !== "managed" && previewAuthMode !== "api-key") {
      return NextResponse.json({ error: "auth_mode_unsupported" }, { status: 400 });
    }
    const affectedConversationCount = previewAuthMode === null
      ? undefined
      : await repository.countCodexConversationRebinds(resolved.workspaceId, previewAuthMode);
    return NextResponse.json({
      workspaceId: resolved.workspaceId,
      defaultEngineId: await repository.getDefaultEngine(resolved.workspaceId) ?? DEFAULT_AGENT_ENGINE_ID,
      defaultAuthMode: await repository.getDefaultAuthMode(resolved.workspaceId) ?? "managed",
      codexAuthMode: await repository.getCodexAuthMode(resolved.workspaceId) ?? "managed",
      ...(affectedConversationCount === undefined ? {} : { affectedConversationCount }),
      engines: await Promise.all(listReviewedEngineDefinitions().map(async ({ id, version, transport, authModes, enabledForNewRuns, settingsSelectable }): Promise<EngineSettingsMetadata> =>
        ({ id, version, transport, authModes, enabledForNewRuns, settingsSelectable, rolloutEnabled: await isEngineRolloutEnabled(id, resolved.identity.orgId, resolved.identity) }))),
    });
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "workspace_owner_required") {
      return NextResponse.json({ error: "workspace_owner_required" }, { status: 403 });
    }
    reportSilentFallback(error, { feature: "agent-engine-settings", op: "read" });
    return NextResponse.json({ error: "settings_unavailable" }, { status: 503 });
  }
}

export async function PUT(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/dashboard/settings/agent-engine", origin);
  const resolved = await context(request);
  if ("response" in resolved) return resolved.response;
  let body: {
    engineId?: unknown;
    authMode?: unknown;
    applyToExistingCodexConversations?: unknown;
    expectedAffectedConversationCount?: unknown;
  };
  try { body = (await request.json()) as typeof body; } catch {
    return NextResponse.json({ error: "malformed_json" }, { status: 400 });
  }
  if (typeof body.engineId !== "string") {
    return NextResponse.json({ error: "engineId required" }, { status: 400 });
  }
  if (body.applyToExistingCodexConversations !== undefined
      && typeof body.applyToExistingCodexConversations !== "boolean") {
    return NextResponse.json({ error: "apply_to_existing_invalid" }, { status: 400 });
  }
  if (body.expectedAffectedConversationCount !== undefined
      && (typeof body.expectedAffectedConversationCount !== "number"
        || !Number.isInteger(body.expectedAffectedConversationCount)
        || (body.expectedAffectedConversationCount as number) < 0)) {
    return NextResponse.json({ error: "affected_count_invalid" }, { status: 400 });
  }
  try {
    const definition = reviewedEngineRegistry.get(body.engineId);
    if (!definition.enabledForNewRuns && !definition.settingsSelectable) {
      return NextResponse.json({ error: "engine_disabled" }, { status: 409 });
    }
    if (!definition.settingsSelectable
      && !(await isEngineRolloutEnabled(definition.id, resolved.identity.orgId, resolved.identity))) {
      return NextResponse.json({ error: "engine_rollout_disabled" }, { status: 409 });
    }
    const authMode = body.authMode === undefined ? undefined : body.authMode;
    if (authMode !== undefined && (typeof authMode !== "string" || !definition.authModes.includes(authMode))) {
      return NextResponse.json({ error: "auth_mode_unsupported" }, { status: 400 });
    }
    const applyToExistingCodexConversations = body.applyToExistingCodexConversations === true;
    if (applyToExistingCodexConversations && (
      definition.id !== "codex"
      || authMode === undefined
      || typeof body.expectedAffectedConversationCount !== "number"
    )) {
      return NextResponse.json({ error: "existing_codex_mode_change_required" }, { status: 400 });
    }
    const repository = new AgentEnginePersistenceRepository(resolved.supabase as unknown as PersistenceClient);
    if (definition.settingsSelectable && !definition.enabledForNewRuns && !applyToExistingCodexConversations) {
      return NextResponse.json({ error: "engine_execution_disabled" }, { status: 409 });
    }
    const targetEngineId = definition.settingsSelectable && !definition.enabledForNewRuns
      ? applyToExistingCodexConversations
        ? DEFAULT_AGENT_ENGINE_ID
        : await repository.getDefaultEngine(resolved.workspaceId) ?? DEFAULT_AGENT_ENGINE_ID
      : definition.id;
    const result = authMode === undefined
      ? await repository.setDefaultEngine(resolved.workspaceId, targetEngineId)
      : applyToExistingCodexConversations
        ? await repository.setDefaultEngine(
            resolved.workspaceId,
            definition.id,
            authMode,
            true,
            body.expectedAffectedConversationCount as number,
          )
        : await repository.setDefaultEngine(resolved.workspaceId, targetEngineId, authMode);
    const committedSettings = result && typeof result === "object"
      ? result as { defaultEngineId?: unknown; defaultAuthMode?: unknown }
      : undefined;
    if (applyToExistingCodexConversations && (
      !committedSettings
      || typeof committedSettings.defaultEngineId !== "string"
      || typeof committedSettings.defaultAuthMode !== "string"
    )) {
      throw new Error("Codex rebind RPC returned invalid committed workspace settings");
    }
    const affectedConversationCount = result && typeof result === "object"
      ? (result as { affectedConversationCount?: unknown }).affectedConversationCount
      : undefined;
    return NextResponse.json({
      defaultEngineId: committedSettings?.defaultEngineId ?? targetEngineId,
      ...(authMode ? { defaultAuthMode: committedSettings?.defaultAuthMode ?? authMode } : {}),
      ...(definition.id === "codex" && authMode ? { codexAuthMode: authMode } : {}),
      ...(typeof affectedConversationCount === "number" ? { affectedConversationCount } : {}),
    });
  } catch (error) {
    if (error instanceof Error && error.message === "engine_unknown") {
      return NextResponse.json({ error: "engine_unknown" }, { status: 400 });
    }
    if (error instanceof Error && "code" in error && error.code === "workspace_owner_required") {
      return NextResponse.json({ error: "workspace_owner_required" }, { status: 403 });
    }
    if (error instanceof Error && error.message.includes("affected Codex conversation count changed")) {
      return NextResponse.json({ error: "affected_count_changed" }, { status: 409 });
    }
    reportSilentFallback(error, { feature: "agent-engine-settings", op: "write" });
    return NextResponse.json({ error: "settings_update_failed" }, { status: 503 });
  }
}
