// Real-git battery for #12718: the session-start `syncPull` on the hardened arm (rulings X1, X4, X5, D25-D28).
//
// Every row drives the REAL `syncPull` (and, where named, the real `syncPush` and the checkpoint restore) against a
// local bare `file://` remote standing in for `https://github.com/acme/widget.git`, and asserts EFFECTS on the
// workspace: HEAD, its parents, MERGE_HEAD, file bytes, the stash, the shallow file, the objects present. Recorded argv
// is the secondary evidence (which children ran, with what arm).
//
// Fixture rules (plan "Test Scenarios — #12718"): a template remote built once in `beforeAll` and COPIED per row, so
// every row that moves the remote has its own bare remote (D26(6)); workspaces are `git clone --depth 1`; fixture git
// runs under the app-local `gitFixtureEnv` re-export with increasing dates; the token-bearing call is wrapped to rewrite
// ONLY the literal fixture URL to the local remote. Synthesized data only (cq-test-fixtures-synthesized-only): the token
// is built by concatenation.
import { execFileSync, spawn } from "node:child_process";
import { chmodSync, cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "./helpers/git-fixture-env";

const LITERAL_URL = "https://github.com/acme/widget.git";
const USER = "77777777-7777-4777-8777-777777777777";
const WS_ID = "11111111-1111-4111-8111-111111111111";
const TOKEN = ["ghs", "_", "PULLSENTINEL", "q".repeat(24)].join("");

const H = vi.hoisted(() => ({
  calls: [] as Array<{ args: string[]; hardened: boolean; cwd: string | undefined }>,
  remoteUrl: "",
  /** Every host-side git argv (the caller's part, before the shared hardening block). */
  host: [] as string[][],
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
  iso: [] as Array<{ args: string[]; input: string; code: number }>,
  writeRepoCols: vi.fn(async () => undefined),
  writeHeld: vi.fn(async () => undefined),
  rpc: vi.fn(async () => ({ data: null, error: null })),
  prs: [] as Array<{ number: number; htmlUrl: string; url: string; state: "open" | "closed"; merged: boolean; headSha: string }>,
  prListFails: false,
  sideTipNow: (() => "") as () => string,
  createPullRequest: vi.fn(async () => ({ htmlUrl: "https://github.com/acme/widget/pull/1" })),
  listPullRequestsForHead: vi.fn(async () => [] as unknown[]),
  findOpenPullRequest: vi.fn(async () => null as null | { htmlUrl: string }),
  /** When set, the isolated env carries GIT_TRACE / GIT_TRACE_PACKET into these files (TX2). */
  trace: null as null | { trace: string; packet: string },
  /** Extra transports for the isolated arm and the legacy arm (TX1-f adds http). */
  extraProtocols: "file",
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: H.reportSilentFallback,
  warnSilentFallback: H.warnSilentFallback,
  mirrorWithDebounce: H.mirrorWithDebounce,
  mirrorWarnWithDebounce: H.mirrorWarnWithDebounce,
  hashUserId: (x: string) => `h-${x}`,
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => H.log, default: H.log }));
vi.mock("@/server/workspace-repo-mirror", () => ({ writeRepoColsToWorkspace: H.writeRepoCols, writeKbSyncHeldCols: H.writeHeld }));
vi.mock("@/server/resolve-installation-id", () => ({ resolveInstallationId: async () => 1 }));
vi.mock("@/server/current-repo-url", () => ({ getCurrentRepoUrl: async () => "https://github.com/acme/widget" }));
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: async () => ["ghs", "_", "PULLSENTINEL", "q".repeat(24)].join(""),
  findOpenPullRequest: H.findOpenPullRequest,
  createPullRequest: H.createPullRequest,
  listPullRequestsForHead: H.listPullRequestsForHead,
}));
vi.mock("@/lib/supabase/tenant", () => {
  class RuntimeAuthError extends Error {}
  const chain = { maybeSingle: async () => ({ data: { id: "u" }, error: null }) };
  return {
    RuntimeAuthError,
    getFreshTenantClient: async () => ({ from: () => ({ select: () => ({ eq: () => chain }) }), rpc: H.rpc }),
  };
});
vi.mock("@/server/git-auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-auth")>();
  return {
    ...actual,
    gitWithInstallationAuth: async (args: string[], id: number, opts: import("@/server/git-auth").GitExecOptions = {}) => {
      H.calls.push({ args: [...args], hardened: opts.hardened !== undefined, cwd: opts.cwd });
      return actual.gitWithInstallationAuth(args.map((a) => (a === LITERAL_URL ? H.remoteUrl : a)), id, opts);
    },
  };
});
// Test-only: the production clamp is `https`; the fixture remote is file:// (and http:// in TX1-f).
vi.mock("@/server/git-hardened-env", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-hardened-env")>();
  return {
    ...actual,
    buildIsolatedGitEnv: (dir: import("@/server/git-hardened-env").IsolatedPushDir, extra: Readonly<Record<string, string>> = {}) => ({
      ...actual.buildIsolatedGitEnv(dir, extra),
      GIT_ALLOW_PROTOCOL: `https:${H.extraProtocols}`,
      ...(H.trace ? { GIT_TRACE: H.trace.trace, GIT_TRACE_PACKET: H.trace.packet } : {}),
    }),
  };
});
vi.mock("@/server/git-isolated-local", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-isolated-local")>();
  return {
    ...actual,
    runIsolatedGitLocal: async (
      iso: import("@/server/git-hardened-env").IsolatedPushDir,
      args: readonly string[],
      opts: import("@/server/git-isolated-local").IsolatedGitLocalOptions = {},
    ) => {
      const r = await actual.runIsolatedGitLocal(iso, args, opts);
      H.iso.push({ args: [...args], input: opts.input === undefined ? "" : opts.input.toString(), code: r.code });
      return r;
    },
  };
});
vi.mock("@/server/host-git", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/host-git")>();
  return {
    ...actual,
    hostGitInvocation: (args: readonly string[], opts: import("@/server/host-git").HostGitOpts) => {
      H.host.push([...args]);
      return actual.hostGitInvocation(
        args,
        opts.allowProtocol === actual.ALLOW_PROTOCOL_NONE ? opts : { ...opts, allowProtocol: `${opts.allowProtocol}:${H.extraProtocols}` },
      );
    },
  };
});

