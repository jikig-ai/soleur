# Learning: a review panel can pull a guard in opposite directions, and a row count I derived by subtraction was wrong

## Problem

PR #10663 (item 2 of umbrella #9757) moved the zot pull token off terraform's argv (`-var` to an exported `TF_VAR_zot_pull_token`) in four steps of the inngest rehearsal workflow, and added a guard stage S9 to `tests/scripts/test-argv-bearer-sweep.sh`. The 12-seat review returned findings that pulled in OPPOSITE directions: the simplicity seat wanted ~22 of 35 rows cut (Guard 2 repeated identically on two destroy bodies, duplicated floor rows), while the test-design and structural seats wanted MORE (the two plan steps covered only by a regex pin that `if false; then export ...; fi`, a later `unset`, or a second garbage export all fooled; a stub that answered every flag; no mask assertion although the first ruling required one).

## Solution

One batched CTO ruling with named lines resolved all nine contested items at once. The decisive move was to execute all four step bodies under strict stubs (exit 64 on any argv they do not model) and delete the regex arms execution made redundant (`export-order`, the duplicate floor rows). That was both smaller and stronger than hardening the pin against each evasion, and it closed the simplicity and test-design findings together. The scanner gained a fallback `nonliteral` arm, landed only because it added zero records on the real tree. Measured Terraform 1.10.5 behavior (TF_VAR consumed identically by plan/apply/destroy, `-var` outranks `TF_VAR_`, a destroy without the token fails on `No value for required variable`) went into the ADR.

## Key Insight

When seats disagree on size, the question is not "bigger or smaller" but "what one mechanism makes the redundant assertions redundant": executing the real bodies replaced three families of static pins. And a number derived by subtraction from a baseline measured on a different tree is a claim, not a measurement: the S9 row count was 29, not 27, because the 843 base predated the merge of main (the true base was 841).

## Session Errors

1. **Data-integrity seat returned nothing twice (first run ~30 s with no text; the respawn wrote only a header).** Recovery: covered its lens with a scratch-dir Terraform fixture. **Prevention:** already in review/SKILL.md ("mandate file delivery in the spawn prompt"); when a respawn also fails, do the lens inline rather than a third spawn.
2. **Five seats died on `ECONNRESET`/`EAI_AGAIN`.** Recovery: resumed from transcripts in batches of three then two (a resume keeps partial work). **Prevention:** none needed beyond the existing resume-in-small-batches rule.
3. **Names-row fixture counted benign names twice** because the scratch root is a copy of the base (the real workflow files carry the same names). Recovery: scoped the awk to the fixture file. **Prevention:** a fixture asserted by name must filter on its own file path whenever its root is a copy of real files.
4. **A scripted edit batch asserted per edit and aborted midway:** the first edits had already written, a suite run had already started on the half-edited tree. Recovery: checked which edits landed with grep, killed the run, applied the rest with the real strings. **Prevention:** build the whole batch in memory and write each file once, or assert every anchor before the first write; never launch a run in the same call as an edit batch.
5. **Reused fixed log and rc names across detached launches.** Two runs raced; the log was truncated and an `rc=0` belonged to a different run. Recovery: relaunched with a fresh name and confirmed no process was alive. **Prevention:** a unique file name per launch (`s9-rN`), and confirm no stray process with `list_runs` before reading an rc.
6. **Derived the S9 row count by subtraction from a stale baseline** (870 - 843 = 27; actual 29 on a 841 base). Recovery: counted `[ok] S9` rows in the log and fixed the ledger, ADR and ruling record. **Prevention:** count rows from the log, never subtract from a baseline measured before a merge of main.
7. **A seat's claim about an OPEN PR (a same-line `PJ_TRIPLES` collision) was stale; the PR had merged.** Recovery: the CTO ruling checked `gh pr view` first. **Prevention:** re-check PR state before acting on any seat claim about another PR.
8. **`rm -rf "$(dirname "$d")"` was refused by the safety check.** Recovery: reran without the removal and left the scratch dir. **Prevention:** never remove a command-substitution target; print the path first, then remove the literal.
9. **My Terraform fixture used a sensitive variable in a plain output.** Recovery: wrapped it in `nonsensitive()`. **Prevention:** none (one-off).

## Tags

category: workflow-patterns
module: review, argv-bearer-sweep
