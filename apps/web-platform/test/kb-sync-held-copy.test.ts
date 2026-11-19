import { describe, expect, test } from "vitest";
import {
  disconnectHeldBody,
  disconnectHeldWarning,
  formatHeldCount,
  HELD_FILES_RENDER_MAX,
  HELD_OWNER_LABEL_FALLBACK,
  heldMemberNoRoute,
  heldMemberRouteAvailable,
  heldMemberTransient,
  heldOwnerNoRoute,
  heldOwnerRouteAvailable,
  heldOwnerTransient,
  heldRoleUnknown,
  isRenderableHeldCount,
  kbSyncHeldNotice,
} from "@/lib/kb-sync-held-copy";

// #12714 V6 strings as amended by the CPO's V7 (no "Nothing is lost"), V9 (`{n}` format), V10 (role unknown) and V11
// (the clearance hedge), verbatim (review-ext-rulings.md, CPO rows V7-V11). The literals below are the spec: a reworded
// string must fail here, not pass through a shared constant.

describe("kb-sync-held-copy: Owner strings (V6 + V7 + V11)", () => {
  test("route available, singular and plural", () => {
    expect(heldOwnerRouteAvailable(1)).toBe(
      "1 changed code file is not on your repository's main branch yet. The change is kept in your workspace. To publish it, ask your agent to push it to a new branch and approve the push, then open a pull request for that branch on GitHub and merge it. If you already did, this notice should clear the next time your workspace is updated from GitHub. If it does not, ask your agent which files are still counted.",
    );
    expect(heldOwnerRouteAvailable(3)).toBe(
      "3 changed code files are not on your repository's main branch yet. The changes are kept in your workspace. To publish them, ask your agent to push them to a new branch and approve the push, then open a pull request for that branch on GitHub and merge it. If you already did, this notice should clear the next time your workspace is updated from GitHub. If it does not, ask your agent which files are still counted.",
    );
  });

  test("no route, singular and plural", () => {
    expect(heldOwnerNoRoute(1)).toBe(
      "1 changed code file is not on your repository's main branch yet. The change is kept in your workspace. Publishing code changes is not available for this workspace.",
    );
    expect(heldOwnerNoRoute(42)).toBe(
      "42 changed code files are not on your repository's main branch yet. The changes are kept in your workspace. Publishing code changes is not available for this workspace.",
    );
  });

  test("transient, singular and plural", () => {
    expect(heldOwnerTransient(1)).toBe(
      "1 changed code file is not on your repository's main branch yet. The change is kept in your workspace. Whether your agent can publish it could not be checked right now. Reload this page to check again.",
    );
    expect(heldOwnerTransient(2)).toBe(
      "2 changed code files are not on your repository's main branch yet. The changes are kept in your workspace. Whether your agent can publish them could not be checked right now. Reload this page to check again.",
    );
  });
});

describe("kb-sync-held-copy: member strings (V6 + V7 + V11)", () => {
  test("route available, singular and plural, with the owner label", () => {
    expect(heldMemberRouteAvailable(1, "Acme Co")).toBe(
      "1 changed code file is not on the repository's main branch yet. The change is kept in the workspace. To publish it, ask your agent to push it to a new branch, then ask Acme Co to approve the push and merge the branch on GitHub. If this was already done, this notice should clear the next time the workspace is updated from GitHub. If it does not, ask your agent which files are still counted.",
    );
    expect(heldMemberRouteAvailable(3, "Acme Co")).toBe(
      "3 changed code files are not on the repository's main branch yet. The changes are kept in the workspace. To publish them, ask your agent to push them to a new branch, then ask Acme Co to approve the push and merge the branch on GitHub. If this was already done, this notice should clear the next time the workspace is updated from GitHub. If it does not, ask your agent which files are still counted.",
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
      "1 changed code file is not on the repository's main branch yet. The change is kept in the workspace.",
    );
    expect(heldMemberNoRoute(3)).toBe(
      "3 changed code files are not on the repository's main branch yet. The changes are kept in the workspace.",
    );
  });

  test("transient, singular and plural", () => {
    expect(heldMemberTransient(1)).toBe(
      "1 changed code file is not on the repository's main branch yet. The change is kept in the workspace. Whether your agent can publish it could not be checked right now. Reload this page to check again.",
    );
    expect(heldMemberTransient(3)).toBe(
      "3 changed code files are not on the repository's main branch yet. The changes are kept in the workspace. Whether your agent can publish them could not be checked right now. Reload this page to check again.",
    );
  });
});

describe("kb-sync-held-copy: role unknown (V10)", () => {
  test("singular and plural", () => {
    expect(heldRoleUnknown(1)).toBe(
      "1 changed code file is not on the repository's main branch yet. The change is kept in the workspace. Your role in this workspace could not be checked right now, so the steps to publish it are not shown. Reload this page to check again.",
    );
    expect(heldRoleUnknown(4)).toBe(
      "4 changed code files are not on the repository's main branch yet. The changes are kept in the workspace. Your role in this workspace could not be checked right now, so the steps to publish them are not shown. Reload this page to check again.",
    );
  });

  test("the role-unknown audience ignores the route state", () => {
    for (const route of ["available", "unavailable", "unknown"] as const) {
      expect(kbSyncHeldNotice({ audience: "unknown", route, count: 4, ownerLabel: "Acme Co" })).toBe(heldRoleUnknown(4));
    }
  });
});

