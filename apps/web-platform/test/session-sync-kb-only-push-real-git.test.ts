// Real-git battery for #12600: the post-session `syncPush` publishes only a commit the server built (CTO ruling R14).
//
// Every row drives the REAL `syncPush` (and, where named, the real `syncWorkspace`) against a local bare `file://` remote
// that stands in for `https://github.com/acme/widget.git`, and asserts EFFECTS on the bare remote and the workspace: tip
// sha, parent, tree shape, author and committer, the presence or absence of an object, the local branch, the tracking
// ref and `git status`. Assertions on recorded argv are secondary (H5, census).
//
// Fixture rules (plan "Test Scenarios"): a template remote is built once in `beforeAll` and COPIED per row (no row
// mutates the template); workspaces are `git clone --depth 1` so the shallow boundary matches production; fixture git runs
// under `gitFixtureEnv` (GIT_CONFIG_GLOBAL=/dev/null, GIT_CONFIG_NOSYSTEM=1) with increasing GIT_COMMITTER_DATE values;
// the protected default branch is a REAL `pre-receive` hook printing GitHub's GH006 line. Synthesized data only
// (cq-test-fixtures-synthesized-only): the token is built by concatenation.
//
// Matrix rows refer to the plan's Guard 1 mutation matrix; H-rows to its harness rows.
import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const LITERAL_URL = "https://github.com/acme/widget.git";
const SOLEUR_NAME = "Soleur Agent";
const SOLEUR_EMAIL = "agent@soleur.ai";
const SIDE_MSG = "Soleur: sync knowledge-base";
const MERGE_MSG = "Soleur: merge knowledge-base sync";
const USER = "77777777-7777-4777-8777-777777777777";
const WS_ID = "11111111-1111-4111-8111-111111111111";

interface Call {
  args: string[];
  hardened: boolean;
  cwd: string | undefined;
}

const H = vi.hoisted(() => ({
  calls: [] as Array<{ args: string[]; hardened: boolean; cwd: string | undefined }>,
  remoteUrl: "",
  beforeCall: null as null | ((args: string[]) => void),
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
  writeRepoCols: vi.fn(async () => undefined),
  rpc: vi.fn(async () => ({ data: null, error: null })),
  findOpenPullRequest: vi.fn(async () => null as null | { htmlUrl: string }),
  createPullRequest: vi.fn(async () => ({ htmlUrl: "https://github.com/acme/widget/pull/1" })),
  log: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: H.reportSilentFallback,
  warnSilentFallback: H.warnSilentFallback,
  mirrorWarnWithDebounce: H.mirrorWarnWithDebounce,
  hashUserId: (x: string) => `h-${x}`,
}));
vi.mock("@/server/logger", () => ({ createChildLogger: () => H.log, default: H.log }));
vi.mock("@/server/workspace-repo-mirror", () => ({ writeRepoColsToWorkspace: H.writeRepoCols }));
vi.mock("@/server/resolve-installation-id", () => ({ resolveInstallationId: async () => 1 }));
vi.mock("@/server/current-repo-url", () => ({ getCurrentRepoUrl: async () => "https://github.com/acme/widget" }));
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: async () => ["ghs", "_", "b".repeat(40)].join(""),
  findOpenPullRequest: H.findOpenPullRequest,
  createPullRequest: H.createPullRequest,
}));
vi.mock("@/lib/supabase/tenant", () => {
  class RuntimeAuthError extends Error {}
  const chain = { maybeSingle: async () => ({ data: { id: "u" }, error: null }) };
  return {
    RuntimeAuthError,
    getFreshTenantClient: async () => ({ from: () => ({ select: () => ({ eq: () => chain }) }), rpc: H.rpc }),
  };
});
// Record every authenticated git call, then rewrite ONLY the literal fixture URL token to the local bare remote.
vi.mock("@/server/git-auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-auth")>();
  return {
    ...actual,
    gitWithInstallationAuth: async (args: string[], id: number, opts: import("@/server/git-auth").GitExecOptions = {}) => {
      H.calls.push({ args: [...args], hardened: opts.hardened !== undefined, cwd: opts.cwd });
      H.beforeCall?.(args);
      const rewritten = args.map((a) => (a === "https://github.com/acme/widget.git" ? H.remoteUrl : a));
      return actual.gitWithInstallationAuth(rewritten, id, opts);
    },
  };
});
// Test-only: the production clamp is `https`; the fixture remote is file://. Widened on the builder's RESULT.
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
// The syncWorkspace rows and the legacy-arm mutation rows run host-side git against the file:// origin.
vi.mock("@/server/host-git", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/host-git")>();
  return {
    ...actual,
    hostGitInvocation: (args: readonly string[], opts: import("@/server/host-git").HostGitOpts) =>
      actual.hostGitInvocation(args, { ...opts, allowProtocol: `${opts.allowProtocol}:file` }),
  };
});

