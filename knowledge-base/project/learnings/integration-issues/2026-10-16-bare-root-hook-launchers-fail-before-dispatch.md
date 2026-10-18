---
module: Development Workflow
date: 2026-10-16
problem_type: integration_issue
component: tooling
symptoms:
  - "Codex reported Hook failed with exit code 127 when started from the bare repository root."
  - "The repository rules loader and guardrails did not run because their hook commands resolved targets beneath /.claude/hooks."
root_cause: config_error
resolution_type: config_change
severity: high
tags:
  - bare-repository
  - codex-hooks
  - devin-hooks
  - git-root-resolution
  - hook-launchers
synced_to: [work]
---

# Troubleshooting: Repository hook launchers fail from a bare root

## Problem

Codex's configured SessionStart rules-loader and PreToolUse guardrails failed when the session began at Soleur's bare repository root. Their bootstrap relied on `git rev-parse --show-toplevel`, which requires a working tree; the failed substitution left an empty root and the shell attempted to run a target under `/.claude/hooks`, exiting 127. Devin's deepest Git fallback used the same worktree-only assumption.

## Environment

- Module: Development Workflow
- Affected component: repository hook launchers in `.codex/config.toml` and `.devin/config.json`
- Harnesses: Codex and Devin; Claude/Grok behavior and the existing Cursor boundary were retained
- Date: 2026-10-16
- Feature artifacts: [spec](../../specs/archive/20261016-160747-feat-one-shot-portable-hook-launchers/spec.md), [interface contract](../../specs/archive/20261016-160747-feat-one-shot-portable-hook-launchers/interface-contract.md), [plan](../../plans/archive/20261016-160747-2026-10-15-fix-portable-hook-launchers-plan.md), and [session state](../../specs/archive/20261016-160747-feat-one-shot-portable-hook-launchers/session-state.md)

## Symptoms

- Codex displayed `Hook failed` and `hook exited with code 127` when launched from the bare repository root.
- Rules-loader and guardrails targets were not dispatched from that root.
- The same failure class existed in Devin's deepest fallback, while worktree-root runs did not expose it.

## What Didn't Work

**Using `git rev-parse --show-toplevel` as the only root probe:** It works from a checkout but fails from a bare repository, so it cannot locate the configured repository hook targets in both layouts.

**Reusing the installed-plugin root resolver:** These are repository-owned hooks, and locating a helper under the repository would require the same unresolved root bootstrap. The plan therefore retained a bounded inline fallback instead of adding a dispatcher.

## Session Errors

1. **Guessed diagnostic paths were absent.** Recovery: inspected the actual directory and SQLite layouts. **Prevention:** derive diagnostic paths from the repository or runtime's real layout before querying guessed locations.
2. **The GNU Bash documentation fetch was unavailable, and the optional critical-patterns file was absent.** Recovery: used executable shell tests as the behavior evidence. **Prevention:** record unavailable references as unavailable and use bounded execution tests for shell semantics rather than assuming either resource exists.
3. **A config-agent orchestration snippet had a JavaScript template parse error before any side effect.** Recovery: corrected the string quoting. **Prevention:** syntax-check orchestration snippets before invoking tools or delegating work.
4. **The initial GREEN log redirect failed because the new worktree lacked `.soleur`.** Recovery: created the directory and reran; only completed suite results were counted. **Prevention:** create and verify a worktree-local log directory before redirecting test output into it.
5. **The initial manual Devin registration count was off by one.** Recovery: native registry traversal and frozen expectations corrected the count. **Prevention:** derive registry populations structurally and assert them instead of relying on manual counting.
6. **A read-only diagnostic command was accidentally run from another worktree, where `git status` failed outside a worktree.** Recovery: returned to the correct worktree without reading or modifying the other branch. **Prevention:** verify the current directory and worktree before running repository-scoped diagnostics.
7. **Semgrep 1.180 under Python 3.15 repeatedly crashed in `semgrep-core`; the probes exited 2 and generated systemd coredumps.** Recovery: symbolized the crash, identified the Python 3.15 stack-limit incompatibility, then used Semgrep 1.181 under Python 3.14 and verified the scan. This was separate from the hook-launcher defect. **Prevention:** check Semgrep and Python compatibility when a minimal scan crashes before matching targets, and use isolated version probes before changing shared tooling.
8. **A cleanup command was rejected by a command guard before execution.** Recovery: left the files untouched and continued without cleanup. **Prevention:** treat a guard rejection as a hard stop for that command and do not retry through another execution path without authorization.
9. **The Semgrep bootstrap was first invoked from the wrong path, then the tracked script was invoked directly despite lacking executable mode.** Recovery: invoked the correct script through `bash`, which passed. **Prevention:** verify the tracked path and file mode, then invoke non-executable shell scripts explicitly with `bash`.
10. **The default Semgrep `io_uring` scan failed before reaching targets.** Recovery: retried with `EIO_BACKEND=posix` and `-j 1`, which passed. **Prevention:** when the backend fails before file scanning, retry the focused scan with the supported POSIX backend and one worker, and record the backend used.
11. **The broad `gh pr checks` payload was truncated by output limits.** Recovery: reran it as concise, bounded `jq` summaries. **Prevention:** summarize check states and names in `jq` before printing GitHub API payloads, and bound the number of emitted rows.
12. **`git status` initially ran from the bare repository root and failed with `fatal: this operation must be run in a work tree`.** Recovery: inspected `git worktree list` and continued in the PR worktree. **Prevention:** verify worktree context before repository status commands.
13. **An `apply_patch` attempt failed because expected text no longer matched after a concurrent update.** Recovery: reread the exact lines and retried the patch. **Prevention:** refresh the target immediately before applying a patch after concurrent edits.
14. **The ADR-ordinal check was first called from a nonexistent plugin-relative path and exited 127.** Recovery: located the tracked script at `scripts/check-adr-ordinals.sh` and reran it successfully. **Prevention:** locate the tracked path before running repository-specific checks.
15. **The staged `git diff --check` flagged an extra blank line at EOF.** Recovery: removed the blank line and reran the check. **Prevention:** run diff-whitespace validation after final documentation edits.
16. **A performance optimization initially used Bash-only substring expansion in commands that can run under POSIX `sh`.** Recovery: code-quality review reproduced the failure in `dash`; the parser was changed to portable shell tools and exercised under `dash`. **Prevention:** execute registered commands with each supported shell, including both success and failure paths.
17. **Two `sed` processes per fallback made the proposed optimization slower than the original three-Git path.** Recovery: consolidated the metadata parsing into one `sed` process and remeasured. **Prevention:** benchmark the complete final command, including parsing overhead, rather than counting only removed subprocesses.
18. **An attempted newline-delimiter parser was escaped incorrectly and allowed malformed metadata through.** Recovery: replaced it with a single `sed` parser and tested its outputs. **Prevention:** test shell escaping through the actual TOML/JSON registry strings before replacing a known-good parser.
19. **A pipeline from Git into `sed` hid Git's nonzero exit when Git emitted partial metadata.** Recovery: captured and checked Git's status before parsing; added a partial-output failure fixture across all affected registrations. **Prevention:** preserve and test producer exit status whenever parsing command output.
20. **The POSIX executable was not at the hard-coded `/bin/dash` test path.** Recovery: resolved `dash` through the test PATH with `Bun.which`. **Prevention:** discover optional test interpreters through the environment instead of assuming a platform path.
21. **A fix-round agent launch hit the active collaboration thread limit.** Recovery: waited for completed review threads and reused them for the remaining checks. **Prevention:** account for the four total collaboration slots, including the caller, before scheduling a new review wave.
22. **An exact-match scripted replacement expected the wrong JSON-escaped form and stopped before changing that file.** Recovery: inspected the serialized substring and guarded the corrected replacement by the expected count. **Prevention:** inspect exact serialized text and verify match counts before writing generated configuration.
23. **An `apply_patch` bundle included a nonexistent context line and was rejected without editing either file.** Recovery: split it into the valid work-skill edit and the separately reviewed learning update. **Prevention:** keep patches anchored only to context already read from each target.

