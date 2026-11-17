// Real-git rows for the workspace self-heal (#12600, CTO rulings D6 and D7; supersede R18's KB exemption and gate
// placement). Each row drives the REAL `syncWorkspace` against a local bare `file://` remote and asserts EFFECTS on the
// workspace: file bytes, the local branch, recovery branches. Unit rows: test/server/workspace-sync-self-heal-gate.test.ts.
//
// Fixture rules (as test/session-sync-kb-only-push-real-git.test.ts): a template remote built once and COPIED per row;
// workspaces are `git clone --depth 1`; fixture git runs under `gitFixtureEnv` with increasing dates; the host-git
// protocol clamp is widened to `file` for the token-bearing arm only (the token-free runner keeps `none`). Synthesized
// data only (cq-test-fixtures-synthesized-only): the token is built by concatenation.
import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "./helpers/git-fixture-env";

const USER = "77777777-7777-4777-8777-777777777777";
const WS_ID = "11111111-1111-4111-8111-111111111111";
const LITERAL_URL = "https://github.com/acme/widget.git";
const TOKEN = ["ghs", "_", "c".repeat(36)].join("");

const H = vi.hoisted(() => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  /** Known-positive switch: route the self-heal's LOCAL verbs through the token-bearing legacy arm (the pre-D6d shape). */
  localViaTokenArm: false,
  /** Called after each token-bearing call returns (args[0] = verb). */
  afterTokenCall: null as null | ((verb: string) => void),
  tokenVerbs: [] as string[],
  /** The fixture remote the literal URL is rewritten to on the hardened arm (D27: the held-commits merge). */
  remoteUrl: "",
  writeRepoCols: vi.fn(async () => undefined),
  writeHeldCols: vi.fn(async () => undefined),
  /** D39(a)/D42: every held-count write the self-heal asked for, with the count its inputs give (WP3 owns the write). */
  heldWrites: [] as Array<{ T: string; headSha: string; pullBlocked: unknown; count: number | null }>,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: H.reportSilentFallback,
  warnSilentFallback: H.warnSilentFallback,
  mirrorWithDebounce: H.mirrorWithDebounce,
  mirrorWarnWithDebounce: H.mirrorWarnWithDebounce,
  hashUserId: (x: string) => `h-${x}`,
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => H.log, default: H.log }));
vi.mock("@/server/github-app", () => ({ generateInstallationToken: async () => ["ghs", "_", "c".repeat(36)].join("") }));
// D27: the held-commits merge resolves the literal URL from the workspace row and never stamps.
vi.mock("@/server/current-repo-url", () => ({ getCurrentRepoUrl: async () => "https://github.com/acme/widget" }));
vi.mock("@/server/workspace-repo-mirror", () => ({ writeRepoColsToWorkspace: H.writeRepoCols, writeKbSyncHeldCols: H.writeHeldCols }));
// The self-heal's held-count write (frozen signature): recorded with the count the REAL compute gives on its inputs, so a
// row asserts what would be stored without depending on the write's body.
vi.mock("@/server/kb-sync-held-refresh", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/kb-sync-held-refresh")>();
  return {
    ...actual,
    writeHeldFromIsolated: async (a: Parameters<typeof actual.writeHeldFromIsolated>[0]) => {
      const held = await actual.heldCountOn(a.isolated, a.T, a.headSha, a.workspacePath, a.workspaceId);
      H.heldWrites.push({ T: a.T, headSha: a.headSha, pullBlocked: a.pullBlocked, count: held?.total ?? null });
      return held?.total ?? null;
    },
  };
});
vi.mock("@/lib/supabase/tenant", () => ({ RuntimeAuthError: class RuntimeAuthError extends Error {}, getFreshTenantClient: async () => ({}) }));
vi.mock("@/server/git-hardened-env", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-hardened-env")>();
  return {
    ...actual,
    buildIsolatedGitEnv: (dir: import("@/server/git-hardened-env").IsolatedPushDir, extra: Readonly<Record<string, string>> = {}) => ({
      ...actual.buildIsolatedGitEnv(dir, extra),
      GIT_ALLOW_PROTOCOL: "https:file",
    }),
  };
});
vi.mock("@/server/git-auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-auth")>();
  return {
    ...actual,
    gitWithInstallationAuth: async (args: string[], id: number, opts: import("@/server/git-auth").GitExecOptions = {}) => {
      H.tokenVerbs.push(args[0]);
      try {
        return await actual.gitWithInstallationAuth(args.map((a) => (a === LITERAL_URL ? H.remoteUrl : a)), id, opts);
      } finally {
        H.afterTokenCall?.(args[0]);
      }
    },
  };
});
vi.mock("@/server/workspace-local-git", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/workspace-local-git")>();
  const auth = await import("@/server/git-auth");
  return {
    ...actual,
    runWorkspaceLocalGit: (args: string[], opts: { cwd: string; timeout: number }) =>
      H.localViaTokenArm ? auth.gitWithInstallationAuth(args, 1, opts) : actual.runWorkspaceLocalGit(args, opts),
  };
});
// The fixture remote is file://; widen the clamp on the token-bearing (https) arm only.
vi.mock("@/server/host-git", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/host-git")>();
  return {
    ...actual,
    hostGitInvocation: (args: readonly string[], opts: import("@/server/host-git").HostGitOpts) =>
      actual.hostGitInvocation(args, opts.allowProtocol === actual.ALLOW_PROTOCOL_NONE ? opts : { ...opts, allowProtocol: `${opts.allowProtocol}:file` }),
  };
});

