# Learning: a global SessionStart hook that shells out inherits the project it runs in

## Problem
The plugin-version banner (PR #10064) first shipped with `git ls-remote` and a GitHub compare
`curl` run straight from the hook's cwd with the user's environment. A security seat showed that
a project's `.git/config` (`url.<base>.insteadOf`, `http.extraHeader`, `core.sshCommand`) or a
`GIT_CONFIG_COUNT` env could redirect the "fixed URL" lookup, attach an `Authorization` header,
or run a command, and that the very common user-global ssh-style `url.<base>.insteadOf` rewrite turns the
"unauthenticated" lookup into an SSH-key-authenticated one. Plugin hooks are global: they fire in
every project the user opens, so the project is attacker-controlled input.

## Solution
Run the lookups from `/` with `GIT_CONFIG_GLOBAL/SYSTEM=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`,
`HOME=/nonexistent`, `GIT_CONFIG_COUNT`/`GIT_SSH*`/`GIT_PROXY_COMMAND` unset,
`-c protocol.allow=never -c protocol.https.allow=always`, and curl with `-q --proto =https`. The
same review round fixed: a shared single-slot cache that one install clobbered for another (now one
file per install with a `complete=1` marker), a stale `relation=current` reported as current, a
failed compare cached fresh for 24 h, `sort -V` portability, a no-jq fallback that read a nested
`version`, relative `XDG_CACHE_HOME` writing into the project, and a bash watchdog for hosts
without `timeout`.

## Key Insight
For anything a global hook, MCP server or plugin command executes, the working directory and the
ambient environment are inputs, not context. Isolate git/curl config and cwd, key persisted state
per identity, and let a cached "no problem" answer expire into "unknown", never into reassurance.

## Session Errors
- **Planning subagent's worktree lost its `.git`; its commits landed on the main checkout's branch.**
  Recovery: `update-ref` back, re-attached the worktree with `worktree-manager.sh` (it healed a
  stale `extensions.worktreeConfig`). Prevention: verify `git branch --show-current` after any
  subagent returns before trusting its commits.
- **`pkill -f <pattern>` in a Bash call matched the call's own command line (exit 144).**
  Recovery: kill by `/proc/<pid>/cwd` match. Prevention: already hook-denied class; never `-f`.
- **Substitute test selection missed `harness-parity-tree` (a non-canonical `/version` sentence).**
  Recovery: pattern seat ran it. Prevention: run the repo's census/parity suites whenever a new
  command or skill file is added, before the review.
- **Affected gate queued behind sibling sessions for >40 min and then wedged on fork failures.**
  Recovery: killed, re-run after review. Prevention: start the gate early or let ship Phase 4 own it.
- **A tmpdir-based fixture scanner flagged test files and a plugin script (`fixture-relative-assert`).**
  Recovery: canonical `assert_fixture_dir` guards in tests; dated baseline row for the plugin script.
- **Fix-round review seats were lost when the session ended mid-run.** Recovery: applied the one
  completed seat's findings and rely on mutation-proven suites. Prevention: persist seat reports
  to files as they land (done via lead-notes).

## Tags
category: security-issues
module: plugins/soleur (version banner, plugin-version.sh)
