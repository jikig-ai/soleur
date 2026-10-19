# Learning: a read-only drift probe's own fixes needed a second mutation round (PR #10424, item 9 of #9927)

## Problem
The `sole-copy-protection-check` job (read-only Hetzner GET of the Inngest store volume, compared with the
`protection.delete` value derived from the Terraform declaration) passed a 13-seat review, and the first fix
round then introduced new gaps of its own: a Doppler hang was filed as `no-token` with an operator-only remedy,
a hung `tf_commit` skipped the probe, an `echo >> $GITHUB_OUTPUT` writer bypassed a `printf`-keyed single-writer
pin, and validator anchors (`^`, `$`) could be dropped with the suite still green.

## Solution
- Bound every external call inside the step (`timeout -k 5 60` for the secret read, `timeout 30` for the age
  lookup) and map the timeout rc (124/137) to its own verdict (`could-not-read`), never to the missing-credential
  one. Drop `-z "$TOKEN" &&` from that branch: a read killed after printing a fragment is still a timeout.
- Pin the writer set by counting every line that writes `$GITHUB_OUTPUT` (any form), not by the one token a
  writer happens to use.
- For each validator anchor add a suffix-garbage and a prefix-garbage value; for each leak term add a control that
  plants exactly that term. Equivalent mutants (a full token whose own 6-character prefix term stays) are recorded
  in the suite header, not left as unexplained survivors.
- Re-derive FLOOR/TABLE_ROWS from a green run (194 / 126), never by hand.

## Key Insight
A fix is the least-audited surface: round 2 found a time bound equal to the stub's own sleep (the guard could not
fail) and prefix terms with no control. Ask of each new bound "what value of the mutated input still passes?" and
mutate it in a sandbox with a landing assertion before claiming RED.

## Session Errors
1. **cla-check failed on the PR: commit 25e6664685 was authored by a placeholder identity (name `s`, an invalid-TLD address left by a fixture)** (probable cause: a test fixture wrote the shared `.git/config`; UNVERIFIED) — Recovery: `git filter-branch --env-filter` on `origin/main..HEAD` (tree identical), `--force-with-lease` push — Prevention: run `git log origin/main..HEAD --format='%an <%ae> | %cn <%ce>'` before the first push of any branch whose suite runs git fixtures (rule `wg-cla-signed-author-before-merge` already covers the merge side).
2. **technical-ruling-gate FAIL on a "~60 lines" row** — Recovery: CTO ruled single PR, row replaced — Prevention: write `technical` rows in the `Ruled by CTO agent, <date>: ...` shape from the start.
3. **Subagent API error (EAI_AGAIN) and a weekly rate limit killed review seats and the fix agent** — Recovery: resumed each via SendMessage — Prevention: none needed (platform); keep seat reports written to scratchpad so a resumed seat can finish.
4. **Affected-kb oracle red: the suite globbed the decisions directory** — Recovery: literal ADR path — Prevention: tests that read KB files name them literally.
5. **A process-listing command was blocked by a hook (full-command-line match is self-matching); `test-argv-bearer-sweep` hung without stdin** — Recovery: PIDs from `$!`, `</dev/null` — Prevention: run suites with `</dev/null` in non-interactive shells, and keep the blocked command's text out of heredocs (the hook scans the whole command).
6. **A foreground mutation batch exceeded the 120 s tool limit** — Recovery: it continued in the background and was read from its output file — Prevention: run multi-mutant batches with `run_in_background` from the start.
7. **Assumed the sandbox copy held the ADR/runbook files the suite reads; it did not** — Recovery: copied them in before the control run — Prevention: always run the unmutated control first (it caught this).
8. **CI `test-scripts (6/8)` went red on `.claude/hooks/grep-q-pipe-guard.test.sh`: a new suite that stubs `curl`/`doppler` needs `PRODUCER_JOIN` rows and a `PJ_TRIPLES` bump (275 to 277)** — Recovery: two exempt rows with vocabulary reasons plus the count, guard green locally — Prevention: the affected selector does not pick this guard for workflow-file or new-suite changes (the guard's own header says so, #10447), so run `bash .claude/hooks/grep-q-pipe-guard.test.sh` by hand whenever a new suite stubs a verb that a workflow or script pipes text into.
9. **CI `test-scripts (4/8)` went red on `scripts/test-affected-kb-consumers`: registering the new suite in the grep-q guard made the oracle follow that hop into the suite's reads of ADR-282 and two runbooks** — Recovery: `bash scripts/test-affected-kb-consumers.test.sh --write-baseline` (three added lines, no classification needed for `argv-code`) — Prevention: whenever a hook-guard row names a new suite, regenerate the KB-consumer baseline in the same commit (run `--write-baseline` and inspect the diff).

## Tags
category: workflow-issues
module: scheduled-terraform-drift