import { syncWorkspace } from "@/server/workspace-sync";

let base = "";
let template = "";
let dateTick = 1_700_000_000;

function fixtureEnv(cwd: string): NodeJS.ProcessEnv {
  const t = `${dateTick++} +0000`;
  return { ...gitFixtureEnv(cwd), GIT_COMMITTER_DATE: t, GIT_AUTHOR_DATE: t };
}
function git(cwd: string, ...args: string[]): string {
  return execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8", env: fixtureEnv(cwd) }).trim();
}
function write(path: string, body: string): void {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, body);
}
const read = (path: string): string => readFileSync(path, "utf8");

interface Row {
  root: string;
  remote: string;
  ws: string;
}

beforeAll(() => {
  base = realpathSync(mkdtempSync(join(tmpdir(), "selfheal-")));
  template = join(base, "template.git");
  execFileSync("git", ["init", "-q", "--bare", "-b", "main", template], { env: gitFixtureEnv(base) });
  const seed = join(base, "seed");
  mkdirSync(seed);
  git(seed, "init", "-q", "-b", "main");
  write(join(seed, "knowledge-base", "a.md"), "a\n");
  write(join(seed, "app", "x.ts"), "export const x = 1;\n");
  write(join(seed, "src", "s.ts"), "export const s = 1;\n");
  write(join(seed, "a.txt"), "a1\n");
  write(join(seed, "b.txt"), "b1\n");
  write(join(seed, "README.md"), "readme\n");
  git(seed, "add", "-A");
  git(seed, "commit", "-q", "-m", "T0");
  git(seed, "push", "-q", template, "main");
}, 30_000);

afterAll(() => {
  if (base) rmSync(base, { recursive: true, force: true });
});

const savedEnv: Record<string, string | undefined> = {};

function newRow(): Row {
  const root = realpathSync(mkdtempSync(join(base, "row-")));
  const remote = join(root, "remote.git");
  cpSync(template, remote, { recursive: true });
  const ws = join(root, "ws");
  execFileSync("git", ["clone", "-q", "--depth", "1", `file://${remote}`, ws], { env: fixtureEnv(root), stdio: "pipe" });
  git(ws, "config", "user.name", "Seeded Local");
  git(ws, "config", "user.email", "local@example.test");
  mkdirSync(join(root, "home"));
  mkdirSync(join(root, "tmp"));
  process.env.HOME = join(root, "home");
  process.env.TMPDIR = join(root, "tmp");
  H.remoteUrl = `file://${remote}`;
  return { root, remote, ws };
}

/** A commit on the remote main made by "someone else". */
function upstreamCommit(r: Row, edit: (dir: string) => void, msg = "upstream"): string {
  const dir = mkdtempSync(join(r.root, "up-"));
  execFileSync("git", ["clone", "-q", `file://${r.remote}`, dir], { env: fixtureEnv(r.root), stdio: "pipe" });
  edit(dir);
  git(dir, "add", "-A");
  git(dir, "commit", "-q", "-m", msg);
  git(dir, "push", "-q", "origin", "HEAD:refs/heads/main");
  return git(dir, "rev-parse", "HEAD");
}

