// Real-git fixture for the safe-bash config-exec falsifier (Ref #9600).
//
// Plants every repo-config channel through which an AUTO-APPROVED git read can execute a helper
// (diff.external, textconv, core.fsmonitor, filter.*.clean, gpg.program) and three config CARRIERS that
// need no file-tool write: a text-built bare directory, an embedded bare repository COMMITTED into a
// source repo and cloned, and a submodule. Every helper appends one tag to a marker file, so a row's
// "channels" are exactly the tags that appeared while its command ran.
//
// Hermetic by construction: the git env is built from scratch (no inherited GIT_DIR / GIT_INDEX_FILE —
// the vitest globalSetup tripwire exits rc=97 otherwise), HOME is a fixture dir, global and system
// config are disabled, identity is pinned. Fixtures are synthesized (cq-test-fixtures-synthesized-only).
import { execFileSync, spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

export type Channel = "ext-diff" | "textconv" | "fsmonitor" | "filter" | "gpg";
export type Base = "repo" | "clone" | "sub";
export type EnvKind = "plain" | "pinned";

export interface GitConfigExecFixture {
  root: string;
  bases: Record<Base, string>;
  gitVersion: string;
  run(cmd: string, base: Base, envKind: EnvKind): Channel[];
  cleanup(): void;
}

const IDENT = {
  GIT_AUTHOR_NAME: "Fixture",
  GIT_AUTHOR_EMAIL: "fixture@example.invalid",
  GIT_COMMITTER_NAME: "Fixture",
  GIT_COMMITTER_EMAIL: "fixture@example.invalid",
  GIT_AUTHOR_DATE: "2026-01-01T00:00:00Z",
  GIT_COMMITTER_DATE: "2026-01-01T00:00:00Z",
};

/** The pin `buildAgentEnv` applies (server/agent-env.ts), spelled as the raw git env it produces. */
export const PINNED_GIT_ENV = {
  GIT_CONFIG_COUNT: "1",
  GIT_CONFIG_KEY_0: "safe.bareRepository",
  GIT_CONFIG_VALUE_0: "explicit",
};

export function baseGitEnv(home: string): Record<string, string> {
  return {
    PATH: process.env.PATH ?? "/usr/bin:/bin",
    HOME: home,
    LANG: "C",
    LC_ALL: "C",
    GIT_CONFIG_GLOBAL: "/dev/null",
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_TERMINAL_PROMPT: "0",
    ...IDENT,
  };
}

function git(cwd: string, env: Record<string, string>, ...args: string[]): string {
  return execFileSync("git", args, { cwd, env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

function script(path: string, body: string): void {
  writeFileSync(path, `#!/bin/sh\n${body}\n`);
  chmodSync(path, 0o755);
}

export function buildGitConfigExecFixture(): GitConfigExecFixture {
  const root = mkdtempSync(join(tmpdir(), "safe-bash-cfgexec-"));
  const home = join(root, "home");
  const helpers = join(root, "h");
  const marker = join(root, "marker");
  mkdirSync(home);
  mkdirSync(helpers);
  const env = baseGitEnv(home);

  // Helpers: each records its channel, then behaves as a benign no-op of its kind.
  const tag = (c: string) => `echo ${c} >> '${marker}'`;
  script(join(helpers, "ext.sh"), `${tag("ext-diff")}\nexit 0`);
  script(join(helpers, "tc.sh"), `${tag("textconv")}\ncat "$1"`);
  script(join(helpers, "fsm.sh"), `${tag("fsmonitor")}\nprintf '/\\0'`);
  script(join(helpers, "clean.sh"), `${tag("filter")}\ncat`);
  script(join(helpers, "gpg.sh"), `${tag("gpg")}\nexit 1`);

  // ---- main fixture repo: history first, config planted AFTER (so history building runs no helper).
  const repo = join(root, "repo");
  mkdirSync(repo);
  git(repo, env, "init", "-q", "-b", "main");
  writeFileSync(join(repo, "f.txt"), "one\n");
  writeFileSync(join(repo, "g.zz"), "a\n");
  writeFileSync(join(repo, ".gitattributes"), "f.txt diff=evil\n*.zz filter=zz\n");
  git(repo, env, "add", "-A");
  git(repo, env, "commit", "-q", "-m", "c1");
  writeFileSync(join(repo, "f.txt"), "two\n");
  git(repo, env, "commit", "-q", "-am", "c2");

  // A hand-built commit carrying a gpgsig header, so --show-signature reaches gpg.program.
  const tree = git(repo, env, "rev-parse", "HEAD^{tree}").trim();
  const parent = git(repo, env, "rev-parse", "HEAD").trim();
  const signed =
    `tree ${tree}\nparent ${parent}\nauthor Fixture <fixture@example.invalid> 1767225600 +0000\n` +
    `committer Fixture <fixture@example.invalid> 1767225600 +0000\n` +
    `gpgsig -----BEGIN PGP SIGNATURE-----\n \n fixturefixture\n -----END PGP SIGNATURE-----\n\nsigned\n`;
  const signedPath = join(root, "signed.commit");
  writeFileSync(signedPath, signed);
  const signedSha = git(repo, env, "hash-object", "-t", "commit", "-w", "--literally", signedPath).trim();
  git(repo, env, "branch", "signed", signedSha);

  // Dirty worktree so worktree-diffing rows have something to filter / convert.
  writeFileSync(join(repo, "f.txt"), "three\n");
  writeFileSync(join(repo, "g.zz"), "b\n");

  // Plant the five channels in the repo-local config.
  const cfg = (k: string, v: string) => git(repo, env, "config", "--local", k, v);
  cfg("diff.external", join(helpers, "ext.sh"));
  cfg("diff.evil.textconv", join(helpers, "tc.sh"));
  cfg("core.fsmonitor", join(helpers, "fsm.sh"));
  cfg("filter.zz.clean", join(helpers, "clean.sh"));
  cfg("gpg.program", join(helpers, "gpg.sh"));

  const outerObjects = join(repo, ".git", "objects");
  const head = git(repo, env, "rev-parse", "main").trim();

  // ---- text-built bare directory `evil/` inside the repo: plain files, no `.git` path component.
  const evilFiles: Record<string, string> = {
    HEAD: "ref: refs/heads/main\n",
    config:
      `[core]\n\trepositoryformatversion = 0\n\tbare = true\n` +
      `[diff]\n\texternal = ${join(helpers, "ext.sh")}\n` +
      // A repo-local attempt to undo the pin: protected config means this must NOT win.
      `[safe]\n\tbareRepository = all\n`,
    "objects/info/alternates": `${outerObjects}\n`,
    "refs/heads/main": `${head}\n`,
  };
  const writeEvil = (dir: string) => {
    for (const [rel, body] of Object.entries(evilFiles)) {
      const p = join(dir, rel);
      mkdirSync(join(p, ".."), { recursive: true });
      writeFileSync(p, body);
    }
  };
  writeEvil(join(repo, "evil"));

  // ---- committed carrier: a source repo COMMITS the embedded bare repo; a plain clone then has it.
  const src = join(root, "src");
  mkdirSync(src);
  git(src, env, "init", "-q", "-b", "main");
  writeFileSync(join(src, "README.md"), "x\n");
  git(src, env, "add", "-A");
  git(src, env, "commit", "-q", "-m", "s1");
  writeFileSync(join(src, "README.md"), "y\n");
  git(src, env, "commit", "-q", "-am", "s2");
  const srcHead = git(src, env, "rev-parse", "main").trim();
  evilFiles["objects/info/alternates"] = `${join(src, ".git", "objects")}\n`;
  evilFiles["refs/heads/main"] = `${srcHead}\n`;
  writeEvil(join(src, "evil"));
  git(src, env, "add", "-A");
  git(src, env, "commit", "-q", "-m", "embed");
  const clone = join(root, "clone");
  git(root, env, "clone", "-q", src, clone);

  // ---- submodule: gitdir lives in .git/modules (written locally, never delivered by clone).
  const subOrigin = join(root, "suborigin");
  mkdirSync(subOrigin);
  git(subOrigin, env, "init", "-q", "-b", "main");
  writeFileSync(join(subOrigin, "s.txt"), "1\n");
  git(subOrigin, env, "add", "-A");
  git(subOrigin, env, "commit", "-q", "-m", "o1");
  writeFileSync(join(subOrigin, "s.txt"), "2\n");
  git(subOrigin, env, "commit", "-q", "-am", "o2");
  git(src, env, "-c", "protocol.file.allow=always", "submodule", "add", "-q", subOrigin, "sub");
  git(src, env, "commit", "-q", "-m", "addsub");
  git(root, env, "-c", "protocol.file.allow=always", "clone", "-q", "--recurse-submodules", src, join(root, "clone2"));

  const bases: Record<Base, string> = { repo, clone, sub: join(root, "clone2", "sub") };
  const gitVersion = git(repo, env, "--version").trim();

  function run(cmd: string, base: Base, envKind: EnvKind): Channel[] {
    writeFileSync(marker, "");
    const e = envKind === "pinned" ? { ...env, ...PINNED_GIT_ENV } : env;
    spawnSync("bash", ["-c", cmd], { cwd: bases[base], env: e, encoding: "utf8", timeout: 20_000 });
    const seen = readFileSync(marker, "utf8").split("\n").filter(Boolean);
    return [...new Set(seen)].sort() as Channel[];
  }

  return {
    root,
    bases,
    gitVersion,
    run,
    cleanup: () => rmSync(root, { recursive: true, force: true }),
  };
}
