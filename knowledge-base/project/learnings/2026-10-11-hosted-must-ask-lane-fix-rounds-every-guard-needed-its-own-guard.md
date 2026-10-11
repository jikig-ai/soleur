# Learning: the fix rounds for the hosted must-ask lane (#9776) kept tripping repo-global ratchets and my own edit tooling

## Problem

Two review rounds on the hosted must-ask lane produced a dozen follow-up fixes. Almost none of the friction was in the classifier
itself. It was in (a) repo-global ratchets that a file-selected suite set cannot see, (b) conflicting lint rules over the same line
of a new shell harness, and (c) my own scripted edits.

## Solution

- **Conflicting temp-dir rules.** `fixture-relative-assert` wants the sandbox root provably absolute; `lint-trap-tempfile-ownership`
  rejects a literal `/var/tmp` base (rule (e), and its high-water counts annotated sites too). The only form both accept is a
  `${TMPDIR:-/var/tmp}` base plus the byte-identical `assert_fixture_dir "$SB"` copy, and the scanner credits a guard only inside
  the NEAREST ENCLOSING function window, so the call is repeated after every function definition that precedes a use.
- **A constant defined four times.** `PROMOTED_FILES` in `scripts/guard-vacuity-floor.test.sh` is assigned four times and the last
  assignment wins. Edit the effective one; the earlier three are shadowed history.
- **A shell pin containing backticks.** `README_SENT_HOSTED="…`terraform destroy`…"` executes the backticks at assignment. Pinned
  prose with backticks or apostrophes goes in `$'…'` with `\'` escapes.
- **Repo-global ratchets the affected selection missed:** `credentials_required` declared-probe baseline (53 to 54, with the
  established justification block) and the trap-ownership high-water. Remedy is the code or a deliberate, justified bump.

## Key Insight

Every guard added in a fix round (a floor, a guard call, a baseline, a mutant anchor) is itself new surface that the repo's
ratchets and my own tooling grade. Run the whole-repo ratchets (`guard-vacuity-floor`, `fixture-relative-assert`,
`lint-trap-tempfile-ownership`, `repo-wide-containment`, the discoverability baseline) after any fix round that adds a test,
a harness or a plan, not only the suites that reference the changed files.

## Session Errors

1. **A scripted slice with an empty `old` string replaced everywhere** (`s.index(a)` was after `s.index(b)`, so `old == ""` and
   `str.replace("", new)` inserted `new` between every character: +87k lines into the soak probe). Recovery: `git restore
   --source=HEAD --worktree` and redo. **Prevention:** assert `old` is non-empty and `a < b` before any slice-and-replace; check
   `wc -l` against the expected size after a scripted edit.
2. **Backticks inside a double-quoted bash pin ran `terraform destroy`** via command substitution (no config in the cwd, so only an
   empty `terraform.tfstate`). Recovery: removed the untracked file, re-quoted with `$'…'`. **Prevention:** before editing a shell
   constant that holds prose, grep the new text for backticks and `$(`; quote with `$'…'`; never run a suite after editing such a
   line without reading the diff for substitutions.
3. **Edited shadowed definitions of a last-wins constant.** **Prevention:** `grep -n '^NAME='` for every definition first.
4. **`fixture-relative-assert` vs trap-ownership conflict on one `mktemp`.** **Prevention:** satisfy both with a `${TMPDIR:-…}` base
   and the canonical `assert_fixture_dir` per function window; do not raise the trap-ownership high-water for a fixable site.
5. **Selection-blind ratchets** (discoverability baseline, trap-ownership) reddened only in the full affected gate.
   **Prevention:** run the five whole-repo ratchets by hand after adding a test file, a harness or a plan with a
   `discoverability_test`.
6. **Passed an unmeasured `--findings 60` to `emit-review-trailer.sh`.** Recovery: dropped the unpushed empty commit, re-emitted
   without the count. **Prevention:** only pass numbers you measured; omit the flag otherwise.
7. **A monitor filter matched a harness self-test line** (`judge: a red log with exit 0 is UNRESOLVED`) and re-fired every poll.
   **Prevention:** exclude the self-test prefix (`judge:`) from a monitor's failure grep, and read the log before trusting the
   first event.
8. **`gh issue create` was refused twice** (no milestone, then no filing exit). **Prevention:** write the body with a filing exit
   and pass `--milestone` and a label on the first attempt (a verification-machinery finding takes `--label meta/machinery`).
9. **A pre-existing environmental failure read as mine** (`orphan-process-reaper` AC40 refuses to signal when sibling processes are
   alive). Recovery: reproduced on an `origin/main` snapshot and filed #9975. **Prevention:** reproduce a gate failure against
   `origin/main` before attributing it.

## Tags
category: workflow-issues
module: apps/web-platform/server/destroy-ask-lane, scripts/guard-vacuity-floor, fixture-relative-assert