/** A local commit in the workspace (an agent commit, or Soleur's KB auto-commit). */
function localCommit(r: Row, edit: (dir: string) => void, msg = "local"): string {
  edit(r.ws);
  git(r.ws, "add", "-A");
  git(r.ws, "commit", "-q", "-m", msg);
  return git(r.ws, "rev-parse", "HEAD");
}

const heal = (r: Row) => syncWorkspace(1, r.ws, H.log as never, { userId: USER, workspaceId: WS_ID, op: "push" });
const isAncestor = (r: Row, a: string, b: string): boolean => {
  try {
    git(r.ws, "merge-base", "--is-ancestor", a, b);
    return true;
  } catch {
    return false;
  }
};
const mergeHeadPresent = (r: Row): boolean => existsSync(join(r.ws, ".git", "MERGE_HEAD"));
/** `git ls-files -s` plus every tracked file's bytes: equal before and after = the tracked tree is byte-identical. */
const treeBytes = (r: Row): string =>
  git(r.ws, "ls-files", "-s") + git(r.ws, "ls-files").split("\n").filter(Boolean).map((f) => `\n${f}:${read(join(r.ws, f))}`).join("");
const localMain = (r: Row): string => git(r.ws, "rev-parse", "refs/heads/main");
const recoveryBranches = (r: Row): string => git(r.ws, "for-each-ref", "--format=%(refname)", "refs/heads/soleur/");
const warnOps = (): Array<{ op?: string; tags?: Record<string, string> }> =>
  H.mirrorWarnWithDebounce.mock.calls.map(([, ctx]) => ctx as { op?: string; tags?: Record<string, string> });
const allOps = (): string[] =>
  [...H.reportSilentFallback.mock.calls, ...H.warnSilentFallback.mock.calls, ...H.mirrorWithDebounce.mock.calls, ...H.mirrorWarnWithDebounce.mock.calls].map(
    ([, ctx]) => (ctx as { op?: string }).op ?? "",
  );

beforeEach(() => {
  for (const k of ["HOME", "TMPDIR"]) savedEnv[k] = process.env[k];
  H.localViaTokenArm = false;
  H.afterTokenCall = null;
  H.tokenVerbs.length = 0;
  H.writeRepoCols.mockClear();
  H.heldWrites.length = 0;
  for (const f of [H.reportSilentFallback, H.warnSilentFallback, H.mirrorWithDebounce, H.mirrorWarnWithDebounce, H.log.info, H.log.warn, H.log.error, H.log.debug]) f.mockClear();
});

afterEach(() => {
  for (const [k, v] of Object.entries(savedEnv)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
});

describe("self-heal: a dirty tracked tree is never reset (D6a/b, real git)", { timeout: 30_000 }, () => {
  test("git-history seat's measured erase: uncommitted app/x.ts edit + upstream change to the same file, 0 local commits -> preserved", async () => {
    const r = newRow();
    upstreamCommit(r, (d) => write(join(d, "app", "x.ts"), "export const x = 2; // upstream\n"));
    write(join(r.ws, "app", "x.ts"), "export const x = 9; // member edit, uncommitted\n");
    const before = localMain(r);
    const result = await heal(r);
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward" }));
    expect(read(join(r.ws, "app", "x.ts"))).toBe("export const x = 9; // member edit, uncommitted\n");
    expect(localMain(r)).toBe(before);
    expect(warnOps().map((c) => c.op)).toEqual(["self-heal-aborted-dirty-tracked"]);
    expect(allOps()).not.toContain("self-heal-reset");
  });

  test("uncommitted KB edit + held commit + upstream change to the same KB file -> refused, KB edit preserved (supersedes the R18 positive control)", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // held\n"));
    upstreamCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nupstream\n"));
    write(join(r.ws, "knowledge-base", "a.md"), "a\nin-flight kb edit\n");
    const result = await heal(r);
    expect(result.ok).toBe(false);
    expect(read(join(r.ws, "knowledge-base", "a.md"))).toBe("a\nin-flight kb edit\n");
    expect(localMain(r)).toBe(held);
    expect(recoveryBranches(r)).toBe("");
    expect(warnOps().map((c) => c.op)).toEqual(["self-heal-aborted-dirty-tracked"]);
  });

  test("held commit + dirty tracked code file, upstream moves -> refused, code edit preserved (matrix 21 shape)", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, ".github", "workflows", "x.yml"), "on: push\njobs: {}\n"));
    write(join(r.ws, "src", "s.ts"), "export const s = 2; // dirty, uncommitted\n");
    upstreamCommit(r, (d) => write(join(d, "README.md"), "readme 2\n"));
    const result = await heal(r);
    expect(result.ok).toBe(false);
    expect(read(join(r.ws, "src", "s.ts"))).toBe("export const s = 2; // dirty, uncommitted\n");
    expect(localMain(r)).toBe(held);
    expect(warnOps().map((c) => c.op)).toEqual(["self-heal-aborted-dirty-tracked"]);
  });
});

