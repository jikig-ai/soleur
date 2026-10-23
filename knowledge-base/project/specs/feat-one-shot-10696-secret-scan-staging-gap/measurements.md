# Measurements: would-be index for git-commit-secret-scan (#10696)

Host: Linux 7.2.8, 16 cores, git 2.56.0, `/tmp` is tmpfs (the scratch worktree lived there), gitleaks 8.30.1 on
PATH except where stated. The host was shared and never idle (load average 7 to 29 during the runs; values are
stated per table). All timings use `date +%s%N` and are Linux-only.

## AC13: latency (gate: p95(b) - p95(a) at most 1.5 s)

Scratch worktree of this repo (19,855 tracked files), 5 modified tracked files and 3 untracked files, 30 interleaved
iterations (order of the (b) and (c) runs alternated per iteration), load 7.7 at start and 9.9 at end.
(a) = today's hook (commit 0f811f2ac2) on `git commit -m x` with the files already staged;
(b) = the new hook on `git add -A && git commit -m x`, files unstaged;
(c) = today's hook on the same chained command, unstaged (what users feel today).

| Series | p50 ms | p95 ms (29th of 30) | min ms | max ms | decisions |
|---|---|---|---|---|---|
| (a) old hook, staged commit | 1273 | 2814 | 996 | 3110 | 30 allow |
| (b) new hook, chained | 1398 | 2761 | 1138 | 2781 | 30 allow |
| (c) old hook, chained, unstaged | 1148 | 2735 | 916 | 2817 | 30 allow |

| Statistic | Value |
|---|---|
| p95(b) - p95(a) | -53 ms (gate: <= 1500 ms): PASS |
| paired p50 difference (b - a) | +70 ms (p95 of the paired differences: +458 ms) |
| p95(b) - p95(c) | +26 ms |

Liveness check in the same worktree: with one untracked synthetic PEM file the new hook denies in 1047 ms and the old
hook allows in 944 ms, so (b) really builds and scans the simulated index.

Non-gating runs (new hook, same worktree):

| Case | Result | Cap / expectation |
|---|---|---|
| 5,000 small untracked files | 1319, 1326, 1334 ms (old hook: 913 ms) | cap 5 s: PASS |
| one 5.3 MB high-entropy untracked text file | 2919, 3624 ms (old hook: 1082 ms) | about 7 s expected: better |


## AC13 re-measure on the review-round tree (final tree, short run)

The review round changed the hook (bound prefix, the lexer on every strict commit where perl exists, plan-once,
fallback-only roots scanned against the real index, sanitised deny text), so AC13 was re-measured with the same method
as above (`ac13.sh`: scratch worktree of this repo, 5 modified tracked files and 3 untracked files, interleaved
iterations, order of (b) and (c) alternated), shortened to 16 iterations because the host was busy (load average
18.8 at the start and 12.7 at the end, gitleaks 8.30.1). The p95 is the 16th of 16 sorted samples (the maximum).

| Series | p50 ms | p95 ms | min ms | max ms | decisions |
|---|---|---|---|---|---|
| (a) old hook, staged commit | 1520 | 2232 | 1189 | 2232 | 16 allow |
| (b) new hook, chained | 1599 | 2570 | 1320 | 2570 | 16 allow |
| (c) old hook, chained, unstaged | 1477 | 2087 | 1244 | 2087 | 16 allow |

| Statistic | Value |
|---|---|
| p95(b) - p95(a) | +338 ms (gate: <= 1500 ms): PASS |
| paired p50 difference (b - a) | +86 ms (p95 of the paired differences: +367 ms) |
| p95(b) - p95(c) | +483 ms |

Liveness check in the same worktree with one untracked synthetic PEM file: the new hook denies in 1504 ms and the old
hook allows in 1483 ms, so (b) really builds and scans the simulated index. The lexer now runs on every strict commit
where perl exists; the earlier measurement put it at about 13 ms.

## AC14: lexer-failure ceiling (counts only; limit 0.5 percent) and multi-root frequency

Source: read-only extraction of the Bash command text and cwd of `git commit` tool calls from the local session
transcripts (7,555 files), then each command through the old and the new `ctr_wants_lex` and the new `ctr_collect`.
No command text is stored in this repository or printed.

| Measure | Count |
|---|---|
| strict `git commit` commands | 4,692 |
| reach the lexer under the old pre-filter | 2,733 (58.2 percent) |
| reach the lexer under the new pre-filter | 4,622 (98.5 percent) |
| newly lexed (incremental lexer rate) | 1,889 (40.3 percent); lexed before and not now: 0 |
| newly lexed and landing in `lex_state=unavailable` | 0 |
| newly lexed and carrying a `CTR_BAD` deny | 0 |
| newly failing in total | 0 (0.000 percent of all strict commit commands): PASS |
| lexed commands failing for reasons that pre-date this change | 333 |
| commands where the simulation runs (`CTR_COMMIT_STAGES=1`) | 4,109 (87.6 percent) |
| of those: opaque (superset) / refused | 222 / 2 |

The 5 percent incremental rate in the plan was measured on commit messages alone; the large share is the
`git add ... && git commit` chain, which the plan expected (about 77 percent of commits).

