// End-to-end: the remote URL the app builds (server/git-data-replication.ts) through REAL git and
// the REAL transport wrapper (infra/git-data-transport-wrapper.sh). #8211, ADR-239.
//
// Why this exists: the app built an ssh:// URL whose path was `/repositories/<id>.git`. Git sends an
// ssh:// path to the server unchanged and ABSOLUTE, so the wrapper ran `readlink -f '/repositories/<id>.git'`,
// got nothing and refused every fetch and push (rehearsal 2, 2026-10-27). Every existing check
// tested one endpoint: the wrapper suite fed hand-written paths under its fixture root, the app
// suites pinned the URL string, and the container probe dials its own constant. Nothing ran git's
// real emission through the real wrapper.
//
// Harness: a shim named `ssh` (any other name makes git send an `ssh -G` capability probe first)
// records the remote command git emitted, path-maps the literal bare-repo root onto a fixture root
// (CI has no /mnt/git-data), and execs the REAL wrapper under `env -i` with the test seams. The
// literal equality of the app prefix with the wrapper / provision / remove / cutover / cloud-init
// defaults is R-PARITY, so the path-mapping cannot hide a drifted prefix.

import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";

// The three mocks importing server/git-data-replication.ts needs; node:child_process stays REAL.
vi.mock("../server/git-auth", () => ({
  gitWithPrivateKeyAuth: vi.fn(),
  sshWithPrivateKeyAuth: vi.fn(),
}));
vi.mock("../server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: async () => ({ data: true, error: null }) })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

import { ensureGitDataRemote, gitDataRemoteUrl } from "../server/git-data-replication";

const APP_ROOT = resolve(__dirname, "..");
const INFRA = join(APP_ROOT, "infra");
const WRAPPER = join(INFRA, "git-data-transport-wrapper.sh");
const APP_TS = join(APP_ROOT, "server", "git-data-replication.ts");

const WS = "11111111-1111-4111-8111-111111111111";
const WT = "55555555-5555-4555-8555-555555555555";
const STORE_PREFIX = "/mnt/git-data/repositories";
// The pre-fix prefix (the incident). Spelled as a constant so the residual-URL sweep stays empty.
const OLD_PREFIX = "/repositories";

const read = (p: string) => readFileSync(p, "utf8");

/** Environment for every git child: no ambient GIT_* (a caller's GIT_DIR beats cwd), fixed identity. */
function cleanEnv(extra: Record<string, string> = {}): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (!k.startsWith("GIT_") && v !== undefined) env[k] = v;
  }
  return {
    ...env,
    GIT_AUTHOR_NAME: "t",
    GIT_AUTHOR_EMAIL: "t@example.invalid",
    GIT_COMMITTER_NAME: "t",
    GIT_COMMITTER_EMAIL: "t@example.invalid",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    ...extra,
  };
}

function git(cwd: string, args: string[], env: Record<string, string> = cleanEnv()) {
  return spawnSync("git", args, { cwd, env: env as NodeJS.ProcessEnv, encoding: "utf8" });
}

/** Exactly one match or a loud failure: a zero-match extraction must never pass silently. */
function extractOne(label: string, text: string, re: RegExp): string {
  const g = new RegExp(re.source, re.flags.includes("g") ? re.flags : `${re.flags}g`);
  const hits = [...text.matchAll(g)];
  if (hits.length !== 1) {
    throw new Error(`${label}: expected exactly one match for ${re}, got ${hits.length}`);
  }
  return hits[0][1];
}

let root: string;
let storeDir: string; // <root>/store/repositories
let work: string;
let dialLog: string;
let shimDir: string;
let seamEnv: Record<string, string>;