describe("self-heal: held commits are merged, never reset (D27 amending D6(c), real git)", { timeout: 30_000 }, () => {
  test("held code commit + upstream KB push -> merged (hardened pull merge): no reset, no recovery branch, no stamp", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // held code\n"));
    const up = upstreamCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nupstream kb\n"));
    const result = await heal(r);
    expect(result).toEqual({ ok: true });
    expect(isAncestor(r, held, "HEAD")).toBe(true);
    expect(isAncestor(r, up, "HEAD")).toBe(true);
    expect(git(r.ws, "rev-parse", "--abbrev-ref", "HEAD")).toBe("main");
    expect(read(join(r.ws, "src", "s.ts"))).toBe("export const s = 2; // held code\n");
    expect(read(join(r.ws, "knowledge-base", "a.md"))).toBe("a\nupstream kb\n");
    expect(recoveryBranches(r)).toBe("");
    expect(allOps()).not.toContain("self-heal-recovered-diverged");
    expect(allOps()).not.toContain("self-heal-aborted-held-commits");
    expect(H.writeRepoCols).not.toHaveBeenCalled();
    // the merge's token-bearing calls are the hardened ls-remote and fetch; the legacy pull and fetch stay (X3)
    expect(H.tokenVerbs).toEqual(["pull", "fetch", "ls-remote", "fetch"]);
  });

  test("held code commit + a conflicting upstream change -> merge_conflict_precheck: no MERGE_HEAD, tree byte-identical, one report", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // held code\n"));
    upstreamCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 3; // upstream\n"));
    const before = treeBytes(r);
    const result = await heal(r);
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward", held: "held_commits" }));
    expect(localMain(r)).toBe(held);
    expect(mergeHeadPresent(r)).toBe(false);
    expect(treeBytes(r)).toBe(before);
    expect(recoveryBranches(r)).toBe("");
    expect(warnOps()).toEqual([
      expect.objectContaining({ op: "self-heal-aborted-held-commits", tags: { held_kind: "nonkb", reason: "merge_conflict_precheck" } }),
    ]);
    expect(H.writeRepoCols).not.toHaveBeenCalled();
    // D42: the precheck hold is recorded for the cc surfaces, with the count (src/s.ts is held)
    expect(H.heldWrites).toEqual([{ T: git(r.remote, "rev-parse", "refs/heads/main"), headSha: held, pullBlocked: "merge_conflict_precheck", count: 1 }]);
  });

  test("held code commit + an ignored local file at an upstream-added path -> refused, the file byte-identical", async () => {
    const r = newRow();
    localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // held code\n"));
    write(join(r.ws, ".gitignore"), "build/\n");
    git(r.ws, "add", ".gitignore");
    git(r.ws, "commit", "-q", "-m", "ignore build");
    write(join(r.ws, "build", "out.txt"), "local ignored bytes\n");
    upstreamCommit(r, (d) => write(join(d, "build", "out.txt"), "upstream tracked\n"));
    const result = await heal(r);
    expect(result.ok).toBe(false);
    expect(read(join(r.ws, "build", "out.txt"))).toBe("local ignored bytes\n");
    expect(mergeHeadPresent(r)).toBe(false);
    expect(H.writeRepoCols).not.toHaveBeenCalled();
    // D42: the pre-call collision refusal reads T (no merge) and records the hold with the count
    expect(result).toEqual(expect.objectContaining({ held: "untracked_collision" }));
    expect(H.heldWrites).toEqual([
      expect.objectContaining({ T: git(r.remote, "rev-parse", "refs/heads/main"), headSha: git(r.ws, "rev-parse", "HEAD"), pullBlocked: "untracked_collision" }),
    ]);
  });

  test("KB-only unpublished local commit, upstream moves elsewhere -> merged, never stranded on a recovery branch", async () => {
    const r = newRow();
    const kbCommit = localCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nunpublished kb\n"), "Soleur: sync knowledge-base");
    upstreamCommit(r, (d) => write(join(d, "README.md"), "readme 2\n"));
    const result = await heal(r);
    expect(result).toEqual({ ok: true });
    expect(isAncestor(r, kbCommit, "HEAD")).toBe(true);
    expect(read(join(r.ws, "knowledge-base", "a.md"))).toBe("a\nunpublished kb\n");
    expect(recoveryBranches(r)).toBe("");
  });

  test("a path that CONTAINS knowledge-base/ without starting with it (src/knowledge-base/x.ts) counts as non-KB", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "knowledge-base", "x.ts"), "export const k = 1;\n"));
    upstreamCommit(r, (d) => write(join(d, "src", "knowledge-base", "x.ts"), "export const k = 2;\n"));
    const result = await heal(r);
    expect(result.ok).toBe(false);
    expect(localMain(r)).toBe(held);
    expect(warnOps()).toEqual([expect.objectContaining({ op: "self-heal-aborted-held-commits", tags: expect.objectContaining({ held_kind: "nonkb" }) })]);
  });

  test("squash-merged side PR (local KB commit whose content upstream already has) -> branch-aside + reset, nothing lost", async () => {
    const r = newRow();
    const side = localCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nkb via side PR\n"), "Soleur: sync knowledge-base");
    const squash = upstreamCommit(r, (d) => {
      write(join(d, "knowledge-base", "a.md"), "a\nkb via side PR\n");
      write(join(d, "README.md"), "readme 2\n");
    }, "Soleur: sync knowledge-base (#7)");
    const result = await heal(r);
    expect(result).toEqual({ ok: true, recovered: true });
    expect(localMain(r)).toBe(squash);
    const branches = recoveryBranches(r).split("\n").filter(Boolean);
    expect(branches).toHaveLength(1);
    expect(git(r.ws, "rev-parse", branches[0])).toBe(side);
    expect(H.warnSilentFallback.mock.calls.map(([, c]) => (c as { op: string }).op)).toEqual(["self-heal-recovered-diverged"]);
  });
});

