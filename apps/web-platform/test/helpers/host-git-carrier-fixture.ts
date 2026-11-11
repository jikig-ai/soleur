// Real-git fixture for the host-side git consumer battery (Ref #9601, follow-on to the git-read hardening).
//
// Plants the repo-config / .git carriers an agent session can author (a `commondir` redirect to a directory it
// wrote, .git/config, config.worktree, hooks, tracked and untracked attributes, a foreign core.worktree, a
// local-exec remote program) and measures the EFFECT: every planted helper appends one tag to a canary file that
// lives OUTSIDE the workspace and writes the environment it saw to a per-helper dump file. A row's evidence is
// therefore the canary and the dumps, never an argv assertion.
//
// Hermetic by construction: the fixture's own git env is built from scratch (no inherited GIT_DIR /
// GIT_INDEX_FILE: the vitest globalSetup tripwire exits rc=97 otherwise), HOME is a fixture dir, global and system
// config are disabled and identity is pinned. Fixtures are synthesized (cq-test-fixtures-synthesized-only).
import { execFileSync, spawnSync } from "node:child_process";
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export const GIT_FLOOR = [2, 38] as const;

/** Throws (never skips) when the host git is older than the floor the shipped controls assume. */
export function assertGitFloor(): string {
  const out = spawnSync("git", ["--version"], { encoding: "utf8" }).stdout.trim();
  const m = /(\d+)\.(\d+)/.exec(out);
  const major = m ? Number(m[1]) : 0;
  const minor = m ? Number(m[2]) : 0;
  if (major < GIT_FLOOR[0] || (major === GIT_FLOOR[0] && minor < GIT_FLOOR[1])) {
    throw new Error(`git version ${out} is older than ${GIT_FLOOR.join(".")}; the host-git hardening battery cannot run`);
  }
  return out;
}

const IDENT = {
  GIT_AUTHOR_NAME: "Fixture",
  GIT_AUTHOR_EMAIL: "fixture@example.invalid",
  GIT_COMMITTER_NAME: "Fixture",
  GIT_COMMITTER_EMAIL: "fixture@example.invalid",
  // Fixed dates: two workspaces built from the same content must get IDENTICAL commit ids, whatever second each was built in.
  // The refs-symlink control relies on the foreign repository's tip existing in the attacker workspace's object store; with
  // wall-clock dates the two ids differ whenever a second boundary falls between them and the raw commit fails (CI, measured).
  GIT_AUTHOR_DATE: "2020-01-01T00:00:00Z",
  GIT_COMMITTER_DATE: "2020-01-01T00:00:00Z",
};

/** The shared fixture-env builder (`plugins/soleur/test/lib/git-fixture-env`), injected by the suite: this helper stays inside apps/web-platform. */
type FixtureEnvBuilder = (fixtureDir: string) => NodeJS.ProcessEnv;
let gitFixtureEnv: FixtureEnvBuilder = () => {
  throw new Error("host-git-carrier-fixture: call useSharedFixtureEnv(gitFixtureEnv) before building a world");
};
export function useSharedFixtureEnv(builder: FixtureEnvBuilder): void {
  gitFixtureEnv = builder;
}

/**
 * The fixture's own (setup-time) git env: SCRATCH-BUILT, nothing inherited. It takes the shared fixture builder's hermeticity
 * fields (discovery ceiling, XDG and attributes isolation) but not its inherited `process.env` or its signing override: the
 * battery's planted helpers dump the environment they run under and assert the server sentinel is absent, and the signing carrier
 * must stay live under the fixture's own raw runs.
 */
export function fixtureGitEnv(home: string): NodeJS.ProcessEnv {
  const shared = gitFixtureEnv(home);
  return {
    PATH: process.env.PATH ?? "/usr/bin:/bin",
    HOME: home,
    LANG: "C",
    LC_ALL: "C",
    GIT_CEILING_DIRECTORIES: shared.GIT_CEILING_DIRECTORIES,
    GIT_ATTR_NOSYSTEM: shared.GIT_ATTR_NOSYSTEM,
    XDG_CONFIG_HOME: shared.XDG_CONFIG_HOME,
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_TERMINAL_PROMPT: "0",
    GIT_ALLOW_PROTOCOL: "file:https:ssh",
    ...IDENT,
  } as unknown as NodeJS.ProcessEnv;
}

export interface World {
  root: string;
  home: string;
  /** Appended to by every planted helper. Outside any workspace. */
  canary: string;
  /** One file per helper run: the exact environment that helper saw. */
  dumps: string;
  /** A directory whose files must never be touched by a consumer (the foreign-worktree target). */
  victim: string;
  env: NodeJS.ProcessEnv;
  git(cwd: string, ...args: string[]): string;
  /** Write an executable helper that tags the canary, dumps its env, then runs `tail`. */
  helper(tag: string, tail?: string): string;
  tags(): string[];
  envDumps(): string[];
  cleanup(): void;
}

