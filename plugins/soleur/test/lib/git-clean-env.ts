/**
 * A child-process environment with every `GIT_*` variable removed.
 *
 * Git resolves its repository from `GIT_DIR` / `GIT_WORK_TREE` /
 * `GIT_INDEX_FILE` FIRST, and only then falls back to discovery from the
 * working directory. `git -C <dir>` does not save you either: `-C` changes
 * directory, and `GIT_DIR` still wins. Every git HOOK exports these, and this
 * repo's lefthook pre-commit runs the test suites — so a fixture that spawns
 * `git` with a raw `process.env` operates on the CONTRIBUTOR'S repository
 * rather than its own temp dir.
 *
 * That is not hypothetical. It has now happened twice:
 *   - 2026-04-03 (#1454) `welcome-hook.test.ts` — `git init` resolved to the
 *     parent repo; the suite passed standalone and failed only under lefthook.
 *   - 2026-09-03 (#7822) `web-platform-runtime-plugin-trigger.test.ts` — a
 *     fixture's `git add -A` + `git commit` ran against the caller's branch and
 *     CONSUMED an in-flight commit. Recovery was `git reset --mixed`.
 *
 * EXCLUSION BY PREFIX, NEVER BY NAME LIST. The 2026-04-03 learning called this
 * out explicitly and it is the reason this file exists: a hardcoded list is a
 * claim about which variables git honours, and it is wrong the moment git adds
 * one. `GIT_CEILING_DIRECTORIES`, `GIT_NAMESPACE` and
 * `GIT_ALTERNATE_OBJECT_DIRECTORIES` are all already outside the obvious three.
 * The prefix has no such failure mode.
 *
 * THE SECOND HARM IS QUIETER THAN THE DATA LOSS. A case that runs a gate in a
 * deliberately NON-git directory, to prove the gate fails for want of a
 * repository, INVERTS under an inherited `GIT_DIR`: the directory is a
 * repository, the gate succeeds, and the case proves nothing while staying
 * green. Suites asserting "no repo here" need this helper to be meaningful at
 * all, not merely to be safe.
 *
 * Import this rather than re-deriving it. It was re-derived twice before it was
 * extracted, and the third copy was the one that lost data.
 */
export function gitCleanEnv(
  overrides: Record<string, string> = {},
): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [k, v] of Object.entries(process.env)) {
    if (!k.startsWith("GIT_") && v !== undefined) env[k] = v;
  }
  for (const [k, v] of Object.entries(overrides)) env[k] = v;
  return env;
}