import { syncPush } from "@/server/session-sync";
import { syncWorkspace } from "@/server/workspace-sync";

let base = "";
let template = "";
let dateTick = 1_700_000_000;
let gitVersion = "";

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

const GH006_HOOK = `#!/bin/sh
while read old new ref; do
  if [ "$ref" = "refs/heads/main" ]; then
    echo "error: GH006: Protected branch update failed for $ref." >&2
    echo "error: Changes must be made through a pull request." >&2
    exit 1
  fi
done
exit 0
`;

interface Row {
  root: string;
  remote: string;
  ws: string;
  /** remote main tip before the turn */
  T: string;
}

beforeAll(() => {
  gitVersion = execFileSync("git", ["--version"], { encoding: "utf8", env: { PATH: process.env.PATH ?? "" } as unknown as NodeJS.ProcessEnv }).trim();
  // eslint-disable-next-line no-console -- recorded once per run for the PR body (plan Phase 0)
  console.log(`[kb-only-push battery] ${gitVersion}`);
  base = realpathSync(mkdtempSync(join(tmpdir(), "kbpush-")));
  template = join(base, "template.git");
  execFileSync("git", ["init", "-q", "--bare", "-b", "main", template], { env: gitFixtureEnv(base) });
  const seed = join(base, "seed");
  mkdirSync(seed);
  git(seed, "init", "-q", "-b", "main");
  write(join(seed, "knowledge-base", "a.md"), "a\n");
  write(join(seed, "knowledge-base", "nested", "b.md"), "b\n");
  write(join(seed, "src", "s.ts"), "export const s = 1;\n");
  write(join(seed, "README.md"), "readme\n");
  git(seed, "add", "-A");
  git(seed, "commit", "-q", "-m", "T0");
  git(seed, "push", "-q", template, "main");
}, 30_000);

afterAll(() => {
  if (base) rmSync(base, { recursive: true, force: true });
});

const savedEnv: Record<string, string | undefined> = {};
let row: Row;

function newRow(opts: { protectedMain?: boolean } = {}): Row {
  const root = realpathSync(mkdtempSync(join(base, "row-")));
  const remote = join(root, "remote.git");
  cpSync(template, remote, { recursive: true });
  if (opts.protectedMain) {
    writeFileSync(join(remote, "hooks", "pre-receive"), GH006_HOOK);
    chmodSync(join(remote, "hooks", "pre-receive"), 0o755);
  }
  const ws = join(root, "ws");
  execFileSync("git", ["clone", "-q", "--depth", "1", `file://${remote}`, ws], { env: fixtureEnv(root), stdio: "pipe" });
  git(ws, "config", "user.name", "Seeded Local");
  git(ws, "config", "user.email", "local@example.test");
  mkdirSync(join(root, "home"));
  mkdirSync(join(root, "tmp"));
  process.env.HOME = join(root, "home");
  process.env.TMPDIR = join(root, "tmp");
  H.remoteUrl = `file://${remote}`;
  return { root, remote, ws, T: git(remote, "rev-parse", "refs/heads/main") };
}

/** A commit on the remote main made by "someone else" (a scratch clone pushing past any hook via update-ref). */
function upstreamCommit(r: Row, edit: (dir: string) => void, msg = "upstream"): string {
  const dir = mkdtempSync(join(r.root, "up-"));
  execFileSync("git", ["clone", "-q", `file://${r.remote}`, dir], { env: fixtureEnv(r.root), stdio: "pipe" });
  edit(dir);
  git(dir, "add", "-A");
  git(dir, "commit", "-q", "-m", msg);
  const sha = git(dir, "rev-parse", "HEAD");
  git(dir, "push", "-q", "origin", `HEAD:refs/heads/tmp-up-${sha.slice(0, 8)}`);
  git(r.remote, "update-ref", "refs/heads/main", sha);
  git(r.remote, "update-ref", "-d", `refs/heads/tmp-up-${sha.slice(0, 8)}`);
  return sha;
}

