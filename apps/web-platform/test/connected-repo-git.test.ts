// Module rows for server/connected-repo-git.ts (review fix round 1, WP1: rulings D35, D36, D37(1)(2), D38(1)(6)).
//
// - The argv guard: exactly the two pinned merge shapes (D37(2)), the four new read/pin shapes (D35, D36(a)(c)), each
//   accepted exactly and refused in every variant.
// - The pull writer over REAL git: a stale `MERGE_AUTOSTASH` refuses `in_progress` before any merge child and pins the
//   autostash commit under `refs/soleur/autostash/` (TX4-h, D36(c), D37(1)); the pin reads only a small regular file.
// - The async runner rejects with git's exit status and stderr, and the same-host lock serializes one workspace.
// Synthesized data only (cq-test-fixtures-synthesized-only).
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "./helpers/git-fixture-env";

const H = vi.hoisted(() => ({
  host: [] as string[][],
  mirrorWarnWithDebounce: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: vi.fn(),
  mirrorWarnWithDebounce: H.mirrorWarnWithDebounce,
}));
vi.mock("@/server/host-git", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/host-git")>();
  return {
    ...actual,
    hostGitInvocation: (args: readonly string[], opts: import("@/server/host-git").HostGitOpts) => {
      H.host.push([...args]);
      return actual.hostGitInvocation(args, opts);
    },
  };
});

import {
  AUTOSTASH_PIN_PREFIX,
  assertConnectedRepoArgv,
  kbPullWriter,
  MERGE_CONFIG_PINS,
  mergeArgv,
  pinInterruptedAutostash,
  runConnectedRepoGitAsync,
  withWorkspaceGitLock,
  WORKSPACE_GIT_LOCK_TIMEOUT,
} from "@/server/connected-repo-git";
import { AUTO_MERGE_MSG_PULL, AUTO_MERGE_MSG_SELF_HEAL } from "@/server/kb-sync-pull";

const SHA = "a".repeat(40);
const SHA2 = "b".repeat(40);

describe("argv guard: the two pinned merge shapes (D37(2))", () => {
  test("the pull shape (--autostash, the pull message) and the self-heal shape (no --autostash, its own message) pass", () => {
    expect(() => assertConnectedRepoArgv(mergeArgv(SHA))).not.toThrow();
    expect(() => assertConnectedRepoArgv(mergeArgv(SHA, { autostash: false }))).not.toThrow();
    expect(mergeArgv(SHA, { autostash: false })).toEqual([
      ...MERGE_CONFIG_PINS, "merge", "--no-edit", "--no-overwrite-ignore", "-m", AUTO_MERGE_MSG_SELF_HEAL, SHA,
    ]);
    expect(AUTO_MERGE_MSG_SELF_HEAL).toBe("Soleur: merge GitHub into workspace");
  });

  test("a mix of the two shapes is refused", () => {
    const pull = mergeArgv(SHA);
    const heal = mergeArgv(SHA, { autostash: false });
    // --autostash with the self-heal message
    const mixA = pull.map((a) => (a === AUTO_MERGE_MSG_PULL ? AUTO_MERGE_MSG_SELF_HEAL : a));
    // no --autostash with the pull message
    const mixB = heal.map((a) => (a === AUTO_MERGE_MSG_SELF_HEAL ? AUTO_MERGE_MSG_PULL : a));
    for (const argv of [mixA, mixB]) expect(() => assertConnectedRepoArgv(argv)).toThrow(/pinned/);
  });
});

