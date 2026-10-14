---
module: System
date: 2026-10-05
problem_type: logic_error
component: tooling
symptoms:
  - "A hand-closed follow-through tracker whose probe exits 5 is reopened on every daily sweep for the 14-day lookback, with an empty comment"
  - "A probe suite stayed green with the shebang, exec bit and no-seam clock path unexercised"
  - "The review panel found 14 unique defects, 6 of them in the fixes' own guards"
root_cause: logic_error
resolution_type: code_fix
severity: medium
tags: [follow-through, sweeper, notify-only-probe, retirement-path, guard-shaped-pr, mutation-testing, structural-enumeration]
---

# Troubleshooting: a notify-only probe's retirement path was an untested sweeper arm, and my suite never ran the probe the way the sweeper does

## Problem

PR #9536 enrolled tracker #9387 in the follow-through sweeper with a notify-only date probe
(`scripts/followthroughs/tty-ack-migration-9387.sh`: exit 2 before 2026-10-16, 5 on or after, 3 on an
unusable clock, never 0 or 1). Review found that the tracker's own retirement path did not work: the
sweeper's closed-set `5)` arm set `action="comment"` but never `body_msg`, so under `set -euo pipefail`
the shared tail expanded an unset variable (the caller's `|| fail` suppresses `set -e`) and then ran
`gh issue reopen` for every action. An operator who closed the tracker as instructed would have had it
reopened daily for 14 days, with no reopen marker to bound it. Two existing probes
(`ccla-representative-icla-7922.sh`, `ghcr-read-retired-8036.sh`) share the exit-5 vocabulary and the same
exposure.

## What Didn't Work

**Direct source assertions.** `T19c` in `scripts/sweep-followthroughs.test.sh` asserted
`action="comment"; verdict="ACTION REQUIRED"` and `action="reopen"; verdict="ACTION REQUIRED"` are absent. Both are
true, and the arm still reopened, because the reopen lived in the shared tail and ran for any action. A
grep over the source cannot see a branch that the arm does not contain.

**My first suite for the probe.** It pinned the probe's text (exit operands, no `set -e`, no `gh`) and ran a
fixed-clock table, always as `bash <probe>`. The sweeper runs the probe by direct exec under `env -i` with
the real clock. So a broken shebang, a lost exec bit, CRLF line endings, `exec true`, `eval`, a computed
command name or `${NOW_EPOCH:-0}` all left the suite green (the structural-enumeration seat measured 12
such edits at 41/0; the test-design seat found the no-seam clock path unreachable by any row).

## Solution

- **Sweeper (5 lines):** the `5)` arm builds its own comment body, and the reopen is guarded by
  `[[ "$action" == "reopen" ]]`. Test `T11b` drives the closed-set exit-5 path through the existing stub
  harness and asserts: comment posted, **no reopen**, non-empty body carrying the verdict heading and the
  label instruction. It fails against the old sweeper (verified on a sandbox copy); `T9` still pins that exit 1
  reopens. The second-reviewer gate DISSENTED on filing this as a scope-out (5 lines, 2 files, no
  technical objection), so it was fixed inline.
- **Probe message and runbook:** exit 5 now says "close #9387 by hand AND remove its `follow-through`
  label", because a closed tracker keeps being swept for `CLOSED_LOOKBACK_DAYS` while the label is on.
  `followthrough-convention.md` says the same for every notify-only tracker.
- **Probe suite (41 → 60 assertions, 17 mutants):** run the probe through its own shebang under `env -i`
  (`exec_ok`), pin the exact shebang and no CR, ban `exec`/`eval`/`source`/`kill`, `/dev/tcp` and other
  network clients on executable lines, report a bare `exit` with a sentinel instead of letting it vanish,
  re-run the clock table under a non-UTC zone, fold the date-unusable arms into the mutation checker, drive
  the no-seam real-clock path with a fake `date` (`realclock_check`), and run a non-ASCII digit under
  `en_US.utf8` where `[0-9]` really matches it (`locale_check`, skipped loudly where that locale is absent).

## Key Insight

1. **A substrate's retirement path is code, and it needs a behavioural test.** The probe's whole design
   hinged on "the operator closes the tracker when done". Nothing exercised what the sweeper does next. For
   any probe-shaped deliverable, drive the CLOSED path as well as the open one.
2. **Run the guarded thing through the entry point its consumer uses.** `bash <probe>` and the sweeper's
   `env -i <probe>` are different programs (shebang, exec bit, line endings, PATH, real clock). A seam that
   injects the clock hides the one input production always uses.
3. **A guard over a spelling is not a guard over the property.** Six of the second-round findings were in
   the first-round fixes' own guards: a locale test forced `C.UTF-8` (where `[0-9]` matches no non-ASCII
   digit, so the rows could not fail) and used digits that do not match `[0-9]` even in `en_US.utf8`; a
   comment said a bare `exit` prints nothing (it printed an empty line that passed the filter). The cure was
   the same as in the sibling learnings: a map of every path to the property (structural-enumeration seat), one
   mutant per sub-check, and a re-verification pass that mutates the new checks rather than re-reading them.
