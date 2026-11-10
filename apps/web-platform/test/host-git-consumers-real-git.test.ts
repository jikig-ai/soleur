// Real-git battery for the host-side git consumers (Ref #9601; follow-on to the git-read hardening).
//
// Host-side git runs OUTSIDE the agent sandbox, with the server's process environment, in a workspace whose
// `.git` an agent session can author. Every row here plants an agent-authorable carrier, drives the REAL code
// path of one consumer and asserts EFFECTS:
//   A1  no closable carrier ran (canary file untouched; a foreign worktree is not staged, committed or overwritten);
//   A2  the server-only sentinel is absent from the OWN environment of every helper that did run (this says nothing
//       about a helper that reads the server's /proc environ: any carrier that executes is a same-uid compromise);
//   A3  the consumer's own operation still succeeded.
// `RESIDUAL` rows pin what is NOT closed. They are measured open items, not controls: a change in either
// direction fails them on purpose.
//
// No `child_process` mock anywhere in this file. Fixtures are synthesized (cq-test-fixtures-synthesized-only).
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  PLANTERS,
  SENTINEL_VAR,
  assertGitFloor,
  dirty,
  newWorkspace,
  newWorld,
  plant,
  planterById,
  type Planter,
  type World,
} from "./helpers/host-git-carrier-fixture";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";

const H = vi.hoisted(() => ({
  WT: "55555555-5555-4555-8555-555555555555",
  fetchImpl: (async (_a: { workspacePath: string }) => {}) as (a: { workspacePath: string }) => Promise<void>,
  reportSilentFallback: vi.fn(),
  logWarn: vi.fn(),
  keepProductionProtocol: false,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: H.reportSilentFallback,
  warnSilentFallback: vi.fn(),
  hashUserId: (x: string) => `h-${x}`,
}));
vi.mock("@/server/logger", () => ({
  createChildLogger: () => ({ info: vi.fn(), warn: H.logWarn, error: vi.fn(), debug: vi.fn() }),
}));
vi.mock("@/server/repo-resolver-divergence", () => ({ reportRepoCloneFailed: vi.fn() }));
vi.mock("@/server/workspace-resolver", () => ({
  isGitDataStoreEnabled: () => true,
  workspacePathForWorkspaceId: (id: string) => `/clones/${id}`,
}));
vi.mock("@/server/git-data-client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/git-data-client")>()),
  fetchFromGitData: (a: { workspacePath: string }) => H.fetchImpl(a),
}));
vi.mock("@/server/worktree-write-lease", () => ({ resolveWorktreeId: () => H.WT, assertSafeWorktreeId: () => {} }));
vi.mock("@/server/worktree-config-seed", () => ({ seedWorktreeConfig: vi.fn() }));
vi.mock("@/server/workspace-permission-lock", () => ({
  withWorkspacePermissionLock: (_p: string, fn: () => Promise<unknown>) => fn(),
}));
vi.mock("@/server/workspace-repo-mirror", () => ({ writeRepoColsToWorkspace: vi.fn() }));
vi.mock("@/server/resolve-installation-id", () => ({ resolveInstallationId: async () => null }));
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: async () => `ghs_${"a".repeat(36)}`,
}));
const { FakeRuntimeAuthError } = vi.hoisted(() => ({
  FakeRuntimeAuthError: class FakeRuntimeAuthError extends Error {},
}));
vi.mock("@/lib/supabase/tenant", () => {
  const chain = { maybeSingle: async () => ({ data: { id: "u" }, error: null }) };
  return {
    RuntimeAuthError: FakeRuntimeAuthError,
    getFreshTenantClient: async () => ({ from: () => ({ select: () => ({ eq: () => chain }) }) }),
  };
});

// Fixtures use a local file:// remote while production pins https / ssh. Widen through the helper's OWN parameter
// (`allowProtocol`), never a separate seam; the uploadpack rows keep the production value on purpose.
vi.mock("@/server/host-git", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/host-git")>();
  return {
    ...actual,
    hostGitInvocation: (args: readonly string[], opts: import("@/server/host-git").HostGitOpts) =>
      actual.hostGitInvocation(args, {
        ...opts,
        allowProtocol: H.keepProductionProtocol ? opts.allowProtocol : `${opts.allowProtocol}:file`,
      }),
  };
});

import { syncPush } from "@/server/session-sync";
import { ensureWorkspaceRepoCloned, __setGraftForTests } from "@/server/ensure-workspace-repo";
import { gitWithInstallationAuth, gitWithPrivateKeyAuth, KEY_AUTH_ALLOW_PROTOCOL, LEGACY_ALLOW_PROTOCOL } from "@/server/git-auth";
import { ALLOW_PROTOCOL_NONE, hostGitInvocation } from "@/server/host-git";
import { assertNoUrlRewrite, GitDataUrlRewriteError } from "@/server/git-data-url-guard";
import { ensureGitDataRemote } from "@/server/git-data-replication";
import { checkpointInflightWork, checkpointRefName } from "@/server/inflight-checkpoint";
import { gitDataFetchRefspecs } from "@/server/git-data-client";
import { gitDataPushRefspecs } from "@/server/git-data-replication";

const USER = "77777777-7777-4777-8777-777777777777";
const WS_ID = "11111111-1111-4111-8111-111111111111";
const CONV = "99999999-9999-4999-8999-999999999999";
const REPO = "https://github.com/acme/widget";
const SENTINEL = `SENTINEL-${Math.random().toString(36).slice(2)}`;

let gitVersion = "";
let w: World;
const saved: Record<string, string | undefined> = {};

beforeAll(() => {
  gitVersion = assertGitFloor(); // THROWS below the floor: never a skip
});

beforeEach(() => {
  vi.clearAllMocks();
  // Module-level state a row can leave behind: reset so a row never depends on which row ran before it.
  H.keepProductionProtocol = false;
  H.fetchImpl = async () => {};
  currentPlanters = [];
  saved[SENTINEL_VAR] = process.env[SENTINEL_VAR];
  process.env[SENTINEL_VAR] = SENTINEL;
  w = newWorld();
});
afterEach(() => {
  if (saved[SENTINEL_VAR] === undefined) delete process.env[SENTINEL_VAR];
  else process.env[SENTINEL_VAR] = saved[SENTINEL_VAR];
  w.cleanup();
});

