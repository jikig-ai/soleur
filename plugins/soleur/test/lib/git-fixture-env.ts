// A fixture git environment: `gitCleanEnv()` plus the three things a fixture that WRITES needs.
//
// This layers on `./git-clean-env`, it does not compete with it. That module owns the sweep and
// states the rule it enforces — EXCLUSION BY PREFIX, NEVER BY NAME LIST — and this file honours it:
// there is no name list here. An earlier revision of this file shipped one, and review found four
// omissions in a single pass (GIT_TEMPLATE_DIR and GIT_EXEC_PATH, both proven to execute arbitrary
// code; GIT_SSH, which a `GIT_SSH_COMMAND` prefix rule structurally cannot match because the prefix
// is LONGER than the name; and the GIT_TRACE family, which appends to an absolute path — a write
// outside the fixture, i.e. the very property this file exists to establish). That is the failure
// mode `git-clean-env.ts` predicted in caps, so the list is gone and the prefix sweep is the base.
//
// What the sweep alone does NOT give a fixture that writes:
//   1. an identity — `git commit` under a swept env fails `Author identity unknown`, because the
//      sweep removes GIT_AUTHOR_* and the config hardening below removes the developer's own;
//   2. a discovery ceiling — the sweep stops git being POINTED elsewhere, but not git WALKING UP
//      into an enclosing repository from the fixture's own directory;
//   3. config hermeticity — a developer's ~/.config/git/attributes still rewrites fixture bytes.
//
// See #7833 and `knowledge-base/project/specs/feat-one-shot-7833-git-dir-beats-cwd/measurements.md`.

import { execFileSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { existsSync, realpathSync } from "node:fs";

import { gitCleanEnv } from "./git-clean-env";

/**
 * The variables that redirect WHERE git reads and writes, or that make `git init` copy executable
 * content into the fixture.
 *
 * This is NOT used to build the fixture env — the prefix sweep does that, and a list could only
 * make it narrower. It exists because the TRIPWIRE and the entry-point scrub need a concrete set to
 * name: a tripwire cannot refuse "every GIT_ variable" (GIT_AUTHOR_NAME is harmless and a hook
 * exports it on every commit), and an `unset` needs words. Consumers: `./git-tripwire`, and the
 * parity test that pins this against the python and shell copies.
 *
 * GIT_TEMPLATE_DIR and GIT_EXEC_PATH are the two members no config hardening can touch. Measured:
 * under GIT_CONFIG_NOSYSTEM=1 + GIT_CONFIG_GLOBAL=/dev/null + a correct ceiling + a pinned identity,
 * an inherited GIT_TEMPLATE_DIR made `git init` copy a hook into the fixture and the fixture's own
 * `git commit` EXECUTED it — templates are copied before any config is consulted.
 */
export const GIT_LOCATION_VARS = [
  "GIT_DIR",
  "GIT_WORK_TREE",
  "GIT_INDEX_FILE",
  "GIT_COMMON_DIR",
  "GIT_OBJECT_DIRECTORY",
  "GIT_ALTERNATE_OBJECT_DIRECTORIES",
  "GIT_NAMESPACE",
  "GIT_TEMPLATE_DIR",
  "GIT_EXEC_PATH",
] as const;

/**
 * Execution vectors git consults whose names carry NO `GIT_` prefix, so the sweep cannot reach them.
 * `SSH_ASKPASS` is git's documented fallback when GIT_ASKPASS and core.askPass are unset, i.e. an
 * inherited value names a program git will run.
 */
const NON_GIT_SCRUBBED_VARS = ["SSH_ASKPASS"] as const;

/**
 * Compute the discovery ceiling for a fixture: the fixture's PARENT, resolved through symlinks.
 *
 * Exported for the guard suite, which asserts the exact value rather than merely that one is set —
 * a ceiling of `"/"` is silently ignored by git, so `toBeTruthy()` passes over a no-op.
 *
 * @throws if the computed ceiling cannot be enforced, rather than emitting one that does nothing.
 */
export function fixtureCeiling(fixtureDir: string): string {
  // Resolve the FIXTURE, then take its parent — not the other way round. `realpathSync(dirname(x))`
  // resolves the LEXICAL parent, so a fixture directory that is itself a symlink yields a ceiling
  // naming the link's parent while git's getcwd() reports the physical path, and discovery escapes.
  // (A previous comment here claimed the resolve was needed because git compares ceilings against a
  // resolved path. That is measurably false — git resolves ceiling entries itself. The resolve is
  // for the symlinked-fixture case, and for nothing else.)
  const abs = resolve(fixtureDir);
  const physical = existsSync(abs) ? realpathSync(abs) : abs;
  const ceiling = dirname(physical);

  // GIT_CEILING_DIRECTORIES is ":"-separated and git IGNORES every non-absolute entry, so a colon
  // anywhere in the path splits it into two fragments that are both discarded and the ceiling is
  // silently unenforceable. `"/"` is ignored for the same reason. Fail loudly instead: an
  // unenforceable ceiling that looks set is worse than no ceiling, because it reads as protection.
  if (!ceiling.startsWith("/") || ceiling === "/" || ceiling.includes(":")) {
    throw new Error(
      `gitFixtureEnv: no enforceable GIT_CEILING_DIRECTORIES for ${JSON.stringify(fixtureDir)} ` +
        `(computed ${JSON.stringify(ceiling)}). git ignores a ceiling that is "/" or non-absolute, ` +
        `and ":" splits it into fragments that are all ignored. Pass a fixture at least two levels ` +
        `below "/" whose path contains no colon.`,
    );
  }
  return ceiling;
}

/**
 * Build the environment a fixture's `git` subprocess should run under.
 *
 * @param fixtureDir the fixture's own directory. Required — there is deliberately no default. A
 *   default of `tmpdir()` yields a ceiling of `"/"`, which git ignores, so every caller that
 *   omitted the argument would silently lose the ceiling while the code read as if it had one.
 */
export function gitFixtureEnv(fixtureDir: string): Record<string, string> {
  const ceiling = fixtureCeiling(fixtureDir);
  const physical = existsSync(resolve(fixtureDir))
    ? realpathSync(resolve(fixtureDir))
    : resolve(fixtureDir);

  const env = gitCleanEnv({
    GIT_CEILING_DIRECTORIES: ceiling,
    GIT_CONFIG_NOSYSTEM: "1",
    GIT_CONFIG_GLOBAL: "/dev/null",
    // GIT_CONFIG_GLOBAL replaces ~/.gitconfig and ~/.config/git/config, but NOT the sibling XDG git
    // files: ~/.config/git/attributes and ~/.config/git/ignore are located independently of config
    // content, so a developer's `* text=auto` still rewrites fixture bytes and changes `git status`
    // output on their machine but not in CI. Point XDG at the fixture (which holds no `git/`
    // subdirectory) and refuse the system attributes file.
    GIT_ATTR_NOSYSTEM: "1",
    XDG_CONFIG_HOME: join(physical, ".soleur-fixture-xdg"),
    GIT_TERMINAL_PROMPT: "0",
    // Synthesized identity (`cq-test-fixtures-synthesized-only`). Required: the sweep removes
    // GIT_AUTHOR_*/GIT_COMMITTER_* and GIT_CONFIG_GLOBAL=/dev/null removes the developer's, so
    // without these the fixture's first commit fails `Author identity unknown`.
    GIT_AUTHOR_NAME: "Soleur Fixture",
    GIT_AUTHOR_EMAIL: "fixture@example.com",
    GIT_COMMITTER_NAME: "Soleur Fixture",
    GIT_COMMITTER_EMAIL: "fixture@example.com",
  });

  // Non-GIT_ execution vectors the sweep cannot see by shape.
  for (const key of NON_GIT_SCRUBBED_VARS) delete env[key];

  return env;
}

/**
 * A `git` runner bound to one fixture directory, already carrying {@link gitFixtureEnv}.
 *
 * Commit signing is disabled explicitly: a developer with `commit.gpgsign=true` would otherwise have
 * every fixture commit fail, and GIT_CONFIG_GLOBAL=/dev/null does not cover a repo-local setting
 * inherited via a template.
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
