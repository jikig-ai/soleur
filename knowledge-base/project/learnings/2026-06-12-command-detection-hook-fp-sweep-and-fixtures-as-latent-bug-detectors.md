# Learning: command-detection-hook FP fixes are sweeps; FP fixtures double as latent-bug detectors

## Problem

#5192: the `require-milestone` guardrail (and its siblings) false-matched a trigger phrase
(`gh issue create`, `gh pr merge`, `git stash`, `gh pr ready`) when that phrase appeared at a
line-start inside a `git commit -m "…"` message body — blocking a legitimate commit that merely
*documented* the command. The canonical fix (#4600) — a `perl -0777` strip of quoted/heredoc
bodies before the detection grep — already existed inline in `pre-merge-rebase.sh`. The task was
to extract it into a shared helper and apply it across every FP-reachable gate.

## Solution

Extracted `strip_command_bodies` into `.claude/hooks/lib/incidents.sh` (the de-facto shared hook
lib — already hosts `resolve_command_cwd`, `detect_bypass`), then routed every PHRASE-detecting
gate's trigger grep through the stripped `$SCAN` while leaving `git commit`-class gates on raw
`$COMMAND` (a body mentioning "git commit" still IS a commit — not FP-reachable). Six hooks +
`pre-merge-rebase.sh` consume the one tested copy. `pre-merge-rebase.sh`'s inline perl was deleted.

## Key Insight

**A command-detection-hook FP fix is a SWEEP, and the plan's sweep-audit table is an intuited
list — re-grep every phrase-class gate at work/review time.** The plan enumerated guardrails'
require-milestone + block-stash and 5 siblings but MISSED `block-delete-branch`
(`gh pr merge --delete-branch`), an identical phrase-class FP. An independent
`grep -rnE 'echo "\$COMMAND" | grep .*gh\s+pr\s+merge' .claude/hooks/` at review-time surfaced it;
fixed inline. This is the same rule as
[[2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited]] applied to PreToolUse hooks, and
extends [[2026-05-29-command-detection-hook-self-interception-and-heredoc-fp]].

**FP test fixtures double as latent-bug detectors.** Building the RED case for
`follow-through-directive-gate.sh` forced the hook down code paths the existing tests never
exercised, surfacing two pre-existing bugs:
- `BODY_FILE=$(echo "$CMD" | grep -oE -- '--body-file…' | head -1 | awk …)` under
  `set -eo pipefail`: a no-match `grep` exits 1 → `pipefail` aborts the hook → **fail-OPEN** for
  any real inline-`--body` create. Sibling `BODY_INLINE` line already had `|| true`; restored parity.
- `perl … { print 2; }` (literal `2`) instead of `print $2;` → `BODY_INLINE` was always `"2"` →
  every inline-`--body` follow-through create was wrongly DENIED (directive-missing). 1-char fix.

Both were fixed inline with regression tests (T16) per the cost-of-filing gate, not filed.

## Prevention

- **Sweep grep, not plan table.** When a PR claims "fix the latent FP class in one PR," re-derive
  the gate list with a grep at work-start AND review-time; treat the plan's audit table as a
  hypothesis. (Reinforces the grep-enumerated-work-list rule already in plan/review skills.)
- **`set -e` + `pipefail` + no-match `grep` = silent abort.** Any `VAR=$(… | grep … | …)` extractor
  in a hook needs `|| true` (or the grep must be guaranteed to match). The abort direction matters:
  for a deny-gate it fails OPEN.
- **Develop command-detection hooks through committed `*.test.sh` fixtures only** — never put an
  unquoted trigger literal in an ad-hoc Bash tool call while editing these hooks (self-interception).

## Session Errors

1. **Plan Sweep-Audit table omitted `block-delete-branch`** — Recovery: independent review-time
   re-grep of phrase-class gates; fixed inline (cc0832ae3). Prevention: grep-derive the sweep list
   at work-start, don't trust the plan's intuited table (already a rule; this is a confirming instance).
2. **`set -e`+pipefail no-match-grep fail-open** in `follow-through-directive-gate.sh` `--body-file`
   extraction — Recovery: added `|| true` (parity with the sibling `BODY_INLINE` line). Prevention:
   audit every `$(… | grep … )` in a `set -e` hook for the no-match-abort foot-gun.
3. **`print 2`→`print $2` typo** (pre-existing #4262) wrongly denied all inline-`--body` follow-through
   creates — Recovery: fixed inline + T16 regression test. Prevention: one-off typo; the new test guards it.
4. **`cla-signed-author-gate.test.sh` T6 transient flake** under chained full-suite runs — Recovery:
   confirmed standalone green + CI runs each file as a separate process (unaffected). Prevention:
   one-off; if it recurs, harden `make_branch`'s git-setup against concurrent-run contention.
5. **grep `T15` matched the `…T15:00:00Z` timestamp substring** / a nested-quote `bash -c` isolation
   harness mis-quoted once — Recovery: used literal `grep -F "[T15]"` / switched to a heredoc.
   Prevention: one-off; anchor test-marker greps with the literal bracket.

## Tags
category: bug-fixes
module: .claude/hooks
