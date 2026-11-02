// #8211: workspaceReapRoots() is the DELETE list; workspaceTenantDenyRoots() the
// sandbox-masking contract. They share one private raw-roots helper.
import { describe, test, expect, beforeEach, afterEach, vi } from "vitest";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  workspacePathForWorkspaceId,
  workspaceReapRoots,
  workspaceTenantDenyRoots,
} from "../server/workspace-resolver";

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
  vi.doUnmock("fs");
  vi.resetModules();
  if (saved.ws === undefined) delete process.env.WORKSPACES_ROOT;
  else process.env.WORKSPACES_ROOT = saved.ws;
  if (saved.wt === undefined) delete process.env.WORKTREE_ROOT;
  else process.env.WORKTREE_ROOT = saved.wt;
  rmSync(sandbox, { recursive: true, force: true });
});

const labels = (r: { roots: { label: string }[] }) => r.roots.map((x) => x.label);

describe("workspaceReapRoots", () => {
  test("returns both raw roots, labelled, workspaces first, flag-independent, no faults", () => {
    delete process.env.GIT_DATA_STORE_ENABLED;
    expect(workspaceReapRoots()).toEqual({
      roots: [
        { label: "workspaces", root: join(sandbox, "ws") },
        { label: "worktree", root: join(sandbox, "wt") },
      ],
      faults: [],
    });
  });

  test("strips trailing slashes", () => {
    process.env.WORKTREE_ROOT = join(sandbox, "wt") + "///";
    expect(workspaceReapRoots().roots[1].root).toBe(join(sandbox, "wt"));
  });

  test("dedupes equal roots, and roots that are different SYMLINKS to the same directory", () => {
    process.env.WORKTREE_ROOT = process.env.WORKSPACES_ROOT;
    expect(workspaceReapRoots().roots).toHaveLength(1);
    process.env.WORKTREE_ROOT = join(sandbox, "alias");
    symlinkSync(join(sandbox, "ws"), join(sandbox, "alias"));
    expect(workspaceReapRoots().roots).toEqual([{ label: "workspaces", root: join(sandbox, "ws") }]);
  });

  test("a lexical alias (trailing slashes) is the same root; distinct directories are not merged", () => {
    process.env.WORKTREE_ROOT = join(sandbox, "ws") + "/";
    expect(workspaceReapRoots().roots).toHaveLength(1);
    process.env.WORKTREE_ROOT = join(sandbox, "wt");
    expect(workspaceReapRoots().roots).toHaveLength(2);
  });

  test("when canonicalization fails (EACCES) the LEXICAL root is not guessed: it is a fault, the other root survives", async () => {
    vi.resetModules();
    vi.doMock("fs", async () => {
      const actual = await vi.importActual<typeof import("fs")>("fs");
      return {
        ...actual,
        realpathSync: Object.assign(
          (p: string, ...rest: unknown[]) => {
            if (p === join(sandbox, "wt")) throw Object.assign(new Error(`EACCES: ${p}`), { code: "EACCES" });
            return (actual.realpathSync as (...a: unknown[]) => string)(p, ...rest);
          },
          actual.realpathSync,
        ),
      };
    });
    const { workspaceReapRoots: reap } = await import("../server/workspace-resolver");
    const out = reap();
    expect(out.roots).toEqual([{ label: "workspaces", root: join(sandbox, "ws") }]);
    expect(out.faults.map((f) => f.label)).toEqual(["worktree"]);
    expect((out.faults[0].err as { code: string }).code).toBe("EACCES");
  });

  test("does NOT add canonical aliases of a symlinked root (that is the deny set's job)", () => {
    rmSync(join(sandbox, "wt"), { recursive: true });
    mkdirSync(join(sandbox, "real"));
    symlinkSync(join(sandbox, "real"), join(sandbox, "wt"));
    expect(workspaceReapRoots().roots.map((r) => r.root)).toEqual([join(sandbox, "ws"), join(sandbox, "wt")]);
    expect(workspaceTenantDenyRoots()).toContain(join(sandbox, "real"));
  });

  test("an empty WORKTREE_ROOT / WORKSPACES_ROOT falls back to its default", () => {
    process.env.WORKTREE_ROOT = "";
    expect(workspaceReapRoots().roots[1].root).toBe("/var/lib/soleur/worktrees");
    process.env.WORKTREE_ROOT = join(sandbox, "wt");
    process.env.WORKSPACES_ROOT = "";
    expect(workspaceReapRoots().roots[0]).toEqual({ label: "workspaces", root: "/workspaces" });
  });

  test.each([
    ["root '/'", "/", /filesystem root/],
    ["relative", "wt/rel", /not an absolute normalized path/],
    ["dotdot", "/tmp/../etc", /not an absolute normalized path/],
  ])("a bad WORKTREE_ROOT (%s) is a per-root fault; WORKSPACES_ROOT is still returned", (_n, value, re) => {
    process.env.WORKTREE_ROOT = value;
    const out = workspaceReapRoots();
    expect(out.roots).toEqual([{ label: "workspaces", root: join(sandbox, "ws") }]);
    expect(out.faults).toHaveLength(1);
    expect(out.faults[0].label).toBe("worktree");
    expect((out.faults[0].err as Error).message).toMatch(re);
  });

  test("a bad WORKSPACES_ROOT is a per-root fault; a valid WORKTREE_ROOT is still returned", () => {
    process.env.WORKSPACES_ROOT = "relative/ws";
    const out = workspaceReapRoots();
    expect(labels(out)).toEqual(["worktree"]);
    expect(out.faults.map((f) => f.label)).toEqual(["workspaces"]);
  });

  test("a root that canonicalizes to '/' is a fault", () => {
    process.env.WORKTREE_ROOT = join(sandbox, "toroot");
    symlinkSync("/", join(sandbox, "toroot"));
    const out = workspaceReapRoots();
    expect(out.faults.map((f) => f.label)).toEqual(["worktree"]);
    expect((out.faults[0].err as Error).message).toMatch(/filesystem root/);
  });
});

