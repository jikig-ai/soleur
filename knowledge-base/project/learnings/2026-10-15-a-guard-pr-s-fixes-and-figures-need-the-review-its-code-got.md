# Learning: a guard PR's fix commits and the numbers in its prose need the same review its code got

## Problem

Item F of the `grep -q` pipe-guard series (PR #10327, tracker #9217) widened a line-regex guard (wrappers, flag order, `sh -c`, 13 extensions, a split-line pass, a markdown-fence pass) and shipped green: 85 of 85 mutation rows red, two awks, mawk, shellcheck. Three review rounds still found defects, and the pattern was the same each time:

1. **Predicate narrower than the property it names**, in the FIX commits as well as in the first code: the first fix of "a pipe that ends a line" joined `x |` but not `x | \`, `x | # c` or a continued reader at the end of a file (the last was a regression from the first draft); the first fix for non-UTF-8 input added `-a` to the comment filter but left the regexes in the caller's locale, so a byte before the bar still hid the line, and the fixture put the byte AFTER the match, where it could not matter; the "locale" fix then missed two of the greps.
2. **A check that cannot fail**: a floor compared a counter the awk reported about itself (a stub printing the right numbers passed); a dispatch block pinned the router function but not the statements that raised its result; a `spec-dir-zero` check counted zero hits on an empty scan; a "barless alternative" pin accepted a barless alternative in the middle of the pattern.
3. **Figures and causal sentences I wrote that did not reproduce**: "user CPU 68 s to 16 s" (measured 61 s to 35 s), "marker census prefiltered" (never done), "415 joins" (400), "go.md 284 fence lines" (455), "the longest bar line is 4 KB" (the longest tracked line is 6,296 bytes and holds a bar), "`if x | grep -q` is an unread opener" (it is read), "any unambiguous abbreviation" (four are missed), head/awk counts called 13-extension figures while measured over 8.
4. **A battery that grades the wrong reason**: when a real-tree floor trips first, a row aimed at a fixture reads UNRESOLVED for a different cause; two of my own mutants were equivalent (`[#]` matched the `#` in the file name it was meant to miss).

## Solution

- Treat the fix commit as its own change and give it its own panel: a targeted round plus ONE fresh-eyes verification seat found 3 P2s and 9 P3s in fixes the lead had just verified green.
- For every figure the diff's prose adds, put the COMMAND beside it, run it on the final tree, and write the committed measurement script (`j0-measure.py`, `j0-md-figures.sh`) so a reader re-derives it; date the population (8 vs 13 extensions) in the same sentence.
- Make a floor a tripwire for "the pass is not running" (far below the measured count) and tie the counter to the lines the program printed (`scan_sweep` reports the count of printed lines, fails when the program's own number disagrees), then prove each floor reads its own counter with pairwise-distinct counters on a fixture root.
- Fix a class at its ROOT, not at each call site: `scan_sweep() { LC_ALL=C _scan_sweep_c "$@"; }` replaced a per-grep `LC_ALL=C` that had already missed two greps.
- Aim each mutation row at the layer it names: switch the real-tree floor off in the mutant when the mutation lowers a real-tree count; assert the mutant text is not made equivalent by the fixture's own name.

## Key Insight

A guard's green battery measures the mutations its author imagined, and its prose measures what its author remembered. Review the guard (predicate vs property, can each check fail), the FIX commits (same lens, applied to the new code), and every sentence that asserts a number or a cause (name the command, run it on the final tree). The three failure surfaces recur together: on this PR the second panel's P2s were all introduced by the first panel's fixes, and every stale figure was one I had copied forward after the tree moved.

## Tags
category: workflow-issues
module: grep-q-pipe-guard, soleur:review, soleur:compound

## Session Errors

1. **A multi-statement Bash command containing an `rm -rf` of a scratch checkout was refused by the safety hook as a whole, so the `cat >>` append before it never ran; I assumed it had.** Recovery: re-ran the append alone and verified with `tail`. **Prevention:** keep any `rm -rf` (even of a scratch dir) in its own command, and `tail` the file after an append instead of trusting the exit.
2. **Patch scripts built with nested triple quotes raised SyntaxError, and anchor asserts aborted scripts before they wrote anything (twice), leaving the guard unchanged while I reasoned as if it had changed.** Recovery: moved row definitions to a separate file `exec`d by the generator; re-ran. **Prevention:** write edits as data files, not strings nested in strings; confirm with `git diff --stat` after each patch script.
3. **`SWEEP_SHQ` was written with `\$?` inside double quotes, which bash turns into the ERE anchor `$?`; every `sh -c` case failed.** Recovery: the case-table harness showed 26 misses at once; escaped to `\\\$?`. **Prevention:** run the case table after every pattern edit (it did) and print the composed regex once when a part contains `$`.
4. **A fixture file name written as `"...\351..."` in double quotes created a name with a literal backslash, which the new path refusal (correctly) rejected, and a probe referenced `okroot` before its definition (`unbound variable`).** Recovery: `$'\351'`; moved the checks after the definition. **Prevention:** build non-ASCII file names with `$'...'`; run the guard immediately after adding a probe block.
5. **A pipefail-in-comment narrowing of the fence pass cut the real fence lines from 676 to 76** (caught by the new floor). Recovery: reverted and pinned the over-read as `md-fp-*`. **Prevention:** measure a narrowing against the real tree before keeping it.
6. **Battery rows graded the wrong reason (M4b, M10, G2-12-cmt, G3-2-*, G2-7, G3-10b, T1) and one was an equivalent mutant (R5: `[#]` matched the `#` in the file name).** Recovery: floors switched off in mutants that lower a real-tree count; mutant text changed. **Prevention:** after a battery run, read each row's `missing:` line, not only the verdict count.
7. **I wrote figures and causal sentences that did not reproduce (68 s to 16 s, marker census prefiltered, 415 joins, go.md 284, 4 KB longest bar line, `if x | grep -q` unread, abbreviations), and copied head/awk counts measured over 8 extensions as 13-extension figures.** Recovery: the second panel and the verification seat falsified them; re-measured with committed scripts. **Prevention:** the command goes in the same commit as the number; re-run it on the final tree before the last push; state the population.
8. **Fix-round seats took 30 to 80 minutes each under load, and the history seat's report existed only in the transcript (it writes no file).** Recovery: read the transcript JSONL. **Prevention:** brief seats to write their file even when told to report in the message.
9. **The session `grep` is a ugrep function, `sleep` and `rm -rf` are blocked, and cwd resets to the non-worktree root after some commands.** Recovery: `/usr/bin/grep -a`, `tail -f | grep -m1` for waiting, absolute worktree paths. **Prevention:** already in the review brief; no change.
