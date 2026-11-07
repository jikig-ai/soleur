# Learning: the sentence I added to explain a failure was the false one, and a job-key allow-list pinned three keys of ten

## Problem

#10932 (umbrella #9757) added an exit-1 arm to the apply workflow's restore step plus a runbook row and a rationale-doc section, and extended the W9 behavioural suite. A 10-seat review found no P1 in the first pass; the targeted fix round over the fix commit then found a P1 in the fix itself.

- The fix rewrote "suspect an altered artifact" into "the gate's own manifest check is parse-only (it does not apply the engine's floor, zero-entry or duplicate checks)". False: `scripts/registry-pull-path-health.sh` asserts `.entries` is an array carrying at least the resolved entry count, and A3 pins that count to the floor. Only the engine's required-disposition, distinct-pair and floor checks are not applied by the gate.
- The first-pass wording ("the store is still EMPTY", "the artifact was altered") claimed more than the code supports: the restore job can chain against a store that was not empty because the refill flag is set before the apply; and no step rewrites the artifact, so the traceable route is the resume arm.
- The new W9 job-level pin was an allow-list of three keys (`needs`, `if`, no `continue-on-error`/`defaults`/`strategy`) plus a prefix/substring match on `if`. The structural-enumeration seat found about 20 edits that left the suite green (`container`, `services`, `env`, `concurrency`, a `|| true` suffix on the `if`, extra step env keys such as `SHELLOPTS`).

## Solution

- Re-derive every sentence a correction ADDS against the code it names (read the gate lines, not the ADR), including the sentence written to replace a refuted one.
- Pin a mapping exactly or not at all: exact normalized `if`, exact sorted job key set, exact step env set; keep value pins (timeout, permissions, environment) out and say so, since a value pin only mirrors the workflow into the test.
- Give each new pin a control whose expected fragment is produced only by that pin (`manifest`, `envextra`, `ifor`, `jobctr`), and split messages so two controls cannot be satisfied by the same line.

## Key Insight

Explanatory prose and verification code written during a fix are the least-audited surface of that fix: they are written fast, and they inherit the framing of the defect just removed. A negative claim about another component ("it does not apply X") is a claim about that component's code and needs the same command-backed check as a number.

## Session Errors

1. **Plan-review panel skipped in planning (forwarded).** Recovery: review panel covered it. **Prevention:** none beyond the existing pipeline gate; one-off.
2. **A new runbook sentence about the rehearsal gate was false.** Recovery: reworded after a data-integrity seat traced it. **Prevention:** `**Prevention:**` already exists in review/SKILL.md ("review the NEW assertions before the new code" and the correction-PR scope rule); before committing a claim about another component, read that component's check and quote it.
3. **Unsupported "store still EMPTY" / "altered artifact" wording.** Recovery: reworded to "this attempt wrote nothing" and the resume-arm route. **Prevention:** state a claim at the granularity the code proves (this attempt vs the store).
4. **Job-level pin was an allow-list.** Recovery: exact key set, exact `if`, exact env set plus four controls. **Prevention:** for any structural pin ask "what else may legally appear beside the subject?" and pin the set.
5. **A commit during an in-flight `test-all --affected` run invalidates it (repo-boundary check); relaunched twice.** Recovery: stopped my own run with `proc.sh kill_mine`, committed, relaunched. **Prevention:** finish all commits (including the review-evidence trailer commit) before launching the gate; launch it last.
6. **A PreToolUse hook blocked a commit because the same command launched a detached `bash -c` ("script held in an expansion").** Recovery: separate calls, commit with a literal absolute path and a message file. **Prevention:** launch detached runs as their own Bash call, never in the same command line as `git commit`.
7. **Stop-hook rejected closing text that promised an action.** Recovery: ended with a `Paused:` sentence. **Prevention:** end a waiting turn with one plain `Paused:` or `Blocked:` sentence.

## Tags
category: workflow-issues
module: apply-web-platform-infra restore step, W9 suite
