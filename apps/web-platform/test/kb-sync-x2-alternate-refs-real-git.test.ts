// X2 real-git row (#12600, CTO ruling X2, measured F1; D13): a token-bearing `fetch` from the isolated directory spawns NO
// `for-each-ref` child in the agent-writable workspace `.git`, so agent-planted refs never become `have` lines.
//
// Observable effect, not an argv pin: the workspace holds commit X (on its own `main`, and as an agent-planted ref), the
// remote's `main` is Y (a child of X). git's default alternate-refs child would list X from the workspace refs and send it
// as a `have`, so the server would send only Y's new objects. With `core.alternateRefsCommand=true` (HARDENED_GIT_ARGS) no
// workspace ref is read: nothing is advertised as a `have` and the server sends every object reachable from Y, X's included.
// The control row runs the same fetch with the setting overridden back to git's default child and shows the difference,
// so the instrument can tell the two apart. The token is synthesized; the remote is a local bare `file://` repo.
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";

const H = vi.hoisted(() => ({ hardenedArgs: [] as string[], pristine: [] as string[] }));

vi.mock("@/server/github-app", () => ({ generateInstallationToken: async () => ["ghs", "_", "x".repeat(40)].join("") }));
vi.mock("@/server/logger", () => {
  const l = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() };
  return { default: l, createChildLogger: () => l };
});
// Test-only seams on the builder's RESULT: the production clamp is `https` (the fixture remote is file://), and
// `transfer.unpackLimit=1` keeps the received pack as a pack (unpack-objects would skip every object the alternate already
// has, hiding what the server sent). The control row edits the SAME HARDENED_GIT_ARGS array git-auth spreads per call.
vi.mock("@/server/git-hardened-env", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/git-hardened-env")>();
  H.pristine = [...actual.HARDENED_GIT_ARGS];
  H.hardenedArgs = [...actual.HARDENED_GIT_ARGS];
  return {
    ...actual,
    HARDENED_GIT_ARGS: H.hardenedArgs,
    buildIsolatedGitEnv: (dir: import("@/server/git-hardened-env").IsolatedPushDir, extra: Readonly<Record<string, string>> = {}) => ({
      ...actual.buildIsolatedGitEnv(dir, extra),
      GIT_ALLOW_PROTOCOL: "https:file",
      GIT_CONFIG_COUNT: "1",
      GIT_CONFIG_KEY_0: "transfer.unpackLimit",
      GIT_CONFIG_VALUE_0: "1",
    }),
  };
});

import { gitWithInstallationAuth } from "@/server/git-auth";
import { createIsolatedPushDir, type IsolatedPushDirHandle } from "@/server/git-isolated-push-dir";

const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8", env: gitFixtureEnv(cwd) }).trim();

/** Objects in the isolated directory's OWN store (loose + packed), alternates excluded. */
function ownObjectCount(iso: IsolatedPushDirHandle): number {
  const out = execFileSync("git", ["count-objects", "-v"], { encoding: "utf8", env: { PATH: process.env.PATH ?? "", GIT_DIR: iso.gitDir, GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null" } });
  const field = (k: string): number => Number(out.match(new RegExp(`^${k}: (\\d+)$`, "m"))?.[1] ?? "0");
  return field("count") + field("in-pack");
}

describe("X2: the hardened fetch reads no workspace ref (real git)", { timeout: 30_000 }, () => {
  let root: string;
  let remote: string;
  let ws: string;
  let iso: IsolatedPushDirHandle | undefined;
  const saved: Record<string, string | undefined> = {};

  beforeEach(() => {
    for (const k of ["HOME", "TMPDIR"]) saved[k] = process.env[k];
    H.hardenedArgs.splice(0, H.hardenedArgs.length, ...H.pristine);
    root = realpathSync(mkdtempSync(join(tmpdir(), "x2-")));
    mkdirSync(join(root, "home"));
    mkdirSync(join(root, "tmp"));
    process.env.HOME = join(root, "home");
    process.env.TMPDIR = join(root, "tmp");
    remote = join(root, "remote.git");
    execFileSync("git", ["init", "-q", "--bare", "-b", "main", remote], { env: gitFixtureEnv(root) });
    const seed = join(root, "seed");
    mkdirSync(seed);
    git(seed, "init", "-q", "-b", "main");
    for (let i = 0; i < 6; i++) writeFileSync(join(seed, `f${i}.md`), `file ${i}\n`);
    git(seed, "add", "-A");
    git(seed, "commit", "-q", "-m", "X");
    git(seed, "push", "-q", remote, "main");
    ws = join(root, "ws");
    execFileSync("git", ["clone", "-q", `file://${remote}`, ws], { env: gitFixtureEnv(root), stdio: "pipe" });
    // an agent-planted ref naming X, besides the clone's own refs
    git(ws, "update-ref", "refs/planted/x", git(ws, "rev-parse", "HEAD"));
    writeFileSync(join(seed, "y.md"), "y\n");
    git(seed, "add", "-A");
    git(seed, "commit", "-q", "-m", "Y");
    git(seed, "push", "-q", remote, "main");
  });

  afterEach(() => {
    iso?.dispose();
    iso = undefined;
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
    rmSync(root, { recursive: true, force: true });
  });

  const fetchY = async (): Promise<number> => {
    iso = createIsolatedPushDir(ws);
    await gitWithInstallationAuth(["fetch", "--no-tags", `file://${remote}`, "refs/heads/main"], 1, { hardened: iso, timeout: 20_000 });
    return ownObjectCount(iso);
  };

  test("hardened: no have line from the workspace, so X's objects are fetched too (Y commit+tree+blob, X commit+tree+6 blobs)", async () => {
    expect(H.hardenedArgs).toContain("core.alternateRefsCommand=true");
    expect(await fetchY()).toBe(11);
  });

  test("control: without the setting, git's default child reads the workspace refs, X is a have, and X's objects are not sent", async () => {
    const i = H.hardenedArgs.indexOf("core.alternateRefsCommand=true");
    H.hardenedArgs.splice(i - 1, 2);
    // Y's commit, tree and blob (git may add one more object to the kept pack); never X's 8
    expect(await fetchY()).toBeLessThanOrEqual(4);
  });
});
