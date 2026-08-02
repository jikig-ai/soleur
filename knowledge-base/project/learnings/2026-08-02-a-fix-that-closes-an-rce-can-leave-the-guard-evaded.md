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

## Session Errors

Four forwarded from the planning phase via `session-state.md`, the rest from implementation. The
review panel and the full suite found more defects in *this PR's own fix* than the fix itself
originally addressed, which is the honest headline.

**Control bytes emitted where escape notation was intended** — four times (a probe, the jq program
itself, and two test fixtures). A literal U+001E inside the single-quoted jq program is invalid JSON
and flags the file as binary. **Prevention:** construct the escape programmatically
(`printf '\\u%04x' 30`) rather than typing it; the contract test now asserts structurally that the
jq program contains no apostrophe, and a `grep -qP '\x1e'` check catches the byte form.

**An apostrophe inside the jq program terminated the bash string** — writing "jq's" in a comment
inside `_HOOK_INPUT_JQ='…'` silently ended the single-quoted string, and bash began interpreting the
program as commands. **Prevention:** assertion added (`no apostrophe inside the jq program`), plus a
comment in the file saying why.

**The mutation harness wrote its sub-runner to `/tmp`**, so the suite resolved `AGGREGATOR` from its
own `SCRIPT_DIR` to a nonexistent path and every arm "failed" for that reason. The first battery
reported 9 baseline failures that meant nothing. **Prevention:** a harness that cannot set itself up
must abort, not emit verdicts — and a baseline arm that is not green invalidates the whole run.

**`chmod 000 jq` does not hide a binary from `command -v`** — it skips non-executables and finds the
real jq further along `PATH`, so A5 silently exercised the `nonstring` path while claiming to test
`jq_missing`. It reported `ask` for the wrong reason. **Prevention:** the test now builds a PATH of
symlinks that genuinely omits jq **and self-checks the precondition**, failing loudly if jq is still
reachable.

**`pkill -f 'timeout 3000 bash scripts/test-all.sh'` matched this session's own command line** and
killed the invoking shell, taking an unwritten heredoc with it (the commit message file was never
created, so the next command failed `no such file`). **Prevention:** kill by PID, or match a pattern
that cannot appear in the matching command itself.

**A background-task notification reported a stale result twice.** The mutation battery was reported
as 7 caught / 3 missed from a monitor event while the file on disk said 10/10; a suite-runner
notification said "exit code 0" for a wrapper whose child was still running. **Prevention:** read the
result FILE; a notification reports the last command in the wrapper, not the work.

**Edited files under a running `test-all` twice**, invalidating both runs — the first failure
(`pre-merge-rebase.test.sh`) was a mid-flight snapshot of a half-migrated tree and had to be
re-diagnosed against the settled tree. **Prevention:** `git status --porcelain` empty before launch;
if an edit cannot wait, kill the run rather than reinterpret its output.

**Two bugs in the extractor's first draft:** `local o=${IFS-}` always *sets* the variable, so the
`unset IFS` restore branch was unreachable and IFS was restored to `""` for a caller that had it
unset; and `jq_rc` was captured but never read, collapsing "we shipped a broken hook" (rc 3) into
"the model sent junk" (rc 5). **Prevention:** both now have assertions; the restore path is driven
with IFS genuinely unset under `set -u`.

**A per-invocation `mktemp` shipped on the hot path** — 18 allocate+unlink pairs per Bash tool call,
to carry diagnostic text the exit code already provided. It was added *after* the plan's benchmarks,
so no measured number covered it. **Prevention:** benchmark the final code, not an intermediate; the
ADR-129 trap-ownership lint is what surfaced it, and it caught a second `mktemp` leak later in the
same PR.

**Four defects the review panel found in code this PR added** — jq's `//` falsy-default letting
`false` defeat the type assertion; a mirror guard placed below the early-exit gates that consume the
fields it validates (dead code); a third wired blocking mirror missed because the scope said "two";
and a missing-helper path that passed through silently in 12 hooks, where the *first* fix was also
wrong (placed after the `source`, unreachable under `set -e`). **Prevention:** each has a regression
assertion; the boolean case in particular exposed that the type corpus covered array/string/object
and no boolean.

**A false rationale written into the README by this PR** — 10 hooks described as gating nothing, when
4 emit `permissionDecision` and one can emit an explicit `allow`. **Prevention:** the claim is now a
measured table, not prose. This is the same shape as the `@sh`-is-safe comment that let #7164 live
for four months: a plausible sentence nobody re-measured.

**Two suites the full run caught**, both mine and both legitimate: a `gh` stub that ignored `argv`
(so it could not detect the gate querying the wrong thing) and a `mktemp` with no owning trap.
**Prevention:** both classes already had repo-wide gates; the lesson is that the gates work and the
full suite is not optional.

**Forwarded from planning:** two transient `gh` TLS timeouts (succeeded on retry); the reproducer
creating stray `TOOL_NAME=`/`FILE_PATH=`/`SESSION_ID=` files in the worktree root when run from the
wrong CWD; control bytes in both artifacts; and `test-design-reviewer` + `code-simplicity-reviewer`
forcing a second full plan rewrite.

## The durable rule

`.claude/hooks/lib/hook-input.sh` type-asserts every contracted field and performs **no shell
evaluation of hook input**. The claim to make is exactly that; "input is now safe" is the claim that
made this invisible for four months, and it is the one the four corrected comments used to make.

## Tags

category: security-issues
module: claude-code-hooks
issue: 7164
pattern: normalization-is-not-verification + red-first-assertion + mutation-battery
