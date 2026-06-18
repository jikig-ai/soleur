# "does NOT close #N" auto-closes the issue — GitHub's parser is negation-blind, and hand-rolling /ship Phase 6 bypasses the scanner that would catch it

## Problem

PR #5519 (the live-verify harness fix) carried a PR body line intended to PREVENT a
closure: **"this PR does NOT close #5463 and does NOT change the gate's
continue-on-error/topology"**. On merge, GitHub **auto-closed #5463** anyway. #5463 is
the report-only→blocking flip TRACKER — it must stay open until the flip ships — so a
later session that built a watcher targeting #5463 found it wrongly CLOSED and the
watcher's `state != OPEN → exit 0` self-disable guard would have made it a silent no-op.

## Root cause

GitHub's issue-auto-close parser is **markdown-blind AND negation-blind**: it matches
`close[sd]?|fix(e[sd])?|resolve[sd]? #N` anywhere in the PR body, including inside the
phrase "does NOT close #5463". It does not understand "not", checkboxes, code fences, or
blockquotes. The literal substring `close #5463` was enough.

This is the same class as the `#3407` trap (PR #3185 closed twice — once via a title
`(Closes #N after fire)`, once via a body checkbox `- [ ] Post-merge: close #N`). This
incident is a THIRD variant: **a negated prose mention.**

The compounding failure: the `/ship` skill's **Auto-Close Keyword Pre-Creation Scan**
(Phase 6, shared `scripts/auto-close-scan.sh`) exists precisely to catch this — it greps
the proposed title+body for close-keyword + #N and forces an explicit confirm. But I had
**hand-rolled `/ship` Phase 6** (ran `gh pr edit --body-file` directly instead of letting
the ship skill drive it), so the scanner never ran.

## Solution

1. **Recover:** `gh issue reopen 5463` with a comment explaining the negated-close
   auto-closure. The flip had not shipped (gate still report-only), so reopening was
   correct.
2. **Prevent (authoring):** never put a close-keyword + `#N` in a PR body unless you
   intend to auto-close N — even negated. To DISCLAIM a closure, phrase it without the
   keyword: "this PR is a **prerequisite for** #5463 (it does not resolve it)" or
   "tracked separately in #5463". Reserve `Closes #N` for genuine work targets.
3. **Prevent (process):** do NOT hand-roll `/ship` Phase 6 (`gh pr edit` / `gh pr ready`
   / `gh pr merge` by hand). Invoke the `soleur:ship` skill so its Auto-Close Keyword
   Pre-Creation Scan (and the Phase 6.4 unpushed-commits gate, title guard, etc.) run.
   The scanner is markdown/negation-blind by design — same as GitHub — so it WOULD have
   flagged `close #5463` for confirmation.

## Key insight

A close-keyword next to `#N` in a PR body is a loaded gun regardless of surrounding
prose — GitHub fires on the substring, not the sentence. The defenses (the #3407
pre-creation scanner) only protect you if you actually run the skill that hosts them;
hand-rolling the merge ritual silently removes the safety. "I'll just `gh pr edit` the
body quickly" is exactly when the trap fires.

## Session Errors

- **PR #5519 auto-closed #5463 via the negated prose "does NOT close #5463".** —
  Recovery: `gh issue reopen 5463` + explanatory comment. — Prevention: phrase closure
  disclaimers without the `close/fix/resolve` keyword ("prerequisite for #N"), AND run
  `soleur:ship` rather than hand-rolling `gh pr edit` so the Auto-Close Keyword
  Pre-Creation Scan (#3407, `scripts/auto-close-scan.sh`) runs.
- **shellcheck SC2034 (unused `LAST_OUT`) in the new test.** — Recovery: removed the
  unused capture; shellcheck rc=0. — Prevention: one-off, self-caught by the bash review
  gate; no workflow change needed.

## Tags
category: workflow-patterns
module: ship
