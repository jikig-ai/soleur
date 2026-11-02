// Integration (local subprocess): the remote URL the app builds (server/git-data-replication.ts)
// through REAL git and the REAL transport wrapper (infra/git-data-transport-wrapper.sh). #8211,
// ADR-239.
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
// literal equality of the app prefix with the host-side literals (wrapper, provision, remove, gc,
// bootstrap, container probe, cutover, cloud-init mount and log redaction) is R-PARITY, so the
// path-mapping cannot hide a drifted prefix. R-PARITY pins DECLARATIONS, not use sites.

import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";
import {
  gitFixtureEnv,
  GIT_LOCATION_VARS,
} from "../../../plugins/soleur/test/lib/git-fixture-env";

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
import { fetchFromGitData } from "../server/git-data-client";
import { gitWithPrivateKeyAuth } from "../server/git-auth";

const APP_ROOT = resolve(__dirname, "..");
const INFRA = join(APP_ROOT, "infra");
const WRAPPER = join(INFRA, "git-data-transport-wrapper.sh");
const APP_TS = join(APP_ROOT, "server", "git-data-replication.ts");

const WS = "11111111-1111-4111-8111-111111111111";
const WT = "55555555-5555-4555-8555-555555555555";
const USER = "77777777-7777-4777-8777-777777777777";
const STORE_PREFIX = "/mnt/git-data/repositories";
// The pre-fix prefix (the incident), used only by the negative control and R-STALE.
const OLD_PREFIX = "/repositories";

const read = (p: string) => readFileSync(p, "utf8");

/**
 * Environment for every child process this file spawns (git above all): the shared fixture builder (prefix sweep of ambient GIT_*, a
 * discovery ceiling, config hermeticity, a synthesized identity) plus fixed commit dates so the
 * commit ids a test creates do not depend on the wall clock.
 */
function cleanEnv(extra: Record<string, string> = {}): NodeJS.ProcessEnv {
  return {
    ...gitFixtureEnv(root),
    GIT_AUTHOR_DATE: "2026-01-01T00:00:00Z",
    GIT_COMMITTER_DATE: "2026-01-01T00:00:00Z",
    ...extra,
  };
}

