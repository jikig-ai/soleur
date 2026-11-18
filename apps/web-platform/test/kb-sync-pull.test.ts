// Module rows for server/kb-sync-pull.ts (#12718, rulings D25(2), D26(5)) with a RECORDING writer over real git.
//
// TX1-e, equality half: the merge target is exactly the value the module passed to `writer.setTracking` (the in-memory
// `T` from `ls-remote`), and nothing re-reads the agent-writable tracking ref: a writer whose tracking ref is swapped
// under the module still sees `merge(T)`. The shape half lives in test/session-sync-path-allowlist.test.ts.
// TX1-j: a `D` from `ls-remote` that could be read as an option or fails the ref-format rules is `remote_state`, and no
// fetch runs.
import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "./helpers/git-fixture-env";

const LITERAL_URL = "https://github.com/acme/widget.git";

const H = vi.hoisted(() => ({
  remoteUrl: "",
  lsRemote: null as null | string,
  calls: [] as string[][],
  /** R2-B: the timeout each token-bearing child was given, and a hook run before each isolated local child. */
  timeouts: [] as Array<[string, number | undefined]>,
  beforeIso: null as null | ((args: readonly string[]) => void),
}));

vi.mock("@/server/github-app", () => ({ generateInstallationToken: async () => ["ghs", "_", "u".repeat(36)].join("") }));
vi.mock("@/server/git-auth", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-auth")>();
  return {
    ...actual,
    gitWithInstallationAuth: async (args: string[], id: number, opts: import("@/server/git-auth").GitExecOptions = {}) => {
      H.calls.push([...args]);
      H.timeouts.push([args[0], opts.timeout]);
      if (args[0] === "ls-remote" && H.lsRemote !== null) return Buffer.from(H.lsRemote);
      return actual.gitWithInstallationAuth(args.map((a) => (a === LITERAL_URL ? H.remoteUrl : a)), id, opts);
    },
  };
});
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

vi.mock("@/server/git-isolated-local", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-isolated-local")>();
  return {
    ...actual,
    runIsolatedGitLocal: async (
      iso: import("@/server/git-hardened-env").IsolatedPushDir,
      args: readonly string[],
      opts: import("@/server/git-isolated-local").IsolatedGitLocalOptions = {},
    ) => {
      H.beforeIso?.(args);
      return actual.runIsolatedGitLocal(iso, args, opts);
    },
  };
});

import { createIsolatedPushDir, type IsolatedPushDirHandle } from "@/server/git-isolated-push-dir";
import { KB_PULL_HELD_MESSAGES, mergeVerifiedDefault, type KbMergeOutcome, type KbPullWriter } from "@/server/kb-sync-pull";

let base = "";
let dateTick = 1_700_000_000;
const fixtureEnv = (cwd: string): NodeJS.ProcessEnv => {
  const t = `${dateTick++} +0000`;
  return { ...gitFixtureEnv(cwd), GIT_COMMITTER_DATE: t, GIT_AUTHOR_DATE: t };
};
const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8", env: fixtureEnv(cwd) }).trim();

interface Fixture {
  root: string;
  remote: string;
  ws: string;
  T: string;
  headSha: string;
}

beforeAll(() => {
  base = realpathSync(mkdtempSync(join(tmpdir(), "kbpull-unit-")));
});
afterAll(() => {
  if (base) rmSync(base, { recursive: true, force: true });
});