describe("workspaceTenantDenyRoots (shared helper regression: still throws for the WHOLE set)", () => {
  test("returns both raw roots and throws on '/' or a bad WORKSPACES_ROOT", () => {
    expect(workspaceTenantDenyRoots()).toEqual([join(sandbox, "ws"), join(sandbox, "wt")]);
    process.env.WORKTREE_ROOT = "/";
    expect(() => workspaceTenantDenyRoots()).toThrow(/filesystem root/);
    process.env.WORKTREE_ROOT = join(sandbox, "wt");
    process.env.WORKSPACES_ROOT = "relative";
    expect(() => workspaceTenantDenyRoots()).toThrow(/not an absolute normalized path/);
  });
});

describe("workspacePathForWorkspaceId lowercases after the shape check", () => {
  test("a mixed-case id resolves to the lowercase directory; a non-UUID still throws", () => {
    delete process.env.GIT_DATA_STORE_ENABLED;
    const id = "abcdef01-2222-4333-8444-5555555555ab";
    expect(workspacePathForWorkspaceId(id.toUpperCase())).toBe(join(sandbox, "ws", id));
    expect(() => workspacePathForWorkspaceId("../x")).toThrow(/Invalid workspaceId/);
  });
});

describe("validation parity: workspaceReapRoots vs workspaceTenantDenyRoots (kept in sync by hand)", () => {
  // The two functions carry separate copies of the `/` / relative / `..` rules (the deny set
  // must stay byte-identical to main). Drive BOTH over the same bad roots: any root one
  // refuses, the other must refuse too, and the messages say which function refused.
  test.each([
    ["root '/'", "/", /filesystem root/],
    ["a trailing-slash-only root '//'", "//", /filesystem root/],
    ["relative", "wt/rel", /not an absolute normalized path/],
    ["dotdot", "/tmp/../etc", /not an absolute normalized path/],
    ["leading dotdot", "../x", /not an absolute normalized path/],
  ])("%s on WORKTREE_ROOT: deny throws, reap records a fault", (_n, value, re) => {
    process.env.WORKTREE_ROOT = value;
    expect(() => workspaceTenantDenyRoots()).toThrow(re);
    expect(() => workspaceTenantDenyRoots()).toThrow(/^workspaceTenantDenyRoots:/);
    const out = workspaceReapRoots();
    expect(out.faults).toHaveLength(1);
    expect(out.faults[0].label).toBe("worktree");
    expect((out.faults[0].err as Error).message).toMatch(re);
    expect((out.faults[0].err as Error).message).toMatch(/^workspaceReapRoots:/);
  });

  test.each([
    ["root '/'", "/"],
    ["relative", "ws/rel"],
    ["dotdot", "/a/../b"],
  ])("%s on WORKSPACES_ROOT: deny throws, reap records a fault for the workspaces root only", (_n, value) => {
    process.env.WORKSPACES_ROOT = value;
    expect(() => workspaceTenantDenyRoots()).toThrow();
    const out = workspaceReapRoots();
    expect(out.faults.map((f) => f.label)).toEqual(["workspaces"]);
    expect(out.roots.map((r) => r.label)).toEqual(["worktree"]);
  });

  test("a good configuration is accepted by both", () => {
    expect(() => workspaceTenantDenyRoots()).not.toThrow();
    expect(workspaceReapRoots().faults).toEqual([]);
  });
});
