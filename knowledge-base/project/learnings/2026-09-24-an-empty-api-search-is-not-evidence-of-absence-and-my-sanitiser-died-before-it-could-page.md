---
title: "An empty API search is not evidence of absence, and my annotation sanitiser died before it could page"
date: 2026-09-24
category: integration-issues
module: .github/workflows/web-platform-release.yml (resolve-target)
tags: [github-actions, runs-api, eventual-consistency, pipefail, sigpipe, deploy, fail-closed]
pr: 8770
---

# Learning: an empty API search is not evidence of absence

## Problem

The deploy arm of Web Platform Release (`resolve-target`, `workflow_run` trigger) decided whether
a SHA had a release to deploy with ONE call to
`GET actions/workflows/web-platform-release.yml/runs?event=push&head_sha=<sha>`. An empty answer
was read as "`on.push.paths` declined this push" and the run clean-skipped GREEN. On 2026-09-24
(run 36050118687 attempt 1) that search answered `[]` at least 13 minutes after the push-arm
release (run 36047804812) had published; production stayed on the previous build until a manual
re-run.

`event`, `head_sha`, `branch`, `status`, `check_suite_id` are documented **search** parameters of
the list-runs endpoint. The unfiltered list (no search params) was current while the search was
stale. Over 200 runs, 1 of 10 attempt-1 `no_release_run` verdicts was false.

## Solution

- Up to 4 lookups, 20 s apart, each reading the filtered search and then the UNFILTERED list,
  selected client-side (`event == "push" and head_branch == "main" and head_sha == $sha`). The
  unfiltered read is a locator only; identity is still bound against the artifact.
- Only when both stay empty, diff `<sha>~1..<sha>` under the release pathspec (the same range
  `check_changed` uses). Empty diff → the old green clean skip. Deployable or uncomputable diff →
  a new LOUD reason, `release_run_missing`. The diff never turns a deploy ON.
- `exec 3>&1` so `::error::` lines inside `x=$( … )` reach the log (they were being captured and
  lost on every `github_api_unavailable`); `shopt -s inherit_errexit`; `[skip_reason=<reason>]`
  carried in the annotation because job outputs are not readable through the REST API.

## Key Insight

**An empty answer from a SEARCH is a statement about the search index, not about the world.**
When a green verdict rests on absence, ask what else could produce the empty answer (index lag,
pagination, a filter the index applies differently) and demand an independent discriminator —
here, the commit's own diff — before reading absence as "nothing was due".

**Second, from review: the code I added to REPORT the failure could kill the step before it
reported.** `_files=$(printf '%s\n' "$_changed" | head -n 3 | … )` under `pipefail` is an
assignment whose writer takes SIGPIPE when `head` exits early; on a diff over the pipe buffer
(every run at 1000+ files) the assignment returned 141 and the step died before `fail_closed`
wrote a `skip_reason` — so notify-gated never paged. Five review seats reproduced it
independently. An early-exit reader (`head`, `grep -q`, `grep -m`) belongs in a function
ARGUMENT (status ignored) or behind a here-string with a reader that consumes all input
(`sed -n '1,3p' <<<"$x"`), never in an assignment under `set -eo pipefail`.

## Session Errors

1. **A counter advanced inside `$( )` in a fixture helper** (`CLONE=$(mkshallow …)`). Recovery:
   switched to `mktemp -d`. **Prevention:** a helper called as `x=$(fn)` may only communicate
   through stdout; mint uniqueness from `mktemp`, never a shell counter.
2. **Row-floor derivation claimed 16 new rows; 14 were added.** Recovery: the floor fired and the
   comment was re-derived. **Prevention:** derive the floor from a green run's own count, then
   write the itemised comment to match it.
3. **AC11 (`grep -c fetch-depth` == 0) tripped on my own explanatory comment.** Recovery: reworded
   the comment. **Prevention:** `cq-assert-anchor-not-bare-token` — when an AC greps a token,
   never write that token in prose inside the scanned region.
4. **Fixture-relative/operand ratchets went red on new unasserted fixture writes.** Recovery:
   `assert_fixture_dir` on both write roots; baseline row dropped (a real remediation).
   **Prevention:** already in work §6.6; followed.
5. **`battery-tag-authorship` red: a fixture `git fetch` without `--no-tags`**, caught only by the
   60-minute affected gate. Recovery: added `--no-tags`. **Prevention:** covered — the suite is in
   the affected gate's always-on set; run `bash scripts/battery-tag-authorship.test.sh` alongside the
   §6.6 fixture ratchets when a suite adds a fixture `git fetch`. (A work-SKILL routing was attempted
   and dropped: the skill body is at its ADR-229 byte ceiling.)
6. **Mutation-battery H3 did not revive its mutant** as the plan predicted (A2's exact `rc -eq 1`
   kills it independently). Recovery: recorded as a deviation in `mutation-evidence.md` rather
   than claimed. **Prevention:** a plan's predicted battery outcome is a claim; record what ran.
7. **The SIGPIPE `head`-in-an-assignment pipeline shipped** (see Key Insight). Recovery: here-string
   plus `sed -n`, bash substring cap, row LBIG. **Prevention:** the Key Insight above. Not
   routed to the work skill (body at its byte ceiling); a lint over workflow `run:` bodies for
   `x=$(… | head …)` is the durable form.
8. **Comment-stripping the whole G8 window flagged two pre-existing consumers** (scope creep).
   Recovery: scoped the strip to the new fallback rows. **Prevention:** when tightening a shared
   guard, run it before committing and scope the tightening to the members the PR adds.
9. **New Slack/doc text used `-e push`**, outside G8's accepted arm-naming tokens. Recovery:
   `--event push`. **Prevention:** grep the new prose with the repo's guard before commit (the
   invariants suite does, if run).
10. **W2 counted only line-leading `clean_skip` producers**, so `cond && clean_skip … no_release_run`
    survived. Recovery: count any call on any line. **Prevention:** a producer-count guard
    quantifies over CALLS, not line shapes — mutate with a guarded one-liner.
11. **The `rc-sticky` mutation was malformed** (left `_rc` unset), giving a VOID control. Recovery:
    re-shaped as the intended pair. **Prevention:** a VOID control means the instrument is wrong;
    never read it as a kill.
12. **A double-escaped Python anchor aborted an edit** (nothing written). Recovery: Edit tool.
    **Prevention:** assert-then-replace scripts are correct to abort; check the file changed.
13. **Read `shellcheck … | tail`'s exit code.** Recovery: re-ran without the pipe.
    **Prevention:** `cmd > log; rc=$?`, never an rc through a pipe.
14. **`mutation-evidence.md` first cited `HEAD~1`** for the battery's SHA. Recovery: corrected to
    the worktree's HEAD. **Prevention:** cite the SHA the sandbox was created from, captured then.
15. **Stop-hook fired twice on first-person commitments while waiting on background agents.**
    Recovery: `<stop>BLOCKED: …</stop>` with the wait named. **Prevention:** while waiting, close
    with the BLOCKED form, never with "I will …".
16. **The plan's `discoverability_test.command` failed preflight Check 10 (curl rc=3)** although the
    plan said it "printed `workflow_runs`" live. It was a YAML double-quoted scalar with escaped
    inner quotes; Check 10 strips only the outer pair, so curl got a URL wrapped in literal `\"`.
    Recovery: unquoted the scalar (no shell-active token needed quoting). **Prevention:** verify a
    probe through Check 10's own parse + sandbox path, never by pasting it into a shell.

## Tags

category: integration-issues
module: web-platform-release resolve-target
