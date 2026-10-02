# Learning: a hardening PR's own prose claimed tracking, enforcement and "no host touched" that nothing backed

## Problem

PR #9397 (LUKS web-host follow-ups: provisioner hardening, escrow split, replace-gate arms, T2 rehearsal) went through 12 review seats and shipped 1 P1, 26 P2 and ~77 P3 findings, almost all in the PR's own verification and prose rather than in the feature code. Six shapes recurred.

1. **Claims of tracking that did not exist.** The ADR addendum said the rotation HALT question was "left open and tracked", a `.tf` comment said the old-token retirement was "tracked on #9377", the runbook said a de-pet issue "exists and is scheduled", and the wrapper header said a prerequisite was "recorded on #9358". `gh issue view` showed zero comments, no blocked-by edges and no de-pet issue. Four independent seats converged on it.
2. **An enforcement claim with no enforcer.** `check-web-host-escrow-config.sh` called itself "a hard precondition of every birth route"; no workflow, runbook or gate invoked it, and it reads secret *names* only, so a mis-pasted pair passes.
3. **A "touches no host" claim that was false.** The plan said the merge "creates resources only and touches no host". The SSH-stage apply also re-ran `terraform_data.cron_egress_firewall` and `luks_monitor_install` on live web-1, because their trigger hashes cover files the PR edits.
4. **A hardening that removed an existing alarm.** A literal `ip daddr 169.254.0.0/16 counter drop` placed before the `egress-blocked: ` log rule stopped a container metadata probe from producing the kernel line the resolver counts into the `op=egress_blocked` page.
5. **A status-capture bug in a data-loss path.** `_ct=$(cat "$CRYPTTAB"; printf x) || fatal` tests `printf`'s status, so an I/O error on `cat` read as an empty crypttab and the atomic rewrite dropped every other entry.
6. **A merge with a sibling that changed a contract.** `main` pinned the Sentry ingest host/project/key shapes in the resolver; my nft suite's fixtures (`sentry.invalid`, `PROJECT_ID=1`, `KEY=k`) became refused inputs and 5 resolver rows failed silently-looking.

## Solution

- Filed the missing tracking (#9421, comments on #9356/#9357/#9358/#9377, blocked-by edges where GitHub allows them) and reworded each claim to what is true ("necessary, not sufficient", "inferred, not measured", "runbook step 0, not enforced").
- Corrected the merge-effect claim in the plan and named the live web-1 mutation.
- Added a rate-limited log rule (same prefix) before the unconditional drop, and a census "one drop, before every accept, one log immediately before it".
- `cat && printf x` plus the same no-fewer-lines guard fstab already had; a row where cat fails (a directory stands in for an I/O error) plus a mutation row restoring the `;` form.
- Updated the suite fixtures to a pinned-shape Sentry triple and the new allowlist feeder host.

## Key Insight

The code was the best-reviewed part of the PR. What the panel found were sentences that assert a fact about the *rest of the system* (GitHub, other workflows, the host, another PR's contract) which the author wrote from intent. Each had a one-command falsifier that nobody ran: `gh issue view`, `grep` for the caller, a read of the apply workflow's `paths:` and `-target` graph, a read of what consumes a log line, a read of the merged file.

## Session Errors

1. **Data-integrity review seat died on a weekly rate limit.** Recovery: resumed it (transcript kept). **Prevention:** the review skill already says resume, do not respawn; no change.
2. **A fix agent ended twice on "I'm finishing the rest" with no report and no files.** Recovery: spawned a fresh agent scoped to the one missing file. **Prevention:** put "your final message IS the deliverable; do not end on a status sentence" in the SPAWN prompt (the review skill's Sharp Edges now carry it for seats; apply it to implementation agents too).
3. **`pgrep -f` was denied by the self-match hook.** Recovery: `source proc.sh; list_runs`. **Prevention:** already hook-enforced.
4. **Two Stop-hook blocks for ending a turn on an intention.** Recovery: stated `<stop>BLOCKED: …</stop>` with the real blocker. **Prevention:** already hook-enforced.
5. **A python heredoc left `'"'"'` debris in a shell comment.** Recovery: review caught it. **Prevention:** after a scripted edit that carries quotes, grep the file for the escape sequence you used.
6. **The PR was CONFLICTING/DIRTY at review start and a sibling changed a contract the new suite exercised.** Recovery: merged, resolved by combining both sides, re-ran the suites that execute the merged file. **Prevention:** after merging `main`, run the suites that execute every file the merge touched, not only the conflicted ones; fixtures that carry env literals for a validated input go stale when the validator tightens.
7. **I wrote claims of tracking, enforcement and "no host touched" from intent.** Recovery: filed/corrected. **Prevention:** before writing "tracked on #N", "blocked-by edges ship", "enforced by", or "touches no host", run the one command that proves it and cite it (a work Common Pitfalls bullet was drafted; `work/SKILL.md` has 56 bytes of body headroom under its ceiling, so it is NOT routed there — this learning is the home until headroom exists).
8. **A new drop rule removed the log line an existing page counts.** Recovery: rate-limited log rule before the drop. **Prevention:** when adding a deny/drop ahead of an existing log or counter rule, grep who consumes that log line and keep it (a review defect-class bullet was drafted; `review/SKILL.md` has 39 bytes of headroom, so it is NOT routed there — this learning is the home).
9. **`gh issue edit --add-blocked-by <PR number>` fails** ("Could not resolve to an Issue"). Recovery: recorded the PR-state check in the runbook precondition. **Prevention:** blocked-by edges take issues only; a held PR is a precondition to check with `gh pr view`.

## Tags
category: workflow-issues
module: soleur:review, soleur:work, apps/web-platform/infra
