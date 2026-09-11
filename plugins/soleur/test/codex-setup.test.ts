import { afterEach, beforeEach, expect, test } from "bun:test";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "fs";
import { join, resolve } from "path";
import { tmpdir } from "os";
import { gitFixtureEnv } from "./lib/git-fixture-env";

const sourceRoot = resolve(import.meta.dir, "../../..");
let temporary: string;
let repository: string;
let worktree: string;
let environment: NodeJS.ProcessEnv;

function git(...args: string[]) {
  const result = Bun.spawnSync(["git", ...args], { cwd: repository, env: environment });
  if (result.exitCode !== 0) throw new Error(result.stderr.toString());
}

beforeEach(() => {
  temporary = mkdtempSync(join(tmpdir(), "soleur codex setup "));
  repository = join(temporary, "repo");
  worktree = join(temporary, "feature");
  mkdirSync(repository);
  environment = gitFixtureEnv(temporary);
  git("init");
  git("-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-m", "fixture");
  git("worktree", "add", "-b", "feature", worktree);
  mkdirSync(join(worktree, "scripts"));
  mkdirSync(join(worktree, ".codex"));
  cpSync(join(sourceRoot, "scripts/setup-codex.sh"), join(worktree, "scripts/setup-codex.sh"));
  cpSync(join(sourceRoot, ".codex/config.toml"), join(worktree, ".codex/config.toml"));
  const binaries = join(temporary, "bin");
  mkdirSync(binaries);
  writeFileSync(join(binaries, "codex"), "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$SOLEUR_CODEX_TEST_LOG\"\n", { mode: 0o755 });
  environment.PATH = binaries + ":" + process.env.PATH;
  environment.SOLEUR_CODEX_TEST_LOG = join(temporary, "calls");
});

afterEach(() => rmSync(temporary, { recursive: true, force: true }));

function setup() {
  return Bun.spawnSync(["bash", join(worktree, "scripts/setup-codex.sh")], { cwd: temporary, env: environment });
}

test("installs at the shared root from a linked worktree, including paths with spaces", () => {
  expect(setup().exitCode).toBe(0);
  const expected = readFileSync(join(worktree, ".codex/config.toml"), "utf8");
  expect(readFileSync(join(repository, ".codex/config.toml"), "utf8")).toBe(expected);
  expect(readFileSync(join(temporary, "calls"), "utf8")).toBe(
    "plugin marketplace add " + worktree + "\nplugin add soleur@soleur\n",
  );
  expect(setup().exitCode).toBe(0);
  expect(readFileSync(join(repository, ".codex/config.toml"), "utf8")).toBe(expected);
});

test("refuses to replace differing user configuration", () => {
  mkdirSync(join(repository, ".codex"));
  const target = join(repository, ".codex/config.toml");
  writeFileSync(target, 'model = "example"\n');
  expect(setup().exitCode).toBe(1);
  expect(readFileSync(target, "utf8")).toBe('model = "example"\n');
});

test("refuses a symlinked configuration directory", () => {
  const other = join(temporary, "other");
  mkdirSync(other);
  symlinkSync(other, join(repository, ".codex"));
  const result = setup();
  expect(result.exitCode).toBe(1);
  expect(result.stderr.toString()).toContain("symlink");
});