describe("self-heal: phantom arm branch check (D6f, real git)", { timeout: 30_000 }, () => {
  test("feature branch, 0 local commits, clean tracked tree (untracked collision) -> abort, branch and untracked file unchanged", async () => {
    const r = newRow();
    git(r.ws, "checkout", "-q", "-b", "feat", "--track", "origin/main");
    const before = git(r.ws, "rev-parse", "HEAD");
    write(join(r.ws, "new.txt"), "member untracked\n");
    upstreamCommit(r, (d) => write(join(d, "new.txt"), "upstream tracked\n"));
    const result = await heal(r);
    expect(result.ok).toBe(false);
    expect(git(r.ws, "rev-parse", "refs/heads/feat")).toBe(before);
    expect(read(join(r.ws, "new.txt"))).toBe("member untracked\n");
    // D15(e): debounced per workspace, still error level
    expect(H.mirrorWithDebounce.mock.calls.map(([, c, key, cls]) => [(c as { op: string }).op, key, cls])).toEqual([["self-heal-aborted-dirty", r.ws, "self-heal-aborted-dirty"]]);
    expect(H.reportSilentFallback).not.toHaveBeenCalled();
  });
});

/**
 * A diverged default-branch clone whose one local commit is already upstream (the squash-merged side-PR shape), so every
 * D6 gate passes and only the D15(a) precheck stands between the reset and the paths `upstreamEdit` adds. Untracked
 * files must be written AFTER this call (`localCommit` stages with `add -A`).
 */
function squashedDiverged(r: Row, upstreamEdit: (dir: string) => void): void {
  localCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nkb via side PR\n"), "Soleur: sync knowledge-base");
  upstreamCommit(r, (d) => {
    write(join(d, "knowledge-base", "a.md"), "a\nkb via side PR\n");
    upstreamEdit(d);
  }, "Soleur: sync knowledge-base (#7)");
}

