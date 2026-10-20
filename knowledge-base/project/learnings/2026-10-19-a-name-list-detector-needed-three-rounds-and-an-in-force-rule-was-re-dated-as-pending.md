# Learning: a "file never opened" detector built from a name list needed three rounds, and a dating sweep made an in-force rule read as pending

## Problem

PR #10523 added four shape fields to the wipe-assert exit-34 line and a suite that proves the new `hooks` reads never open a file's content. Eleven review seats, two targeted fix rounds and a verification seat later, the proof was still a set of lexical heuristics, and each round found a fresh way past it:

- Round 0: the closed-set check covered only the lines between two sentinels, so a `$(<f)`, `tail`, `sed`, `dd if=` or `awk FILE` read written just above the sentinel passed 1133/0.
- Round 1: the fix added a list of 19 reviewed lines matched by a name regex (`WA_MNT|hooks|pre-receive`), a shim recorder keyed on tree operands, and a regex that blanked `[[ ]]`, `(( ))` and awk programs. The test-design seat then showed reads through `$tgt`, `$cowdir`, `$mntdir`, `/dev/mapper/$WA_SNAP`, `uniq`, `paste` and `strings` all passed, and that the blanking itself hid `awk 'BEGIN{getline x < f}'` and a read between two quoted brackets.
- Round 2: closing those with more names left `BYID`, `src`, `lf`, `dm` and `&&<"$f"` open (verification seat).

Separately, a runbook date sweep (R7) fixed two of nine "the change that adds it" phrases, and the next sweep's fix (D6) rewrote the 2026-10-18 owner-posts sentence to "takes effect on the merge of the 2026-10-19 change", which made a rule already in force read as not yet in effect, the permissive direction. The CLO caught it.

## Solution

- Delete the heuristic instead of extending it: the redirect rule no longer blanks anything and flags every `<`; the live script has no comparison `<`, so nothing needed exempting.
- Derive the name set from the script's own variables (every variable that holds the mount, the snapshot node, the COW file or the loop device) and pin the lines as an exact multiset (94 lines), with a first-differing-line message.
- Count emit sites by occurrence (`say` as a word token, every `>&` token) instead of by line.
- Give every guard a mutation row; a cached control per (setup, case, script checksum) keeps the 129+ mutant rows inside the time budget.
- For dated runbook phrases: grep the phrase class across the whole file, and for each hit say which change it refers to (2026-10-18 vs 2026-10-19); the CLO's exact-edit protocol with an asserting apply script (each old string must occur exactly once) made the correction mechanical.

## Key Insight

A detector built from a list of names is a claim that the list is the set of things that reach the sink, and each round the list was one name short. When a seat finds a bypass in a lexical detector, ask what the system itself uses to decide membership (here: the script's own variables) and derive the set from that, or count the sink's uses, instead of adding the name the seat happened to find. A repeated fix for the same class on the same file in consecutive rounds means the mechanism is wrong.

A dating or scoping edit applied to the instance fixes the sentence it was aimed at and can invert the sentence next to it. Name the proposition ("this rule is in force since 2026-10-18") and check every phrase that mentions it, in both directions.

## Session Errors

1. **Truncated resume brief (items 4-6).** Recovery: flagged to the owner, who re-supplied what was needed. Prevention: a resume brief that ends mid-list is stated back to the owner before acting on the missing items.
2. **CLO edit E1 old string not verbatim (line wrap).** Recovery: applied semantically with an asserting script. Prevention: apply CLO exact edits with an apply script that asserts each old string occurs exactly once and writes nothing otherwise (used for R-1 to R-7).
3. **MD038 and forbidden-wording substring hit ("our hook" in "four hooks words").** Recovery: reworded. Prevention: run the forbidden-wording grep with a negative control before committing runbook edits.
4. **Ledger stated the Terraform-rendered sizes wrongly.** Recovery: re-derived with `git log -S` and the strip regex. Prevention: re-derive every size and date the lead writes into a ledger before forwarding it to a fix agent.
5. **Suite edited under a running seat.** Recovery: ignored the seat's syntax error. Prevention: hold the tree until every seat returns (already a review-skill rule).
6. **`/usr/bin/time` absent; three suites exited 127 with no output.** Recovery: re-ran without it. Prevention: wrap suite runs with `$SECONDS`, and read the `rc=` and summary tails before reporting anything.
7. **First `wl_classify` identity check passed vacuously (empty equals empty after a CWD change).** Recovery: added `[ -n "$a" ]` and matched the real indented definition. Prevention: every identity check needs a non-empty guard and, for a function extraction, the extracted line count printed.
8. **D6 re-dated an in-force rule as pending.** Recovery: CLO exact edit R-1. Prevention: when re-dating a phrase, state which change it refers to and re-read the neighbouring sentences.
9. **Two running fix agents stopped at the usage limit.** Recovery: checked the tree was clean, then re-dispatched. Prevention: check `git status` before re-dispatch after any stop.
10. **Lexical detectors bypassed in two consecutive rounds.** Recovery: replaced with closed sets and counts. Prevention: already in the review skill ("delete the heuristic after two rounds"); the lead should apply it at the first repeat, not after the third seat.

## Tags

category: logic-errors
module: apps/web-platform/infra git-data-wipe-assert (#10138, #6897)
