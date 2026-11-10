// Real-git battery for the host-side git consumers (Ref #9601; follow-on to the git-read hardening).
//
// Host-side git runs OUTSIDE the agent sandbox, with the server's process environment, in a workspace whose
// `.git` an agent session can author. Every row here plants an agent-authorable carrier, drives the REAL code
// path of one consumer and asserts EFFECTS:
//   A1  no closable carrier ran (canary file untouched; a foreign worktree is not staged, committed or overwritten);
//   A2  the server-only sentinel is absent from the environment of every helper that did run;
//   A3  the consumer's own operation still succeeded.
// `RESIDUAL` rows pin what is NOT closed. They are measured open items, not controls: a change in either
// direction fails them on purpose.
//
// No `child_process` mock anywhere in this file. Fixtures are synthesized (cq-test-fixtures-synthesized-only).
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
    hostGitInvocation: (args: readonly string[], opts: import("@/server/host-git").HostGitOpts = {}) =>
      actual.hostGitInvocation(args, {
        ...opts,
        allowProtocol:
          opts.allowProtocol !== undefined && !H.keepProductionProtocol ? `${opts.allowProtocol}:file` : opts.allowProtocol,
      }),
  };
});

import { syncPush } from "@/server/session-sync";
import { ensureWorkspaceRepoCloned, __setGraftForTests } from "@/server/ensure-workspace-repo";
import { gitWithInstallationAuth, gitWithPrivateKeyAuth } from "@/server/git-auth";
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
    "fsmonitor-via-commondir",
    "fsmonitor-in-config-worktree",
    "hook-pre-commit",
    "hook-reference-transaction",
    "signing-program",
    "core-worktree-foreign",
  ],
  residual: ["filter-via-git-config", "filter-via-info-attributes", "filter-via-commondir"],
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
  closable: [
    "fsmonitor-in-git-config",
    "fsmonitor-via-commondir",
    "fsmonitor-in-config-worktree",
    "hook-reference-transaction",
    "core-worktree-foreign",
  ],
  residual: [],
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
  closable: ["hook-pre-push", "uploadpack-local-remote"],
  residual: [],
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
    "fsmonitor-via-commondir",
    "fsmonitor-in-config-worktree",
    "hook-reference-transaction",
    "uploadpack-local-remote",
  ],
  residual: [],
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
  closable: [
    "fsmonitor-in-git-config",
    "fsmonitor-via-commondir",
    "fsmonitor-in-config-worktree",
    "hook-reference-transaction",
    "core-worktree-foreign",
  ],
  residual: ["filter-via-git-config", "filter-via-info-attributes", "filter-via-commondir"],
  // the shared hardening set already closes these on today's code: control / regression pin
  preexistingControl: ["fsmonitor-in-git-config", "fsmonitor-via-commondir", "fsmonitor-in-config-worktree"],
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

async function runCell(d: Driver, p: Planter): Promise<{ tags: string[]; ctx: Ctx }> {
  H.keepProductionProtocol = p.id === "uploadpack-local-remote";
  const ctx = await d.prepare();
  currentPlanters = [p];
  if (d !== overlayDriver) plant(p, ctx.ws, w);
  await d.run(ctx);
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
  expect(readdirSync(w.victim).sort()).toEqual(["knowledge-base", "victim.txt"]);
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
        }
        // A2
        for (const dump of w.envDumps()) expect(dump).not.toContain(SENTINEL);
        // A3
        if (!d.skipVerify?.includes(id)) d.verify(ctx);
      });
    }
  }
});