// ---------------------------------------------------------------------------------------------------------------
// Drivers: the REAL code path of each consumer. `closable`/`residual` name the planter ids each driver is run with.
// ---------------------------------------------------------------------------------------------------------------
interface Ctx {
  ws: string;
  upstream: string;
  storeTip?: string;
  note?: string;
}
interface Driver {
  id: string;
  /** Planters that must stay silent on this driver's verbs. */
  closable: string[];
  /** Planters whose helper is expected to RUN on this driver's verbs (measured open items). */
  residual: string[];
  /** Planters that redirect the git directory (`commondir`): the call is REFUSED before git runs. */
  refused: string[];
  /** After a refused call: the consumer's operation must have had no effect. */
  refusedCheck?(c: Ctx): void;
  /** Planters measured as already inert on today's code: control / regression pin, excluded from RED. */
  preexistingControl?: string[];
  prepare(): Promise<Ctx>;
  /** Called after the carrier is planted. */
  run(c: Ctx): Promise<void>;
  /** A3: the consumer's own operation succeeded. */
  verify(c: Ctx): void;
  /** A planter that makes the operation itself unable to succeed on purpose (skip A3). */
  skipVerify?: string[];
}

const syncPushDriver: Driver = {
  id: "session-sync syncPush",
  closable: [
    "fsmonitor-in-git-config",
    "fsmonitor-in-config-worktree",
    "hook-pre-commit",
    "hook-reference-transaction",
    "signing-program",
    "core-worktree-foreign",
  ],
  residual: ["filter-via-git-config", "filter-via-info-attributes"],
  refused: ["fsmonitor-via-commondir", "filter-via-commondir"],
  refusedCheck(c) {
    expect(w.git(c.ws, "-c", "core.fsmonitor=false", "log", "-1", "--format=%s")).not.toBe("Auto-commit after session");
  },
  async prepare() {
    const { ws, upstream } = newWorkspace(w);
    dirty(ws);
    return { ws, upstream };
  },
  async run(c) {
    await syncPush(USER, c.ws, {} as never, WS_ID);
  },
  verify(c) {
    const log = w.git(c.ws, "-c", "core.fsmonitor=false", "log", "-1", "--format=%an|%s");
    expect(log).toBe("Seeded Local|Auto-commit after session");
  },
};

