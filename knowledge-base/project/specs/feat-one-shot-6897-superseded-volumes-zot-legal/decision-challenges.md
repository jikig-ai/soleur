# Decision Challenges — #6897 ledger re-home + legal reconcile

Headless one-shot: taste / user-challenge decisions surfaced by the plan-review panel
(architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer). Recorded here for the
operator; `ship` renders these into the PR body + files an `action-required` issue. The plan's
default direction is retained (operator's stated direction is the default).

## UC-1 (User-Challenge) — Must #6897 close at all, or stay open as the umbrella bound?

**Challenge (code-simplicity-reviewer):** the minimal-correct answer might be **0 new issues** —
leave #6897 OPEN as the residual-teardown bound, since it already bounds all 8 exceptions. Closing
it is what forces the re-home + new-issue cost.

**RESOLVED (operator, 2026-07-24): KEEP #6897 OPEN — 0 new issues, net-issue-flow = 0.** When the plan
surfaced that closing #6897 orphans the exceptions and grows the backlog +2 (opposite of "draining"),
the operator chose to keep #6897 as the umbrella homing these *ongoing* bounded exceptions (they are
not one-time fixes). Phase 1 (tracker creation) and Phase 2 re-homing are CUT; the ledger/C4 `#6897`
refs stay. The PR is `Ref #6897` (not Closes) + the legal reconciliation + a read-only ledger
verification. This supersedes the task's original "`Closes #6897`" framing.

## UC-2 (Taste) — Issue count — MOOT (superseded by UC-1 resolution)

The 3-vs-4-vs-parents question is moot: **0 issues are filed** (UC-1 resolved to keep #6897 open). No
teardown/posture/zot trackers are created; #6897 continues to bound all residual exceptions.

## Note — plan-time sign-off is CLO, not CPO (fixed contradiction)

The threshold is `single-user incident` (legal-claim-vs-reality axis, the #6588 blast radius), but
Product = NONE (zero UI). The plan-time domain sign-off is therefore **CLO** (legal), not CPO
(product); `user-impact-reviewer` runs at review time per the threshold. The original
`requires_cpo_signoff: true` frontmatter contradicted Product=NONE and was corrected.
