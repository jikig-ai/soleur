---
module: System
date: 2026-10-08
problem_type: integration_issue
component: tooling
symptoms:
  - "Converted `SIG=$(printf .. | HMAC_KEY=.. python3 -I -c '..k or sys.exit(1)..')` exits 1 with no output at all when the key is empty or python3 is missing, at 17 call sites under set -euo pipefail"
  - "Every suite green on bash 5.3.15 / curl 8.22.0 while two P1s existed only on the CI runner userland (bash 5.2.21, curl 8.5.0)"
  - "Repo-global fixture-relative ratchet red after the fixes although no consumer-grep selected it"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [argv-credential-sweep, set-e, command-substitution, ci-toolchain-parity, mutation-battery, review-process]
synced_to: [work]
---

# Learning: a pipe-tail swapped inside `$(...)` changes the failure mode, and a suite green on the dev host proves nothing about the runner

## Problem

Slice S2 of the argv-credential sweep (PR #9753) moved HMAC keys off `openssl dgst -hmac` argv onto a python3 child's environment. Two defects shipped past the plan, the deepen pass, two self-run mutation batteries and 20 green suites, and were found only by review.

1. **Mute abort.** `SIG=$(printf '' | openssl dgst -sha256 -hmac "$K" | sed 's/.*= //')` always exits 0 (openssl signs with an empty key), so an empty `WEBHOOK_SECRET` reached the host, got a 403 and printed the arm's `::error::` remedy. The replacement `SIG=$(... python3 -I -c '... k or sys.exit(1) ...')` fails on an empty key or a missing python3, and under `set -euo pipefail` a failing bare assignment ends the script at that line: rc 1, no `::error::`, no marker. Seven of thirteen review seats converged on it independently. Every row asserted the snippet in isolation, never the arm that contains it.
2. **Toolchain skew.** The real-curl lint oracle used a sink URL with an empty path, so curl 8.5.0 aborts `-O` (rc 23) before recording the user, and its floors were totals of one curl build. A battery mutant put `<(` inside the replacement of `${v//pat/"repl"}`, a parse error on bash 5.2. Both were green on the dev host (bash 5.3.15, curl 8.22.0) and red on ubuntu-24.04. A verification seat found them only by running the suites in an `ubuntu:24.04` container.

## Solution

- Append `|| VAR=""` after each substitution so the existing shape guard (`_sig_curl` -> `_bearer_ok`) refuses with the value-free marker; add a behavioural row per site that runs the REAL arm with the key empty, unset and python3 absent, asserting the marker once, the arm's own `::error::`, zero curl calls and a non-zero rc.
- Give the oracle's sink URL a path, state floors as invariants over NAMED character sets and make the alphabet check a superset test, assign the `${v//pat/repl}` replacement to a variable first, and require the affected suites green in the host AND an `ubuntu:24.04` container with identical row counts.
- Run the repo-global ratchets by hand (`fixture-relative-assert`, `fixture-dir-operand-assert`, `lint-shell-capture-exit`, `lint-window-closure-assertion`, `lint-trap-tempfile-ownership`): a consumer-grep never selects them. Guard new fixture writes with the canonical `assert_fixture_dir`, placed BELOW the xtrace refusal (above it the Rule A prologue lint fails).

## Key Insight

A tool swapped inside a command substitution carries its exit semantics with it: whoever wrote the old pipe tail (`sed`, always 0) made "empty input" a visible downstream error, and the new tail (`sys.exit(1)`) makes it a silent script exit. Assert the failure behaviour at the CALL SITE, not in the snippet. And a suite's green is a statement about the toolchain it ran on: verify new shell tests on the runner's userland before pushing, and never write a floor that is the count of one tool build.

## Session Errors

**Empty-key / missing-python3 conversion aborted mute at 17 sites (found by 7 review seats, not by plan, deepen or the batteries)** — Recovery: `|| VAR=""` at each site plus behavioural arm rows — **Prevention:** when a PR replaces the tail of a `$(...)` capture, list the old and new tool's exit status for empty/absent input and fixture the enclosing arm, not the snippet.

**Two P1s existed only on the CI toolchain (curl 8.5.0 `-O` rc 23; bash 5.2 `<(` in a `${//}` replacement)** — Recovery: sink path, named-set floors, replacement via variable; verified in an ubuntu:24.04 container — **Prevention:** run each new/changed bash suite once in a container matching the runner (`docker run --rm -v "$PWD":/w ubuntu:24.04`) before the first push; state tool-dependent floors as invariants over named sets.

**Repo-global ratchets found red only by running them by hand after review (`fixture-relative-assert` +100 sites; a 87-row battery entry)** — Recovery: canonical `assert_fixture_dir` guards, regenerated baseline last — **Prevention:** add the five ratchet suites above to the pre-push list of any PR that adds shell test files; regenerate a baseline only after all fix commits land.

**Helper inserted above the xtrace refusal in `learning-retrieval-bench.sh` failed the Rule A prologue lint (10 commands before the refusal)** — Recovery: moved the helper below the refusal — **Prevention:** put any new top-level function after the `case "$-"` refusal block in scripts that handle credentials.

**Plan facts the deepen pass left wrong, falsified by review: #9736's merge time (00:35:36Z, not 00:13Z), the soak probe's refusal exit (3, not 2), and a post-merge marker check that read only the last tracker comment (blind to closed trackers and stale comments)** — Recovery: corrected plan, decisions file and the check (sweeper dry-run log) — **Prevention:** `gh pr view <n> --json mergedAt` for every cited merge time; grep every consumer of an exit code before tabulating it.

**Fix agents in isolated worktrees started on a newer main, so `git merge --ff-only <sha>` failed (4 agents)** — Recovery: `git reset --hard <sha>` on the empty worktree — **Prevention:** brief isolated fix agents with `git reset --hard <sha>`, not ff-only.

**A fix agent twice ended its turn "waiting on the battery monitor" with uncommitted edits and no report** — Recovery: SendMessage telling it to run the suite in the foreground with a timeout, commit green work and report — **Prevention:** brief fix agents that waiting on a background monitor is not a deliverable; foreground with `timeout`, log to a file, commit, report.

**Stop hook "unkept promise" fired on first-person future phrasing in closing text (about eight times)** — Recovery: restated the block as a present-tense fact — **Prevention:** when blocked on background agents, close with a factual `<stop>BLOCKED: ...</stop>` that names the blocker and carries no "I will".

**Two Bash calls were blocked by hooks for their TEXT (`git stash list` inside a compound; `ps … | awk '/pattern/'` self-match)** — Recovery: re-issued without the text / used `ls` and git log instead — **Prevention:** never type `git stash` or `ps | awk '/<pat>/'` in a command even as a read; use `git log`, rc files and captured PIDs.

**Four CI-only reds after every local gate was green: two other suites stubbed curl and parsed `-u` (one under `apps/web-platform/infra/`), the affected-tests edge list did not name five records the sweep suite now reads, and two probes printed a broken-pipe line when the runner inherits an ignored SIGPIPE** — Recovery: stubs read the stdin config line (and reject `-u`), five edges added, the config writer's stderr silenced inside the process substitution; the infra-path stub edit was approved by the operator because it fires the push-triggered apply — **Prevention:** when a PR changes HOW a credential reaches a shared script, grep every test stub of the transport (`-u)`, `--user`, `Authorization`) across the whole repo, not only suites that name the script; run the sweep suite once under `trap '' PIPE` (CI harnesses ignore SIGPIPE) and run `scripts/test-affected-kb-consumers.test.sh` whenever a suite gains a `knowledge-base/` read.

**Session `cd` to the repo root left the Bash CWD outside the worktree for one call** — Recovery: chained `cd <worktree> &&` — **Prevention:** chain `cd <abs-worktree> &&` in every call after any `gh`/path probe that changed directory.

## Tags

category: integration-issues
module: System