/** The one untracked-collision refusal of the turn (D15a): warning, debounced on the workspace, `arm` the only tag. */
function expectCollisionRefusal(r: Row, result: Awaited<ReturnType<typeof heal>>, arm: "phantom" | "diverged", mainBefore: string): void {
  expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward", held: "untracked_collision" }));
  expect(localMain(r)).toBe(mainBefore);
  expect(recoveryBranches(r)).toBe("");
  expect(H.mirrorWarnWithDebounce.mock.calls).toHaveLength(1);
  const [err, ctx, key, cls] = H.mirrorWarnWithDebounce.mock.calls[0] as [unknown, { op: string; tags: Record<string, string>; extra: Record<string, unknown>; message: string }, string, string];
  expect(err).toBeNull();
  expect(ctx.op).toBe("self-heal-aborted-untracked-collision");
  expect(ctx.tags).toEqual({ arm });
  expect(ctx.extra).toEqual({ userId: USER });
  expect([key, cls]).toEqual([r.ws, "self-heal-aborted-untracked-collision"]);
  expect(allOps()).toEqual(["self-heal-aborted-untracked-collision"]);
}

describe("self-heal: an untracked or ignored file in the reset's way is never replaced (D15a, real git)", { timeout: 30_000 }, () => {
  test("data-integrity PC repro: untracked KB file at a path upstream adds, 0 local commits -> refused, the agent's bytes survive", async () => {
    const r = newRow();
    write(join(r.ws, "knowledge-base", "new.md"), "agent in-flight work\n");
    upstreamCommit(r, (d) => write(join(d, "knowledge-base", "new.md"), "uploaded via UI\n"));
    const before = localMain(r);
    const result = await heal(r);
    expect(read(join(r.ws, "knowledge-base", "new.md"))).toBe("agent in-flight work\n");
    expectCollisionRefusal(r, result, "phantom", before);
  });

  test("untracked FILE at a leading directory of an added path (docs vs docs/guide.md) -> refused, file survives", async () => {
    const r = newRow();
    squashedDiverged(r, (d) => write(join(d, "docs", "guide.md"), "upstream guide\n"));
    write(join(r.ws, "docs"), "member notes, a plain file\n");
    const before = localMain(r);
    const result = await heal(r);
    expect(read(join(r.ws, "docs"))).toBe("member notes, a plain file\n");
    expectCollisionRefusal(r, result, "diverged", before);
  });

  test("untracked file inside a directory that an added path turns into a file (src/ -> src) -> refused, file survives", async () => {
    const r = newRow();
    squashedDiverged(r, (d) => {
      rmSync(join(d, "src"), { recursive: true, force: true });
      write(join(d, "src"), "src is now a file upstream\n");
    });
    write(join(r.ws, "src", "local-notes.txt"), "member untracked notes\n");
    const before = localMain(r);
    const result = await heal(r);
    expect(read(join(r.ws, "src", "local-notes.txt"))).toBe("member untracked notes\n");
    expectCollisionRefusal(r, result, "diverged", before);
  });

  test("IGNORED file at an added path (reset --keep alone overwrites it) -> refused, file survives", async () => {
    const r = newRow();
    squashedDiverged(r, (d) => write(join(d, "settings.local"), "upstream settings\n"));
    write(join(r.ws, ".git", "info", "exclude"), "*.local\n");
    write(join(r.ws, "settings.local"), "member settings, ignored\n");
    expect(git(r.ws, "status", "--porcelain", "--untracked-files=all")).toBe("");
    const before = localMain(r);
    const result = await heal(r);
    expect(read(join(r.ws, "settings.local"))).toBe("member settings, ignored\n");
    expectCollisionRefusal(r, result, "diverged", before);
  });

  test("D23 pin for `ls-files --directory`: a NESTED ignored file under a directory an added path turns into a file still refuses", async () => {
    const r = newRow();
    squashedDiverged(r, (d) => {
      rmSync(join(d, "src"), { recursive: true, force: true });
      write(join(d, "src"), "src is now a file upstream\n");
    });
    // src/build/ holds ONLY ignored content, two levels down: `--directory` collapses it to one `src/build/` entry,
    // which is still non-empty output (ls-files applies no exclude without --exclude-standard)
    write(join(r.ws, ".git", "info", "exclude"), "build/\n");
    write(join(r.ws, "src", "build", "deep", "out.o"), "member build output, ignored\n");
    expect(git(r.ws, "status", "--porcelain", "--untracked-files=all")).toBe("");
    const before = localMain(r);
    const result = await heal(r);
    expect(read(join(r.ws, "src", "build", "deep", "out.o"))).toBe("member build output, ignored\n");
    expectCollisionRefusal(r, result, "diverged", before);
  });

  test("control: an untracked file the reset does not touch survives a recovered reset, and a deleted tracked leading path is not a collision", async () => {
    const r = newRow();
    // upstream turns the tracked FILE a.txt into a directory: the leading `a.txt` on disk is a deleted tracked path
    squashedDiverged(r, (d) => {
      rmSync(join(d, "a.txt"));
      write(join(d, "a.txt", "inner.md"), "now a directory\n");
    });
    write(join(r.ws, "scratch.txt"), "unrelated untracked\n");
    const result = await heal(r);
    expect(result).toEqual({ ok: true, recovered: true });
    expect(read(join(r.ws, "scratch.txt"))).toBe("unrelated untracked\n");
    expect(read(join(r.ws, "a.txt", "inner.md"))).toBe("now a directory\n");
    expect(allOps()).toEqual(["self-heal-recovered-diverged"]);
  });
});

