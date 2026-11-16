// Real-git rows for the workspace self-heal (#12600, CTO rulings D6 and D7; supersede R18's KB exemption and gate
// placement). Each row drives the REAL `syncWorkspace` against a local bare `file://` remote and asserts EFFECTS on the
// workspace: file bytes, the local branch, recovery branches. Unit rows: test/server/workspace-sync-self-heal-gate.test.ts.
//
// Fixture rules (as test/session-sync-kb-only-push-real-git.test.ts): a template remote built once and COPIED per row;
// workspaces are `git clone --depth 1`; fixture git runs under `gitFixtureEnv` with increasing dates; the host-git
// protocol clamp is widened to `file` for the token-bearing arm only (the token-free runner keeps `none`). Synthesized
// data only (cq-test-fixtures-synthesized-only): the token is built by concatenation.
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const USER = "77777777-7777-4777-8777-777777777777";
const TOKEN = ["ghs", "_", "c".repeat(36)].join("");

const H = vi.hoisted(() => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  /** Known-positive switch: route the self-heal's LOCAL verbs through the token-bearing legacy arm (the pre-D6d shape). */
  localViaTokenArm: false,
  /** Called after each token-bearing call returns (args[0] = verb). */
  afterTokenCall: null as null | ((verb: string) => void),
  tokenVerbs: [] as string[],
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: H.reportSilentFallback,
  warnSilentFallback: H.warnSilentFallback,
  mirrorWarnWithDebounce: H.mirrorWarnWithDebounce,
  hashUserId: (x: string) => `h-${x}`,
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => H.log, default: H.log }));
vi.mock("@/server/github-app", () => ({ generateInstallationToken: async () => ["ghs", "_", "c".repeat(36)].join("") }));
vi.mock("@/server/git-auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-auth")>();
  return {
    ...actual,
    gitWithInstallationAuth: async (args: string[], id: number, opts: import("@/server/git-auth").GitExecOptions = {}) => {
      H.tokenVerbs.push(args[0]);
      try {
        return await actual.gitWithInstallationAuth(args, id, opts);
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

const heal = (r: Row) => syncWorkspace(1, r.ws, H.log as never, { userId: USER, op: "push" });
const localMain = (r: Row): string => git(r.ws, "rev-parse", "refs/heads/main");
const recoveryBranches = (r: Row): string => git(r.ws, "for-each-ref", "--format=%(refname)", "refs/heads/soleur/");
const warnOps = (): Array<{ op?: string; tags?: Record<string, string> }> =>
  H.mirrorWarnWithDebounce.mock.calls.map(([, ctx]) => ctx as { op?: string; tags?: Record<string, string> });
const allOps = (): string[] =>
  [...H.reportSilentFallback.mock.calls, ...H.warnSilentFallback.mock.calls, ...H.mirrorWarnWithDebounce.mock.calls].map(
    ([, ctx]) => (ctx as { op?: string }).op ?? "",
  );

beforeEach(() => {
  for (const k of ["HOME", "TMPDIR"]) savedEnv[k] = process.env[k];
  H.localViaTokenArm = false;
  H.afterTokenCall = null;
  H.tokenVerbs.length = 0;
  for (const f of [H.reportSilentFallback, H.warnSilentFallback, H.mirrorWarnWithDebounce, H.log.info, H.log.warn, H.log.error, H.log.debug]) f.mockClear();
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

describe("self-heal: held commits reset only when their content is upstream (D6c interim, real git)", { timeout: 30_000 }, () => {
  test("held code commit + upstream KB push -> not reset, not branched aside; op self-heal-aborted-held-commits held_kind nonkb", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // held code\n"));
    upstreamCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nupstream kb\n"));
    const result = await heal(r);
    expect(result).toEqual(expect.objectContaining({ ok: false, errorClass: "non_fast_forward" }));
    expect(localMain(r)).toBe(held);
    expect(git(r.ws, "rev-parse", "--abbrev-ref", "HEAD")).toBe("main");
    expect(read(join(r.ws, "src", "s.ts"))).toBe("export const s = 2; // held code\n");
    expect(recoveryBranches(r)).toBe("");
    expect(warnOps()).toEqual([expect.objectContaining({ op: "self-heal-aborted-held-commits", tags: { held_kind: "nonkb", reason: "merge_not_attempted" } })]);
  });

  test("KB-only unpublished local commit, upstream moves elsewhere -> not stranded on a recovery branch; held_kind kb", async () => {
    const r = newRow();
    const kbCommit = localCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nunpublished kb\n"), "Soleur: sync knowledge-base");
    upstreamCommit(r, (d) => write(join(d, "README.md"), "readme 2\n"));
    const result = await heal(r);
    expect(result.ok).toBe(false);
    expect(localMain(r)).toBe(kbCommit);
    expect(read(join(r.ws, "knowledge-base", "a.md"))).toBe("a\nunpublished kb\n");
    expect(recoveryBranches(r)).toBe("");
    expect(warnOps()).toEqual([expect.objectContaining({ op: "self-heal-aborted-held-commits", tags: { held_kind: "kb", reason: "merge_not_attempted" } })]);
  });

  test("a path that CONTAINS knowledge-base/ without starting with it (src/knowledge-base/x.ts) counts as non-KB", async () => {
    const r = newRow();
    const held = localCommit(r, (d) => write(join(d, "src", "knowledge-base", "x.ts"), "export const k = 1;\n"));
    upstreamCommit(r, (d) => write(join(d, "README.md"), "readme 2\n"));
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
    expect(H.reportSilentFallback.mock.calls.map(([, c]) => (c as { op: string }).op)).toEqual(["self-heal-aborted-dirty"]);
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
    expect(new Set(H.tokenVerbs)).toEqual(new Set(["pull", "symbolic-ref", "fetch"]));
  });
});