describe("argv guard: the four new read / pin shapes (D35, D36(a)(c))", () => {
  const DIFF = ["diff", "--name-status", "-z", "--no-renames", "--no-ext-diff", "--no-textconv", "--diff-filter=AD", "HEAD", SHA, "--"];
  const LS = ["ls-files", "-z", "--others", "--directory", "--", ":(literal)build/"];
  const STASH = ["rev-parse", "-q", "--verify", "refs/stash"];
  const PIN = ["update-ref", "--no-deref", `${AUTOSTASH_PIN_PREFIX}${SHA}`, SHA];

  test("each shape passes exactly", () => {
    for (const argv of [DIFF, LS, STASH, PIN]) expect(() => assertConnectedRepoArgv(argv), argv.join(" ")).not.toThrow();
  });

  test.each([
    ["diff: a ref target", [...DIFF.slice(0, 8), "refs/remotes/origin/main", "--"]],
    ["diff: no --no-ext-diff", DIFF.filter((a) => a !== "--no-ext-diff")],
    ["diff: an extra pathspec", [...DIFF, "src"]],
    ["diff: --output", [...DIFF.slice(0, 2), "--output=/tmp/x", ...DIFF.slice(2)]],
    ["diff: another base", [...DIFF.slice(0, 7), SHA2, SHA, "--"]],
    ["ls-files: not literal", ["ls-files", "-z", "--others", "--directory", "--", "build/"]],
    ["ls-files: no trailing slash", ["ls-files", "-z", "--others", "--directory", "--", ":(literal)build"]],
    ["ls-files: --exclude-standard", ["ls-files", "-z", "--others", "--directory", "--exclude-standard", "--", ":(literal)build/"]],
    ["ls-files: empty path", ["ls-files", "-z", "--others", "--directory", "--", ":(literal)/"]],
    ["ls-files: two pathspecs", [...LS, ":(literal)x/"]],
    ["rev-parse: another ref", ["rev-parse", "-q", "--verify", "refs/heads/main"]],
    ["rev-parse: --git-path", ["rev-parse", "--git-path", "x"]],
    ["rev-parse: short refname", ["rev-parse", "-q", "--verify", "stash"]],
    ["pin: a value that is not its name", ["update-ref", "--no-deref", `${AUTOSTASH_PIN_PREFIX}${SHA}`, SHA2]],
    ["pin: an old value", [...PIN, SHA]],
    ["pin: all-zero", ["update-ref", "--no-deref", `${AUTOSTASH_PIN_PREFIX}${"0".repeat(40)}`, "0".repeat(40)]],
    ["pin: a nested name", ["update-ref", "--no-deref", `${AUTOSTASH_PIN_PREFIX}x/${SHA}`, SHA]],
    ["pin: no --no-deref", ["update-ref", `${AUTOSTASH_PIN_PREFIX}${SHA}`, SHA]],
    ["pin: delete", ["update-ref", "-d", `${AUTOSTASH_PIN_PREFIX}${SHA}`]],
  ])("refused: %s", (_name, argv) => {
    expect(() => assertConnectedRepoArgv(argv)).toThrow(/connected-repo git/);
  });
});

let base = "";
let dateTick = 1_700_000_000;
const env = (cwd: string): NodeJS.ProcessEnv => {
  const t = `${dateTick++} +0000`;
  return { ...gitFixtureEnv(cwd), GIT_COMMITTER_DATE: t, GIT_AUTHOR_DATE: t };
};
const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8", env: env(cwd) }).trim();

beforeAll(() => {
  base = realpathSync(mkdtempSync(join(tmpdir(), "connected-repo-git-")));
});
afterAll(() => {
  if (base) rmSync(base, { recursive: true, force: true });
});
beforeEach(() => {
  H.host.length = 0;
  H.mirrorWarnWithDebounce.mockClear();
});

/** A workspace with two commits on main (`T` = the second, on a side ref) and HEAD at the first. */
function repo(): { ws: string; head: string; T: string } {
  const ws = realpathSync(mkdtempSync(join(base, "ws-")));
  git(ws, "init", "-q", "-b", "main");
  git(ws, "config", "user.name", "Local");
  git(ws, "config", "user.email", "local@example.test");
  writeFileSync(join(ws, "a.txt"), "a\n");
  git(ws, "add", "-A");
  git(ws, "commit", "-q", "-m", "one");
  const head = git(ws, "rev-parse", "HEAD");
  git(ws, "checkout", "-q", "-b", "up");
  writeFileSync(join(ws, "b.txt"), "b\n");
  git(ws, "add", "-A");
  git(ws, "commit", "-q", "-m", "two");
  const T = git(ws, "rev-parse", "HEAD");
  git(ws, "checkout", "-q", "main");
  git(ws, "branch", "-q", "-D", "up");
  return { ws, head, T };
}

/** A stash commit of a dirty `a.txt`, written to `.git/MERGE_AUTOSTASH` as an interrupted merge leaves it; tree clean. */
function staleAutostash(ws: string): string {
  writeFileSync(join(ws, "a.txt"), "a\nUSER-DIRTY\n");
  const sha = git(ws, "stash", "create");
  git(ws, "checkout", "--", "a.txt");
  writeFileSync(join(ws, ".git", "MERGE_AUTOSTASH"), `${sha}\n`);
  return sha;
}