describe("self-heal: the gate reads the remote-tracking ref, never an agent-writable alias (D15b/c, real git)", { timeout: 30_000 }, () => {
  test("branch.main.remote=. (so @{u} is a local decoy branch HEAD is behind) does not hide a held commit", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // held code\n"));
    upstreamCommit(r, (d) => write(join(d, "README.md"), "readme 2\n"));
    // decoy = held + new.txt; with an untracked new.txt on disk the ff-only pull from `.` fails (a non_fast_forward
    // class), so the self-heal runs while `@{u}..HEAD` counts 0 (HEAD is an ancestor of the decoy)
    localCommit(r, (d) => write(join(d, "new.txt"), "decoy\n"), "decoy");
    git(r.ws, "branch", "decoy");
    git(r.ws, "reset", "-q", "--hard", held);
    write(join(r.ws, "new.txt"), "member untracked\n");
    git(r.ws, "config", "branch.main.remote", ".");
    git(r.ws, "config", "branch.main.merge", "refs/heads/decoy");
    expect(git(r.ws, "rev-list", "--count", "@{u}..HEAD")).toBe("0");
    const result = await heal(r);
    // D27: the held commit is kept by a merge with the remote tip ls-remote names, never reset away
    expect(result).toEqual({ ok: true });
    expect(isAncestor(r, held, "HEAD")).toBe(true);
    expect(isAncestor(r, git(r.remote, "rev-parse", "refs/heads/main"), "HEAD")).toBe(true);
    expect(read(join(r.ws, "src", "s.ts"))).toBe("export const s = 2; // held code\n");
    expect(recoveryBranches(r)).toBe("");
  });

  test("a local branch named origin/main (refs/heads/origin/main, which DWIM prefers) does not stand in for the remote", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 3; // held code\n"));
    upstreamCommit(r, (d) => write(join(d, "README.md"), "readme 3\n"));
    git(r.ws, "update-ref", "refs/heads/origin/main", held);
    const result = await heal(r);
    expect(result).toEqual({ ok: true });
    expect(isAncestor(r, held, "refs/heads/main")).toBe(true);
    expect(isAncestor(r, git(r.remote, "rev-parse", "refs/heads/main"), "refs/heads/main")).toBe(true);
    expect(git(r.ws, "for-each-ref", "--format=%(refname)", "refs/heads/soleur/")).toBe("");
  });
});

describe("self-heal: no token reaches a planted clean/smudge filter (D6d, real git)", { timeout: 30_000 }, () => {
  /**
   * Squash-merged side shape (so the gate passes and the reset runs), with a planted `filter.x` in the agent-writable
   * `.git/config` + `.git/info/attributes`, and a stat-dirty tracked `b.txt` so `status` re-hashes it through `clean`.
   * The reset checks out the upstream `a.txt` through `smudge`. Each filter run appends `RAN:<token or none>` to `leak`.
   * The leak file is emptied after the token-bearing `fetch`, so it records only the gate and the reset.
   */
  async function plantedFilterRun(viaTokenArm: boolean): Promise<string> {
    const r = newRow();
    localCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nkb via side PR\n"));
    upstreamCommit(r, (d) => {
      write(join(d, "knowledge-base", "a.md"), "a\nkb via side PR\n");
      write(join(d, "a.txt"), "a2\n");
    });
    const leak = join(r.root, "leak");
    writeFileSync(leak, "");
    const cmd = `printf 'RAN:%s\\n' "\${GIT_INSTALLATION_TOKEN:-none}" >> '${leak}'; cat`;
    git(r.ws, "config", "filter.x.clean", cmd);
    git(r.ws, "config", "filter.x.smudge", cmd);
    write(join(r.ws, ".git", "info", "attributes"), "*.txt filter=x\n");
    const future = new Date(Date.now() + 60_000);
    utimesSync(join(r.ws, "b.txt"), future, future);
    H.afterTokenCall = (verb) => {
      if (verb === "fetch") writeFileSync(leak, "");
    };
    H.localViaTokenArm = viaTokenArm;
    const result = await heal(r);
    expect(result).toEqual({ ok: true, recovered: true });
    expect(read(join(r.ws, "a.txt"))).toBe("a2\n");
    return read(leak);
  }

  test("known-positive: routing the local verbs through the token-bearing arm leaks the synthetic token to the filter", async () => {
    const leak = await plantedFilterRun(true);
    expect(leak).toContain(`RAN:${TOKEN}`);
  });

  test("token-free runner: the filter still runs during the gate and the reset, but sees no token", async () => {
    const leak = await plantedFilterRun(false);
    expect(leak).toMatch(/RAN:none/);
    expect(leak).not.toContain(TOKEN);
    expect(leak).not.toContain("ghs_");
    // D15(d): `symbolic-ref` is a local verb and runs token-free; only `pull` and `fetch origin` carry the token
    expect(new Set(H.tokenVerbs)).toEqual(new Set(["pull", "fetch"]));
  });
});

