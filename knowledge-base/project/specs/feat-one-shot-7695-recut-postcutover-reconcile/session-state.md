# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-18-chore-inngest-recut-postcutover-reconcile-plan.md
- Status: complete
- Plan artifact: complete (selector=subagent-summary)

### Errors
- Non-fatal: first `gh issue create` for the deferral issue refused by the filing hook (no `Mandated-By:`); retried OK as #8316.
- Non-fatal: CTO domain-review claimed `article-30-register.md` is outside PR 8248's file set — re-measured false (it is in the 54-path set); plan records the correction, file not edited.
- Playwright MCP failed to connect (unused in this phase).

### Decisions
- Live state measured: newest dedicated probe row `cutover_flag=done flush_latched=true redis_keys=1081 probe_schema=8 data_mount_devid=scsi-0HC_Volume_106261946 registry_fns=70`; Doppler `INNGEST_CUTOVER_FLIP=done`, `INNGEST_DIAGNOSTIC_BOOT=0`; volume 106261946 attached to host 166317708 (created 2026-09-17).
- Recut target documented as DORMANT on this volume (G19 alone unreachable on `done`; G8/G9/G13 refuse independently; standing latch defers store-emptying to #7777). Retirement deferred to #8316, gated on PR 8248.
- Closes #7695, #8017, #8015. #8078 stays open re-graded p1→p3; #7777 re-scoped; #8018 unchanged.
- Edits kept disjoint from PR 8248: runbook G3.7 post-cutover callout, ADR-100 addendum, addendum on the 2026-09-02 plan, archive both `issue: 7695` plan/spec pairs. No code, no cloud-init, no gate edits, no dispatch.
- Plan-review: exit-5 follow-through probe adopted then cut; cross-link comment on PR 8248 instead. Two DHH findings recorded in decision-challenges.md, not applied.

### Components Invoked
- Skills: soleur:plan, soleur:plan-review, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, git-history-analyzer, functional-discovery, cto, spec-flow-analyzer, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, Explore, observability-coverage-reviewer, code-quality-analyst
- Commands: betterstack-query.sh, doppler secrets get, Hetzner API curl, inngest-host-not-serving-7674.sh (PASS), gh issue/pr, archive-kb.sh --dry-run ×4, lint-infra-no-human-steps.py
