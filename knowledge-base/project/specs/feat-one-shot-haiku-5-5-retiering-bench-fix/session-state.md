# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-09-chore-haiku-5-5-retiering-verdicts-and-bench-self-test-plan.md
- Status: complete

### Errors
None blocking. The brief's "51/1 on origin/main" does not reproduce on current main (177/0); it reproduces only on a pre-#9753 copy of learning-retrieval-bench.sh. Planning made small live Anthropic calls with the soleur-ci-eval key (about $0.06 in total) to measure the CLI internal model.

### Decisions
- Bench: root cause is the #8394 reader change against a mock curl that printed no block type; #9753 fixed it incidentally. Stage 2 is live (kb-search contract), so it is not retired. Add a wrapper suite and fix two caller-environment leaks; file no tracking issue.
- #9790: a pre-registered spend gate decides each class before any eval arm exists. The four crons cost about $1.6 to $9 a month, claude-code-review.yml has been disabled since 2026-02-12, and the seven standard pins are unmetered, so no class qualifies and nothing moves; PIN_ALLOWLIST is untouched.
- Design questions: CLI 2.1.293 internal calls (haiku alias, WebFetch summarizer) report claude-haiku-5-5; leader effort and refusal retry get recorded dispositions with triggers; add a haiku-no-text-block-rate Sentry alert in Terraform.
- Closes #9790 only if AC1 to AC7 are all delivered in the PR; otherwise Ref.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, cto, cfo, dhh/kieran/code-simplicity reviewers.