function git(cwd: string, args: string[], env: NodeJS.ProcessEnv = cleanEnv()) {
  return spawnSync("git", args, { cwd, env, encoding: "utf8" });
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

function transportEnv(): NodeJS.ProcessEnv {
  return cleanEnv({
    GIT_SSH_COMMAND: join(shimDir, "ssh"),
    ...seamEnv,
  });
}

function makeBare(id: string): string {
  const bare = join(storeDir, `${id}.git`);
  // A fresh store per test: a leftover ref from an earlier test would let a later fetch pass on
  // state its own push never wrote.
  rmSync(bare, { recursive: true, force: true });
  mkdirSync(storeDir, { recursive: true });
  const r = git(storeDir, ["init", "--bare", "-q", bare]);
  expect(r.status, r.stderr).toBe(0);
  expect(git(bare, ["symbolic-ref", "HEAD", "refs/heads/main"]).status).toBe(0);
  // Production gets this from the bootstrap's system config; without it `--push-option` fails with
  // "the receiving end does not support push options".
  expect(git(bare, ["config", "receive.advertisePushOptions", "true"]).status).toBe(0);
  return bare;
}

// The commit message is the clone's name, so two clones never share a commit id.
function makeClone(name: string): string {
  const dir = join(work, name);
  mkdirSync(dir, { recursive: true });
  expect(git(dir, ["init", "-q"]).status).toBe(0);
  expect(git(dir, ["symbolic-ref", "HEAD", "refs/heads/main"]).status).toBe(0);
  expect(git(dir, ["commit", "-q", "--allow-empty", "-m", name]).status).toBe(0);
  expect(git(dir, ["tag", "v1"]).status).toBe(0);
  return dir;
}

// (#8211 fix-forward 2) The app's workspace clones are ALWAYS `git clone --depth 1`
// (ensure-workspace-repo.ts), so the store must accept pushes whose history bottoms out
// at the client's shallow boundary, and the overlay fetch must accept a pack cut at the
// STORE's shallow boundary. A `file://` clone with --depth goes through the real transport
// (no hardlink shortcut), so the shallowness is real protocol state — asserted, because a
// full-clone fixture would let every shallow case pass vacuously (Guard-1 mutation row 5).
function makeShallowClone(name: string): string {
  const origin = join(work, `${name}-origin`);
  mkdirSync(origin, { recursive: true });
  expect(git(origin, ["init", "-q"]).status).toBe(0);
  expect(git(origin, ["symbolic-ref", "HEAD", "refs/heads/main"]).status).toBe(0);
  // >=3 commits so the clone's boundary actually truncates history.
  for (const m of ["a", "b", "c"]) {
    expect(git(origin, ["commit", "-q", "--allow-empty", "-m", `${name}-${m}`]).status).toBe(0);
  }
  const dir = join(work, name);
  const c = git(work, ["clone", "-q", "--depth", "1", `file://${origin}`, dir]);
  expect(c.status, c.stderr).toBe(0);
  expect(git(dir, ["rev-parse", "--is-shallow-repository"]).stdout.trim()).toBe("true");
  return dir;
}

beforeAll(() => {
  root = mkdtempSync(join(tmpdir(), "gdurl-"));
  // Hard preconditions: fail loud, never skip.
  for (const bin of ["git", "bash", "findmnt", "mountpoint", "stat", "readlink"]) {
    const r = spawnSync("bash", ["-c", `command -v ${bin}`], { encoding: "utf8", env: cleanEnv() });
    if (r.status !== 0) throw new Error(`precondition: ${bin} is not on PATH`);
  }
  work = join(root, "work");
  shimDir = join(root, "bin");
  storeDir = join(root, "store", "repositories");
  mkdirSync(work, { recursive: true });
  mkdirSync(shimDir, { recursive: true });
  mkdirSync(storeDir, { recursive: true });
  dialLog = join(root, "dialed.log");

  const mount = execFileSync("stat", ["-c", "%m", storeDir], {
    encoding: "utf8",
    env: cleanEnv(),
  }).trim();
  const dev = spawnSync("findmnt", ["-n", "-o", "SOURCE", "--mountpoint", mount], {
    encoding: "utf8",
    env: cleanEnv(),
  }).stdout.trim();
  if (!dev) throw new Error(`precondition: findmnt prints no SOURCE for ${mount}`);
  const realUuid = spawnSync("findmnt", ["-n", "-o", "UUID", "--mountpoint", mount], {
    encoding: "utf8",
    env: cleanEnv(),
  }).stdout.trim();
  const uuid = realUuid || "0b1d0000-8211-4000-8000-000000000002";

  // findmnt stub answering ONLY the UUID query (tmpfs has no filesystem UUID); everything else is
  // delegated to the real binary.
  const fmReal = execFileSync("bash", ["-c", "command -v findmnt"], {
    encoding: "utf8",
    env: cleanEnv(),
  }).trim();
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

afterEach(() => {
  vi.unstubAllEnvs();
});

beforeEach(() => {
  rmSync(dialLog, { force: true });
  // ensureGitDataRemote spawns git with the ambient environment: never let an inherited GIT_DIR
  // (or friends) aim its `remote add|set-url` at a repository that is not the fixture clone.
  for (const k of GIT_LOCATION_VARS) vi.stubEnv(k, undefined);
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

  it("R-PUSH-SHALLOW: a --depth 1 workspace clone's push is accepted by the store", () => {
    const bare = makeBare(WS);
    const shallow = makeShallowClone("shallow-push");
    ensureGitDataRemote(shallow, WS);
    // A session's work: the pushed tip is new, not just the cloned boundary.
    expect(git(shallow, ["commit", "-q", "--allow-empty", "-m", "session-work"]).status).toBe(0);
    const push = git(
      shallow,
      ["push", "--force", "git-data", `refs/heads/*:refs/soleur/worktrees/${WT}/heads/*`],
      transportEnv(),
    );
    expect(push.status, push.stderr).toBe(0);
    const sha = git(shallow, ["rev-parse", "refs/heads/main"]).stdout.trim();
    expect(
      git(bare, ["rev-parse", `refs/soleur/worktrees/${WT}/heads/main`]).stdout.trim(),
    ).toBe(sha);

    // Guard-1 mutation row 3: a second shallow clone, different origin and a different
    // worktree id — the flag rides the verb, never this fixture's identity.
    const WT2 = "66666666-6666-4666-8666-666666666666";
    const shallow2 = makeShallowClone("shallow-push-2");
    ensureGitDataRemote(shallow2, WS);
    const push2 = git(
      shallow2,
      ["push", "--force", "git-data", `refs/heads/*:refs/soleur/worktrees/${WT2}/heads/*`],
      transportEnv(),
    );
    expect(push2.status, push2.stderr).toBe(0);
    expect(
      git(bare, ["rev-parse", `refs/soleur/worktrees/${WT2}/heads/main`]).stdout.trim(),
    ).toBe(git(shallow2, ["rev-parse", "refs/heads/main"]).stdout.trim());
  });

  it("R-FETCH-OVERLAY: production fetchFromGitData lands git-data/* in a shallow clone when the store pack is boundary-cut", async () => {
    const bare = makeBare(WS);
    // The store is shallow because it accepted a shallow push — the state the
    // wrapper's `-c receive.shallowUpdate=true` produces. Seeded on the fixture
    // repo directly (the repo-local equivalent of the exec-time flag) so this
    // case's RED pins the FETCH argv, not the receive half — R-PUSH-SHALLOW
    // covers the receive half end-to-end through the real wrapper.
    expect(git(bare, ["config", "receive.shallowUpdate", "true"]).status).toBe(0);
    const pusher = makeShallowClone("overlay-pusher");
    expect(git(pusher, ["commit", "-q", "--allow-empty", "-m", "replicated-work"]).status).toBe(
      0,
    );
    const pushedSha = git(pusher, ["rev-parse", "refs/heads/main"]).stdout.trim();
    const seed = git(pusher, [
      "push",
      `file://${bare}`,
      `refs/heads/*:refs/soleur/worktrees/${WT}/heads/*`,
    ]);
    expect(seed.status, seed.stderr).toBe(0);
    // The fetcher is shallow too and holds NONE of the pushed objects (its own
    // origin), so the pack the store sends is cut at the store's shallow root —
    // the fetch must update .git/shallow, which git refuses without
    // --update-shallow (and it refuses QUIETLY: fetch exits 0 with the
    // `shallow roots are not allowed to be updated` warning and lands no ref).
    const fetcher = makeShallowClone("overlay-fetcher");

    vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", "transport-key");
    // Real-git passthrough of gitWithPrivateKeyAuth: the PRODUCTION argv
    // (fetchFromGitData's own flag order) drives a real `git fetch` through the
    // ssh shim into the REAL wrapper's upload-pack — a canned answer would leave
    // the ref-landing assertion unexercised (Guard-2 mutation row 5).
    const passthrough: typeof gitWithPrivateKeyAuth = async (args, _key, _pin, opts = {}) => {
      const r = spawnSync("git", args, {
        cwd: opts.cwd,
        env: transportEnv(),
        encoding: "utf8",
      });
      if (r.status !== 0) {
        throw Object.assign(new Error(`git ${args[0]} exited ${r.status}: ${r.stderr}`), {
          stderr: r.stderr,
        });
      }
      return Buffer.from(r.stdout ?? "");
    };
    vi.mocked(gitWithPrivateKeyAuth).mockImplementation(passthrough);

    await fetchFromGitData({
      userId: USER,
      workspaceId: WS,
      worktreeId: WT,
      workspacePath: fetcher,
    });
    expect(git(fetcher, ["rev-parse", "refs/remotes/git-data/main"]).stdout.trim()).toBe(
      pushedSha,
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
    // The refusal is only reproducible where /repositories is absent, as on the git-data host.
    expect(existsSync(OLD_PREFIX)).toBe(false);
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

  it("equals the default REPO_ROOT of the wrapper, provision, remove and gc scripts", () => {
    const prefix = appPrefix();
    expect(prefix).toBe(STORE_PREFIX);
    expect(defaultOf("git-data-transport-wrapper.sh")).toBe(prefix);
    expect(defaultOf("git-data-provision.sh")).toBe(prefix);
    expect(defaultOf("git-data-remove.sh")).toBe(prefix);
    expect(defaultOf("git-data-gc.sh")).toBe(prefix);
  });

  it("equals the bootstrap's own writer of the directory and the container probe's default", () => {
    const prefix = appPrefix();
    const bootstrap = read(join(INFRA, "git-data-bootstrap.sh"));
    const dataRoot = extractOne(
      "bootstrap GIT_DATA_ROOT",
      bootstrap,
      /^GIT_DATA_ROOT="([^"$]+)"[ \t]*(#.*)?$/m,
    );
    const sub = extractOne(
      "bootstrap REPO_ROOT",
      bootstrap,
      /^REPO_ROOT="\$GIT_DATA_ROOT(\/[^"]+)"[ \t]*(#.*)?$/m,
    );
    expect(`${dataRoot}${sub}`).toBe(prefix);
    const probe = extractOne(
      "container probe repo_root default",
      read(join(INFRA, "git-data-container-probe.sh")),
      /^repo_root="\$\{GDCP_REPO_ROOT:-([^}]+)\}"[ \t]*(#.*)?$/m,
    );
    expect(probe).toBe(prefix);
  });

  it("is the path the host's log redaction matches and rewrites to REDACTED", () => {
    const cloud = read(join(INFRA, "cloud-init-git-data.yml"));
    const redacted = extractOne(
      "cloud-init redaction target",
      cloud,
      /#(\/mnt\/git-data\/repositories)\/REDACTED#g/,
    );
    expect(redacted).toBe(appPrefix());
    // The match side decides what is redacted; pin it too (the optional -luks group is the
    // pre-cutover store path and is not part of the comparison).
    const matchSide = extractOne(
      "cloud-init redaction match side",
      cloud,
      /s#(\/mnt\/git-data[^#\n]*?\/repositories)\/\[\^\[:space:\]\]\*#/,
    );
    expect(matchSide.replace("\\(-luks\\)\\{0,1\\}", "")).toBe(appPrefix());
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