const remoteMain = (r: Row): string => git(r.remote, "rev-parse", "refs/heads/main");
const remoteSide = (r: Row): string | null => {
  try {
    return git(r.remote, "rev-parse", "--verify", "--quiet", "refs/heads/soleur/kb-sync");
  } catch {
    return null;
  }
};
const onRemote = (r: Row, sha: string): boolean => gitOk(r.remote, "cat-file", "-e", `${sha}^{object}`);
const parents = (dir: string, sha: string): string[] => git(dir, "rev-list", "--parents", "-n", "1", sha).split(" ").slice(1);
const ident = (dir: string, sha: string): string => git(dir, "log", "-1", "--format=%an|%ae|%cn|%ce|%s", sha);
const rootEntries = (dir: string, sha: string): string[] => git(dir, "ls-tree", sha).split("\n").filter(Boolean);
const nonKb = (entries: string[]): string[] => entries.filter((e) => !e.endsWith("\tknowledge-base"));
const kbEntry = (dir: string, sha: string): string => git(dir, "rev-parse", `${sha}:knowledge-base`);
const localMain = (r: Row): string => git(r.ws, "rev-parse", "refs/heads/main");
const tracking = (r: Row): string => git(r.ws, "rev-parse", "refs/remotes/origin/main");
/** `git status --porcelain` with its leading status columns intact (only the trailing newline is dropped). */
const status = (r: Row): string =>
  execFileSync("git", ["status", "--porcelain"], { cwd: r.ws, encoding: "utf8", env: fixtureEnv(r.ws) }).replace(/\n$/, "");
const heldInfo = (reason: string): unknown[] =>
  H.log.info.mock.calls.filter(([o]) => (o as { op?: string; reason?: string })?.op === "kb-sync.push-held" && (o as { reason?: string }).reason === reason);
const heldWarn = (reason: string): unknown[] =>
  H.mirrorWarnWithDebounce.mock.calls.filter(([, , , cls]) => cls === `kb-sync-push-held:${reason}`);

/** A foreign (non-KB) commit the agent made through Bash, plus the KB edit the auto-commit picks up. */
function foreignPlusKb(r: Row, { kb = true, dirtyCode = true } = {}): string {
  write(join(r.ws, ".github", "workflows", "x.yml"), "on: push\njobs: {}\n");
  git(r.ws, "add", "-A");
  git(r.ws, "commit", "-q", "-m", "Fixes #1 add workflow");
  const foreign = git(r.ws, "rev-parse", "HEAD");
  if (kb) write(join(r.ws, "knowledge-base", "a.md"), "a\nlocal kb edit\n");
  if (dirtyCode) write(join(r.ws, "src", "s.ts"), "export const s = 2; // dirty, uncommitted\n");
  return foreign;
}

const run = (r: Row): Promise<void> => syncPush(USER, r.ws, {} as never, WS_ID);

beforeEach(() => {
  for (const k of ["HOME", "TMPDIR"]) savedEnv[k] = process.env[k];
  H.calls.length = 0;
  H.beforeCall = null;
  for (const f of [H.reportSilentFallback, H.warnSilentFallback, H.mirrorWarnWithDebounce, H.writeRepoCols, H.rpc, H.findOpenPullRequest, H.createPullRequest, H.log.info, H.log.warn, H.log.error, H.log.debug]) f.mockClear();
  H.findOpenPullRequest.mockImplementation(async () => null);
});