const overlayDriver: Driver = {
  id: "ensure-workspace-repo overlay",
  closable: ["fsmonitor-in-git-config", "fsmonitor-in-config-worktree", "hook-reference-transaction", "core-worktree-foreign"],
  residual: [],
  refused: ["fsmonitor-via-commondir"],
  refusedCheck(c) {
    expect(w.git(c.ws, "-c", "core.fsmonitor=false", "rev-parse", "HEAD")).not.toBe(c.storeTip);
  },
  async prepare() {
    const origin = join(w.root, "origin");
    const store = join(w.root, "store.git");
    mkdirSync(origin);
    w.git(origin, "init", "-q", "-b", "main");
    w.git(origin, "config", "user.name", "O");
    w.git(origin, "config", "user.email", "o@example.invalid");
    writeFileSync(join(origin, "a.txt"), "a0\n");
    w.git(origin, "add", "--", "a.txt");
    w.git(origin, "commit", "-q", "-m", "c0");
    writeFileSync(join(origin, "a.txt"), "a1\n");
    w.git(origin, "commit", "-q", "-am", "c1");
    w.git(w.root, "init", "-q", "--bare", store);
    w.git(store, "config", "receive.shallowUpdate", "true");
    const user = join(w.root, "user");
    w.git(w.root, "clone", "-q", "--depth", "1", `file://${origin}`, user);
    w.git(user, "config", "user.name", "U");
    w.git(user, "config", "user.email", "u@example.invalid");
    writeFileSync(join(user, "b.txt"), "user work\n");
    w.git(user, "add", "--", "b.txt");
    w.git(user, "commit", "-q", "-m", "user");
    const storeTip = w.git(user, "rev-parse", "HEAD");
    w.git(user, "push", "-q", "--force", `file://${store}`, gitDataPushRefspecs(H.WT).heads);
    const ws = join(w.root, "workspaces", WS_ID);
    mkdirSync(join(w.root, "workspaces"));
    H.fetchImpl = async ({ workspacePath }) => {
      const fetch = gitDataFetchRefspecs(H.WT);
      // The fixture's OWN fetch runs after the carrier is planted: keep it from tripping the carrier itself.
      w.git(workspacePath, "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "fetch", "-q", "--update-shallow", `file://${store}`, fetch.heads, fetch.negativeRescue, fetch.tags);
    };
    return { ws, upstream: origin, storeTip, note: origin };
  },
  async run(c) {
    // the planter runs after the graft, inside the overlay's own sequence
    const planters = currentPlanters;
    __setGraftForTests(async (workspacePath: string) => {
      w.git(w.root, "clone", "-q", "--depth", "1", `file://${c.note}`, workspacePath);
      w.git(workspacePath, "config", "user.name", "Seeded Local");
      w.git(workspacePath, "config", "user.email", "seeded-local@example.invalid");
      for (const p of planters) plant(p, workspacePath, w);
    });
    await ensureWorkspaceRepoCloned({ userId: USER, workspacePath: c.ws, installationId: 1, repoUrl: REPO });
  },
  verify(c) {
    expect(w.git(c.ws, "-c", "core.fsmonitor=false", "rev-parse", "HEAD")).toBe(c.storeTip);
  },
};

const keyAuthPushDriver: Driver = {
  id: "git-data gitWithPrivateKeyAuth push",
  closable: ["hook-pre-push", "uploadpack-local-remote", "core-worktree-foreign"],
  residual: [],
  refused: ["fsmonitor-via-commondir"],
  refusedCheck(c) {
    // the push did not happen: the upstream is still behind the local commit
    expect(w.git(c.upstream, "rev-parse", "main")).not.toBe(w.git(c.ws, "-c", "core.fsmonitor=false", "rev-parse", "HEAD"));
  },
  async prepare() {
    const { ws, upstream } = newWorkspace(w);
    writeFileSync(join(ws, "knowledge-base", "more.md"), "more\n");
    w.git(ws, "add", "--", "knowledge-base/more.md");
    w.git(ws, "commit", "-q", "-m", "ahead");
    return { ws, upstream };
  },
  async run(c) {
    const pin = makeEd25519Pin();
    const key = "-----BEGIN OPENSSH PRIVATE KEY-----\nZmFrZQ==\n-----END OPENSSH PRIVATE KEY-----";
    await gitWithPrivateKeyAuth(["push", "origin", "main"], key, pin, { cwd: c.ws, timeout: 30_000 }).catch(() => {});
    // the fetch verb carries uploadpack
    await gitWithPrivateKeyAuth(["fetch", "origin"], key, pin, { cwd: c.ws, timeout: 30_000 }).catch(() => {});
  },
  verify(c) {
    expect(w.git(c.upstream, "rev-parse", "main")).toBe(w.git(c.ws, "-c", "core.fsmonitor=false", "rev-parse", "HEAD"));
  },
  skipVerify: ["uploadpack-local-remote"],
};

const legacyPullDriver: Driver = {
  id: "git-auth legacy gitWithInstallationAuth pull",
  closable: [
    "fsmonitor-in-git-config",
    "fsmonitor-in-config-worktree",
    "hook-reference-transaction",
    "uploadpack-local-remote",
    "core-worktree-foreign",
  ],
  residual: [],
  refused: ["fsmonitor-via-commondir"],
  refusedCheck(c) {
    expect(w.git(c.ws, "-c", "core.fsmonitor=false", "rev-parse", "HEAD")).not.toBe(c.storeTip);
  },
  async prepare() {
    const { ws, upstream } = newWorkspace(w);
    const other = join(w.root, "other");
    w.git(w.root, "clone", "-q", `file://${upstream}`, other);
    w.git(other, "config", "user.name", "O");
    w.git(other, "config", "user.email", "o@example.invalid");
    writeFileSync(join(other, "knowledge-base", "up.md"), "up\n");
    w.git(other, "add", "--", "knowledge-base/up.md");
    w.git(other, "commit", "-q", "-m", "upstream moves");
    w.git(other, "push", "-q", "origin", "main");
    return { ws, upstream, storeTip: w.git(upstream, "rev-parse", "main") };
  },
  async run(c) {
    await gitWithInstallationAuth(["pull", "--no-rebase", "origin", "main"], 1, { cwd: c.ws, timeout: 30_000 }).catch(() => {});
  },
  verify(c) {
    expect(w.git(c.ws, "-c", "core.fsmonitor=false", "rev-parse", "HEAD")).toBe(c.storeTip);
  },
  skipVerify: ["uploadpack-local-remote"],
};

const checkpointDriver: Driver = {
  id: "inflight-checkpoint checkpointInflightWork",
  closable: ["fsmonitor-in-git-config", "fsmonitor-in-config-worktree", "hook-reference-transaction", "core-worktree-foreign"],
  residual: ["filter-via-git-config", "filter-via-info-attributes"],
  refused: ["fsmonitor-via-commondir", "filter-via-commondir"],
  refusedCheck(c) {
    expect(() => w.git(c.ws, "-c", "core.fsmonitor=false", "rev-parse", "--verify", checkpointRefName(CONV))).toThrow();
  },
  // the shared hardening set already closes these on today's code: control / regression pin
  preexistingControl: ["fsmonitor-in-git-config", "fsmonitor-in-config-worktree"],
  async prepare() {
    const { ws, upstream } = newWorkspace(w);
    dirty(ws);
    return { ws, upstream };
  },
  async run(c) {
    await checkpointInflightWork(c.ws, CONV, USER);
  },
  verify(c) {
    expect(w.git(c.ws, "-c", "core.fsmonitor=false", "rev-parse", "--verify", checkpointRefName(CONV))).toMatch(/^[0-9a-f]{40}/);
  },
};

const DRIVERS: Driver[] = [syncPushDriver, overlayDriver, keyAuthPushDriver, legacyPullDriver, checkpointDriver];

let currentPlanters: Planter[] = [];

async function runCell(d: Driver, p: Planter, tolerate = false): Promise<{ tags: string[]; ctx: Ctx }> {
  H.keepProductionProtocol = p.id === "uploadpack-local-remote";
  const ctx = await d.prepare();
  currentPlanters = [p];
  if (d !== overlayDriver) plant(p, ctx.ws, w);
  // a refused call may surface as a rejection (the consumer's own handling differs); the evidence is the effect
  if (tolerate) await d.run(ctx).catch(() => {});
  else await d.run(ctx);
  return { tags: w.tags(), ctx };
}

// ---------------------------------------------------------------------------------------------------------------
// Twin control: each carrier type runs ONCE under raw git and must fire. A carrier that cannot fire on this git
// fails every row that uses it as "carrier not live" instead of passing vacuously.
// ---------------------------------------------------------------------------------------------------------------
const twinCache = new Map<string, boolean>();

function rawTwin(p: Planter): boolean {
  const hit = twinCache.get(p.id);
  if (hit !== undefined) return hit;
  const tw = newWorld("host-git-twin-");
  try {
    const { ws } = newWorkspace(tw, "twin");
    plant(p, ws, tw);
    const run = (...a: string[]) => {
      try {
        tw.git(ws, ...a);
      } catch {
        /* a carrier may also make the verb fail; the canary is the evidence */
      }
    };
    switch (p.id) {
      case "hook-pre-push":
        run("commit", "-q", "--allow-empty", "-m", "x");
        run("push", "origin", "main");
        break;
      case "uploadpack-local-remote":
        run("fetch", "origin");
        break;
      case "core-worktree-foreign": {
        run("status", "--porcelain");
        const out = (() => {
          try {
            return tw.git(ws, "status", "--porcelain");
          } catch {
            return "";
          }
        })();
        twinCache.set(p.id, /n\.md/.test(out));
        return twinCache.get(p.id)!;
      }
      case "filter-via-git-config":
      case "filter-via-info-attributes":
      case "filter-via-commondir":
        dirty(ws);
        run("add", "--", "knowledge-base/note.md");
        break;
      case "signing-program":
      case "hook-pre-commit":
      case "hook-reference-transaction":
        dirty(ws);
        run("add", "--", "knowledge-base/note.md");
        run("commit", "-q", "-m", "x");
        break;
      default:
        run("status", "--porcelain");
        run("reset", "--hard");
    }
    const fired = tw.tags().includes(p.tag);
    twinCache.set(p.id, fired);
    return fired;
  } finally {
    tw.cleanup();
  }
}

/** The foreign tenant's file must not have been staged into, or the workspace's own file dropped from, the commit. */
function headTreeIntact(ws: string): void {
  const tree = w.git(ws, "-c", "core.fsmonitor=false", "ls-tree", "-r", "--name-only", "HEAD").split("\n");
  expect(tree).toContain("knowledge-base/base.md");
  expect(tree).not.toContain("knowledge-base/n.md");
}

function victimUntouched(): void {
  // recursive: a new file written UNDER the foreign tenant's tree must fail the row too
  expect((readdirSync(w.victim, { recursive: true }) as string[]).sort()).toEqual(["knowledge-base", "knowledge-base/n.md", "victim.txt"]);
  expect(readFileSync(join(w.victim, "victim.txt"), "utf8")).toBe("foreign tenant content\n");
  expect(readFileSync(join(w.victim, "knowledge-base", "n.md"), "utf8")).toBe("foreign tenant note\n");
}

let canaryCheckedRuns = 0;
let residualRows = 0;

describe("git floor", () => {
  it("the host git meets the 2.38 floor (the suite's beforeAll throws below it)", () => {
    expect(gitVersion).toMatch(/git version/);
  });
});

describe("closable carriers stay silent on every consumer (A1, A2, A3)", () => {
  for (const d of DRIVERS) {
    for (const id of d.closable) {
      const p = planterById(id);
      const control = d.preexistingControl?.includes(id) ? " [pre-existing control / regression pin]" : "";
      it(`${d.id}: ${id}${control}`, async () => {
        // carrier-not-live guard: the raw twin must have fired for this carrier type
        expect(rawTwin(p), `carrier ${id} is not live on ${gitVersion}`).toBe(true);
        const { tags, ctx } = await runCell(d, p);
        canaryCheckedRuns++;
        // A1
        expect(tags.filter((t) => t === p.tag)).toEqual([]);
        if (id === "core-worktree-foreign") {
          victimUntouched();
          if (d === syncPushDriver) headTreeIntact(ctx.ws);
          if (d === checkpointDriver) {
            // the checkpoint commits the WORKSPACE's tree, not the foreign tenant's
            const tree = w.git(ctx.ws, "-c", "core.fsmonitor=false", "ls-tree", "-r", "--name-only", checkpointRefName(CONV)).split("\n");
            expect(tree).toContain("knowledge-base/base.md");
            expect(tree).not.toContain("knowledge-base/n.md");
            expect(tree).not.toContain("victim.txt");
          }
        }
        // A2
        for (const dump of w.envDumps()) expect(dump).not.toContain(SENTINEL);
        // A3
        if (!d.skipVerify?.includes(id)) d.verify(ctx);
      });
    }
  }
});

describe("a .git that redirects the git directory is REFUSED before git runs (commondir): no helper, no effect", () => {
  for (const d of DRIVERS) {
    for (const id of d.refused) {
      it(`${d.id}: ${id} (refused)`, async () => {
        const p = planterById(id);
        expect(rawTwin(p), `carrier ${id} is not live on ${gitVersion}`).toBe(true);
        const { tags, ctx } = await runCell(d, p, true);
        canaryCheckedRuns++;
        expect(tags.filter((t) => t === p.tag)).toEqual([]);
        for (const dump of w.envDumps()) expect(dump).not.toContain(SENTINEL);
        d.refusedCheck?.(ctx);
      });
    }
  }
});

describe("git-data remote: the push target is the explicit URL, and a url.* rewrite is refused (C4)", () => {
  // Two bare "tenant" repositories on one "host": A is the workspace's own, B is another tenant's.
  function twoTenants(): { ws: string; a: string; b: string } {
    const { ws } = newWorkspace(w);
    const a = join(w.root, "tenant-a.git");
    const b = join(w.root, "tenant-b.git");
    w.git(w.root, "init", "-q", "--bare", a);
    w.git(w.root, "init", "-q", "--bare", b);
    return { ws, a, b };
  }
  const tipOf = (bare: string): string => {
    try {
      return w.git(bare, "rev-parse", "--verify", "refs/heads/main");
    } catch {
      return "none";
    }
  };
  /** The push exactly as the replication builds it: hardening block + explicit URL, widened to file:// for the fixture. */
  function hostPush(ws: string, target: string): void {
    const h = hostGitInvocation(["push", "--force", target, "main"], { cwd: ws, allowProtocol: "none:file" });
    try {
      execFileSync("git", h.args, { cwd: ws, env: h.env, stdio: "pipe" });
    } catch {
      /* the evidence is where the ref landed */
    }
  }

  it("remote.git-data.pushurl aimed at tenant B: raw git pushing by remote NAME lands in B (control); the explicit URL lands in A", () => {
    const { ws, a, b } = twoTenants();
    w.git(ws, "remote", "add", "git-data", `file://${a}`);
    w.git(ws, "config", "remote.git-data.pushurl", `file://${b}`);
    // control: the remote name resolves through the planted config
    w.git(ws, "push", "-q", "--force", "git-data", "main");
    expect(tipOf(b), "control: the pushurl carrier is not live").not.toBe("none");
    expect(tipOf(a)).toBe("none");
    w.git(b, "update-ref", "-d", "refs/heads/main");
    hostPush(ws, `file://${a}`);
    expect(tipOf(a)).not.toBe("none");
    expect(tipOf(b)).toBe("none");
  });

  it("url.<B>.insteadOf <A>: raw git follows it even for an explicit URL (control); assertNoUrlRewrite refuses before the push", () => {
    const { ws, a, b } = twoTenants();
    w.git(ws, "config", `url.file://${b}.insteadOf`, `file://${a}`);
    w.git(ws, "push", "-q", "--force", `file://${a}`, "main");
    expect(tipOf(b), "control: the insteadOf carrier is not live").not.toBe("none");
    w.git(b, "update-ref", "-d", "refs/heads/main");
    expect(() => assertNoUrlRewrite(ws)).toThrow(GitDataUrlRewriteError);
    // the error carries a count, never the key or the value
    try {
      assertNoUrlRewrite(ws);
    } catch (err) {
      expect((err as Error).message).not.toContain(b);
    }
  });

  it("a remote NAMED by the explicit URL carrying a pushurl: git resolves the argument as a remote name (control: raw git lands in B); the guard refuses it", () => {
    const { ws, a, b } = twoTenants();
    const url = `file://${a}`;
    w.git(ws, "config", `remote.${url}.url`, url);
    w.git(ws, "config", `remote.${url}.pushurl`, `file://${b}`);
    w.git(ws, "push", "-q", "--force", url, "main");
    expect(tipOf(b), "control: the remote-name carrier is not live").not.toBe("none");
    expect(() => assertNoUrlRewrite(ws)).toThrow(GitDataUrlRewriteError);
    // the two expected remotes alone are fine
    const { ws: ws2 } = newWorkspace(w, "second-ws");
    w.git(ws2, "remote", "add", "git-data", `file://${a}`);
    w.git(ws2, "remote", "add", "upstream", `file://${b}`); // a fork workflow is ordinary state, not a rewrite
    w.git(ws2, "config", "remote.pushDefault", "upstream");
    expect(() => assertNoUrlRewrite(ws2)).not.toThrow();
  });

  it("an include.path carrier is covered (the guard reads the EFFECTIVE config); a clean workspace passes", () => {
    const { ws, a, b } = twoTenants();
    expect(() => assertNoUrlRewrite(ws)).not.toThrow();
    const inc = join(w.root, "inc.gitconfig");
    writeFileSync(inc, `[url "file://${b}"]\n\tinsteadOf = file://${a}\n`);
    w.git(ws, "config", "include.path", inc);
    expect(() => assertNoUrlRewrite(ws)).toThrow(GitDataUrlRewriteError);
  });

  it("ensureGitDataRemote adds then re-points the git-data remote in the workspace's own config", () => {
    const { ws } = newWorkspace(w);
    const savedHost = process.env.GIT_DATA_SSH_HOST;
    process.env.GIT_DATA_SSH_HOST = "git-data.invalid";
    try {
      ensureGitDataRemote(ws, WS_ID);
      process.env.GIT_DATA_SSH_HOST = "git-data-2.invalid";
      ensureGitDataRemote(ws, WS_ID); // second call takes the set-url path
    } finally {
      if (savedHost === undefined) delete process.env.GIT_DATA_SSH_HOST;
      else process.env.GIT_DATA_SSH_HOST = savedHost;
    }
    expect(w.git(ws, "config", "--local", "remote.git-data.url")).toContain("git-data-2.invalid");
  });

  it("ensureGitDataRemote on a workspace whose .git carries commondir is refused (fail-loud), and the foreign config is not edited", () => {
    const { ws } = newWorkspace(w);
    const foreign = newWorkspace(w, "foreign-tenant");
    writeFileSync(join(ws, ".git", "commondir"), `${join(foreign.ws, ".git")}\n`);
    const before = readFileSync(join(foreign.ws, ".git", "config"), "utf8");
    process.env.GIT_DATA_SSH_HOST = "git-data.invalid";
    try {
      expect(() => ensureGitDataRemote(ws, WS_ID)).toThrow(/failed to configure the git-data remote/);
    } finally {
      delete process.env.GIT_DATA_SSH_HOST;
    }
    expect(readFileSync(join(foreign.ws, ".git", "config"), "utf8")).toBe(before);
  });
});

describe("clean repository: every consumer's operation succeeds with no carrier (must-PASS input)", () => {
  for (const d of DRIVERS) {
    it(`${d.id}`, async () => {
      const ctx = await d.prepare();
      currentPlanters = [];
      await d.run(ctx);
      expect(w.tags()).toEqual([]);
      d.verify(ctx);
    });
  }
});

describe("RESIDUAL rows: measured open items, not controls", () => {
  // These carriers are NOT closed by `-c` arguments or the environment scrub. The helper they name RUNS, and these
  // rows pin that so a change in either direction fails a test on purpose. Server-only variables must not reach it.
  for (const d of DRIVERS) {
    for (const id of d.residual) {
      const p = planterById(id);
      it(`RESIDUAL ${d.id}: ${id} still runs; the server sentinel is absent from its own environment`, async () => {
        expect(rawTwin(p), `carrier ${id} is not live on ${gitVersion}`).toBe(true);
        await runCell(d, p);
        residualRows++;
        expect(w.tags()).toContain(p.tag);
        for (const dump of w.envDumps()) expect(dump).not.toContain(SENTINEL);
      });
    }
  }

  it("RESIDUAL legacy arm: the installation token is visible to a helper that runs (the consumer's own auth variable)", async () => {
    const { ws, upstream } = newWorkspace(w);
    // a merge driver runs only on a content merge: both sides touch the same tracked file
    writeFileSync(join(ws, ".gitattributes"), "*.txt merge=mg\n");
    writeFileSync(join(ws, "knowledge-base", "m.txt"), "1\n2\n3\n");
    w.git(ws, "add", "--", ".gitattributes", "knowledge-base/m.txt");
    w.git(ws, "commit", "-q", "-m", "m");
    w.git(ws, "push", "-q", "origin", "main");
    const other = join(w.root, "other");
    w.git(w.root, "clone", "-q", `file://${upstream}`, other);
    w.git(other, "config", "user.name", "O");
    w.git(other, "config", "user.email", "o@example.invalid");
    writeFileSync(join(other, "knowledge-base", "m.txt"), "1\n2\n3-up\n");
    w.git(other, "commit", "-q", "-am", "up m");
    w.git(other, "push", "-q", "origin", "main");
    writeFileSync(join(ws, "knowledge-base", "m.txt"), "1-local\n2\n3\n");
    w.git(ws, "commit", "-q", "-am", "local m");
    w.git(ws, "config", "merge.mg.driver", w.helper("merge-driver", "exit 0"));
    await gitWithInstallationAuth(["pull", "--no-rebase", "origin", "main"], 1, { cwd: ws, timeout: 30_000 }).catch(() => {});
    residualRows++;
    expect(w.tags()).toContain("merge-driver");
    const dumps = w.envDumps();
    expect(dumps.length).toBeGreaterThan(0);
    for (const dump of dumps) {
      expect(dump).not.toContain(SENTINEL);
      expect(dump).toContain("GIT_INSTALLATION_TOKEN=");
    }
  });

  it("RESIDUAL legacy arm: a repo-config url.<x>.insteadOf rewrite is followed by a pull", async () => {
    const d = legacyPullDriver;
    const ctx = await d.prepare();
    const evil = join(w.root, "evil.git");
    w.git(w.root, "clone", "-q", "--bare", `file://${ctx.upstream}`, evil);
    const evilWork = join(w.root, "evil-work");
    w.git(w.root, "clone", "-q", `file://${evil}`, evilWork);
    w.git(evilWork, "config", "user.name", "E");
    w.git(evilWork, "config", "user.email", "e@example.invalid");
    writeFileSync(join(evilWork, "knowledge-base", "evil.md"), "evil\n");
    w.git(evilWork, "add", "--", "knowledge-base/evil.md");
    w.git(evilWork, "commit", "-q", "-m", "evil");
    w.git(evilWork, "push", "-q", "origin", "main");
    w.git(ctx.ws, "config", `url.file://${evil}.insteadOf`, `file://${ctx.upstream}`);
    await gitWithInstallationAuth(["pull", "--no-rebase", "origin", "main"], 1, { cwd: ctx.ws, timeout: 30_000 }).catch(() => {});
    residualRows++;
    expect(existsSync(join(ctx.ws, "knowledge-base", "evil.md"))).toBe(true);
  });
});

/** The foreign tenant's loose refs, read from disk (a symlinked refs directory writes here without moving any object count). */
function refsSnapshot(wsPath: string): string {
  const out: string[] = [];
  const walk = (dir: string): void => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else out.push(`${p}=${readFileSync(p, "utf8").trim()}`);
    }
  };
  walk(join(wsPath, ".git", "refs"));
  return out.sort().join("\n");
}

