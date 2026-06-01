import { describe, test, expect } from "vitest";
import { isInviteReturnTarget } from "./setup-key-gate";

// feat-invite-accept-membership-byok (#4715). The "invite outranks /setup-key"
// rule has one unit-tested home. A validated `/invite/<token>` next-hop must be
// recognized so the redirect gates return it directly instead of wrapping it in
// the onboarding funnel (which strands a keyless invitee at /setup-key).
describe("isInviteReturnTarget", () => {
  test("a /invite/<token> path is an invite return target", () => {
    expect(isInviteReturnTarget("/invite/abc")).toBe(true);
  });

  test("the /dashboard fallback is NOT an invite return target", () => {
    expect(isInviteReturnTarget("/dashboard")).toBe(false);
  });

  test("null (no next-hop) is NOT an invite return target", () => {
    expect(isInviteReturnTarget(null)).toBe(false);
  });

  test("a prefix-adjacent path (/invitedX) does NOT match — boundary guard", () => {
    // `/invited-users` or `/invitedX` must not be mistaken for `/invite/`.
    // safeReturnTo already requires the trailing slash; this locks the boundary.
    expect(isInviteReturnTarget("/invitedX")).toBe(false);
  });

  test("the bare /invite (no trailing slash) does NOT match", () => {
    expect(isInviteReturnTarget("/invite")).toBe(false);
  });
});