import { gitWithInstallationAuth } from "@/server/git-auth";
import { AUTO_MERGE_MSG_PULL } from "@/server/kb-sync-pull";
import { checkpointInflightWork, restoreInflightCheckpoint } from "@/server/inflight-checkpoint";
import { syncPull, syncPush } from "@/server/session-sync";

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
function gitOk(cwd: string, ...args: string[]): boolean {
  try {
    execFileSync("git", args, { cwd, stdio: "pipe", env: fixtureEnv(cwd) });
    return true;
  } catch {
    return false;
  }
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
  T: string;
}

beforeAll(() => {
  base = realpathSync(mkdtempSync(join(tmpdir(), "kbpull-")));
  template = join(base, "template.git");
  execFileSync("git", ["init", "-q", "--bare", "-b", "main", template], { env: gitFixtureEnv(base) });
  const seed = join(base, "seed");
  mkdirSync(seed);
  git(seed, "init", "-q", "-b", "main");
  write(join(seed, "knowledge-base", "a.md"), "a\n");
  write(join(seed, "knowledge-base", "nested", "b.md"), "b\n");
  write(join(seed, "src", "s.ts"), "export const s = 1;\n");
  write(join(seed, "src", "x.ts"), "export const x = 1;\n");
  write(join(seed, "README.md"), "readme\n");
  write(join(seed, ".gitignore"), "build/\n");
  git(seed, "add", "-A");
  git(seed, "commit", "-q", "-m", "T0");
  git(seed, "push", "-q", template, "main");
}, 30_000);

afterAll(() => {
  if (base) rmSync(base, { recursive: true, force: true });
});

const savedEnv: Record<string, string | undefined> = {};
let row: Row;

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
  row = { root, remote, ws, T: git(remote, "rev-parse", "refs/heads/main") };
  return row;
}

/** A commit on the remote `ref` made by "someone else" (a scratch clone; the ref is moved on the bare remote). */
function upstreamCommit(r: Row, edit: (dir: string) => void, msg = "upstream", ref = "refs/heads/main", from = "main"): string {
  const dir = mkdtempSync(join(r.root, "up-"));
  execFileSync("git", ["clone", "-q", `file://${r.remote}`, dir], { env: fixtureEnv(r.root), stdio: "pipe" });
  if (from !== "main") git(dir, "checkout", "-q", "--detach", from);
  edit(dir);
  git(dir, "add", "-A");
  git(dir, "commit", "-q", "-m", msg);
  const sha = git(dir, "rev-parse", "HEAD");
  git(dir, "push", "-q", "origin", `HEAD:refs/heads/tmp-up-${sha.slice(0, 8)}`);
  git(r.remote, "update-ref", ref, sha);
  git(r.remote, "update-ref", "-d", `refs/heads/tmp-up-${sha.slice(0, 8)}`);
  return sha;
}

/** The side tip `soleur/kb-sync` on the remote: a commit on top of `from` (default: the remote main). */
const sideCommit = (r: Row, edit: (dir: string) => void, from = "main"): string =>
  upstreamCommit(r, edit, "Soleur: sync knowledge-base", "refs/heads/soleur/kb-sync", from === "main" ? git(r.remote, "rev-parse", "refs/heads/main") : from);

const head = (r: Row): string => git(r.ws, "rev-parse", "HEAD");
const parentsOf = (r: Row, sha: string): string[] => git(r.ws, "rev-list", "--parents", "-n", "1", sha).split(" ").slice(1);
const isAncestor = (r: Row, a: string, b: string): boolean => gitOk(r.ws, "merge-base", "--is-ancestor", a, b);
const hasObject = (r: Row, sha: string): boolean => gitOk(r.ws, "cat-file", "-e", `${sha}^{object}`);
const mergeHead = (r: Row): boolean => existsSync(join(r.ws, ".git", "MERGE_HEAD"));
const status = (r: Row): string =>
  execFileSync("git", ["status", "--porcelain"], { cwd: r.ws, encoding: "utf8", env: fixtureEnv(r.ws) }).replace(/\n$/, "");
const pullLines = (): Array<{ reason: string; ref?: string }> =>
  H.log.info.mock.calls.filter(([o]) => (o as { op?: string })?.op === "kb-sync.pull-held").map(([o]) => o as { reason: string; ref?: string });
const pullWarn = (reason: string): unknown[] =>
  H.mirrorWarnWithDebounce.mock.calls.filter(([, , , cls]) => cls === `kb-sync-pull-held:${reason}`);
const stamps = (): number =>
  H.writeRepoCols.mock.calls.filter((c) => Object.prototype.hasOwnProperty.call((c as unknown[])[2] ?? {}, "repo_last_synced_at")).length;
const tokenVerbs = (): string[] => H.calls.map((c) => c.args[0]);
/** The workspace git children that ran a given subcommand (exact argv element). */
const hostRan = (verb: string): string[][] => H.host.filter((a) => a.includes(verb));
const isoRan = (verb: string): number => H.iso.filter((c) => c.args.includes(verb)).length;

const pull = (r: Row, opts?: Parameters<typeof syncPull>[4]) => syncPull(USER, r.ws, {} as never, WS_ID, opts);

const resetTurn = (): void => {
  H.calls.length = 0;
  H.host.length = 0;
  H.iso.length = 0;
  for (const f of [H.reportSilentFallback, H.warnSilentFallback, H.mirrorWithDebounce, H.mirrorWarnWithDebounce, H.writeRepoCols, H.writeHeld, H.createPullRequest, H.listPullRequestsForHead, H.log.info]) f.mockClear();
};

