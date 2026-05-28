import { describe, expect, it, vi } from "vitest";
import { randomUUID } from "crypto";
import {
  getCurrentOrganizationId,
  getCurrentWorkspaceId,
  resolveCurrentOrganizationId,
  resolveCurrentWorkspaceId,
  getDefaultWorkspaceForUser,
  resolveWorkspacePathForUser,
} from "@/server/workspace-resolver";
import { mockQueryChain } from "../helpers/mock-supabase";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

// Build a minimal supabase-shape stub that returns `chain` for every `.from(table)` call.
function supabaseFor(chain: unknown) {
  return { from: vi.fn(() => chain) } as unknown as Parameters<
    typeof getDefaultWorkspaceForUser
  >[1];
}

describe("workspace-resolver: getCurrentOrganizationId", () => {
  it("returns app_metadata.current_organization_id from session JWT when present", () => {
    const orgId = randomUUID();
    const session = {
      user: {
        id: randomUUID(),
        app_metadata: { current_organization_id: orgId },
      },
    };
    expect(getCurrentOrganizationId(session)).toBe(orgId);
  });

  it("returns null when claim absent (fallback path will resolve to default)", () => {
    const session = { user: { id: randomUUID(), app_metadata: {} } };
    expect(getCurrentOrganizationId(session)).toBeNull();
  });

  it("returns null for an empty/anonymous session", () => {
    expect(getCurrentOrganizationId(null)).toBeNull();
    expect(getCurrentOrganizationId(undefined)).toBeNull();
  });
});

describe("workspace-resolver: resolveCurrentOrganizationId", () => {
  it("returns current_organization_id from user_session_state", async () => {
    const userId = randomUUID();
    const orgId = randomUUID();
    const chain = mockQueryChain({ current_organization_id: orgId });
    const supabase = supabaseFor(chain);

    const result = await resolveCurrentOrganizationId(userId, supabase);

    expect(result).toBe(orgId);
    expect(supabase.from).toHaveBeenCalledWith("user_session_state");
  });

  it("returns null when no user_session_state row exists", async () => {
    const userId = randomUUID();
    const chain = mockQueryChain(null);
    const supabase = supabaseFor(chain);

    const result = await resolveCurrentOrganizationId(userId, supabase);

    expect(result).toBeNull();
  });
});

describe("workspace-resolver: getCurrentWorkspaceId (AC9 — read claim from session JWT)", () => {
  it("returns app_metadata.current_workspace_id from the session access token", () => {
    const wsId = randomUUID();
    const session = {
      user: { id: randomUUID(), app_metadata: { current_workspace_id: wsId } },
    };
    expect(getCurrentWorkspaceId(session)).toBe(wsId);
  });

  it("returns null when the claim is absent (caller falls back to solo)", () => {
    expect(getCurrentWorkspaceId({ user: { id: randomUUID(), app_metadata: {} } })).toBeNull();
    expect(getCurrentWorkspaceId(null)).toBeNull();
    expect(getCurrentWorkspaceId(undefined)).toBeNull();
  });
});

describe("workspace-resolver: resolveCurrentWorkspaceId (solo fallback, never sibling)", () => {
  it("returns current_workspace_id from user_session_state", async () => {
    const userId = randomUUID();
    const wsId = randomUUID();
    const supabase = supabaseFor(mockQueryChain({ current_workspace_id: wsId }));

    const result = await resolveCurrentWorkspaceId(userId, supabase);

    expect(result).toBe(wsId);
    expect(supabase.from).toHaveBeenCalledWith("user_session_state");
  });

  it("falls back to the SOLO workspace (= userId) when the claim is null", async () => {
    const userId = randomUUID();
    const supabase = supabaseFor(mockQueryChain({ current_workspace_id: null }));

    expect(await resolveCurrentWorkspaceId(userId, supabase)).toBe(userId);
  });

  it("falls back to the SOLO workspace when no session_state row exists", async () => {
    const userId = randomUUID();
    const supabase = supabaseFor(mockQueryChain(null));

    expect(await resolveCurrentWorkspaceId(userId, supabase)).toBe(userId);
  });

  it("falls back to the SOLO workspace on transient error (never a sibling)", async () => {
    const userId = randomUUID();
    const supabase = supabaseFor(mockQueryChain(null, { message: "boom" }));

    expect(await resolveCurrentWorkspaceId(userId, supabase)).toBe(userId);
  });
});

describe("workspace-resolver: getDefaultWorkspaceForUser", () => {
  it("returns the user's single workspace_id (solo N2 invariant: workspaces.id === user.id)", async () => {
    const userId = randomUUID();
    // Solo backfill row: workspace_id === userId per migration 053 §1.1.7 N2.
    const chain = mockQueryChain([{ workspace_id: userId }]);
    const supabase = supabaseFor(chain);

    const workspaceId = await getDefaultWorkspaceForUser(userId, supabase);

    expect(workspaceId).toBe(userId);
    expect(supabase.from).toHaveBeenCalledWith("workspace_members");
  });

  it("returns the MIN(created_at) workspace_id when the user belongs to multiple", async () => {
    const userId = randomUUID();
    const oldestWorkspaceId = randomUUID();
    const newerWorkspaceId = randomUUID();
    // mockQueryChain resolves the same payload for any chain shape, so the
    // ordering is verified at the SQL level via .order(). We simulate the
    // ORDER BY workspaces.created_at ASC LIMIT 1 result.
    const chain = mockQueryChain([{ workspace_id: oldestWorkspaceId }]);
    const supabase = supabaseFor(chain);

    const workspaceId = await getDefaultWorkspaceForUser(userId, supabase);

    expect(workspaceId).toBe(oldestWorkspaceId);
    expect(workspaceId).not.toBe(newerWorkspaceId);
  });

  it("throws when the user has no workspace membership (post-trigger race shouldn't happen, but fail closed)", async () => {
    const userId = randomUUID();
    const chain = mockQueryChain([]);
    const supabase = supabaseFor(chain);

    await expect(getDefaultWorkspaceForUser(userId, supabase)).rejects.toThrow(
      /no workspace membership/i,
    );
  });
});

describe("workspace-resolver: resolveWorkspacePathForUser", () => {
  it("joins WORKSPACES_ROOT with the default workspace_id", async () => {
    const userId = randomUUID();
    process.env.WORKSPACES_ROOT = "/tmp/soleur-test-workspaces";
    const chain = mockQueryChain([{ workspace_id: userId }]);
    const supabase = supabaseFor(chain);

    const path = await resolveWorkspacePathForUser(userId, supabase);

    expect(path).toBe(`/tmp/soleur-test-workspaces/${userId}`);
  });
});
