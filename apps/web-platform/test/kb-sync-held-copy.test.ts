import { describe, expect, test } from "vitest";
import {
  HELD_OWNER_LABEL_FALLBACK,
  heldMemberNoRoute,
  heldMemberRouteAvailable,
  heldMemberTransient,
  heldOwnerNoRoute,
  heldOwnerRouteAvailable,
  heldOwnerTransient,
  isRenderableHeldCount,
  kbSyncHeldNotice,
} from "@/lib/kb-sync-held-copy";

// #12714 V6 strings, verbatim (decision-challenges.md row V6; plan "V6 amendments"). The literals below are the spec:
// a reworded string must fail here, not pass through a shared constant.

describe("kb-sync-held-copy: V6 Owner strings", () => {
  test("route available, singular and plural", () => {
    expect(heldOwnerRouteAvailable(1)).toBe(
      "1 changed code file is not on your repository's main branch yet. Nothing is lost: the change stays in your workspace. To publish it, ask your agent to push it to a new branch and approve the push, then open a pull request for that branch on GitHub and merge it. If you already did, this notice clears once the merge reaches your workspace.",
    );
    expect(heldOwnerRouteAvailable(3)).toBe(
      "3 changed code files are not on your repository's main branch yet. Nothing is lost: the changes stay in your workspace. To publish them, ask your agent to push them to a new branch and approve the push, then open a pull request for that branch on GitHub and merge it. If you already did, this notice clears once the merge reaches your workspace.",
    );
  });

  test("no route, singular and plural", () => {
    expect(heldOwnerNoRoute(1)).toBe(
      "1 changed code file is not on your repository's main branch yet. Nothing is lost: the change stays in your workspace. Publishing code changes is not available for this workspace.",
    );
    expect(heldOwnerNoRoute(42)).toBe(
      "42 changed code files are not on your repository's main branch yet. Nothing is lost: the changes stay in your workspace. Publishing code changes is not available for this workspace.",
    );
  });

  test("transient, singular and plural", () => {
    expect(heldOwnerTransient(1)).toBe(
      "1 changed code file is not on your repository's main branch yet. Nothing is lost: the change stays in your workspace. Whether your agent can publish it could not be checked right now. Reload this page to check again.",
    );
    expect(heldOwnerTransient(2)).toBe(
      "2 changed code files are not on your repository's main branch yet. Nothing is lost: the changes stay in your workspace. Whether your agent can publish them could not be checked right now. Reload this page to check again.",
    );
  });
});

describe("kb-sync-held-copy: V6 member strings", () => {
  test("route available, singular and plural, with the owner label", () => {
    expect(heldMemberRouteAvailable(1, "Acme Co")).toBe(
      "1 changed code file is not on the repository's main branch yet. Nothing is lost: the change stays in the workspace. To publish it, ask your agent to push it to a new branch, then ask Acme Co to approve the push and merge the branch on GitHub. If this was already done, this notice clears once the merge reaches the workspace.",
    );
    expect(heldMemberRouteAvailable(3, "Acme Co")).toBe(
      "3 changed code files are not on the repository's main branch yet. Nothing is lost: the changes stay in the workspace. To publish them, ask your agent to push them to a new branch, then ask Acme Co to approve the push and merge the branch on GitHub. If this was already done, this notice clears once the merge reaches the workspace.",
    );
  });

  test("the {ownerLabel} fallback is 'your workspace owner' (null, empty or whitespace label)", () => {
    expect(HELD_OWNER_LABEL_FALLBACK).toBe("your workspace owner");
    for (const label of [null, undefined, "", "   "]) {
      expect(heldMemberRouteAvailable(3, label)).toContain(
        "then ask your workspace owner to approve the push and merge the branch on GitHub.",
      );
    }
  });

  test("no route (C7: no wait and no action), singular and plural", () => {
    expect(heldMemberNoRoute(1)).toBe(
      "1 changed code file is not on the repository's main branch yet. Nothing is lost: the change stays in the workspace.",
    );
    expect(heldMemberNoRoute(3)).toBe(
      "3 changed code files are not on the repository's main branch yet. Nothing is lost: the changes stay in the workspace.",
    );
  });

  test("transient, singular and plural", () => {
    expect(heldMemberTransient(1)).toBe(
      "1 changed code file is not on the repository's main branch yet. Nothing is lost: the change stays in the workspace. Whether your agent can publish it could not be checked right now. Reload this page to check again.",
    );
    expect(heldMemberTransient(3)).toBe(
      "3 changed code files are not on the repository's main branch yet. Nothing is lost: the changes stay in the workspace. Whether your agent can publish them could not be checked right now. Reload this page to check again.",
    );
  });
});

describe("kb-sync-held-copy: dispatcher and render bound (D29(8))", () => {
  test("picks the string per audience and route state", () => {
    expect(kbSyncHeldNotice({ audience: "owner", route: "available", count: 3 })).toBe(heldOwnerRouteAvailable(3));
    expect(kbSyncHeldNotice({ audience: "owner", route: "unavailable", count: 3 })).toBe(heldOwnerNoRoute(3));
    expect(kbSyncHeldNotice({ audience: "owner", route: "unknown", count: 3 })).toBe(heldOwnerTransient(3));
    expect(kbSyncHeldNotice({ audience: "member", route: "available", count: 3, ownerLabel: "Acme Co" })).toBe(
      heldMemberRouteAvailable(3, "Acme Co"),
    );
    expect(kbSyncHeldNotice({ audience: "member", route: "unavailable", count: 3 })).toBe(heldMemberNoRoute(3));
    expect(kbSyncHeldNotice({ audience: "member", route: "unknown", count: 3 })).toBe(heldMemberTransient(3));
  });

  test("n = 0, null, non-integer, negative or above 10000 gives no notice", () => {
    for (const count of [0, null, undefined, 1.5, -1, 10_001, Number.NaN, Number.POSITIVE_INFINITY, "3" as unknown]) {
      expect(isRenderableHeldCount(count), String(count)).toBe(false);
      expect(kbSyncHeldNotice({ audience: "owner", route: "available", count })).toBeNull();
      expect(kbSyncHeldNotice({ audience: "member", route: "available", count })).toBeNull();
    }
    expect(isRenderableHeldCount(1)).toBe(true);
    expect(isRenderableHeldCount(10_000)).toBe(true);
  });

  test("no string names the agent tool or says 'not on GitHub' (C5, D23)", () => {
    const all = [
      heldOwnerRouteAvailable(1),
      heldOwnerRouteAvailable(2),
      heldOwnerNoRoute(1),
      heldOwnerNoRoute(2),
      heldOwnerTransient(1),
      heldOwnerTransient(2),
      heldMemberRouteAvailable(1, null),
      heldMemberRouteAvailable(2, null),
      heldMemberNoRoute(1),
      heldMemberNoRoute(2),
      heldMemberTransient(1),
      heldMemberTransient(2),
    ];
    for (const s of all) {
      expect(s).not.toMatch(/github_push_branch/);
      expect(s).not.toMatch(/not on GitHub/i);
      expect(s).not.toMatch(/waiting/i);
    }
  });
});
