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
  /** Runs after a token-bearing call SUCCEEDED (a push that lands at the remote while the client sees an error, D14). */
  afterCall: null as null | ((args: string[]) => void),
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
  /** Every direct `runIsolatedGitLocal` call kb-sync-publish makes (args, stdin, stdout, exit code). */
  iso: [] as Array<{ args: string[]; input: string; stdout: Buffer; code: number }>,
  /** Every `verifyObject` call (type, id). */
  verify: [] as Array<{ type: string; id: string }>,
  /** When > 0, every direct isolated call runs with this stdout cap (the D10 scaled row). */
  isoMaxBuffer: 0,
  /** Returns a fake runner result for an isolated call (tri-state rows); null runs the real child. */
  isoFault: null as null | ((args: string[]) => { code: number; stdout: Buffer; stderr: string; timedOut: boolean } | null),
  verifyFault: null as null | ((type: string, id: string) => unknown),
  writeRepoCols: vi.fn(async () => undefined),
  rpc: vi.fn(async () => ({ data: null, error: null })),
  findOpenPullRequest: vi.fn(async () => null as null | { htmlUrl: string }),
  /** The fake GitHub PR list (D17): `createPullRequest` appends an open PR on the remote's side tip; rows may close one. */
  prs: [] as Array<{ number: number; htmlUrl: string; url: string; state: "open" | "closed"; merged: boolean; headSha: string }>,
  sideTipNow: (() => "") as () => string,
  createPullRequest: vi.fn(async () => ({ htmlUrl: "https://github.com/acme/widget/pull/1" })),
  listPullRequestsForHead: vi.fn(async () => [] as unknown[]),
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
vi.mock("@/server/workspace-repo-mirror", () => ({ writeRepoColsToWorkspace: H.writeRepoCols }));
vi.mock("@/server/resolve-installation-id", () => ({ resolveInstallationId: async () => 1 }));
vi.mock("@/server/current-repo-url", () => ({ getCurrentRepoUrl: async () => "https://github.com/acme/widget" }));
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: async () => ["ghs", "_", "b".repeat(40)].join(""),
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
// Record every authenticated git call, then rewrite ONLY the literal fixture URL token to the local bare remote.
vi.mock("@/server/git-auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-auth")>();
  return {
    ...actual,
    gitWithInstallationAuth: async (args: string[], id: number, opts: import("@/server/git-auth").GitExecOptions = {}) => {
      H.calls.push({ args: [...args], hardened: opts.hardened !== undefined, cwd: opts.cwd });
      H.beforeCall?.(args);
      const rewritten = args.map((a) => (a === "https://github.com/acme/widget.git" ? H.remoteUrl : a));
      const out = await actual.gitWithInstallationAuth(rewritten, id, opts);
      H.afterCall?.(args);
      return out;
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
// Records the token-free isolated calls (pack shape, Guard 1 count) and injects the tri-state faults. `verifyObject`'s own
// child is internal to the module, so `verifyObject` is wrapped as a whole.
vi.mock("@/server/git-isolated-local", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-isolated-local")>();
  return {
    ...actual,
    runIsolatedGitLocal: async (
      iso: import("@/server/git-hardened-env").IsolatedPushDir,
      args: readonly string[],
      opts: import("@/server/git-isolated-local").IsolatedGitLocalOptions = {},
    ) => {
      const faked = H.isoFault?.([...args]) ?? null;
      const r = faked ?? (await actual.runIsolatedGitLocal(iso, args, H.isoMaxBuffer > 0 ? { ...opts, maxBufferBytes: H.isoMaxBuffer } : opts));
      H.iso.push({ args: [...args], input: opts.input === undefined ? "" : opts.input.toString(), stdout: r.stdout, code: r.code });
      return r;
    },
    verifyObject: async (iso: import("@/server/git-hardened-env").IsolatedPushDir, type: import("@/server/git-isolated-local").GitObjectType, id: string) => {
      H.verify.push({ type, id });
      const faked = H.verifyFault?.(type, id);
      return faked !== undefined && faked !== null ? faked : actual.verifyObject(iso, type, id);
    },
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

function newRow(opts: { protectedMain?: boolean; prep?: (r: { root: string; remote: string }) => void } = {}): Row {
  const root = realpathSync(mkdtempSync(join(base, "row-")));
  const remote = join(root, "remote.git");
  cpSync(template, remote, { recursive: true });
  opts.prep?.({ root, remote });
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
function upstreamCommit(r: { root: string; remote: string }, edit: (dir: string) => void, msg = "upstream", addAll = true): string {
  const dir = mkdtempSync(join(r.root, "up-"));
  execFileSync("git", ["clone", "-q", `file://${r.remote}`, dir], { env: fixtureEnv(r.root), stdio: "pipe" });
  edit(dir);
  if (addAll) git(dir, "add", "-A");
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
const pushesOf = (): string[] => H.calls.filter((c) => c.args[0] === "push").map((c) => c.args[c.args.length - 1]);
/** Every `kb-sync.push-held` outcome line of the turn, in order (D14(5): never more than one). */
const heldLines = (): string[] =>
  H.log.info.mock.calls.filter(([o]) => (o as { op?: string })?.op === "kb-sync.push-held").map(([o]) => (o as { reason: string }).reason);
/** The `kb-sync-fallback-failed:<reason>` debounce classes the turn emitted (error and warning helpers alike). */
const fallbackFailed = (): string[] =>
  [...H.mirrorWithDebounce.mock.calls, ...H.mirrorWarnWithDebounce.mock.calls]
    .map(([, , , cls]) => cls as string)
    .filter((cls) => cls.startsWith("kb-sync-fallback-failed:"));
const sleepSync = (ms: number): void => {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
};
const subjectOf = (dir: string, sha: string): string => git(dir, "log", "-1", "--format=%s", sha);
/** The hand-over packs of the turn: the object list on stdin, the argv and the object count in the pack header. */
const packs = (): Array<{ args: string[]; objects: string[]; count: number }> =>
  H.iso
    .filter((c) => c.args[0] === "pack-objects")
    .map((c) => ({ args: c.args, objects: c.input.split("\n").filter(Boolean), count: c.stdout.length >= 12 ? c.stdout.readUInt32BE(8) : -1 }));
const guardReads = (sha: string): number => H.verify.filter((v) => v.type === "commit" && v.id === sha).length;
/** Make every workspace object loose (so a row can overwrite one object's file). */
function loosenObjects(r: Row): string {
  const objects = join(r.ws, ".git", "objects");
  for (const p of readdirSync(join(objects, "pack")).filter((f) => f.endsWith(".pack"))) {
    const packPath = join(objects, "pack", p);
    const moved = join(r.root, p);
    cpSync(packPath, moved);
    rmSync(packPath);
    rmSync(packPath.replace(/\.pack$/, ".idx"), { force: true });
    execFileSync("git", ["unpack-objects", "-q"], { cwd: r.ws, input: readFileSync(moved), env: fixtureEnv(r.ws) });
  }
  return objects;
}
/** Overwrite the loose object file of `victim` with the bytes of `donor` (a forged object under a genuine id). */
function forgeObject(r: Row, victim: string, donor: string): void {
  const objects = join(r.ws, ".git", "objects");
  const dst = join(objects, victim.slice(0, 2), victim.slice(2));
  chmodSync(dst, 0o644);
  cpSync(join(objects, donor.slice(0, 2), donor.slice(2)), dst);
}
const resetTurn = (): void => {
  H.calls.length = 0;
  H.iso.length = 0;
  H.verify.length = 0;
  for (const f of [H.reportSilentFallback, H.warnSilentFallback, H.mirrorWithDebounce, H.mirrorWarnWithDebounce, H.findOpenPullRequest, H.createPullRequest, H.listPullRequestsForHead, H.log.info]) f.mockClear();
};

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
  // a row that never sets `row` (the census) must not assert on the previous row's directory
  row = undefined as unknown as Row;
  H.calls.length = 0;
  H.iso.length = 0;
  H.verify.length = 0;
  H.isoMaxBuffer = 0;
  H.isoFault = null;
  H.verifyFault = null;
  H.beforeCall = null;
  H.afterCall = null;
  for (const f of [H.reportSilentFallback, H.warnSilentFallback, H.mirrorWithDebounce, H.mirrorWarnWithDebounce, H.writeRepoCols, H.rpc, H.findOpenPullRequest, H.createPullRequest, H.listPullRequestsForHead, H.log.info, H.log.warn, H.log.error, H.log.debug]) f.mockClear();
  H.findOpenPullRequest.mockImplementation(async () => null);
  H.prs.length = 0;
  H.sideTipNow = () => (row ? (remoteSide(row) ?? "") : "");
  H.createPullRequest.mockImplementation(async () => {
    const n = H.prs.length + 1;
    const pr = { number: n, htmlUrl: `https://github.com/acme/widget/pull/${n}`, url: "", state: "open" as const, merged: false, headSha: H.sideTipNow() };
    H.prs.push(pr);
    return pr;
  });
  H.listPullRequestsForHead.mockImplementation(async () => H.prs.map((p) => ({ ...p })));
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
    // D10: the hand-over packs exactly S and its root tree, from an explicit object list (no --revs walk)
    const sTree = git(row.remote, "rev-parse", `${S}^{tree}`);
    expect(packs()).toEqual([{ args: ["pack-objects", "--stdout", "-q"], objects: [S, sTree], count: 2 }]);
    // D13: Guard 1 reads S once
    expect(guardReads(S)).toBe(1);
  });

  test("H1c: a failing tracking-ref update still publishes S and mirrors one debounced kb-sync.tracking-ref warning", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb edit\n");
    const lock = join(row.ws, ".git", "refs", "remotes", "origin", "main.lock");
    mkdirSync(join(row.ws, ".git", "refs", "remotes", "origin"), { recursive: true });
    writeFileSync(lock, "");
    await run(row);
    const S = remoteMain(row);
    expect(parents(row.remote, S)).toEqual([row.T]);
    expect(localMain(row)).toBe(S);
    expect(tracking(row)).toBe(row.T);
    const mirrored = H.mirrorWarnWithDebounce.mock.calls.filter(([, , , cls]) => cls === "kb-sync-tracking-ref");
    expect(mirrored).toHaveLength(1);
    const [, ctx, key] = mirrored[0] as [unknown, { op: string; feature: string; extra: Record<string, unknown> }, string];
    expect(ctx).toEqual(expect.objectContaining({ feature: "session-sync", op: "kb-sync.tracking-ref", extra: { userId: USER } }));
    expect(key).toBe(WS_ID);
    rmSync(lock);
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
    // D10: S, its root tree and M (M's tree is HEAD's, already local)
    expect(packs()).toEqual([{ args: ["pack-objects", "--stdout", "-q"], objects: [S, git(row.remote, "rev-parse", `${S}^{tree}`), M], count: 3 }]);
    expect(guardReads(S)).toBe(1);
  });

  test("D10: a KB change set larger than the isolated stdout cap still syncs (the pack carries only the server-built objects)", async () => {
    row = newRow();
    // Scaled: production caps the isolated stdout at 64 MiB; this row lowers the cap to 1 MiB through the runner's
    // injectable maxBufferBytes and writes 3 MiB of incompressible KB content, the same "change set > cap" property at
    // a size that keeps the row fast (a 64 MiB fixture would cost ~10 s and ~200 MB of disk per run).
    H.isoMaxBuffer = 1024 * 1024;
    const { createHash } = await import("node:crypto");
    const chunks: Buffer[] = [];
    for (let i = 0; chunks.length * 32 < 3 * 1024 * 1024; i++) chunks.push(createHash("sha256").update(`kb-fixture-${i}`).digest());
    write(join(row.ws, "knowledge-base", "big.bin"), "");
    writeFileSync(join(row.ws, "knowledge-base", "big.bin"), Buffer.concat(chunks));
    await run(row);
    const S = remoteMain(row);
    expect(parents(row.remote, S)).toEqual([row.T]);
    expect(localMain(row)).toBe(S);
    expect(heldInfo("unpack_failed")).toHaveLength(0);
    expect(packs().map((p) => p.count)).toEqual([2]);
    // Instrument control (D19(4)): the injected 1 MiB cap bites. The same runner on an output above it returns -1, and the
    // same read with the cap lifted succeeds, so the row above passed because the pack is small, not because no cap applied.
    const { createIsolatedPushDir } = await import("@/server/git-isolated-push-dir");
    const { runIsolatedGitLocal } = await import("@/server/git-isolated-local");
    const { disposeIsolated } = await import("@/server/push-branch");
    const iso = createIsolatedPushDir(row.ws);
    try {
      const blob = git(row.ws, "rev-parse", `${S}:knowledge-base/big.bin`);
      expect((await runIsolatedGitLocal(iso, ["cat-file", "blob", blob])).code).toBe(-1);
      H.isoMaxBuffer = 0;
      const full = await runIsolatedGitLocal(iso, ["cat-file", "blob", blob]);
      expect(full.code).toBe(0);
      expect(full.stdout.length).toBeGreaterThan(1024 * 1024);
    } finally {
      disposeIsolated(iso);
    }
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
    loosenObjects(row);
    forgeObject(row, git(row.ws, "rev-parse", `${row.T}^{tree}`), git(row.ws, "rev-parse", `${foreign}^{tree}`));
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(onRemote(row, foreign)).toBe(false);
    expect(heldWarn("hash_mismatch")).toHaveLength(1);
  });

  test("matrix 2b (TD-forge): forged bytes for T's COMMIT object (tree pointer swapped to the foreign root) -> nothing pushed", async () => {
    row = newRow();
    // the same .github subtree already exists on the remote, on a non-default branch, so connectivity alone cannot stop it
    {
      const d = mkdtempSync(join(row.root, "ci-"));
      execFileSync("git", ["clone", "-q", `file://${row.remote}`, d], { env: fixtureEnv(row.root), stdio: "pipe" });
      write(join(d, ".github", "workflows", "x.yml"), "on: push\njobs: {}\n");
      git(d, "add", "-A");
      git(d, "commit", "-q", "-m", "ci branch");
      git(d, "push", "-q", "origin", "HEAD:refs/heads/ci-branch");
    }
    const foreign = foreignPlusKb(row, { dirtyCode: false });
    git(row.ws, "add", "-A");
    git(row.ws, "commit", "-q", "-m", "kb");
    loosenObjects(row);
    const fRoot = git(row.ws, "rev-parse", `${foreign}^{tree}`);
    const forged = git(row.ws, "commit-tree", fRoot, "-m", "T0");
    forgeObject(row, row.T, forged);
    // instrument check: the workspace now serves the forged bytes under T's id
    expect(git(row.ws, "cat-file", "commit", row.T)).toContain(`tree ${fRoot}`);
    await run(row);
    expect(gitOk(row.remote, "cat-file", "-e", "refs/heads/main:.github/workflows/x.yml")).toBe(false);
    expect(remoteMain(row)).toBe(row.T);
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

  test("matrix 19b (setTracking twin): refs/remotes/origin/main swapped to a symref during the turn -> its target is untouched", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    let y = "";
    H.beforeCall = (args) => {
      if (args[0] !== "ls-remote" || y) return;
      y = git(row.ws, "rev-parse", "HEAD");
      git(row.ws, "update-ref", "refs/heads/y", y);
      mkdirSync(join(row.ws, ".git", "refs", "remotes", "origin"), { recursive: true });
      writeFileSync(join(row.ws, ".git", "refs", "remotes", "origin", "main"), "ref: refs/heads/y\n");
    };
    await run(row);
    const S = remoteMain(row);
    expect(S).not.toBe(row.T);
    expect(y).not.toBe("");
    // --no-deref: the symref itself is replaced, the branch it pointed at never moves
    expect(git(row.ws, "rev-parse", "refs/heads/y")).toBe(y);
    expect(git(row.ws, "rev-parse", "refs/remotes/origin/main")).toBe(S);
  });

  test("D13 tri-state: a failing cat-file -t child is local_git_failed (outer catch), never remote_unknown_tip", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    H.isoFault = (args) => (args[0] === "cat-file" && args[1] === "-t" ? { code: -1, stdout: Buffer.alloc(0), stderr: "", timedOut: true } : null);
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldInfo("remote_unknown_tip")).toHaveLength(0);
    const outer = H.reportSilentFallback.mock.calls.filter(([, o]) => (o as { op?: string }).op === "syncPush");
    expect(outer).toHaveLength(1);
    expect((outer[0][1] as { tags?: Record<string, string> }).tags?.reason).toBe("local_git_failed");
  });

  test("D13 tri-state: a failing object read is local_git_failed (outer catch), never hash_mismatch", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    H.verifyFault = (type) => (type === "commit" ? { kind: "failed" } : null);
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldWarn("hash_mismatch")).toHaveLength(0);
    const outer = H.reportSilentFallback.mock.calls.filter(([, o]) => (o as { op?: string }).op === "syncPush");
    expect(outer).toHaveLength(1);
    expect((outer[0][1] as { tags?: Record<string, string> }).tags?.reason).toBe("local_git_failed");
  });

  test("D13: unmerged index entries without MERGE_HEAD (a conflicted stash pop / cherry-pick shape) -> no auto-commit, no push, merge_in_progress", async () => {
    row = newRow();
    const before = localMain(row);
    const blob = (body: string): string =>
      execFileSync("git", ["hash-object", "-w", "--stdin"], { cwd: row.ws, input: body, encoding: "utf8", env: fixtureEnv(row.ws) }).trim();
    const [b1, b2, b3] = [blob("a\n"), blob("a\nours\n"), blob("a\ntheirs\n")];
    execFileSync("git", ["update-index", "--index-info"], {
      cwd: row.ws,
      input: `0 ${"0".repeat(40)}\tknowledge-base/a.md\n100644 ${b1} 1\tknowledge-base/a.md\n100644 ${b2} 2\tknowledge-base/a.md\n100644 ${b3} 3\tknowledge-base/a.md\n`,
      env: fixtureEnv(row.ws),
    });
    write(join(row.ws, "knowledge-base", "a.md"), "<<<<<<< ours\na\nours\n=======\na\ntheirs\n>>>>>>> theirs\n");
    expect(existsSync(join(row.ws, ".git", "MERGE_HEAD"))).toBe(false);
    await run(row);
    expect(localMain(row)).toBe(before);
    expect(remoteMain(row)).toBe(row.T);
    expect(H.calls).toEqual([]);
    expect(heldWarn("merge_in_progress")).toHaveLength(1);
  });

  test("fixture: a root-level submodule (gitlink) survives S unchanged", async () => {
    const SUB = "1".repeat(40);
    row = newRow({
      prep: (r) =>
        upstreamCommit(
          r,
          (d) => {
            git(d, "update-index", "--add", "--cacheinfo", `160000,${SUB},vendor-sub`);
          },
          "gitlink",
          false,
        ),
    });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    const S = remoteMain(row);
    expect(parents(row.remote, S)).toEqual([row.T]);
    expect(rootEntries(row.remote, S)).toContain(`160000 commit ${SUB}\tvendor-sub`);
    expect(nonKb(rootEntries(row.remote, S))).toEqual(nonKb(rootEntries(row.remote, row.T)));
    expect(localMain(row)).toBe(S);
  });

  test("fixture: a non-ASCII root entry name round-trips byte-exact into S", async () => {
    row = newRow({ prep: (r) => upstreamCommit(r, (d) => write(join(d, "caf\u00e9-\u00fcber.md"), "accents\n"), "non-ascii") });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    const S = remoteMain(row);
    expect(parents(row.remote, S)).toEqual([row.T]);
    expect(git(row.remote, "rev-parse", `${S}^{tree}`)).toBe(git(row.ws, "rev-parse", "HEAD^{tree}"));
    expect(nonKb(rootEntries(row.remote, S))).toEqual(nonKb(rootEntries(row.remote, row.T)));
    expect(localMain(row)).toBe(S);
  });

  test("fixture: the first-ever sync (T has no knowledge-base) publishes S = T's root plus HEAD's knowledge-base", async () => {
    row = newRow({ prep: (r) => upstreamCommit(r, (d) => rmSync(join(d, "knowledge-base"), { recursive: true }), "no kb yet") });
    expect(gitOk(row.remote, "cat-file", "-e", `${row.T}:knowledge-base`)).toBe(false);
    write(join(row.ws, "knowledge-base", "first.md"), "first\n");
    await run(row);
    const S = remoteMain(row);
    expect(parents(row.remote, S)).toEqual([row.T]);
    expect(git(row.remote, "show", `${S}:knowledge-base/first.md`)).toBe("first");
    expect(nonKb(rootEntries(row.remote, S))).toEqual(nonKb(rootEntries(row.remote, row.T)));
    expect(localMain(row)).toBe(S);
  });

  test("fixture: HEAD deleted the whole knowledge-base the remote holds -> nothing pushed, kb_absent (not kb_not_tree)", async () => {
    row = newRow();
    git(row.ws, "rm", "-q", "-r", "knowledge-base");
    git(row.ws, "commit", "-q", "-m", "drop kb");
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldWarn("kb_absent")).toHaveLength(1);
    expect(heldWarn("kb_not_tree")).toHaveLength(0);
  });

  test("fixture: no knowledge-base on either side and a code-only commit -> held_foreign info, no warning", async () => {
    row = newRow({ prep: (r) => upstreamCommit(r, (d) => rmSync(join(d, "knowledge-base"), { recursive: true }), "no kb") });
    foreignPlusKb(row, { kb: false, dirtyCode: false });
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(heldInfo("held_foreign")).toHaveLength(1);
    expect(H.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  test("fixture: a binary KB file (NUL bytes) is published byte-exact", async () => {
    row = newRow();
    const bin = Buffer.from([0, 1, 2, 255, 0, 10, 13, 0x80, 0xfe, 0]);
    mkdirSync(join(row.ws, "knowledge-base", "assets"), { recursive: true });
    writeFileSync(join(row.ws, "knowledge-base", "assets", "x.bin"), bin);
    await run(row);
    const S = remoteMain(row);
    expect(parents(row.remote, S)).toEqual([row.T]);
    const onRemoteBytes = execFileSync("git", ["cat-file", "blob", `${S}:knowledge-base/assets/x.bin`], { cwd: row.remote, env: fixtureEnv(row.remote) });
    expect(Buffer.compare(onRemoteBytes, bin)).toBe(0);
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
    // D6(b)/(e): the designed hold is a debounced, null-first warning with op self-heal-aborted-dirty-tracked
    const ops = H.mirrorWarnWithDebounce.mock.calls.map(([err, o]) => ({ err, op: (o as { op?: string }).op }));
    expect(ops).toContainEqual({ err: null, op: "self-heal-aborted-dirty-tracked" });
  });

  test("D6(b) (was the R18 positive control): only KB files dirty -> syncWorkspace refuses too and keeps the KB edit", async () => {
    row = newRow();
    const foreign = foreignPlusKb(row, { kb: false, dirtyCode: false });
    write(join(row.ws, "knowledge-base", "a.md"), "a\ndirty kb\n");
    upstreamCommit(row, (d) => write(join(d, "README.md"), "readme 2\n"));
    const result = await syncWorkspace(1, row.ws, H.log as never, { userId: USER, op: "push" });
    expect(result.ok).toBe(false);
    expect(readFileSync(join(row.ws, "knowledge-base", "a.md"), "utf8")).toBe("a\ndirty kb\n");
    expect(localMain(row)).toBe(foreign);
    const ops = H.mirrorWarnWithDebounce.mock.calls.map(([err, o]) => ({ err, op: (o as { op?: string }).op }));
    expect(ops).toContainEqual({ err: null, op: "self-heal-aborted-dirty-tracked" });
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
  test("matrix 12: KB-only edit + dirty code file -> single-parent side on T, PR created, local == side, tracking == T, dirty file kept", async () => {
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
    // D11: the tracking ref says what GitHub's main is (T), never the side commit
    expect(tracking(row)).toBe(row.T);
    expect(status(row)).toBe(" M src/s.ts");
    expect(readFileSync(join(row.ws, "src", "s.ts"), "utf8")).toBe("export const s = 2; // dirty\n");
    // one rejected push to main, one side push; no fetch on the push side (D5d)
    expect(pushesOf().map((r) => r.split(":")[1])).toEqual(["refs/heads/main", "refs/heads/soleur/kb-sync"]);
    expect(H.calls.filter((c) => c.args[0] === "fetch")).toEqual([]);
    // D10: step 4 packs S + root tree, the side hand-over packs side + root tree
    const tree = git(row.remote, "rev-parse", `${side}^{tree}`);
    const S = packs()[0]?.objects[0];
    expect(packs().map((p) => p.objects)).toEqual([[S, tree], [side, tree]]);
    expect(guardReads(side as string)).toBe(1);
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
    // D5c: the local merge links the SIDE commit (M' = merge(headSha, side)), so the next turn sees the side as local
    expect(parents(row.ws, M)[1]).toBe(side);
    expect(gitOk(row.ws, "merge-base", "--is-ancestor", side, M)).toBe(true);
    expect(git(row.ws, "rev-parse", `${M}^{tree}`)).toBe(git(row.ws, "rev-parse", `${parents(row.ws, M)[0]}^{tree}`));
    expect(tracking(row)).toBe(row.T);
    // D10: the side hand-over packs side, its root tree and M'
    expect(packs()[1]?.objects).toEqual([side, git(row.remote, "rev-parse", `${side}^{tree}`), M]);
  });

  test("D5: protected + held code, three turns (edit, no edit, no edit) -> no M growth and no repeated push to main", async () => {
    row = newRow({ protectedMain: true });
    foreignPlusKb(row);
    await run(row);
    const side = remoteSide(row) as string;
    const M1 = localMain(row);
    expect(parents(row.ws, M1)[1]).toBe(side);
    expect(pushesOf()).toHaveLength(2);
    for (const turn of [2, 3]) {
      resetTurn();
      await run(row);
      expect(localMain(row), `turn ${turn}: local branch`).toBe(M1);
      expect(pushesOf(), `turn ${turn}: pushes`).toEqual([]);
      expect(remoteSide(row)).toBe(side);
      expect(H.calls.map((c) => c.args[0])).toEqual(["ls-remote"]);
      expect(heldInfo("side_pending")).toHaveLength(1);
      expect(heldWarn("side_pending")).toEqual([]);
      // D17: one PR re-check (state=all) finds the open PR on the side tip, so nothing is created
      expect(H.listPullRequestsForHead).toHaveBeenCalledTimes(1);
      expect(H.listPullRequestsForHead.mock.calls[0]).toEqual([1, "acme", "widget", "soleur/kb-sync", "main"]);
      expect(H.findOpenPullRequest).not.toHaveBeenCalled();
      expect(H.createPullRequest).not.toHaveBeenCalled();
      expect(H.warnSilentFallback).not.toHaveBeenCalled();
      expect(H.mirrorWithDebounce).not.toHaveBeenCalled();
    }
    expect(git(row.ws, "rev-list", "--count", `${row.T}..${M1}`)).toBe(git(row.ws, "rev-list", "--count", `${row.T}..refs/heads/main`));
  });

  test("D5: protected + KB-only, two editing turns -> the second side commit stacks on the first; local follows the side", async () => {
    row = newRow({ protectedMain: true });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nturn 1\n");
    await run(row);
    const side1 = remoteSide(row) as string;
    expect(localMain(row)).toBe(side1);
    resetTurn();
    write(join(row.ws, "knowledge-base", "nested", "b.md"), "b\nturn 2\n");
    await run(row);
    const side2 = remoteSide(row) as string;
    expect(side2).not.toBe(side1);
    expect(parents(row.remote, side2)).toEqual([side1]);
    expect(localMain(row)).toBe(side2);
    expect(tracking(row)).toBe(row.T);
    expect(git(row.remote, "show", `${side2}:knowledge-base/a.md`)).toBe("a\nturn 1");
    expect(git(row.remote, "show", `${side2}:knowledge-base/nested/b.md`)).toBe("b\nturn 2");
    // a no-edit turn after that: side_pending, nothing pushed
    resetTurn();
    await run(row);
    expect(pushesOf()).toEqual([]);
    expect(localMain(row)).toBe(side2);
    expect(heldInfo("side_pending")).toHaveLength(1);
  });

  test("D5d interim: a side tip absent from the workspace -> side_ahead with no fetch (Phase 9 adopts it on the pull side)", async () => {
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
    expect(remoteSide(row)).toBe(P);
    expect(H.calls.filter((c) => c.args[0] === "fetch")).toEqual([]);
    expect(heldWarn("side_ahead")).toHaveLength(1);
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
    expect(H.calls.filter((c) => c.args[0] === "fetch")).toEqual([]);
  });

  test("matrix 16 forge twin: a forged side tip P (KB equal to T's, parent T) never makes the fallback drop the PR's content", async () => {
    row = newRow({ protectedMain: true });
    const dir = mkdtempSync(join(row.root, "pr-"));
    execFileSync("git", ["clone", "-q", `file://${row.remote}`, dir], { env: fixtureEnv(row.root), stdio: "pipe" });
    write(join(dir, "knowledge-base", "pr-only.md"), "unmerged PR content\n");
    git(dir, "add", "-A");
    git(dir, "commit", "-q", "-m", "side content");
    git(dir, "push", "-q", "origin", "HEAD:refs/heads/soleur/kb-sync");
    const P = remoteSide(row) as string;
    // the workspace holds P's objects (a fetch of the side branch), then the agent forges P's commit bytes: same id, a
    // commit whose tree is T's (so its KB equals T's: "the PR merged") and whose parent is T
    git(row.ws, "fetch", "-q", "origin", "refs/heads/soleur/kb-sync");
    loosenObjects(row);
    const forged = git(row.ws, "commit-tree", `${row.T}^{tree}`, "-p", row.T, "-m", "side content");
    forgeObject(row, P, forged);
    expect(git(row.ws, "cat-file", "commit", P)).toContain(`tree ${git(row.ws, "rev-parse", `${row.T}^{tree}`)}`);
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    expect(remoteSide(row)).toBe(P);
    expect(git(row.remote, "show", "refs/heads/soleur/kb-sync:knowledge-base/pr-only.md")).toBe("unmerged PR content");
    const failed = H.mirrorWithDebounce.mock.calls.filter(([, , , cls]) => cls === "kb-sync-fallback-failed:side_hash_mismatch");
    expect(failed).toHaveLength(1);
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
    // P present in the workspace (D5d: the push side never fetches it)
    git(row.ws, "fetch", "-q", "origin", "refs/heads/soleur/kb-sync");
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    const side = remoteSide(row) as string;
    expect(side).not.toBe(P);
    expect(gitOk(row.remote, "merge-base", "--is-ancestor", P, side)).toBe(true);
    expect(git(row.remote, "show", `${side}:knowledge-base/a.md`)).toBe("a\nkb");
  });
});

// CTO ruling D14: the fallback converges on EVERY exit, not only on success. The local branch keeps side lineage before the
// push (the M arm whenever a present side tip is an ancestor of HEAD), the link runs right after the side push and before the
// PR, and every exit before the link moves the local branch back to the turn's HEAD (never after a non-protected D push error).
describe("D14: the protected-branch fallback converges on every exit (real git)", { timeout: 60_000 }, () => {
  const setHook = (r: Row, body: string): void => {
    writeFileSync(join(r.remote, "hooks", "pre-receive"), body);
    chmodSync(join(r.remote, "hooks", "pre-receive"), 0o755);
  };
  const SIDE_TOO_HOOK = GH006_HOOK.replace(
    'if [ "$ref" = "refs/heads/main" ]; then',
    'if [ "$ref" = "refs/heads/main" ] || [ "$ref" = "refs/heads/soleur/kb-sync" ]; then',
  );
  const isAnc = (r: Row, a: string, b = "refs/heads/main"): boolean => gitOk(r.ws, "merge-base", "--is-ancestor", a, b);
  /** A KB-only protected workspace after turn 1: the local branch IS side1 (S -> side link). */
  const kbOnlyTurn1 = async (): Promise<string> => {
    row = newRow({ protectedMain: true });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nturn 1\n");
    await run(row);
    const side1 = remoteSide(row) as string;
    expect(side1).toBeTruthy();
    expect(localMain(row)).toBe(side1);
    resetTurn();
    return side1;
  };
  /** Turn 3 after a failed turn 2: a new KB edit stacks on `prev` (no side_ahead) and is linked locally. */
  const turn3StacksOn = async (prev: string): Promise<void> => {
    resetTurn();
    H.beforeCall = null;
    write(join(row.ws, "knowledge-base", "a.md"), "a\nturn 3\n");
    await run(row);
    const side3 = remoteSide(row) as string;
    expect(side3).not.toBe(prev);
    expect(parents(row.remote, side3)).toEqual([prev]);
    expect(heldWarn("side_ahead")).toEqual([]);
    expect(isAnc(row, side3)).toBe(true);
    expect(heldLines()).toEqual(["synthetic_pushed"]);
  };

  test("A1: KB-only, turn-2 PR creation fails after the side push -> the link is kept (pr_failed), turn 3 stacks on side2", async () => {
    const side1 = await kbOnlyTurn1();
    H.createPullRequest.mockImplementationOnce(async () => {
      throw new Error("502");
    });
    write(join(row.ws, "knowledge-base", "nested", "b.md"), "b\nturn 2\n");
    await run(row);
    const side2 = remoteSide(row) as string;
    expect(parents(row.remote, side2)).toEqual([side1]);
    // D14(2): the link ran before the PR, so side2 is local lineage even though the PR failed
    expect(localMain(row)).toBe(side2);
    expect(fallbackFailed()).toEqual(["kb-sync-fallback-failed:pr_failed"]);
    expect(heldLines()).toEqual([]);
    expect(tracking(row)).toBe(row.T);
    await turn3StacksOn(side2);
  });

  test("A2: KB-only, a transient side push failure on turn 2 -> rolled back to the turn's HEAD (side1 kept), turn 3 stacks on side1", async () => {
    const side1 = await kbOnlyTurn1();
    H.beforeCall = (args) => {
      if (args[0] === "push" && args.some((a) => a.endsWith(":refs/heads/soleur/kb-sync"))) {
        throw Object.assign(new Error("transient"), { stderr: "fatal: unable to access: Could not resolve host: github.com\n" });
      }
    };
    write(join(row.ws, "knowledge-base", "nested", "b.md"), "b\nturn 2\n");
    await run(row);
    expect(remoteSide(row)).toBe(side1);
    // D14(4): the scoped rollback put the local branch back on the turn's HEAD, the auto-commit on side1
    const head2 = localMain(row);
    expect(parents(row.ws, head2)).toEqual([side1]);
    expect(subjectOf(row.ws, head2)).toBe("Auto-commit after session");
    expect(fallbackFailed()).toHaveLength(1);
    await turn3StacksOn(side1);
  });

  test("KB-only, side1 present and the side push REJECTED on turn 2 -> the local branch keeps side1, turn 3 side parent = side1", async () => {
    const side1 = await kbOnlyTurn1();
    setHook(row, SIDE_TOO_HOOK);
    write(join(row.ws, "knowledge-base", "nested", "b.md"), "b\nturn 2\n");
    await run(row);
    expect(remoteSide(row)).toBe(side1);
    expect(isAnc(row, side1)).toBe(true);
    expect(parents(row.ws, localMain(row))).toEqual([side1]);
    expect(fallbackFailed()).toEqual(["kb-sync-fallback-failed:side_push_rejected"]);
    setHook(row, GH006_HOOK);
    await turn3StacksOn(side1);
  });

  test("PG: protected + held code, the side tip ABSENT from the workspace (re-clone), 3 no-edit turns -> no local growth", async () => {
    row = newRow({ protectedMain: true });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    const side1 = remoteSide(row) as string;
    const ws2 = join(row.root, "ws2");
    execFileSync("git", ["clone", "-q", "--depth", "1", `file://${row.remote}`, ws2], { env: fixtureEnv(row.root), stdio: "pipe" });
    git(ws2, "config", "user.name", "Seeded Local");
    git(ws2, "config", "user.email", "local@example.test");
    row = { ...row, ws: ws2 };
    foreignPlusKb(row, { dirtyCode: false });
    let head = "";
    for (const turn of [1, 2, 3]) {
      resetTurn();
      await run(row);
      if (turn === 1) head = localMain(row);
      expect(subjectOf(row.ws, head)).toBe("Auto-commit after session");
      // D14(4): side_ahead rolls step 4 back, so the local branch is the turn's HEAD every turn (no M_n growth)
      expect(localMain(row), `turn ${turn}: local`).toBe(head);
      expect(remoteSide(row)).toBe(side1);
      expect(heldLines(), `turn ${turn}: outcome`).toEqual(["side_ahead"]);
    }
  });

  test("CQFIX1: protected + held code, three EDITING turns with a 1.1 s clock gap -> the side stacks, no side_ahead", async () => {
    row = newRow({ protectedMain: true });
    const foreign = foreignPlusKb(row);
    const gapBeforeFirstPush = (): void => {
      let delayed = false;
      H.beforeCall = (args) => {
        if (args[0] === "push" && !delayed) {
          delayed = true;
          sleepSync(1100); // S and the side commit fall in different seconds
        }
      };
    };
    gapBeforeFirstPush();
    await run(row);
    const sides = [remoteSide(row) as string];
    expect(sides[0]).toBeTruthy();
    for (const turn of [2, 3]) {
      resetTurn();
      gapBeforeFirstPush();
      write(join(row.ws, "knowledge-base", `t${turn}.md`), `turn ${turn}\n`);
      await run(row);
      const s = remoteSide(row) as string;
      expect(heldWarn("side_ahead"), `turn ${turn}: side_ahead`).toEqual([]);
      expect(s, `turn ${turn}: new side`).not.toBe(sides[sides.length - 1]);
      expect(parents(row.remote, s), `turn ${turn}: side parent`).toEqual([sides[sides.length - 1]]);
      expect(isAnc(row, s), `turn ${turn}: side local`).toBe(true);
      expect(isAnc(row, foreign)).toBe(true);
      expect(onRemote(row, foreign)).toBe(false);
      expect(tracking(row)).toBe(row.T);
      sides.push(s);
    }
    resetTurn();
    H.beforeCall = null;
    await run(row);
    expect(pushesOf()).toEqual([]);
    expect(heldLines()).toEqual(["side_pending"]);
  });

  test("A3: protected + held code, KB edits on turns 2 and 3 with a gap before the main push -> each turn's local is M' = (HEAD, side)", async () => {
    row = newRow({ protectedMain: true });
    const foreign = foreignPlusKb(row);
    H.beforeCall = (args) => {
      if (args[0] === "push" && args.some((a) => a.endsWith(":refs/heads/main"))) sleepSync(1100);
    };
    await run(row);
    let prev = remoteSide(row) as string;
    for (const turn of [2, 3]) {
      resetTurn();
      write(join(row.ws, "knowledge-base", "nested", "b.md"), `b\nturn ${turn}\n`);
      await run(row);
      const side = remoteSide(row) as string;
      expect(parents(row.remote, side), `turn ${turn}`).toEqual([prev]);
      const mPrime = localMain(row);
      const [head, second] = parents(row.ws, mPrime);
      expect(second, `turn ${turn}: M' second parent`).toBe(side);
      expect(subjectOf(row.ws, head)).toBe("Auto-commit after session");
      expect(git(row.ws, "rev-parse", `${mPrime}^{tree}`)).toBe(git(row.ws, "rev-parse", `${head}^{tree}`));
      expect(isAnc(row, foreign)).toBe(true);
      expect(heldLines()).toEqual(["synthetic_pushed"]);
      prev = side;
    }
  });

  test("D14(1): M' fails to build -> nothing is delivered (it is built before the side push) and step 4 is rolled back", async () => {
    row = newRow({ protectedMain: true });
    foreignPlusKb(row);
    let merges = 0;
    H.isoFault = (args) =>
      args.includes("commit-tree") && args.includes(MERGE_MSG) && ++merges === 2 ? { code: -1, stdout: Buffer.alloc(0), stderr: "", timedOut: true } : null;
    const before = localMain(row);
    await run(row);
    expect(merges).toBe(2);
    expect(remoteSide(row)).toBeNull();
    expect(pushesOf().map((r) => r.split(":")[1])).toEqual(["refs/heads/main"]);
    const head = localMain(row);
    expect(parents(row.ws, head)).toEqual([before]);
    expect(subjectOf(row.ws, head)).toBe("Auto-commit after session");
    const outer = H.reportSilentFallback.mock.calls.filter(([, o]) => (o as { op?: string }).op === "syncPush");
    expect((outer[0]?.[1] as { tags?: Record<string, string> }).tags?.reason).toBe("local_git_failed");
    expect(heldLines()).toEqual([]);
  });

  test("D14(5): the link's hand-over fails after the side push -> one held outcome line (unpack_failed), no synthetic_pushed, rolled back", async () => {
    const side1 = await kbOnlyTurn1();
    let packsSeen = 0;
    H.isoFault = (args) => (args[0] === "pack-objects" && ++packsSeen === 2 ? { code: 1, stdout: Buffer.alloc(0), stderr: "", timedOut: false } : null);
    write(join(row.ws, "knowledge-base", "nested", "b.md"), "b\nturn 2\n");
    await run(row);
    expect(remoteSide(row)).not.toBe(side1);
    expect(heldLines()).toEqual(["unpack_failed"]);
    expect(H.createPullRequest).not.toHaveBeenCalled();
    expect(parents(row.ws, localMain(row))).toEqual([side1]);
    expect(subjectOf(row.ws, localMain(row))).toBe("Auto-commit after session");
  });

  test("crash after the step-4 CAS and before the push (protected, side1 present) -> the next turn converges", async () => {
    const side1 = await kbOnlyTurn1();
    // A throw from inside the D push call: the push never runs, nothing after it runs (the state a process crash leaves)
    H.beforeCall = (args) => {
      if (args[0] === "push") throw new Error("crash");
    };
    write(join(row.ws, "knowledge-base", "nested", "b.md"), "b\nturn 2\n");
    await run(row);
    expect(remoteMain(row)).toBe(row.T);
    expect(remoteSide(row)).toBe(side1);
    // D14(3): side1 is an ancestor of HEAD, so step 4 took the M arm and the crash state keeps the side lineage
    const m = localMain(row);
    expect(subjectOf(row.ws, m)).toBe(MERGE_MSG);
    expect(isAnc(row, side1)).toBe(true);
    // the next turn, with no new edit, delivers turn 2's KB and links it
    resetTurn();
    H.beforeCall = null;
    await run(row);
    const side2 = remoteSide(row) as string;
    expect(parents(row.remote, side2)).toEqual([side1]);
    expect(git(row.remote, "show", `${side2}:knowledge-base/nested/b.md`)).toBe("b\nturn 2");
    expect(localMain(row)).toBe(side2);
    expect(heldWarn("side_ahead")).toEqual([]);
    expect(heldLines()).toEqual(["synthetic_pushed"]);
  });

  test("ambiguous transient: the D push lands but the client sees an error -> no rollback, the next turn is a noop", async () => {
    row = newRow();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    H.afterCall = (args) => {
      if (args[0] === "push") throw Object.assign(new Error("reset"), { stderr: "fatal: the remote end hung up unexpectedly\n" });
    };
    await run(row);
    const S = remoteMain(row);
    expect(parents(row.remote, S)).toEqual([row.T]);
    // D14(4): a non-protected D push error leaves localNext (here S itself), never a rollback to HEAD
    expect(localMain(row)).toBe(S);
    const outer = H.reportSilentFallback.mock.calls.filter(([, o]) => (o as { op?: string }).op === "syncPush");
    expect((outer[0]?.[1] as { tags?: Record<string, string> }).tags?.reason).toBe("push_transient");
    resetTurn();
    H.afterCall = null;
    await run(row);
    expect(pushesOf()).toEqual([]);
    expect(H.reportSilentFallback).not.toHaveBeenCalled();
    expect(tracking(row)).toBe(S);
  });
});

// CTO ruling D17: a `side_pending` turn re-checks the side branch's PR with one GET (state=all), so a PR that failed to open
// is opened, an Owner-closed PR for the same head commit stays closed, and a failed GET creates nothing.
describe("D17: the side_pending PR re-check (real git)", { timeout: 60_000 }, () => {
  test("the PR creation fails on turn 1 -> the next no-edit turn creates it (side_pending, commitCount 0)", async () => {
    row = newRow({ protectedMain: true });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    H.createPullRequest.mockImplementationOnce(async () => {
      throw new Error("502");
    });
    await run(row);
    const side = remoteSide(row) as string;
    expect(localMain(row)).toBe(side);
    expect(H.prs).toEqual([]);
    resetTurn();
    await run(row);
    expect(pushesOf()).toEqual([]);
    expect(H.listPullRequestsForHead).toHaveBeenCalledTimes(1);
    expect(H.createPullRequest).toHaveBeenCalledTimes(1);
    expect(H.prs.map((p) => [p.state, p.headSha])).toEqual([["open", side]]);
    expect(heldLines()).toEqual(["side_pending"]);
    const delivered = H.warnSilentFallback.mock.calls.filter(([, o]) => (o as { op?: string }).op === "kb-sync.push-protected-fallback");
    expect((delivered[0]?.[1] as { extra?: Record<string, unknown> }).extra).toEqual(
      expect.objectContaining({ prUrl: "https://github.com/acme/widget/pull/1", commitCount: 0 }),
    );
    // and the turn after that finds the open PR: nothing created again
    resetTurn();
    await run(row);
    expect(H.createPullRequest).not.toHaveBeenCalled();
    expect(heldLines()).toEqual(["side_pending"]);
  });

  test("an Owner-closed (unmerged) PR on the same side tip stays closed: side_declined, info only, nothing created", async () => {
    row = newRow({ protectedMain: true });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    await run(row);
    expect(H.prs).toHaveLength(1);
    H.prs[0].state = "closed";
    resetTurn();
    await run(row);
    expect(H.createPullRequest).not.toHaveBeenCalled();
    expect(pushesOf()).toEqual([]);
    expect(heldLines()).toEqual(["side_declined"]);
    expect(heldWarn("side_declined")).toEqual([]);
    expect(H.warnSilentFallback).not.toHaveBeenCalled();
    expect(H.mirrorWithDebounce).not.toHaveBeenCalled();
    // the next KB edit opens a new PR as today
    resetTurn();
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb 2\n");
    await run(row);
    expect(H.createPullRequest).toHaveBeenCalledTimes(1);
    expect(heldLines()).toEqual(["synthetic_pushed"]);
  });

  test("the PR re-check GET fails -> side_pending and no PR is created (fail toward no duplicate)", async () => {
    row = newRow({ protectedMain: true });
    write(join(row.ws, "knowledge-base", "a.md"), "a\nkb\n");
    H.createPullRequest.mockImplementationOnce(async () => {
      throw new Error("502");
    });
    await run(row);
    resetTurn();
    H.listPullRequestsForHead.mockImplementationOnce(async () => {
      throw new Error("503");
    });
    await run(row);
    expect(H.listPullRequestsForHead).toHaveBeenCalledTimes(1);
    expect(H.createPullRequest).not.toHaveBeenCalled();
    expect(heldLines()).toEqual(["side_pending"]);
    expect(H.mirrorWithDebounce).not.toHaveBeenCalled();
  });
});

// The push / gitWithInstallationAuth census (AC3, D12) is the AST census in test/census-git-push-sites.test.ts.
describe("census (AC4)", () => {
  const SERVER = join(__dirname, "..", "server");
  const code = (p: string): string =>
    existsSync(p) ? readFileSync(p, "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "") : "";
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