const savedEnv: Record<string, string | undefined> = {};
let iso: IsolatedPushDirHandle | undefined;
beforeEach(() => {
  for (const k of ["HOME", "TMPDIR"]) savedEnv[k] = process.env[k];
  H.lsRemote = null;
  H.calls.length = 0;
  H.timeouts.length = 0;
  H.beforeIso = null;
});
afterEach(() => {
  iso?.dispose();
  iso = undefined;
  for (const [k, v] of Object.entries(savedEnv)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
});

/** A remote one upstream commit ahead of a `--depth 1` workspace. */
function fixture(): Fixture {
  const root = realpathSync(mkdtempSync(join(base, "row-")));
  const remote = join(root, "remote.git");
  execFileSync("git", ["init", "-q", "--bare", "-b", "main", remote], { env: fixtureEnv(root) });
  const seed = join(root, "seed");
  mkdirSync(seed);
  git(seed, "init", "-q", "-b", "main");
  mkdirSync(join(seed, "knowledge-base"));
  writeFileSync(join(seed, "knowledge-base", "a.md"), "a\n");
  git(seed, "add", "-A");
  git(seed, "commit", "-q", "-m", "T0");
  git(seed, "push", "-q", `file://${remote}`, "main");
  const ws = join(root, "ws");
  execFileSync("git", ["clone", "-q", "--depth", "1", `file://${remote}`, ws], { env: fixtureEnv(root), stdio: "pipe" });
  writeFileSync(join(seed, "up.txt"), "upstream\n");
  git(seed, "add", "-A");
  git(seed, "commit", "-q", "-m", "up");
  git(seed, "push", "-q", `file://${remote}`, "main");
  mkdirSync(join(root, "home"));
  mkdirSync(join(root, "tmp"));
  process.env.HOME = join(root, "home");
  process.env.TMPDIR = join(root, "tmp");
  H.remoteUrl = `file://${remote}`;
  cpSync(join(ws, ".git", "shallow"), join(root, "shallow.orig"));
  return { root, remote, ws, T: git(remote, "rev-parse", "refs/heads/main"), headSha: git(ws, "rev-parse", "HEAD") };
}

/** A writer that records every call and applies it with plain git; `swapTracking` writes another value than asked. */
function recordingWriter(f: Fixture, opts: { swapTracking?: string; outcome?: KbMergeOutcome } = {}) {
  const calls: Array<[string, ...string[]]> = [];
  const writer: KbPullWriter = {
    unpack: async (pack) => {
      calls.push(["unpack"]);
      execFileSync("git", ["unpack-objects", "-q"], { cwd: f.ws, input: pack, env: fixtureEnv(f.ws) });
    },
    setTracking: async (branch, sha) => {
      calls.push(["setTracking", branch, sha]);
      git(f.ws, "update-ref", "--no-deref", `refs/remotes/origin/${branch}`, opts.swapTracking ?? sha);
    },
    casBranch: async (branch, next, prev) => {
      calls.push(["casBranch", branch, next, prev]);
      git(f.ws, "update-ref", "--no-deref", `refs/heads/${branch}`, next, prev);
    },
    merge: async (target): Promise<KbMergeOutcome> => {
      calls.push(["merge", target]);
      if (opts.outcome !== undefined) return opts.outcome; // a writer-reported outcome, no merge run
      git(f.ws, "merge", "-q", "--no-edit", target);
      return "clean";
    },
  };
  return { writer, calls };
}

describe("mergeVerifiedDefault with a recording writer (TX1-e equality half, D26(5))", { timeout: 30_000 }, () => {
  test("merge receives exactly the value passed to setTracking: the in-memory T", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const { writer, calls } = recordingWriter(f);
    const r = await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer });
    expect(r.reason).toBe("merged");
    // D39(f): the remote state carries the instant this run's ls-remote returned T.
    expect(r.remote?.readAt).toBeInstanceOf(Date);
    const tracking = calls.find((c) => c[0] === "setTracking");
    const merge = calls.find((c) => c[0] === "merge");
    expect(tracking).toEqual(["setTracking", "main", f.T]);
    expect(merge).toEqual(["merge", f.T]);
    expect(calls.map((c) => c[0])).toEqual(["unpack", "setTracking", "merge"]);
  });

  test("a tracking ref swapped under the module (an agent write) never becomes the merge target", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const { writer, calls } = recordingWriter(f, { swapTracking: f.headSha });
    await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer });
    expect(calls.find((c) => c[0] === "merge")).toEqual(["merge", f.T]);
  });

  test("the module stamps nothing, reports nothing and leaves the isolated directory to its caller", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const { writer } = recordingWriter(f);
    await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer });
    expect(() => git(iso!.gitDir, "rev-parse", "--git-dir")).not.toThrow();
  });
});

describe("R2-B (verify-coverage P3-2): the fetch stage reads the budget per child, not once", { timeout: 30_000 }, () => {
  /** A budget on a fake clock that each have-ref write (the first isolated children of the fetch stage) advances. */
  const clocked = (total: number, perHaveMs: number) => {
    let spentMs = 0;
    H.beforeIso = (args) => {
      if (args[0] === "update-ref" && String(args[2] ?? "").startsWith("refs/heads/have-")) spentMs += perHaveMs;
    };
    return { remaining: () => total - spentMs, mergeStartMinMs: 0 };
  };

  test("the fetch child is capped at what is left AFTER the have-ref children ran, not at the stage's entry value", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const { writer } = recordingWriter(f);
    const budget = clocked(30_000, 20_000);
    const r = await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer, budget });
    expect(r.reason).toBe("merged");
    const fetchTimeout = H.timeouts.find(([verb]) => verb === "fetch")?.[1];
    expect(fetchTimeout).toBeLessThanOrEqual(10_000);
  });

  test("a fetch stage that ran out of budget mid-way is pull_deadline (ref=default), not fetch_failed, and nothing merges", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const { writer, calls } = recordingWriter(f);
    const budget = clocked(30_000, 31_000);
    const r = await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer, budget });
    // the fetch got the 1 ms floor (nothing left), was cut short, and that is the budget's doing: pull_deadline
    expect(H.timeouts.find(([verb]) => verb === "fetch")?.[1]).toBe(1);
    expect(r).toEqual(expect.objectContaining({ reason: "pull_deadline", ref: "default" }));
    expect(calls.find((c) => c[0] === "merge")).toBeUndefined();
  });
});