afterEach(() => {
  for (const [k, v] of Object.entries(savedEnv)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  // every row: no isolated directory is left behind
  if (row && existsSync(join(row.root, "home", ".soleur-push"))) {
    expect(readdirSync(join(row.root, "home", ".soleur-push"))).toEqual([]);
  }
});

describe("syncPush publishes only a Soleur-built KB commit (real git)", { timeout: 30_000 }, () => {
  test("H1: a KB-only auto-commit over T is published as S (parent T, HEAD's tree, Soleur identity); local == tracking == S", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb edit\n");
    await run(row);
    const S = remoteMain(row);
    expect(S).not.toBe(row.T);
    expect(parents(row.remote, S)).toEqual([row.T]);
    expect(ident(row.remote, S)).toBe(`${SOLEUR_NAME}|${SOLEUR_EMAIL}|${SOLEUR_NAME}|${SOLEUR_EMAIL}|${SIDE_MSG}`);
    expect(git(row.remote, "show", `${S}:knowledge-base/a.md`)).toBe("a\nkb edit");
    expect(localMain(row)).toBe(S);
    expect(tracking(row)).toBe(S);
    expect(status(row)).toBe("");
    expect(heldInfo("synthetic_pushed")).toHaveLength(1);
    expect(H.writeRepoCols).toHaveBeenCalledTimes(1);
  });

  test("H1b: a KB-only local commit plus a session-start pull merge of an upstream code change publishes S on the new T", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb edit\n");
    git(row.ws, "commit", "-q", "-am", "Auto-commit before sync pull");
    const T1 = upstreamCommit(row, (d) => write(join(d, "src", "s.ts"), "export const s = 3;\n"));
    git(row.ws, "pull", "-q", "--no-rebase", "--no-edit", "origin", "main");
    const headTree = git(row.ws, "rev-parse", "HEAD^{tree}");
    await run(row);
    const S = remoteMain(row);
    expect(parents(row.remote, S)).toEqual([T1]);
    expect(git(row.remote, "rev-parse", `${S}^{tree}`)).toBe(headTree);
    expect(localMain(row)).toBe(S);
    expect(tracking(row)).toBe(S);
    expect(status(row)).toBe("");
  });

  test("H2 (matrix 1, 3, 4, 5, 11): foreign commit + KB edit -> remote gets only S; local is M and keeps the foreign commit", async () => {
    row = newRow();
    const foreign = foreignPlusKb(row);
    await run(row);
    const S = remoteMain(row);
    expect(S).not.toBe(row.T);
    expect(onRemote(row, foreign)).toBe(false);
    expect(parents(row.remote, S)).toEqual([row.T]);
    expect(nonKb(rootEntries(row.remote, S))).toEqual(nonKb(rootEntries(row.remote, row.T)));
    expect(git(row.remote, "show", `${S}:knowledge-base/a.md`)).toBe("a\nlocal kb edit");
    expect(ident(row.remote, S)).toBe(`${SOLEUR_NAME}|${SOLEUR_EMAIL}|${SOLEUR_NAME}|${SOLEUR_EMAIL}|${SIDE_MSG}`);
    const M = localMain(row);
    const [p1, p2] = parents(row.ws, M);
    expect(p2).toBe(S);
    expect(gitOk(row.ws, "merge-base", "--is-ancestor", foreign, p1)).toBe(true);
    expect(git(row.ws, "log", "-1", "--format=%an|%s", M)).toBe(`${SOLEUR_NAME}|${MERGE_MSG}`);
    expect(gitOk(row.ws, "merge-base", "--is-ancestor", foreign, M)).toBe(true);
    expect(tracking(row)).toBe(S);
    expect(status(row)).toBe(" M src/s.ts");
    expect(heldInfo("synthetic_pushed")).toHaveLength(1);
  });

  test("H3: foreign commit and no KB change -> remote unchanged, one held_foreign info line, no Sentry event", async () => {
    row = newRow();
    foreignPlusKb(row, { kb: false, dirtyCode: false });
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldInfo("held_foreign")).toHaveLength(1);
    expect(H.mirrorWarnWithDebounce).not.toHaveBeenCalled();
    expect(H.reportSilentFallback).not.toHaveBeenCalled();
  });

  test("H5 (matrix 7, 8): every token-bearing call is hardened and names exactly the literal URL; no legacy-arm call", async () => {
    row = newRow();
    foreignPlusKb(row);
    await run(row);
    expect(H.calls.length).toBeGreaterThan(0);
    for (const c of H.calls) {
      expect(c.hardened, `legacy-arm call: ${c.args[0]}`).toBe(true);
      expect(c.cwd).toBeUndefined();
      if (["ls-remote", "fetch", "push"].includes(c.args[0])) expect(c.args).toContain(LITERAL_URL);
      for (const a of c.args) if (/^(https?|file):\/\//.test(a)) expect(a).toBe(LITERAL_URL);
    }
    const pushes = H.calls.filter((c) => c.args[0] === "push");
    expect(pushes).toHaveLength(1);
    expect(pushes[0].args.slice(-1)[0]).toMatch(/^[0-9a-f]{40}:refs\/heads\/main$/);
  });

  test("H6: the turn after a successful push with no new commits mints no token and writes no history row", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb edit\n");
    await run(row);
    expect(remoteMain(row)).not.toBe(row.T);
    H.calls.length = 0;
    H.rpc.mockClear();
    await run(row);
    expect(H.calls).toEqual([]);
    expect(H.rpc).not.toHaveBeenCalled();
  });

  test("H7: turn 2 after H2 with another KB edit -> remote S2 (parent S), local M2", async () => {
    row = newRow();
    const foreign = foreignPlusKb(row);
    await run(row);
    const S = remoteMain(row);
    const M = localMain(row);
    write(join(row.ws, "knowledge-base", "nested", "b.md"), "b\nturn 2\n");
    await run(row);
    const S2 = remoteMain(row);
    expect(S2).not.toBe(S);
    expect(parents(row.remote, S2)).toEqual([S]);
    expect(onRemote(row, foreign)).toBe(false);
    const M2 = localMain(row);
    expect(parents(row.ws, M2)[1]).toBe(S2);
    expect(gitOk(row.ws, "merge-base", "--is-ancestor", M, M2)).toBe(true);
    // ADR-068 overlay check after a re-clone: the remote tip is an ancestor of the local branch
    expect(gitOk(row.ws, "merge-base", "--is-ancestor", S2, "HEAD")).toBe(true);
  });

  test("matrix 2: forged bytes for T's root tree in the workspace store -> nothing pushed, hash_mismatch", async () => {
    row = newRow();
    const foreign = foreignPlusKb(row, { dirtyCode: false });
    git(row.ws, "add", "-A");
    git(row.ws, "commit", "-q", "-m", "kb");
    // make every object loose, then overwrite T's root tree file with the foreign root tree's bytes (probe7 shape)
    const objects = join(row.ws, ".git", "objects");
    for (const p of readdirSync(join(objects, "pack")).filter((f) => f.endsWith(".pack"))) {
      const packPath = join(objects, "pack", p);
      const moved = join(row.root, p);
      cpSync(packPath, moved);
      rmSync(packPath);
      rmSync(packPath.replace(/\.pack$/, ".idx"), { force: true });
      execFileSync("git", ["unpack-objects", "-q"], { cwd: row.ws, input: readFileSync(moved), env: fixtureEnv(row.ws) });
    }
    const tRoot = git(row.ws, "rev-parse", `${row.T}^{tree}`);
    const fRoot = git(row.ws, "rev-parse", `${foreign}^{tree}`);
    const dst = join(objects, tRoot.slice(0, 2), tRoot.slice(2));
    chmodSync(dst, 0o644);
    cpSync(join(objects, fRoot.slice(0, 2), fRoot.slice(2)), dst);
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(onRemote(row, foreign)).toBe(false);
    expect(heldWarn("hash_mismatch")).toHaveLength(1);
  });

  test("matrix 6: a forged refs/remotes/origin/main is never the base (parent is the ls-remote tip)", async () => {
    row = newRow();
    const foreign = foreignPlusKb(row, { dirtyCode: false });
    git(row.ws, "update-ref", "refs/remotes/origin/main", foreign);
    await run(row);
    const S = remoteMain(row);
    expect(parents(row.remote, S)).toEqual([row.T]);
    expect(onRemote(row, foreign)).toBe(false);
  });

  test("matrix 7: push.default=matching and a second local branch holding a foreign commit -> remote gains no branch", async () => {
    row = newRow();
    git(row.ws, "config", "push.default", "matching");
    git(row.ws, "config", "remote.origin.push", "refs/heads/*:refs/heads/*");
    git(row.ws, "checkout", "-q", "-b", "other");
    const foreign = foreignPlusKb(row, { kb: false, dirtyCode: false });
    git(row.remote, "update-ref", "refs/heads/other", row.T); // a remote 'other' a matching push would move
    git(row.ws, "checkout", "-q", "main");
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    expect(git(row.remote, "rev-parse", "refs/heads/other")).toBe(row.T);
    expect(onRemote(row, foreign)).toBe(false);
    expect(parents(row.remote, remoteMain(row))).toEqual([row.T]);
  });

  test("matrix 8: remote.origin.url pointed at another bare remote -> that remote receives nothing", async () => {
    row = newRow();
    const evil = join(row.root, "evil.git");
    execFileSync("git", ["init", "-q", "--bare", evil], { env: fixtureEnv(row.root) });
    git(row.ws, "remote", "set-url", "origin", `file://${evil}`);
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    expect(git(evil, "for-each-ref")).toBe("");
    expect(parents(row.remote, remoteMain(row))).toEqual([row.T]);
    for (const c of H.calls) expect(c.args.join(" ")).not.toContain(evil);
  });

  test("matrix 9: a remote KB edit fetched but not merged plus a local KB edit -> nothing pushed, remote_ahead", async () => {
    row = newRow();
    const T1 = upstreamCommit(row, (d) => write(join(d, "knowledge-base", "a.md"), "a\nremote kb edit\n"));
    git(row.ws, "fetch", "-q", "origin", "main");
    write(join(row.ws, "knowledge-base", "nested", "b.md"), "b\nlocal\n");
    await run(row);
    expect(remoteMain(row)).toBe(T1);
    expect(git(row.remote, "show", "refs/heads/main:knowledge-base/a.md")).toBe("a\nremote kb edit");
    expect(heldInfo("remote_ahead")).toHaveLength(1);
    expect(H.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  test("remote tip absent from the workspace -> nothing pushed, remote_unknown_tip", async () => {
    row = newRow();
    const T1 = upstreamCommit(row, (d) => write(join(d, "src", "s.ts"), "export const s = 9;\n"));
    write(join(row.ws, "knowledge-base", "a.md"), "a\nlocal\n");
    await run(row);
    expect(remoteMain(row)).toBe(T1);
    expect(heldInfo("remote_unknown_tip")).toHaveLength(1);
  });

  test("detached HEAD -> nothing pushed, detached_head", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    git(row.ws, "commit", "-q", "-am", "kb");
    git(row.ws, "checkout", "-q", "--detach");
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldWarn("detached_head")).toHaveLength(1);
  });

  test("matrix 18: a local feature branch that also exists on the remote -> remote feature unchanged, non_default_branch", async () => {
    row = newRow();
    git(row.remote, "update-ref", "refs/heads/feature", row.T);
    git(row.ws, "checkout", "-q", "-b", "feature");
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    expect(git(row.remote, "rev-parse", "refs/heads/feature")).toBe(row.T);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldWarn("non_default_branch")).toHaveLength(1);
  });

  test("a bare remote with no HEAD -> nothing pushed, remote_branch_absent", async () => {
    row = newRow();
    git(row.remote, "symbolic-ref", "HEAD", "refs/heads/nope");
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldWarn("remote_branch_absent")).toHaveLength(1);
  });

  test("knowledge-base replaced by a file -> nothing pushed, kb_not_tree", async () => {
    row = newRow();
    git(row.ws, "rm", "-q", "-r", "knowledge-base");
    write(join(row.ws, "knowledge-base"), "not a directory\n");
    git(row.ws, "add", "-A");
    git(row.ws, "commit", "-q", "-m", "kb file");
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldWarn("kb_not_tree")).toHaveLength(1);
  });

  test("matrix 17: MERGE_HEAD present with conflict markers in a KB file -> no auto-commit, no push, merge_in_progress", async () => {
    row = newRow();
    const before = localMain(row);
    write(join(row.ws, "knowledge-base", "a.md"), "<<<<<<< HEAD\na\n=======\nb\n>>>>>>> theirs\n");
    writeFileSync(join(row.ws, ".git", "MERGE_HEAD"), `${row.T}\n`);
    await run(row);
    expect(localMain(row)).toBe(before);
    expect(remoteMain(row)).toBe(row.T);
    expect(H.calls).toEqual([]);
    expect(heldWarn("merge_in_progress")).toHaveLength(1);
  });

  test("matrix 15: HEAD moves during the ls-remote -> nothing pushed, the new commit stays, head_moved", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    let moved = "";
    H.beforeCall = (args) => {
      if (args[0] !== "ls-remote" || moved) return;
      write(join(row.ws, "knowledge-base", "late.md"), "late\n");
      git(row.ws, "add", "-A");
      git(row.ws, "commit", "-q", "-m", "late");
      moved = git(row.ws, "rev-parse", "HEAD");
    };
    await run(row);
    expect(moved).not.toBe("");
    expect(localMain(row)).toBe(moved);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldWarn("head_moved")).toHaveLength(1);
  });

  test("matrix 19: refs/heads/main swapped to a symref after the HEAD read -> refs/heads/x is untouched", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    let x = "";
    H.beforeCall = (args) => {
      if (args[0] !== "ls-remote" || x) return;
      x = git(row.ws, "rev-parse", "HEAD");
      git(row.ws, "update-ref", "refs/heads/x", x);
      writeFileSync(join(row.ws, ".git", "refs", "heads", "main"), "ref: refs/heads/x\n");
    };
    await run(row);
    expect(x).not.toBe("");
    expect(git(row.ws, "rev-parse", "refs/heads/x")).toBe(x);
  });

  test("matrix 14: after H2 the real syncWorkspace (reconcile webhook shape) fast-forwards with no recovery branch", async () => {
    row = newRow();
    foreignPlusKb(row);
    await run(row);
    const result = await syncWorkspace(1, row.ws, H.log as never, { userId: USER, op: "push" });
    expect(result).toEqual({ ok: true });
    expect(git(row.ws, "for-each-ref", "--format=%(refname)", "refs/heads/soleur/")).toBe("");
    expect(status(row)).toBe(" M src/s.ts");
  });

  test("matrix 21: held foreign commit + dirty tracked code file, upstream main moves -> syncWorkspace does not reset", async () => {
    row = newRow();
    const foreign = foreignPlusKb(row, { kb: false });
    upstreamCommit(row, (d) => write(join(d, "README.md"), "readme 2\n"));
    const result = await syncWorkspace(1, row.ws, H.log as never, { userId: USER, op: "push" });
    expect(result.ok).toBe(false);
    expect(readFileSync(join(row.ws, "src", "s.ts"), "utf8")).toBe("export const s = 2; // dirty, uncommitted\n");
    expect(localMain(row)).toBe(foreign);
    const ops = H.reportSilentFallback.mock.calls.map(([, o]) => (o as { op?: string }).op);
    expect(ops).toContain("self-heal-aborted-dirty-nonkb");
  });

  test("R18 positive control: only KB files dirty -> syncWorkspace still recovers (branch-aside + reset)", async () => {
    row = newRow();
    foreignPlusKb(row, { kb: false, dirtyCode: false });
    write(join(row.ws, "knowledge-base", "a.md"), "a\ndirty kb\n");
    upstreamCommit(row, (d) => write(join(d, "README.md"), "readme 2\n"));
    const result = await syncWorkspace(1, row.ws, H.log as never, { userId: USER, op: "push" });
    expect(result).toEqual({ ok: true, recovered: true });
  });

  test("a failing ls-remote -> the isolated dir is disposed and op syncPush carries reason ls_remote_failed, no URL", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    H.remoteUrl = `file://${join(row.root, "missing.git")}`;
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    const outer = H.reportSilentFallback.mock.calls.filter(([, o]) => (o as { op?: string }).op === "syncPush");
    expect(outer).toHaveLength(1);
    const [err, ctx] = outer[0] as [unknown, { tags?: Record<string, string>; message?: string }];
    expect(ctx.tags?.reason).toBe("ls_remote_failed");
    expect(String((err as Error)?.message ?? "")).not.toMatch(/github\.com|file:\/\/|[0-9a-f]{40}/);
    expect(readdirSync(join(row.root, "home", ".soleur-push"))).toEqual([]);
  });
});

