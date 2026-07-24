# Decision Challenges — #6897 ledger re-home + legal reconcile

Headless one-shot: taste / user-challenge decisions surfaced by the plan-review panel
(architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer). Recorded here for the
operator; `ship` renders these into the PR body + files an `action-required` issue. The plan's
default direction is retained (operator's stated direction is the default).

## UC-1 (User-Challenge) — Must #6897 close at all, or stay open as the umbrella bound?

**Challenge (code-simplicity-reviewer):** the minimal-correct answer might be **0 new issues** —
leave #6897 OPEN as the residual-teardown bound, since it already bounds all 8 exceptions. Closing
it is what forces the re-home + new-issue cost.

**Operator's stated direction (default, retained):** the task explicitly instructs
*"Close #6897 … Deliverable: reviewed, merged PR that `Closes #6897`."* So #6897 closes; the plan
sources the close to that directive (previously it asserted the convention without a source — now
fixed). If the operator prefers to keep #6897 open as the umbrella and skip the new issues, that is
a one-line change to the plan (drop Phase 1, keep #6897's `tracking_issue` references as-is).

## UC-2 (Taste) — Issue count: 3 consolidated (B, adopted) vs 4 per-item (A) vs re-point-to-parents (C)

**Adopted default = Option B (3 new issues):** teardown (workspaces+git_data, same remediation
class), Layer-B posture (session-store + git-data host), zot. Panel consensus: B is minimal-correct;
C is unsafe (re-pointing narrow triggers at broad parents #6893/#6588 lets the parent close while a
child trigger is unresolved — the #6897 defect recurred); A (per-item, mirrors #6894/#6895) is
"acceptable but mildly over-built" for a non-technical operator (+1 standing P3 issue).

**Trade-off the operator may want to override:** A is more faithful to the existing per-volume
#6894/#6895 pattern and gives workspaces-detach vs git_data-DL-2-wipe their own 1:1 trackers. If
per-item granularity is preferred, split the teardown issue into two.

## Note — plan-time sign-off is CLO, not CPO (fixed contradiction)

The threshold is `single-user incident` (legal-claim-vs-reality axis, the #6588 blast radius), but
Product = NONE (zero UI). The plan-time domain sign-off is therefore **CLO** (legal), not CPO
(product); `user-impact-reviewer` runs at review time per the threshold. The original
`requires_cpo_signoff: true` frontmatter contradicted Product=NONE and was corrected.