## Solution

The launcher bootstrap tries `git rev-parse --show-toplevel` first, preserving the active checkout for ordinary and linked worktrees. If that fails, it captures the exit status from one combined `git rev-parse --is-bare-repository --absolute-git-dir` probe before parsing its two-line output. It requires the first line to be exactly `true`, validates a non-empty Git directory, and removes only a terminal `/.git`. One `sed` process joins the metadata lines for POSIX-safe shell parsing; failed or partial Git output cannot fall through to a hook target. The fallback works under `dash` and uses two Git launches instead of three.

The bounded fallback was applied to both Codex hook commands and every affected deepest Git fallback in Devin. Devin's existing `CLAUDE_PROJECT_DIR` then `DEVIN_PROJECT_DIR` override precedence remains intact. The launchers preserve each registered target, interpreter, argument tail, working directory, stdin, output streams, and exit status. They do not search another checkout when the selected root or target is missing.

Verification recorded for the feature included 213 passing launcher, Codex setup/plugin, and Devin harness tests; 12 additional Devin setup/backstop parity tests; and 9 matcher/disposition parity tests, including enumeration of all 111 registrations and permission rules. Mutation checks rejected the original bootstrap and five other isolated regressions. The feature plan and spec are archived at the paths linked above as part of the ship workflow.

## Why This Works

`git rev-parse --show-toplevel` reports a checkout's working-tree root; a bare repository has no working tree and therefore no top-level directory to report. Its failure is not proof that Git is unavailable or that the selected root should be guessed. Testing `--is-bare-repository` distinguishes the supported bare-root case before obtaining the absolute Git directory. Stripping only `/.git` maps Soleur's bare root correctly while leaving conventional bare repository paths unchanged.

Keeping checkout discovery first prevents linked-worktree commands from being redirected to a common checkout. Chaining the target invocation to successful root assignment prevents an empty substitution from launching an accidental root-level path. The same bounded rule therefore supports bare and working checkouts without changing hook dispatch semantics.

## Prevention

- For repository hook launchers that must run from both working and bare checkouts, try `--show-toplevel` first and use `--absolute-git-dir` only after a positive bare-repository check; capture the producer status before parsing its output.
- Keep root assignment and target dispatch fail-closed; test that failed resolution does not invoke any target.
- Execute commands extracted from the actual harness registries against ordinary, nested, linked-worktree, Soleur-style bare, and conventional-bare fixtures, with spaces and failure cases. Test each supported shell on successful and failed discovery paths.
- Preserve selected-checkout ownership and independently freeze command interpreter, target, and argument expectations before editing the registries.

## Related Issues

- See also: [Bare-repository `rev-parse` failure in worktree-manager](../2026-03-13-bare-repo-git-rev-parse-failure.md) — earlier instance of `--show-toplevel` failing in a bare repository, in a different launcher.
- See also: [Bare-repository plugin hook sync gap](../2026-03-20-bare-repo-plugin-hook-sync-gap.md) — related bare-root hook behavior involving synchronization rather than target-root discovery.
- See also: [Session-start command substitution allow rule](../2026-02-26-allow-rule-for-session-start-command-substitution.md) — prior learning about repository-root discovery in a session-start command.
