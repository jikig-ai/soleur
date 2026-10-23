// #8211: workspaceReapRoots() is the DELETE list; workspaceTenantDenyRoots() the
// sandbox-masking contract. They share one private raw-roots helper.
import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { workspaceReapRoots, workspaceTenantDenyRoots } from "../server/workspace-resolver";

let sandbox: string;
const saved = { ws: process.env.WORKSPACES_ROOT, wt: process.env.WORKTREE_ROOT };

beforeEach(() => {
  sandbox = mkdtempSync(join(tmpdir(), "soleur-reaproots-"));
  mkdirSync(join(sandbox, "ws"));
  mkdirSync(join(sandbox, "wt"));
  process.env.WORKSPACES_ROOT = join(sandbox, "ws");
  process.env.WORKTREE_ROOT = join(sandbox, "wt");
});
afterEach(() => {
  if (saved.ws === undefined) delete process.env.WORKSPACES_ROOT;
  else process.env.WORKSPACES_ROOT = saved.ws;
  if (saved.wt === undefined) delete process.env.WORKTREE_ROOT;
  else process.env.WORKTREE_ROOT = saved.wt;
  rmSync(sandbox, { recursive: true, force: true });
});

describe("workspaceReapRoots", () => {
  test("returns both raw roots, labelled, workspaces first, flag-independent", () => {
    delete process.env.GIT_DATA_STORE_ENABLED;
    expect(workspaceReapRoots()).toEqual([
      { label: "workspaces", root: join(sandbox, "ws") },
      { label: "worktree", root: join(sandbox, "wt") },
    ]);
  });

  test("strips trailing slashes", () => {
    process.env.WORKTREE_ROOT = join(sandbox, "wt") + "///";
    expect(workspaceReapRoots()[1].root).toBe(join(sandbox, "wt"));
  });

  test("dedupes equal roots and roots that resolve to the same canonical directory", () => {
    process.env.WORKTREE_ROOT = process.env.WORKSPACES_ROOT;
    expect(workspaceReapRoots()).toHaveLength(1);
    process.env.WORKTREE_ROOT = join(sandbox, "alias");
    symlinkSync(join(sandbox, "ws"), join(sandbox, "alias"));
    expect(workspaceReapRoots()).toEqual([{ label: "workspaces", root: join(sandbox, "ws") }]);
  });

  test("does NOT add canonical aliases of a symlinked root (that is the deny set's job)", () => {
    rmSync(join(sandbox, "wt"), { recursive: true });
    mkdirSync(join(sandbox, "real"));
    symlinkSync(join(sandbox, "real"), join(sandbox, "wt"));
    expect(workspaceReapRoots().map((r) => r.root)).toEqual([join(sandbox, "ws"), join(sandbox, "wt")]);
    expect(workspaceTenantDenyRoots()).toContain(join(sandbox, "real"));
  });

  test("an empty WORKTREE_ROOT falls back to the default", () => {
    process.env.WORKTREE_ROOT = "";
    expect(workspaceReapRoots()[1].root).toBe("/var/lib/soleur/worktrees");
  });

  test.each([
    ["root '/'", "/", /filesystem root/],
    ["relative", "wt/rel", /not an absolute normalized path/],
    ["dotdot", "/tmp/../etc", /not an absolute normalized path/],
  ])("throws on %s", (_n, value, re) => {
    process.env.WORKTREE_ROOT = value;
    expect(() => workspaceReapRoots()).toThrow(re);
  });

  test("throws when a root canonicalizes to '/'", () => {
    process.env.WORKTREE_ROOT = join(sandbox, "toroot");
    symlinkSync("/", join(sandbox, "toroot"));
    expect(() => workspaceReapRoots()).toThrow(/filesystem root/);
  });
});

describe("workspaceTenantDenyRoots (shared helper regression)", () => {
  test("still returns both raw roots and still throws on '/'", () => {
    expect(workspaceTenantDenyRoots()).toEqual([join(sandbox, "ws"), join(sandbox, "wt")]);
    process.env.WORKTREE_ROOT = "/";
    expect(() => workspaceTenantDenyRoots()).toThrow(/filesystem root/);
  });
});
