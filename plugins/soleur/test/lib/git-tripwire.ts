// Guard 3 — fail-loud runtime tripwire.
//
// PROPERTY. A test-runner process that starts while holding any git-location variable ABORTS
// before running a single test, naming the variables and the runner.
//
// This is the layer neither Guard 1 (a helper you must remember to call) nor Guard 2 (a static
// scan of the hook entry points we enumerated) can cover:
//   * an entry point nobody enumerated — an agent shell with GIT_DIR exported, `git rebase -x`,
//     `git bisect run`, an editor's test runner;
//   * a TRANSITIVE spawn — a script under test that runs `git` itself, which no helper call and
//     no source scan can reach.
//
// It FAILS rather than scrubbing. An in-process scrub would be false comfort: under Bun a
// `delete process.env.GIT_DIR` does not reach a child spawned without an explicit `env`
// (measurements.md §M-5), so a tripwire that "fixed" the environment would leave every default-env
// subprocess still hostile while reporting success. Mutation row K2 pins this.
//
// Exit code 97 is arbitrary but distinctive: it must not collide with a runner's own failure
// codes, so an aborted run is attributable at a glance.

/** Variables that redirect WHERE git reads and writes. Kept in sync with git-fixture-env.ts. */
const GIT_LOCATION_VARS = [
  "GIT_DIR",
  "GIT_WORK_TREE",
  "GIT_INDEX_FILE",
  "GIT_COMMON_DIR",
  "GIT_OBJECT_DIRECTORY",
  "GIT_ALTERNATE_OBJECT_DIRECTORIES",
  "GIT_NAMESPACE",
] as const;

export const GIT_TRIPWIRE_EXIT_CODE = 97;

/** The variables currently present in `env`. Exported so a test can assert the watched set. */
export function detectGitLocationVars(env: NodeJS.ProcessEnv = process.env): string[] {
  return GIT_LOCATION_VARS.filter((k) => {
    const v = env[k];
    return typeof v === "string" && v.length > 0;
  });
}

/**
 * Abort the process if any git-location variable is present.
 *
 * Deliberately NOT scoped to absolute values. A relative `GIT_INDEX_FILE=.git/index` (what a plain
 * clone's hook exports, §M-1) is harmless in the common case but depends on the subprocess's cwd
 * to stay harmless — and a fixture's whole purpose is to change cwd. Refusing the whole family is
 * the cheap, legible rule; a value-shape carve-out would be a proxy for the property, and this
 * repo has paid for proxies before.
 *
 * NOT tripped by the author, committer or config-parameter families: those leak into fixture commit
 * metadata (a flake source) but are not a write-boundary breach, and blocking on them would make
 * every ordinary `git commit -m` hook run unusable. Harness row L2 pins that they must PASS.
 * (Written in prose deliberately: the glob spelling of those names contains a literal star-slash,
 * which closes this block comment early — a trap already paid for in #5920.)
 */
export function assertNoInheritedGitLocation(runner: string): void {
  const found = detectGitLocationVars();
  if (found.length === 0) return;

  const detail = found.map((k) => `  ${k}=${process.env[k]}`).join("\n");
  process.stderr.write(
    [
      "",
      `FATAL: ${runner} started with an inherited git-location environment.`,
      "",
      "These variables override BOTH a subprocess's working directory and `git -C`, so any test",
      "that builds a temporary git fixture would write into the repository they point at instead:",
      "",
      detail,
      "",
      "This is what #7833 reported — fixture commits landing on the developer's live branch and",
      "moving its tip. In a linked worktree git exports these to every hook it runs.",
      "",
      "Fix the ENTRY POINT that started this runner, by prefixing it with:",
      "",
      "  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE && <runner>",
      "",
      "Do not scrub in-process: under Bun a `delete process.env.GIT_DIR` does not reach a child",
      "spawned without an explicit `env`.",
      "",
    ].join("\n"),
  );
  process.exit(GIT_TRIPWIRE_EXIT_CODE);
}

// Fire on import. Registering this file as a runner preload is the mechanism; the guard asserts
// the tripwire FIRED, not that this file exists (mutation row K3).
assertNoInheritedGitLocation(
  typeof (globalThis as { Bun?: unknown }).Bun !== "undefined" ? "bun test" : "vitest",
);