function dialedCommands(): string[] {
  try {
    return read(dialLog).split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

function transportEnv(): Record<string, string> {
  return cleanEnv({
    GIT_SSH_COMMAND: join(shimDir, "ssh"),
    ...seamEnv,
  });
}

function makeBare(id: string): string {
  const bare = join(storeDir, `${id}.git`);
  mkdirSync(storeDir, { recursive: true });
  const r = git(storeDir, ["init", "--bare", "-q", bare]);
  expect(r.status, r.stderr).toBe(0);
  expect(git(bare, ["symbolic-ref", "HEAD", "refs/heads/main"]).status).toBe(0);
  // Production gets this from the bootstrap's system config; without it `--push-option` fails with
  // "the receiving end does not support push options".
  expect(git(bare, ["config", "receive.advertisePushOptions", "true"]).status).toBe(0);
  return bare;
}

function makeClone(name: string): string {
  const dir = join(work, name);
  mkdirSync(dir, { recursive: true });
  expect(git(dir, ["init", "-q"]).status).toBe(0);
  expect(git(dir, ["symbolic-ref", "HEAD", "refs/heads/main"]).status).toBe(0);
  expect(git(dir, ["commit", "-q", "--allow-empty", "-m", "one"]).status).toBe(0);
  expect(git(dir, ["tag", "v1"]).status).toBe(0);
  return dir;
}

beforeAll(() => {
  // Hard preconditions: fail loud, never skip.
  for (const bin of ["git", "bash", "findmnt", "mountpoint", "stat", "readlink"]) {
    const r = spawnSync("bash", ["-c", `command -v ${bin}`], { encoding: "utf8" });
    if (r.status !== 0) throw new Error(`precondition: ${bin} is not on PATH`);
  }
  root = mkdtempSync(join(tmpdir(), "gdurl-"));
  work = join(root, "work");
  shimDir = join(root, "bin");
  storeDir = join(root, "store", "repositories");
  mkdirSync(work, { recursive: true });
  mkdirSync(shimDir, { recursive: true });
  mkdirSync(storeDir, { recursive: true });
  dialLog = join(root, "dialed.log");

  const mount = execFileSync("stat", ["-c", "%m", storeDir], { encoding: "utf8" }).trim();
  const dev = spawnSync("findmnt", ["-n", "-o", "SOURCE", "--mountpoint", mount], {
    encoding: "utf8",
  }).stdout.trim();
  if (!dev) throw new Error(`precondition: findmnt prints no SOURCE for ${mount}`);
  const realUuid = spawnSync("findmnt", ["-n", "-o", "UUID", "--mountpoint", mount], {
    encoding: "utf8",
  }).stdout.trim();
  const uuid = realUuid || "0b1d0000-8211-4000-8000-000000000002";

  // findmnt stub answering ONLY the UUID query (tmpfs has no filesystem UUID); everything else is
  // delegated to the real binary.
  const fmReal = execFileSync("bash", ["-c", "command -v findmnt"], { encoding: "utf8" }).trim();
  const stubDir = join(root, "fm");
  mkdirSync(stubDir, { recursive: true });
  writeFileSync(
    join(stubDir, "findmnt"),
    [
      "#!/usr/bin/env bash",
      `if [ "$#" = 5 ] && [ "$1 $2 $3 $4" = "-n -o UUID --mountpoint" ] && [ "$5" = "${mount}" ]; then`,
      `  printf '%s\\n' '${uuid}'; exit 0`,
      "fi",
      `exec "${fmReal}" "$@"`,
      "",
    ].join("\n"),
  );
  chmodSync(join(stubDir, "findmnt"), 0o755);
  const marker = join(root, "store-verified");
  writeFileSync(marker, `${uuid}\n`);
  const hooks = join(root, "hooks");
  mkdirSync(hooks, { recursive: true });

  // The shim: LAST argv is the remote command git emitted.
  writeFileSync(
    join(shimDir, "ssh"),
    [
      "#!/usr/bin/env bash",
      "for last; do :; done",
      'printf \'%s\\n\' "$last" >> "$DIAL_LOG"',
      'cmd="${last//"$DIAL_PREFIX"/"$DIAL_ROOT"}"',
      'exec env -i PATH="$DIAL_PATH" HOME="$DIAL_HOME" GIT_DATA_REPO_ROOT="$DIAL_ROOT" \\',
      '  GIT_DATA_MOUNT_ROOT="$DIAL_MOUNT" GIT_DATA_HOOKS_DIR="$DIAL_HOOKS" \\',
      '  GIT_DATA_STORE_DEVICE="$DIAL_DEV" GIT_DATA_STORE_VERIFIED="$DIAL_MARKER" \\',
      '  SSH_ORIGINAL_COMMAND="$cmd" bash "$DIAL_WRAPPER"',
      "",
    ].join("\n"),
  );
  chmodSync(join(shimDir, "ssh"), 0o755);

  seamEnv = {
    DIAL_LOG: dialLog,
    DIAL_PREFIX: STORE_PREFIX,
    DIAL_ROOT: storeDir,
    DIAL_PATH: `${stubDir}:${process.env.PATH ?? ""}`,
    DIAL_HOME: root,
    DIAL_MOUNT: mount,
    DIAL_HOOKS: hooks,
    DIAL_DEV: dev,
    DIAL_MARKER: marker,
    DIAL_WRAPPER: WRAPPER,
  };
});

afterAll(() => {
  if (root && root.startsWith(tmpdir())) rmSync(root, { recursive: true, force: true });
});

beforeEach(() => {
  rmSync(dialLog, { force: true });
  vi.stubEnv("GIT_DATA_SSH_HOST", "10.0.1.20");
  vi.stubEnv("GIT_DATA_SSH_HOST_KEY", makeEd25519Pin());
  vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
});

describe("R-URL: the URL the app builds", () => {
  it("is the absolute bare-repo path under the git-data store, for a UUID and for a ws-* id", () => {
    expect(gitDataRemoteUrl(WS)).toBe(`ssh://git@10.0.1.20${STORE_PREFIX}/${WS}.git`);
    expect(gitDataRemoteUrl("ws-uuid-123")).toBe(
      `ssh://git@10.0.1.20${STORE_PREFIX}/ws-uuid-123.git`,
    );
  });
});

describe("R-PUSH / R-FETCH / R-STALE: real git -> real wrapper", () => {
  it("R-PUSH: the production push shape lands refs only under the worktree namespace", () => {
    const bare = makeBare(WS);
    const clone = makeClone("push");
    ensureGitDataRemote(clone, WS);
    expect(git(clone, ["remote", "get-url", "git-data"]).stdout.trim()).toBe(gitDataRemoteUrl(WS));

    const push = git(
      clone,
      [
        "push",
        "--force",
        "git-data",
        `refs/heads/*:refs/soleur/worktrees/${WT}/heads/*`,
        `refs/tags/*:refs/soleur/worktrees/${WT}/tags/*`,
        "--push-option=lease-gen=1",
        `--push-option=worktree-id=${WT}`,
      ],
      transportEnv(),
    );
    expect(push.status, push.stderr).toBe(0);

    const dialed = dialedCommands().filter((c) => c.startsWith("git-receive-pack "));
    expect(dialed).toContain(`git-receive-pack '${STORE_PREFIX}/${WS}.git'`);

    const sha = git(clone, ["rev-parse", "refs/heads/main"]).stdout.trim();
    const tagSha = git(clone, ["rev-parse", "refs/tags/v1"]).stdout.trim();
    const refs = git(bare, ["for-each-ref", "--format=%(refname) %(objectname)"])
      .stdout.trim()
      .split("\n")
      .sort();
    expect(refs).toEqual(
      [
        `refs/soleur/worktrees/${WT}/heads/main ${sha}`,
        `refs/soleur/worktrees/${WT}/tags/v1 ${tagSha}`,
      ].sort(),
    );
  });

  it("R-FETCH: the explicit fetch URL (the session-start graft) round-trips the pushed ref", () => {
    makeBare(WS);
    const pusher = makeClone("pusher");
    ensureGitDataRemote(pusher, WS);
    const push = git(
      pusher,
      ["push", "--force", "git-data", `refs/heads/*:refs/soleur/worktrees/${WT}/heads/*`],
      transportEnv(),
    );
    expect(push.status, push.stderr).toBe(0);

    const fetcher = makeClone("fetcher");
    rmSync(dialLog, { force: true });
    const fetched = git(
      fetcher,
      [
        "fetch",
        gitDataRemoteUrl(WS),
        `+refs/soleur/worktrees/${WT}/heads/*:refs/remotes/git-data/*`,
      ],
      transportEnv(),
    );
    expect(fetched.status, fetched.stderr).toBe(0);
    expect(dialedCommands()).toContain(`git-upload-pack '${STORE_PREFIX}/${WS}.git'`);
    expect(git(fetcher, ["rev-parse", "refs/remotes/git-data/main"]).stdout.trim()).toBe(
      git(pusher, ["rev-parse", "refs/heads/main"]).stdout.trim(),
    );
  });

  it("R-STALE: a clone holding the old /repositories remote is re-pointed on the next ensure", () => {
    const clone = makeClone("stale");
    const oldUrl = `ssh://git@10.0.1.20${OLD_PREFIX}/${WS}.git`;
    expect(git(clone, ["remote", "add", "git-data", oldUrl]).status).toBe(0);
    ensureGitDataRemote(clone, WS);
    expect(git(clone, ["remote", "get-url", "git-data"]).stdout.trim()).toBe(gitDataRemoteUrl(WS));
  });

  it("the OLD form is refused with the incident's message (the control that gives the rows teeth)", () => {
    makeBare(WS);
    const clone = makeClone("old");
    const r = git(
      clone,
      ["push", "--force", `ssh://git@10.0.1.20${OLD_PREFIX}/${WS}.git`, "refs/heads/*:refs/x/*"],
      transportEnv(),
    );
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain(`repo path does not resolve: '${OLD_PREFIX}/${WS}.git'`);
    expect(dialedCommands().some((c) => c === `git-receive-pack '${OLD_PREFIX}/${WS}.git'`)).toBe(
      true,
    );
  });
});

describe("R-PARITY: the app prefix is the bare-repo root every host-side consumer uses", () => {
  const appPrefix = () =>
    extractOne(
      "app GIT_DATA_REPO_PATH_PREFIX",
      read(APP_TS),
      /^const GIT_DATA_REPO_PATH_PREFIX = "([^"]+)";$/m,
    );
  const defaultOf = (file: string) =>
    extractOne(
      `${file} REPO_ROOT default`,
      read(join(INFRA, file)),
      /^REPO_ROOT="\$\{GIT_DATA_REPO_ROOT:-([^}]+)\}"$/m,
    );

  it("equals the default REPO_ROOT of the wrapper, provision and remove scripts", () => {
    const prefix = appPrefix();
    expect(prefix).toBe(STORE_PREFIX);
    expect(defaultOf("git-data-transport-wrapper.sh")).toBe(prefix);
    expect(defaultOf("git-data-provision.sh")).toBe(prefix);
    expect(defaultOf("git-data-remove.sh")).toBe(prefix);
  });

  it("equals the cutover script's OLD_ROOT + REPO_SUBDIR composition", () => {
    const cutover = read(join(INFRA, "git-data-cutover.sh"));
    const oldRoot = extractOne("OLD_ROOT default", cutover, /^OLD_ROOT="\$\{OLD_ROOT:-([^}]+)\}"/m);
    const subdir = extractOne(
      "REPO_SUBDIR default",
      cutover,
      /^REPO_SUBDIR="\$\{REPO_SUBDIR:-([^}]+)\}"/m,
    );
    expect(`${oldRoot}/${subdir}`).toBe(appPrefix());
  });

  it("equals the host's mount literal in cloud-init joined with /repositories", () => {
    const cloud = read(join(INFRA, "cloud-init-git-data.yml"));
    const mount = extractOne("cloud-init mkdir -p", cloud, /^ {2}- mkdir -p (\/mnt\/git-data)$/m);
    expect(`${mount}/repositories`).toBe(appPrefix());
  });
});
