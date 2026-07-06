# Decision Challenges — feat-one-shot-roadmap-review-dedup-output-contract

Recorded during plan + plan-review (headless). Surfaced by /ship into the PR body + an
`action-required` issue for operator visibility.

## 1. Cross-midnight title-date pin: proposed by DHH, then deferred cohort-wide by precedent-diff

- **Class:** user-challenge → resolved to defer (precedent-diff reversal).
- **Source:** DHH plan-review #2, then deepen-plan Phase 4.4 precedent-diff gate.
- **Brief said:** remove the prompt 6-day DEDUP RULE, adjust `## Output`, update tests.
- **DHH found:** the code-level same-date dedup can skew across a UTC-midnight boundary because the
  dedup key is `runStartedAt.slice(0,10)` (host UTC) while the digest title date is agent-derived
  (container clock); DHH proposed pinning the date by injecting `runStartedAt` into the prompt.
- **Precedent-diff found (decisive):** all 7 always-create cohort crons use a static prompt const
  + agent-derived title date; the 5 without a DEDUP RULE (content-generator, growth-audit,
  growth-execution, competitive-analysis, seo-aeo-audit) run this way with NO backstop and that is
  the canonical accepted pattern (#5786: "a duplicate paper-cut beats a missed digest"). The skew
  is a cohort-wide pre-existing property, not created by this PR. Pinning roadmap alone would make
  it a snowflake diverging from 6 siblings.
- **Decision:** KEEP the narrow fix (remove DEDUP RULE only, prompt stays a static const). DEFER
  the date-pin as a **cohort-wide** follow-up (tracking issue) alongside the community-monitor
  deferral. Removing roadmap's DEDUP RULE introduces no risk beyond the accepted cohort baseline.
- **If the operator wants the pin now:** it should be applied to all 7 cohort prompts in one
  change (shared prompt-builder), not roadmap-only — that is the non-snowflake path.