describe("R2-B (data-sec P3-1): the isolated merge-tree runs with directory-rename detection off, as the merge does", { timeout: 30_000 }, () => {
  test("the precheck's merge-tree argv carries -c merge.directoryRenames=false (the same pin as the workspace merge)", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const seen: string[][] = [];
    H.beforeIso = (args) => {
      if (args.includes("merge-tree")) seen.push([...args]);
    };
    const { writer } = recordingWriter(f);
    const r = await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer, precheck: true });
    expect(r.reason).toBe("merged");
    expect(seen).toEqual([["-c", "merge.directoryRenames=false", "merge-tree", "--write-tree", "--no-messages", f.headSha, f.T]]);
  });
});

// Review Phase 0 (cq-union-widening-grep-three-patterns): the widened merge outcomes map to their closed reasons, and
// every widened reason is a warning (a non-null message). Later packages return them; the mapping is frozen here.
describe("Phase 0: the widened merge outcomes and pull reasons", { timeout: 30_000 }, () => {
  test.each([
    ["collision", "untracked_collision"],
    ["unverified", "merge_unverified"],
    ["in_progress", "unresolved_merge"],
  ] as const)("writer outcome %s -> %s", async (outcome, reason) => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const { writer, calls } = recordingWriter(f, { outcome });
    const r = await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer });
    expect(r.reason).toBe(reason);
    expect(calls.find((c) => c[0] === "merge")).toEqual(["merge", f.T]);
  });

  test.each(["untracked_collision", "merge_unverified", "pull_deadline", "side_pr_create_failed", "pull_unexpected"] as const)(
    "%s is a warning reason (a static message)",
    (reason) => {
      expect(typeof KB_PULL_HELD_MESSAGES[reason]).toBe("string");
    },
  );
});

describe("TX1-j (D26(5)): an option-shaped or malformed default branch from ls-remote is remote_state", { timeout: 30_000 }, () => {
  for (const D of ["-x", "--upload-pack=x", "a..b"]) {
    test(`D = ${JSON.stringify(D)} -> remote_state, no fetch`, async () => {
      const f = fixture();
      iso = createIsolatedPushDir(f.ws);
      H.lsRemote = `ref: refs/heads/${D}\tHEAD\n${f.T}\tHEAD\n`;
      const { writer, calls } = recordingWriter(f);
      const r = await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer });
      expect(r.reason).toBe("remote_state");
      expect(H.calls.map((c) => c[0])).toEqual(["ls-remote"]);
      expect(calls).toEqual([]);
    });
  }
});

// Review fix round 1, WP1: the budget's merge-start gate (D38(3)), the catch-all's diagnostics (obs F3), the side-conflict
// warning (D44) and the remote sub-cause (obs F8).
describe("WP1: budget, catch-all and closed sub-causes", { timeout: 30_000 }, () => {
  test("D38(3): with less than mergeStartMinMs left the merge never starts -> pull_deadline (ref=default)", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const { writer, calls } = recordingWriter(f);
    const r = await mergeVerifiedDefault({
      isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer,
      budget: { remaining: () => 19_999, mergeStartMinMs: 20_000 },
    });
    expect(r).toEqual(expect.objectContaining({ reason: "pull_deadline", ref: "default" }));
    expect(calls.find((c) => c[0] === "merge")).toBeUndefined();
  });

  test("D38(2): a spent budget starts no network step -> pull_deadline, no ls-remote", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const { writer, calls } = recordingWriter(f);
    const r = await mergeVerifiedDefault({
      isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer,
      budget: { remaining: () => 0, mergeStartMinMs: 20_000 },
    });
    expect(r.reason).toBe("pull_deadline");
    expect(H.calls).toEqual([]);
    expect(calls).toEqual([]);
  });

  test("obs F3: a writer that throws is pull_unexpected with its class name, never its message", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    const { writer } = recordingWriter(f);
    class WriterBroke extends Error {
      override name = "WriterBroke";
    }
    writer.merge = async () => {
      throw new WriterBroke(`git merge ${f.T} at ${f.ws}`);
    };
    const r = await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer });
    expect(r.reason).toBe("pull_unexpected");
    expect(r.errName).toBe("WriterBroke");
    expect(JSON.stringify({ ...r, remote: undefined })).not.toMatch(/[0-9a-f]{40}|\/tmp\//);
  });

  test("obs F8: an unreadable ls-remote answer is remote_state with remote_cause remote_state_invalid", async () => {
    const f = fixture();
    iso = createIsolatedPushDir(f.ws);
    H.lsRemote = "garbage\n";
    const { writer } = recordingWriter(f);
    const r = await mergeVerifiedDefault({ isolated: iso, installationId: 1, url: LITERAL_URL, headSha: f.headSha, refName: "refs/heads/main", writer });
    expect(r.reason).toBe("remote_state");
    expect(["remote_state_invalid", "remote_head_absent"]).toContain(r.remoteCause);
  });

  test("D44: side_conflict is a warning reason (a static message)", () => {
    expect(typeof KB_PULL_HELD_MESSAGES.side_conflict).toBe("string");
  });
});
