---
title: A syntax census was claimed to close a credential channel it could only sample
date: 2026-11-20
category: security-issues
module: plugins/soleur/scripts/cloudflare-readonly.sh
tags: [credential-boundary, census, mutation-testing, closed-environment, review-fix-round, follow-through]
related: ["#12846", "#12959", "#12931", "#12441"]
---

# Learning: a syntax census was claimed to close a credential channel it could only sample

## Problem

PR #12959 added a 7th Class R read (`analytics-health-colo`) to the read-only Cloudflare wrapper. A round-0 review seat showed five one-line wrapper edits that sent the bearer token elsewhere and still passed the full suite. CTO ruling Q11 asked for censuses: the set of names the code reads, the identifiers inside `$(( ))`, the `${NAME-default}` forms, and whole-body pins of four helpers. I built them, added a mutation row per seat edit, and wrote into the suite and the commit message that "ANY added name, arithmetic operand or default-form expansion reds a row".

The fix-round security seat then showed eight more one-line edits, each fully green and each sending the token to a caller-chosen host:

- `${!x}` indirection;
- `declare -n`;
- `printf -v`;
- `.` or `source` of a file under `~`;
- a quote-split `'ev'al`;
- a `TOKVAR` swap;
- `read -r` from a file;
- a bare `(( ))` command.

After the class fix (the closed environment below), the verification seat found two more:

- `read -r GQL_URL < /var/tmp/x`, or `$(< /etc/x)`;
- reading the parent's `/proc/<ppid>/environ`.

## Solution

1. **Close the channel instead of enumerating its spellings.** Right after its xtrace refusal, the wrapper re-execs once. The re-exec removes every exported name outside a fixed allowlist, using `env -u NAME`. That puts names only on argv: `env -i NAME=value` would put every token value into `/proc/<pid>/cmdline`. The decision is keyed on the set of names `compgen -e` lists, never on a marker a caller could set. A caller-set marker with an open environment is refused with exit 64. After the re-exec, every syntax for reading a caller-chosen variable finds it unset. The suite's closed-environment wire rows check this per subcommand: they plant names and compare curl argv, the stdin config and the output byte for byte.
2. **Census what the closure leaves open.** These rows run on a quote-aware copy of the code:
   - a ban on `.` or `source` used as a command;
   - a ban on `~` in code;
   - a redirection census: every input redirection must be `< <(`, so no row may read a file or `/proc`.

   Each row has positive and negative control fixtures and mutation rows.
3. **State the residual where the reader acts.** The wrapper header says the closed environment closes the shell-visible process environment only. `BASH_ENV`, exported builtin-named functions, `SHELLOPTS`, `PS4` and `LD_PRELOAD` still act in the first bash start, before the re-exec.

Result: the wrapper suite passes 2565/0, with 273 of 273 mutation rows caught.

## Key Insight

A census over syntax families samples the edits that could open a channel. It never proves the channel is closed, because bash has more spellings for "read an input" than any list. Name the channel as a resource: the process environment, the filesystem, another process. Close the one you can close by construction. Census only what the closure leaves, and put the residual in the header. Never write "any" in a claim about a census. A census row's honest claim is "these N spellings red", and the real test is a mutation in a spelling the census author did not list.

## Session Errors

