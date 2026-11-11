// Real-git rows for the url/remote rewrite guard at its production call sites (Ref #9601).
//
// `assertNoUrlRewrite` (server/git-data-url-guard.ts) has exactly two production callers: `replicateToGitData`
// (server/git-data-replication.ts, the push) and `fetchFromGitData` (server/git-data-client.ts, the fetch). A third caller
// would not be covered here. Each row plants a carrier in the workspace's own `.git/config` that, without the guard, sends
// the push or fetch to store B (another tenant's repository on the same host) instead of store A (this workspace's own),
// proves that with a control through the same fake transport, then drives the entry point and checks that it refuses
// before any transport call and that neither store moved.
//
// What these rows do NOT show: the guard is a preflight, not a structural control. A config write between the check and
// the git call is not covered, and the transport here is a local stand-in for the ssh path (see the helper).
//
// child_process is NOT mocked: the guard, `ensureGitDataRemote` and the rescue listing run real git with the production
// host-git environment. Only the authenticated transport (`gitWithPrivateKeyAuth`) is replaced, by the shared fake that
// runs the production argv against local bare stores.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";
import { runGitDataLocal } from "./helpers/git-data-local-transport";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const TEST_PIN = makeEd25519Pin();
const WS = "ws-uuid-123";
const WT = "55555555-5555-5555-5555-555555555555";
const USER = "44444444-4444-4444-4444-444444444444";

let root = "";
const gitTransport = vi.fn();
const sshProvision = vi.fn(async () => Buffer.from(""));
const reportSilentFallback = vi.fn();

vi.mock("@/server/git-auth", () => ({
  gitWithPrivateKeyAuth: (...a: unknown[]) => gitTransport(...a),
  sshWithPrivateKeyAuth: (...a: unknown[]) => sshProvision(...(a as [])),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: vi.fn(async () => ({ data: true, error: null })) })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
// Partial: hashUserId and warnSilentFallback stay real.
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: (...a: unknown[]) => reportSilentFallback(...a),
}));

import { replicateToGitData, gitDataRemoteUrl, gitDataPushRefspecs } from "@/server/git-data-replication";
import { fetchFromGitData, gitDataFetchRefspecs } from "@/server/git-data-client";
import { GitDataUrlRewriteError } from "@/server/git-data-url-guard";

const git = (cwd: string, args: string[]): string =>
  execFileSync("git", args, { cwd, env: gitFixtureEnv(root), encoding: "utf8", stdio: "pipe" }).trim();
const storeRef = (b: string) => `refs/soleur/worktrees/${WT}/heads/${b}`;
/** Refs and object counts of a bare store, so "unchanged" covers both. */
const state = (bare: string): string => {
  const objs = git(bare, ["count-objects", "-v"])
    .split("\n")
    .filter((l) => /^(count|in-pack):/.test(l))
    .join(" ");
  return `${git(bare, ["for-each-ref", "--format=%(objectname) %(refname)"])}\n${objs}`;
};
const hasObject = (repo: string, sha: string): boolean => {
  try {
    git(repo, ["cat-file", "-e", `${sha}^{commit}`]);
    return true;
  } catch {
    return false;
  }
};

let ws = "";
let storeA = "";
let storeB = "";
const URL_ = () => gitDataRemoteUrl(WS);

// the fake transport: the argv production built, through real git, routed onto <root>/stores
const fakeTransport = (args: string[], cwd: string): Buffer =>
  runGitDataLocal(args, { exec: execFileSync, cwd, storesRoot: path.join(root, "stores"), fixtureRoot: root, gitFixtureEnv });

beforeEach(() => {
  vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
  vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", "transport-key");
  vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "provision-key");
  vi.stubEnv("GIT_DATA_SSH_HOST_KEY", TEST_PIN);
  vi.stubEnv("GIT_DATA_SSH_HOST", ""); // the non-prod default URL
  gitTransport.mockReset().mockImplementation(async (...a: unknown[]) => {
    const [args, , , opts] = a as [string[], string, string, { cwd: string }];
    return fakeTransport(args, opts.cwd);
  });
  sshProvision.mockClear();
  reportSilentFallback.mockClear();

  root = fs.mkdtempSync(path.join(os.tmpdir(), "url-guard-entry-"));
  fs.mkdirSync(path.join(root, "stores"));
  fs.mkdirSync(path.join(root, "other"));
  storeA = path.join(root, "stores", `${WS}.git`);
  storeB = path.join(root, "other", "b.git");
  for (const s of [storeA, storeB]) {
    git(root, ["init", "-q", "--bare", s]);
    git(s, ["config", "receive.advertisePushOptions", "true"]);
  }
  ws = path.join(root, "ws");
  fs.mkdirSync(ws);
  git(ws, ["init", "-q", "-b", "main"]);
  fs.writeFileSync(path.join(ws, "a.txt"), "a\n");
  git(ws, ["add", "--", "a.txt"]);
  git(ws, ["commit", "-q", "-m", "a"]);
});