describe("a .git naming another tenant's repository (gitfile, symlink, commondir) is refused: the foreign history does not move", () => {
  // `GIT_WORK_TREE` pins the working tree, not the git directory; the shape check (host-git.ts) refuses these shapes and
  // `GIT_DIR` / `GIT_COMMON_DIR` pin the workspace's own store. Measured for session-sync only: the other consumers share
  // the helper but have no row naming a foreign store here. A preflight, not a structural control.
  const shapes: Array<[string, (ws: string, foreignGit: string) => void]> = [
    ["gitfile", (ws, f) => {
      rmSync(join(ws, ".git"), { recursive: true, force: true });
      writeFileSync(join(ws, ".git"), `gitdir: ${f}\n`);
    }],
    ["symlink", (ws, f) => {
      rmSync(join(ws, ".git"), { recursive: true, force: true });
      symlinkSync(f, join(ws, ".git"));
    }],
    ["commondir", (ws, f) => writeFileSync(join(ws, ".git", "commondir"), `${f}\n`)],
    ["refs-symlink", (ws, f) => {
      rmSync(join(ws, ".git", "refs"), { recursive: true, force: true });
      symlinkSync(join(f, "refs"), join(ws, ".git", "refs"));
    }],
    ["objects-symlink", (ws, f) => {
      rmSync(join(ws, ".git", "objects"), { recursive: true, force: true });
      symlinkSync(join(f, "objects"), join(ws, ".git", "objects"));
    }],
  ];
  for (const [name, plantShape] of shapes) {
    it(`session-sync syncPush with a ${name} .git: refused; raw git (control) moves the foreign repository`, async () => {
      // control: the same carrier under raw git writes into the foreign repository
      const ctl = newWorkspace(w, `ctl-ws-${name}`);
      const ctlForeign = newWorkspace(w, `ctl-foreign-${name}`);
      const ctlBefore = w.git(ctlForeign.ws, "-c", "core.fsmonitor=false", "rev-list", "--all", "--count");
      const ctlObjectsBefore = w.git(ctlForeign.ws, "-c", "core.fsmonitor=false", "count-objects", "-v");
      const ctlRefsBefore = refsSnapshot(ctlForeign.ws);
      plantShape(ctl.ws, join(ctlForeign.ws, ".git"));
      writeFileSync(join(ctl.ws, "knowledge-base", "tenant-a-note.md"), "tenant A content\n");
      try {
        w.git(ctl.ws, "add", "--", "knowledge-base/tenant-a-note.md");
        w.git(ctl.ws, "commit", "-q", "-m", "ctl");
      } catch {
        /* a redirect may also make the verb fail; the foreign object store is the evidence */
      }
      const moved = (() => {
        try {
          return (
            Number(w.git(ctlForeign.ws, "-c", "core.fsmonitor=false", "rev-list", "--all", "--count")) > Number(ctlBefore) ||
            w.git(ctlForeign.ws, "-c", "core.fsmonitor=false", "count-objects", "-v") !== ctlObjectsBefore ||
            refsSnapshot(ctlForeign.ws) !== ctlRefsBefore
          );
        } catch {
          return true; // the foreign repository no longer even lists its own history: the raw write reached it
        }
      })();
      expect(moved, `control: carrier ${name} is not live on ${gitVersion}`).toBe(true);

      const { ws } = newWorkspace(w);
      const foreign = newWorkspace(w, "foreign-tenant");
      const before = w.git(foreign.ws, "-c", "core.fsmonitor=false", "rev-list", "--all", "--count");
      const objectsBefore = w.git(foreign.ws, "-c", "core.fsmonitor=false", "count-objects", "-v");
      const refsBefore = refsSnapshot(foreign.ws);
      plantShape(ws, join(foreign.ws, ".git"));
      writeFileSync(join(ws, "knowledge-base", "tenant-a-note.md"), "tenant A content\n");
      H.reportSilentFallback.mockClear();
      await syncPush(USER, ws, {} as never, WS_ID).catch(() => {});
      canaryCheckedRuns++;
      // the refusal is REPORTED once (reason only), not swallowed as "no remote"
      const refused = H.reportSilentFallback.mock.calls.filter(([, ctx]) => (ctx as { op?: string }).op === "git-refused");
      expect(refused, `a refused ${name} workspace was not reported`).toHaveLength(1);
      expect((refused[0][0] as Error).message).toBe("session-sync refused: git-dir-shape");
      expect(w.git(foreign.ws, "-c", "core.fsmonitor=false", "rev-list", "--all", "--count")).toBe(before);
      expect(w.git(foreign.ws, "-c", "core.fsmonitor=false", "count-objects", "-v")).toBe(objectsBefore);
      expect(refsSnapshot(foreign.ws)).toBe(refsBefore);
    });
  }
});

