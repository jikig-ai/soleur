# Weakness Digest

_Read-only recurring-failure signal from learnings added in the last 7d (#6037).
Triage clusters into `/compound`; this file never edits the harness._

Learnings in window: 68

## Recurring failure patterns

_Clusters of learnings sharing >= 2 tags, ranked by size (>= 3 members)._

### fail-open + mutation-testing — 9 learnings
- 2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md
- 2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md
- 2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md
- 2026-07-20-my-fix-for-a-crash-class-reintroduced-the-crash-class-three-times.md
- 2026-07-20-the-lint-i-wrote-to-catch-a-fail-open-shipped-the-same-fail-open.md
- 2026-07-21-a-gates-own-documentation-satisfied-the-gates-test.md
- 2026-07-22-widening-a-lint-repo-wide-shipped-three-fail-opens-my-green-suite-missed.md
- 2026-07-23-live-api-fail-closed-guard-counts-degraded-200-as-empty-and-control-probe-must-cover-every-scheme.md
- 2026-07-25-a-stale-presence-guard-fails-green-and-an-unknown-model-id-halves-max-tokens.md

### mutation-testing + vacuous-test — 5 learnings
- 2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md
- 2026-07-19-an-allowlist-widening-verified-against-the-string-not-the-credential.md
- 2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md
- 2026-07-20-the-fix-for-a-green-with-no-artifact-bug-shipped-green-with-no-artifact.md
- 2026-07-25-a-stale-presence-guard-fails-green-and-an-unknown-model-id-halves-max-tokens.md

### mutation-testing + vacuous-tests — 5 learnings
- 2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md
- 2026-07-20-a-red-test-got-more-dangerous-while-the-suite-pass-count-improved.md
- 2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md
- 2026-07-21-a-gates-own-documentation-satisfied-the-gates-test.md
- 2026-07-21-my-fixture-set-had-a-direction-and-both-batteries-were-blind-to-the-other-one.md

### luks + mutation-testing — 4 learnings
- 2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md
- 2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md
- 2026-07-20-a-red-test-got-more-dangerous-while-the-suite-pass-count-improved.md
- 2026-07-20-every-property-i-asserted-instead-of-measuring-was-wrong.md

### ci + mutation-testing — 3 learnings
- 2026-07-19-an-allowlist-widening-verified-against-the-string-not-the-credential.md
- 2026-07-20-adding-a-second-copy-of-a-guarded-literal-disarms-the-first.md
- 2026-07-23-ci-guard-test-must-assert-enforcement-not-just-presence.md

### mutation-testing + observability — 3 learnings
- 2026-07-19-a-mutation-battery-that-passes-can-still-leave-the-central-mechanism-untestable.md
- 2026-07-20-the-fix-for-a-green-with-no-artifact-bug-shipped-green-with-no-artifact.md
- 2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md

### fail-open + vacuous-test — 3 learnings
- 2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md
- 2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md
- 2026-07-25-a-stale-presence-guard-fails-green-and-an-unknown-model-id-halves-max-tokens.md

### mutation-testing + vacuity — 3 learnings
- 2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md
- 2026-07-20-i-fixed-three-unfailable-gates-and-shipped-eight-more.md
- 2026-07-23-ci-guard-test-must-assert-enforcement-not-just-presence.md