afterEach(() => {
  vi.unstubAllEnvs();
  fs.rmSync(root, { recursive: true, force: true });
});

const refusedReports = () =>
  reportSilentFallback.mock.calls.filter((c) => (c[1] as { op?: string }).op === "git_data_replication_refused");
const pushReports = () =>
  reportSilentFallback.mock.calls.filter((c) => (c[1] as { op?: string }).op === "git_data_replication_push");

describe("replicateToGitData — url/remote rewrite carriers, real git (A = own store, B = another tenant)", () => {
  const replicate = () =>
    replicateToGitData({ workspacePath: ws, workspaceId: WS, worktreeId: WT, leaseGeneration: 1, userId: USER });
  // the production step-2 argv (git-data-replication.ts builds the same from the same exports)
  const mainPushArgv = () => {
    const r = gitDataPushRefspecs(WT);
    return ["push", "--force", URL_(), r.heads, r.tags, "--push-option=lease-gen=1", `--push-option=worktree-id=${WT}`];
  };

  it("R-PUSH-0 ordinary origin / upstream remotes and remote.pushDefault are not rewrites: the push lands in A only", async () => {
    git(ws, ["remote", "add", "origin", "https://example.invalid/o.git"]);
    git(ws, ["remote", "add", "upstream", "https://example.invalid/u.git"]);
    git(ws, ["config", "remote.pushDefault", "upstream"]);
    const b0 = state(storeB);

    await expect(replicate()).resolves.toEqual({ status: "replicated" });
    expect(git(storeA, ["rev-parse", storeRef("main")])).toBe(git(ws, ["rev-parse", "main"]));
    expect(state(storeB)).toBe(b0);
    expect(gitTransport).toHaveBeenCalledTimes(1);
    expect(refusedReports()).toHaveLength(0);
  });

  it.each([
    {
      name: "R-PUSH-1 url.<B>.insteadOf <git-data URL>",
      control: "control: the insteadOf carrier is not live",
      plant: () => git(ws, ["config", `url.file://${storeB}.insteadOf`, URL_()]),
    },
    {
      name: "R-PUSH-2 [remote \"<git-data URL>\"] pushurl = <B>",
      control: "control: the remote-name carrier is not live",
      plant: () => {
        git(ws, ["config", `remote.${URL_()}.url`, URL_()]);
        git(ws, ["config", `remote.${URL_()}.pushurl`, `file://${storeB}`]);
      },
    },
  ])("$name: refuses before any transport call, neither store moves, one refused report", async ({ control, plant }) => {
    plant();
    // 1. control: the same argv through the same fake, with no guard, lands in B and not in A
    const a0 = state(storeA);
    let landedInB = "";
    try {
      fakeTransport(mainPushArgv(), ws);
      landedInB = git(storeB, ["rev-parse", storeRef("main")]);
    } catch {
      landedInB = "";
    }
    expect(landedInB, control).toBe(git(ws, ["rev-parse", "main"]));
    expect(state(storeA), control).toBe(a0);

    // 2. a leaked push would MOVE B's ref again: without a new commit it would be a no-op and "B unchanged" vacuous
    git(ws, ["commit", "-q", "--allow-empty", "-m", "after-control"]);
    const tip = git(ws, ["rev-parse", "main"]);
    const sA = state(storeA);
    const sB = state(storeB);
    gitTransport.mockClear();
    sshProvision.mockClear();
    reportSilentFallback.mockClear();

    // 3-4. the entry point refuses, in the production order (provision, remote config, guard), before any transport call
    const err = await replicate().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(GitDataUrlRewriteError);
    expect(gitTransport).toHaveBeenCalledTimes(0);
    expect(sshProvision).toHaveBeenCalledTimes(1);
    expect(git(ws, ["config", "--get", "remote.git-data.url"])).toBe(URL_());

    // 5. nothing moved in either store
    expect(state(storeA)).toBe(sA);
    expect(state(storeB)).toBe(sB);
    expect(git(storeB, ["rev-parse", storeRef("main")])).not.toBe(tip);

    // 6. exactly one refused report, no push report, and the report carries no path of B
    expect(refusedReports()).toHaveLength(1);
    expect(pushReports()).toHaveLength(0);
    expect(JSON.stringify(reportSilentFallback.mock.calls)).not.toContain(storeB);
  });
});

