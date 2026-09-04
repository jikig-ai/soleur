// Shared fixture git-environment constructor.
//
// A test that builds a temporary git fixture and passes `cwd` (or `-C`) to every `git` call is
// still NOT scoped to that fixture: when the test process inherits GIT_DIR / GIT_INDEX_FILE from a
// git hook environment, the subprocess honours the environment over BOTH its working directory and
// `-C`. `git init` then initialises nothing and the fixture's writes land in the surrounding
// repository. See #7833 and the measurements in
// `knowledge-base/project/specs/feat-one-shot-7833-git-dir-beats-cwd/measurements.md`.
//
// WHY THIS RETURNS AN OBJECT INSTEAD OF MUTATING `process.env`.
// Under Bun 1.3.11 a `delete process.env.GIT_DIR` takes effect in-process but a child spawned
// WITHOUT an explicit `env` still receives the original inherited value; Node propagates the
// deletion correctly (§M-5). Measured only for a variable INHERITED from the ambient environment —
// a set-then-delete in the same process is a different code path and looks clean under both
// runtimes, so a re-probe must inherit or it will wrongly read as "Bun is fine". The scrub
// therefore belongs on the INVOCATION, never inside the runtime. Mutation row M6 pins this.
//
// WHY A DENY-LIST AND NOT AN ALLOW-LIST.
// `buildGitProbeEnv()`'s allowlist cannot be copied verbatim: it is a read-only PROBE env, and a
// fixture `git commit` under it fails `Author identity unknown` (§M-7). Every shell fixture suite
// in this repo commits. So this keeps the ambient env, removes what is dangerous, and pins an
// identity. Mutation row M7 pins the identity.

import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { existsSync, realpathSync } from "node:fs";

/**
 * Variables that redirect WHERE git reads and writes. Any one of these is sufficient to retarget a
 * fixture's writes into another repository, and they are not interchangeable: with GIT_DIR removed,
 * an absolute GIT_INDEX_FILE alone still stages into the victim's index while HEAD stays put
 * (§M-3). Removing a subset is the defect, not a partial fix.
 */
export const GIT_LOCATION_VARS = [
  "GIT_DIR",
  "GIT_WORK_TREE",
  "GIT_INDEX_FILE",
  "GIT_COMMON_DIR",
  "GIT_OBJECT_DIRECTORY",
  "GIT_ALTERNATE_OBJECT_DIRECTORIES",
  "GIT_NAMESPACE",
] as const;

/**
 * Variables that let an inherited environment inject config or execute a command of its choosing.
 * Not a write-boundary breach on their own, but a fixture that inherits them is not hermetic.
 * GIT_CONFIG_PARAMETERS is included because a git hook demonstrably exports it (§M-1) and it is the
 * older spelling of the same injection the GIT_CONFIG_* family provides.
 */
const GIT_INJECTION_VAR_PREFIXES = [
  "GIT_SSH_COMMAND",
  "GIT_PROXY_COMMAND",
  "GIT_EXTERNAL_DIFF",
  "GIT_CONFIG_COUNT",
  "GIT_CONFIG_KEY",
  "GIT_CONFIG_VALUE",
  "GIT_CONFIG_PARAMETERS",
] as const;

function isInjectionVar(key: string): boolean {
  return GIT_INJECTION_VAR_PREFIXES.some((p) => key === p || key.startsWith(p));
}

/**
 * Build the environment a fixture's `git` subprocess should run under.
 *
 * @param fixtureDir the fixture's own directory. Its PARENT becomes GIT_CEILING_DIRECTORIES —
 *   the fixture-dir spelling does NOT stop discovery escaping to the enclosing repository when
 *   git's cwd equals it (§M-4).
 */
export function gitFixtureEnv(fixtureDir: string): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [key, val] of Object.entries(process.env)) {
    if (val === undefined) continue;
    if ((GIT_LOCATION_VARS as readonly string[]).includes(key)) continue;
    if (isInjectionVar(key)) continue;
    env[key] = val;
  }

  // The ceiling must be the fixture's parent. Resolve through symlinks where possible: git compares
  // ceilings against the resolved path, so an unresolved /var/tmp -> /private/var/tmp style symlink
  // would make the ceiling silently not match.
  const abs = resolve(fixtureDir);
  const parent = dirname(abs);
  env.GIT_CEILING_DIRECTORIES = existsSync(parent) ? realpathSync(parent) : parent;

  env.GIT_CONFIG_NOSYSTEM = "1";
  env.GIT_CONFIG_GLOBAL = "/dev/null";
  env.GIT_TERMINAL_PROMPT = "0";

  // Synthesized identity (`cq-test-fixtures-synthesized-only`). Without it the first commit fails
  // `Author identity unknown`, because GIT_CONFIG_GLOBAL=/dev/null removes the developer's own.
  env.GIT_AUTHOR_NAME = "Soleur Fixture";
  env.GIT_AUTHOR_EMAIL = "fixture@example.com";
  env.GIT_COMMITTER_NAME = "Soleur Fixture";
  env.GIT_COMMITTER_EMAIL = "fixture@example.com";

  return env;
}

/**
 * A `git` runner bound to one fixture directory, already carrying {@link gitFixtureEnv}.
 *
 * Commit signing is disabled explicitly: a developer with `commit.gpgsign=true` would otherwise
 * have every fixture commit fail, and GIT_CONFIG_GLOBAL=/dev/null does not cover a repo-local
 * setting inherited via a template.
 */
export function gitFixture(fixtureDir: string): (args: string[]) => string {
  const env = gitFixtureEnv(fixtureDir);
  return (args: string[]): string =>
    execFileSync("git", ["-c", "commit.gpgsign=false", ...args], {
      cwd: fixtureDir,
      env,
      encoding: "utf8",
    });
}
