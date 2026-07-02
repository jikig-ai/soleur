/**
 * Unit tests — per-user worktree_id foundation (epic #5274 Phase 3 Sub-PR 3.B,
 * ADR-068 D0 amendment: user-sticky routing).
 *
 * `worktree_id` stops being the hardcoded `"primary"` constant and becomes
 * per-user: each user's session keys its OWN write-lease + fence stream +
 * git-data ref namespace off `resolveWorktreeId(userId)`. This file covers the
 * CWE-22 validation (`assertSafeWorktreeId`, symmetric to `assertSafeWorkspaceId`
 * and the git-data-pre-receive.sh:92-96 shell guard) and the per-user resolver.
 */

import { describe, expect, test } from "vitest";

import {
  assertSafeWorktreeId,
  resolveWorktreeId,
} from "@/server/worktree-write-lease";

const USER = "22222222-2222-2222-2222-222222222222";

describe("assertSafeWorktreeId (CWE-22)", () => {
  test("accepts a UUID (the per-user worktree id shape)", () => {
    expect(() => assertSafeWorktreeId(USER)).not.toThrow();
  });

  test("accepts the [A-Za-z0-9._-]+ token shape the pre-receive hook allows", () => {
    expect(() => assertSafeWorktreeId("primary")).not.toThrow();
    expect(() => assertSafeWorktreeId("wt-main_2.0")).not.toThrow();
  });

  test.each([
    ["", "empty"],
    [".", "dot"],
    ["..", "dotdot"],
    ["a/b", "slash (path traversal)"],
    ["../etc", "parent traversal"],
    ["ref\nheads", "newline"],
    ["has space", "space"],
    ["tilde~", "disallowed punctuation"],
  ])("rejects %j (%s)", (bad) => {
    expect(() => assertSafeWorktreeId(bad)).toThrow(/worktree.?id/i);
  });
});

describe("resolveWorktreeId (per-user, stops hardcoding 'primary')", () => {
  test("returns the user's own id as their per-user worktree id", () => {
    expect(resolveWorktreeId(USER)).toBe(USER);
  });

  test("two distinct users resolve to distinct worktree ids (D0: distinct lease streams)", () => {
    const a = "33333333-3333-3333-3333-333333333333";
    const b = "44444444-4444-4444-4444-444444444444";
    expect(resolveWorktreeId(a)).not.toBe(resolveWorktreeId(b));
  });

  test("never returns the legacy hardcoded 'primary' constant", () => {
    expect(resolveWorktreeId(USER)).not.toBe("primary");
  });

  test("fails loud (CWE-22) on an unsafe user id rather than building a bad ref path", () => {
    expect(() => resolveWorktreeId("../../etc/passwd")).toThrow(/worktree.?id/i);
  });
});
