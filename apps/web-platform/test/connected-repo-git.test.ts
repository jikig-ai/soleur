// Module rows for server/connected-repo-git.ts (review fix round 1, WP1: rulings D35, D36, D37(1)(2), D38(1)(6)).
//
// - The argv guard: exactly the two pinned merge shapes (D37(2)), the four new read/pin shapes (D35, D36(a)(c)), each
//   accepted exactly and refused in every variant.
// - The pull writer over REAL git: a stale `MERGE_AUTOSTASH` refuses `in_progress` before any merge child and pins the
//   autostash commit under `refs/soleur/autostash/` (TX4-h, D36(c), D37(1)); the pin reads only a small regular file.
// - The async runner rejects with git's exit status and stderr, and the same-host lock serializes one workspace.
// Synthesized data only (cq-test-fixtures-synthesized-only).
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
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

  test("a MERGE_HEAD next to MERGE_AUTOSTASH (a content conflict) is in_progress and pins nothing", async () => {
    const { ws, T } = repo();
    staleAutostash(ws);
    writeFileSync(join(ws, ".git", "MERGE_HEAD"), `${T}\n`);
    expect(await kbPullWriter(ws).merge(T)).toBe("in_progress");
    expect(pins(ws)).toBe("");
  });

  test.each([
    ["a symlink", (ws: string, sha: string) => {
      writeFileSync(join(ws, "target"), `${sha}\n`);
      symlinkSync(join(ws, "target"), join(ws, ".git", "MERGE_AUTOSTASH"));
    }, "not_regular"],
    ["a file over 64 bytes", (ws: string, sha: string) => writeFileSync(join(ws, ".git", "MERGE_AUTOSTASH"), `${sha}\n${"x".repeat(64)}\n`), "too_large"],
    ["a first line that is not 40 hex", (ws: string) => writeFileSync(join(ws, ".git", "MERGE_AUTOSTASH"), "refs/heads/main\n"), "malformed"],
    ["a directory", (ws: string) => mkdirSync(join(ws, ".git", "MERGE_AUTOSTASH")), "not_regular"],
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