describe("kb-sync-held-copy: {n} format (V9)", () => {
  test("below 1,000 a plain integer; from 1,000 a fixed comma separator; exactly 10,000 is a lower bound", () => {
    expect(formatHeldCount(1)).toBe("1");
    expect(formatHeldCount(999)).toBe("999");
    expect(formatHeldCount(1000)).toBe("1,000");
    expect(formatHeldCount(1234)).toBe("1,234");
    expect(formatHeldCount(9999)).toBe("9,999");
    expect(formatHeldCount(HELD_FILES_RENDER_MAX)).toBe("10,000 or more");
  });

  test("the notice at the cap keeps the plural grammar and reads as a lower bound", () => {
    expect(heldOwnerNoRoute(10_000)).toBe(
      "10,000 or more changed code files are not on your repository's main branch yet. The changes are kept in your workspace. Publishing code changes is not available for this workspace.",
    );
    expect(heldMemberNoRoute(1234)).toBe(
      "1,234 changed code files are not on the repository's main branch yet. The changes are kept in the workspace.",
    );
  });

  test("the separator does not depend on the runtime locale (no toLocaleString)", async () => {
    const { readFileSync } = await import("node:fs");
    const { join } = await import("node:path");
    const src = readFileSync(join(__dirname, "..", "lib", "kb-sync-held-copy.ts"), "utf8");
    expect(src).not.toMatch(/toLocaleString|Intl\./);
  });
});

describe("kb-sync-held-copy: the Disconnect dialog (V8)", () => {
  test("route available: the warning with the publish step, singular and plural", () => {
    expect(disconnectHeldWarning(1, "available")).toBe(
      "1 changed code file is not on your repository's main branch yet, and disconnecting deletes it with your workspace files. If it is not on a branch on GitHub yet, cancel and ask your agent to push it to a new branch, then approve the push.",
    );
    expect(disconnectHeldWarning(3, "available")).toBe(
      "3 changed code files are not on your repository's main branch yet, and disconnecting deletes them with your workspace files. If they are not on a branch on GitHub yet, cancel and ask your agent to push them to a new branch, then approve the push.",
    );
  });

  test("route unavailable or unknown: the warning without an instruction", () => {
    for (const route of ["unavailable", "unknown"] as const) {
      expect(disconnectHeldWarning(1, route)).toBe(
        "1 changed code file is not on your repository's main branch yet, and disconnecting deletes it with your workspace files.",
      );
      expect(disconnectHeldWarning(3, route)).toBe(
        "3 changed code files are not on your repository's main branch yet, and disconnecting deletes them with your workspace files.",
      );
    }
  });

  test("the count is formatted per V9", () => {
    expect(disconnectHeldWarning(10_000, "unknown")).toBe(
      "10,000 or more changed code files are not on your repository's main branch yet, and disconnecting deletes them with your workspace files.",
    );
  });

  test("no renderable count: no warning, and the dialog paragraph gains the conditional clause", () => {
    for (const count of [null, undefined, 0, -1, 1.5, 10_001, "3" as unknown]) {
      expect(disconnectHeldWarning(count, "available"), String(count)).toBeNull();
      expect(disconnectHeldBody(count)).toEqual({
        before: "This will unlink ",
        after:
          " from your account. Your workspace files will be removed, including any code changes your agent made that are not on your repository's main branch yet. You can reconnect a repository at any time.",
      });
    }
  });

  test("a renderable count keeps the existing paragraph unchanged", () => {
    expect(disconnectHeldBody(2)).toEqual({
      before: "This will unlink ",
      after: " from your account. Your workspace files will be removed. You can reconnect a repository at any time.",
    });
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
      for (const audience of ["owner", "member", "unknown"] as const) {
        expect(kbSyncHeldNotice({ audience, route: "available", count })).toBeNull();
      }
    }
    expect(isRenderableHeldCount(1)).toBe(true);
    expect(isRenderableHeldCount(HELD_FILES_RENDER_MAX)).toBe(true);
    expect(HELD_FILES_RENDER_MAX).toBe(10_000);
  });

  test("no string names the agent tool, says 'not on GitHub' or claims 'Nothing is lost' (C5, D23, V7)", () => {
    const all = [1, 2, 10_000].flatMap((n) => [
      heldOwnerRouteAvailable(n),
      heldOwnerNoRoute(n),
      heldOwnerTransient(n),
      heldMemberRouteAvailable(n, null),
      heldMemberNoRoute(n),
      heldMemberTransient(n),
      heldRoleUnknown(n),
      disconnectHeldWarning(n, "available") as string,
      disconnectHeldWarning(n, "unknown") as string,
    ]);
    all.push(disconnectHeldBody(null).after, disconnectHeldBody(2).after);
    for (const s of all) {
      expect(s).not.toMatch(/github_push_branch/);
      expect(s).not.toMatch(/not on GitHub/i);
      expect(s).not.toMatch(/waiting/i);
      expect(s).not.toMatch(/Nothing is lost/i);
    }
  });
});
