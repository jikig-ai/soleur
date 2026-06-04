---
title: "docs: document cron-bug-fixer manual-trigger event + override semantics"
status: pending
lane: single-domain
---

# Tasks: cron-bug-fixer runbook documentation

## Phase 1: Add cron bug-fixer section to inngest-server.md

- [ ] 1.1 Read `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- [ ] 1.2 Add Quick Reference table row: `| Cron bug-fixer manual trigger | [link] |`
- [ ] 1.3 Insert `## Cron bug-fixer` section between `## Concurrency conventions` and `## Plan deviations`
  - [ ] 1.3.1 Document event name: `cron/bug-fixer.manual-trigger`
  - [ ] 1.3.2 Document payload shape: `{ "issue_number": <positive integer> }` (optional)
  - [ ] 1.3.3 Document validation rules (positive integer, rejection with Sentry fallback)
  - [ ] 1.3.4 Document override semantics (bypasses cascade, operator owns compatibility)
  - [ ] 1.3.5 Document concurrency (fn limit 1 + account `cron-platform` limit 1, queuing)
  - [ ] 1.3.6 Document how to fire (`inngest send` CLI + dashboard)
  - [ ] 1.3.7 Document how to observe (Sentry `scheduled-bug-fixer`, `bot-fix/*` PRs, dashboard)
  - [ ] 1.3.8 Document common failure modes (override rejection, empty cascade, timeout, workspace failure, no PR detected, auto-merge gate rejection)

## Phase 2: Verification

- [ ] 2.1 Verify section heading: `grep -c '## Cron bug-fixer' knowledge-base/engineering/operations/runbooks/inngest-server.md` returns 1
- [ ] 2.2 Verify no SSH: `grep -c 'ssh ' <new-section>` returns 0
- [ ] 2.3 Verify event name present: `grep -c 'cron/bug-fixer.manual-trigger' knowledge-base/engineering/operations/runbooks/inngest-server.md` >= 1
