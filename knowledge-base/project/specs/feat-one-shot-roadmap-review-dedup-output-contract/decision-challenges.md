# Decision Challenges — feat-one-shot-roadmap-review-dedup-output-contract

Recorded during plan + plan-review (headless). Surfaced by /ship into the PR body + an
`action-required` issue for operator visibility.

## 1. Fix scope extended beyond the literal brief: pin the digest title date

- **Class:** user-challenge (reviewer proposed completing the brief's own stated contract).
- **Source:** DHH plan-review finding #2 (corroborated against source).
- **Brief said:** remove the prompt 6-day DEDUP RULE, adjust `## Output`, update tests.
- **Reviewer found:** the brief's net contract ("same-day manual+cron duplicates handled
  code-side") has a cross-midnight-UTC hole — the code-level dedup key is `runStartedAt.slice(0,10)`
  (host UTC) but the digest title date is agent-derived (container clock), and the deleted 6-day
  rolling rule was the date-source-agnostic backstop that masked the skew.
- **Decision (folded in):** convert `ROADMAP_REVIEW_PROMPT` to a builder that interpolates
  `runStartedAt.slice(0,10)` and make the title date exact/mandatory. This is in-scope completion
  of the brief's own contract (not new scope), cheap, and tightly coupled to the removed backstop.
- **If the operator disagrees:** the date-pin can be dropped to a follow-up issue, leaving the
  cross-midnight duplicate/suppression risk as a known (rare) gap. Recommend keeping it in this PR.
