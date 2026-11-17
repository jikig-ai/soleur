# Learning: a text-parsing guard must enumerate what it refuses, not only what it reads

## Problem

Two guards for #12008 (a follow-through probe over the #12007 host-state reader, and a declared-firewall
invariant suite over Terraform text) passed their own 71 and 27 assertions and a 12-mutant battery, and a
ten-seat panel still returned "no, the assembly is narrower than the property" on both. The exposure suite
read one directory of `*.tf` files with a line-start regex plus brace counting. Everything the parser could not
see read as clean: `.tf.json`, override files, tfvars, modules, hyphenated or indented or bare-label headers,
a one-line resource that swallowed the next resource, braces inside strings, `//` and block comments, an
unmapped firewall, a second firewall bound to a mapped server. The probe had an awk shape gate with no case that
killed it, an `aggregate` that returned the all-clear for any class string other than two, and a role list spelled
in four places.

## Solution

- Parse to a fail-closed record set: strings blanked and comments cut BEFORE brace counting, and every
  construct the parser cannot read becomes a finding (`unsupported-syntax <reason>`), never a skip. The reason
  list is the guard's real specification.
- Compare counts, not only content: a header at column 0 while a block is open means the brace count drifted;
  a file ending inside a resource is a finding.
- Make the all-clear the narrow case: `aggregate` returns it only when every class is exactly `within`.
- Derive duplicated lists (known roles) from the one authoritative list.
- Give every shape clause its own single-defect fixture and its own mutant; add a `edit` helper that fails the
  suite when a fixture edit changes nothing; make the mutant grader name the killing case and refuse mutants that
  do not parse.
- Re-drive every escape from the structural seat's report against the fix, with mutants written as exact string
  replacements (a regex-escaped `sed` mutant silently did not land in 6 of 20 cases).

## Key Insight

A guard's coverage is the set of inputs it refuses to call clean. Enumerate that set (other file types, other
spellings of the same construct, other places the same fact can be declared, other tokens that merely contain
yours) before writing assertions, because assertions only prove the cases you thought of. The structural
enumeration seat found the escapes by asking, for each path into the all-clear, "what edit gets here and stays
green", and it found them in both guards after twelve mutants and a design-validity pass had said clean. A fix
for one escape was applied to the instance twice (nested quotes first handled per line, then per class), so the
second round re-ran the escape list against the new code instead of trusting the fix.

## Session Errors

1. **Fenced follow-through directive refused by the issue-create hook on a labeled issue.** Recovery: filed the tracker unlabeled and documented arming as "add the label and paste the unfenced directive". **Prevention:** read the hook's refusal condition before drafting a tracker; arming trackers are filed unlabeled by design.
2. **Orphan lint reported an unclassified suite, then a missing self-edge.** Recovery: added the `AFFECTED_*_PATHS` blocks and the self-edge to each. **Prevention:** a new suite needs run_suite, the shard rows, an AFFECTED block and the self-edge in one change; grep an existing suite's four registration sites first.
3. **110 s tool timeout killed the orphan lint (rc 124).** Recovery: ran it detached with an rc file and a Monitor. **Prevention:** run known-slow repo lints detached from the first call.
4. **Staging a file created in the same command was blocked by a hook; a commit message file was missing.** Recovery: created files with the Write tool first. **Prevention:** write files and messages in separate calls before `git add`/`git commit -F`.
5. **Merge conflicts only in the generated shard TSVs.** Recovery: took main's version and re-ran the generator with `--incremental --write`. **Prevention:** never hand-merge generated manifests.
6. **Mutation false survivors from overlapping comment-strip rules.** Recovery: a column-0 comment fixture. **Prevention:** a survivor is first a question about the fixture, then the code.
7. **The reader prints a sixth role, so the all-clear was unreachable; found by the architecture seat, not my suites.** Recovery: ignored-role list plus a contract case pinning the reader's role table. **Prevention:** run the guard once against the REAL producer's output shape before declaring the all-clear reachable.
8. **Technical-ruling gate rejected rows labeled "mechanical".** Recovery: reclassified to `taste`. **Prevention:** read the gate's vocabulary before writing ruling rows.
9. **Stop-hook rejected forward-looking closing sentences while waiting on seats.** Recovery: ended turns with a `Paused:` sentence naming the wait. **Prevention:** state the wait as a present fact, not a promise.
10. **Shellcheck findings (unused locals, ls iteration, unguarded rm).** Recovery: fixed. **Prevention:** run `shellcheck -S warning` before the first commit of a new script.
11. **First rewrite of the exposure parser tested its header regex on the string-blanked line, so the baseline read as "no servers".** Recovery: tested on the raw-prefix line; the suite's own positive control caught it. **Prevention:** after changing a scrubber, name which line variant each regex reads.
12. **Regex-escaped `sed` mutants silently did not land (6 of 20), one hit an unmatched brace.** Recovery: Python exact-string mutants; the suite's `mutate()` already refuses a non-landing mutant. **Prevention:** write mutants as exact replacements, and fail loudly on NOCHANGE.
13. **`cd` into a subdirectory moved the working directory out of the worktree root twice.** Recovery: absolute paths from the worktree root. **Prevention:** never `cd`; use absolute paths or `git -C`.
14. **A tracker comment meant for one issue was posted on another (the #12386 text on #12385), found by the user-impact seat.** Recovery: correction comments on both issues. **Prevention:** after posting, read the comment back and check the first sentence names the issue it is on.
15. **A docs-editing subagent introduced a phrase the hygiene scan forbids, and a `false && ok ... || bad` leftover turned a control into a permanent failure.** Recovery: reworded; removed the line. **Prevention:** run the scan after any doc edit; never leave a placeholder control in a patch.
16. **A 500 s command (mutation sweep plus suite) exceeded the tool timeout.** Recovery: moved to the background automatically. **Prevention:** run sweeps detached with a done marker.

## Tags
category: workflow-issues
module: scripts/host-tcp-exposure, scripts/followthroughs
