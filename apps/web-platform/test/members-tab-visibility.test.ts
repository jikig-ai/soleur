import { describe, it, expect, vi } from "vitest";
import {
  shouldShowMembersTab,
  userHasWorkspaceMembership,
} from "@/server/workspace-resolver";

// Regression guard for feat-fix-multi-user-feature-not-visible.
//
// The Settings "Members" tab (+ "Team Activity") is gated server-side by the
// visibility chain in settings/layout.tsx: an authenticated user with a
// resolved current org AND the team-workspace-invite flag ON. Any single gate
// failing hides BOTH tabs with no error surfaced to the user — the silent
// failure that prompted the ops@jikigai.com report. These tests pin the pure
// decision so a future CODE regression of the chain fails deterministically
// (the original incident was a non-code live-state question; this guards the
// code path itself). See the plan's Acceptance Criteria AC6.

describe("shouldShowMembersTab — visibility-chain predicate", () => {
  const ORG = "1a8045bf-6718-43c9-887b-0c0652ca75c3";

  it("shows when the current org resolves AND the flag is ON", () => {
    expect(shouldShowMembersTab(ORG, true)).toBe(true);
  });

  it("hides when the current org is null (gate #2 fail)", () => {
    expect(shouldShowMembersTab(null, true)).toBe(false);
  });

  it("hides when the flag evaluates OFF (gate #3 fail)", () => {
    expect(shouldShowMembersTab(ORG, false)).toBe(false);
  });
});

describe("userHasWorkspaceMembership — integrity-surface discriminator", () => {
  // Distinguishes a legitimately org-less identity (normal, stay silent) from
  // a member whose current org resolved null (the integrity surface that hides
  // org-gated UI — emit to Sentry). Recursive chain mock mirrors the live
  // PostgREST fluent API: every chained call returns the same object, the
  // terminal awaited value is the row set.
  function mockSupabase(rows: unknown[] | null, error: unknown = null) {
    const chain = {
      select: () => chain,
      eq: () => chain,
      limit: () => Promise.resolve({ data: rows, error }),
    };
    return { from: vi.fn(() => chain) };
  }

  it("true when the user has >=1 membership row", async () => {
    expect(
      await userHasWorkspaceMembership("u", mockSupabase([{ workspace_id: "w" }])),
    ).toBe(true);
  });

  it("false when the user has zero membership rows", async () => {
    expect(await userHasWorkspaceMembership("u", mockSupabase([]))).toBe(false);
  });

  it("false (fail-quiet) on a query error — never blocks the render path", async () => {
    expect(
      await userHasWorkspaceMembership("u", mockSupabase(null, { message: "boom" })),
    ).toBe(false);
  });
});