describe("the auto-commit Sentry mirror carries a classified failure, never the argv or a tenant path", () => {
  it("a stale index.lock makes `git add` fail: op auto-commit-push is reported with a closed bucket and no file name or workspace path", async () => {
    const { ws } = newWorkspace(w);
    dirty(ws);
    writeFileSync(join(ws, ".git", "index.lock"), "");
    await syncPush(USER, ws, {} as never, WS_ID).catch(() => {});
    const calls = H.reportSilentFallback.mock.calls.filter(([, ctx]) => (ctx as { op?: string }).op === "auto-commit-push");
    expect(calls).toHaveLength(1);
    const reported = calls[0][0] as Error;
    expect(reported.message).toMatch(/^auto-commit-push failed \(exit \d+, index-lock\)$/);
    expect(reported.message).not.toContain("note.md");
    expect(reported.message).not.toContain(ws);
    expect(JSON.stringify(calls[0][1])).not.toContain(ws);
  });
});

describe("key-auth arm: transport pinning survives repo-config rewriting (RESIDUAL: the dial still goes to the rewritten host)", () => {
  // A fake `ssh` first on PATH records its argv and fails like a refused handshake. The helper's scrubbed env keeps PATH.
  function fakeSsh(): { bin: string; argvFile: string; envFile: string } {
    const bin = join(w.root, "bin");
    mkdirSync(bin);
    const argvFile = join(w.root, "ssh-argv");
    const envFile = join(w.root, "ssh-env");
    writeFileSync(join(bin, "ssh"), `#!/bin/sh\necho "$@" >> '${argvFile}'\nenv >> '${envFile}'\nexit 255\n`, { mode: 0o755 });
    return { bin, argvFile, envFile };
  }

  it("a repo-config core.sshCommand does not run for the key-auth arm (GIT_SSH_COMMAND wins) [pre-existing control / regression pin]", async () => {
    const { bin, argvFile, envFile } = fakeSsh();
    const { ws } = newWorkspace(w);
    w.git(ws, "remote", "add", "git-data", "ssh://git@git-data.invalid/repo.git");
    w.git(ws, "config", "core.sshCommand", w.helper("ssh-command", "exit 255"));
    const savedPath = process.env.PATH;
    process.env.PATH = `${bin}:${savedPath}`;
    try {
      await gitWithPrivateKeyAuth(["ls-remote", "git-data"], "-----BEGIN OPENSSH PRIVATE KEY-----\nZmFrZQ==\n-----END OPENSSH PRIVATE KEY-----", makeEd25519Pin(), { cwd: ws, timeout: 20_000 }).catch(() => {});
    } finally {
      process.env.PATH = savedPath;
    }
    expect(w.tags()).not.toContain("ssh-command");
    // the dial DID happen through the pinned command (so the absence above is not "never reached ssh"), and the ssh
    // child's environment carries no server-only variable (positive control: it does carry the git-set variables)
    expect(existsSync(argvFile), "the key-auth arm never reached ssh").toBe(true);
    const sshEnv = readFileSync(envFile, "utf8");
    expect(sshEnv).toContain("GIT_ALLOW_PROTOCOL=ssh");
    expect(sshEnv).not.toContain(SENTINEL);
  });

  it("a repo-config protocol.ext.allow=always and an ext:: URL do not run a command on the key-auth arm or the legacy arm (control: raw git does)", async () => {
    H.keepProductionProtocol = true; // the production allowProtocol values, not the fixture's file:// widening
    const marker = join(w.root, "ext-marker");
    const url = `ext::touch ${marker}`;
    const { ws } = newWorkspace(w);
    w.git(ws, "config", "protocol.ext.allow", "always");
    w.git(ws, "remote", "add", "x", url);
    // control: raw git honours the repo config and runs the command
    // (the fixture's own env pins GIT_ALLOW_PROTOCOL without ext, so the control brings a bare env)
    spawnSync("git", ["ls-remote", "x"], {
      cwd: ws,
      env: { PATH: process.env.PATH ?? "/usr/bin:/bin", HOME: w.home, GIT_CONFIG_GLOBAL: "/dev/null", GIT_CONFIG_NOSYSTEM: "1" } as unknown as NodeJS.ProcessEnv,
      timeout: 20_000,
    });
    expect(existsSync(marker), "control: the ext:: carrier is not live").toBe(true);
    rmSync(marker);
    await gitWithPrivateKeyAuth(["ls-remote", "x"], "-----BEGIN OPENSSH PRIVATE KEY-----\nZmFrZQ==\n-----END OPENSSH PRIVATE KEY-----", makeEd25519Pin(), { cwd: ws, timeout: 20_000 }).catch(() => {});
    expect(existsSync(marker), "key-auth arm ran the ext:: command").toBe(false);
    await gitWithInstallationAuth(["ls-remote", "x"], 1, { cwd: ws, timeout: 20_000 }).catch(() => {});
    expect(existsSync(marker), "legacy arm ran the ext:: command").toBe(false);
  });

  it("RESIDUAL: a repo-config url.<x>.insteadOf makes the key-auth arm dial the rewritten host, with the host-key pin options still on the command", async () => {
    const { bin, argvFile } = fakeSsh();
    const { ws } = newWorkspace(w);
    w.git(ws, "remote", "add", "git-data", "ssh://git@git-data.invalid/repo.git");
    w.git(ws, "config", "url.ssh://git@evil.invalid/.insteadOf", "ssh://git@git-data.invalid/");
    const savedPath = process.env.PATH;
    process.env.PATH = `${bin}:${savedPath}`;
    try {
      await gitWithPrivateKeyAuth(["ls-remote", "git-data"], "-----BEGIN OPENSSH PRIVATE KEY-----\nZmFrZQ==\n-----END OPENSSH PRIVATE KEY-----", makeEd25519Pin(), { cwd: ws, timeout: 20_000 }).catch(() => {});
    } finally {
      process.env.PATH = savedPath;
    }
    const argv = readFileSync(argvFile, "utf8");
    residualRows++;
    // measured open item, not a control: the rewritten host IS dialled ...
    expect(argv).toContain("evil.invalid");
    // ... and the pinned options that keep the key from authenticating to an unpinned host are on the same command
    expect(argv).toContain("HostKeyAlias=git-data");
    expect(argv).toContain("StrictHostKeyChecking=yes");
    expect(argv).toMatch(/UserKnownHostsFile=\S+\.known_hosts/);
    // assembled so the repo-wide no-TOFU scanner sees no unpinned-host literal in this file
    expect(argv).not.toContain("StrictHostKeyChecking=" + "no");
  });
});

