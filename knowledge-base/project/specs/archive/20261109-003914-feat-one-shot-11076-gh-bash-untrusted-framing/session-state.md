# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-08-feat-gh-bash-untrusted-framing-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking. Phase 0.7 skeleton checkpoint skipped; two follow-up trackers recommended by the CTO were not filed (brief forbids issue creation).

### Decisions
- SDK Bash result shape is {stdout, stderr, interrupted, persistedOutputPath?}; hook returns {} on any other shape. No cc-dispatcher edit planned.
- CTO rulings recorded: note on any output size; quote-aware linear tokenizer with bounded 64 KiB fallback; closed verb table pinned to the safe-bash set; distinct log op untrusted-gh-frame with closed field set; gh-token-without-web-egress sessions out of slice and stated as ADR limit.
- Three Guard Contract entries (hook census + single-rewriter sweep, Playwright absence pin, safe-bash verb-table pin); new suite listed in repo-wide-suites.ts.
- ADR-287 gets an append-only second addendum plus one C4 hook-list sentence.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents: learnings-researcher, cto, cpo, dhh/kieran/simplicity/architecture/spec-flow reviewers, security-sentinel, observability-coverage-reviewer, test-design-reviewer, user-impact-reviewer.

## Operator Constraints

- constraint: Never work, reference, read or close the egress-audit enablement issue. Its number must never appear in a diff line, PR body, commit or comment. Run both restricted-token greps before every push.
- constraint: Operator holds, never done by the agent: creating or flipping any flag or environment, production writes needing approval, migrations or psql against prd, editing an applied migration, legal wording sign-off, public security claims ahead of a measured control, reading or flipping AGENT_OUTER_WRAP live value.
- constraint: Do not edit the epic body. File no issue. Do not touch 10613. Never edit dsar-export-allowlist.ts.
- constraint: Record in the PR test plan that the slow local affected battery was not awaited because CI is the ship gate.
- constraint: PR body avoids the words soak, stays 0, post-deploy verify. Ref only. Include a Changelog section and a Brand-survival threshold bullet. Write the ci_cycles tally after the final push. Edit the PR body in its own call.
- constraint: Retitle the WIP draft with a fix or chore prefix before gh pr ready. After every push or sync post a NEW Review-Evidence comment whose head equals the current PR head.
- constraint: Merge with session-state.sh with_lock merge-main 600 and gh pr merge squash auto, single call. Never sync an armed or queued PR. Use a read-only watcher, not the Phase 7 poll.
- constraint: After merge run deploy-arm.sh find wait and served from a detached origin main worktree with the full sha, then postmerge. Emit DONE only after merge and postmerge with pipeline-tally show.
- ci-is-the-gate: Record in the PR test plan that the slow local affected battery was not awaited because CI is the ship gate.
- cto_spawns=1 (one-shot batched ruling for six planner-resolved rows; planning subagent spawns tracked in its own run)
- cto_spawns=2 (second: batched ruling on six review findings; rows 24-29 in decision-challenges.md)

## Review Phase (PANEL_SHA 2bda41f85b, tier single-user incident, 12 seats + coverage consult)

structural-cause roll-up: (1) the fallback scan's grammar was narrower than the tokenizer's (separators, even quote parity); (2) the ADR's statement of the hook's reach and uncovered channels was incomplete. dedup: about 60 raw items -> 20 unique.

| raw finding | canonical defect key | reporting seat(s) | planned fix commit |
|---|---|---|---|
| fallback tokens split on whitespace only; separator-glued gh missed | fallback-scan-separator-grammar | history, security, architecture, code-quality | review: fix 1 |
| even-parity comment/heredoc apostrophes hide a gh read | tokenizer-quote-parity-desync | security | review: fix 1 |
| predicate registers only where gh is auth-denied | reach-narrower-than-hazard (operator scope, row 30) | agent-native, architecture, structural | ADR + plan wording (review: fix 1) |
| note gated on a typings-only response shape | response-shape-gate | security | review: fix 1 |
| third hand-rolled shell lexer | tokenizer-reuse (ruled keep, row 26) | pattern | ADR follow-up |
| no subagent field | subagent-observability (ruled leave out, row 27) | pattern, history | ADR follow-up |
| error mirror without cause | catch-cause | pattern | review: fix 1 |
| rollback latency claim wrong | adr-rollback-latency | user-impact | review: fix 1 |
| backslash-newline treated as whitespace | line-continuation | code-quality | review: fix 1 |
| alias ls, -R between noun and verb, unlisted nouns | verb-table-extras (row 29) | structural, security, code-quality | review: fix 1 |
| surviving mutants and slack floors, Guard 3 grid, pin legs | test-fixture-gaps | test-design, security, code-quality | review: fix 1 |
| naming, comment, plan wording, runbook entry, ADR departure | docs-and-nits | pattern, code-quality, history, data-integrity | review: fix 1 |
| per-call note may cause under-action; PostToolUseFailure routine non-zero | accepted-and-documented | user-impact, agent-native | ADR items 2 and 4 |