describe("fetchFromGitData — url/remote rewrite carriers, real git", () => {
  let evil = "";
  const fetchArgv = () => {
    const r = gitDataFetchRefspecs(WT);
    return ["fetch", "--update-shallow", URL_(), r.heads, r.negativeRescue, r.tags];
  };
  const gitDataRefs = (repo: string) => git(repo, ["for-each-ref", "--format=%(refname)", "refs/remotes/git-data/"]);
  const fetch = () => fetchFromGitData({ userId: USER, workspaceId: WS, worktreeId: WT, workspacePath: ws });
  /** A byte copy of the workspace (same config, same carrier) for the control, so the workspace never holds B's objects. */
  const controlCopy = (): string => {
    const c = path.join(root, "ws-control");
    fs.cpSync(ws, c, { recursive: true });
    return c;
  };

  beforeEach(() => {
    // A holds this workspace's main; B holds a commit that exists only in B
    git(ws, ["push", "-q", `file://${storeA}`, `refs/heads/main:${storeRef("main")}`]);
    const bsrc = path.join(root, "bsrc");
    fs.mkdirSync(bsrc);
    git(bsrc, ["init", "-q", "-b", "main"]);
    fs.writeFileSync(path.join(bsrc, "evil.txt"), "b only\n");
    git(bsrc, ["add", "--", "evil.txt"]);
    git(bsrc, ["commit", "-q", "-m", "b only"]);
    evil = git(bsrc, ["rev-parse", "HEAD"]);
    git(bsrc, ["push", "-q", `file://${storeB}`, `refs/heads/main:${storeRef("evil")}`]);
    expect(hasObject(ws, evil)).toBe(false);
  });

  it("R-FETCH-0 no carrier: the fetch lands A's main in refs/remotes/git-data/*", async () => {
    await expect(fetch()).resolves.toBeUndefined();
    expect(gitTransport).toHaveBeenCalledTimes(1);
    expect(git(ws, ["rev-parse", "refs/remotes/git-data/main"])).toBe(git(ws, ["rev-parse", "main"]));
    expect(gitDataRefs(ws)).not.toContain("evil");
  });

  it.each([
    {
      name: "R-FETCH-1 url.<B>.insteadOf <git-data URL>",
      control: "control: the insteadOf carrier is not live",
      plant: () => git(ws, ["config", `url.file://${storeB}.insteadOf`, URL_()]),
      carrierRedirectsFetch: true,
    },
    {
      name: "R-FETCH-2 [remote \"<git-data URL>\"] url = <B>",
      control: "control: the remote-name carrier is not live",
      plant: () => git(ws, ["config", `remote.${URL_()}.url`, `file://${storeB}`]),
      carrierRedirectsFetch: true,
    },
    {
      // Inverted control: pushurl does not redirect a fetch (git 2.56). If a future git starts honouring it, the control
      // goes red and the change is noticed. The guard still refuses: every URL-shaped remote name is refused.
      name: "R-FETCH-3 [remote \"<git-data URL>\"] pushurl = <B> (inverted control)",
      control: "inverted control: a pushurl carrier now redirects a fetch",
      plant: () => {
        git(ws, ["config", `remote.${URL_()}.url`, URL_()]);
        git(ws, ["config", `remote.${URL_()}.pushurl`, `file://${storeB}`]);
      },
      carrierRedirectsFetch: false,
    },
  ])("$name: refuses before the fetch, no ref or object of B lands", async ({ control, plant, carrierRedirectsFetch }) => {
    plant();
    // control: the production fetch argv through the same fake, with no guard, in a byte copy of the workspace
    const c = controlCopy();
    fakeTransport(fetchArgv(), c);
    expect(gitDataRefs(c).includes(`refs/remotes/git-data/evil`), control).toBe(carrierRedirectsFetch);
    expect(hasObject(c, evil), control).toBe(carrierRedirectsFetch);

    const sA = state(storeA);
    const sB = state(storeB);
    gitTransport.mockClear();
    reportSilentFallback.mockClear();

    const err = await fetch().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(GitDataUrlRewriteError);
    expect(gitTransport).toHaveBeenCalledTimes(0);
    expect(gitDataRefs(ws)).toBe("");
    expect(hasObject(ws, evil)).toBe(false);
    expect(state(storeA)).toBe(sA);
    expect(state(storeB)).toBe(sB);
    // fetchFromGitData reports nothing itself: its caller (ensure-workspace-repo) owns the refusal report
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });
});
