# Learning: a closing probe counted rows where its property said slots (and the plan's ruling said rows)

## Problem

PR for #10972 added a follow-through probe whose exit 0 closes a tracker after a 14-day window of twice-daily Sentry check-ins. The first design (plan ruling R1: "simple window, not per-slot buckets") required 28 `ok` rows, no bad row, and a denylist of bad statuses. Four review seats independently showed that 27 distinct slots plus one duplicate `ok` row (a manual re-dispatch, which the runbook itself prescribes) exited 0 and closed the tracker over a slot that never ran. The same probe also accepted statuses outside its denylist, judged only the first of several JSON documents, and fell through to PASS on a leading-zero clock value.

## Solution

CTO rulings D1-D4: bucket each row by its own timestamp and require every one of the 28 slots to hold an `ok` row; allowlist statuses (fold case, no trim; anything else exit 3, printed only from a closed token set); require exactly one JSON array document (`jq -s`); validate the clock and window bounds as `^[1-9][0-9]{0,15}$`; cap the reply. The suite was rebuilt around rows that each name the mutant they kill (166 assertions), with an exact-argv curl shim, a universal per-run leak check, a self-test of every verdict helper and the final gate, and a nested re-run proving the last lines of the file exit nonzero.

## Key Insight

A guard's property and its predicate drift apart when a plan ruling restates the property as a count. The review panel's shared finding was one gap: "one ok per slot" assembled as "28 ok rows". Fix the property first (what set does this quantify over?), then pick the predicate. A settled ruling is a hypothesis: four seats contradicted R1, and the CTO amended it in one batched spawn.

## Session Errors

1. **The probe counted rows, not slots (inherited from plan ruling R1).** Recovery: CTO D1. **Prevention:** the follow-through convention now carries the "cover slots, not rows" rule; reviewers of any closing probe ask which set the property quantifies over.
2. **Header, plan and tasks claimed things not true of the diff** ("four manifest files", a `NOT_BEFORE` constant, "the sweeper does not track edits to the issue-body `earliest=`", copied from a review note without reading `scripts/sweep-followthroughs.sh`). Recovery: corrected plus a plan Addendum. **Prevention:** before writing a rationale about another component, read that component (the sweeper re-reads and honours an edited `earliest=`).
3. **The runbook stated the apply result as fact before the apply had run.** Recovery: conditional wording naming both steps. **Prevention:** prose merged ahead of a post-merge step is written in the conditional tense.
4. **I read the ruling "lowercase only, no trimming" as "no case folding"; the CTO's own row said "after ascii_downcase".** Recovery: restored the fold. **Prevention:** quote the ruling's full row in the implementation comment instead of a paraphrase.
5. **The first mutation battery had a pattern that did not land (a typo), and the final `exit $?` survived until a nested gate run was added.** Recovery: a landing assertion per mutant plus the nested gate. **Prevention:** run the not-landed/identical guard on every battery row and mutate the last line of any suite.
6. **The first local affected gate returned rc 6 (budget deferred) after a 10-minute queue on the shared lock.** Recovery: recorded as not a pass; re-run on the final tree before mark-ready. **Prevention:** none beyond the existing rc 6 rule.
7. **A `grep -c` with an unset shell variable as its file operand read stdin and hung for 120 s.** Recovery: stopped the background task. **Prevention:** a shell variable does not survive between Bash calls; add `</dev/null` to any grep whose file operand is a variable.
8. **The Write tool refused twice ("modified since read") after scripted edits to the same file.** Recovery: Read, then re-Write. **Prevention:** after a scripted edit, Read before the next whole-file Write.
9. **A process-listing command with the full-command-line flag was denied by the self-match hook, and a Bash command whose text merely quoted that flag was denied too.** Recovery: the runner's own capacity verb; the Write tool for prose that names the flag. **Prevention:** already hook-enforced; put prose naming a blocked command in a file written with the Write tool.

## Tags
category: workflow-patterns
module: followthroughs, sentry-monitors
