// Regression test for the keyless-invitee recovery-banner deadlock (#4715).
//
// PR #4713 added getPendingInvitesForUser() but its embedded select referenced
// `raw_user_meta_data` on the `users` relationship. supabase-js/PostgREST
// resolves that FK target to `public.users`, which has NO `raw_user_meta_data`
// column (it exists only on `auth.users`), so both query branches failed with
// Postgres 42703 and the function returned []. The recovery banner therefore
// rendered null for every invitee — confirmed against the live prod DB.
//
// The pre-existing tests passed because their mocks (e.g. `chainableMock` in
// workspace-invitation-identity.test.ts) set `.select = vi.fn(() => chain)`,
// DISCARDING the select argument. This test captures and asserts the actual
// select string so a re-introduced auth.users-only column fails CI, and also
// asserts the mapped output shape. Fix-pattern precedent: workspace-resolver.test.ts.

import { describe, expect, it, vi, beforeEach } from "vitest";
import { mockQueryChain } from "../helpers/mock-supabase";

const { mockFrom } = vi.hoisted(() => ({ mockFrom: vi.fn() }));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom })),
}));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));
vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ error: vi.fn(), info: vi.fn(), warn: vi.fn() }),
}));

import { getPendingInvitesForUser } from "@/server/workspace-invitations";

const TEST_USER_ID = "11111111-2222-3333-4444-555555555555";
const TEST_EMAIL = "alice@example.com";

describe("getPendingInvitesForUser — select string (42703 regression)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("does not reference auth.users-only columns and still embeds the inviter email", async () => {
    mockFrom.mockReturnValue(mockQueryChain([], null));

    await getPendingInvitesForUser(TEST_USER_ID, TEST_EMAIL);

    expect(mockFrom).toHaveBeenCalledWith("workspace_invitations");

    const chain = mockFrom.mock.results[0]?.value as { select: { mock: { calls: unknown[][] } } };
    const selectArg = chain.select.mock.calls[0]?.[0] as string;
    expect(typeof selectArg).toBe("string");

    // The bug: an auth.users-only column embedded against public.users → 42703.
    expect(selectArg).not.toMatch(
      /\b(raw_user_meta_data|raw_app_meta_data|encrypted_password|email_confirmed_at|last_sign_in_at)\b/,
    );

    // Guard the other direction: a future "fix" must not silently drop the
    // inviter embed or the email column the display name derives from.
    expect(selectArg).toMatch(/inviter:users!workspace_invitations_inviter_user_id_fkey/);
    expect(selectArg).toMatch(/\bemail\b/);
  });

  it("derives inviter_name from the inviter email when present", async () => {
    mockFrom.mockReturnValue(
      mockQueryChain(
        [
          {
            id: "i1",
            workspace_id: "w1",
            role: "member",
            expires_at: "2026-06-08T00:00:00.000Z",
            created_at: "2026-06-01T00:00:00.000Z",
            workspaces: { name: "Acme" },
            inviter: { email: "boss@acme.com" },
          },
        ],
        null,
      ),
    );

    const invites = await getPendingInvitesForUser(TEST_USER_ID, TEST_EMAIL);

    expect(invites).toHaveLength(1);
    expect(invites[0]?.inviter_name).toBe("boss@acme.com");
    expect(invites[0]?.workspace_name).toBe("Acme");
  });

  it("falls back to 'A team member' when the inviter row has no email", async () => {
    mockFrom.mockReturnValue(
      mockQueryChain(
        [
          {
            id: "i2",
            workspace_id: "w2",
            role: "member",
            expires_at: "2026-06-08T00:00:00.000Z",
            created_at: "2026-06-01T00:00:00.000Z",
            workspaces: { name: "Acme" },
            inviter: { email: null },
          },
        ],
        null,
      ),
    );

    const invites = await getPendingInvitesForUser(TEST_USER_ID, TEST_EMAIL);

    expect(invites).toHaveLength(1);
    expect(invites[0]?.inviter_name).toBe("A team member");
  });
});