beforeEach(() => {
  for (const k of ["HOME", "TMPDIR", "GIT_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"]) savedEnv[k] = process.env[k];
  row = undefined as unknown as Row;
  H.trace = null;
  H.extraProtocols = "file";
  H.prListFails = false;
  resetTurn();
  H.prs.length = 0;
  H.sideTipNow = () => (row ? gitOrNull(row.remote, "refs/heads/soleur/kb-sync") ?? "" : "");
  H.createPullRequest.mockImplementation(async () => {
    const n = H.prs.length + 1;
    const pr = { number: n, htmlUrl: `https://github.com/acme/widget/pull/${n}`, url: "", state: "open" as const, merged: false, headSha: H.sideTipNow() };
    H.prs.push(pr);
    return pr;
  });
  H.listPullRequestsForHead.mockImplementation(async () => {
    if (H.prListFails) throw new Error("502 from the list endpoint");
    return H.prs.map((p) => ({ ...p }));
  });
});

function gitOrNull(cwd: string, ref: string): string | null {
  try {
    return git(cwd, "rev-parse", "--verify", "--quiet", ref);
  } catch {
    return null;
  }
}

afterEach(() => {
  for (const [k, v] of Object.entries(savedEnv)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  // every row: the isolated directory is disposed
  if (row && existsSync(join(row.root, "home", ".soleur-push"))) {
    expect(readdirSync(join(row.root, "home", ".soleur-push"))).toEqual([]);
  }
});

const openPr = (P: string): void => {
  H.prs.push({ number: 7, htmlUrl: "https://github.com/acme/widget/pull/7", url: "", state: "open", merged: false, headSha: P });
};

describe("syncPull on the hardened arm: the default-branch merge (TX1, real git)", { timeout: 30_000 }, () => {
  test("TX1-a: upstream 3 commits ahead of a --depth 1 workspace -> all merged, connectivity intact, workspace shallow unchanged", async () => {
    const r = newRow();
    const shallowBefore = read(join(r.ws, ".git", "shallow"));
    const ups = [1, 2, 3].map((i) => upstreamCommit(r, (d) => write(join(d, "src", "x.ts"), `export const x = ${i + 1};\n`), `u${i}`));
    const result = await pull(r);
    // #12714: the count is computed on the pull's own isolated dir after the merge (nothing local is held here) and written
    expect(result).toEqual({ heldFiles: 0, onRecovered: 0, pullReason: "merged", checkedAt: expect.any(String) });
    expect(H.writeHeld).toHaveBeenCalledTimes(1);
    expect(H.writeHeld.mock.calls[0].slice(1)).toEqual([WS_ID, { heldFiles: 0, checkedAt: new Date(result.checkedAt as string) }]);
    for (const u of ups) expect(isAncestor(r, u, "HEAD")).toBe(true);
    expect(gitOk(r.ws, "rev-list", "--objects", "HEAD")).toBe(true);
    expect(gitOk(r.ws, "fsck", "--connectivity-only")).toBe(true);
    expect(read(join(r.ws, ".git", "shallow"))).toBe(shallowBefore);
    expect(read(join(r.ws, "src", "x.ts"))).toBe("export const x = 4;\n");
    expect(stamps()).toBe(1);
  });

  test("TX1-a (real shallow store): a remote that became a shallow store with another boundary -> shallow_changed, HEAD unchanged", async () => {
    const r = newRow();
    const before = head(r);
    // the remote moves on, then is replaced by a shallow store (receive.shallowUpdate + a --depth 1 push) whose boundary is
    // the moved tip, not the workspace's: no seam, the isolated fetch meets a real shallow history.
    upstreamCommit(r, (d) => write(join(d, "src", "x.ts"), "export const x = 2;\n"), "u1");
    upstreamCommit(r, (d) => write(join(d, "src", "x.ts"), "export const x = 3;\n"), "u2");
    const store = join(r.root, "shallow-store.git");
    execFileSync("git", ["init", "-q", "--bare", "-b", "main", store], { env: fixtureEnv(r.root) });
    git(store, "config", "receive.shallowUpdate", "true");
    const sc = join(r.root, "sc");
    execFileSync("git", ["clone", "-q", "--depth", "1", `file://${r.remote}`, sc], { env: fixtureEnv(r.root), stdio: "pipe" });
    write(join(sc, "src", "x.ts"), "export const x = 4;\n");
    git(sc, "commit", "-q", "-am", "X");
    git(sc, "push", "-q", `file://${store}`, "HEAD:refs/heads/main");
    H.remoteUrl = `file://${store}`;
    const result = await pull(r);
    expect(result.pullReason).toBe("shallow_changed");
    expect(head(r)).toBe(before);
    expect(stamps()).toBe(0);
    expect(pullWarn("shallow_changed")).toHaveLength(1);
    expect(pullLines()).toEqual([expect.objectContaining({ reason: "shallow_changed", ref: "default" })]);
  });

  test("TX1-b (AC13): a KB auto-commit plus an upstream code change -> merge commit with the pull message and the auto-commit's committer; every token-bearing call hardened, no cwd", async () => {
    const r = newRow();
    const up = upstreamCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2; // upstream\n"));
    write(join(r.ws, "knowledge-base", "a.md"), "a\nlocal kb\n");
    const result = await pull(r);
    expect(result.pullReason).toBe("merged");
    const [p1, p2] = parentsOf(r, "HEAD");
    expect(git(r.ws, "log", "-1", "--format=%s", p1)).toBe("Auto-commit before sync pull");
    expect(p2).toBe(up);
    expect(git(r.ws, "log", "-1", "--format=%s", "HEAD")).toBe(AUTO_MERGE_MSG_PULL);
    expect(git(r.ws, "log", "-1", "--format=%cn <%ce>", "HEAD")).toBe(git(r.ws, "log", "-1", "--format=%cn <%ce>", p1));
    expect(read(join(r.ws, "knowledge-base", "a.md"))).toBe("a\nlocal kb\n");
    expect(read(join(r.ws, "src", "s.ts"))).toBe("export const s = 2; // upstream\n");
    expect(stamps()).toBe(1);
    expect(tokenVerbs()).toEqual(["ls-remote", "fetch"]);
    for (const c of H.calls) {
      expect(c.hardened).toBe(true);
      expect(c.cwd).toBeUndefined();
      expect(c.args).toContain(LITERAL_URL);
    }
    expect(H.calls.find((c) => c.args[0] === "fetch")?.args).toEqual([
      "fetch",
      "--no-tags",
      "--no-recurse-submodules",
      "--no-write-fetch-head",
      LITERAL_URL,
      "refs/heads/main:refs/heads/fetched",
    ]);
    // the tracking ref names T (the value the merge took), never an agent ref
    expect(git(r.ws, "rev-parse", "refs/remotes/origin/main")).toBe(up);
    expect(pullLines()).toEqual([expect.objectContaining({ reason: "merged" })]);
    expect(H.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  test("TX1-c: T == headSha, and T an ancestor of headSha -> no fetch, no merge, stamped, up_to_date", async () => {
    const r = newRow();
    expect((await pull(r)).pullReason).toBe("up_to_date");
    expect(tokenVerbs()).toEqual(["ls-remote"]);
    expect(hostRan("merge")).toEqual([]);
    expect(stamps()).toBe(1);
    resetTurn();
    write(join(r.ws, "knowledge-base", "a.md"), "a\nahead\n"); // the auto-commit puts HEAD one commit past T
    expect((await pull(r)).pullReason).toBe("up_to_date");
    expect(tokenVerbs()).toEqual(["ls-remote"]);
    expect(hostRan("merge")).toEqual([]);
    expect(stamps()).toBe(1);
  });

  test("TX1-d (M11): the remote force-pushed to unrelated history -> merge_refused, HEAD unchanged, no stamp", async () => {
    const r = newRow();
    const before = head(r);
    const orphanDir = join(r.root, "orphan");
    mkdirSync(orphanDir);
    git(orphanDir, "init", "-q", "-b", "main");
    write(join(orphanDir, "other.txt"), "unrelated\n");
    git(orphanDir, "add", "-A");
    git(orphanDir, "commit", "-q", "-m", "unrelated root");
    git(orphanDir, "push", "-q", "--force", `file://${r.remote}`, "main");
    const result = await pull(r);
    expect(result.pullReason).toBe("merge_refused");
    expect(head(r)).toBe(before);
    expect(stamps()).toBe(0);
    expect(mergeHead(r)).toBe(false);
  });

  test("TX1-g (M8): a conflicting merge -> merge_conflict, no stamp, MERGE_HEAD and markers as today's pull leaves them", async () => {
    const r = newRow();
    git(r.ws, "commit", "-q", "--allow-empty", "-m", "noop");
    write(join(r.ws, "knowledge-base", "a.md"), "a\nlocal side\n");
    git(r.ws, "commit", "-q", "-am", "local kb");
    upstreamCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nupstream side\n"));
    const result = await pull(r);
    expect(result.pullReason).toBe("merge_conflict");
    expect(mergeHead(r)).toBe(true);
    expect(read(join(r.ws, "knowledge-base", "a.md"))).toMatch(/^<<<<<<< /m);
    expect(stamps()).toBe(0);
    expect(pullWarn("merge_conflict")).toHaveLength(1);
  });

  test("TX1-h (M6): a dirty tracked non-KB edit upstream also changes -> autostash_conflict (never merged), edit bytes kept, stash kept, no MERGE_HEAD", async () => {
    const r = newRow();
    upstreamCommit(r, (d) => write(join(d, "src", "x.ts"), "export const x = 2; // upstream\n"));
    write(join(r.ws, "src", "x.ts"), "export const x = 9; // dirty member edit\n");
    const result = await pull(r);
    expect(result.pullReason).toBe("autostash_conflict");
    expect(mergeHead(r)).toBe(false);
    expect(git(r.ws, "stash", "list")).not.toBe("");
    const kept = read(join(r.ws, "src", "x.ts")).includes("dirty member edit") || git(r.ws, "stash", "show", "-p").includes("dirty member edit");
    expect(kept).toBe(true);
    // a merge with rc 0: the X1 stamp rule holds
    expect(stamps()).toBe(1);
    expect(pullWarn("autostash_conflict")).toHaveLength(1);
  });

  test("TX1-h control: a dirty tracked non-KB edit upstream does NOT touch survives in the worktree and the merge is clean", async () => {
    const r = newRow();
    upstreamCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2;\n"));
    write(join(r.ws, "src", "x.ts"), "export const x = 9; // dirty member edit\n");
    expect((await pull(r)).pullReason).toBe("merged");
    expect(read(join(r.ws, "src", "x.ts"))).toBe("export const x = 9; // dirty member edit\n");
    expect(git(r.ws, "stash", "list")).toBe("");
  });

  test("TX1-i (D26(2)): planted merge.verifySignatures + gpg.program marker and a post-merge hook never run", async () => {
    const r = newRow();
    // the local KB commit is made BEFORE the plant: the auto-commit's own `commit` would honour rerere.enabled (out of D26(2))
    write(join(r.ws, "knowledge-base", "a.md"), "a\nlocal\n");
    git(r.ws, "commit", "-q", "-am", "local kb");
    const marker = join(r.root, "marker");
    const script = join(r.root, "evil.sh");
    write(script, `#!/bin/sh\necho ran >> ${marker}\nexit 0\n`);
    chmodSync(script, 0o755);
    git(r.ws, "config", "merge.verifySignatures", "true");
    git(r.ws, "config", "gpg.program", script);
    git(r.ws, "config", "gpg.ssh.program", script);
    git(r.ws, "config", "rerere.enabled", "true");
    write(join(r.ws, ".git", "hooks", "post-merge"), `#!/bin/sh\necho hook >> ${marker}\n`);
    chmodSync(join(r.ws, ".git", "hooks", "post-merge"), 0o755);
    upstreamCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2;\n"));
    expect((await pull(r)).pullReason).toBe("merged");
    expect(parentsOf(r, "HEAD")).toHaveLength(2); // a real merge ran
    expect(existsSync(marker)).toBe(false);
    expect(existsSync(join(r.ws, ".git", "rr-cache"))).toBe(false);
  });

  test("TX1-i (--no-overwrite-ignore): an ignored local file at an upstream-added tracked path -> merge_refused, the file byte-identical", async () => {
    const r = newRow();
    write(join(r.ws, "build", "out.txt"), "local ignored bytes\n");
    upstreamCommit(r, (d) => {
      write(join(d, "build", "out.txt"), "upstream tracked\n");
      git(d, "add", "-f", "build/out.txt");
    });
    const before = head(r);
    expect((await pull(r)).pullReason).toBe("merge_refused");
    expect(read(join(r.ws, "build", "out.txt"))).toBe("local ignored bytes\n");
    expect(head(r)).toBe(before);
    expect(stamps()).toBe(0);
  });

  test("TX1-k (D25(1)): a loose object planted at T's id in the workspace store -> tip_mismatch before any hand-over", async () => {
    const r = newRow();
    const T = upstreamCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2;\n"));
    // a donor commit only the workspace has, written loose, copied under T's id
    const donor = git(r.ws, "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "forged");
    const objects = join(r.ws, ".git", "objects");
    mkdirSync(join(objects, T.slice(0, 2)), { recursive: true });
    cpSync(join(objects, donor.slice(0, 2), donor.slice(2)), join(objects, T.slice(0, 2), T.slice(2)));
    const before = head(r);
    expect((await pull(r)).pullReason).toBe("tip_mismatch");
    expect(head(r)).toBe(before);
    expect(isoRan("pack-objects")).toBe(0);
    expect(hostRan("unpack-objects")).toEqual([]);
    expect(pullLines()).toEqual([expect.objectContaining({ reason: "tip_mismatch", ref: "default" })]);
  });

  test("TX1-l (D25(8)): the walk cap is checked before pack-objects runs; the hand-over cap refuses handover_too_large", async () => {
    const r = newRow();
    upstreamCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2;\n"));
    const before = head(r);
    expect((await pull(r, { limits: { walkEntryCap: 1 } })).pullReason).toBe("walk_cap");
    expect(isoRan("pack-objects")).toBe(0);
    expect(head(r)).toBe(before);
    resetTurn();
    expect((await pull(r, { limits: { handoverMaxBytes: 1 } })).pullReason).toBe("handover_too_large");
    expect(hostRan("unpack-objects")).toEqual([]);
    expect(head(r)).toBe(before);
    expect(stamps()).toBe(0);
  });

  test("a failing ls-remote -> remote_state, no fetch, no stamp, the isolated dir disposed", async () => {
    const r = newRow();
    H.remoteUrl = `file://${join(r.root, "absent.git")}`;
    expect((await pull(r)).pullReason).toBe("remote_state");
    expect(tokenVerbs()).toEqual(["ls-remote"]);
    expect(stamps()).toBe(0);
  });
});

describe("TX1-f / AC14: the token reaches only the literal host (two logging HTTP servers)", { timeout: 60_000 }, () => {
  interface Seen {
    name: string;
    path: string;
    auth: string | null;
    xEvil: string | null;
  }

  /** A logging smart-HTTP server: 401 without credentials, then `git http-backend` over `projectRoot` (or 404 when null). */
  function gitHttp(name: string, projectRoot: string | null, seen: Seen[]): Promise<{ base: string; close: () => Promise<void> }> {
    const server = createServer((req: IncomingMessage, res: ServerResponse) => {
      const u = new URL(req.url ?? "/", "http://fixture.invalid");
      const authHeader = req.headers.authorization ?? null;
      const auth = authHeader?.startsWith("Basic ") ? Buffer.from(authHeader.slice(6), "base64").toString("utf8") : authHeader;
      seen.push({ name, path: u.pathname, auth, xEvil: (req.headers["x-evil"] as string | undefined) ?? null });
      if (!authHeader) {
        res.writeHead(401, { "WWW-Authenticate": 'Basic realm="fixture"' });
        res.end();
        return;
      }
      if (projectRoot === null) {
        res.writeHead(404);
        res.end();
        return;
      }
      const env: NodeJS.ProcessEnv = {
        ...gitFixtureEnv(projectRoot),
        GIT_PROJECT_ROOT: projectRoot,
        GIT_HTTP_EXPORT_ALL: "1",
        PATH_INFO: u.pathname,
        QUERY_STRING: u.search.replace(/^\?/, ""),
        REQUEST_METHOD: req.method ?? "GET",
        CONTENT_TYPE: (req.headers["content-type"] as string | undefined) ?? "",
        REMOTE_USER: "x-access-token",
        REMOTE_ADDR: "127.0.0.1",
      };
      if (req.headers["content-encoding"]) env.HTTP_CONTENT_ENCODING = String(req.headers["content-encoding"]);
      if (req.headers["git-protocol"]) {
        env.GIT_PROTOCOL = String(req.headers["git-protocol"]);
        env.HTTP_GIT_PROTOCOL = String(req.headers["git-protocol"]);
      }
      const child = spawn("git", ["http-backend"], { env });
      const out: Buffer[] = [];
      child.stdout.on("data", (c: Buffer) => out.push(c));
      child.stderr.on("data", () => undefined);
      req.pipe(child.stdin);
      child.on("close", () => {
        const all = Buffer.concat(out);
        let sep = all.indexOf("\r\n\r\n");
        let sepLen = 4;
        if (sep < 0) {
          sep = all.indexOf("\n\n");
          sepLen = 2;
        }
        const headers: Record<string, string> = {};
        let code = 200;
        for (const line of all.subarray(0, sep).toString("latin1").split(/\r?\n/)) {
          const i = line.indexOf(":");
          if (i < 0) continue;
          const k = line.slice(0, i).trim();
          const v = line.slice(i + 1).trim();
          if (k.toLowerCase() === "status") code = parseInt(v, 10);
          else headers[k] = v;
        }
        res.writeHead(code, headers);
        res.end(all.subarray(sep + sepLen));
      });
    });
    return new Promise((resolve) => {
      server.listen(0, "127.0.0.1", () => {
        const port = (server.address() as AddressInfo).port;
        resolve({ base: `http://127.0.0.1:${port}/`, close: () => new Promise<void>((done) => server.close(() => done())) });
      });
    });
  }

  test("TX1-f: workspace insteadOf + extraHeader + remote.origin.url + server-HOME and XDG config -> EVIL sees nothing, the token reaches LIT only; the legacy control leaks it to EVIL", async () => {
    const r = newRow();
    H.extraProtocols = "file:http";
    const up = upstreamCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2;\n"));
    const served = join(r.root, "http");
    mkdirSync(join(served, "o"), { recursive: true });
    cpSync(r.remote, join(served, "o", "r.git"), { recursive: true });
    const seen: Seen[] = [];
    const lit = await gitHttp("LIT", served, seen);
    const evil = await gitHttp("EVIL", null, seen);
    try {
      H.remoteUrl = `${lit.base}o/r.git`;
      git(r.ws, "config", `url.${evil.base}.insteadOf`, lit.base);
      git(r.ws, "config", "http.extraHeader", "X-Evil: repo-unscoped");
      git(r.ws, "config", `http.${evil.base}.extraHeader`, "X-Evil: repo-scoped");
      git(r.ws, "config", "remote.origin.url", `${evil.base}o/r.git`);
      const planted = `[url "${evil.base}"]\n\tinsteadOf = ${lit.base}\n[http]\n\textraHeader = X-Evil: global\n`;
      write(join(r.root, "home", ".gitconfig"), planted);
      write(join(r.root, "home", ".config", "git", "config"), planted);

      const result = await pull(r);
      expect(result.pullReason).toBe("merged");
      expect(isAncestor(r, up, "HEAD")).toBe(true);
      expect(seen.filter((s) => s.name === "EVIL")).toEqual([]);
      expect(seen.length).toBeGreaterThan(0);
      expect(seen.filter((s) => s.xEvil !== null)).toEqual([]);
      const authed = seen.filter((s) => s.auth !== null);
      expect(authed.length).toBeGreaterThan(0);
      for (const s of authed) {
        expect(s.name).toBe("LIT");
        expect(s.auth).toBe(`x-access-token:${TOKEN}`);
      }

      // Control (T1): the legacy arm with the same workspace config sends the token to EVIL, so the fixture is sensitive.
      seen.length = 0;
      await gitWithInstallationAuth(["pull", "--no-rebase", "--autostash"], 1, { cwd: r.ws }).catch(() => undefined);
      expect(seen.filter((s) => s.name === "EVIL" && s.auth === `x-access-token:${TOKEN}`).length).toBeGreaterThan(0);
    } finally {
      await lit.close();
      await evil.close();
    }
  });
});

describe("TX2 / AC15: no git child reads the workspace .git, and no workspace ref becomes a have line", { timeout: 30_000 }, () => {
  test("default fetch and side-adoption fetch, with GIT_DIR / GIT_INDEX_FILE / GIT_OBJECT_DIRECTORY / GIT_ALTERNATE_OBJECT_DIRECTORIES in the process env", async () => {
    const r = newRow();
    upstreamCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2;\n"));
    const P = sideCommit(r, (d) => write(join(d, "knowledge-base", "side.md"), "side kb\n"));
    openPr(P);
    const planted = git(r.ws, "commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "planted ref");
    git(r.ws, "update-ref", "refs/heads/planted", planted);
    H.trace = { trace: join(r.root, "trace.log"), packet: join(r.root, "packet.log") };
    process.env.GIT_DIR = join(r.root, "decoy-git-dir");
    process.env.GIT_INDEX_FILE = join(r.root, "decoy-index");
    process.env.GIT_OBJECT_DIRECTORY = join(r.root, "decoy-objects");
    process.env.GIT_ALTERNATE_OBJECT_DIRECTORIES = join(r.root, "decoy-alt");
    const result = await pull(r);
    expect(tokenVerbs()).toEqual(["ls-remote", "fetch", "fetch"]);
    expect(H.calls[2].args).toContain("refs/heads/soleur/kb-sync:refs/heads/fetched-side");
    expect(isAncestor(r, P, "HEAD")).toBe(true);
    expect(result.pullReason).toBe("merged");
    const trace = read(H.trace.trace);
    expect(trace).toMatch(/fetch/);
    expect(trace).not.toContain(`--git-dir=${r.ws}/.git`);
    expect(read(H.trace.packet)).not.toContain(`have ${planted}`);
    expect(existsSync(join(r.root, "decoy-index"))).toBe(false);
  });
});

describe("TX4: a half-done merge refuses before any auto-commit (X4, D26(1))", { timeout: 30_000 }, () => {
  /** An upstream change to knowledge-base/a.md, then a dirty local edit of the same file stashed and popped over it (M4). */
  function autostashConflict(r: Row): void {
    upstreamCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nupstream\n"));
    write(join(r.ws, "knowledge-base", "a.md"), "a\nlocal\n");
    git(r.ws, "stash");
    git(r.ws, "fetch", "-q", "origin");
    git(r.ws, "merge", "-q", "--ff-only", "origin/main");
    try {
      git(r.ws, "stash", "pop");
    } catch {
      /* the conflict is the point */
    }
  }

  test("TX4-a: MERGE_HEAD, then MERGE_AUTOSTASH, then an unmerged entry with neither -> no token, no commit, no merge, unresolved_merge; syncPush holds merge_in_progress on the same fixture", async () => {
    for (const variant of ["MERGE_HEAD", "MERGE_AUTOSTASH", "unmerged"] as const) {
      const r = newRow();
      if (variant === "unmerged") autostashConflict(r);
      else writeFileSync(join(r.ws, ".git", variant), `${head(r)}\n`);
      write(join(r.ws, "knowledge-base", "fresh.md"), "would be auto-committed\n");
      resetTurn();
      const before = head(r);
      expect((await pull(r)).pullReason, variant).toBe("unresolved_merge");
      expect(H.calls, variant).toEqual([]);
      expect(hostRan("commit"), variant).toEqual([]);
      expect(hostRan("merge"), variant).toEqual([]);
      expect(head(r), variant).toBe(before);
      expect(stamps(), variant).toBe(0);
      expect(pullWarn("unresolved_merge"), variant).toHaveLength(1);
      resetTurn();
      await syncPush(USER, r.ws, {} as never, WS_ID);
      expect(hostRan("commit"), variant).toEqual([]);
      expect(H.log.info.mock.calls.filter(([o]) => (o as { op?: string; reason?: string })?.op === "kb-sync.push-held" && (o as { reason?: string }).reason === "merge_in_progress"), variant).toHaveLength(1);
    }
  });

  test("TX4-b (M4/M10): UU knowledge-base/a.md with markers and no MERGE_HEAD -> neither auto-commit runs; the remote never gets a marker blob", async () => {
    const r = newRow();
    autostashConflict(r);
    expect(status(r)).toMatch(/^UU knowledge-base\/a\.md$/m);
    expect(mergeHead(r)).toBe(false);
    await pull(r);
    await syncPush(USER, r.ws, {} as never, WS_ID);
    expect(hostRan("commit")).toEqual([]);
    expect(git(r.remote, "show", "refs/heads/main:knowledge-base/a.md")).not.toContain("<<<<<<<");
  });

  test("TX4-c: MERGE_HEAD with every conflict staged (no unmerged entry) -> no commit argv, MERGE_HEAD survives", async () => {
    const r = newRow();
    write(join(r.ws, "knowledge-base", "a.md"), "a\nlocal side\n");
    git(r.ws, "commit", "-q", "-am", "local kb");
    upstreamCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nupstream side\n"));
    git(r.ws, "fetch", "-q", "origin");
    expect(gitOk(r.ws, "merge", "--no-edit", "origin/main")).toBe(false);
    git(r.ws, "add", "knowledge-base/a.md"); // markers staged: no unmerged entry left
    expect(status(r)).not.toMatch(/^(UU|AA|DD|AU|UA|DU|UD) /m);
    expect(mergeHead(r)).toBe(true);
    expect((await pull(r)).pullReason).toBe("unresolved_merge");
    await syncPush(USER, r.ws, {} as never, WS_ID);
    expect(hostRan("commit")).toEqual([]);
    expect(mergeHead(r)).toBe(true);
  });

  test("TX4-d: a MERGE_HEAD left by a prior session, resolved in the workspace -> the next sync reaches a clean HEAD, no re-clone", async () => {
    const r = newRow();
    git(r.ws, "commit", "-q", "--allow-empty", "-m", "noop");
    write(join(r.ws, "knowledge-base", "a.md"), "a\nlocal side\n");
    git(r.ws, "commit", "-q", "-am", "local kb");
    const up = upstreamCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nupstream side\n"));
    expect((await pull(r)).pullReason).toBe("merge_conflict");
    resetTurn();
    expect((await pull(r)).pullReason).toBe("unresolved_merge");
    // the member resolves it
    write(join(r.ws, "knowledge-base", "a.md"), "a\nresolved\n");
    git(r.ws, "add", "knowledge-base/a.md");
    git(r.ws, "commit", "-q", "--no-edit");
    resetTurn();
    expect((await pull(r)).pullReason).toBe("up_to_date");
    expect(status(r)).toBe("");
    expect(isAncestor(r, up, "HEAD")).toBe(true);
    expect(mergeHead(r)).toBe(false);
  });
});

describe("TX5 (X5): a non-default branch or a detached HEAD is not pulled", { timeout: 30_000 }, () => {
  test("feature branch, then detached HEAD -> no fetch, no merge, no stamp, one info non_default_branch line, no adoption", async () => {
    for (const shape of ["feature", "detached"] as const) {
      const r = newRow();
      upstreamCommit(r, (d) => write(join(d, "src", "s.ts"), "export const s = 2;\n"));
      const P = sideCommit(r, (d) => write(join(d, "knowledge-base", "side.md"), "side\n"));
      openPr(P);
      if (shape === "feature") git(r.ws, "checkout", "-q", "-b", "feature");
      else git(r.ws, "checkout", "-q", "--detach");
      resetTurn();
      const before = head(r);
      expect((await pull(r)).pullReason, shape).toBe("non_default_branch");
      expect(tokenVerbs(), shape).not.toContain("fetch");
      expect(hostRan("merge"), shape).toEqual([]);
      expect(head(r), shape).toBe(before);
      expect(stamps(), shape).toBe(0);
      expect(pullLines(), shape).toEqual([expect.objectContaining({ reason: "non_default_branch" })]);
      expect(H.mirrorWarnWithDebounce, shape).not.toHaveBeenCalled();
      expect(H.listPullRequestsForHead, shape).not.toHaveBeenCalled();
    }
  });
});

describe("TX5-b (D26(7)): a checkpoint taken before a pull merge is not restored over it", { timeout: 30_000 }, () => {
  test("checkpoint at A, syncPull merges to B -> restore refuses stale-base, tree unchanged, ref kept", async () => {
    const r = newRow();
    write(join(r.ws, "src", "s.ts"), "export const s = 9; // in-flight\n");
    await checkpointInflightWork(r.ws, "conv-tx5b", USER);
    const ref = "refs/checkpoints/conv-tx5b";
    expect(gitOk(r.ws, "rev-parse", "--verify", "--quiet", ref)).toBe(true);
    git(r.ws, "checkout", "--", "src/s.ts");
    upstreamCommit(r, (d) => write(join(d, "src", "x.ts"), "export const x = 2;\n"));
    expect((await pull(r)).pullReason).toBe("merged");
    const res = await restoreInflightCheckpoint(r.ws, "conv-tx5b", { siblingSlotActive: false });
    expect(res).toEqual({ restored: false, reason: "stale-base" });
    expect(read(join(r.ws, "src", "s.ts"))).toBe("export const s = 1;\n");
    expect(gitOk(r.ws, "rev-parse", "--verify", "--quiet", ref)).toBe(true);
  });
});

describe("TX6 (D28): side-tip adoption, step 6b", { timeout: 30_000 }, () => {
  test("TX6-a open: an open PR on P, P absent locally -> fetched, verified, handed over, merged; the next no-edit syncPush is side_pending", async () => {
    const r = newRow();
    const P = sideCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nside kb\n"));
    openPr(P);
    expect(hasObject(r, P)).toBe(false);
    const result = await pull(r);
    expect(result.pullReason).toBe("merged");
    expect(isAncestor(r, P, "HEAD")).toBe(true);
    expect(read(join(r.ws, "knowledge-base", "a.md"))).toBe("a\nside kb\n");
    expect(git(r.ws, "rev-parse", "refs/remotes/origin/soleur/kb-sync")).toBe(P);
    expect(H.createPullRequest).not.toHaveBeenCalled();
    resetTurn();
    await syncPush(USER, r.ws, {} as never, WS_ID);
    expect(H.log.info.mock.calls.filter(([o]) => (o as { op?: string })?.op === "kb-sync.push-held").map(([o]) => (o as { reason: string }).reason)).toEqual(["side_pending"]);
  });

  test("TX6-b none: no PR on P (a re-clone after pr_failed) -> the PR is created (side_pr_created), then P is adopted", async () => {
    const r = newRow();
    const P = sideCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nside kb\n"));
    const result = await pull(r);
    expect(H.createPullRequest).toHaveBeenCalledTimes(1);
    expect(result.pullReason).toBe("side_pr_created");
    expect(isAncestor(r, P, "HEAD")).toBe(true);
    expect(H.prs.map((p) => [p.state, p.headSha])).toEqual([["open", P]]);
  });

  test("TX6-c declined: a closed, unmerged PR on P -> side_declined, no create, no merge, no hand-over", async () => {
    const r = newRow();
    const P = sideCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nside kb\n"));
    H.prs.push({ number: 3, htmlUrl: "https://github.com/acme/widget/pull/3", url: "", state: "closed", merged: false, headSha: P });
    const before = head(r);
    expect((await pull(r)).pullReason).toBe("side_declined");
    expect(H.createPullRequest).not.toHaveBeenCalled();
    expect(head(r)).toBe(before);
    expect(hasObject(r, P)).toBe(false);
    expect(H.mirrorWarnWithDebounce).not.toHaveBeenCalled();
    // the up_to_date stamp is never undone by an adoption reason
    expect(stamps()).toBe(1);
  });

  test("TX6-d not KB-only: P adds src/evil.ts with an open PR -> side_not_kb_only, HEAD unchanged, no hand-over; attempted with T == headSha", async () => {
    const r = newRow();
    const P = sideCommit(r, (d) => {
      write(join(d, "knowledge-base", "a.md"), "a\nside kb\n");
      write(join(d, "src", "evil.ts"), "export const evil = true;\n");
    });
    openPr(P);
    const before = head(r);
    expect(before).toBe(r.T); // T == headSha: the early return must still reach step 6b
    expect((await pull(r)).pullReason).toBe("side_not_kb_only");
    expect(head(r)).toBe(before);
    expect(hasObject(r, P)).toBe(false);
    expect(existsSync(join(r.ws, "src", "evil.ts"))).toBe(false);
    expect(pullWarn("side_not_kb_only")).toHaveLength(1);
    expect(pullLines()).toEqual([expect.objectContaining({ reason: "side_not_kb_only" })]);
  });

  test("TX6-e link: P's KB tree equals a first-parent commit's (D24(12)) -> side_linked, no MERGE_HEAD, HEAD's tree unchanged, P an ancestor", async () => {
    const r = newRow();
    // the local KB commit K and the side tip P carry the same KB tree (the relink dropped P from local lineage)
    write(join(r.ws, "knowledge-base", "a.md"), "a\nsame kb\n");
    git(r.ws, "commit", "-q", "-am", "local kb K");
    const P = sideCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nsame kb\n"));
    // a later local KB edit on the same hunk
    write(join(r.ws, "knowledge-base", "a.md"), "a\nsame kb\nlater\n");
    git(r.ws, "commit", "-q", "-am", "later kb");
    openPr(P);
    const treeBefore = git(r.ws, "rev-parse", "HEAD^{tree}");
    const result = await pull(r);
    expect(result.pullReason).toBe("side_linked");
    expect(mergeHead(r)).toBe(false);
    expect(git(r.ws, "rev-parse", "HEAD^{tree}")).toBe(treeBefore);
    expect(isAncestor(r, P, "HEAD")).toBe(true);
    expect(hostRan("merge")).toEqual([]);
    expect(H.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  test("TX6-f conflict: a P whose merge conflicts with HEAD -> side_conflict, files untouched, no MERGE_HEAD", async () => {
    const r = newRow();
    write(join(r.ws, "knowledge-base", "a.md"), "a\nlocal kb\n");
    git(r.ws, "commit", "-q", "-am", "local kb");
    const P = sideCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nside kb\n"));
    openPr(P);
    const before = head(r);
    expect((await pull(r)).pullReason).toBe("side_conflict");
    expect(head(r)).toBe(before);
    expect(mergeHead(r)).toBe(false);
    expect(read(join(r.ws, "knowledge-base", "a.md"))).toBe("a\nlocal kb\n");
    expect(H.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  test("the PR GET fails -> side_pr_unknown, zero creates and zero writes", async () => {
    const r = newRow();
    const P = sideCommit(r, (d) => write(join(d, "knowledge-base", "a.md"), "a\nside kb\n"));
    H.prListFails = true;
    const before = head(r);
    expect((await pull(r)).pullReason).toBe("side_pr_unknown");
    expect(H.createPullRequest).not.toHaveBeenCalled();
    expect(head(r)).toBe(before);
    expect(hasObject(r, P)).toBe(false);
    expect(pullWarn("side_pr_unknown")).toHaveLength(1);
  });

  test("a side tip already in HEAD's history, or whose KB equals T's, is not adopted (no PR read)", async () => {
    const r = newRow();
    const P = sideCommit(r, (d) => write(join(d, "README.md"), "readme on the side\n"), r.T); // KB equal to T's
    openPr(P);
    expect((await pull(r)).pullReason).toBe("up_to_date");
    expect(H.listPullRequestsForHead).not.toHaveBeenCalled();
    expect(hasObject(r, P)).toBe(false);
    expect(lstatSync(join(r.ws, ".git")).isDirectory()).toBe(true);
  });
});
