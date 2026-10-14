---
title: "My test stub was bypassed by env, and my harness verified the first definition while bash ran the last"
date: 2026-09-24
category: test-failures
tags: [shell, test-harness, stubs, cutover-inngest, better-stack, hetzner]
related: [8759, 8767, 7674, 6616]
---

# Learning: two ways a shell suite verified code that does not run

## Problem

PR #8759 scoped op=resume's G3 check (and op=arm G3.7 H and LUKS G3) to the current
Hetzner server generation. The suite executes the real functions by awk-extracting them from
`scripts/cutover-inngest.sh` and `eval`-ing them beside bash-function stubs for `doppler` and
`curl`. Two properties of that pattern each let the suite certify code that production does
not run:

1. **`env -u VAR … curl` execs the real `curl` binary.** Adding `env -u SSLKEYLOGFILE …` in
   front of the curl call (a review fix) silently bypassed the test's `curl()` function stub —
   every mode read `__UNREADABLE__` because the suite was now hitting the real
   `api.hetzner.cloud` with a sentinel token. Command lookup for `env`'s argument never sees
   shell functions.
2. **The harness evals the FIRST definition; bash runs the LAST.** A one-line
   `_inngest_server_created_epoch() { printf "%s" 1735689600; }` added later in the file
   floors at 2025-01-01 (re-admitting every predecessor row) while the suite stayed 877/0 —
   the extractor matched only the original multi-line definition.

## Solution

- Unset the TLS/keylog variables in a SUBSHELL around the call
  (`| ( unset SSLKEYLOGFILE …; curl --disable … )`), so function lookup still applies.
- Pin exactly one definition per extracted function, counting every spelling:
  `grep -cE "^[[:space:]]*(function[[:space:]]+)?NAME[[:space:]]*(\(\))?[[:space:]]*\{"` == 1.
- Make the stubs replay the real contract (the curl stub requires `--disable` first, `--get`,
  `-w '\n%{http_code}'`, `-H @-`, `--proto =https`, `--max-time <= 30`, the exact URL; the
  doppler stub matches the full argv), record every miss in a ledger asserted empty, and give
  the ledger a positive control that proves both stubs can reject.

## Key Insight

An extract-and-eval harness is only as faithful as its binding: anything that changes which
definition, or which *kind* of command, the name resolves to (a later redefinition, `env`,
`command`, `exec`, an absolute path) silently moves the code under test out from under the
suite. Pin the resolution, not just the behaviour.

A second, smaller one: when two reviewers disagree about a system fact (here, whether Better
Stack's `dt` is the host's event time or the warehouse's receive time), one read-only query
settles it faster than any argument — `dt` equals `ingest_time` byte-for-byte for the Vector
source, ~1 s after the journald `timestamp`, shared across a batch. The repo's own query
runbook had it labelled "event time"; corrected.

## Session Errors

1. **Plan-write guard refused two plan edits** (literal Doppler write verb in prose). Recovery:
   reworded. **Prevention:** already hook-enforced; plan prose says "the Doppler write of the flag".
2. **Filing gate refused the #8767 filing twice** (body file must pre-exist; `Mandated-By:`
   line). Recovery: wrote the body file first. **Prevention:** already documented in review §5.
3. **`git stash list` typed inside two compound commands**; the hook blocked the whole call,
   dropping a co-located edit. Recovery: re-ran without it. **Prevention:** hook-enforced; keep
   git-state probes out of compound edit commands.
4. **`env -u … curl` bypassed the curl stub; the suite hit the real Hetzner API.** Recovery:
   subshell `unset`. **Prevention:** work-skill Sharp Edge (this PR).
5. **New code tripped two existing pins** (the word `curl rc=` in messages counted as an
   unconfined curl; a jq program mentioning `fromdateiso8601` was swept into the #6178
   bucketing extraction). Recovery: `transport rc=`, `strptime`. **Prevention:** run the owning
   suite after every edit to a file other suites parse by shape (done; caught immediately).
6. **The widened rebuild pin matched its own source line.** Recovery: bracketed first letter
   (`actions/[r]ebuild`). **Prevention:** a repo-wide negative grep in a test file must not
   contain its own literal.
7. **A `$(printf '%s\n' …)` fixture lost its trailing newline to command substitution**, so the
   trailing-newline row was vacuous until rebuilt with `$'\n'`. **Prevention:** work-skill
   Sharp Edge (this PR).
8. **The PR was CONFLICTING (a sibling merged into the same suite's floor), so no
   `pull_request` CI ran** until review merged `main` in. **Prevention:** already in review
   Step 1 (`merge-tree` + `mergeable` before the panel); run it right after pushing too.
9. **Local affected gate stopped at 96/181 (0 failures) under load 36/16 cores**, by operator
   decision; CI owns the full battery. **Prevention:** `test-all.sh --capacity` before
   launching; say which mode ran.
10. **`kill_mine test-all.sh` left orphaned vitest children in the worktree.** Recovery: killed
    by `/proc/<pid>/cwd`. **Prevention:** already documented in work §Common Pitfalls.
11. **A pre-existing registry-probe mutation row flaked** only while another copy of the suite
    ran concurrently; two isolated re-runs were clean. **Prevention:** re-run a red row alone
    before attributing it; one-off.
12. **P1 (review): first-definition extraction was a fail-open.** Recovery: one-definition pins
    for seven functions. **Prevention:** this learning; the pin.
13. **Two reviewers disagreed on `dt` semantics.** Recovery: live query. **Prevention:** the
    corrected `betterstack-log-query.md` line tells the next reader to measure per source.
14. **The stubs answered any request** (test-design review). Recovery: contract-replaying stubs
    plus a miss ledger with a positive control. **Prevention:** existing work-skill rule on
    PATH-shimmed fakes; applied.
15. **Route-to-definition hit the work skill's byte ceiling** (`lint-skill-body-budget`: 737 over),
    and the first revert used `git checkout --`, which restores from the INDEX where the edit was
    already staged — the next commit failed again. Recovery: `git restore --source=HEAD --staged
    --worktree`. **Prevention:** already documented in work §REGENERATE (name the restore source);
    the routing was skipped because the suite's one-definition pin enforces the lesson mechanically.

## Tags
category: test-failures
module: scripts/cutover-inngest.sh, apps/web-platform/infra/cutover-inngest-workflow.test.sh
