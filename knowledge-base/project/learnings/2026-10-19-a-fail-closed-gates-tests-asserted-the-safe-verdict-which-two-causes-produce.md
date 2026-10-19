---
module: CI
date: 2026-10-19
problem_type: test_gap
component: doc_only_skip_classifiers
symptoms:
  - "New executed modes (symlink, execbit, modeflip, transition) asserted only `applicable=true`, a verdict the enum-failed fallback also prints, so a broken diff feed would have passed them"
  - "Appending `--diff-filter=AM` after the `git diff --raw` range left all three suites green (substring anchor), dropping deletions and typechanges"
  - "The `transition` case ran an embedded frozen pre-change classifier that nothing proved said `false` on a name-status row"
  - "Dropping the row regex `^` or `$` stayed green: the STATUS guard masked the rename rows meant to pin them"
root_cause: assertion_satisfiable_by_wrong_cause
tags: [ci, classifier, fail-closed, test-design, mutation]
---

# A fail-closed gate's tests asserted the safe verdict, which two causes produce

## Problem

#10416 made two doc-only skip classifiers mode-aware (`git diff --raw` rows, skip only for A 000000->100644 and M 100644->100644). The first test pass was green on every axis the plan listed. Eleven review seats then found no bypass, but the test-design seat showed four ways the suites stayed green while the central change was not actually exercised. All four have one shape: for a gate whose safe answer is `true`, asserting `true` proves nothing about WHICH path produced it.

## Solution

- Assert the cause, not the verdict. The executed-step cases now also require that the `fell back to enum-failed` warning is absent for every mode that reaches the classifier with a real diff (`ci-classify-step-exec.test.sh`).
- Give every embedded instrument a control. The frozen pre-change classifier must print `false` on a name-status markdown row, otherwise a heredoc that always fails closed keeps the `transition` case green for the wrong reason.
- End-anchor a pinned command line through the next token that follows it (`2>>"$GIT_ERR")"`), so a flag appended after the range reds the anchor. A substring anchor pins what is there, never what may follow.
- Pin a regex's `^`/`$` with a probe the other guards cannot mask (a status-M row with a second tab field; junk before the colon). Prove each probe discriminates by dropping the anchor on a mktemp copy and watching the probe go red.
- A diff feed has flags that change what it can SEE (`--ignore-submodules=none`): list the flags that hide rows, not only the ones that shape them.

## Key Insight

Ask of every assertion in a fail-closed suite: name a second cause that prints the same expected output. If one exists, the assertion pins the output, not the property. The review skill's "name the edit that reverts the central change" question found three of the four; the fourth (`^`/`$`) needed the mutant run on a copy.

## Session Errors

1. **Fixtures built by a generator carried doubled escapes (`\\t`, `\\n`), so rows were vacuous and every `false` case passed for the wrong reason.** Recovery: sed fix, re-verified RED/GREEN counts. **Prevention:** after generating fixtures, print one with `od -c` and assert the TAB byte is present before trusting the suite.
2. **An inline copy of `assert_fixture_dir` differed from the canonical body; `fixture-dir-operand-assert` and `fixture-relative-assert` flagged it and 9 write sites.** Recovery: byte-identical copy, guard before each write. **Prevention:** copy the helper with `sed -n` from `test-helpers.sh`, never retype it.
3. **Three decision-log rows were labelled `technical`/`mechanical` for rulings that were not the CTO's; `technical-ruling-gate.sh` failed.** Recovery: reclassified to `taste`. **Prevention:** label a row `technical` only when a CTO agent ruled it; everything else is `taste`.
4. **Hooks blocked `git stash list` and `pgrep -f`.** Recovery: re-ran without them. **Prevention:** none needed beyond the existing hooks; one-off.
5. **A two-dot `git diff origin/main` showed unrelated deletions because the branch was behind.** Recovery: three-dot merge-base diff. **Prevention:** always `origin/main...HEAD` for "what did this branch change".
6. **A long ratchet loop exceeded the 600 s tool timeout, and `test-all.sh --affected` sat in the FIFO lock queue about 2 h; in review, `timeout 250` around `test-all-affected.test.sh` left the wrapper alive past 17 min.** Recovery: detached `setsid` run with an `RC=` line, monitored. **Prevention:** run any suite that may queue behind the test lock detached with a written `RC=` line and a Monitor, never in the foreground.
7. **The first `--fix-round --since` call used a SHA I retyped from memory with wrong middle characters (`does not resolve to a commit`, rc=2).** Recovery: `git rev-parse` of the short SHA. **Prevention:** resolve a panel SHA with `git rev-parse` into a file at panel time; never retype a 40-hex.
8. **A seat was spawned for a lens the plan's threshold excludes (user-impact on an `aggregate pattern` plan); it declined after one tool call.** Recovery: none needed, one seat of cost. **Prevention:** read the plan's `Brand-survival threshold` before listing the panel; the risk-tier table owns which seats a tier adds.
9. **Two closing messages named a next action without taking it and were bounced by the unkept-promise stop hook.** Recovery: ended with a `Paused:` sentence stating what was awaited. **Prevention:** when waiting on background work, end with the `Paused:` sentence in the first place.

## Recurring-vs-one-off triage

| item | recurring? | disposition |
|---|---|---|
| 1 doubled escapes in generated fixtures | recurring | fix-now: prevention line above (no code to change here) |
| 2 inline helper drift | one-off (ratchet already catches it) | none |
| 3 ruling-class mislabel | one-off (gate already catches it) | none |
| 4 blocked stash/pgrep | one-off | none |
| 5 two-dot diff | one-off | none |
| 6 foreground suite behind the lock queue | recurring | note in learning |
| 7 retyped SHA | recurring | note in learning |
| 8 excluded seat spawned | one-off | none |
| 9 unkept-promise closes | one-off (hook catches it) | none |
| silent refusal reason in the classifiers | recurring | file-tracked: #10522 |

## Route to definition

No skill edit. The question that found three of the four gaps ("name the edit that reverts the central change, and say which test reds") is already in `soleur:review` and `test-design-reviewer`; the new content here is the cause-versus-verdict phrasing, kept in this learning.
