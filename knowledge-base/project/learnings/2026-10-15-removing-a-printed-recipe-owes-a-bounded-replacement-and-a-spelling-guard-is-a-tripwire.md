# Learning: removing a printed recipe owes a bounded replacement, and a spelling guard is a tripwire

## Problem
#9927 item 8c removed the runnable Hetzner DELETE and Doppler destroy recipes that two orphan-sweep issue filers
printed in `scheduled-terraform-drift.yml`. The edit was 10 lines. Four review rounds then found 34 issues, almost
all in what surrounded it: a regression guard that was a lexical denylist, and a replacement procedure that was
bounded only for Hetzner.

## Solution
- Guard: scan every string leaf of every step, job-level key and workflow-level key, in a joined and a flattened
  form (re-wrapped `echo` lines), with no comment stripping; run the mutation table in-process off the same code
  (53 per-spelling rows plus a verdict-rule control that must fail both ways); give the bash consumer of the
  python verdicts its own stubbed-counter control; pin that a filer builds its body inline.
- Docs: the removed recipe's replacement is an owner-authorized, per-command procedure (runbook), bounded per
  object class. Hetzner objects are bounded by label; Doppler objects carry no label and are bounded by name
  (rung-2 config vs inngest environment). A per-item live-state read precedes every write.

## Key Insight
1. A guard that bans a SPELLING is a tripwire, not a property check. Every round found another spelling
   (`-sSX`, `-d` glued, `hcloud --quiet`, a verb on the next `echo` line). Size the effort for that: a table of
   one row per alternative of each matcher family, built so a tidy-up that drops one token goes red.
2. Removing a printed operator recipe creates a debt: the replacement procedure must exist, and its bound must
   fit every object class it covers (a label bound does not reach Doppler).
3. A plan's Guard Contract goes stale when review changes the design (comment-only input flipped from GREEN to
   RED); append an Implementation Outcome rather than leaving ticked ACs that describe the old behavior.

## Session Errors
- Ruling Class written as `technical-fork` (gate wants `technical`). Prevention: the plan skill's decision-challenges template already lists the classes; run the technical-ruling gate before `work`.
- Guard shipped as a single-spelling denylist and was widened over three rounds. Prevention: see Key Insight 1.
- `owner'"'"'s` typed inside a double-quoted echo. Prevention: render the echo body under `bash -eo pipefail` with a stub `gh` after every edit to an echo block.
- ADR bullet stated a removal date before merge. Prevention: cite the PR number, add the date in an appended addendum.
- Runbook step bounded Doppler objects by the Hetzner label. Prevention: Key Insight 2.

## Tags
category: logic-errors
module: scheduled-terraform-drift, token-drift-workflow-causes.test.sh
