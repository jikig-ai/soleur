# Learning: a backstop claim copied into two rulings was false, and only a conflict between review seats exposed it

## Problem

PR #10879 (detect-and-file follower for cancelled apply pushes) shipped, after its first review round, a close comment and runbook/ADR text saying the 12 h drift check "covers" pushes older than the follower's 7-day window and "does not catch a non-Terraform delivery such as a deploy-fix host copy". Two CTO rulings (F22, F23) carried that sentence. Both halves were wrong in different directions: the close comment asserted coverage nobody measured, and the "non-Terraform" example was false because `terraform_data.deploy_pipeline_fix` is Terraform state whose trigger hash changes with the script, so an untargeted `terraform plan` does surface a missed deploy-fix apply.

It surfaced only because two verification seats disagreed (security read "plan only, no deploy-fix hits in the workflow"; architecture read the resource and the full-root plan). A single seat would have passed either reading.

## Solution

Read the resource, not the workflow name: `server.tf:2147` (`terraform_data.deploy_pipeline_fix`) plus `scheduled-terraform-drift.yml` (full-root `terraform plan -detailed-exitcode`, no `-target`). Then correct by appending (decision row F29, a dated "Corrected" note in the ADR) and narrowing every runtime string to what the code verifies: the close comment now says older pushes are "not examined by this check" and nothing more.

Three further fixes from the same review round:

- The flip-evidence recipe grepped `apply-delivery-gap::row`, but `gh run view --log` renders `::notice title=T::msg` as `##[notice]msg` (the title is dropped), so the recipe would have counted zero on a real run. The grep now matches `row workflow=<key> sha=<40hex>`, which both renderings share, and the suite runs the runbook's own regex over the emitter's line in both forms.
- A row emitter joined fields with tabs while the parser used `IFS=$'\t' read`: an empty middle field collapsed and shifted the next value into the wrong cell. Use a non-whitespace sentinel for empty fields.
- A delivery loop that tested ancestry before the apply job burned its read budget on skipped-apply successes (150 reads and a budget failure for 60 candidates). Testing the cheaper memoised predicate first made it 63 reads.

## Key Insight

A sentence about what a backstop covers is a claim about another system. When it is copied into a ruling, a comment and two docs, each copy reads as established because the others do. Falsify it where the other system is defined (the resource and the plan scope), once, before it propagates. Also: when two seats disagree, that is the highest-value signal in the round, not noise to average out.

## Session Errors

1. **Ruling premise unverified (F22/F23 drift-coverage claim)** — Recovery: verified against `server.tf` and the drift workflow; appended F29 and an ADR correction. Prevention: before a ruling or comment states what a backstop does or does not catch, read the backstop's resource definition and plan scope and cite them in the ruling row.
2. **Flip-evidence grep written from emitter text, not from the rendered log** — Recovery: matched on the shared `row workflow=… sha=…` substring and pinned it with a suite assertion over both renderings. Prevention: when documenting how to find an annotation, check how the log renders it (the repo already has two measured notes) and assert the recipe against the emitter's output.
3. **Structural-enumeration seat ended its turn with only partial mutation output and no final report** — Recovery: used the partial output (it showed the same "deleted group stays green" class as test-design), recorded the seat as missing in the review trailer (12/13, degraded). Prevention: a seat brief must say "write the report file before waiting on any monitor", and the lead should check the report file exists when a seat notifies, re-prompting with SendMessage if it does not.
4. **A verification seat ran about 2.5 h on a loaded host** — Recovery: SendMessage asking it to write what it had verified; it did. Prevention: bound long seat runs in the brief ("stop at N minutes, write what you have") and nudge early rather than wait.
5. **Suite wall time (the 90 s ceiling) varied 77–114 s with host load** — Recovery: disclosed in the PR body; the ceiling is a design target that nothing enforces. Prevention: state a CPU-time budget (stable under load) rather than a wall-clock ceiling when the host is shared.
6. **Untracked `.local/state/gh/device-id` appeared in the worktree mid-session, source unattributed** — Recovery: never staged (explicit paths only). Prevention: keep `git add <path>`; never `git add -A`.
7. **Brief inaccuracy: fix-round brief said the six new relative-operand sites were in the script; they were in the suite file** — Recovery: implementer found and reported the deviation. Prevention: re-derive line anchors from the live file before putting them in a brief.
8. **Closing text with a first-person commitment tripped the stop hook once** — Recovery: ended with a `Paused:` sentence. Prevention: a waiting turn ends with one `Paused: <what is awaited>` sentence, not "I'll do X once…".

## Tags

category: workflow-issues
module: apply-delivery-gap-follower, review