describe("protected default branch: side commit on soleur/kb-sync (real git, real pre-receive hook)", { timeout: 30_000 }, () => {
  test("matrix 12: KB-only edit + dirty code file -> single-parent side on T, PR created, local == tracking == side, dirty file kept", async () => {
    row = newRow({ protectedMain: true });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    write(join(row.ws, "src", "s.ts"), "export const s = 2; // dirty\n");
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    const side = remoteSide(row);
    expect(side).not.toBeNull();
    expect(parents(row.remote, side as string)).toEqual([row.T]);
    expect(nonKb(rootEntries(row.remote, side as string))).toEqual(nonKb(rootEntries(row.remote, row.T)));
    expect(ident(row.remote, side as string)).toBe(`${SOLEUR_NAME}|${SOLEUR_EMAIL}|${SOLEUR_NAME}|${SOLEUR_EMAIL}|${SIDE_MSG}`);
    expect(H.createPullRequest).toHaveBeenCalledTimes(1);
    expect(H.createPullRequest.mock.calls[0]).toEqual(expect.arrayContaining(["acme", "widget", "soleur/kb-sync", "main"]));
    expect(localMain(row)).toBe(side);
    expect(tracking(row)).toBe(side);
    expect(status(row)).toBe(" M src/s.ts");
    expect(readFileSync(join(row.ws, "src", "s.ts"), "utf8")).toBe("export const s = 2; // dirty\n");
  });

  test("matrix 13: protected + foreign commit -> local is M, keeps the foreign commit and the dirty code file", async () => {
    row = newRow({ protectedMain: true });
    const foreign = foreignPlusKb(row);
    await run(row);
    const side = remoteSide(row) as string;
    expect(side).toBeTruthy();
    expect(onRemote(row, foreign)).toBe(false);
    const M = localMain(row);
    expect(gitOk(row.ws, "merge-base", "--is-ancestor", foreign, M)).toBe(true);
    expect(git(row.ws, "log", "-1", "--format=%s", M)).toBe(MERGE_MSG);
    expect(status(row)).toBe(" M src/s.ts");
  });

  test("matrix 10: a forged refs/remotes/origin/soleur/kb-sync (remote has none) is never the side parent", async () => {
    row = newRow({ protectedMain: true });
    const foreign = foreignPlusKb(row, { dirtyCode: false });
    git(row.ws, "update-ref", "refs/remotes/origin/soleur/kb-sync", foreign);
    await run(row);
    const side = remoteSide(row) as string;
    expect(side).toBeTruthy();
    expect(parents(row.remote, side)).toEqual([row.T]);
    expect(onRemote(row, foreign)).toBe(false);
  });

  test("matrix 20: an unmerged side tip on an older T (ancestor of HEAD) -> side has parents (P, T); after a PR merge pull --ff-only fast-forwards", async () => {
    row = newRow({ protectedMain: true });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nturn 1\n");
    await run(row);
    const P = remoteSide(row) as string;
    expect(localMain(row)).toBe(P);
    const T1 = upstreamCommit(row, (d) => write(join(d, "src", "s.ts"), "export const s = 5;\n"));
    git(row.ws, "pull", "-q", "--no-rebase", "--no-edit", "origin", "main");
    write(join(row.ws, "knowledge-base", "nested", "b.md"), "b\nturn 2\n");
    await run(row);
    const side = remoteSide(row) as string;
    expect(side).not.toBe(P);
    expect(parents(row.remote, side)).toEqual([P, T1]);
    // PR merge simulation (bypasses the hook through update-ref), then the workspace fast-forwards
    const merger = mkdtempSync(join(row.root, "merge-"));
    execFileSync("git", ["clone", "-q", `file://${row.remote}`, merger], { env: fixtureEnv(row.root), stdio: "pipe" });
    git(merger, "merge", "-q", "--no-ff", "-m", "Merge PR", "origin/soleur/kb-sync");
    const merged = git(merger, "rev-parse", "HEAD");
    git(merger, "push", "-q", "origin", "HEAD:refs/heads/tmp-merge");
    git(row.remote, "update-ref", "refs/heads/main", merged);
    expect(gitOk(row.ws, "pull", "-q", "--ff-only", "origin", "main")).toBe(true);
  });

  test("matrix 16: a side tip holding unmerged KB content not in HEAD's history -> nothing pushed, side_ahead", async () => {
    row = newRow({ protectedMain: true });
    const dir = mkdtempSync(join(row.root, "pr-"));
    execFileSync("git", ["clone", "-q", `file://${row.remote}`, dir], { env: fixtureEnv(row.root), stdio: "pipe" });
    write(join(dir, "knowledge-base", "pr-only.md"), "unmerged PR content\n");
    git(dir, "add", "-A");
    git(dir, "commit", "-q", "-m", "side content");
    git(dir, "push", "-q", "origin", "HEAD:refs/heads/soleur/kb-sync");
    const P = remoteSide(row);
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    expect(remoteSide(row)).toBe(P);
    expect(git(row.remote, "show", "refs/heads/soleur/kb-sync:knowledge-base/pr-only.md")).toBe("unmerged PR content");
    expect(heldWarn("side_ahead")).toHaveLength(1);
  });

  test("matrix 16 positive: the side tip's KB equals T's (PR merged) -> the side commit is built", async () => {
    row = newRow({ protectedMain: true });
    const dir = mkdtempSync(join(row.root, "pr-"));
    execFileSync("git", ["clone", "-q", `file://${row.remote}`, dir], { env: fixtureEnv(row.root), stdio: "pipe" });
    write(join(dir, "README.md"), "side-only readme\n");
    git(dir, "add", "-A");
    git(dir, "commit", "-q", "-m", "older side");
    git(dir, "push", "-q", "origin", "HEAD:refs/heads/soleur/kb-sync");
    const P = remoteSide(row) as string;
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    const side = remoteSide(row) as string;
    expect(side).not.toBe(P);
    expect(gitOk(row.remote, "merge-base", "--is-ancestor", P, side)).toBe(true);
    expect(git(row.remote, "show", `${side}:knowledge-base/a.md`)).toBe("a\nkb");
  });
});