describe("git-data ensureGitDataRemote (local config of the git-data remote) under planted carriers", () => {
  for (const id of ["fsmonitor-in-git-config", "fsmonitor-via-commondir", "hook-reference-transaction", "core-worktree-foreign"]) {
    it(`${id}: the remote is added then re-pointed, no canary runs, the real workspace config is what changed`, async () => {
      const p = planterById(id);
      expect(rawTwin(p), `carrier ${id} is not live on ${gitVersion}`).toBe(true);
      const { ws } = newWorkspace(w);
      plant(p, ws, w);
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
      expect(w.tags().filter((t) => t === p.tag)).toEqual([]);
      if (id === "core-worktree-foreign") victimUntouched();
      const url = w.git(ws, "-c", "core.fsmonitor=false", "config", "--local", "remote.git-data.url");
      expect(url).toContain("git-data-2.invalid");
    });
  }
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
      it(`RESIDUAL ${d.id}: ${id} still runs; the server sentinel does not reach it`, async () => {
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

describe("RESIDUAL: a gitfile .git pointing at a foreign gitdir (not closed by GIT_WORK_TREE)", () => {
  // Measured open item, not a control. `GIT_WORK_TREE=<workspace>` pins the working tree, not the git directory: a workspace
  // `.git` FILE ("gitdir: <path>") the agent wrote redirects the object store, refs and config to another repository, and the
  // consumer then commits the workspace's files INTO that repository. The shape check in git-worktree-validity.ts is the
  // candidate structural answer (follow-up); until then this row pins today's behaviour.
  it("RESIDUAL session-sync syncPush: the auto-commit lands in the foreign repository the gitfile names", async () => {
    const { ws } = newWorkspace(w);
    const foreign = newWorkspace(w, "foreign-tenant");
    const before = w.git(foreign.ws, "rev-list", "--count", "HEAD");
    rmSync(join(ws, ".git"), { recursive: true, force: true });
    writeFileSync(join(ws, ".git"), `gitdir: ${join(foreign.ws, ".git")}\n`);
    writeFileSync(join(ws, "knowledge-base", "tenant-a-note.md"), "tenant A content\n");
    await syncPush(USER, ws, {} as never, WS_ID).catch(() => {});
    residualRows++;
    const after = w.git(foreign.ws, "-c", "core.fsmonitor=false", "rev-list", "--count", "HEAD");
    // pin: the foreign repository's history moved
    expect(Number(after)).toBeGreaterThan(Number(before));
  });
});

describe("key-auth arm: transport pinning survives repo-config rewriting (RESIDUAL: the dial still goes to the rewritten host)", () => {
  // A fake `ssh` first on PATH records its argv and fails like a refused handshake. The helper's scrubbed env keeps PATH.
  function fakeSsh(): { bin: string; argvFile: string } {
    const bin = join(w.root, "bin");
    mkdirSync(bin);
    const argvFile = join(w.root, "ssh-argv");
    writeFileSync(join(bin, "ssh"), `#!/bin/sh\necho "$@" >> '${argvFile}'\nexit 255\n`, { mode: 0o755 });
    return { bin, argvFile };
  }

  it("a repo-config core.sshCommand does not run for the key-auth arm (GIT_SSH_COMMAND wins) [pre-existing control / regression pin]", async () => {
    const { bin } = fakeSsh();
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
  const IN_SCOPE = ["session-sync.ts", "ensure-workspace-repo.ts", "git-data-replication.ts", "git-auth.ts", "inflight-checkpoint.ts"];
  const CENSUS_ONLY: Record<string, string> = {
    "compound-promote-create-gates.ts": "own scrubbed env + hardening (the model for the helper); async closed-evidence",
    "context-queries-hook.ts": "read-only context queries",
    "git-config-atomic.ts": "census item: atomic config writes into the workspace (follow-up)",
    "git-worktree-validity.ts": "own minimal env, rev-parse probe only",
    "push-branch.ts": "legacy branch census-only; the isolated-GIT_DIR path is operator-held and untouched",
    "workspace.ts": "fresh `git init` / clone into a new directory",
    "worktree-config-seed.ts": "census item: seeds worktree config",
  };
  const CRON_DIR = join("inngest", "functions");

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

  const GIT_EXEC = /(?:execFile|execFileSync|spawn|spawnSync|execFileAsync|execFileP)\(\s*"git"/g;

  it("no unclassified file execs git, and every in-scope file reaches git through the helper", () => {
    const hits: Record<string, number> = {};
    for (const f of walk(SERVER)) {
      const rel = f.slice(SERVER.length + 1);
      const n = (code(f).match(GIT_EXEC) ?? []).length;
      if (n > 0) hits[rel] = n;
    }
    const unclassified = Object.keys(hits).filter(
      (rel) => !IN_SCOPE.includes(rel) && !(rel in CENSUS_ONLY) && !rel.startsWith(CRON_DIR),
    );
    expect(unclassified, "a host-side git exec site is not classified: add it to IN_SCOPE (and route it through hostGitInvocation) or to CENSUS_ONLY with a reason").toEqual([]);
    for (const rel of IN_SCOPE) {
      const src = code(join(SERVER, rel));
      expect(src, `${rel} does not use hostGitInvocation`).toContain("hostGitInvocation(");
      // every exec of git in an in-scope file passes an env: no bare `execFile*("git", args)` with the server environment
      for (const m of src.matchAll(/(?:execFile|execFileSync|execFileAsync|execFileP)\(\s*"git"/g)) {
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
      }
    }
  });

  it("production call sites pass only the two arm constants as allowProtocol", () => {
    const sites: string[] = [];
    for (const f of walk(SERVER)) {
      if (f.endsWith("host-git.ts")) continue;
      for (const m of code(f).matchAll(/allowProtocol:\s*([A-Za-z_]+)/g)) sites.push(m[1]);
    }
    expect(sites.sort()).toEqual(["KEY_AUTH_ALLOW_PROTOCOL", "LEGACY_ALLOW_PROTOCOL"]);
  });
});

describe("floor", () => {
  it("the battery executed one canary-checked run per closable cell (derived, not a literal)", () => {
    const expected = DRIVERS.reduce((n, d) => n + d.closable.length, 0);
    expect(canaryCheckedRuns).toBe(expected);
    const residualExpected = DRIVERS.reduce((n, d) => n + d.residual.length, 0) + 4; // + merge-driver/token, insteadOf, rewritten-host, gitfile
    expect(residualRows).toBe(residualExpected);
    expect(PLANTERS.length).toBeGreaterThan(0);
  });
});
