// Real-git rows for the url/remote rewrite guard at its production call sites (Ref #9601).
//
// `assertNoUrlRewrite` (server/git-data-url-guard.ts) has exactly two production callers: `replicateToGitData`
// (server/git-data-replication.ts, the push) and `fetchFromGitData` (server/git-data-client.ts, the fetch). A third caller
// would not be covered here. Each row plants a carrier in the workspace's own `.git/config` that, without the guard, sends
// the push or fetch to store B (another tenant's repository on the same host) instead of store A (this workspace's own),
// proves that with a control through the same fake transport, then drives the entry point and checks that it refuses
// before any transport call and that neither store moved. The push rows run with and without a local rescue branch,
// because a rescue branch makes replication push twice (the rescue refs, then main) and the guard must precede both.
//
// What these rows do NOT show:
// - The guard is a preflight, not a structural control. A config write between the check and the git call (which, with a
//   rescue branch, spans the whole rescue push) is not covered.
// - The controls run through a local stand-in for the ssh transport (see the helper). Production's transport sets
//   `GIT_ALLOW_PROTOCOL=ssh`, so a `file://` carrier proves the carrier is live under git's URL resolution, not that
//   production would reach a local file. The guard refuses by key name, so that difference does not change a refusal.
// - The local stores carry only `receive.advertisePushOptions`, not the production store's hooks (the pre-receive fence).
// - Include-based carriers (`include.path`, `includeIf`) are covered at the unit level, not at these entry points.
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
import { DRAINING_RECEIVE_PACK, runGitDataLocal } from "./helpers/git-data-local-transport";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const TEST_PIN = makeEd25519Pin();
const WS = "ws-uuid-123";
const WT = "55555555-5555-5555-5555-555555555555";
const USER = "44444444-4444-4444-4444-444444444444";
const RESCUE = "soleur-store-tip-aaaaaaaaaaaa";

let root = "";
const gitTransport = vi.fn();
const sshProvision = vi.fn(async () => Buffer.from(""));
const reportSilentFallback = vi.fn();

