# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-24-feat-harness-parity-census-agent-bodies-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- Issue-filing gate blocked the phantom-agent issue (missing User-Impact/Fix-Size); fix was folded into this plan instead. Agent-description budget filed as #8692.
- #8317's "35 sites" was stale; real figure is 287 in agent files (+2 in the one reference doc).
- Observability probe switched from `bun` to `grep` (preflight sandbox PATH has no bun).

### Decisions
- New region policy `"agent"` plus a `SELF-NAME` verdict: the first `^name:` line must equal the filename stem; exactly one self-name per agent doc is asserted.
- #8622 NOT folded: same module, different path (fixDoc/quote exemption vs membership/classification); its AC needs the contested exemption design and an ADR-226 §3 amendment. Comment on #8622 during work.
- Phantom agent `agents/operations/references/service-deep-links.md` inlined into `service-automator.md` and deleted; public count 68 → 67 across READMEs, nfr-register, grok-onboarding.
- Remediation: ~35 sites via `--fix`, 185 bare leaves via a throwaway script in one reviewed commit; Grok stub descriptions render registry ids as spawn stems.
- model.c4 65 → 67 with new c4-count-parity row C8; ADR-226 dated amendment; agent authoring checklist switched to registry ids.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; repo-research-analyst, learnings-researcher, functional-discovery, cto (x2), cpo, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, test-design-reviewer

## Work Phase
- Status: complete at d891a323ad
- Verification: `bun test plugins/soleur` 3636 pass / 0 fail; all 123 plugins/soleur/test/*.test.sh + eval-gate + lint-agents-enforcement-tags rc 0; web-platform c4 vitest 24/24; census 0 non-canonical, 67 self-name; unknown-ns diff empty; AC2 mutations G1 rows 1/3/4 and G2 row 10 observed RED and reverted.
- The test-all bun/scripts shards were queued behind sibling worktrees for 20+ minutes and were cancelled; the full battery runs at ship Phase 4 and in CI's required `test` context.
- Plan corrections: AC4's literal anchor `^### Cloudflare` collides with the pre-existing `### Cloudflare (MCP Tier)` heading (content diff verified from the Service Deep Links section instead); the phantom service-deep-links file never rendered as a docs card (`references` was not in `subOrder`); discovered the docs page also omitted engineering/discovery (65 shown vs 67), fixed with docs-agents-data.test.ts.
- Operator-typed sites canonicalized by --fix: cto.md:28 and architecture-strategist.md:38 (`soleur:architecture`), deployment-verification-agent.md:108 (`soleur:schedule --once`), clo.md:68 (`soleur:go`), ux-design-lead.md:11 (`soleur:pencil-setup`).
- Issue comments posted: #8622, #8063, #8409, #8410.
