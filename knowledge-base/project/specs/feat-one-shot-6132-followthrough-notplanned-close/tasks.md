# Tasks — fix #6132 follow-through monitor timeout close (not-planned)

Plan: `knowledge-base/project/plans/2026-07-07-fix-followthrough-monitor-timeout-close-not-planned-plan.md`
Lane: single-domain

## Phase 1 — Rewrite Guard C prompt (RED first)

- [ ] 1.1 Add `T9 — Guard C not-planned close semantics (#6132)` describe block
      to `apps/web-platform/test/server/inngest/cron-follow-through-monitor.test.ts`
      asserting: Guard C region has `--reason "not planned"` + `--remove-label
      "needs-attention"` + no `--add-label`; Guard A region has bare
      `gh issue close <number>` + no `not planned`. (RED — fails pre-fix.)
- [ ] 1.2 Export `FOLLOW_THROUGH_PROMPT` from
      `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`
      (test-parity export, matches existing exported constants).
- [ ] 1.3 Rewrite Guard C block: remove `--add-label` step; comment FIRST;
      conditional `--remove-label "needs-attention"` BEFORE close; close with
      `--reason "not planned"`; keep idempotency guard + extend torn-write
      recovery to strip residual `needs-attention`. (GREEN.)
- [ ] 1.4 Add inline comment near Guard A clarifying its bare close is
      intentionally COMPLETED (predicate-pass path). Update the `## Sharp Edges`
      close-clarifier line in the prompt.

## Phase 2 — Verify allowlist (no change)

- [ ] 2.1 Confirm `CLAUDE_CODE_FLAGS --allowedTools` already has
      `Bash(gh issue close:*)` + `Bash(gh issue edit:*)`; assert no diff to that
      line vs `main`. Record verified no-op.

## Phase 3 — Verify

- [ ] 3.1 `cd apps/web-platform && ./node_modules/.bin/vitest run
      test/server/inngest/cron-follow-through-monitor.test.ts` green (T1–T9).
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 3.3 AC greps (AC1–AC4) pass on the edited file.

## Phase 4 — Ship

- [ ] 4.1 PR body: `Closes #6132` + correct the "not in this repo / bot service"
      framing (monitor is the in-repo Inngest cron; fix lands here).
- [ ] 4.2 Post-merge (operator/automatable): run AC8 discoverability `gh` query
      after next fire — expect zero COMPLETED+needs-attention follow-throughs.
