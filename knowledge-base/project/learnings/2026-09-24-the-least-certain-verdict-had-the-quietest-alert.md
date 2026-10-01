---
title: The least certain verdict had the quietest alert
date: 2026-09-24
category: logic-errors
module: .github/actions/dispatch-web-redeploy
issues: ["#8710", "#5274"]
pr: 8755
tags: [ci-gate, alerting, review-panel, subagents, mutation-testing]
---

# Learning: the least certain verdict had the quietest alert

## Problem

#8710's gate (`source-run-gate.sh`) decides whether a git-data birth/replace run published a new
SSH host-key pin and so must force a production web redeploy. The fix correctly keyed it on the
`id: apply` step's conclusion instead of the job's (a `plan_only` rehearsal ends `success` with
the apply skipped). But it split the red-job case in two:

- `pin_published` — apply step `success`, job red: warning **and** an ops email.
- `pin_maybe_published` — apply step `failure`/`cancelled`/not found, job red: warning only.

The second state is the one where the pin may already be in Doppler prd (the replace job writes
the secret right after server create, and its post-apply checks can fail afterwards). It ended the
follower run GREEN with one annotation and no email — the least certain state had the quietest
alert. Four of eleven review seats found it independently (agent-native, simplicity, architecture,
code-quality); code-quality reproduced it with a stubbed `gh`.

## Solution

Both warning verdicts set the `pin_published=true` output, which drives the ops email; the tokens
stay distinct so the operator still reads which case it was. The email step got `id: pin_email`
and a follow-up step fails the run when `sent != 'true'`, so the failure email is a second try
(the `scheduled-terraform-drift.yml` `reconcile_notify` precedent). The mutation row
`maybe-no-email` (`pin_published=${warn}` → `${pub}`) now reds G12.

Same review, same gate: every jq read became a checked assignment in the gate's own shell. A
nested `cnt="$(num "$(jq ...)")"` hides a jq failure from errexit and `num` turned it into `0` —
"could not read" graded as "job did not run", the dangerous direction for a pin.

## Key Insight

When a gate grades uncertainty in steps (published / maybe published / not published), check that
the alerting is monotonic in RISK, not in CERTAINTY. The natural way to write it — alert loudly on
the case you are sure of — inverts that: the certain case gets the email and the uncertain one,
which is at least as dangerous, gets a log line. Ask of every verdict: "if this is the bad case,
who finds out, and how?"

## Session Errors

1. **Two review seats returned EMPTY final results** (structural enumeration ×3, test design ×2);
   `SendMessage` resumes did not recover the report text. Recovery: a fresh spawn whose prompt
   mandated writing the report INCREMENTALLY to a scratchpad file and ending with `WROTE <path>`.
   **Prevention:** for long-running mutating/enumeration seats, put the file-delivery mandate in the
   SPAWN prompt (routed to `review/SKILL.md` Sharp Edges).
2. **Two "killed" mutants were false kills.** The GM rows apply a mutation by literal text and
   report a stale site as a failure, so an edit to a guarded line reds the suite through the site
   check, not a behavioural assertion. Recovery: the reviewer rewrote each mutant to keep the site
   text; both survived until rows G26 / G10b were added. **Prevention:** attribute a kill to the
   row's named assertion, never to the suite's rc (already the rule in `review/SKILL.md`
   "A CRASH IS NOT A KILL").
3. **`sed -n 56-124p` → "unknown command".** Recovery: `56,124p`. **Prevention:** one-off typo.
4. **A runbook substitution asserted 5 sites; there were 4.** Recovery: the assert aborted before
   writing; recounted. **Prevention:** keep the count assert (it did its job).
5. **A mutant replaced a `case` arm with `:`** and failed to parse. Recovery: `"__never__")`.
   **Prevention:** the harness's `bash -n` check caught it; mutate a case arm's PATTERN, not its body.
6. **PT5 was over-broad:** the runbook also cites other gates' `verdict=` tokens. Recovery: scope to
   lines about this gate plus a non-vacuity assertion that each document still cites its tokens.
   **Prevention:** derive a parity set's population from the subject, not from a token shape.
7. **`TEST_FLOOR` set to tests RUN (227)** where it counts declared `test(` sites (222). Recovery:
   read the floor test and use its measure. **Prevention:** read what a floor counts before setting it.
8. **`lint-infra-no-human-steps` rejected an ADR sentence** prescribing an operator
   `terraform apply`. Recovery: restate it as a fact pointing at the CI recovery dispatch.
   **Prevention:** the pre-commit hook already enforces this.
9. **`git rev-parse --short HEAD origin/<branch>`** → "Needed a single revision". Recovery:
   `git ls-remote`. **Prevention:** one-off.
10. (forwarded) A foreground `sleep` was refused, and one Edit was rejected on a stale read.
    Recovery: a background wait; a re-read. **Prevention:** already harness-enforced.

## Tags
category: logic-errors
module: .github/actions/dispatch-web-redeploy
