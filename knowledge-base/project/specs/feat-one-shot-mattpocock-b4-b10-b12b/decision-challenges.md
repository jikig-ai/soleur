# Decision challenges: feat-one-shot-mattpocock-b4-b10-b12b

Taste-class suggestions that surfaced during headless planning. They were not applied, and they are
recorded here so `ship` can surface them.

## T1: offer to park the rest after about 5 questions (CPO, taste)

- **Suggestion:** after about 5 brainstorm questions, offer the founder a "park the rest?" option.
- **Why it was not applied:** it uses one of `AskUserQuestion`'s 4 option slots on every question
  past the threshold, and a fixed threshold is a product-taste call. An early "proceed" already parks
  everything that remains.

## T2: label the help-map rows by goal (CPO, taste)

- **Suggestion:** label each help-map path by the founder's goal ("have an idea -> go") instead of
  by skill names.
- **Why it was not applied:** the help output already opens with "Start here: go <what you want>",
  and goal labels would widen a map the invocation asked to keep compact.

## T3: show the count of open decisions with each question (CPO, taste)

- **Suggestion:** with each brainstorm question, tell the founder how many open decisions remain.
- **Why it was not applied:** it was applied at the domain review, then cut in plan review. DHH
  and code-simplicity found that it serves no property in the plan's list, and that it can
  mislead, because answers open new branches.

## U1: a repo-level null-guardrail finding (audit null case, user-challenge)

- **Suggestion:** the audit's B10 row calls "no pre-commit hook and no CI job runs the check
  command" a finding in itself, even when the session had no errors.
- **Why it was not applied:** plan review cut it. DHH said it is a repo linter, not a
  retrospective. The CTO said it repeats on every run in a repo with no CI by choice.
- **What remains:** the null-guardrail check for each recurring failure class, which is the
  operator's own wording ("for the failure class").
- **Revisit when:** the founder wants compound to also audit the repo's safety net as a whole.

## T4: fold the null-guardrail check into Phase 0.5 triage instead (code-simplicity, taste)

- **Suggestion:** add one clause to compound's recurring-vs-one-off triage rather than a new
  Phase 1.5 step.
- **Why it was not applied:** the operator named the Deviation Analyst, Phase 1.5, as the home.

## T5: a single shared help-map section, or a durable parity test (code-simplicity / CTO, taste)

- **Suggestion:** use one map section rendered into every harness block, or extend
  `components.test.ts` to assert that the three copies stay byte-identical and that every listed
  skill exists. Also add a note on who maintains the map.
- **Why it was not applied:** the harness blocks are literal output templates. The plan keeps
  three copies with a work-time parity AC and adds no new test infrastructure.
