// `runIsolatedGitLocal` / `verifyObject` against the real git binary (#12600, plan Phase 1.2; probe8.sh shape).
// Synthesized fixtures only. The isolated directory is the real creator's, so the runner gets the real hardened env.
import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";
import { createIsolatedPushDir, type IsolatedPushDirHandle } from "../server/git-isolated-push-dir";
import { runIsolatedGitLocal, verifyObject } from "../server/git-isolated-local";

const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8", env: gitFixtureEnv(cwd) }).trim();

describe("git-isolated-local (real git)", () => {
  let root: string;
  let ws: string;
  let iso: IsolatedPushDirHandle;
  const saved: Record<string, string | undefined> = {};

  beforeEach(() => {
    for (const k of ["HOME", "TMPDIR"]) saved[k] = process.env[k];
    root = realpathSync(mkdtempSync(join(tmpdir(), "iso-local-")));
    mkdirSync(join(root, "home"));
    mkdirSync(join(root, "tmp"));
    process.env.HOME = join(root, "home");
    process.env.TMPDIR = join(root, "tmp");
    ws = join(root, "ws");
    mkdirSync(ws);
    git(ws, "init", "-q", "-b", "main");
    writeFileSync(join(ws, "a.txt"), "a\n");
    git(ws, "add", "-A");
    git(ws, "commit", "-q", "-m", "T");
    writeFileSync(join(ws, "a.txt"), "b\n");
    git(ws, "commit", "-q", "-am", "F");
    iso = createIsolatedPushDir(ws);
  });

  afterEach(() => {
    iso?.dispose();
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
    rmSync(root, { recursive: true, force: true });
  });

  test("runs in the isolated dir with the workspace objects as the alternate, exit codes surfaced", async () => {
    const head = git(ws, "rev-parse", "HEAD");
    const ok = await runIsolatedGitLocal(iso, ["rev-parse", "--verify", "--quiet", `${head}^{commit}`]);
    expect(ok.code).toBe(0);
    expect(ok.stdout.toString().trim()).toBe(head);
    const absent = await runIsolatedGitLocal(iso, ["rev-parse", "--verify", "--quiet", `${"1".repeat(40)}^{commit}`]);
    expect(absent.code).toBe(1);
    // no workspace ref is visible: the isolated dir has its own (empty) refs
    const refs = await runIsolatedGitLocal(iso, ["for-each-ref"]);
    expect(refs.code).toBe(0);
    expect(refs.stdout.toString()).toBe("");
  });

  test("stdin input reaches the child", async () => {
    const r = await runIsolatedGitLocal(iso, ["hash-object", "--stdin"], { input: Buffer.from("x\n") });
    expect(r.code).toBe(0);
    const expected = execFileSync("git", ["hash-object", "--stdin"], { cwd: ws, input: "x\n", encoding: "utf8", env: gitFixtureEnv(ws) }).trim();
    expect(r.stdout.toString().trim()).toBe(expected);
  });

  test("verifyObject returns the bytes of a genuine object and null for a forged loose one", async () => {
    const tTree = git(ws, "rev-parse", "HEAD~1^{tree}");
    const fTree = git(ws, "rev-parse", "HEAD^{tree}");
    const T = git(ws, "rev-parse", "HEAD~1");
    expect(await verifyObject(iso, "commit", T)).not.toBeNull();
    const bytes = await verifyObject(iso, "tree", tTree);
    expect(bytes?.includes(Buffer.from("a.txt\0"))).toBe(true);
    // forge: T's tree file now holds F's tree bytes (loose objects in a fresh non-gc'd repo)
    const objects = join(ws, ".git", "objects");
    const dst = join(objects, tTree.slice(0, 2), tTree.slice(2));
    chmodSync(dst, 0o644);
    cpSync(join(objects, fTree.slice(0, 2), fTree.slice(2)), dst);
    expect(await verifyObject(iso, "tree", tTree)).toBeNull();
    expect(await verifyObject(iso, "tree", "not-a-sha")).toBeNull();
  });
});
