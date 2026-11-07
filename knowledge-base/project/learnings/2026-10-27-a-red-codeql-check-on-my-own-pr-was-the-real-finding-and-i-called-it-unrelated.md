# Learning: a red CodeQL check on my own PR was the real finding, and I filed it as "unrelated"

## Problem

PR #11233 (WikiSkill Phase 2 create arm) merged with a failing `CodeQL` check on every head, 2-3 seconds long. I read it as
a pre-existing, non-required check and kept polling the required ones. After the merge, `CodeQL Main Alert Gate` went red
on the merge commit: alert 312 (`js/file-system-race`) in `snapshotClone`, a stat-then-read I wrote in that PR. The gate
auto-filed a p1 security issue (#11275) and the fix needed a second PR, a second review and a second deploy.

## Solution

Open each path once: `open(O_RDONLY | O_NOFOLLOW | O_NONBLOCK)`, take the kind and the bytes from the same descriptor, record a
symlink (ELOOP) by `readlink`, and record anything that is not a regular file as "deleted". The review of the fix found two
more things in the same lines: a FIFO at a git-listed path would park a worker thread in `open()` forever (the old code had
the same hang), and a `close()` error could overwrite an already-computed hash. A mutation run showed each guard is pinned:
dropping `O_NONBLOCK` hangs the test to its timeout, dropping the `isFile()` check or `O_NOFOLLOW` reds it.

## Key Insight

A check that is red on your own head is evidence about your diff until you have read its name and its first line. "Not
required" describes how GitHub weighs the check, not whether it is about you. The required-check list is the merge gate;
the red-check list is the finding list. The one command that would have separated them was a single
`gh api repos/{o}/{r}/code-scanning/alerts?ref=refs/pull/N/head` on the first red run.

## Session Errors

1. **Dismissed a red CodeQL check on my own PR as unrelated.** It had failed on four consecutive heads. Recovery: follow-up
   fix PR. **Prevention:** before arming merge, read every red check's name and first log line; list code-scanning alerts for
   the PR ref and fix any that point at added lines.
2. **Two CI rounds lost to my own test suites** (a markdownlint presence assertion that failed in app-only CI legs, and git
   spawns without a constructed env in two suites). Recovery: both fixed. **Prevention:** run the repo's own
   `fixture-env-adoption.test.sh` and the app-only legs' environment before the first push, not after.
3. **The review skill's semgrep run did not flag the race.** The custom rules file covers TOCTOU patterns on `existsSync`
   and `statSync` but not `lstat` followed by `readFile`. Recovery: none needed this time. **Prevention:** extend
   `semgrep-custom-rules.yaml` with the lstat-then-read shape when a CodeQL finding slips past it (not done here).
4. **A Bash `sleep` between tool calls was blocked.** Recovery: ended the turn and waited for the task notification.
   **Prevention:** none needed (harness behaviour).

## Tags

category: workflow-patterns
module: compound-promote
