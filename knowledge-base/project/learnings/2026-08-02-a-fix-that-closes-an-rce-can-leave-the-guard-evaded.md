# A fix that closes an RCE can leave the guard evaded — in the same line

**Date:** 2026-08-02
**Issue:** #7164 · **PR:** #7168
**ADRs:** ADR-155 (trust boundary), ADR-156 (response posture)

## The bug behind the bug

Ten `PreToolUse` hooks ran `eval "$(… jq -r '@sh "COMMAND=\(.tool_input.command)"' …)"`, each
carrying a comment asserting that `@sh` made `eval` safe. It does — for a **string**. `jq @sh` quotes
each element of an **array** as a separate word, so `["x","touch","/tmp/PWNED"]` became an assignment
followed by a command, executed before the permission prompt with operator privileges. 10/10
reproduced.

The issue proposed coercing non-strings with `tojson` as the first remedy. **That would have closed
the issue on a false negative.** Coercion stops the execution and leaves every anchored guard
bypassed: `["git","stash"]` matches no guard regex. Eight further hooks read the same field via
`$( )`, never call `eval`, and were defeated by the identical payload — so a fix scoped to the ten
`eval` sites would have retired a P0 while most of the Bash-path gates stayed evadable.

**Whenever the remedy for hostile input is *normalization* — coercion, scrubbing, transliteration,
case-folding — re-run the downstream matcher against the normalized value.** "It can no longer
execute" is not "the guard still fires". This work committed the error twice: once with `tojson`, and
again with a proposed lone-surrogate scrub (`git ␦ stash` matches nothing either). Both were caught
only by running the real regex against the transformed value.

## Corollaries that generalize

**A test authored after the fix cannot be seen to fail.** The assertion that catches
coerce-and-continue was written and observed RED against `main` first: the array payload *allowed*
`git stash` while the string control still denied. Written after the migration it would have been a
green line of unknown strength.

**A mutation battery is how you find out what your suite cannot see.** As first written, the contract
suite let two protections be deleted while staying green — `${IFS-}` → `$IFS`, and removing `set -f`.
Neither was observable, because the hooks run `set -eo pipefail` without `-u` and no assertion used a
whole-value glob (`rm *` cannot catch a missing `set -f`; only a value that is *entirely* `*` can).
Require each arm to fail with a **relevant assertion label** — "the suite went red" cannot say which
protection was removed, and one loud failure masks a second silent one.

**A harness bug reads exactly like a finding.** The first mutation run reported 9 failures at
baseline; the cause was that the sub-runner had been written to `/tmp`, so `SCRIPT_DIR` resolved the
aggregator to a nonexistent path and every arm "failed" for that reason. Verdicts from a harness that
cannot set itself up are not weak evidence — they are *no* evidence. Same shape as the reproducer
whose payload created stray `TOOL_NAME=` files in the CWD: run it from a fresh `mktemp -d`, or stale
markers either false-fail or self-satisfy.

**A lint finding can be a cost finding.** The ADR-129 trap-ownership lint flagged a `mktemp` in the
extractor. The hygiene issue was real, but the *actual* defect was that the helper allocated and
unlinked a tempfile on **every invocation** — 18 hooks fire per Bash tool call — to carry diagnostic
garnish that jq's exit code already provided. Removing it roughly halved the small-payload overhead
(+16.7% → +6.5% at 100 B). The tempfile had been added *after* the plan's benchmarks, so no measured
number covered it.

**Read the file, not the notification.** Twice, a background-task notification reported "exit code 0"
for a wrapper while the real work was still running or had failed — once for a suite runner, once for
the mutation battery, whose monitor reported a stale 7/10 when the file on disk said 10/10. And
`pkill -f <pattern>` matched this session's own command line and killed the invoking shell, taking an
unwritten heredoc with it.

**An expectation can encode the bug.** `pre-merge-rebase.test.sh` asserted that a malformed payload
produces exit 0, no deny, **and no incident row**. The third clause was defect 2 written down as a
requirement: it pinned the silent disarm. Refreshing it — rather than silencing it — was the fix.

## The durable rule

`.claude/hooks/lib/hook-input.sh` type-asserts every contracted field and performs **no shell
evaluation of hook input**. The claim to make is exactly that; "input is now safe" is the claim that
made this invisible for four months, and it is the one the four corrected comments used to make.

## Tags

category: security-issues
module: claude-code-hooks
issue: 7164
pattern: normalization-is-not-verification + red-first-assertion + mutation-battery