vi.mock("@/server/git-auth", () => ({
  gitWithPrivateKeyAuth: (...a: unknown[]) => gitTransport(...a),
  sshWithPrivateKeyAuth: () => sshProvision(),
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
/** Refs and object counts of a repository, so "unchanged" covers both. */
const state = (repo: string): string => {
  const objs = git(repo, ["count-objects", "-v"])
    .split("\n")
    .filter((l) => /^(count|in-pack):/.test(l))
    .join(" ");
  return `${git(repo, ["for-each-ref", "--format=%(objectname) %(refname)"])}\n${objs}`;
};
/** True iff the object exists. Only "missing" (status 1) reads as false; any other git failure throws. */
const hasObject = (repo: string, sha: string): boolean => {
  try {
    git(repo, ["cat-file", "-e", sha]);
    return true;
  } catch (e) {
    if ((e as { status?: number }).status === 1) return false;
    throw e;
  }
};
/** Every op reported, in order: rows assert the exact list, not a filter of it. */
const reportedOps = () => reportSilentFallback.mock.calls.map((c) => (c[1] as { op?: string } | undefined)?.op);
/** Everything a report could carry as text: JSON.stringify drops an Error's message, so read it separately. */
const reportText = () =>
  JSON.stringify(reportSilentFallback.mock.calls) +
  reportSilentFallback.mock.calls.map((c) => (c[0] instanceof Error ? `${c[0].message}\n${c[0].stack}` : "")).join("\n");

let ws = "";
let storeA = "";
let storeB = "";
const gitDataUrl = () => gitDataRemoteUrl(WS);

// the fake transport: the argv production built, through real git, routed onto <root>/stores
const fakeTransport = (args: string[], cwd: string): Buffer =>
  runGitDataLocal(args, { exec: execFileSync, cwd, storesRoot: path.join(root, "stores"), fixtureRoot: root, gitFixtureEnv });
const transportArgvs = () => gitTransport.mock.calls.map((c) => c[0] as string[]);

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

describe("the fake transport's push argv (the F21 fix)", () => {
  // The race this wrapper fixes hit 2 of 1000 serial no-op pushes in planning (plan, Root cause), so deleting the
  // splice would leave F21 green almost every run. This row pins the argv instead.
  const capture = (args: string[]): string[] => {
    let seen: string[] = [];
    const exec = ((_f: string, a: string[]) => {
      seen = a;
      return Buffer.from("");
    }) as unknown as typeof execFileSync;
    runGitDataLocal(args, { exec, cwd: "/nonexistent", storesRoot: "/s", fixtureRoot: "/r", gitFixtureEnv: () => ({}) as NodeJS.ProcessEnv });
    return seen;
  };

  it("UG-FAKE push carries the draining receive-pack once, fetch never does, ssh is off, other shapes are refused", () => {
    const push = capture(["push", "--force", gitDataUrl(), "x:y"]);
    expect(push.filter((a) => a.startsWith("--receive-pack"))).toEqual([`--receive-pack=${DRAINING_RECEIVE_PACK}`]);
    expect(push.slice(0, 4)).toEqual(["-c", "protocol.ssh.allow=never", "-c", expect.stringMatching(/^url\.file:\/\/\/s\/\.insteadOf=/)]);
    const fetch = capture(["fetch", gitDataUrl(), "x:y"]);
    expect(fetch.some((a) => a.startsWith("--receive-pack"))).toBe(false);
    expect(fetch).toContain("protocol.ssh.allow=never");
    expect(() => capture(["ls-remote", gitDataUrl()])).toThrow(/unsupported verb/);
    expect(() => capture(["push", "--receive-pack=git-receive-pack", gitDataUrl()])).toThrow(/remote program/);
    expect(() => capture(["push", "--exec", "x", gitDataUrl()])).toThrow(/remote program/);
    expect(() => capture(["push", "--receiv=x", gitDataUrl()])).toThrow(/remote program/);
    expect(capture(["fetch", "--update-shallow", gitDataUrl(), "x:y"])).toContain("--update-shallow");
  });
});

describe("replicateToGitData — url/remote rewrite carriers, real git (A = own store, B = another tenant)", () => {
  const replicate = () =>
    replicateToGitData({ workspacePath: ws, workspaceId: WS, worktreeId: WT, leaseGeneration: 1, userId: USER });
  // the production argv (git-data-replication.ts builds the same from the same exports)
  const pushOptions = ["--push-option=lease-gen=1", `--push-option=worktree-id=${WT}`];
  const mainPushArgv = () => {
    const r = gitDataPushRefspecs(WT);
    return ["push", "--force", gitDataUrl(), r.heads, r.tags, ...pushOptions];
  };
  const rescuePushArgv = () => ["push", "--force", "--atomic", gitDataUrl(), gitDataPushRefspecs(WT).rescue, ...pushOptions];

  for (const withRescue of [false, true]) {
    const shape = withRescue ? "with a rescue branch (two pushes)" : "no rescue branch (one push)";

    it(`UG-PUSH-0 ${shape}: ordinary origin / upstream remotes and remote.pushDefault are not rewrites, the push lands in A only`, async () => {
      git(ws, ["remote", "add", "origin", "https://example.invalid/o.git"]);
      git(ws, ["remote", "add", "upstream", "https://example.invalid/u.git"]);
      git(ws, ["config", "remote.pushDefault", "upstream"]);
      if (withRescue) git(ws, ["branch", RESCUE]);
      const b0 = state(storeB);

      await expect(replicate()).resolves.toEqual({ status: "replicated" });
      expect(git(storeA, ["rev-parse", storeRef("main")])).toBe(git(ws, ["rev-parse", "main"]));
      expect(transportArgvs()).toEqual(withRescue ? [rescuePushArgv(), mainPushArgv()] : [mainPushArgv()]);
      if (withRescue) expect(git(storeA, ["rev-parse", storeRef(RESCUE)])).toBe(git(ws, ["rev-parse", "main"]));
      expect(state(storeB)).toBe(b0);
      expect(reportedOps()).toEqual([]);
    });
  }

  const carriers = [
    {
      id: "UG-PUSH-1",
      name: "url.<B>.insteadOf <git-data URL>",
      plant: () => git(ws, ["config", `url.file://${storeB}.insteadOf`, gitDataUrl()]),
    },
    {
      id: "UG-PUSH-2",
      name: "[remote \"<git-data URL>\"] pushurl = <B>",
      plant: () => {
        git(ws, ["config", `remote.${gitDataUrl()}.url`, gitDataUrl()]);
        git(ws, ["config", `remote.${gitDataUrl()}.pushurl`, `file://${storeB}`]);
      },
    },
    {
      id: "UG-PUSH-3",
      name: "url.<B>.pushInsteadOf <git-data URL>",
      plant: () => git(ws, ["config", `url.file://${storeB}.pushInsteadOf`, gitDataUrl()]),
    },
  ];

  for (const { id, name, plant } of carriers) {
    for (const withRescue of [false, true]) {
      const shape = withRescue ? "with a rescue branch" : "no rescue branch";
      it(`${id} ${name}, ${shape}: refuses before any transport call, neither store moves, one refused report`, async () => {
        plant();
        // 1. control: the same argv through the same fake, with no guard, lands in B and not in A
        const a0 = state(storeA);
        let controlErr: unknown;
        try {
          fakeTransport(mainPushArgv(), ws);
        } catch (e) {
          controlErr = e;
        }
        expect(controlErr, `control: the push failed (${name})`).toBeUndefined();
        // --verify -q: a ref absent from B is "" (status 1), so the labelled assertion carries a dead carrier
        let inB = "";
        try {
          inB = git(storeB, ["rev-parse", "--verify", "-q", storeRef("main")]);
        } catch (e) {
          if ((e as { status?: number }).status !== 1) throw e;
        }
        expect(inB, `control: the carrier is not live, the push did not land in B (${name})`).toBe(git(ws, ["rev-parse", "main"]));
        expect(state(storeA), "control: the push touched A").toBe(a0);

        // 2. a leaked push would MOVE B's refs: without a new commit it would be a no-op and "B unchanged" vacuous
        git(ws, ["commit", "-q", "--allow-empty", "-m", "after-control"]);
        if (withRescue) git(ws, ["branch", RESCUE]);
        const tip = git(ws, ["rev-parse", "main"]);
        const sA = state(storeA);
        const sB = state(storeB);
        gitTransport.mockClear();
        sshProvision.mockClear();
        reportSilentFallback.mockClear();

        // 3-4. the entry point refuses, in the production order (provision, remote config, guard), before any transport call
        const err = await replicate().catch((e: unknown) => e);
        expect(err).toBeInstanceOf(GitDataUrlRewriteError);
        expect(transportArgvs()).toEqual([]);
        expect(sshProvision).toHaveBeenCalledTimes(1);
        expect(git(ws, ["config", "--get", "remote.git-data.url"])).toBe(gitDataUrl());

        // 5. nothing moved in either store, and the local rescue branch was not consumed
        expect(state(storeA)).toBe(sA);
        expect(state(storeB)).toBe(sB);
        expect(git(storeB, ["rev-parse", storeRef("main")])).not.toBe(tip);
        expect(git(storeB, ["for-each-ref", "--format=%(refname)"])).not.toContain("soleur-store-tip");
        if (withRescue) expect(git(ws, ["rev-parse", RESCUE])).toBe(tip);

        // 6. exactly one report, the refusal, and neither it nor the thrown error carries a path of B
        expect(reportedOps()).toEqual(["git_data_replication_refused"]);
        expect(reportText()).not.toContain(storeB);
        expect(String((err as Error).message)).not.toContain(storeB);
      });
    }
  }
});

describe("fetchFromGitData — url/remote rewrite carriers, real git", () => {
  let evil = "";
  const fetchArgv = () => {
    const r = gitDataFetchRefspecs(WT);
    return ["fetch", "--update-shallow", gitDataUrl(), r.heads, r.negativeRescue, r.tags];
  };
  const gitDataRefs = (repo: string) => git(repo, ["for-each-ref", "--format=%(refname)", "refs/remotes/git-data/"]);
  const fetchHeadExists = (repo: string) => fs.existsSync(path.join(repo, ".git", "FETCH_HEAD"));
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

  it("UG-FETCH-0 no carrier: the fetch lands A's main in refs/remotes/git-data/*", async () => {
    await expect(fetch()).resolves.toBeUndefined();
    expect(transportArgvs()).toEqual([fetchArgv()]);
    expect(git(ws, ["rev-parse", "refs/remotes/git-data/main"])).toBe(git(ws, ["rev-parse", "main"]));
    expect(gitDataRefs(ws)).not.toContain("evil");
    expect(hasObject(ws, evil)).toBe(false);
  });

  const carriers = [
    {
      id: "UG-FETCH-1",
      name: "url.<B>.insteadOf <git-data URL>",
      plant: () => git(ws, ["config", `url.file://${storeB}.insteadOf`, gitDataUrl()]),
      carrierRedirectsFetch: true,
    },
    {
      id: "UG-FETCH-2",
      name: "[remote \"<git-data URL>\"] url = <B>",
      plant: () => git(ws, ["config", `remote.${gitDataUrl()}.url`, `file://${storeB}`]),
      carrierRedirectsFetch: true,
    },
    {
      // Inverted control: pushurl does not redirect a fetch (git 2.56), so the control fetch lands A's main, not B's.
      // If a future git starts honouring it, the control goes red and the change is noticed. The guard still refuses:
      // every URL-shaped remote name is refused.
      id: "UG-FETCH-3",
      name: "[remote \"<git-data URL>\"] pushurl = <B> (inverted control)",
      plant: () => {
        git(ws, ["config", `remote.${gitDataUrl()}.url`, gitDataUrl()]);
        git(ws, ["config", `remote.${gitDataUrl()}.pushurl`, `file://${storeB}`]);
      },
      carrierRedirectsFetch: false,
    },
  ];

  for (const { id, name, plant, carrierRedirectsFetch } of carriers) {
    it(`${id} ${name}: refuses before the fetch, no ref or object of B lands, the workspace is unchanged`, async () => {
      plant();
      // control: the production fetch argv through the same fake, with no guard, in a byte copy of the workspace
      const c = controlCopy();
      fakeTransport(fetchArgv(), c);
      const control = carrierRedirectsFetch ? "control: the carrier is not live" : "inverted control: a pushurl carrier now redirects a fetch";
      expect(gitDataRefs(c).includes("refs/remotes/git-data/evil"), control).toBe(carrierRedirectsFetch);
      expect(hasObject(c, evil), control).toBe(carrierRedirectsFetch);
      if (!carrierRedirectsFetch) {
        expect(git(c, ["rev-parse", "refs/remotes/git-data/main"]), "inverted control: the fetch did not reach A").toBe(
          git(ws, ["rev-parse", "main"]),
        );
      }

      const sA = state(storeA);
      const sB = state(storeB);
      const sWs = state(ws);
      gitTransport.mockClear();
      reportSilentFallback.mockClear();

      const err = await fetch().catch((e: unknown) => e);
      expect(err).toBeInstanceOf(GitDataUrlRewriteError);
      expect(transportArgvs()).toEqual([]);
      expect(gitDataRefs(ws)).toBe("");
      expect(hasObject(ws, evil)).toBe(false);
      expect(state(ws)).toBe(sWs);
      expect(fetchHeadExists(ws)).toBe(false);
      expect(state(storeA)).toBe(sA);
      expect(state(storeB)).toBe(sB);
      expect(String((err as Error).message)).not.toContain(storeB);
      // fetchFromGitData reports nothing itself: its caller (ensure-workspace-repo) owns the refusal report
      expect(reportedOps()).toEqual([]);
    });
  }
});