const pins = (ws: string): string => git(ws, "for-each-ref", "--format=%(refname) %(objectname)", AUTOSTASH_PIN_PREFIX);

describe("the pull writer's entry check (D37(1)) and the autostash pin (D36(c)), real git", { timeout: 30_000 }, () => {
  test("TX4-h: a stale MERGE_AUTOSTASH only -> in_progress, no merge child, the autostash pinned by its own sha", async () => {
    const { ws, head, T } = repo();
    const sha = staleAutostash(ws);
    expect(await kbPullWriter(ws).merge(T)).toBe("in_progress");
    expect(H.host.filter((a) => a.includes("merge"))).toEqual([]);
    expect(git(ws, "rev-parse", "HEAD")).toBe(head);
    expect(pins(ws)).toBe(`${AUTOSTASH_PIN_PREFIX}${sha} ${sha}`);
    // idempotent: a second refusal leaves exactly the same one ref
    expect(await kbPullWriter(ws, { autostash: false }).merge(T)).toBe("in_progress");
    expect(pins(ws)).toBe(`${AUTOSTASH_PIN_PREFIX}${sha} ${sha}`);
    // the pinned commit survives an immediate prune
    git(ws, "gc", "-q", "--prune=now");
    expect(git(ws, "show", `${sha}:a.txt`)).toBe("a\nUSER-DIRTY");
  });

  test("R2-B (data P2-1): a MERGE_HEAD next to MERGE_AUTOSTASH (a content conflict) is in_progress AND the autostash is pinned", async () => {
    const { ws, T } = repo();
    const sha = staleAutostash(ws);
    writeFileSync(join(ws, ".git", "MERGE_HEAD"), `${T}\n`);
    expect(await kbPullWriter(ws).merge(T)).toBe("in_progress");
    expect(pins(ws)).toBe(`${AUTOSTASH_PIN_PREFIX}${sha} ${sha}`);
    // MERGE_AUTOSTASH and MERGE_HEAD are untouched (git commit / merge --abort still apply the autostash)
    expect(git(ws, "rev-parse", "--verify", "MERGE_AUTOSTASH")).toBe(sha);
    expect(git(ws, "rev-parse", "--verify", "MERGE_HEAD")).toBe(T);
  });

  test("R2-B (data P2-1): a conflicted pull merge leaves MERGE_HEAD + MERGE_AUTOSTASH; the writer pins it on its conflict return, and it survives gc", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "ws-")));
    git(ws, "init", "-q", "-b", "main");
    git(ws, "config", "user.name", "Local");
    git(ws, "config", "user.email", "local@example.test");
    writeFileSync(join(ws, "a.txt"), "a\n");
    writeFileSync(join(ws, "c.txt"), "c\n");
    git(ws, "add", "-A");
    git(ws, "commit", "-q", "-m", "one");
    git(ws, "checkout", "-q", "-b", "up");
    writeFileSync(join(ws, "a.txt"), "upstream\n");
    git(ws, "commit", "-q", "-am", "upstream edit");
    const T = git(ws, "rev-parse", "HEAD");
    git(ws, "checkout", "-q", "main");
    git(ws, "branch", "-q", "-D", "up");
    writeFileSync(join(ws, "a.txt"), "local\n");
    git(ws, "commit", "-q", "-am", "local edit");
    writeFileSync(join(ws, "c.txt"), "c\nUSER-DIRTY-OTHER\n"); // the uncommitted edit only the autostash holds
    expect(await kbPullWriter(ws).merge(T)).toBe("conflict");
    const autostash = git(ws, "rev-parse", "--verify", "MERGE_AUTOSTASH");
    expect(git(ws, "rev-parse", "--verify", "MERGE_HEAD")).toBe(T);
    expect(pins(ws)).toBe(`${AUTOSTASH_PIN_PREFIX}${autostash} ${autostash}`);
    git(ws, "gc", "-q", "--prune=now");
    expect(git(ws, "show", `${autostash}:c.txt`)).toBe("c\nUSER-DIRTY-OTHER");
    // the next sync's entry refusal pins idempotently: still exactly one ref
    expect(await kbPullWriter(ws).merge(T)).toBe("in_progress");
    expect(pins(ws)).toBe(`${AUTOSTASH_PIN_PREFIX}${autostash} ${autostash}`);
  });

  test.each([
    ["a symlink", (ws: string, sha: string) => {
      writeFileSync(join(ws, "target"), `${sha}\n`);
      symlinkSync(join(ws, "target"), join(ws, ".git", "MERGE_AUTOSTASH"));
    }, "not_regular"],
    ["a file over 64 bytes", (ws: string, sha: string) => writeFileSync(join(ws, ".git", "MERGE_AUTOSTASH"), `${sha}\n${"x".repeat(64)}\n`), "too_large"],
    ["a first line that is not 40 hex", (ws: string) => writeFileSync(join(ws, ".git", "MERGE_AUTOSTASH"), "refs/heads/main\n"), "malformed"],
    ["a directory", (ws: string) => mkdirSync(join(ws, ".git", "MERGE_AUTOSTASH")), "not_regular"],
    // verify-final B3: an agent-planted FIFO is refused without ever blocking the event loop
    ["a FIFO", (ws: string) => execFileSync("mkfifo", [join(ws, ".git", "MERGE_AUTOSTASH")]), "not_regular"],
  ] as const)("the pin refuses %s: no ref, one warning", async (_name, plant, cause) => {
    const { ws } = repo();
    const sha = staleAutostash(ws);
    rmSync(join(ws, ".git", "MERGE_AUTOSTASH"));
    plant(ws, sha);
    await pinInterruptedAutostash(ws);
    expect(pins(ws)).toBe("");
    expect(H.mirrorWarnWithDebounce).toHaveBeenCalledTimes(1);
    expect(H.mirrorWarnWithDebounce.mock.calls[0][1]).toEqual(expect.objectContaining({ op: "kb-sync.autostash-pin", tags: { cause } }));
  });

  test("verify-final B3: the MERGE_AUTOSTASH open is O_NONBLOCK (a FIFO swapped in after the lstat cannot stall the loop)", () => {
    const src = readFileSync(join(__dirname, "..", "server", "connected-repo-git.ts"), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
    const start = src.indexOf("function readMergeAutostash(");
    expect(start).toBeGreaterThan(-1);
    const body = src.slice(start, src.indexOf("\n}\n", start));
    const opens = [...body.matchAll(/openSync\(([^)]*)\)/g)].map((m) => m[1]);
    expect(opens).toHaveLength(1);
    expect(opens[0]).toMatch(/^path, fsConstants\.O_RDONLY \| fsConstants\.O_NOFOLLOW \| fsConstants\.O_NONBLOCK$/);
    // no pre-open lstat: the checks run on the open descriptor, so there is no check-then-open window (CodeQL js/file-system-race)
    expect(body).not.toMatch(/\blstatSync\(/);
    expect(body).toMatch(/fstatSync\(fd\)/);
  });

  test("no MERGE_AUTOSTASH: the pin does nothing and says nothing", async () => {
    const { ws } = repo();
    await pinInterruptedAutostash(ws);
    expect(pins(ws)).toBe("");
    expect(H.host).toEqual([]);
    expect(H.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  test("an unmerged index entry with neither state file is in_progress (the same check as syncPull)", async () => {
    const { ws, T } = repo();
    git(ws, "checkout", "-q", "-b", "x");
    writeFileSync(join(ws, "a.txt"), "x\n");
    git(ws, "commit", "-q", "-am", "x");
    git(ws, "checkout", "-q", "main");
    writeFileSync(join(ws, "a.txt"), "main\n");
    git(ws, "commit", "-q", "-am", "main");
    try {
      git(ws, "merge", "-q", "--no-edit", "x");
    } catch {
      /* the conflict is the point */
    }
    rmSync(join(ws, ".git", "MERGE_HEAD"));
    rmSync(join(ws, ".git", "MERGE_MSG"), { force: true });
    expect(await kbPullWriter(ws).merge(T)).toBe("in_progress");
  });
});

describe("R2-B (data-sec P3-1): directory-rename detection is off in the merge, so an upstream add never lands on an ignored path", { timeout: 30_000 }, () => {
  /** Local renames old/ -> new/ with an ignored new/x; upstream (T) adds old/x. Returns T. */
  function renameScenario(ws: string): string {
    git(ws, "init", "-q", "-b", "main");
    git(ws, "config", "user.name", "Local");
    git(ws, "config", "user.email", "local@example.test");
    mkdirSync(join(ws, "old"));
    writeFileSync(join(ws, "old", "a"), "a\n");
    writeFileSync(join(ws, "old", "b"), "b\n");
    writeFileSync(join(ws, ".gitignore"), "new/x\n");
    git(ws, "add", "-A");
    git(ws, "commit", "-q", "-m", "base");
    git(ws, "checkout", "-q", "-b", "up");
    writeFileSync(join(ws, "old", "x"), "upstream-x\n");
    git(ws, "add", "-A");
    git(ws, "commit", "-q", "-m", "upstream adds old/x");
    const T = git(ws, "rev-parse", "HEAD");
    git(ws, "checkout", "-q", "main");
    git(ws, "branch", "-q", "-D", "up");
    git(ws, "mv", "old", "new");
    git(ws, "commit", "-q", "-m", "local renames old/ to new/");
    writeFileSync(join(ws, "new", "x"), "IGNORED-LOCAL\n");
    return T;
  }

  test.each([
    ["the pull shape", {}],
    ["the self-heal shape", { autostash: false }],
  ] as const)("%s: the ignored new/x keeps its bytes, the upstream file lands at old/x, the merge is clean", async (_name, opts) => {
    const ws = realpathSync(mkdtempSync(join(base, "ws-")));
    const T = renameScenario(ws);
    expect(await kbPullWriter(ws, opts).merge(T)).toBe("clean");
    expect(readFileSync(join(ws, "new", "x"), "utf8")).toBe("IGNORED-LOCAL\n");
    expect(readFileSync(join(ws, "old", "x"), "utf8")).toBe("upstream-x\n");
    expect(git(ws, "status", "--porcelain")).toBe("");
  });
});

describe("R2-B (verify-coverage P3-1): the writer's status runs skip untracked files; the collision check still sees them", { timeout: 30_000 }, () => {
  const statusRuns = (): string[][] => H.host.filter((a) => a[0] === "status");

  test("a clean merge: both status runs (before, after) are --untracked-files=no", async () => {
    const { ws, T } = repo();
    writeFileSync(join(ws, "scratch.txt"), "untracked\n");
    expect(await kbPullWriter(ws).merge(T)).toBe("clean");
    expect(statusRuns()).toEqual([
      ["status", "--porcelain=v1", "-z", "--untracked-files=no"],
      ["status", "--porcelain=v1", "-z", "--untracked-files=no"],
    ]);
  });

  test("an untracked file and an ignored file at an incoming path are still collisions (the check reads the disk, not status)", async () => {
    for (const ignored of [false, true]) {
      const { ws, T } = repo();
      if (ignored) writeFileSync(join(ws, ".git", "info", "exclude"), "b.txt\n");
      writeFileSync(join(ws, "b.txt"), "LOCAL-ONLY\n");
      H.host.length = 0;
      expect(await kbPullWriter(ws).merge(T), `ignored=${ignored}`).toBe("collision");
      expect(readFileSync(join(ws, "b.txt"), "utf8")).toBe("LOCAL-ONLY\n");
      expect(statusRuns()).toEqual([["status", "--porcelain=v1", "-z", "--untracked-files=no"]]);
    }
  });
});

describe("the async runner and the same-host lock (D38(1)(6))", { timeout: 30_000 }, () => {
  test("a failing child rejects with git's exit status and stderr; a refused argv rejects before any child", async () => {
    const { ws } = repo();
    const err = (await runConnectedRepoGitAsync(["rev-parse", "-q", "--verify", "refs/stash"], { cwd: ws }).catch((e: unknown) => e)) as {
      status?: unknown;
    };
    expect(err.status).toBe(1);
    H.host.length = 0;
    await expect(runConnectedRepoGitAsync(["reset", "--hard"], { cwd: ws })).rejects.toThrow(/not allowed/);
    expect(H.host).toEqual([]);
  });

  test("the input reaches the child's stdin", async () => {
    const { ws } = repo();
    const pack = execFileSync("git", ["pack-objects", "--stdout", "-q", "--revs"], { cwd: ws, input: "HEAD\n", env: env(ws) });
    await expect(runConnectedRepoGitAsync(["unpack-objects", "-q"], { cwd: ws, input: pack })).resolves.toBeInstanceOf(Buffer);
  });

  test("two holders of one workspace run one after the other; another workspace does not wait", async () => {
    const order: string[] = [];
    const slow = (tag: string, ms: number) => async () => {
      order.push(`${tag}:start`);
      await new Promise((r) => setTimeout(r, ms));
      order.push(`${tag}:end`);
      return tag;
    };
    const a = withWorkspaceGitLock(base, slow("a", 40));
    const b = withWorkspaceGitLock(`${base}/`, slow("b", 1)); // the same real path
    const c = withWorkspaceGitLock(join(base, "other"), slow("c", 1));
    expect(await Promise.all([a, b, c])).toEqual(["a", "b", "c"]);
    expect(order.indexOf("b:start")).toBeGreaterThan(order.indexOf("a:end"));
    expect(order.indexOf("c:end")).toBeLessThan(order.indexOf("a:end"));
  });

  test("a holder that throws releases the lock", async () => {
    await expect(withWorkspaceGitLock(base, async () => {
      throw new Error("boom");
    })).rejects.toThrow("boom");
    await expect(withWorkspaceGitLock(base, async () => "next")).resolves.toBe("next");
  });
});

describe("R2-B: the lock wait is bounded by the caller's budget (verify-coverage P2-1)", { timeout: 30_000 }, () => {
  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
  const hold = (ms: number, order: string[], tag: string) => async () => {
    order.push(`${tag}:start`);
    await sleep(ms);
    order.push(`${tag}:end`);
    return tag;
  };

  test("a wait that outlasts waitMs resolves lock_timeout and never runs fn", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "lock-")));
    const order: string[] = [];
    const a = withWorkspaceGitLock(ws, hold(200, order, "a"));
    const fn = vi.fn(async () => "b");
    const startedAt = Date.now();
    const b = await withWorkspaceGitLock(ws, fn, { waitMs: 20 });
    expect(b).toBe(WORKSPACE_GIT_LOCK_TIMEOUT);
    expect(Date.now() - startedAt).toBeLessThan(150); // it did not wait for the holder
    expect(fn).not.toHaveBeenCalled();
    expect(order).toEqual(["a:start"]);
    expect(await a).toBe("a");
    expect(fn).not.toHaveBeenCalled();
  });

  test("FIFO is kept across a timed-out waiter: a later caller still waits for the holder", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "lock-")));
    const order: string[] = [];
    const a = withWorkspaceGitLock(ws, hold(150, order, "a"));
    const b = withWorkspaceGitLock(ws, hold(1, order, "b"), { waitMs: 10 });
    const c = withWorkspaceGitLock(ws, hold(1, order, "c"));
    expect(await b).toBe(WORKSPACE_GIT_LOCK_TIMEOUT);
    // a caller arriving after the timeout, while the holder still runs, queues behind it too
    const d = withWorkspaceGitLock(ws, hold(1, order, "d"), { waitMs: 5_000 });
    expect(await Promise.all([a, c, d])).toEqual(["a", "c", "d"]);
    expect(order).toEqual(["a:start", "a:end", "c:start", "c:end", "d:start", "d:end"]);
  });

  test("the timed-out waiter was the queue's tail: the next caller still waits for the holder (the queue entry is kept)", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "lock-")));
    const order: string[] = [];
    const a = withWorkspaceGitLock(ws, hold(150, order, "a"));
    expect(await withWorkspaceGitLock(ws, hold(1, order, "b"), { waitMs: 10 })).toBe(WORKSPACE_GIT_LOCK_TIMEOUT);
    const c = withWorkspaceGitLock(ws, hold(1, order, "c"));
    expect(await Promise.all([a, c])).toEqual(["a", "c"]);
    expect(order).toEqual(["a:start", "a:end", "c:start", "c:end"]);
  });

  test("a holder that finishes inside the wait releases it: the waiter runs and returns its value", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "lock-")));
    const order: string[] = [];
    const a = withWorkspaceGitLock(ws, hold(20, order, "a"));
    expect(await withWorkspaceGitLock(ws, hold(1, order, "b"), { waitMs: 2_000 })).toBe("b");
    expect(await a).toBe("a");
    expect(order).toEqual(["a:start", "a:end", "b:start", "b:end"]);
  });

  test("no holder: the lock is taken at once whatever the wait (an Infinity wait never fires early)", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "lock-")));
    expect(await withWorkspaceGitLock(ws, async () => "x", { waitMs: 0 })).toBe("x");
    const order: string[] = [];
    const a = withWorkspaceGitLock(ws, hold(30, order, "a"));
    expect(await withWorkspaceGitLock(ws, hold(1, order, "b"), { waitMs: Number.POSITIVE_INFINITY })).toBe("b");
    await a;
    expect(order).toEqual(["a:start", "a:end", "b:start", "b:end"]);
  });
});