describe("census: every host-side git exec site is classified (consistency with the source, not integrity)", () => {
  // The census proves the classification table agrees with the source IN THE SAME COMMIT; a diff can edit both. The
  // behavioural rows above are the integrity half. A sixth in-scope site in any file reddens the unclassified check.
  const SERVER = join(__dirname, "..", "server");
  const IN_SCOPE = ["session-sync.ts", "ensure-workspace-repo.ts", "git-data-replication.ts", "git-auth.ts", "inflight-checkpoint.ts", "context-queries-hook.ts", "workspace.ts", "git-data-url-guard.ts", "worktree-config-seed.ts"];
  const CENSUS_ONLY: Record<string, string> = {
    "compound-promote-create-gates.ts": "own scrubbed env + hardening (the model for the helper); async closed-evidence",
    "git-config-atomic.ts": "census-only: atomic config writes; executes host git on an agent-authored `.git` without the shared hardening, and its write follows a gitfile or commondir redirect (read from source, not measured)",
    "git-worktree-validity.ts": "census-only: own minimal env, rev-parse probe; a redirect only changes its verdict",
    "push-branch.ts": "census-only: the file holds the operator-held isolated-GIT_DIR push; its direct `cat-file` / `config user.*` calls run unhardened (writes follow a redirect, read from source, not measured)",
  };
  // Cron handlers: classified PER FILE (a new file here is an unclassified hit, not covered by a directory exemption).
  const CRON_CENSUS: Record<string, string> = {
    "inngest/functions/_cron-safe-commit.ts": "own hardening + env; refuses symlink/gitfile .git shapes",
    "inngest/functions/cron-compound-promote.ts": "cron checkout of the product repo, not an agent workspace",
    "inngest/functions/cron-content-publisher.ts": "cron checkout of the product repo, not an agent workspace",
    "inngest/functions/cron-content-vendor-drift.ts": "cron checkout of the product repo, not an agent workspace",
    "inngest/functions/cron-rule-prune.ts": "cron checkout of the product repo, not an agent workspace",
    "inngest/functions/cron-strategy-review.ts": "cron checkout of the product repo, not an agent workspace",
    "inngest/functions/cron-weekly-analytics.ts": "cron checkout of the product repo, not an agent workspace",
  };

  /** Code only: a doc comment that quotes an exec call is not an exec site. */
  const code = (path: string): string =>
    readFileSync(path, "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");

  function walk(dir: string, out: string[] = []): string[] {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name);
      if (e.isDirectory()) walk(p, out);
      else if (e.name.endsWith(".ts")) out.push(p);
    }
    return out;
  }

  const GIT_EXEC = /\b(?:exec|execSync|execFile|execFileSync|spawn|spawnSync|execFileAsync|execFileP)\s*(?:<[^>]*>)?\(\s*["'`]git\b/g;

  it("no unclassified file execs git, and every in-scope file reaches git through the helper", () => {
    const hits: Record<string, number> = {};
    for (const f of walk(SERVER)) {
      const rel = f.slice(SERVER.length + 1);
      const n = (code(f).match(GIT_EXEC) ?? []).length;
      if (n > 0) hits[rel] = n;
    }
    const unclassified = Object.keys(hits).filter(
      (rel) => !IN_SCOPE.includes(rel) && !(rel in CENSUS_ONLY) && !(rel in CRON_CENSUS),
    );
    // totality: a classified entry that no longer matches any exec site is stale
    for (const rel of [...IN_SCOPE, ...Object.keys(CENSUS_ONLY), ...Object.keys(CRON_CENSUS)]) {
      expect(hits[rel], `${rel} is classified but has no git exec site (stale entry)`).toBeGreaterThan(0);
    }
    expect(unclassified, "a host-side git exec site is not classified: add it to IN_SCOPE (and route it through hostGitInvocation) or to CENSUS_ONLY with a reason").toEqual([]);
    for (const rel of IN_SCOPE) {
      const src = code(join(SERVER, rel));
      expect(src, `${rel} does not use hostGitInvocation`).toContain("hostGitInvocation(");
      // every exec of git in an in-scope file passes an env: no bare `execFile*("git", args)` with the server environment
      for (const m of src.matchAll(GIT_EXEC)) {
        // the call's own argument list: paren-balanced, so a neighbouring `env` cannot satisfy it
        const open = src.indexOf("(", m.index);
        let depth = 0;
        let end = open;
        for (; end < src.length; end++) {
          if (src[end] === "(") depth++;
          else if (src[end] === ")" && --depth === 0) break;
        }
        const call = src.slice(open, end + 1);
        expect(call, `${rel}: a git exec without an explicit env: ${call.slice(0, 80)}`).toMatch(/\benv\b/);
        // ... and never the server's: `process.env` in the exec's own options is the regression this census exists for
        expect(call, `${rel}: a git exec passes the server environment: ${call.slice(0, 80)}`).not.toMatch(/process\.env/);
      }
    }
  });

  it("production call sites pass only the three allowProtocol constants, each with its pinned value", () => {
    const sites: string[] = [];
    for (const f of walk(SERVER)) {
      if (f.endsWith("host-git.ts")) continue;
      for (const m of code(f).matchAll(/allowProtocol:\s*([^,}\s)]+)/g)) sites.push(m[1]);
    }
    const allowed = new Set(["KEY_AUTH_ALLOW_PROTOCOL", "LEGACY_ALLOW_PROTOCOL", "ALLOW_PROTOCOL_NONE"]);
    expect(sites.filter((n) => !allowed.has(n)), "an allowProtocol that is not one of the three constants").toEqual([]);
    expect(sites.filter((n) => n === "KEY_AUTH_ALLOW_PROTOCOL")).toHaveLength(1);
    expect(sites.filter((n) => n === "LEGACY_ALLOW_PROTOCOL")).toHaveLength(1);
    expect(sites.filter((n) => n === "ALLOW_PROTOCOL_NONE").length).toBeGreaterThan(0);
    // the values: `ssh:ext` would re-enable ext:: past protocol.ext.allow=never; `none` is what blocks a promisor or file remote
    expect(KEY_AUTH_ALLOW_PROTOCOL).toBe("ssh");
    expect(LEGACY_ALLOW_PROTOCOL).toBe("https");
    expect(ALLOW_PROTOCOL_NONE).toBe("none");
  });
});

describe("floor", () => {
  it("the battery executed one canary-checked run per closable cell (derived, not a literal)", () => {
    const shapeRows = 5; // gitfile, symlink, commondir, refs symlink, objects symlink naming a foreign tenant
    const expected = DRIVERS.reduce((n, d) => n + d.closable.length + d.refused.length, 0) + shapeRows;
    expect(canaryCheckedRuns).toBe(expected);
    const residualExpected = DRIVERS.reduce((n, d) => n + d.residual.length, 0) + 3; // + merge-driver/token, insteadOf, rewritten-host
    expect(residualRows).toBe(residualExpected);
    expect(PLANTERS.length).toBeGreaterThan(0);
  });
});