1. **First `git push` rejected once** (forwarded from the plan phase). Recovery: retried. **Prevention:** none needed; it was transient.
2. **A hook false-positived on inline Python heredocs** (forwarded). Recovery: moved the scripts to the scratchpad. **Prevention:** put multi-line Python in scratchpad files from the start.
3. **`technical-ruling-gate.sh` failed 3 times on row formatting** (forwarded). Recovery: fixed the rows. **Prevention:** copy an existing passing row's exact shape.
4. **Markdownlint findings** (forwarded). Recovery: fixed. **Prevention:** run markdownlint before committing.
5. **`lint-orphan-test-suites.sh` hit rc=124 under machine load.** Recovery: re-ran later (rc 0). **Prevention:** run long lints with `run_in_background` and a long timeout; never read a timeout as a pass.
6. **Three merge conflicts with main**, the last two only on the shard and duration manifests. Recovery: took main's copies and re-ran `regenerate-shard-manifest.py --incremental --write`. **Prevention:** run `git merge-tree --write-tree origin/main HEAD` before every push, not only before the panel.
7. **I first wrote that #12931 gives no deletion date.** The date was sourced from Cloudflare's domain-status docs in plan line 121. Recovery: cited the docs. **Prevention:** grep the plan for the claim's subject before writing a date claim.
8. **A Python edit wrote literal `\n` text into a mutation anchor** (M8). Recovery: the exactly-once assertion caught it, and I rewrote it with real newlines. **Prevention:** keep the anchor-uniqueness assertion in every scripted edit.
9. **The plan's loop copy was synced from the first anchor match, which was the F/G loop, not the H loop.** Recovery: a stub run printed F/G subcommand names, and I restored and re-synced on an anchor unique to the H loop (`...; sub=analytics-health-colo`). **Prevention:** when copying a block between files, anchor on a line that occurs exactly once in each, and assert the count before slicing.
10. **The stub `doppler` used the wrong argument indices.** Recovery: corrected to `$9` and `${10}`. **Prevention:** print `"$@"` once in a new stub before relying on positions.
11. **Moving the floors into a `finish()` function made two floors unconstructible for `guard-vacuity-floor`** (17 became 19). A leftover child block also made the exit-status check pass vacuously: the child died on an unbound `ROW_FLOOR`, with the expected rc 1. Recovery: floors back at top level with the threshold assigned on the line above; the child falls through the same trailer; mutation-verified. **Prevention:** after touching a suite's floors, run `scripts/guard-vacuity-floor.test.sh`. Verify a forced-fail child by deleting the final failure exit, never by its rc alone.
12. **A sandbox mutation did not land.** The run block contains three backticks inside an awk program, so splitting on backticks cut the block. Recovery: `diff -q` reported it, and I split on a `\n` + three-backtick fence line instead. **Prevention:** always `diff -q` a mutant against its pristine copy, as the review brief requires.
13. **A push "rc=1" came from an empty `grep -v`**, not from the push. Recovery: re-ran the push alone: "Everything up-to-date". **Prevention:** redirect the push to a log and read `$?` of the push itself, never through a pipe.
14. **`git log --no-merges` listed main's commits reached through the merges.** Recovery: switched to `--first-parent --no-merges`. **Prevention:** compute a fix-round file list from the branch's own first-parent commits.
15. **I claimed the Q11 census turned "any" added name red.** The security seat showed eight green bypasses. Recovery: built the closed environment as the class fix, and the census claim now names its scope. **Prevention:** this learning's Key Insight, routed to `plan-sharp-edges.md`.
16. **The closed-environment claim was also too broad.** File reads and the parent's environ were still open. Recovery: added the redirection census and reworded the header's scope. **Prevention:** same as 15: name every input resource (environment, files, other processes) and say which control covers each.
17. **I wrote "eleven cases added 2026-11-20"**, a miscount across two days. Recovery: reworded to point at the case list. **Prevention:** derive counts from the file (`grep -c`), never from memory.
18. **The runbook called the capture-marker comment "a Class R act".** Standing-delegation §9 item 5 keeps record-marker comments outside Class R. Recovery: the owner posts it, or a session does under the owner's typed go. The runbook, tasks and probe text agree. **Prevention:** before labelling any posted comment Class R, check whether its line is a marker a gate or probe reads; if it is, §9 item 5 applies.
19. **The Q10 probe shipped with no step that files its tracker** (flagged by four fix-round seats). Recovery: task 6.0, AC13a and a non-⏳ PR-body line. **Prevention:** when a PR adds `scripts/followthroughs/*.sh`, the same commit adds the tracker-filing task with the exact directive, per `followthrough-convention.md` author steps 1, 3 and 4.

## Tags

category: security-issues
module: cloudflare-readonly wrapper, health-colo falsification suite, follow-through probe
