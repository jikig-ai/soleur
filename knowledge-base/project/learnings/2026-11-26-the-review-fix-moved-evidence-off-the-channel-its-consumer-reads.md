---
title: The review fix moved evidence off the channel its consumer reads
date: 2026-11-26
category: logic-errors
module: cf-token-scope
tags: [cf-token-scope, bash, jq, test-design, fix-round, stdout-contract]
issues: ["#12931", "#13076"]
---

# Learning: the review fix moved evidence off the channel its consumer reads

## Problem

PR #13076 changed the `cf-token-scope.sh` zone-rest probe to send a JSON probe body to
`PATCH /zones/<z>/settings`. That endpoint parses JSON before it checks authorization, so a
non-JSON body got 400 code 6007 for every token. A 10-seat review panel asked for more evidence on
fatal and refused runs, and the first fix commit (509453acc8) added it. The 6-seat fix round on that
commit then found that the fix had brought in five new defects of its own:

1. **Evidence on a channel the consumer drops.** The new write-response and read-back summaries were
   lines indented two spaces (`write response …`), and the refusal detail went to stderr. The swap-0b wrapper
   (`run_scope_probe` in the archived `bootstrap.sh`) keeps only stdout lines matching
   `^(probe=|cf-token-scope: migration)`. Run through the wrapper, the evidence that the docs say to post
   after an exit 4 never appeared, and the docs also forbid re-running to recover it.
2. **A guard decided on display text.** The 6007 check compared `"$(mig_errcode)" == ", err 6007"`.
   `mig_errcode` reads only `.errors[0].code` and returns nothing for two JSON documents. So a 6007
   listed second, or a reply made of two documents, read as `authorized`, which is a false pass.
3. **An empty-array guard that cannot fire.** `printf '%s\n' "${arr[@]}"` on an EMPTY array prints one
   blank line. `mapfile` then gets one element, so `[[ ${#rows[@]} -eq 0 ]]` never matched. An emptied
   table was still refused, but by the method check and with the wrong message.
4. **A test labelled "on stdout" that read both streams.** `has` greps the combined capture, so moving
   the verdict to stderr kept all 607 assertions green.
5. **A fixture wrong on two axes.** The "(method)" dispatch row sent a PUT to `…/bot_management`. That
   is the wrong method and the wrong URL, so the URL half of the guard refused it on its own, and
   deleting the method half left every test green.

## Solution

- Every line an operator must post is now a `probe=<profile> …` stdout line: `fatal`, `write-response`,
  `read-back` and `refused-detail`. The wrapper matches the whole line `probe=<p> verdict=pass`, so
  these extra lines cannot forge a pass. `mig_summary` also redacts object keys, not only string values.
- `mig_grant_unparsed` decides on the parsed codes:
  `jq -n -e '[inputs] | length == 1 and (any(.[0].errors[]?; .code? == 6007) | not)'`. A reply that is
  not one JSON document counts as unparsed.
- Blank rows are dropped before the count (`[[ -n $r ]] && rows+=("$r")`). Test M11m now empties the
  table itself, not only the accessor arm.
- A `mrun_out` helper captures stdout and stderr separately. The refusal rows assert `^…$` on stdout and
  `lacks_err` on stderr.
- The method-half fixture is a PUT to the settings URL, so it differs on one axis only.
- Three mutants (the verdict sent to stderr, the wrong token key, the PATCH half removed) were each run
  against a copy of the script and test. Each one now fails the suite.

## Key Insight

When a fix adds output for someone to act on, check the reader's filter, not only the producer.
The producer's tests ran the script directly, so they could not see the wrapper's `grep`. The
reliable question is: "which command consumes this line, and does its filter keep it?" More
generally, a fix commit is new code with its own defects. Of 9 fix-round P2s, 7 were in lines the
first fix had added.

## Session Errors

1. **Collision pre-check exited 10 on this branch's own draft PR (forwarded).** Recovery: read the hits;
   neither touched cf-token-scope. **Prevention:** none needed; the pre-check already names the PR so the
   self-hit is visible.
2. **`plan-sharp-edges.md` too large to read whole (forwarded).** Recovery: read lines 1-145 and
   keyword-searched the rest. **Prevention:** keep keyword-searching it; it is a catalogue.
3. **Two plan edits redone after exact-match failures (forwarded).** Recovery: re-read and re-applied.
   **Prevention:** read the exact span before every Edit.
4. **Python edit scripts failed on nested quotes (twice).** Recovery: split the script and used the Edit
   tool for the quote-heavy hunks. **Prevention:** use the Edit tool, not a heredoc Python script, for any
   replacement whose text has both `"""` and trailing `"`.
5. **A mutant replacement was not unique in the source.** Recovery: used a distinctive replacement string.
   **Prevention:** `run_mut` already reports `replacement-not-exactly-once`; pick a replacement that does not
   already occur in the file.
6. **`wbody_set` skipped lines by a `^printf` prefix, but `bash --pretty-print` joins statements with `;`.**
   Recovery: blank the `printf '%s\n' "…"` recipe strings with `gsub` before matching. **Prevention:** a
   lint over `--pretty-print` output must treat a line as several statements.
7. **A vacuous identity mutant row was added.** Recovery: dropped it. **Prevention:** a mutant whose
   replacement equals its anchor is a self-test only, never coverage.
8. **`jq -c` on a string printed it with JSON quotes.** Recovery: `-r` plus `tojson` for objects.
   **Prevention:** when jq returns either a string or an object, use `-r` and `tojson` the object branch.
9. **Assumed the wrong deny token for the pages row.** Recovery: read the row; the deny key is
   `CF_API_TOKEN_RULESETS`. **Prevention:** read the table row before asserting a key name.
10. **The first review fix introduced five defects (Problem 1-5 above).** Recovery: a targeted fix round
    and the fixes above. **Prevention:** for evidence output, grep every consumer's filter before writing
    the line. A guard must decide on parsed values, never on a display string. Never guard on `mapfile`
    length without dropping blank lines. Pin a channel only with a split capture. A dispatch fixture
    must differ from the passing case on exactly one axis.
11. **Stop-hook unkept-promise nudges while the review seats ran.** Recovery: ended those turns with a
    Paused line. **Prevention:** end a turn that waits on background agents with `Paused:` and no promise.
12. **Three automatic context compactions in one session.** Recovery: continued from the summaries.
    **Prevention:** move ship/postmerge to a fresh session through the resume prompt.

## Tags

category: logic-errors
module: cf-token-scope
