# Decision challenges — feat-ci-mattpocock-skills-audit

These are Taste findings from `soleur:plan-review` (named panel) on
`knowledge-base/project/plans/2026-09-23-docs-mattpocock-skills-audit-record-reconcile-plan.md`.
The pipeline was headless, so none of them was auto-applied. `ship` Phase 6 renders them. The founder
decides each one. Where a line gives a default, that default is what the plan does unless the founder
chooses otherwise.

## T1 — Key Takeaway 4: say what the audit produced (CPO, taste)

- **Proposal:** Rewrite KT4's past-tense evidence to lead with the result: one peer audit became five
  bundles, shipped in four days (2026-09-19 to 2026-09-22). That shows the value of a peer audit.
- **Plan default:** KT4 keeps its original insight, puts the evidence in the past tense, and cites the
  closing issues.
- **Founder decision 2026-09-23:** plan default kept (past-tense KT4). No change.

## T2 — Name `#8505` as the next Phase 4 security item in the PR body (CPO, taste)

- **Proposal:** The triage section should call `#8505` the priority deferral. The shared prod/CI key
  already ran out once, and `#8497` is blocked on it. It should not read as one deferral among five.
- **Plan default:** All five verdicts are shown with equal weight. The blocked-by edge is the only
  thing that marks `#8505` as a priority.
- **Founder decision 2026-09-23:** moot. `#8505` shipped and closed 2026-09-23 via PR `#8618`.

## T3 — Status text for B4 / B10, with a revisit trigger (CPO, taste)

- **Proposal:** "Not bundled by the founder (2026-09-18). Revisit if an upstream re-audit shows
  drift, or if a brainstorm or compound failure points to it."
- **Plan default:** "not bundled — remains advisory", with no revisit trigger. The plan no longer
  calls these "explicit declines": that contradiction was corrected as a mechanical fix.
- **Founder decision 2026-09-23:** both options superseded. B4, B10 and B12's second half were
  bundled and shipped in PR `#8647` (merged 2026-09-24, `e5a725a5e1`).

## T4 — Wording of the §2 `setup-pre-commit` reject verdict (CMO, taste)

- **Proposal:** "**Reject — already covered by the hooks listed above.**" This removes the remaining
  comparison.
- **Plan default:** "**Reject — Soleur's hooks fleet already covers this in more depth.**"
- **Founder decision 2026-09-23:** proposal adopted ("Reject — already covered by the hooks
  listed above.").

## T5 — Star-count wording without "unusually high for the repo's age" (CMO, taste)

> **Resolved at review 2026-09-23:** a security-review finding (the hedged wording still read as doubt about a named third party's repo) was routed to the CLO, which replaced all four star/newsletter passages with dated GitHub-API snapshot wording. Both the plan default and this proposal are superseded; nothing to decide.

- **Proposal:** "gh-reported, not independently verified; context only — do not cite downstream;
  confirm against a second source before it informs a decision." The two dates already imply the rest.
- **Plan default:** The CLO wording, which keeps the "unusually high for the repo's age" clause.
