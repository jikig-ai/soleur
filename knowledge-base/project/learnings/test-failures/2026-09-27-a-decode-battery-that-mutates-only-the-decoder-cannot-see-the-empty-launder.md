---
title: "A decode battery that mutates only the decoder cannot see the empty-value launder, and a callee's invariance claim fails in its caller's preprocessing"
date: 2026-09-27
category: test-failures
module: plugins/soleur/skills/preflight/scripts/parse-form-a.awk
tags: [preflight, check-10, yaml, awk, mutation-testing, locale, fixture-shape]
issues: [8102, 7548]
pr: 8887
---

# Learning: a decode battery that mutates only the decoder cannot see the empty-value launder

## Problem

Preflight Check 10 runs a plan's `discoverability_test.command` via `bash -c`. PR #8149 had stripped a
symmetric quote pair in SKILL.md Step 10.4, so a YAML double-quoted scalar's escapes (`\"`, `\\`) and a
single-quoted scalar's `''` reached the shell undecoded (#8102, #7548). PR #8887 moved one YAML-correct
decode into `parse-form-a.awk`'s inline rule (TS mirror `decodeQuotedScalar`) and deleted the Step 10.4 strip.

## Solution

- Decode once, in the parser: find the first unescaped closing quote followed only by space, tab or CR
  (optionally then a whitespace-led `# comment`); decode `\"` and `\\` (double) or `''` (single);
  pass every other escape through byte for byte; leave `""`, `''`, unterminated and mismatched values
  unchanged so an empty value can never make the `[[ -z "$CMD" ]]` test fall through to the Form B fence.
- Run the parser as `LC_ALL=C awk -f` in Step 10.4 and in the test harness, with a Locale row that runs
  the real parse fence under `C` and `C.UTF-8` and requires identical bytes.
- Fixtures 11–14: one row per decode rule in isolation (empty `''`, `\\` before the closing quote, text
  after the closing quote, `#` inside quotes, a kept `\t`, CRLF), an E-fence twin per empty-pair spelling,
  and a single-line quoted Form B fence pinned verbatim.

## Key Insight

The author's four-row battery reported every row red, and a 10-seat review then found 10 of 13 new
mutants green. Every author row edited the decoder; the survivors lived in the FIXTURE corpus: a rule
with no isolated fixture cannot be told apart from its mutant. The sharpest was the empty single-quoted
pair: `''` was kept verbatim only by one `cq < 3` guard, and nothing drove `''` through the chain, so
a one-line edit laundering it to empty would have run a following fenced block with the suite green.
For a decoder, enumerate the RULES and require one fixture per rule, per quote style, before trusting
any battery that mutates the code.

Second shape: the awk header claimed host-independent output because the decode function uses ASCII
`[ \t\r]`, while the unchanged caller line `sub(/^[[:space:]]*command:[[:space:]]*/, "")` matched U+2028
and U+3000 under a UTF-8 gawk. A function's invariance claim is only as true as the preprocessing its
caller does before calling it; pin the environment (`LC_ALL=C`) at the call site and test the call site.

## Session Errors

1. **Planning subagent hung once: an unset shell variable left `grep` reading stdin** (forwarded). Recovery: stopped and re-verified. **Prevention:** `:?`-guard any variable naming a file operand in one-shot Bash blocks (already recorded in the #8803 learning).
2. **Planning recorded that an awk local named `close` "silently returned empty"; it is a syntax error in every awk (rc 1/2), and the prototype's rc was ignored.** Recovery: review measured it; comment reworded. **Prevention:** read an interpreter's rc before describing a failure mode in prose.
3. **Implementation agent hit the weekly Opus limit mid-work, leaving WIP uncommitted.** Recovery: `SendMessage` resume kept the transcript. **Prevention:** commit each verified unit as soon as it is green; one-off quota event otherwise.
4. **The resumed agent's first commit sat ~2.5 h in the pre-commit affected battery behind five sibling full runs.** Recovery: the fix commit used `LEFTHOOK_EXCLUDE=bun-test` after running the targeted suites. **Prevention:** run `test-all.sh --capacity` before a hooked commit of `.ts` files; when contended, run the targeted suites and commit with `LEFTHOOK_EXCLUDE=bun-test` (CI runs the battery).
5. **First commit rejected: MD038 (code span with a leading space) and a stale `plugin-root-skills-ratchet.tsv` row (4→2 after deleting the #8149 comment).** Recovery: rewording; row lowered per its header. **Prevention:** the pre-commit markdown lint and ratchet caught both; deleting prose that names `bash scripts/x.sh` moves that ratchet.
6. **The author's battery mutated only the decoder; 10 of 13 reviewer mutants survived, incl. the `''` launder.** Recovery: fixtures 11–14 and generalized oracle rules. **Prevention:** one isolated fixture per decode rule per quote style before claiming a battery covers a decoder.
7. **The awk header claimed host-independence while its caller's key-strip was locale-dependent.** Recovery: `LC_ALL=C` at the call site plus a Locale row. **Prevention:** test invariance claims at the call site, not the function body.
8. **New prose was false: a "one extraction" comment while two slicers existed; invisible raw U+2028/U+00A0 literals in test source.** Recovery: `step104Chain` now builds on `formAAwkSlice`; literals escaped. **Prevention:** name the command that falsifies each comment the diff adds; write separators as `\u` escapes.
9. **The review-fix commit hit MD038 again on a code span starting with a space (` # comment`).** Recovery: reworded. **Prevention:** never open a code span with a space.
10. **A closing line announced a future action and the unkept-promise Stop hook fired.** Recovery: explicit `<stop>BLOCKED: …</stop>`. **Prevention:** already hook-enforced.

## Tags

category: test-failures
module: preflight Check 10
