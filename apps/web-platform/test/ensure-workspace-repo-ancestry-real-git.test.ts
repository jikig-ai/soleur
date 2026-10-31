// Real-git coverage for the session-start overlay of ensure-workspace-repo.ts (#11704, ADR-068).
//
// Two properties the mocked rows in ensure-workspace-repo.test.ts cannot establish:
//
//  1. ANCESTRY GATE + RESCUE BRANCH (S1..S4). The workspace clone is `--depth 1` and the store is
//     shallow (receive.shallowUpdate), so a shallow boundary cuts the parent link and
//     `--is-ancestor` exit codes are only meaningful when produced by real git on real shallow
//     repositories. The system under test is the real `ensureWorkspaceRepoCloned`; only the clone
//     (graft) and the authenticated fetch are replaced by real local git (a real `git clone
//     --depth 1` of a fixture origin and a real `git fetch --update-shallow` of a fixture bare
//     store). The overlay's own local git ops (`realLocalGit`) run unmocked.
//
//  2. THE REAL THROWN SHAPE (classifier rows). `isFirstSessionStoreMiss` is proven against the
//     error `gitWithPrivateKeyAuth` really throws when the transport refuses with the bound
//     wrapper's wording, produced by a fake `ssh` first on PATH. A row greps the (bound,
//     read-only) wrapper source for the phrase, so a wording change fails here instead of the
//     classifier silently never matching.
//
// Hermeticity: fixture git calls use `gitFixtureEnv(root)`. The system under test's `realLocalGit`
// inherits `process.env`; the vitest `globalSetup` tripwire (test/global-setup-git-tripwire.ts)
// already aborts a runner that started holding a GIT_* location variable, so no extra scrub is
// needed here. Fixtures are synthesized (cq-test-fixtures-synthesized-only).

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { execFileSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const H = vi.hoisted(() => ({
  WT: "55555555-5555-4555-8555-555555555555",
  fetchImpl: (async (_a: { workspacePath: string }) => {}) as (a: {
    workspacePath: string;
  }) => Promise<void>,
  logInfo: vi.fn(),
  logWarn: vi.fn(),
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/observability", () => ({ reportSilentFallback: H.reportSilentFallback }));
vi.mock("@/server/repo-resolver-divergence", () => ({ reportRepoCloneFailed: vi.fn() }));
vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({
    info: H.logInfo,
    warn: H.logWarn,
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));
vi.mock("@/server/workspace-resolver", () => ({ isGitDataStoreEnabled: () => true }));
vi.mock("@/server/git-data-client", () => ({
  fetchFromGitData: (a: { workspacePath: string }) => H.fetchImpl(a),
}));
vi.mock("@/server/worktree-write-lease", () => ({ resolveWorktreeId: () => H.WT }));
vi.mock("@/server/worktree-config-seed", () => ({ seedWorktreeConfig: vi.fn() }));

import {
  ensureWorkspaceRepoCloned,
  isFirstSessionStoreMiss,
  __setGraftForTests,
} from "@/server/ensure-workspace-repo";
import { gitWithPrivateKeyAuth } from "@/server/git-auth";

const REPO = "https://github.com/acme/widget";
const WS_ID = "11111111-1111-4111-8111-111111111111";
const USER = "77777777-7777-4777-8777-777777777777";
const WRAPPER = resolve(__dirname, "..", "infra", "git-data-transport-wrapper.sh");

let root = "";
let origin = "";
let store = "";
let ws = "";

const git = (cwd: string, args: string[]): string =>
  execFileSync("git", args, { cwd, env: gitFixtureEnv(root), encoding: "utf8" }).trim();

function commit(dir: string, file: string, body: string): string {
  writeFileSync(join(dir, file), body);
  git(dir, ["add", "--", file]);
  git(dir, ["commit", "-q", "-m", `add ${file}`]);
  return git(dir, ["rev-parse", "HEAD"]);
}

const STORE_REFSPEC = `+refs/heads/*:refs/soleur/worktrees/${H.WT}/heads/*`;
const storeHead = (b: string) => `refs/soleur/worktrees/${H.WT}/heads/${b}`;

/** origin (main: C0 <- C1), an EMPTY shallow-accepting bare store. Returns C1. */
function buildBase(): string {
  root = mkdtempSync(join(tmpdir(), "ancestry-real-git-"));
  origin = join(root, "origin");
  store = join(root, "store.git");
  ws = join(root, "workspaces", WS_ID);
  mkdirSync(origin);
  mkdirSync(join(root, "workspaces"));
  git(origin, ["init", "-q", "-b", "main"]);
  commit(origin, "a.txt", "a0\n");
  const c1 = commit(origin, "a.txt", "a1\n");
  git(root, ["init", "-q", "--bare", store]);
  git(store, ["config", "receive.shallowUpdate", "true"]);
  return c1;
}

/** A user clone (depth 1 at the origin tip) that replicates `main` into the store, like a session end. */
function replicate(extraLocalCommit: boolean): string {
  const user = join(root, "user");
  git(root, ["clone", "-q", "--depth", "1", `file://${origin}`, user]);
  const tip = extraLocalCommit ? commit(user, "b.txt", "user work\n") : git(user, ["rev-parse", "HEAD"]);
  git(user, ["push", "-q", "--force", `file://${store}`, STORE_REFSPEC]);
  return tip;
}

function advanceOrigin(): string {
  return commit(origin, "c.txt", "origin moved on\n");
}

let headAfterGraft = "";
async function drive() {
  __setGraftForTests(async (workspacePath) => {
    git(root, ["clone", "-q", "--depth", "1", `file://${origin}`, workspacePath]);
    headAfterGraft = git(workspacePath, ["rev-parse", "HEAD"]);
  });
  H.fetchImpl = async ({ workspacePath }) => {
    git(workspacePath, [
      "fetch",
      "-q",
      "--update-shallow",
      `file://${store}`,
      `+refs/soleur/worktrees/${H.WT}/heads/*:refs/remotes/git-data/*`,
    ]);
  };
  return ensureWorkspaceRepoCloned({
    userId: USER,
    workspacePath: ws,
    installationId: 1,
    repoUrl: REPO,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  headAfterGraft = "";
});
afterEach(() => {
  if (root) rmSync(root, { recursive: true, force: true });
  root = "";
});

describe("overlay ancestry gate on real shallow repositories", () => {
  it("S1 origin unmoved: the store tip descends from the shallow clone tip → HEAD moves to the store tip", async () => {
    buildBase();
    const storeTip = replicate(true);
    const out = await drive();

    expect(out).toBe("ok");
    // self-check: the graft really left HEAD somewhere else, so "HEAD == store tip" proves a reset ran
    expect(headAfterGraft).not.toBe(storeTip);
    expect(git(ws, ["rev-parse", "HEAD"])).toBe(storeTip);
    expect(readFileSync(join(ws, "b.txt"), "utf8")).toBe("user work\n");
    // both sides are genuinely shallow
    expect(git(ws, ["rev-parse", "--is-shallow-repository"])).toBe("true");
    expect(git(store, ["rev-parse", "--is-shallow-repository"])).toBe("true");
    expect(H.logWarn).not.toHaveBeenCalled();
    expect(H.reportSilentFallback).not.toHaveBeenCalled();
    // no rescue branch on the benign path
    expect(git(ws, ["for-each-ref", "refs/heads/soleur/"])).toBe("");
  });

  it("S2 origin advanced: not a descendant → HEAD, tree and store ref unchanged; store tip preserved on the rescue branch", async () => {
    buildBase();
    const storeTip = replicate(true);
    const storeRefBefore = git(store, ["rev-parse", storeHead("main")]);
    const c2 = advanceOrigin();
    const out = await drive();

    expect(out).toBe("ok");
    expect(headAfterGraft).toBe(c2);
    expect(git(ws, ["rev-parse", "HEAD"])).toBe(c2);
    expect(git(ws, ["status", "--porcelain"])).toBe("");
    expect(existsSync(join(ws, "b.txt"))).toBe(false);
    expect(readFileSync(join(ws, "c.txt"), "utf8")).toBe("origin moved on\n");
    // the store is byte-identical
    expect(git(store, ["rev-parse", storeHead("main")])).toBe(storeRefBefore);
    expect(storeRefBefore).toBe(storeTip);
    // the rescue branch exists at the store tip and is not the checked-out branch
    const rescue = `soleur/store-tip-${storeTip.slice(0, 12)}`;
    expect(git(ws, ["rev-parse", `refs/heads/${rescue}`])).toBe(storeTip);
    expect(git(ws, ["rev-parse", "--abbrev-ref", "HEAD"])).toBe("main");
    // one warn with the op token, no fallback to Sentry, no identifiers in any log line
    expect(H.logWarn).toHaveBeenCalledTimes(1);
    expect(H.logWarn.mock.calls[0][0]).toEqual({ op: "git-data-overlay-not-descendant" });
    expect(H.reportSilentFallback).not.toHaveBeenCalled();
    const logged = JSON.stringify([H.logInfo.mock.calls, H.logWarn.mock.calls]);
    expect(logged).not.toContain(USER);
    expect(logged).not.toContain(WS_ID);
    expect(logged).not.toContain(storeTip.slice(0, 12));
  });

  it("S3 store BEHIND the clone (store tip is an ancestor of the shallow clone tip): depth 1 cannot prove it → same skip, also rescued", async () => {
    const c1 = buildBase();
    replicate(false); // store tip == C1, which is C2's parent
    const c2 = advanceOrigin();
    const out = await drive();

    expect(out).toBe("ok");
    expect(git(ws, ["rev-parse", "HEAD"])).toBe(c2);
    expect(git(ws, ["status", "--porcelain"])).toBe("");
    expect(git(ws, ["rev-parse", `refs/heads/soleur/store-tip-${c1.slice(0, 12)}`])).toBe(c1);
    expect(H.logWarn).toHaveBeenCalledTimes(1);
    expect(H.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("S4 the follow-up replication push (force, refs/heads/*) after a skip leaves the old store tip reachable", async () => {
    buildBase();
    const storeTip = replicate(true);
    advanceOrigin();
    await drive();
    const rescueHead = storeHead(`soleur/store-tip-${storeTip.slice(0, 12)}`);

    // before the push the store tip is held by exactly the user's main head
    expect(git(store, ["for-each-ref", "--contains", storeTip, "--format=%(refname)"])).toBe(storeHead("main"));

    // The session-end push, exactly the replication refspec shape, with --force. A first push of
    // 2+ refs from a shallow clone can hit git's `remote failure` / `failed to report status`
    // (measured here: main is forced first, the second ref then fails); git-data-replication.ts
    // therefore resends ONCE on that positive-match class, and so does this row. The rescue ref
    // is the one that lands on the resend; the assertions below read the state after that.
    const push = () => git(ws, ["push", "-q", "--force", `file://${store}`, STORE_REFSPEC]);
    try {
      push();
    } catch (err) {
      const text = String((err as { stderr?: unknown; message?: unknown }).stderr ?? "") +
        String((err as { message?: unknown }).message ?? "");
      if (!/remote failure|failed to report status/.test(text)) throw err;
      push();
    }

    // main was force-overwritten with the clone line ...
    expect(git(store, ["rev-parse", storeHead("main")])).not.toBe(storeTip);
    // ... and the old store tip is still reachable, as a head, so gc cannot reap it
    expect(git(store, ["rev-parse", rescueHead])).toBe(storeTip);
    expect(git(store, ["for-each-ref", "--contains", storeTip, "--format=%(refname)"])).toBe(rescueHead);
    expect(git(store, ["cat-file", "-t", storeTip])).toBe("commit");
  });
});

describe("isFirstSessionStoreMiss against the real thrown shape", () => {
  const PHRASE = "repo does not exist (provision it first)";
  let bin = "";
  let marker = "";
  let savedPath: string | undefined;

  beforeEach(() => {
    savedPath = process.env.PATH;
    root = mkdtempSync(join(tmpdir(), "ancestry-real-shape-"));
    bin = join(root, "bin");
    marker = join(root, "ssh-was-used");
    mkdirSync(bin);
    // A fake `ssh`: answers git's `ssh -G` capability probe, otherwise prints the bound wrapper's
    // refusal exactly as `reject` writes it and exits 1, like a refused forced command.
    writeFileSync(
      join(bin, "ssh"),
      [
        "#!/usr/bin/env bash",
        'for a in "$@"; do [ "$a" = "-G" ] && exit 0; done',
        `printf 'used\\n' >> '${marker}'`,
        `echo "remote: git-data transport: ${PHRASE}: '/mnt/git-data/repositories/${WS_ID}.git'" >&2`,
        "exit 1",
        "",
      ].join("\n"),
    );
    chmodSync(join(bin, "ssh"), 0o755);
    process.env.PATH = `${bin}:${savedPath ?? ""}`;
  });
  afterEach(() => {
    process.env.PATH = savedPath;
  });

  async function realThrown(): Promise<Error & { code?: unknown; stderr?: unknown }> {
    const cwd = join(root, "clone");
    mkdirSync(cwd);
    git(cwd, ["init", "-q", "-b", "main"]);
    try {
      await gitWithPrivateKeyAuth(
        [
          "fetch",
          "--update-shallow",
          `ssh://git@git-data/mnt/git-data/repositories/${WS_ID}.git`,
          `+refs/soleur/worktrees/${H.WT}/heads/*:refs/remotes/git-data/*`,
        ],
        "synthesized-test-key-material",
        makeEd25519Pin(),
        { cwd, timeout: 30_000 },
      );
    } catch (err) {
      return err as Error & { code?: unknown; stderr?: unknown };
    }
    throw new Error("expected the fake transport to refuse the fetch");
  }

  it("the real error is code 128 with the wrapper phrase on stderr, the fake ssh was the transport, and the classifier accepts it", async () => {
    const err = await realThrown();
    expect(existsSync(marker)).toBe(true); // the fake ssh (not a real dial) produced this error
    expect(err.code).toBe(128);
    expect(typeof err.stderr).toBe("string");
    expect(err.stderr as string).toContain(PHRASE);
    expect(isFirstSessionStoreMiss(err)).toBe(true);
  });

  it("variants of the real shape: wrong code, no code, a different 128, phrase only on message", async () => {
    const err = await realThrown();
    const stderr = err.stderr as string;
    const base = { message: err.message, stderr };
    expect(isFirstSessionStoreMiss({ ...base, code: 1 })).toBe(false);
    expect(isFirstSessionStoreMiss({ ...base, code: undefined })).toBe(false);
    expect(isFirstSessionStoreMiss({ ...base, code: "128" })).toBe(false);
    expect(
      isFirstSessionStoreMiss({
        code: 128,
        message: "Command failed: git fetch",
        stderr: "git@git-data: Permission denied (publickey).\nfatal: Could not read from remote repository.",
      }),
    ).toBe(false);
    // stderr only: a classifier that read only `message` would fail this row
    expect(isFirstSessionStoreMiss({ code: 128, message: "Command failed: git fetch", stderr })).toBe(true);
    // message only (no stderr captured)
    expect(isFirstSessionStoreMiss({ code: 128, message: err.message, stderr: "" })).toBe(true);
  });

  it("the bound transport wrapper still emits the phrase the classifier matches (read-only grep)", () => {
    const src = readFileSync(WRAPPER, "utf8");
    expect(src).toMatch(/reject "repo does not exist \(provision it first\): '\$path'"/);
    expect(src).toMatch(/echo "remote: git-data transport: \$1" >&2/);
  });
});