export const SENTINEL_VAR = "SERVER_ONLY_SENTINEL";

export function newWorld(prefix = "host-git-"): World {
  const root = mkdtempSync(join(tmpdir(), prefix));
  const home = join(root, "home");
  const dumps = join(root, "dumps");
  const victim = join(root, "victim");
  mkdirSync(home);
  mkdirSync(dumps);
  mkdirSync(victim);
  writeFileSync(join(victim, "victim.txt"), "foreign tenant content\n");
  mkdirSync(join(victim, "knowledge-base"));
  writeFileSync(join(victim, "knowledge-base", "n.md"), "foreign tenant note\n");
  const canary = join(root, "canary");
  writeFileSync(canary, "");
  const env = fixtureGitEnv(home);
  let n = 0;
  return {
    root,
    home,
    canary,
    dumps,
    victim,
    env,
    git(cwd, ...args) {
      return execFileSync("git", args, { cwd, env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
    },
    helper(tag, tail = "exit 0") {
      const p = join(root, `h-${tag}-${n++}.sh`);
      writeFileSync(
        p,
        `#!/bin/sh\necho ${tag} >> '${canary}'\nenv > '${dumps}/${tag}-'$$\n${tail}\n`,
      );
      chmodSync(p, 0o755);
      return p;
    },
    tags() {
      return readFileSync(canary, "utf8").split("\n").filter(Boolean);
    },
    envDumps() {
      return readdirSync(dumps).map((f) => readFileSync(join(dumps, f), "utf8"));
    },
    cleanup() {
      rmSync(root, { recursive: true, force: true });
    },
  };
}

/** A workspace: real repo, baseline commit with knowledge-base content, a seeded LOCAL identity, a bare upstream. */
export interface Workspace {
  ws: string;
  upstream: string;
}

export function newWorkspace(w: World, name = "ws"): Workspace {
  const upstream = join(w.root, `${name}-upstream.git`);
  const ws = join(w.root, name);
  w.git(w.root, "init", "-q", "--bare", "-b", "main", upstream);
  mkdirSync(ws);
  w.git(ws, "init", "-q", "-b", "main");
  w.git(ws, "config", "user.name", "Seeded Local");
  w.git(ws, "config", "user.email", "seeded-local@example.invalid");
  w.git(ws, "config", "commit.gpgsign", "false");
  mkdirSync(join(ws, "knowledge-base"));
  writeFileSync(join(ws, "knowledge-base", "base.md"), "base\n");
  w.git(ws, "add", "--", "knowledge-base/base.md");
  w.git(ws, "commit", "-q", "-m", "baseline");
  w.git(ws, "remote", "add", "origin", `file://${upstream}`);
  w.git(ws, "push", "-q", "origin", "main");
  w.git(ws, "branch", "-q", "--set-upstream-to=origin/main", "main");
  return { ws, upstream };
}

export function dirty(ws: string, name = "note.md"): void {
  writeFileSync(join(ws, "knowledge-base", name), `edit ${Math.random()}\n`);
}

export interface Planter {
  id: string;
  /** Closable by the helper's `-c` arguments / env pins: the canary must stay empty. */
  closable: boolean;
  /** Measured open item: the helper runs, and the test pins that. */
  residual: boolean;
  plant(ws: string, w: World): void;
  /** The canary tag the planted helper writes. */
  tag: string;
  /** A tracked file the carrier needs (written and committed by the planter). */
  tracked?: boolean;
}

function appendConfig(ws: string, w: World, key: string, value: string): void {
  w.git(ws, "config", "--local", key, value);
}

function copyGitDirTo(ws: string, dest: string): void {
  cpSync(join(ws, ".git"), dest, { recursive: true });
}

/** `.git/commondir` -> a copied directory the agent authored; its config/attributes carry the helper. */
function commondir(ws: string, w: World, configure: (dir: string) => void): void {
  const dest = join(ws, ".cache-x");
  copyGitDirTo(ws, dest);
  configure(dest);
  writeFileSync(join(ws, ".git", "commondir"), dest + "\n");
}

export const PLANTERS: Planter[] = [
  {
    id: "fsmonitor-in-git-config",
    tag: "fsmonitor-config",
    closable: true,
    residual: false,
    plant: (ws, w) => appendConfig(ws, w, "core.fsmonitor", w.helper("fsmonitor-config")),
  },
  {
    id: "fsmonitor-via-commondir",
    tag: "fsmonitor-commondir",
    closable: true,
    residual: false,
    plant: (ws, w) =>
      commondir(ws, w, (dir) => {
        writeFileSync(join(dir, "config"), readFileSync(join(dir, "config"), "utf8") + `[core]\n\tfsmonitor = ${w.helper("fsmonitor-commondir")}\n`);
      }),
  },
  {
    id: "fsmonitor-in-config-worktree",
    tag: "fsmonitor-config-worktree",
    closable: true,
    residual: false,
    plant: (ws, w) => {
      appendConfig(ws, w, "extensions.worktreeConfig", "true");
      writeFileSync(join(ws, ".git", "config.worktree"), `[core]\n\tfsmonitor = ${w.helper("fsmonitor-config-worktree")}\n`);
    },
  },
  {
    id: "hook-pre-commit",
    tag: "hook-pre-commit",
    closable: true,
    residual: false,
    plant: (ws, w) => {
      const h = w.helper("hook-pre-commit");
      mkdirSync(join(ws, ".git", "hooks"), { recursive: true });
      cpSync(h, join(ws, ".git", "hooks", "pre-commit"));
      chmodSync(join(ws, ".git", "hooks", "pre-commit"), 0o755);
    },
  },
  {
    id: "hook-reference-transaction",
    tag: "hook-reference-transaction",
    closable: true,
    residual: false,
    plant: (ws, w) => {
      const h = w.helper("hook-reference-transaction");
      mkdirSync(join(ws, ".git", "hooks"), { recursive: true });
      cpSync(h, join(ws, ".git", "hooks", "reference-transaction"));
      chmodSync(join(ws, ".git", "hooks", "reference-transaction"), 0o755);
    },
  },
  {
    id: "hook-pre-push",
    tag: "hook-pre-push",
    closable: true,
    residual: false,
    plant: (ws, w) => {
      const h = w.helper("hook-pre-push");
      mkdirSync(join(ws, ".git", "hooks"), { recursive: true });
      cpSync(h, join(ws, ".git", "hooks", "pre-push"));
      chmodSync(join(ws, ".git", "hooks", "pre-push"), 0o755);
    },
  },
  {
    id: "signing-program",
    tag: "gpg-program",
    closable: true,
    residual: false,
    plant: (ws, w) => {
      appendConfig(ws, w, "commit.gpgsign", "true");
      appendConfig(ws, w, "gpg.program", w.helper("gpg-program", "exit 1"));
    },
  },
  {
    id: "core-worktree-foreign",
    tag: "core-worktree",
    closable: true,
    residual: false,
    plant: (ws, w) => {
      // No helper: the effect is that the consumer operates on the OTHER directory.
      appendConfig(ws, w, "core.worktree", w.victim);
    },
  },
  {
    id: "uploadpack-local-remote",
    tag: "uploadpack",
    closable: true,
    residual: false,
    plant: (ws, w) => appendConfig(ws, w, "remote.origin.uploadpack", w.helper("uploadpack", "exit 1")),
  },
  {
    id: "filter-via-git-config",
    tag: "filter-config",
    closable: false,
    residual: true,
    tracked: true,
    plant: (ws, w) => {
      writeFileSync(join(ws, ".gitattributes"), "*.md filter=zz\n");
      appendConfig(ws, w, "filter.zz.clean", w.helper("filter-config", "cat"));
    },
  },
  {
    id: "filter-via-info-attributes",
    tag: "filter-info",
    closable: false,
    residual: true,
    plant: (ws, w) => {
      mkdirSync(join(ws, ".git", "info"), { recursive: true });
      writeFileSync(join(ws, ".git", "info", "attributes"), "*.md filter=zz\n");
      appendConfig(ws, w, "filter.zz.clean", w.helper("filter-info", "cat"));
    },
  },
  {
    id: "filter-via-commondir",
    tag: "filter-commondir",
    closable: false,
    residual: true,
    plant: (ws, w) =>
      commondir(ws, w, (dir) => {
        mkdirSync(join(dir, "info"), { recursive: true });
        writeFileSync(join(dir, "info", "attributes"), "*.md filter=zz\n");
        writeFileSync(
          join(dir, "config"),
          readFileSync(join(dir, "config"), "utf8") + `[filter "zz"]\n\tclean = ${w.helper("filter-commondir", "cat")}\n`,
        );
      }),
  },
];

export function planterById(id: string): Planter {
  const p = PLANTERS.find((x) => x.id === id);
  if (!p) throw new Error(`no planter ${id}`);
  return p;
}

/** Plant and, for tracked carriers, commit the tracked half so it is part of the baseline. */
export function plant(p: Planter, ws: string, w: World): void {
  p.plant(ws, w);
  if (p.tracked) {
    w.git(ws, "add", "--", ".gitattributes");
    // the planted config may name a gpg/filter helper: commit under a clean -c set, never the carrier
    execFileSync("git", ["-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "commit", "-q", "-m", "tracked carrier"], {
      cwd: ws,
      env: w.env,
      stdio: "pipe",
    });
  }
}

export function exists(p: string): boolean {
  return existsSync(p);
}
