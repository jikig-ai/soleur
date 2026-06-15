/**
 * Shared-workspace fixture helper — Phase 8.2.3.
 *
 * Creates N synthetic users + a single shared workspace + one
 * `workspace_members` row per user (first = owner; rest = members).
 * Used by the integration tests that exercise multi-user workspace
 * isolation, BYOK cost attribution under shared workspaces, and the
 * post-removal DSAR path.
 *
 * Per `cq-test-fixtures-synthesized-only` (Kieran N3): every user_id
 * here is freshly minted via `auth.admin.createUser` against the dev
 * Supabase project — NO test ever references a real-customer auth row.
 * Synthetic emails match the strict regex; `assertSynthetic` gates
 * every destructive op.
 *
 * Cleanup is the test's responsibility — call
 * `tearDownSharedWorkspace(service, fixture)` in `afterAll`. The helper
 * unwinds in FK-RESTRICT-reverse order (members → workspaces →
 * organization → auth.users).
 */

import { randomBytes } from "node:crypto";
import type { SupabaseClient } from "@supabase/supabase-js";
import { withGoTrueRetry } from "./gotrue-retry";

export const WORKSPACE_FIXTURE_EMAIL_RE =
  /^workspace-fixture-[a-f0-9]{16}@soleur\.test$/;

export function syntheticWorkspaceFixtureEmail(): string {
  return `workspace-fixture-${randomBytes(8).toString("hex")}@soleur.test`;
}

export function assertSyntheticWorkspaceFixture(email: string): void {
  if (!WORKSPACE_FIXTURE_EMAIL_RE.test(email)) {
    throw new Error(
      `Refusing destructive op on non-synthetic email "${email}". ` +
        `Emails must match ${WORKSPACE_FIXTURE_EMAIL_RE}.`,
    );
  }
}

export interface SharedWorkspaceMember {
  userId: string;
  email: string;
  role: "owner" | "member";
}

export interface SharedWorkspaceFixture {
  organizationId: string;
  /**
   * Workspace ID — under the N2 invariant (`workspaces.id = owner_user_id`
   * for backfill/solo), this equals members[0].userId for solo cases.
   * For the multi-user case created here we use the trigger-provisioned
   * workspace for the owner (workspace_id = owner.userId).
   */
  workspaceId: string;
  members: SharedWorkspaceMember[];
}

/**
 * Create a shared workspace with `count` members. The first member is
 * the owner; the rest are added via direct service-role INSERT into
 * `workspace_members` (mirrors what `invite_workspace_member` RPC does
 * after the attestation row is written, minus the WORM attestation
 * itself — fixtures use attestation_id=NULL).
 *
 * Returns the fixture handle; tests can iterate `fixture.members`,
 * mint runtime JWTs per user via the existing tenant-iso pattern, etc.
 */
export async function createSharedWorkspaceMembers(
  service: SupabaseClient,
  count: number,
): Promise<SharedWorkspaceFixture> {
  if (count < 1) throw new Error("count must be >= 1");

  const members: SharedWorkspaceMember[] = [];

  for (let i = 0; i < count; i++) {
    const email = syntheticWorkspaceFixtureEmail();
    assertSyntheticWorkspaceFixture(email);
    const { data, error } = await withGoTrueRetry(`createUser:${email}`, () =>
      service.auth.admin.createUser({
        email,
        password: randomBytes(16).toString("hex"),
        email_confirm: true,
      }),
    );
    if (error) throw new Error(`createUser failed: ${error.message}`);
    const userId = data.user?.id;
    if (!userId) throw new Error("createUser returned no user.id");
    members.push({ userId, email, role: i === 0 ? "owner" : "member" });
  }

  // The `handle_new_user` trigger already provisioned org+workspace+
  // members(owner) for member[0]. We adopt that as the shared workspace.
  const owner = members[0];
  const { data: ownerMembership, error: ownerErr } = await service
    .from("workspace_members")
    .select("workspace_id")
    .eq("user_id", owner.userId)
    .single();
  if (ownerErr || !ownerMembership?.workspace_id) {
    throw new Error(
      `Trigger-provisioned membership not found for owner ${owner.userId}: ${ownerErr?.message ?? "no row"}`,
    );
  }
  const workspaceId = ownerMembership.workspace_id as string;

  const { data: wsRow, error: wsErr } = await service
    .from("workspaces")
    .select("organization_id")
    .eq("id", workspaceId)
    .single();
  if (wsErr || !wsRow?.organization_id) {
    throw new Error(
      `Workspace ${workspaceId} has no organization_id: ${wsErr?.message ?? "no row"}`,
    );
  }
  const organizationId = wsRow.organization_id as string;

  // INSERT member rows for users[1..].
  if (members.length > 1) {
    const insertRows = members.slice(1).map((m) => ({
      workspace_id: workspaceId,
      user_id: m.userId,
      role: m.role,
      attestation_id: null,
    }));
    const { error: insertErr } = await service
      .from("workspace_members")
      .insert(insertRows);
    if (insertErr) {
      throw new Error(
        `workspace_members.insert failed: ${insertErr.message}`,
      );
    }
  }

  return { organizationId, workspaceId, members };
}

/**
 * FK-RESTRICT-reverse cleanup. Idempotent — repeated calls are safe.
 */
export async function tearDownSharedWorkspace(
  service: SupabaseClient,
  fixture: SharedWorkspaceFixture,
): Promise<void> {
  for (const m of fixture.members) {
    assertSyntheticWorkspaceFixture(m.email);
  }

  // 1. workspace_members rows for ALL members (owner's trigger row included).
  for (const m of fixture.members) {
    try {
      await service.from("workspace_members").delete().eq("user_id", m.userId);
    } catch {}
  }

  // 2. Workspace (RESTRICT to organizations — handled in step 3).
  try {
    await service.from("workspaces").delete().eq("id", fixture.workspaceId);
  } catch {}

  // 3. Organization.
  try {
    await service
      .from("organizations")
      .delete()
      .eq("id", fixture.organizationId);
  } catch {}

  // 4. Auth users (CASCADE to public.users). Retry past GoTrue rate limits
  // and the opaque transient "Database error deleting user".
  for (const m of fixture.members) {
    try {
      await withGoTrueRetry(`deleteUser:${m.userId}`, () =>
        service.auth.admin.deleteUser(m.userId),
      );
    } catch {}
  }
}
