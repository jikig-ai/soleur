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
