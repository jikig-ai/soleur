/**
 * #4672 R1 (CTO ruling 1): the per-session execution-grant side channel. One-shot, short-lived, bounded, keyed by the
 * zod-parsed handler args, and sticky-enforcing once the approval flow ran in the session.
 */
import { describe, expect, test } from "vitest";
import { handlerArgsKey } from "@/server/approval/canonical";
import { checkGrant, ExecutionGrants, GRANT_MAX_ENTRIES, GRANT_TTL_MS, putGrant } from "@/server/approval/grants";
import { TOOLS, WORKSPACE_ID } from "./fixtures";

const T = TOOLS.pushBranch;
const SHA = "a".repeat(40);

describe("ExecutionGrants", () => {
  test("take is one-shot", () => {
    const g = new ExecutionGrants();
    g.put(T, "k", { workspaceId: WORKSPACE_ID, headSha: SHA });
    expect(g.take(T, "k")).toEqual({ workspaceId: WORKSPACE_ID, headSha: SHA });
    expect(g.take(T, "k")).toBeNull();
  });

  test("a different key or a different tool returns null and leaves the grant in place", () => {
    const g = new ExecutionGrants();
    g.put(T, "k", { workspaceId: WORKSPACE_ID });
    expect(g.take(T, "other")).toBeNull();
    expect(g.take(TOOLS.kbShareCreate, "k")).toBeNull();
    expect(g.take(T, "k")).toEqual({ workspaceId: WORKSPACE_ID });
  });

  test("a grant expires after 120 s and the expired read still consumes it", () => {
    let now = 1_000;
    const g = new ExecutionGrants(() => now);
    expect(GRANT_TTL_MS).toBe(120_000);
    g.put(T, "k", { workspaceId: WORKSPACE_ID });
    now += GRANT_TTL_MS - 1;
    expect(g.take(T, "k")).not.toBeNull();
    g.put(T, "k", { workspaceId: WORKSPACE_ID });
    now += GRANT_TTL_MS;
    expect(g.take(T, "k")).toBeNull();
    expect(g.size()).toBe(0);
  });

  test("the map is capped at 64 entries and the oldest is dropped", () => {
    const g = new ExecutionGrants();
    for (let i = 0; i < GRANT_MAX_ENTRIES + 5; i++) g.put(T, `k${i}`, { workspaceId: WORKSPACE_ID });
    expect(g.size()).toBe(GRANT_MAX_ENTRIES);
    expect(g.take(T, "k0")).toBeNull();
    expect(g.take(T, "k4")).toBeNull();
    expect(g.take(T, "k5")).not.toBeNull();
    expect(g.take(T, `k${GRANT_MAX_ENTRIES + 4}`)).not.toBeNull();
  });

  test("a stored binding is a copy: mutating the object that was put cannot change the grant", () => {
    const g = new ExecutionGrants();
    const b = { workspaceId: WORKSPACE_ID, headSha: SHA };
    g.put(T, "k", b);
    b.headSha = "b".repeat(40);
    expect(g.take(T, "k")!.headSha).toBe(SHA);
  });

  test("enforcing starts false", () => {
    expect(new ExecutionGrants().enforcing).toBe(false);
  });
});

describe("checkGrant", () => {
  const args = { branch: "feat/x" }; // `force` defaults to false on BOTH sides

  test("no grants object, or a session the flow never ran in: legacy (behaviour unchanged)", () => {
    expect(checkGrant(undefined, T, args)).toEqual({ kind: "legacy" });
    expect(checkGrant(new ExecutionGrants(), T, args)).toEqual({ kind: "legacy" });
  });

  test("enforcing and no grant: refuse (the sticky flag fails closed)", () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    expect(checkGrant(g, T, args)).toEqual({ kind: "refuse" });
  });

  test("the handler's zod-parsed args find the gate's grant: defaults apply identically on both sides", () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    // The gate keys by the raw model input; the handler by what zod handed it (force defaulted to false).
    putGrant(g, T, { branch: "feat/x" }, { workspaceId: WORKSPACE_ID, headSha: SHA });
    expect(handlerArgsKey(T, { branch: "feat/x", force: false })).toBe(handlerArgsKey(T, { branch: "feat/x" }));
    expect(checkGrant(g, T, { branch: "feat/x", force: false })).toEqual({
      kind: "granted",
      binding: { workspaceId: WORKSPACE_ID, headSha: SHA },
    });
    // One-shot: a second call with the same args is refused.
    expect(checkGrant(g, T, { branch: "feat/x", force: false })).toEqual({ kind: "refuse" });
  });

  test("different arguments do not find the grant", () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    putGrant(g, T, { branch: "feat/x" }, { workspaceId: WORKSPACE_ID, headSha: SHA });
    expect(checkGrant(g, T, { branch: "feat/y", force: false })).toEqual({ kind: "refuse" });
  });

  test("args that cannot be keyed are a refuse when enforcing, never a throw", () => {
    const g = new ExecutionGrants();
    g.enforcing = true;
    expect(checkGrant(g, T, { branch: "" })).toEqual({ kind: "refuse" });
  });
});