describe("self-heal: review fix round 1, WP2 (D37, D39(a), D42, real git)", { timeout: 30_000 }, () => {
  test("D39(a): the squash-merge scenario: held code that GitHub already merged as a squash is merged in and the count is rewritten to 0", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // held code\n"));
    upstreamCommit(r, (d) => {
      write(join(d, "src", "s.ts"), "export const s = 2; // held code\n");
      write(join(d, "README.md"), "readme 2\n");
    }, "held code (#9, squash)");
    const T = git(r.remote, "rev-parse", "refs/heads/main");
    const result = await heal(r);
    expect(result).toEqual({ ok: true });
    expect(isAncestor(r, held, "HEAD")).toBe(true);
    expect(isAncestor(r, T, "HEAD")).toBe(true);
    // one write, on this run's T and the POST-merge HEAD, clearing pullBlocked: nothing is held any more
    expect(H.heldWrites).toEqual([{ T, headSha: git(r.ws, "rev-parse", "HEAD"), pullBlocked: null, count: 0 }]);
  });

  // needs WP1: the writer's entry check (D37(1), server/connected-repo-git.ts `kbPullWriter().merge`).
  test("D37(1), data P2-2 repro: a stale MERGE_AUTOSTASH alone -> unresolved_merge, no merge child, worktree and HEAD unchanged", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // held code\n"));
    upstreamCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nupstream kb\n"));
    // an interrupted earlier merge left only its autostash pointer (the tracked tree reads clean to the dirty gate)
    const stash = git(r.ws, "commit-tree", "-m", "autostash", "-p", "HEAD", "HEAD^{tree}");
    writeFileSync(join(r.ws, ".git", "MERGE_AUTOSTASH"), `${stash}\n`);
    const before = treeBytes(r);
    const result = await heal(r);
    expect(result).toEqual(expect.objectContaining({ ok: false, held: "held_commits" }));
    expect(localMain(r)).toBe(held);
    expect(treeBytes(r)).toBe(before);
    expect(mergeHeadPresent(r)).toBe(false);
    expect(existsSync(join(r.ws, ".git", "MERGE_AUTOSTASH"))).toBe(true); // never moved or deleted (D36(c))
    expect(warnOps()).toEqual([expect.objectContaining({ op: "self-heal-aborted-held-commits", tags: expect.objectContaining({ reason: "unresolved_merge" }) })]);
    expect(H.heldWrites).toEqual([]);
  });

  // needs WP1: the second pinned merge shape (D37(2), server/connected-repo-git.ts `mergeArgv` / `AUTO_MERGE_MSG_SELF_HEAL`).
  test("D37(2): the self-heal's merge commit carries the self-heal message, not the session-start one", async () => {
    const r = newRow();
    localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // held code\n"));
    upstreamCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nupstream kb\n"));
    expect(await heal(r)).toEqual({ ok: true });
    expect(git(r.ws, "log", "-1", "--format=%s", "HEAD")).toBe("Soleur: merge GitHub into workspace");
    expect(git(r.ws, "rev-list", "--parents", "-n", "1", "HEAD").split(" ")).toHaveLength(3);
  });
});