Multi-root frequency among the 4,109 staging commands (two scanned roots force the superset; roots are derived the way
the hook derives them, from the cwd and the literal `cd` / `-C` targets; a directory that no longer exists is counted as
its own root, so this is an upper bound):

| Topology (by session cwd) | Staging commands | More than one root | Share |
|---|---|---|---|
| worktree-anchored | 3,889 | 132 | 3.4 percent |
| bare-root-anchored | 126 | 2 | 1.6 percent |
| main-checkout-anchored (a `cd` into a worktree) | 94 | 79 | 84.0 percent |
| total | 4,109 | 213 | 5.2 percent |

## Suite wall time (the unchanged suite versus the suite with the new arms)

Alternating runs, both against gitleaks 8.24.2, the full suite each time.

| Run | Assertions | user s | sys s | real s | load start to end |
|---|---|---|---|---|---|
| before (1) | 405 | 195 | 26 | 244 | 16.1 to 21.9 |
| after (1) | 894 | 273 | 52 | 351 | 21.9 to 16.0 |
| before (2) | 405 | 170 | 23 | 190 | 16.0 to 14.2 |
| after (2) | 894 | 174 | 41 | 212 | 14.2 to 8.4 |

Added time on the quieter pair: +21 s real, +22 s CPU (user plus sys), under the 60 s budget. The loaded pair
(+107 s real) is host contention, not work. The canary tier was therefore not trimmed.

## Canary arms against the pinned gitleaks 8.24.2

Tarball from the URL in `.github/workflows/ci.yml`, sha256 `fa0500f6...151a8e` verified, extracted in a scratch
directory. The full suite (all canary arms included) passed: 894 passed, 0 failed, 0 skipped.

## Mutation matrix (Guard 1 and Guard 2) and harness rows

Each row was applied to a sandbox copy, the named arms were run, and the file was restored from a saved pristine copy and
confirmed with `cmp`. Every mutation was confirmed to have landed (the pattern matched exactly once, the file differed from
the pristine copy, and `bash -n` passed).

| Row | Mutation | Result |
|---|---|---|
| G1-1 | delete the staging-verb clause from `ctr_wants_lex` | RED (69 failing) |
| G1-2 | force `CTR_COMMIT_STAGES=0` in the walker | RED (107) |
| G1-3 | replay stops after the first add record | RED (G3h) |
| G1-4 | `cis_unexport` before `scan_root` (REORDER) | RED (44) |
| G1-5 | treat `-p` as a replayable option | RED (4) |
| G1-6 | a failed superset allows | RED (8) |
| G1-7 | drop the one-root rule | SURVIVED: equivalent, see below |
| G1-7b | drop the one-root rule AND the replay-directory-belongs-to-root check | RED (X1f, X1g) |
| G1-9 | any replay failure is warn-and-allow | RED (9) |
| G1-10 | accept a cd that is not the first record as the directory proof | RED (4) |
| G1-11 | allow pathspec-missing despite a producer | RED (2) |
| G1-12 | `-c` handled without the config refusal (nothing is forwarded in this design) | RED (2) |
| G1-13 | drop `checkout` from the stage-unknown list | RED (3) |
| G2-1 | replay against the real index (skip the copy) | RED (5) |
| G2-2 | omit the quarantined `GIT_OBJECT_DIRECTORY` | RED (5) |
| G2-3 | remove the sim directory from `cleanup` | RED (4) |
| G2-4 | revert INT/TERM to a cleanup-only handler | RED (2: rc 0, stdout not empty) |
| G2-5 | drop the `core.splitIndex=false` pin | RED (5) |
| G2-5b | drop the `core.fsmonitor=false` pin | RED (1: G12c3) |
| H1 | shim stops logging arguments | RED (self-test FATAL) |
| H1b | shim never classifies a call as a sim call | RED (30) |
| H2 | snapshot taken after the run | RED (self-test FATAL) |
| H3 | the G1 fixture stages the leak (old shape) | RED (6: the gap-witness controls fail) |

G1-7 is an equivalent mutant, not a fixture gap. Two independent defences protect a second root: the one-root rule, and
the check that the replay directory belongs to the root being built (otherwise that root falls back to the superset).
Removing the first alone changes nothing observable; the new arm X1f (process cwd = leaky repo B, payload cwd = clean
repo A) plus G1-7b prove that removing both loses B's leak.

## Hook timeout and failure handling (documentation re-check)

Source: https://code.claude.com/docs/en/hooks (read through a fetch, which summarises long pages; the quoted sentences
should be re-checked on the page before anyone relies on the exact wording).

- Default timeout for a command hook: 600 seconds ("Defaults: 600 for `command`, `http`, and `mcp_tool`"); the `timeout`
  field is in seconds. PreToolUse is not in the lower-default list.
- A timed-out PreToolUse command hook does not block the tool call, except for hooks whose failure blocks the action.
- `onFailure` exists: `"continue"` or `"block"`, "requires Claude Code v2.1.295 or later"; the page gives `continue` as the
  default for HTTP hooks and states no default for command hooks (an unset field behaves as non-blocking). A timeout
  counts as a failure.
- Blocking: exit 2, or JSON `permissionDecision: "deny"`. Any other non-zero exit is non-blocking.

This hook always exits 0 and carries its verdict in JSON; its own 30 s simulation deadline is therefore well inside the
600 s default, and an expired simulation denies instead of relying on the harness.
