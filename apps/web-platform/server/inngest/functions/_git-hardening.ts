// #7122 P1-B — the git invocation hardening shared by every handler-side git step that
// runs in a workspace an agent may have used (safeCommitAndPr, setOriginToken).
//
// A leaf module on purpose: no imports, so the substrate and the safe-commit helper can
// both take it without a cycle and without loading each other's graph.

/**
 * Global git options for every invocation. `-c` beats the repo's own config:
 *   - `core.hooksPath=/dev/null`, `core.fsmonitor=false`, `core.attributesFile=/dev/null`
 *     stop a planted hook, fsmonitor command or attributes file from running;
 *   - `--no-replace-objects` makes git ignore `refs/replace/*`. A replace ref swaps one
 *     object for another for every READ (`cat-file`, `log`, `diff`) while `push` ships the
 *     real objects, which defeats any read-back integrity check (security round-1 E10).
 */
export const GIT_HARDENING_ARGS: readonly string[] = [
  "--no-replace-objects",
  "-c",
  "core.hooksPath=/dev/null",
  "-c",
  "core.fsmonitor=false",
  "-c",
  "core.attributesFile=/dev/null",
];

/**
 * Environment for every invocation: isolate from host/container git config (signing,
 * hooksPath, templates; fixture determinism in tests, predictability in prod) and turn
 * replace refs off a second way (the env var also covers a child git a git command spawns).
 */
export const GIT_HARDENING_ENV: Readonly<Record<string, string>> = Object.freeze({
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_SYSTEM: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_NO_REPLACE_OBJECTS: "1",
});
