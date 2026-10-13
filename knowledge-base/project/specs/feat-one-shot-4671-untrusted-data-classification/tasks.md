# Tasks: feat-one-shot-4671-untrusted-data-classification

Plan: knowledge-base/project/plans/2026-10-13-feat-runtime-untrusted-data-classification-plan.md

## Phase 0 - Spike
- [x] 0.1 Capture WebFetch PostToolUse input shapes (string/object/blocks, error responses); record in plan Research Insights
- [ ] 0.2 (unverified: subagent hook coverage; recorded as not covered in ADR-287) Check hook fires for Task subagents; check additionalContext coexists with updatedToolOutput
- [x] 0.3 Check whether updatedToolOutput is honored for built-in WebFetch; decide whether wrap flag/code exists
- [x] 0.4 Run bun on a trivial script importing `@/`-aliased code to settle alias resolution

## Phase 1 - RED first
- [x] 1.1 Author corpus fixtures (>=150; frozen holdout in its own earlier commit; hard negatives; summary-shaped)
- [x] 1.2 Write eval test + Guard Contract mutation rows + wiring test + unit tests (all failing)

## Phase 2 - Shared module
- [x] 2.1 server/untrusted-content.ts: classify, envelope, UntrustedSource, extractWebFetchText
- [x] 2.2 createUntrustedContentHook with fail-open, truncation annotation, telemetry (no content)
- [x] 2.3 scripts/untrusted-content-eval.ts prints EVAL PASS

## Phase 3 - Migrate envelopes
- [x] 3.1 email-triage-tools.ts, inbox-tools.ts, crm/crm-tools.ts onto shared envelope, wording byte-stable
- [x] 3.2 Sweep sentinel + preamble-table completeness test

## Phase 4 - Hook wiring and flags
- [ ] 4.1 (operator: typed-yes create.sh --flagsmith-only; code wiring and env mirror done) soleur:flag-create: untrusted-content-classify (and untrusted-content-wrap only if Phase 0 positive); FLAG_* env mirror in .env.example
- [x] 4.2 Flag helpers in lib/feature-flags/server.ts; resolve with real identity in cc-dispatcher.ts; new enableUntrustedContentClassify arg
- [x] 4.3 Register PostToolUse WebFetch matcher in agent-runner-query-options.ts

## Phase 5 - Records and follow-ups
- [x] 5.1 ADR-287 via soleur:architecture (measured numbers, limits, output-rewriter rule); read all three .c4 files for C4 conclusion
- [x] 5.2 File P1 remaining-surfaces issue, taint (blocked-by #4672), LLM-tier, wrap-enable soak tracker with followthrough directive; link from #4671
- [x] 5.3 Roadmap CP1 row text via soleur:product-roadmap
- [ ] 5.4 (tests, tsc, lint-guard-contract green; PR body pending at ship) Run npx vitest run (listed files), tsc, lint-guard-contract; PR body `Ref #4671`; PR stays draft