describe("census (AC3, AC4)", () => {
  const SERVER = join(__dirname, "..", "server");
  const code = (p: string): string =>
    existsSync(p) ? readFileSync(p, "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "") : "";
  test("the push argv appears exactly once in kb-sync-publish.ts and never in session-sync.ts", () => {
    const PUSH = /\[\s*["']push["']/g;
    expect((code(join(SERVER, "kb-sync-publish.ts")).match(PUSH) ?? []).length).toBe(1);
    expect((code(join(SERVER, "session-sync.ts")).match(PUSH) ?? []).length).toBe(0);
  });
  test("no history walk, no agent-writable base, no legacy resolver", () => {
    const publish = code(join(SERVER, "kb-sync-publish.ts"));
    expect(publish).not.toBe("");
    expect(publish).not.toMatch(/@\{u\}/);
    const remotes = publish.match(/refs\/remotes\/[^"'`\s]*/g) ?? [];
    for (const m of remotes) expect(m).toMatch(/^refs\/remotes\/origin\/$/);
    for (const f of ["session-sync.ts", "kb-sync-publish.ts", "workspace-sync.ts"]) {
      expect(code(join(SERVER, f))).not.toMatch(/resolveDefaultBranchForFallback|checkKbOnlyRange|simplify-merges/);
    }
  });
});
