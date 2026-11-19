// `runIsolatedGitLocal` / `verifyObject` against the real git binary (#12600, plan Phase 1.2; probe8.sh shape).
// Synthesized fixtures only. The isolated directory is the real creator's, so the runner gets the real hardened env.
import { execFileSync } from "node:child_process";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";
import { createIsolatedPushDir, type IsolatedPushDirHandle } from "../server/git-isolated-push-dir";
import { gitObjectId, runIsolatedGitLocal, verifyObject } from "../server/git-isolated-local";
import { HARDENED_GIT_ARGS } from "../server/git-hardened-env";

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
    expect((await verifyObject(iso, "commit", T)).kind).toBe("verified");
    const v = await verifyObject(iso, "tree", tTree);
    expect(v.kind === "verified" && v.bytes.includes(Buffer.from("a.txt\0"))).toBe(true);
    // forge: T's tree file now holds F's tree bytes (loose objects in a fresh non-gc'd repo)
    const objects = join(ws, ".git", "objects");
    const dst = join(objects, tTree.slice(0, 2), tTree.slice(2));
    chmodSync(dst, 0o644);
    cpSync(join(objects, fTree.slice(0, 2), fTree.slice(2)), dst);
    expect(await verifyObject(iso, "tree", tTree)).toEqual({ kind: "unverified" });
    expect(await verifyObject(iso, "tree", "not-a-sha")).toEqual({ kind: "unverified" });
    // absent: git read nothing (unverified), not a runner failure
    expect(await verifyObject(iso, "commit", "1".repeat(40))).toEqual({ kind: "unverified" });
  });

  test("verifyObject hashes in-process: the id matches git's own hash-object for commit, tree and blob", async () => {
    const T = git(ws, "rev-parse", "HEAD");
    for (const [type, id] of [["commit", T], ["tree", git(ws, "rev-parse", "HEAD^{tree}")], ["blob", git(ws, "rev-parse", "HEAD:a.txt")]] as const) {
      const v = await verifyObject(iso, type, id);
      expect(v.kind, type).toBe("verified");
      if (v.kind === "verified") expect(gitObjectId(type, v.bytes)).toBe(id);
    }
  });

  test("verifyObject is tri-state: a child that cannot run (git not on PATH) is failed, never unverified", async () => {
    const T = git(ws, "rev-parse", "HEAD");
    const savedPath = process.env.PATH;
    process.env.PATH = join(root, "no-git-here");
    try {
      expect(await verifyObject(iso, "commit", T)).toEqual({ kind: "failed" });
    } finally {
      process.env.PATH = savedPath;
    }
    expect((await verifyObject(iso, "commit", T)).kind).toBe("verified");
  });

  test("the stdout cap is injectable (maxBufferBytes) and an exceeded cap is code -1", async () => {
    const big = execFileSync("git", ["hash-object", "-w", "--stdin"], { cwd: ws, input: Buffer.alloc(2 * 1024 * 1024, 7), encoding: "utf8", env: gitFixtureEnv(ws) }).trim();
    expect((await runIsolatedGitLocal(iso, ["cat-file", "blob", big], { maxBufferBytes: 1024 })).code).toBe(-1);
    expect((await runIsolatedGitLocal(iso, ["cat-file", "blob", big])).code).toBe(0);
  });

  test("the isolated runner applies every HARDENED_GIT_ARGS -c pair (read back with git config)", async () => {
    const pairs: Array<[string, string]> = [];
    for (let i = 0; i < HARDENED_GIT_ARGS.length; i++) {
      if (HARDENED_GIT_ARGS[i] !== "-c") continue;
      const kv = HARDENED_GIT_ARGS[i + 1];
      const eq = kv.indexOf("=");
      pairs.push([kv.slice(0, eq), kv.slice(eq + 1)]);
    }
    expect(pairs.map(([k]) => k)).toEqual(expect.arrayContaining(["core.alternateRefsCommand", "maintenance.auto", "core.hooksPath"]));
    for (const [k, v] of pairs) {
      const r = await runIsolatedGitLocal(iso, ["config", "--get", k]);
      expect(r.code, k).toBe(0);
      expect(r.stdout.toString().replace(/\n$/, ""), k).toBe(v);
    }
    // --no-replace-objects is a global option, not a config pair: a planted replace ref in the alternate is ignored
    expect(HARDENED_GIT_ARGS).toContain("--no-replace-objects");
  });
});