4. **The ledger half of a trigger that lives on the founder's machine cannot be probed from CI.** The honest
   shape is a notify-only date probe that tells the operator to confirm the approval themselves (ADR-264: a
   ledger line is not approval evidence). I first proposed checking the ledger, which was impossible; reading
   the ADR before designing, not after, would have saved a round.

## Session Errors

**Early design claim that the probe would check the run ledger.** — Recovery: read ADR-264 and the operator-script library; the ledger is a founder-machine file the sweeper cannot read; redesigned as a notify-only date probe and told the operator. — **Prevention:** before proposing a CI probe for a condition, name where the evidence lives and whether the CI runner can read it.

**A glob loop ran `bash` over `.highwater`/`.py` files** (rc 127 noise). — Recovery: invoked the lint's real entry point on the files that matter. — **Prevention:** list a lint's own invocation in `scripts/test-all.sh` before running it by name.

**`pgrep -f` was blocked by the self-match hook.** — Recovery: used `proc.sh list_runs`. — **Prevention:** already hook-enforced; use the helper from the first attempt.

**Two foreground commands exceeded the 120 s ceiling and were moved to background.** — Recovery: waited with a bounded Monitor on the output file. — **Prevention:** start any ratchet battery or the sweeper suite in the background with a log file.

**`shellcheck` SC2034 (unused capture) in the new suite.** — Recovery: dropped the capture. — **Prevention:** run `shellcheck -S warning` on every new `*.sh` before the first commit, not at the end.

**False comments I wrote in the probe and suite** (the `LC_ALL` rows "under test"; "a bare exit prints nothing"; "the arithmetic would abort with status 1" when it silently takes the NOT YET arm). — Recovery: re-measured each in the shell and rewrote; added a mutant and a pin so the property is tested rather than described. — **Prevention:** for every claim a comment adds, name the command that falsifies it and run it before committing (already the documented rule; applied late).

**The fixture-relative ratchet was not re-run after the sweeper commit.** — Recovery: T11b's copied `rm -rf "$root"` was a priced site; dropped it because `SUITE_TMP` is removed at exit, baseline untouched. — **Prevention:** re-run `fixture-relative-assert` and `fixture-dir-operand-assert` after EVERY commit that touches a `*.test.sh`, not once per branch.

**The planning agent ran deepen-plan's halt gates mechanically instead of the full research fan-out.** — Recovery: disclosed in its summary and the plan's Enhancement Summary; the review panel then covered the gap. — **Prevention:** none beyond disclosure; the change was a 55-line probe.

## Related

- `knowledge-base/project/learnings/2026-09-18-every-defect-was-in-my-verification-not-the-feature.md`
- `knowledge-base/project/learnings/2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md`
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (notify-only retirement note added by this PR)
